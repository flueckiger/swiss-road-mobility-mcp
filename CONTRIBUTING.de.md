# Beitragen

[🇬🇧 English Version](CONTRIBUTING.md)

Vielen Dank für Ihr Interesse an diesem Projekt! Beiträge sind willkommen. Dieser
Server ist Teil des [Swiss Public Data MCP Portfolios](https://github.com/malkreide/swiss-public-data-mcp).

## Wie kann ich beitragen?

**Fehler melden:** Erstellen Sie ein [Issue](../../issues) mit einer klaren
Beschreibung, Schritten zur Reproduktion und der erwarteten vs. tatsächlichen
Ausgabe. Bitte geben Sie Ihre Python-Version und Ihr Betriebssystem an.

**Feature vorschlagen:** Beschreiben Sie den Use Case, idealerweise mit einem
Bezug zum Schweizer Strassen- und Mobilitätskontext (Shared Mobility, E-Laden,
Verkehr, Park & Rail, multimodale Reisen etc.).

**Code beitragen:**

1. Forken Sie das Repository
2. Erstellen Sie einen Feature-Branch: `git checkout -b feat/mein-feature`
3. Installieren Sie die Dev-Abhängigkeiten: `pip install -e ".[dev]"`
4. Schreiben Sie Tests für Ihre Änderungen
5. Lint prüfen: `ruff check src/ tests/`
6. Stellen Sie sicher, dass alle Tests bestehen: `pytest tests/ -v`
7. Commit mit aussagekräftiger Nachricht (siehe [Conventional Commits](https://www.conventionalcommits.org/)): `git commit -m "feat: neues Tool hinzufügen"`
8. Pull Request gegen `main` erstellen

## Code-Standards

- Python 3.11+, Ruff für Linting und Formatierung
- Type Hints für alle öffentlichen Funktionen erforderlich
- Docstrings auf Englisch (für internationale Kompatibilität)
- Kommentare und Fehlermeldungen dürfen Deutsch oder Englisch sein
- Alle MCP-Tools müssen `readOnlyHint: True` setzen (nur lesender Zugriff)
- Pydantic-v2-Modelle für alle Tool-Inputs
- Den bestehenden FastMCP-Mustern in den Quellmodulen folgen

## Datenquellen

Dieser Server nutzt Schweizer Strassen- und Mobilitäts-APIs — die meisten ohne
Authentifizierung:

| Quelle | Dokumentation |
|--------|--------------|
| sharedmobility.ch | [sharedmobility.ch](https://sharedmobility.ch/) |
| ich-tanke-strom.ch | [ich-tanke-strom.ch](https://ich-tanke-strom.ch/) |
| opentransportdata.swiss | [opentransportdata.swiss](https://opentransportdata.swiss/) |
| SBB Open Data | [data.sbb.ch](https://data.sbb.ch/) |
| geo.admin.ch | [api3.geo.admin.ch](https://api3.geo.admin.ch/) |

Beim Hinzufügen neuer Datenquellen gilt das **No-Auth-First**-Prinzip: zuerst
offene, authentifizierungsfreie Endpunkte; authentifizierte APIs werden mit
Graceful Degradation eingeführt.

## API-Keys

Integrationstests für die Verkehrstools benötigen einen kostenlosen API-Key von
[api-manager.opentransportdata.swiss](https://api-manager.opentransportdata.swiss/).
Committen Sie **niemals** API-Keys.

## Die Live-Suite: wann sie läuft, und wer ein rotes Ergebnis sieht

**Kadenz:** täglich um 04:00 UTC, dazu jederzeit von Hand über *Actions → Live API Tests → Run
workflow*. Siehe [`.github/workflows/live-tests.yml`](.github/workflows/live-tests.yml).

**Wer es sieht:** Ein roter Lauf öffnet ein Issue mit dem Label `upstream` und dem stabilen Titel «Live-Tests gegen transport.opendata.ch / api3.geo.admin.ch rot (<Datum>)». Ein zweiter roter Lauf erkennt das offene Issue am Titelanfang und hängt sich an denselben Thread, statt ein zweites aufzumachen. Wird die Suite wieder grün, schliesst sich das Issue selbst.

**Drei Antworten, nicht zwei.** `scripts/classify_live_run.py` liest das JUnit-XML statt des
Exit-Codes und unterscheidet: `clear` (gelaufen, grün), `finding` (gelaufen,
etwas gefallen) und `unknown` (nicht gelaufen — Installation gescheitert, null
Tests eingesammelt, alle übersprungen). Ein `unknown` schliesst nie ein Issue:
Zuzumachen hiesse zu behaupten, der Vergleich sei gelaufen.

**Ein roter Live-Lauf heisst nicht zwingend «unser Fehler».** Er heisst: Der
Vertrag mit der Quelle hat sich geändert, oder die Quelle ist gerade aus. Beides
gehört gesehen, nur das Erste gehört gefixt. Bitte den Lauf lesen, bevor der Job
deaktiviert wird — so stirbt dieser Check, und er ist der einzige im Repo, der
einer falschen Grundannahme über transport.opendata.ch / api3.geo.admin.ch widersprechen kann. Jeder andere Test
prüft gegen eine Fixture, und die Fixture ist aus derselben Annahme geschrieben
wie der Code.

## Lizenz

Mit Ihrem Beitrag erklären Sie sich damit einverstanden, dass Ihre Beiträge unter
der [MIT-Lizenz](LICENSE) lizenziert werden.
