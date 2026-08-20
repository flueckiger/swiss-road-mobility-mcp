# SessionStart-Hook: Klon-Aktualität

`check-clone-freshness.sh` meldet beim Sessionstart, wie viele Commits der
ausgecheckte Stand hinter `origin/<default-branch>` liegt. Liegt er nicht
zurück, sagt er nichts.

## Grund

Ein veralteter Klon hat am 3.8.2026 **zweimal** eine rote CI erzeugt, deren
Ursache nicht im Diff stand — die fehlenden Commits waren jeweils genau die,
die das Gate einführten, an dem der Branch scheiterte. Man sucht den Fehler
dann in den falschen Dateien, weil der Diff harmlos aussieht und die CI
trotzdem rot ist.

Die Prüfung kostet eine Sekunde und ersetzt diese Fehlersuche.

Sie entspricht dem Abschnitt «Vor der Arbeit» in `CLAUDE.md`; der Hook
automatisiert genau den dort von Hand vorgeschriebenen Dreisatz.

## Die Regel, die über allen anderen steht

**Der Hook blockiert die Session niemals.** Kein Netz, kein Remote, detached
HEAD, flatterndes DNS, kaputtes git, fehlendes `timeout(1)` — jeder dieser
Fälle endet still mit Exit-Code 0 und ohne Ausgabe.

Das ist keine Kosmetik: Ein Hook, der bei Netzproblemen die Arbeit anhält,
wird nach dem zweiten Mal abgeschaltet und schützt danach gar nichts. Deshalb
steht im Skript bewusst **kein** `set -e`, **kein** `set -o pipefail` und
**kein** `trap ... ERR` — jeder Schritt ist einzeln mit `|| exit 0`
abgesichert.

> Zum `ERR`-Trap, gemessen an bash 5.2: Er feuert auch ohne `set -e`, sobald
> ein **nacktes** Kommando ungleich 0 endet — ein alleinstehendes `[ ... ]`,
> ein `grep` ohne Treffer. Ein `cmd && …`-Verbund ist davon ausgenommen. Er
> ist deshalb keine akute, aber eine latente Falle: Die erste Zeile, die
> legitim nicht-null zurückgibt, bricht die Meldung stumm mittendrin ab.
>
> Ebenfalls gemessen: `set -e` allein ändert am Verhalten **nichts**, weil
> ohnehin jeder Schritt in einem getesteten `|| exit 0`-Kontext steht. Die
> `|| exit 0`-Absicherungen sind die tragende Mechanik, nicht das Fehlen von
> `set -e` — Gegenprobe G6 belegt genau das.

## Zeitbudget

Zwei Netzaufrufe, jeder mit `timeout(1)` hart begrenzt auf
`CLAUDE_FRESHNESS_TIMEOUT` (Standard **4 s**), also **≤ 8 s** im schlimmsten
Fall. Der Normalfall ist ein Aufruf (~0,5 s), weil der Default-Branch
zuerst ohne Netz aus `refs/remotes/origin/HEAD` gelesen wird.

Zusätzliche Bremsen, damit nichts hängt:

| Mechanismus | wogegen |
|---|---|
| `timeout -k 2` (bzw. `gtimeout`) | hängende Verbindung |
| `GIT_HTTP_LOW_SPEED_LIMIT/TIME` | Ersatzbremse, falls kein `timeout(1)` da ist (BSD/macOS ohne coreutils) |
| `GIT_TERMINAL_PROMPT=0`, `GIT_ASKPASS=/bin/true` | wartender Passwort-Prompt |
| `ssh -oBatchMode=yes -oConnectTimeout=…` | wartende Host-Key-/Passphrase-Abfrage |

Ein wartender Prompt ist genau das Hängen, das der Hook vermeiden soll — er
läuft ohne TTY und würde sonst bis zum Harness-Timeout stehen. Das
`timeout: 15` in `settings.json` ist der letzte Auffangnetz-Wert.

## Der Default-Branch wird ermittelt, nicht geraten

Mindestens ein Repo im Portfolio nutzt `master` (`openlex-mcp`,
`swiss-courts-mcp`, `swisstopo-mcp`); genau die Annahme «main» hat schon
einmal einen Branch 15 Commits alt werden lassen. Reihenfolge:

1. `refs/remotes/origin/HEAD` — lokal, kein Netz, von `git clone` gesetzt.
2. `git ls-remote --symref origin HEAD` — ein Netzaufruf, nötig bei
   `--single-branch`- oder fetch-basierten Klonen, wo (1) fehlt.

Ergibt keiner der beiden etwas, schweigt der Hook. Ein hart verdrahtetes
`main` wäre hier der Fehler, den der Hook verhindern soll.

Wechselt ein Repo seinen Default-Branch nachträglich, ist (1) veraltet; dann
schlägt der `fetch` fehl und der Hook schweigt — er fällt sicher aus, statt
eine falsche Zahl zu melden.

## Flache Klone

Claude Code on the web klont **flach** (`--depth`). Ein pauschales «shallow →
schweigen» hätte den Hook damit in genau der Umgebung wirkungslos gemacht,
für die er gebaut ist. Gemessen: In diesem flachen Klon existiert ein
gemeinsamer Vorfahr, die Zählung stimmt.

Der Hook prüft deshalb nicht auf «flach», sondern auf **`git merge-base`**.
Fehlt der gemeinsame Vorfahr — die Kappungsgrenze schneidet ihn ab —, zählte
`HEAD..FETCH_HEAD` die ganze geholte Historie und meldete eine erfundene
Zahl. In dem Fall schweigt der Hook: lieber nichts als ein Fehlalarm.

## Der Arbeitsstand wird nicht angefasst

`git fetch <remote> <branch>` ohne Refspec schreibt `FETCH_HEAD` und bewegt
keinen lokalen Branch. Der Hook liest nur; das Einspielen bleibt Handarbeit
(die Meldung nennt den Befehl).

## Detached HEAD

Wird gemessen und gemeldet, nicht übersprungen: Der Schaden — fehlende
Commits, rote CI — ist derselbe, und die Zählung ist dort genauso gültig. Die
Meldung sagt dann «Der ausgecheckte Stand (detached HEAD)» statt eines
Branch-Namens. Nicht blockieren heisst nicht nichts sagen.

## Stellschrauben

| Variable | Standard | Wirkung |
|---|---|---|
| `CLAUDE_FRESHNESS_TIMEOUT` | `4` | Sekunden pro Netzaufruf |
| `CLAUDE_FRESHNESS_REMOTE` | `origin` | zu prüfender Remote |
| `CLAUDE_FRESHNESS_MAX_SUBJECTS` | `5` | angezeigte Commit-Betreffs |

## Selbst ausführen

```bash
.claude/hooks/check-clone-freshness.sh; echo "exit=$?"
```

Erwartung auf aktuellem Stand: keine Ausgabe, `exit=0`.

Die Testmatrix (`tests/test_session_start_hook.sh`) fährt 15 Fälle gegen
Wegwerf-Repos, darunter `master` als Default-Branch, nicht erreichbarer
Remote, detached HEAD und flacher Klon ohne gemeinsamen Vorfahren. Sie
enthält für jede Zusicherung eine Gegenprobe (`CLAUDE.md`, «Tests»): jeder
Schutz wird einzeln neutralisiert, und der Lauf zeigt, dass genau der
zugehörige Fall fällt.

```bash
tests/test_session_start_hook.sh
```

Das Skript ist bash, kein pytest — es braucht echte Repos, Remotes und
Netz-Ausfälle, und läuft deshalb ausserhalb der CI-Gates (die decken
`src/ tests/ scripts/` mit ruff und pytest ab; eine `.sh` fasst keines an).
