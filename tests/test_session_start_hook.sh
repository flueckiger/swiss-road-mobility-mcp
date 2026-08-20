#!/usr/bin/env bash
#
# Testmatrix fuer .claude/hooks/check-clone-freshness.sh
#
# Zwei Teile:
#   TEIL 1  15 Faelle gegen Wegwerf-Repos (file://-Remotes, plus ein echtes
#           Netz-Loch fuer den Timeout-Fall).
#   TEIL 2  Gegenprobe (CLAUDE.md, «Tests»): jede Zusicherung wird einzeln
#           neutralisiert; der Lauf muss zeigen, dass genau die zugehoerigen
#           Faelle fallen. Ein Test, der gruen bleibt, wenn man die
#           Implementierung entfernt, prueft nichts.
#
# Laeuft ausserhalb der CI-Gates: die decken src/ tests/ scripts/ mit ruff und
# pytest ab, und keines davon fasst eine .sh an. Manuell:
#   tests/test_session_start_hook.sh

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/check-clone-freshness.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
FAILED_NAMES=()

ok()   { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

# --- Werkzeug -------------------------------------------------------------

git_q() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

# upstream <name> <default-branch>  -> legt ein bare-Repo mit einem Commit an
upstream() {
  local name="$1" branch="$2" up="$WORK/$1.git" seed="$WORK/$1.seed"
  git init --quiet --bare --initial-branch="$branch" "$up"
  git init --quiet --initial-branch="$branch" "$seed"
  echo seed > "$seed/f.txt"
  git_q -C "$seed" add -A
  git_q -C "$seed" commit -m "commit 0"
  git_q -C "$seed" remote add origin "$up"
  git_q -C "$seed" push origin "$branch"
  # HEAD des bare-Repos auf den Default-Branch zeigen lassen, damit
  # ls-remote --symref etwas zu melden hat.
  git -C "$up" symbolic-ref HEAD "refs/heads/$branch"
  echo "$up"
}

# advance <upstream> <branch> <n>  -> schiebt n Commits auf den Upstream
# Globaler Zaehler: Zwei advance()-Aufrufe auf DEMSELBEN Upstream duerfen
# nicht dieselben Dateien mit demselben Inhalt schreiben — sonst hat
# `git commit` nichts zu stagen und der Aufruf schiebt still 0 Commits.
ADV_SEQ=0
advance() {
  local up="$1" branch="$2" n="$3" tmp="$WORK/adv.$$.$RANDOM"
  git clone --quiet "$up" "$tmp" 2>/dev/null
  git_q -C "$tmp" checkout "$branch"
  for i in $(seq 1 "$n"); do
    ADV_SEQ=$((ADV_SEQ + 1))
    echo "$ADV_SEQ" > "$tmp/new_$ADV_SEQ.txt"
    git_q -C "$tmp" add -A
    git_q -C "$tmp" commit -m "upstream commit $ADV_SEQ"
  done
  git_q -C "$tmp" push origin "$branch"
  rm -rf "$tmp"
}
# Absicherung des Fixtures selbst: advance() muss wirklich Commits erzeugen.
assert_advanced() {  # assert_advanced <klon> <erwartet>
  local got
  git -C "$1" fetch --quiet origin >/dev/null 2>&1
  got="$(git -C "$1" rev-list --count HEAD..FETCH_HEAD 2>/dev/null)"
  if [ "$got" != "$2" ]; then
    printf "  \033[33mWARN\033[0m  Fixture kaputt: erwartete %s neue Commits, Upstream hat %s\n" "$2" "$got"
  fi
}

# run_hook <dir> -> setzt OUT / RC / SECS
run_hook() {
  local dir="$1" start end
  start=$(date +%s)
  OUT="$(CLAUDE_PROJECT_DIR="$dir" "$HOOK" 2>/dev/null)"
  RC=$?
  end=$(date +%s)
  SECS=$((end - start))
}

# Jeder Fall prueft immer auch: Exit-Code 0. Der Hook darf nie blockieren.
expect_rc0() {
  [ "$RC" -eq 0 ] || bad "$1" "Exit-Code $RC statt 0 — der Hook darf NIE blockieren"
}

echo
echo "TEIL 1 — Verhalten"
echo "=================="

# 1 — aktueller Stand: schweigt
UP="$(upstream up1 main)"
git clone --quiet "$UP" "$WORK/c1"
run_hook "$WORK/c1"
expect_rc0 "01 aktuell"
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then ok "01 aktuell -> schweigt (0 Commits)"
else bad "01 aktuell -> schweigt (0 Commits)" "Ausgabe war: $OUT"; fi

# 2 — 3 Commits zurueck: meldet 3
UP="$(upstream up2 main)"
git clone --quiet "$UP" "$WORK/c2"
advance "$UP" main 3
run_hook "$WORK/c2"
expect_rc0 "02 drei zurueck"
if grep -q "3 Commits hinter origin/main" <<< "$OUT"; then ok "02 3 zurueck -> meldet '3 Commits hinter origin/main'"
else bad "02 3 zurueck -> meldet '3 Commits hinter origin/main'" "Ausgabe: $OUT"; fi

# 3 — genau 1 zurueck: Singular
UP="$(upstream up3 main)"
git clone --quiet "$UP" "$WORK/c3"
advance "$UP" main 1
run_hook "$WORK/c3"
if grep -q "1 Commit hinter" <<< "$OUT" && ! grep -q "1 Commits" <<< "$OUT"; then ok "03 1 zurueck -> Singular 'Commit'"
else bad "03 1 zurueck -> Singular 'Commit'" "Ausgabe: $OUT"; fi

# 4 — 12 zurueck: Deckel bei 5 Betreffs + Rest-Hinweis
UP="$(upstream up4 main)"
git clone --quiet "$UP" "$WORK/c4"
advance "$UP" main 12
run_hook "$WORK/c4"
n_subj=$(grep -cE '^  [0-9a-f]{7,} ' <<< "$OUT")
if grep -q "12 Commits hinter" <<< "$OUT" && [ "$n_subj" -eq 5 ] && grep -q "und 7 weitere" <<< "$OUT"; then
  ok "04 12 zurueck -> 5 Betreffs + 'und 7 weitere'"
else bad "04 12 zurueck -> 5 Betreffs + 'und 7 weitere'" "Betreffs=$n_subj; Ausgabe: $OUT"; fi

# 5 — Default-Branch heisst master, nicht main
UP="$(upstream up5 master)"
git clone --quiet "$UP" "$WORK/c5"
advance "$UP" master 2
run_hook "$WORK/c5"
expect_rc0 "05 master"
if grep -q "2 Commits hinter origin/master" <<< "$OUT"; then ok "05 Default-Branch 'master' -> erkannt, meldet origin/master"
else bad "05 Default-Branch 'master' -> erkannt, meldet origin/master" "Ausgabe: $OUT"; fi

# 6 — master UND origin/HEAD fehlt -> ls-remote-Fallback traegt
UP="$(upstream up6 master)"
git clone --quiet "$UP" "$WORK/c6"
git -C "$WORK/c6" update-ref -d refs/remotes/origin/HEAD 2>/dev/null
git -C "$WORK/c6" symbolic-ref -d refs/remotes/origin/HEAD 2>/dev/null
advance "$UP" master 4
run_hook "$WORK/c6"
if grep -q "4 Commits hinter origin/master" <<< "$OUT"; then ok "06 kein origin/HEAD -> ls-remote-Fallback findet 'master'"
else bad "06 kein origin/HEAD -> ls-remote-Fallback findet 'master'" "Ausgabe: $OUT"; fi

# 7 — detached HEAD: wird gemessen und gemeldet
UP="$(upstream up7 main)"
git clone --quiet "$UP" "$WORK/c7"
git_q -C "$WORK/c7" checkout --detach HEAD
advance "$UP" main 2
run_hook "$WORK/c7"
expect_rc0 "07 detached HEAD"
if grep -q "detached HEAD" <<< "$OUT" && grep -q "2 Commits hinter" <<< "$OUT"; then
  ok "07 detached HEAD -> meldet, blockiert nicht"
else bad "07 detached HEAD -> meldet, blockiert nicht" "Ausgabe: $OUT"; fi

# 8 — kein Remote: still
git init --quiet "$WORK/c8"
echo x > "$WORK/c8/f.txt"; git_q -C "$WORK/c8" add -A; git_q -C "$WORK/c8" commit -m x
run_hook "$WORK/c8"
expect_rc0 "08 kein Remote"
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then ok "08 kein Remote -> still, exit 0"
else bad "08 kein Remote -> still, exit 0" "Ausgabe: $OUT"; fi

# 9 — kein git-Repo: still
mkdir -p "$WORK/c9"
run_hook "$WORK/c9"
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then ok "09 kein git-Repo -> still, exit 0"
else bad "09 kein git-Repo -> still, exit 0" "rc=$RC Ausgabe: $OUT"; fi

# 10 — unborn HEAD (init ohne Commit): still
git init --quiet "$WORK/c10"
git_q -C "$WORK/c10" remote add origin "$WORK/up1.git"
run_hook "$WORK/c10"
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then ok "10 unborn HEAD -> still, exit 0"
else bad "10 unborn HEAD -> still, exit 0" "rc=$RC Ausgabe: $OUT"; fi

# 11 — kein gemeinsamer Vorfahr: lieber schweigen als erfinden
UP="$(upstream up11 main)"
git init --quiet --initial-branch=main "$WORK/c11"
echo unrelated > "$WORK/c11/z.txt"
git_q -C "$WORK/c11" add -A
git_q -C "$WORK/c11" commit -m "voellig andere Historie"
git_q -C "$WORK/c11" remote add origin "$UP"
run_hook "$WORK/c11"
expect_rc0 "11 kein merge-base"
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then ok "11 kein gemeinsamer Vorfahr -> still (keine erfundene Zahl)"
else bad "11 kein gemeinsamer Vorfahr -> still (keine erfundene Zahl)" "Ausgabe: $OUT"; fi

# 12 — flacher Klon MIT gemeinsamem Vorfahr: zaehlt trotzdem
#      (Claude Code on the web klont flach — hier muss der Hook wirken.)
UP="$(upstream up12 main)"
advance "$UP" main 5
git clone --quiet --depth 1 "file://$UP" "$WORK/c12"
advance "$UP" main 3
assert_advanced "$WORK/c12" 3
run_hook "$WORK/c12"
expect_rc0 "12 flacher Klon"
if grep -q "3 Commits hinter origin/main" <<< "$OUT"; then ok "12 flacher Klon (depth 1) -> zaehlt korrekt, wird nicht uebersprungen"
else bad "12 flacher Klon (depth 1) -> zaehlt korrekt, wird nicht uebersprungen" "Ausgabe: $OUT"; fi

# 13 — haengender Remote: Timeout greift, Session laeuft weiter
#      git://10.255.255.1 nimmt keine Verbindung an und antwortet nie.
UP="$(upstream up13 main)"
git clone --quiet "$UP" "$WORK/c13"
git_q -C "$WORK/c13" remote set-url origin git://10.255.255.1/x.git
advance "$UP" main 2
run_hook "$WORK/c13"
expect_rc0 "13 haengender Remote"
if [ -z "$OUT" ] && [ "$RC" -eq 0 ] && [ "$SECS" -le 10 ]; then
  ok "13 haengender Remote -> still nach ${SECS}s, exit 0 (Timeout greift)"
else bad "13 haengender Remote -> still, exit 0, <=10s" "rc=$RC secs=$SECS Ausgabe: $OUT"; fi

# 14 — Der Hook fasst den Arbeitsstand nicht an.
#      `git fetch <remote> <branch>` ohne Refspec schreibt nur FETCH_HEAD.
#      Ein Hook, der beim Sessionstart ungefragt mergt, waere ein Uebergriff.
UP="$(upstream up14 main)"
git clone --quiet "$UP" "$WORK/c14"
advance "$UP" main 3
assert_advanced "$WORK/c14" 3
head_before="$(git -C "$WORK/c14" rev-parse HEAD)"
branch_before="$(git -C "$WORK/c14" rev-parse refs/heads/main)"
status_before="$(git -C "$WORK/c14" status --porcelain)"
run_hook "$WORK/c14"
head_after="$(git -C "$WORK/c14" rev-parse HEAD)"
branch_after="$(git -C "$WORK/c14" rev-parse refs/heads/main)"
status_after="$(git -C "$WORK/c14" status --porcelain)"
expect_rc0 "14 read-only"
if [ "$head_before" = "$head_after" ] && [ "$branch_before" = "$branch_after" ] \
   && [ "$status_before" = "$status_after" ] && grep -q "3 Commits hinter" <<< "$OUT"; then
  ok "14 meldet, ohne HEAD/Branch/Arbeitsbaum zu bewegen"
else
  bad "14 meldet, ohne HEAD/Branch/Arbeitsbaum zu bewegen" \
      "HEAD $head_before -> $head_after; main $branch_before -> $branch_after"
fi

# 15 — Merge-Commits: Liste und Zahl muessen dieselbe Menge meinen.
#      Am echten Repo aufgefallen: mit --no-merges meldete der Kopf "6
#      Commits", darunter standen 3 Betreffs und "und 1 weitere".
UP="$(upstream up15 main)"
git clone --quiet "$UP" "$WORK/c15"
# Upstream: 2 Commits auf einem Seitenzweig + ein echter Merge-Commit = 3
MTMP="$WORK/mergework"
git clone --quiet "$UP" "$MTMP"
git_q -C "$MTMP" checkout -b feat
echo a > "$MTMP/a.txt"; git_q -C "$MTMP" add -A; git_q -C "$MTMP" commit -m "feat a"
echo b > "$MTMP/b.txt"; git_q -C "$MTMP" add -A; git_q -C "$MTMP" commit -m "feat b"
git_q -C "$MTMP" checkout main
git_q -C "$MTMP" merge --no-ff -m "merge feat" feat
git_q -C "$MTMP" push origin main
rm -rf "$MTMP"
run_hook "$WORK/c15"
expect_rc0 "15 Merge-Commits"
n_subj=$(grep -cE '^  [0-9a-f]{7,} ' <<< "$OUT")
# Der Merge-Commit selbst muss in der Liste stehen — genau ihn hat
# --no-merges verschluckt (Gegenprobe G8 zeigt: dann nur 2 Betreffs).
if grep -q "3 Commits hinter" <<< "$OUT" && [ "$n_subj" -eq 3 ] \
   && grep -q "merge feat" <<< "$OUT" && ! grep -q "weitere" <<< "$OUT"; then
  ok "15 Merge-Commits -> Liste (3) deckt die genannte Zahl (3), kein Rest-Hinweis"
else
  bad "15 Merge-Commits -> Liste deckt die genannte Zahl" \
      "betreffs=$n_subj; Ausgabe: $OUT"
fi

echo
echo "TEIL 2 — Gegenprobe"
echo "==================="
echo "Jede Zusicherung einzeln neutralisieren; genau die zugehoerigen Faelle"
echo "muessen fallen. Faellt nichts, prueft der Test nichts."
echo

MUT="$WORK/mutant.sh"

# mutate <sed-oder-python-ausdruck> ... via python-Ersetzung
mutate() {  # mutate <suchstring> <ersatz>
  python3 - "$HOOK" "$MUT" "$1" "$2" << 'PY'
import sys
src, dst, old, new = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src).read()
if old not in s:
    sys.stderr.write("MUTATION-ANKER NICHT GEFUNDEN: %r\n" % old[:60])
    sys.exit(3)
open(dst, "w").write(s.replace(old, new, 1))
PY
  return $?
}

run_mut() {  # run_mut <dir> -> MOUT / MRC / MSECS
  local dir="$1" start end
  chmod +x "$MUT"
  start=$(date +%s)
  MOUT="$(CLAUDE_PROJECT_DIR="$dir" "$MUT" 2>/dev/null)"
  MRC=$?
  end=$(date +%s)
  MSECS=$((end - start))
}

# gegenprobe <name> <erwartung-faellt-beschreibung> <bedingung-dass-es-faellt>
check_mut() {
  local name="$1" cond="$2"
  if eval "$cond"; then ok "Gegenprobe $name -> Fall faellt wie erwartet"
  else bad "Gegenprobe $name" "Fall blieb gruen -> der Test prueft diese Zusicherung NICHT"; fi
}

# G1 — Default-Branch hart auf "main" verdrahten: Fall 05 (master) muss fallen
if mutate 'symref="$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null)" || symref=""
if [ -n "$symref" ]; then
  default_branch="${symref#"$REMOTE"/}"
fi' 'default_branch="main"'; then
  run_mut "$WORK/c5"
  check_mut "G1 'main' hart verdrahtet (Fall 05 master)" '! grep -q "hinter origin/master" <<< "$MOUT"'
else bad "Gegenprobe G1" "Mutation konnte nicht angewendet werden"; fi

# G2 — Schweigen-bei-0 entfernen: Fall 01 muss fallen
if mutate '[ "$behind" -gt 0 ] || exit 0' '[ "$behind" -ge 0 ] || exit 0'; then
  run_mut "$WORK/c1"
  check_mut "G2 Schweigen-bei-0 entfernt (Fall 01)" '[ -n "$MOUT" ]'
else bad "Gegenprobe G2" "Mutation konnte nicht angewendet werden"; fi

# G3 — merge-base-Schutz entfernen: Fall 11 muss eine erfundene Zahl melden
if mutate 'git merge-base HEAD FETCH_HEAD >/dev/null 2>&1 || exit 0' 'true'; then
  run_mut "$WORK/c11"
  check_mut "G3 merge-base-Schutz entfernt (Fall 11)" '[ -n "$MOUT" ]'
else bad "Gegenprobe G3" "Mutation konnte nicht angewendet werden"; fi

# G4 — Timeout entfernen: Fall 13 muss haengen (>10s statt <=10s)
if mutate '    "$TIMEOUT_BIN" -k 2 "$NET_TIMEOUT" "$@"' '    "$@"'; then
  python3 - "$MUT" << 'PY'
import sys
# auch die Ersatzbremsen abschalten, sonst greift GIT_HTTP_LOW_SPEED_*
p = sys.argv[1]; s = open(p).read()
s = s.replace('export GIT_HTTP_LOW_SPEED_LIMIT="${GIT_HTTP_LOW_SPEED_LIMIT:-1}"', '', 1)
s = s.replace('export GIT_HTTP_LOW_SPEED_TIME="${GIT_HTTP_LOW_SPEED_TIME:-$NET_TIMEOUT}"', '', 1)
open(p, "w").write(s)
PY
  # Harte Obergrenze, damit die Testsuite selbst nicht haengt.
  start=$(date +%s)
  MOUT="$(CLAUDE_PROJECT_DIR="$WORK/c13" timeout 20 "$MUT" 2>/dev/null)"; MRC=$?
  MSECS=$(( $(date +%s) - start ))
  check_mut "G4 Timeout entfernt (Fall 13, ${MSECS}s)" '[ "$MSECS" -gt 10 ]'
else bad "Gegenprobe G4" "Mutation konnte nicht angewendet werden"; fi

# G5 — ls-remote-Fallback entfernen: Fall 06 (kein origin/HEAD) muss fallen
if mutate 'if [ -z "$default_branch" ]; then
  default_branch="$(' 'if false; then
  default_branch="$('; then
  run_mut "$WORK/c6"
  check_mut "G5 ls-remote-Fallback entfernt (Fall 06)" '[ -z "$MOUT" ]'
else bad "Gegenprobe G5" "Mutation konnte nicht angewendet werden"; fi

# G6 — Die `|| exit 0`-Absicherung ist das, was den Hook nicht blockieren
#      laesst — NICHT das Fehlen von `set -e`: jeder Schritt steht ohnehin in
#      einem getesteten Kontext, `set -eu` allein aendert nichts (gemessen,
#      erste Fassung dieser Gegenprobe blieb gruen). Also: eine Absicherung
#      entfernen und `set -e` dazu -> Fall 09 (kein git-Repo) endet mit
#      Exit-Code != 0 und wuerde die Session anhalten.
if mutate 'git rev-parse --git-dir >/dev/null 2>&1 || exit 0' 'git rev-parse --git-dir >/dev/null 2>&1'; then
  python3 -c "import sys;p=sys.argv[1];s=open(p).read();open(p,'w').write(s.replace('set -u','set -eu',1))" "$MUT"
  run_mut "$WORK/c9"
  check_mut "G6 '|| exit 0'-Absicherung entfernt (Fall 09 blockiert, rc=$MRC)" '[ "$MRC" -ne 0 ]'
else bad "Gegenprobe G6" "Mutation konnte nicht angewendet werden"; fi

# G7 — Zusicherung "read-only" scharf stellen: Wenn der Hook zusaetzlich
#      mergte, muss Fall 14 fallen. (Der urspruenglich hier geplante
#      ERR-Trap-Nachbau ist entfallen: gemessen feuert der Trap bei einem
#      `cmd && ...`-Verbund NICHT, die Mutation waere wirkungslos gewesen und
#      haette eine Zusicherung vorgetaeuscht, die der Test nicht prueft.)
if mutate 'git rev-parse --verify --quiet FETCH_HEAD >/dev/null 2>&1 || exit 0' 'git rev-parse --verify --quiet FETCH_HEAD >/dev/null 2>&1 || exit 0
git merge --ff-only FETCH_HEAD >/dev/null 2>&1'; then
  head_pre="$(git -C "$WORK/c14" rev-parse HEAD)"
  run_mut "$WORK/c14"
  head_post="$(git -C "$WORK/c14" rev-parse HEAD)"
  # Fixture fuer weitere Laeufe zuruecksetzen
  git -C "$WORK/c14" reset --hard "$head_pre" >/dev/null 2>&1
  check_mut "G7 Hook mergt zusaetzlich (Fall 14 read-only)" '[ "$head_pre" != "$head_post" ]'
else bad "Gegenprobe G7" "Mutation konnte nicht angewendet werden"; fi

# G8 — '--no-merges' zurueckbauen: Fall 15 muss fallen (Liste zeigt dann 2
#      Betreffs, waehrend der Kopf 3 Commits nennt).
if mutate "subjects=\"\$(git log --format='  %h %s'" "subjects=\"\$(git log --no-merges --format='  %h %s'"; then
  run_mut "$WORK/c15"
  m_subj=$(grep -cE '^  [0-9a-f]{7,} ' <<< "$MOUT")
  check_mut "G8 '--no-merges' zurueckgebaut (Fall 15, Betreffs=$m_subj)" '[ "$m_subj" -ne 3 ]'
else bad "Gegenprobe G8" "Mutation konnte nicht angewendet werden"; fi

# G9 — Rest-Hinweis wieder aus MAX_SUBJECTS statt aus dem Gedruckten rechnen:
#      Fall 15 muss fallen (3 > 5 ist falsch -> Rest-Zeile fehlt zwar, aber
#      in Fall 04 stimmt sie; hier greift die Kombination mit G8). Geprueft
#      wird die Rechnung direkt an einem Fall mit weniger Zeilen als MAX.
if mutate 'if [ "$behind" -gt "$shown" ]; then
  echo "  ... und $((behind - shown)) weitere"
fi' 'if [ "$behind" -gt "$MAX_SUBJECTS" ]; then
  echo "  ... und $((behind - MAX_SUBJECTS)) weitere"
fi'; then
  # zusaetzlich --no-merges: erst beides zusammen erzeugt den Originalfehler
  python3 -c "import sys;p=sys.argv[1];s=open(p).read();open(p,'w').write(s.replace(chr(36)+\"(git log --format\", chr(36)+\"(git log --no-merges --format\",1))" "$MUT"
  run_mut "$WORK/c15"
  m_subj=$(grep -cE '^  [0-9a-f]{7,} ' <<< "$MOUT")
  check_mut "G9 Rest aus MAX_SUBJECTS + --no-merges (Fall 15, Betreffs=$m_subj)" '[ "$m_subj" -ne 3 ]'
else bad "Gegenprobe G9" "Mutation konnte nicht angewendet werden"; fi

echo
echo "==================="
printf 'PASS %d   FAIL %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Gefallen:\n'
  for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
echo "Alles gruen."
