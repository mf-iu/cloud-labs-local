# 06 – PostgreSQL mit PostGIS

**Ziel:** PostgreSQL 18 mit den Erweiterungen PostGIS und pg_trgm läuft als Dienst `db` in der `compose.yaml` von PlaceFinder. Die Tabelle `places` enthält GeoNames `cities15000`. PlaceFinder (Stand `t06`) liest die Orte aus dieser Datenbank; der Smoke-Test zeigt, dass die API gleich bleibt. Dieselben Skripte laden und prüfen in Termin 6 die verwaltete Datenbank beim Anbieter – die lokale Datenbank liefert die Vergleichswerte. Abfragen mit und ohne Index sind Zusatz.

**Baut auf:** [02-container](../02-container/README.md) (Compose), [05-rest-api](../05-rest-api/README.md) (Smoke-Test) · **Stand:** `t06` (Version 0.6.0) · **Kosten:** keine

| Skript | Aufgabe |
|---|---|
| `load-cities.sh` | Tabelle `places` anlegen, GeoNames per `\copy` laden, Geometrie und Indizes ergänzen |
| `query.sh` | Beispielabfragen aus `queries.sql` ausführen oder eine interaktive psql-Sitzung öffnen |
| `test-api.sh` | PlaceFinder lokal mit dieser Datenbank starten und mit dem Smoke-Test prüfen |
| `load-pois.sh` | Zusatz: POIs aus OpenStreetMap laden |

Alle Skripte nutzen `DATABASE_URL`, wenn die Variable gesetzt ist, sonst die lokale Datenbank `postgresql://pf:pf@localhost:5432/pf`. So arbeiten sie unverändert mit jeder PostgreSQL-Datenbank; das Anbieter-Repository ruft sie im Schritt `05-storage` mit `with-db.sh` und der Adresse der verwalteten Datenbank auf.

## Im Termin: lokal zum Vergleich, PlaceFinder

Die Übung von Termin 6 findet beim eigenen Anbieter statt: Im Anbieter-Repository legt `05-storage/create-db.sh` eine verwaltete Datenbank an, `with-db.sh` ruft die Skripte dieses Ordners mit ihr auf (Anleitung im README von `05-storage`). Die lokale Datenbank hier liefert die Vergleichswerte; beides zusammen dauert rund 60 Minuten. Der Foliensatz `T06_Lab-Skripte` erklärt die Skripte.

### Datenbank mit Compose

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
cd /workspaces/placefinder
docker compose up --detach db   # docker compose ps zeigt db als healthy
```

### Laden und abfragen

```bash
cd /workspaces/cloud-labs-local/06-postgis
export PGOPTIONS="--jit=off --max_parallel_workers_per_gather=0"   # einfache Pläne
./load-cities.sh          # cities15000 laden, Tabelle und Indizes anlegen, wenige Sekunden
./query.sh                # Beispielabfragen aus queries.sql – die Vergleichswerte
```

Die Zeiten notieren und mit `./with-db.sh query.sh` im Anbieter-Repository vergleichen: Die Pläne sind gleich, aber jede Abfrage geht dort durchs Internet.

Liegt `cities15000.txt` im Kursnetz bereit, nach `../.state/data/` kopieren; sonst lädt `load-cities.sh` die Datei von GeoNames (ca. 3 MB, Lizenz CC BY 4.0).

`load-cities.sh` lädt die Daten mit `\copy` (Bulk-Import über das COPY-Protokoll; die Datei bleibt auf dem eigenen Rechner), ergänzt eine generierte Spalte `geom` vom Typ `geography(Point, 4326)`, die PostgreSQL aus Länge und Breite berechnet, und legt danach die Indizes an (`indexes.sql`):

| Index | Art | Wofür | Größe bei cities15000 |
|---|---|---|---|
| `places_geom_idx` | GiST auf `geom` | Umkreis und nächste Nachbarn | ca. 2,5 MB |
| `places_name_trgm_idx` | GIN mit Trigrammen auf `name` | unscharfe Suche (`%`, `similarity`) in `queries.sql` | ca. 2 MB |
| `places_all_names_trgm_idx` | GIN mit Trigrammen auf allen Namen | Namenssuche von PlaceFinder, auch über `alternatenames` (München → Munich) | ca. 19 MB |

Die Tabelle selbst ist rund 11 MB groß. Der Index auf allen Namen ist größer als die Tabelle, weil große Städte Hunderte von Schreibweisen haben – Indizes kosten Speicher. Sein Ausdruck muss genau dem in `src/placefinder/db.py` (`ALL_NAMES`) entsprechen, sonst nutzt PostgreSQL ihn nicht.

### PlaceFinder mit der Datenbank

Ab Tag `t06` liest PlaceFinder die Orte aus PostgreSQL, wenn `DATABASE_URL` gesetzt ist – sonst wie bisher aus der Datei. `test-api.sh` startet PlaceFinder aus `/workspaces/placefinder` auf Port 8006 mit der Datenbank, wartet auf `/health`, führt den Smoke-Test aus `tools/smoke-test.sh` aus, misst drei typische Anfragen und hält den Server wieder an. `DATA_FILE` zeigt dabei auf eine Datei, die es nicht gibt: Ein PlaceFinder, der `DATABASE_URL` übersieht, startet so gar nicht erst.

In der Übung läuft die Musterlösung; ein eigenes `PostgisRepository` ist Zusatz (siehe unten).

```bash
cd /workspaces/placefinder
git stash                                # nur falls es nicht übernommene Änderungen gibt
git fetch upstream --tags                # Tag t06 der Musterlösung holen
git switch --detach t06
../cloud-labs-local/06-postgis/test-api.sh   # endet mit "All checks passed" und drei Zeiten
```

Mit der Datenbank beim Anbieter: im Anbieter-Repository `cd 05-storage && ./with-db.sh test-api.sh` – derselbe Smoke-Test, die Antwortzeiten zeigen den Weg durchs Internet.

Von Hand, etwa für die Karte (`http://localhost:5173/?api=http://localhost:8000`):

```bash
export DATABASE_URL=postgresql://pf:pf@localhost:5432/pf
uv run fastapi dev src/placefinder/main.py             # meldet: Using PostGIS at localhost:5432/pf
unset DATABASE_URL                                     # danach wieder entfernen
```

### Aufräumen – gehört zur Übung

```bash
cd /workspaces/placefinder
docker compose down   # hält die Datenbank an; das Volume pgdata mit den Orten bleibt für Termin 7
git switch -          # zurück zum vorherigen Zweig, z. B. filter aus Termin 5
```

`docker compose down --volumes` würde auch die Daten löschen; dann vor Termin 7 `./load-cities.sh` erneut ausführen.

### Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `connection refused` auf Port 5432 | Die Datenbank läuft nicht. | `docker compose up --detach db` in `/workspaces/placefinder` |
| Skripte arbeiten mit einer anderen Datenbank | `DATABASE_URL` ist im Terminal noch gesetzt. | `unset DATABASE_URL` |
| Port 5432 belegt | Ein anderes PostgreSQL läuft auf dem Rechner. | in `compose.yaml` `127.0.0.1:5433:5432`, dann `export DATABASE_URL=postgresql://pf:pf@localhost:5433/pf` |
| `does not read DATABASE_URL yet` | PlaceFinder hat noch keine Datenbankanbindung. | Tag `t06` auschecken (siehe oben) |
| `Table places not found` | Die Datenbank ist leer. | `./load-cities.sh` |
| `Port 8006 is in use` | Ein früherer Lauf oder ein anderer Server belegt den Port. | `./test-api.sh --port 8007` |

### Fragen zum Weiterdenken

- Warum ist `Execution Time` lokal und beim Anbieter ähnlich, die Antwortzeit von `test-api.sh` aber nicht?
- Warum öffnet PlaceFinder einen Pool von Verbindungen beim Start, statt für jede Anfrage eine neue Verbindung aufzubauen?
- Was übernimmt eine verwaltete Datenbank in der Cloud gegenüber diesem Container (Backups, Updates, Failover)?

## Zusatz

Freiwillig und ohne Folgen für spätere Termine.

### Eigenes PostgisRepository

Statt der Musterlösung den eigenen Stand von PlaceFinder auf PostGIS umstellen: in `src/placefinder/db.py` ein `PostgisRepository` mit `find`, `get` und `count` nach dem Vorbild von `PlaceRepository`, zuerst für die Umkreissuche (Foliensatz `T06_Lab-Skripte`, Folie „PlaceFinder: ein Repository, zwei Implementierungen“).

```bash
uv add "psycopg[binary]" psycopg-pool   # Anführungszeichen wegen der eckigen Klammern
../cloud-labs-local/06-postgis/test-api.sh
TEST_DATABASE_URL=postgresql://pf:pf@localhost:5432/pf uv run pytest   # API-Tests gegen PostGIS
```

Der Smoke-Test prüft alle Filter; er ist erst grün, wenn das Repository vollständig ist.

### Andere GeoNames-Dateien

`./load-cities.sh <name>` holt eine andere Datei von GeoNames und ersetzt die Tabelle `places`. Statt eines Namens geht auch der Pfad einer vorhandenen Datei. Danach für Termin 7 wieder `./load-cities.sh` ohne Argument.

```bash
./load-cities.sh DE             # Länderdatei Deutschland, auch Berge, Seen, Ortsteile
./load-cities.sh allCountries   # rund 13 Millionen Einträge, Download ca. 400 MB
```

Bei `allCountries` dauern Import und Indizes einige Minuten und belegen mehrere GB – ein Skalierungstest: dieselben Abfragen, die Zeiten mit `cities15000` vergleichen.

### POIs aus OpenStreetMap

`load-pois.sh` lädt einen Auszug von Geofabrik (Standard: Thüringen, ca. 150 MB) und importiert mit osm2pgsql (getestet mit 1.11 aus `sudo apt install osm2pgsql` unter Ubuntu 24.04 und mit 2.3) alle benannten Punkte mit `amenity`- oder `tourism`-Tag in die Tabelle `pois` (`pois.lua`) – in Thüringen rund 24.000. POIs, die als Fläche erfasst sind, fehlen. osm2pgsql schreibt `geometry`; `pois.sql` ergänzt deshalb eine Spalte `geog` vom Typ `geography` mit GiST-Index, damit Abstände in Metern gerechnet werden.

```bash
./load-pois.sh                                     # Thüringen
./load-pois.sh europe/germany/sachsen              # anderer Auszug
```

Für spätere Updates mit `osm2pgsql-replication` muss der Import mit `--slim` laufen. Daten © OpenStreetMap contributors, ODbL.

### Abfragen mit und ohne Index

Datenbankwissen zum Auffrischen; Grundlage ist die lokale Datenbank aus dem Abschnitt „Im Termin“.

`queries.sql` enthält:

1. die zehn nächsten Orte zu Erfurt (KNN-Suche mit `<->`),
2. eine Suche über `asciiname` ohne und mit B-Baum-Index (der Index wird mit `ROLLBACK` wieder entfernt),
3. alle Orte im Umkreis von 50 km mit `EXPLAIN ANALYZE` (Bitmap Index Scan),
4. dieselbe Umkreisabfrage mit abgeschaltetem Index (Seq Scan) zum Vergleich,
5. eine unscharfe Suche „Wuerzburg“ → „Würzburg“.

**Die Falle** von Hand ausprobieren – `ST_Distance` im `WHERE` nutzt keinen Index:

```bash
./query.sh --interactive
```

```sql
EXPLAIN ANALYZE SELECT name FROM places
WHERE ST_Distance(geom, ST_MakePoint(11.03, 50.98)::geography) < 50000;   -- Seq Scan
```

Weiter mit [07-cache-and-storage](../07-cache-and-storage/README.md).
