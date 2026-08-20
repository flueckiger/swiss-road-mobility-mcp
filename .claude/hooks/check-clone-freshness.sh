#!/usr/bin/env bash
#
# SessionStart-Hook: meldet, wie viele Commits der ausgecheckte Stand hinter
# origin/<default-branch> liegt. Schweigt, wenn nichts fehlt.
#
# GRUND: Ein veralteter Klon hat am 3.8.2026 zweimal eine rote CI erzeugt,
# deren Ursache nicht im Diff stand — die fehlenden Commits waren jeweils
# genau die, die das Gate einfuehrten, an dem der Branch scheiterte. Die
# Pruefung kostet eine Sekunde und ersetzt eine Fehlersuche in den falschen
# Dateien.
#
# OBERSTE REGEL: Dieser Hook blockiert die Session NIEMALS. Kein Netz, kein
# Remote, detached HEAD, flatterndes DNS, kaputtes git — jeder dieser Faelle
# geht still durch (exit 0, keine Ausgabe). Ein Hook, der bei Netzproblemen
# die Arbeit anhaelt, wird nach dem zweiten Mal abgeschaltet und schuetzt
# danach gar nichts. Getragen wird das von den `|| exit 0`-Absicherungen an
# jedem einzelnen Schritt (Gegenprobe G6 nimmt eine weg und zeigt, dass die
# Session dann mit rc=128 stehenbleibt). `set -e`/`set -o pipefail` fehlen
# zusaetzlich — gemessen aendern sie am Verhalten nichts, weil ohnehin jeder
# Schritt in einem getesteten Kontext steht; sie blieben nur weg, damit eine
# spaeter ergaenzte, ungesicherte Zeile nicht doch zum Abbruch wird.
#
# Details und Testmatrix: .claude/hooks/README.md

set -u

# Kein `trap ... ERR`. Gemessen (bash 5.2): Der Trap feuert auch ohne
# `set -e`, sobald ein NACKTES Kommando ungleich 0 endet — ein alleinstehendes
# `[ ... ]`, ein `grep` ohne Treffer. Ein `cmd && ...`-Verbund ist ausgenommen.
# Ein solcher Trap wuerde die Meldung unten also stumm mittendrin abbrechen,
# sobald jemand hier eine Zeile ergaenzt, die legitim nicht-null zurueckgibt.
# Stattdessen ist jeder Schritt einzeln mit `|| exit 0` abgesichert — das ist
# die Mechanik, die traegt (Gegenprobe G6).

REMOTE="${CLAUDE_FRESHNESS_REMOTE:-origin}"
# Sekunden pro Netzaufruf. Schlimmster Fall sind zwei Aufrufe
# (ls-remote + fetch), also das Doppelte.
NET_TIMEOUT="${CLAUDE_FRESHNESS_TIMEOUT:-4}"
# Wie viele der fehlenden Commit-Betreffs angezeigt werden.
MAX_SUBJECTS="${CLAUDE_FRESHNESS_MAX_SUBJECTS:-5}"

# --- Vorbedingungen, alle still ------------------------------------------

command -v git >/dev/null 2>&1 || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
# Unborn HEAD (frisch initialisiertes Repo ohne Commit): nichts zu vergleichen.
git rev-parse --verify --quiet HEAD >/dev/null 2>&1 || exit 0
# Kein solcher Remote -> nichts zu pruefen.
git remote get-url "$REMOTE" >/dev/null 2>&1 || exit 0

# --- Netzaufrufe hart begrenzen ------------------------------------------

# Niemals interaktiv nach Zugangsdaten oder Host-Keys fragen: ein wartender
# Prompt ist genau das Haengen, das dieser Hook vermeiden soll.
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes -oStrictHostKeyChecking=accept-new -oConnectTimeout=$NET_TIMEOUT}"
# Zweiter Guertel fuer den Fall, dass kein timeout(1) vorhanden ist: bricht
# HTTP-Transfers ab, die laenger als NET_TIMEOUT unter 1 Byte/s haengen.
export GIT_HTTP_LOW_SPEED_LIMIT="${GIT_HTTP_LOW_SPEED_LIMIT:-1}"
export GIT_HTTP_LOW_SPEED_TIME="${GIT_HTTP_LOW_SPEED_TIME:-$NET_TIMEOUT}"

if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"        # macOS mit coreutils
else
  TIMEOUT_BIN=""                # nur die GIT_HTTP_*-Bremse oben
fi

bounded() {
  if [ -n "$TIMEOUT_BIN" ]; then
    # -k: nach der Gnadenfrist SIGKILL, falls git SIGTERM ignoriert.
    "$TIMEOUT_BIN" -k 2 "$NET_TIMEOUT" "$@"
  else
    "$@"
  fi
}

# --- Default-Branch ermitteln, nicht raten --------------------------------
#
# Mindestens ein Repo im Portfolio nutzt "master"; genau die Annahme "main"
# hat schon einmal einen Branch 15 Commits alt werden lassen. Reihenfolge:
#
#   1. refs/remotes/<remote>/HEAD — lokal, kein Netz, von `git clone` gesetzt.
#      Falsch nur, wenn das Repo seinen Default-Branch nachtraeglich gewechselt
#      hat; dann schlaegt der fetch unten fehl und wir schweigen. Faellt also
#      sicher aus, statt Unsinn zu melden.
#   2. `git ls-remote --symref` — ein Netzaufruf, noetig bei --single-branch-
#      oder fetch-basierten Klonen, wo (1) nicht gesetzt ist.
#
# Gibt keiner der beiden etwas her, endet der Hook still. Ein hart
# verdrahtetes "main" waere hier der Fehler, den dieser Hook verhindern soll.

default_branch=""
symref="$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null)" || symref=""
if [ -n "$symref" ]; then
  default_branch="${symref#"$REMOTE"/}"
fi

if [ -z "$default_branch" ]; then
  default_branch="$(
    bounded git ls-remote --symref "$REMOTE" HEAD 2>/dev/null |
      sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p' |
      head -n 1
  )" || default_branch=""
fi

[ -n "$default_branch" ] || exit 0

# --- Stand holen ----------------------------------------------------------
#
# `git fetch <remote> <branch>` ohne Refspec schreibt nur FETCH_HEAD und
# bewegt keinen lokalen Ref — der Hook fasst den Arbeitsstand nicht an.

bounded git fetch --quiet "$REMOTE" "$default_branch" >/dev/null 2>&1 || exit 0
git rev-parse --verify --quiet FETCH_HEAD >/dev/null 2>&1 || exit 0

# Ohne gemeinsamen Vorfahren ist die Zaehlung wertlos: In einem flachen Klon
# (Claude Code on the web klont flach!), dessen Grenze den Vorfahren
# abschneidet, zaehlt HEAD..FETCH_HEAD die ganze geholte Historie und meldet
# eine erfundene Zahl. Lieber schweigen als falsch alarmieren. Ein flacher
# Klon MIT gemeinsamem Vorfahren zaehlt dagegen korrekt und wird hier bewusst
# nicht ausgeschlossen — sonst waere der Hook in der Web-Session wirkungslos.
git merge-base HEAD FETCH_HEAD >/dev/null 2>&1 || exit 0

behind="$(git rev-list --count HEAD..FETCH_HEAD 2>/dev/null)" || exit 0
case "$behind" in
  ''|*[!0-9]*) exit 0 ;;   # keine saubere Zahl -> nichts melden
esac

# Ausgabe nur, wenn tatsaechlich Commits fehlen.
[ "$behind" -gt 0 ] || exit 0

# --- Meldung --------------------------------------------------------------

commit_word="Commits"
if [ "$behind" -eq 1 ]; then
  commit_word="Commit"
fi

if head_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)" && [ -n "$head_branch" ]; then
  where="Branch '$head_branch'"
else
  where="Der ausgecheckte Stand (detached HEAD)"
fi

echo "VERALTETER KLON: $where liegt $behind $commit_word hinter $REMOTE/$default_branch."
echo
echo "Fehlende Commits (max. $MAX_SUBJECTS):"
# KEIN --no-merges: `git rev-list --count` oben zaehlt Merge-Commits mit. Wer
# sie hier herausfiltert, zeigt weniger Zeilen als die Ueberschrift nennt —
# gemessen am echten Repo: Kopf "6 Commits", darunter 3 Betreffs und
# "und 1 weitere". Liste und Zahl muessen dieselbe Menge meinen.
subjects="$(git log --format='  %h %s' -n "$MAX_SUBJECTS" HEAD..FETCH_HEAD 2>/dev/null)"
shown=0
if [ -n "$subjects" ]; then
  printf '%s\n' "$subjects"
  shown="$(printf '%s\n' "$subjects" | wc -l | tr -d ' ')"
fi
# Rest aus dem, was WIRKLICH gedruckt wurde — nicht aus MAX_SUBJECTS.
# Sonst stimmt die Rechnung nicht, sobald weniger Zeilen herauskommen.
case "$shown" in
  ''|*[!0-9]*) shown=0 ;;
esac
if [ "$behind" -gt "$shown" ]; then
  echo "  ... und $((behind - shown)) weitere"
fi
echo
echo "Vor der Arbeit einspielen, sonst droht eine rote CI, deren Ursache nicht"
echo "im Diff steht — fehlende Commits sind oft genau die, die ein neues Gate"
echo "einfuehren. Einspielen mit:"
# `git fetch <remote> <branch>` aktualisiert normalerweise auch
# refs/remotes/<remote>/<branch>. Bei einem Klon mit enger Refspec kann das
# ausbleiben; dann waere `git merge origin/<branch>` ein Rat ins Leere.
if git rev-parse --verify --quiet "refs/remotes/$REMOTE/$default_branch" >/dev/null 2>&1; then
  echo "  git merge $REMOTE/$default_branch     # oder: git rebase $REMOTE/$default_branch"
else
  echo "  git fetch $REMOTE $default_branch && git merge FETCH_HEAD"
fi

exit 0
