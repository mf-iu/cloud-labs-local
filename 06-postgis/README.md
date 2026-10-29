# 06 – PostgreSQL mit PostGIS

**Ziel:** PostgreSQL 18 mit den Erweiterungen PostGIS und pg_trgm läuft als Dienst `db` in der `compose.yaml` von PlaceFinder. Die Tabelle `places` enthält GeoNames `cities15000`; räumliche und unscharfe Abfragen laufen einmal mit und einmal ohne Index. PlaceFinder (Stand `t06`) liest die Orte aus dieser Datenbank; der Smoke-Test zeigt, dass die API gleich bleibt.

**Baut auf:** [02-container](../02-container/README.md) (Compose), [05-rest-api](../05-rest-api/README.md) (Smoke-Test) · **Stand:** `t06` (Version 0.6.0) · **Kosten:** keine

| Skript | Aufgabe |
|---|---|
| `load-cities.sh` | Tabelle `places` anlegen, GeoNames per `\copy` laden, Geometrie und Indizes ergänzen |
| `query.sh` | Beispielabfragen aus `queries.sql` ausführen oder eine interaktive psql-Sitzung öffnen |
| `test-api.sh` | PlaceFinder lokal mit dieser Datenbank starten und mit dem Smoke-Test prüfen |
| `load-pois.sh` | Zusatz: POIs aus OpenStreetMap laden |

Alle Skripte nutzen `DATABASE_URL`, wenn die Variable gesetzt ist, sonst die lokale Datenbank `postgresql://pf:pf@localhost:5432/pf`. So arbeiten sie unverändert mit jeder PostgreSQL-Datenbank; das Anbieter-Repository ruft sie im Schritt `05-storage` mit der Adresse der verwalteten Datenbank auf.

## Datenbank mit Compose (Übung im Termin)

In Termin 2 enthielt die `compose.yaml` nur `api` und den Übungsdienst `web`; jetzt kommen `db` und das Volume `pgdata` dazu. `web` braucht PlaceFinder nicht, er kann bleiben oder entfallen. Die Musterlösung ab Tag `t06` enthält den Dienst schon.

```yaml
services:
  # api (and web) as before
  db:
    image: postgis/postgis:18-3.6        # PostgreSQL 18 with PostGIS 3.6 (amd64 only)
    environment:
      POSTGRES_USER: pf
      POSTGRES_PASSWORD: pf              # plain text for local development only
      POSTGRES_DB: pf
    ports: ["127.0.0.1:5432:5432"]       # reachable from this computer only
    # from PostgreSQL 18 on, the volume belongs at /var/lib/postgresql
    volumes: [pgdata:/var/lib/postgresql]
    healthcheck:
      # --host 127.0.0.1: check via TCP, the init server only listens on the socket
      test: pg_isready --host 127.0.0.1 --username pf
      interval: 5s

volumes:
  www:
  pgdata:
```

```bash
(cd /workspaces/placefinder && docker compose up --detach db)   # db: healthy in docker compose ps
cd /workspaces/cloud-labs-local/06-postgis
export PGOPTIONS="--jit=off --max_parallel_workers_per_gather=0"   # einfache Pläne
./load-cities.sh          # cities15000 laden, Tabelle und Indizes anlegen, wenige Sekunden
./query.sh                # Beispielabfragen aus queries.sql
./query.sh --interactive  # interaktive psql-Sitzung
./test-api.sh             # PlaceFinder mit dieser Datenbank, sobald db.py fertig ist
```

`load-cities.sh` lädt die Daten mit `\copy` (Bulk-Import über das COPY-Protokoll; die Datei bleibt auf dem eigenen Rechner), ergänzt eine generierte Spalte `geom` vom Typ `geography(Point, 4326)`, die PostgreSQL aus Länge und Breite berechnet, und legt danach die Indizes an (`indexes.sql`):

| Index | Art | Wofür | Größe bei cities15000 |
|---|---|---|---|
| `places_geom_idx` | GiST auf `geom` | Umkreis und nächste Nachbarn | ca. 2,5 MB |
| `places_name_trgm_idx` | GIN mit Trigrammen auf `name` | unscharfe Suche (`%`, `similarity`) in `queries.sql` | ca. 2 MB |
| `places_all_names_trgm_idx` | GIN mit Trigrammen auf allen Namen | Namenssuche von PlaceFinder, auch über `alternatenames` (München → Munich) | ca. 19 MB |

Die Tabelle selbst ist rund 11 MB groß. Der Index auf allen Namen ist größer als die Tabelle, weil große Städte Hunderte von Schreibweisen haben – Indizes kosten Speicher. Sein Ausdruck muss genau dem in `src/placefinder/db.py` (`ALL_NAMES`) entsprechen, sonst nutzt PostgreSQL ihn nicht.

Andere GeoNames-Dateien lädt `./load-cities.sh <name>`; das Skript holt die Datei von GeoNames und ersetzt die Tabelle `places`. Statt eines Namens geht auch der Pfad einer vorhandenen Datei.

```bash
./load-cities.sh DE             # Länderdatei Deutschland, auch Berge, Seen, Ortsteile
./load-cities.sh allCountries   # rund 13 Millionen Einträge, Download ca. 400 MB
```

Bei `allCountries` dauern Import und Indizes einige Minuten und belegen mehrere GB.

## Prüfen

`queries.sql` enthält:

1. die zehn nächsten Orte zu Erfurt (KNN-Suche mit `<->`),
2. eine Suche über `asciiname` ohne und mit B-Baum-Index (der Index wird mit `ROLLBACK` wieder entfernt),
3. alle Orte im Umkreis von 50 km mit `EXPLAIN ANALYZE` (Bitmap Index Scan),
4. dieselbe Umkreisabfrage mit abgeschaltetem Index (Seq Scan) zum Vergleich,
5. eine unscharfe Suche „Wuerzburg“ → „Würzburg“.

## PlaceFinder mit der Datenbank

Ab Tag `t06` liest PlaceFinder die Orte aus PostgreSQL, wenn `DATABASE_URL` gesetzt ist – sonst wie bisher aus der Datei. `test-api.sh` startet PlaceFinder aus `/workspaces/placefinder` auf Port 8006 mit der Datenbank, wartet auf `/health`, führt den Smoke-Test aus `tools/smoke-test.sh` aus, misst drei typische Anfragen und hält den Server wieder an. `DATA_FILE` zeigt dabei auf eine Datei, die es nicht gibt: Ein PlaceFinder, der `DATABASE_URL` übersieht, startet so gar nicht erst.

Voraussetzung ist ein Stand von PlaceFinder, der `DATABASE_URL` liest – der eigene aus der Übung oder die Musterlösung:

```bash
cd /workspaces/placefinder
git fetch upstream --tags                # Tag t06 der Musterlösung holen
git switch --detach t06                  # oder den eigenen Stand verwenden
../cloud-labs-local/06-postgis/test-api.sh
git switch master
```

Von Hand, etwa für die Karte (`http://localhost:5173/?api=http://localhost:8000`):

```bash
export DATABASE_URL=postgresql://pf:pf@localhost:5432/pf
uv run fastapi dev src/placefinder/main.py             # meldet: Using PostGIS at localhost:5432/pf
```

**Tests gegen PostGIS:** Mit `TEST_DATABASE_URL` laufen alle API-Tests von PlaceFinder ein zweites Mal gegen PostGIS:

```bash
TEST_DATABASE_URL=postgresql://pf:pf@localhost:5432/pf uv run pytest
```

## Zusatz: POIs aus OpenStreetMap

`load-pois.sh` lädt einen Auszug von Geofabrik (Standard: Thüringen, ca. 150 MB) und importiert mit osm2pgsql (getestet mit 1.11 aus `sudo apt install osm2pgsql` unter Ubuntu 24.04 und mit 2.3) alle benannten Punkte mit `amenity`- oder `tourism`-Tag in die Tabelle `pois` (`pois.lua`) – in Thüringen rund 24.000. POIs, die als Fläche erfasst sind, fehlen. osm2pgsql schreibt `geometry`; `pois.sql` ergänzt deshalb eine Spalte `geog` vom Typ `geography` mit GiST-Index, damit Abstände in Metern gerechnet werden.

```bash
./load-pois.sh                                     # Thüringen
./load-pois.sh europe/germany/sachsen              # anderer Auszug
```

Für spätere Updates mit `osm2pgsql-replication` muss der Import mit `--slim` laufen. Daten © OpenStreetMap contributors, ODbL.

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `connection refused` auf Port 5432 | Die Datenbank läuft nicht. | `docker compose up --detach db` in `/workspaces/placefinder` |
| Skripte arbeiten mit einer anderen Datenbank | `DATABASE_URL` ist im Terminal noch gesetzt, etwa die Datenbank beim Anbieter. | `unset DATABASE_URL` |
| `does not read DATABASE_URL yet` | PlaceFinder hat noch keine Datenbankanbindung. | Übung abschließen oder Tag `t06` auschecken |
| `Table places not found` | Die Datenbank ist leer. | `./load-cities.sh` |
| `Port 8006 is in use` | Ein früherer Lauf oder ein anderer Server belegt den Port. | `./test-api.sh --port 8007` |

## Aufräumen

```bash
docker compose --file /workspaces/placefinder/compose.yaml down   # das Volume pgdata bleibt
```

## Fragen zum Weiterdenken

- Warum ist die Abfrage mit Index schneller, obwohl beide dieselbe Funktion `ST_DWithin` verwenden?
- Warum öffnet PlaceFinder einen Pool von Verbindungen beim Start, statt für jede Anfrage eine neue Verbindung aufzubauen?
- Was übernimmt eine verwaltete Datenbank in der Cloud gegenüber diesem Container (Backups, Updates, Failover)?

Weiter mit [07-cache-and-storage](../07-cache-and-storage/README.md).
