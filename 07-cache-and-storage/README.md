# 07 – Cache und Object Storage

**Ziel:** Object Storage lokal mit SeaweedFS – privat, mit zeitlich begrenztem Zugriff, Range Requests und CORS. Darin liegen die Rohdaten von GeoNames und eine Kacheldatei (PMTiles), aus der die Karte von PlaceFinder ihre Basiskarte liest. Dazu Valkey als Cache für die Suchen von PlaceFinder und als Geo-Index im Vergleich mit PostGIS.

**Baut auf:** [06-postgis](../06-postgis/README.md) · **Stand:** `t07` (Version 0.7.0) · **Kosten:** keine

In Termin 7 sind die Kacheln Pflicht, Valkey ist Zusatz. Den Bucket beim Anbieter legt der Schritt `05-storage` im Anbieter-Repository an; er lädt dieselbe Kacheldatei hoch.

| Skript | Aufgabe |
|---|---|
| `make-tiles.sh` | Kacheln um Erfurt als PMTiles-Datei aus dem Tagesbuild von Protomaps schneiden |
| `local-s3.py` | lokaler Object Storage: CORS und Lebenszyklus, Upload, Pre-Signed URL mit Tests, Adresse der Karte |
| `test-cache.sh` | PlaceFinder mit Valkey starten: jede Suche zweimal, `Cache-Status` und Zeiten, Smoke-Test, Inhalt des Caches |
| `geosearch.sh` | Orte in Valkey laden (`GEOADD`) und die Umkreissuche mit `GEOSEARCH` neben PostGIS stellen |

## Dienste in Compose

Valkey und SeaweedFS laufen als Dienste in der `compose.yaml` von PlaceFinder. Die Musterlösung ab Tag `t07` enthält sie; im eigenen Fork diese Dienste und das Volume `s3data` ergänzen:

```yaml
services:
  # api, web and db as before; api with VALKEY_URL: valkey://valkey:6379/0
  valkey:
    image: valkey/valkey:9.0
    # a cache: memory only, nothing saved to disk; when 64 MB are full,
    # Valkey drops the least recently used keys
    command: >-
      valkey-server --save "" --appendonly no
      --maxmemory 64mb --maxmemory-policy allkeys-lru
    ports: ["127.0.0.1:6379:6379"]       # reachable from this computer only
    healthcheck:
      test: valkey-cli ping
      interval: 5s
  seaweedfs:
    image: chrislusf/seaweedfs:4.48
    # all components in one process: master, volume server, filer and the
    # S3 API on port 8333; WebDAV, admin UI and table catalogs are not needed
    command: >-
      mini -dir=/data -webdav=false -admin.ui=false
      -s3.port.iceberg=0 -s3.port.lance=0
    environment:
      # with credentials every request must be signed: the bucket is private
      AWS_ACCESS_KEY_ID: placefinder
      AWS_SECRET_ACCESS_KEY: placefinder-local    # local development only
      S3_BUCKET: placefinder                      # created at startup
    ports: ["127.0.0.1:8333:8333"]       # S3 API, from this computer only
    volumes: [s3data:/data]
    healthcheck:
      test: curl --fail --silent --output /dev/null http://127.0.0.1:8333/healthz
      interval: 5s

volumes:
  www:
  pgdata:
  s3data:
```

SeaweedFS liest die Zugangsdaten aus den Variablen, die alle S3-Werkzeuge kennen; sie heißen nach dem Anbieter, der die S3-API erfunden hat.

## Kacheln im Object Storage (Übung im Termin)

```bash
(cd /workspaces/placefinder && docker compose up --detach --wait seaweedfs)
cd /workspaces/cloud-labs-local/07-cache-and-storage
uv run local-s3.py setup                         # CORS und Lebenszyklus für den Bucket placefinder
uv run local-s3.py upload ../.state/data/cities15000.txt   # Rohdaten nach raw/ (aus 06-postgis)
./make-tiles.sh                                  # erfurt.pmtiles, wenige MB
uv run local-s3.py upload ../.state/data/erfurt.pmtiles    # nach tiles/
uv run local-s3.py presign tiles/erfurt.pmtiles  # ohne Signatur 403, Range 206, CORS
uv run local-s3.py map tiles/erfurt.pmtiles      # Adresse der Karte mit den eigenen Kacheln
```

Die Karte braucht PlaceFinder auf Port 8000 und einen Webserver für `frontend/` auf Port 5173:

```bash
cd /workspaces/placefinder
uv run fastapi dev src/placefinder/main.py              # Terminal 1: API auf Port 8000
python3 -m http.server 5173 --directory frontend        # Terminal 2: Karte auf Port 5173
```

Die Adresse aus `local-s3.py map` im Browser öffnen. Die Karte lädt ihre Kacheln dann direkt aus dem Bucket – ohne Kachelserver.

### Kacheln: `make-tiles.sh`

Protomaps baut jeden Tag eine Kacheldatei der ganzen Erde aus OpenStreetMap (rund 130 GB, PMTiles). `pmtiles extract` liest daraus mit Range Requests nur die Kacheln einer Bounding Box bis zur gewählten Zoomstufe und schreibt sie in eine neue Datei – für Erfurt (10,90–11,20° Länge, 50,90–51,10° Breite) bis Zoomstufe 14 einige MB. Andere Gebiete: `./make-tiles.sh <min_lon,min_lat,max_lon,max_lat> [maxzoom]`, dann `region.pmtiles`. Daten © OpenStreetMap-Mitwirkende, ODbL.

Die Karte von PlaceFinder liest mit `?tiles=<URL>` zuerst Kopf und Verzeichnis der Datei und dann jede Kachel mit einem Range Request (`Range: bytes=…`, Antwort `206 Partial Content`). Sie zoomt beim Start auf die Bounding Box aus dem Kopf der Datei.

### Object Storage lokal: `local-s3.py`

SeaweedFS spricht die S3-API; jeder S3-Client funktioniert damit. `local-s3.py` nutzt [minio](https://github.com/minio/minio-py), eine kleine S3-Bibliothek für Python; `uv run` installiert sie beim ersten Aufruf (Abhängigkeiten im Kopf der Datei, PEP 723). Endpunkt und Schlüssel stammen aus der `compose.yaml`.

- **Privat:** Mit den Zugangsdaten in der `compose.yaml` verlangt SeaweedFS für jede Anfrage eine Signatur. Ohne Signatur antwortet es mit `403`.
- **Signatur:** Jede S3-Anfrage trägt im Header `Authorization` eine Signatur nach Version 4 (SigV4): ein HMAC über Methode, Pfad, Header und Hash des Inhalts, gebildet mit einem Schlüssel, der aus dem geheimen Schlüssel, dem Datum und der Region abgeleitet ist. Für CORS hat minio keine eigene Funktion; `local-s3.py` baut diese Anfrage deshalb selbst und signiert sie mit dem Signierer von minio (`put_bucket_cors`).
- **Pre-Signed URL:** Die Signatur steht in der URL (`X-Amz-Algorithm`, `X-Amz-Credential`, `X-Amz-Date`, `X-Amz-Expires`, `X-Amz-Signature`). Wer die URL hat, darf genau dieses Objekt lesen, bis sie abläuft (`presign`: eine Stunde, `map`: ein Tag; höchstens sieben Tage).
- **Range Request:** `Range: bytes=0-99` liefert `206 Partial Content` und nur diese Bytes – die Grundlage von PMTiles.
- **CORS:** Die Karte auf `http://localhost:5173` liest den Bucket auf Port 8333, also von einer anderen Herkunft. `setup` erlaubt genau diese Herkunft mit dem Header `Range` und gibt `ETag` sowie `Content-Range` frei; `presign` prüft das mit einer Preflight-Anfrage (`OPTIONS`).
- **Lebenszyklus:** Objekte unter `raw/` löscht SeaweedFS nach 30 Tagen.

## Zusatz: Cache mit Valkey

```bash
(cd /workspaces/placefinder && docker compose up --detach --wait db valkey)
cd /workspaces/cloud-labs-local/07-cache-and-storage
./test-cache.sh                                  # Cache: erst Miss, dann Hit; Smoke-Test
./geosearch.sh                                   # GEOSEARCH in Valkey neben PostGIS
```

### Cache: `test-cache.sh`

Das Skript leert den Cache und startet PlaceFinder auf Port 8007 mit Valkey – mit der Datenbank aus `DATABASE_URL` bzw. der lokalen, wenn der Dienst `db` läuft, sonst mit der Datei im Speicher. Dann sendet es drei Suchen je zweimal. Die erste Anfrage geht an die Datenbank (`Cache-Status: PlaceFinder; fwd=uri-miss; stored`), die zweite beantwortet Valkey (`PlaceFinder; hit`). Danach läuft der Smoke-Test: Mit Cache muss die API genau dieselben Antworten geben. Zum Schluss zeigt das Skript Schlüssel, verbleibende Lebensdauer (TTL), Treffer und Fehlschläge (`keyspace_hits`, `keyspace_misses`) und den Speicherbedarf.

Von Hand:

```bash
cd /workspaces/placefinder
VALKEY_URL=valkey://localhost:6379/0 uv run fastapi dev src/placefinder/main.py   # Terminal 1
curl --include "http://localhost:8000/v1/places?q=Erfurt" | grep --ignore-case cache-status   # fwd=uri-miss; stored
curl --include "http://localhost:8000/v1/places?q=Erfurt" | grep --ignore-case cache-status   # hit
docker compose exec valkey valkey-cli --scan --pattern 'placefinder:*'    # Schlüssel
docker compose exec valkey valkey-cli ttl 'placefinder:v1:/v1/places?q=Erfurt'
docker compose exec valkey valkey-cli monitor                              # alle Befehle live, Strg+C
docker compose exec valkey valkey-cli flushdb                              # Cache leeren
```

Wie der Cache in PlaceFinder arbeitet (Cache-aside, Schlüssel, Fail open): README von PlaceFinder, Abschnitt *Cache*.

### Geo-Index: `geosearch.sh`

`GEOADD` speichert jeden Ort in einem Sorted Set; der Score ist ein 52-Bit-Geohash aus Länge und Breite. Nahe Orte haben ähnliche Geohashes – `GEOSEARCH` sucht deshalb nur in wenigen Bereichen des Sets. Das Skript lädt alle Orte von `cities15000` in einem Strom (`valkey-cli --pipe`), zeigt Geohash und Score von Erfurt und die zehn nächsten Orte im Umkreis von 25 km, dann dieselbe Suche in PostGIS. Die Abstände weichen leicht ab: Valkey rechnet auf einer Kugel, PostGIS mit `geography` auf dem Ellipsoid WGS 84. Der Index belegt rund 4 MB im Speicher; bei vollem Speicher kann `allkeys-lru` ihn verdrängen.

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `No answer from http://localhost:8333` | SeaweedFS läuft nicht. | `docker compose up --detach --wait seaweedfs` in `/workspaces/placefinder` |
| `has no cache yet` | PlaceFinder kennt `VALKEY_URL` noch nicht. | Übung abschließen oder Tag `t07` auschecken |
| Karte zeigt die Basiskarte von OpenFreeMap | Parameter `tiles` fehlt oder ist nicht URL-kodiert. | Adresse aus `local-s3.py map` verwenden |
| Konsole des Browsers: CORS-Fehler | Die Karte läuft unter einer anderen Herkunft, z. B. `http://127.0.0.1:5173`. | Karte über `http://localhost:5173` öffnen |
| `403` trotz Signatur | Die URL ist abgelaufen oder wurde beim Kopieren verändert. | neue URL erzeugen, vollständig kopieren |
| `Port 8007 is in use` | Ein früherer Lauf oder ein anderer Server belegt den Port. | `./test-cache.sh --port 8008` |

## Aufräumen

```bash
cd /workspaces/placefinder && docker compose down   # die Volumes bleiben
```

## Fragen zum Weiterdenken

- Wie lange darf eine Suche im Cache bleiben? Was spricht für 5 Sekunden, was für einen Tag?
- Nach einem neuen `load-cities.sh` liefert der Cache noch alte Antworten. Welche Konsistenz bietet PlaceFinder damit – und wie ließe sich der Cache gezielt leeren?
- Warum ist eine Pre-Signed URL sicherer als ein öffentlicher Bucket, und wann ist sie trotzdem riskant?
- Warum braucht die Karte mit PMTiles keinen Kachelserver – und was ändert ein CDN davor an Kosten und Latenz?

Weiter mit [08-iac-and-operations](../08-iac-and-operations/README.md).
