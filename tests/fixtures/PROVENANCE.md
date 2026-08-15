# Herkunft der Fixtures

Aufgezeichnet am **2026-08-15** mit `PYTHONPATH=src python scripts/record_fixtures.py`.

Eine Antwort je **Abfrage**, nicht je Endpunkt: acht Hosts, aber mehr
Abfrageformen als Hosts. Acht Dateien wuerden die Portfolio-Regel erfuellen
und fast nichts belegen.

Der **Schluessel** unten ist die angefragte URL; danach ordnet der Test zu und
nicht nach Reihenfolge. `road_mobility_snapshot` fragt mehrere Quellen in einem
Aufruf ab, und eine Zuordnung nach Reihenfolge waere im gruenen Fall bloss
zufaellig richtig.

Die Antworten stammen aus dem Client von `client_lifecycle.build_client()`
(gleicher User-Agent, gleiches Timeout, gleiche Egress-Allow-List wie im
Betrieb), abgegriffen ueber einen httpx-Response-Hook. Ausgeloest hat sie
jeweils das Werkzeug selbst — so belegt die Aufzeichnung auch, dass das
Werkzeug genau diese Anfrage schickt.

## Was hier fehlt, und warum

- `road_park_rail`: data.opentransportdata.swiss antwortet mit HTTP 403 (nginx, auch auf site_read) — Sperre gegen diesen Anschluss, kein Befund ueber das Werkzeug

Die Verkehrsmeldungen (Phase 2, `opentransportdata.swiss`) verlangen
`OPENTRANSPORTDATA_API_KEY`. Beim Aufzeichnen war **kein Schluessel gesetzt**, deshalb gibt es fuer `road_traffic_situations` keine Aufzeichnung. Das ist eine Luecke im Ordner — und sie steht hier, statt still zu bleiben.

Neu gesetzt ist die Einrueckung; gekuerzt ist allein die **Zahl** der
Listeneintraege. Kein Feld eines behaltenen Eintrags ist angetastet, und
Zaehlfelder daneben stehen wie geliefert.

Die Fehlerpfade — Timeout, 5xx, leere Trefferliste — bleiben handgeschrieben.
Sie lassen sich nicht auf Zuruf aufzeichnen und sind als Erfindung in Ordnung.

## `charger_1.json`

- **Werkzeuge:** `road_find_charger`, `road_mobility_snapshot`
- **Schluessel:** `https://data.geo.admin.ch/ch.bfe.ladestellen-elektromobilitaet/data/ch.bfe.ladestellen-elektromobilitaet_de.json`
- **Auswahl:** ungekuerzt
- **Groesse:** 15323 Bytes
- **SHA-256:** `1e30cb454fcccb2ab943f11e3ae71e3bf1658914aa63ccba68b8416ae211cd3c`

## `charger_2.json`

- **Werkzeuge:** `road_find_charger`, `road_mobility_snapshot`
- **Schluessel:** `https://data.geo.admin.ch/ch.bfe.ladestellen-elektromobilitaet/status/ch.bfe.ladestellen-elektromobilitaet.json`
- **Auswahl:** ungekuerzt
- **Groesse:** 1260 Bytes
- **SHA-256:** `95af1d17fa0e1a356af78584e36c796b6fdda2a268c2412674ded02ac66efbc6`

## `charger_3.json`

- **Werkzeuge:** `road_find_charger`
- **Schluessel:** `https://data.geo.admin.ch/ch.bfe.ladestellen-elektromobilitaet/data/ch.bfe.ladestellen-elektromobilitaet.json`
- **Auswahl:** ungekuerzt
- **Groesse:** 20736 Bytes
- **SHA-256:** `ee884f095a611f6f8642cde3b2237b0575448338e9e2d07cfde15cbb0be33df8`

## `classify_road_1.json`

- **Werkzeuge:** `road_classify_road`
- **Schluessel:** `https://api3.geo.admin.ch/rest/services/ech/MapServer/identify?geometry=7.4396%2C46.949&geometryFormat=geojson&geometryType=esriGeometryPoint&imageDisplay=1000%2C1000%2C96&mapExtent=7.429600000000001%2C46.939%2C7.4496%2C46.958999999999996&tolerance=50&layers=all%3Ach.swisstopo.swisstlm3d-strassen&sr=4326&lang=de&returnGeometry=false`
- **Auswahl:** ungekuerzt
- **Groesse:** 1295 Bytes
- **SHA-256:** `a2ddb57cdc687e02f05b5eb876e9e4f36503c00132bc12a057da7135c0e669be`

## `geocode_1.json`

- **Werkzeuge:** `road_geocode_address`
- **Schluessel:** `https://api3.geo.admin.ch/rest/services/api/SearchServer?searchText=Bundesplatz+3%2C+Bern&type=locations&origins=address&returnGeometry=true&limit=5&lang=de&sr=4326`
- **Auswahl:** ungekuerzt
- **Groesse:** 1093 Bytes
- **SHA-256:** `a01272af2477990cbb64763d990a0db2e1da7f62db79c7c5f58c0f1a15da6df1`

## `reverse_geocode_1.json`

- **Werkzeuge:** `road_reverse_geocode`
- **Schluessel:** `https://api3.geo.admin.ch/rest/services/ech/MapServer/identify?geometry=7.4396%2C46.949&geometryFormat=geojson&geometryType=esriGeometryPoint&imageDisplay=500%2C500%2C96&mapExtent=7.4346000000000005%2C46.943999999999996%2C7.4446%2C46.954&tolerance=30&layers=all%3Ach.swisstopo.amtliches-gebaeudeadressverzeichnis&sr=4326&lang=de&returnGeometry=false&limit=3`
- **Auswahl:** ungekuerzt
- **Groesse:** 1993 Bytes
- **SHA-256:** `1485829fa3b5606486a2531ca575e06e115d05afb24e544ac318d5d5e3d45dfa`

## `sharing_nearby_1.json`

- **Werkzeuge:** `road_find_sharing`, `road_mobility_snapshot`
- **Schluessel:** `https://api.sharedmobility.ch/v1/sharedmobility/identify?Geometry=7.4396%2C46.949&Tolerance=500&offset=0&geometryFormat=esrijson`
- **Auswahl:** ungekuerzt
- **Groesse:** 2909 Bytes
- **SHA-256:** `1a7711657a843d7bc386ae7340b59e9d72d1662d2a3ff057ebb0296008093ec1`

## `sharing_providers_1.json`

- **Werkzeuge:** `road_sharing_providers`
- **Schluessel:** `https://api.sharedmobility.ch/v1/sharedmobility/providers`
- **Auswahl:** ungekuerzt — der Server liest diese Liste ganz, ein Schnitt behauptete einen kleineren Bestand
- **Groesse:** 25133 Bytes
- **SHA-256:** `ccc50714eda45f44fc4af7c28d6c484aad8498370941222ec8fe07c4c3445af8`

## `sharing_search_1.json`

- **Werkzeuge:** `road_search_sharing`
- **Schluessel:** `https://api.sharedmobility.ch/v1/sharedmobility/find?searchText=Bern&searchField=ch.bfe.sharedmobility.station.name&offset=0&geometryFormat=esrijson`
- **Auswahl:** ungekuerzt
- **Groesse:** 3381 Bytes
- **SHA-256:** `9f3a2f2e8fbe01ae3155e3ab8f7a57a562c1484731a859e45852ad89e7704b13`

## `snapshot_1.json`

- **Werkzeuge:** `road_mobility_snapshot`
- **Schluessel:** `https://transport.opendata.ch/v1/locations?x=7.4396&y=46.949&type=station`
- **Auswahl:** ungekuerzt
- **Groesse:** 733 Bytes
- **SHA-256:** `5e876e816b6e4cd7ca844e359598c882a7c92b411249246bb70c1743b62e295d`
