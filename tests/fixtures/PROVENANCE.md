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
- **Auswahl:** 9 von 8853 Listeneintraegen (je Liste die ersten 3), aus 24345814 Bytes Rohantwort
- **Groesse:** 15323 Bytes
- **SHA-256:** `1e30cb454fcccb2ab943f11e3ae71e3bf1658914aa63ccba68b8416ae211cd3c`

## `charger_2.json`

- **Werkzeuge:** `road_find_charger`, `road_mobility_snapshot`
- **Schluessel:** `https://data.geo.admin.ch/ch.bfe.ladestellen-elektromobilitaet/status/ch.bfe.ladestellen-elektromobilitaet.json`
- **Auswahl:** 12 von 9251 Listeneintraegen (je Liste die ersten 3), aus 1204522 Bytes Rohantwort
- **Groesse:** 1258 Bytes
- **SHA-256:** `2954be484b09788088a3cb7c60594e27ab281a56373fcc9259cc01ecaedf1677`

## `charger_3.json`

- **Werkzeuge:** `road_find_charger`
- **Schluessel:** `https://data.geo.admin.ch/ch.bfe.ladestellen-elektromobilitaet/data/ch.bfe.ladestellen-elektromobilitaet.json`
- **Auswahl:** 95 von 9340 Listeneintraegen (je Liste die ersten 3), aus 26081676 Bytes Rohantwort
- **Groesse:** 20736 Bytes
- **SHA-256:** `ee884f095a611f6f8642cde3b2237b0575448338e9e2d07cfde15cbb0be33df8`

## `classify_road_1.json`

- **Werkzeuge:** `road_classify_road`
- **Schluessel:** `https://api3.geo.admin.ch/rest/services/ech/MapServer/identify?geometry=7.4396%2C46.949&geometryFormat=geojson&geometryType=esriGeometryPoint&imageDisplay=1000%2C1000%2C96&mapExtent=7.429600000000001%2C46.939%2C7.4496%2C46.958999999999996&tolerance=50&layers=all%3Ach.swisstopo.swisstlm3d-strassen&sr=4326&lang=de&returnGeometry=false`
- **Auswahl:** 3 von 22 Listeneintraegen (je Liste die ersten 3), aus 6815 Bytes Rohantwort
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
- **Auswahl:** 6 von 53 Listeneintraegen (je Liste die ersten 3), aus 30735 Bytes Rohantwort
- **Groesse:** 2424 Bytes
- **SHA-256:** `a0048bebdc7be32a19b8c8a2853d47e0aed79ef28a2fcc5099b8fe4cf16b5422`

## `sharing_providers_1.json`

- **Werkzeuge:** `road_sharing_providers`
- **Schluessel:** `https://api.sharedmobility.ch/v1/sharedmobility/providers`
- **Auswahl:** ungekuerzt — der Server liest diese Liste ganz, ein Schnitt behauptete einen kleineren Bestand
- **Groesse:** 25133 Bytes
- **SHA-256:** `23f6a63a78f956b953966a60c8af785068dc47b65dce1b86b5721f35ef5f3a16`

## `sharing_search_1.json`

- **Werkzeuge:** `road_search_sharing`
- **Schluessel:** `https://api.sharedmobility.ch/v1/sharedmobility/find?searchText=Bern&searchField=ch.bfe.sharedmobility.station.name&offset=0&geometryFormat=esrijson`
- **Auswahl:** 12 von 59 Listeneintraegen (je Liste die ersten 3), aus 41357 Bytes Rohantwort
- **Groesse:** 2793 Bytes
- **SHA-256:** `1999482094b37214b0bf4ecb2c8884ca2c24a98f5638e21c5622a78a3fe64142`

## `snapshot_1.json`

- **Werkzeuge:** `road_mobility_snapshot`
- **Schluessel:** `https://transport.opendata.ch/v1/locations?x=7.4396&y=46.949&type=station`
- **Auswahl:** 3 von 10 Listeneintraegen (je Liste die ersten 3), aus 1443 Bytes Rohantwort
- **Groesse:** 733 Bytes
- **SHA-256:** `5e876e816b6e4cd7ca844e359598c882a7c92b411249246bb70c1743b62e295d`
