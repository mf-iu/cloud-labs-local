# Cloud-Übungen: lokal

Übungen für den praktischen Teil des Kurses „Cloud Computing – Konzepte und Praxis für die Softwareentwicklung“, die ohne Cloud-Konto laufen: Container, Kubernetes, Netze im Cluster, REST-API, Datenbank, Cache, Object Storage und Infrastruktur als Code – alles im Dev Container auf dem eigenen Rechner. Kosten entstehen keine.

Die Übungen beim Cloud-Anbieter liegen in den Anbieter-Repositories `cloud-labs-<anbieter>`. Sie bauen auf diesem Repository auf: Sie nutzen sein Dockerfile, seine Bibliothek `lib/common.sh` und seine Werkzeuge, etwa den Smoke-Test. Umgekehrt kennt dieses Repository keinen Anbieter; `tools/check-neutral.sh` prüft das bei jedem Push.

## Ordner

```text
~/kurs/                        im Dev Container: /workspaces/
├── cloud-labs-local/          dieses Repository
├── cloud-labs-<anbieter>/     Übungen beim eigenen Anbieter (ab Termin 1)
└── placefinder/               eigener Fork der Beispielanwendung
```

Die Skripte erwarten PlaceFinder im Nachbarordner `placefinder` (oder in `PLACEFINDER_DIR`). Einrichtung: [00-setup](00-setup/README.md).

## Übungsschritte

Die Schritte bauen aufeinander auf; jeder nennt, was er voraussetzt und mit welchem Stand von PlaceFinder er arbeitet. Die Ordner folgen dem Inhalt, nicht den Terminen – die Zuordnung steht in der nächsten Tabelle.

| Schritt | Inhalt | Baut auf | Stand |
|---|---|---|---|
| [00-setup](00-setup/README.md) | Repositories klonen, Dev Container, Fork mit Tags, `config.env` | – | – |
| [01-placefinder](01-placefinder/README.md) | PlaceFinder starten, Tests, API mit curl | 00 | `t01` |
| [02-container](02-container/README.md) | Image bauen, Schichten, Trivy und Syft, Compose; Image nach ghcr.io | 01 | `t02` |
| [03-kubernetes](03-kubernetes/README.md) | Cluster `pf` mit k3d, Manifest, Rolling Update, ConfigMap, Helm, Autoscaler | 02 | `t03` |
| [04-cluster-network](04-cluster-network/README.md) | Gateway API mit Traefik, HTTPS mit cert-manager, NetworkPolicies, Diagnose | 03 | `t03` |
| [05-rest-api](05-rest-api/README.md) | Filter ergänzen, Smoke-Test lokal und über das Gateway, Vertragstests | 01, 04 | `t05` |
| [06-postgis](06-postgis/README.md) | PostGIS mit Compose, Orte laden, Abfragen mit und ohne Index | 02, 05 | `t06` |
| [07-cache-and-storage](07-cache-and-storage/README.md) | Valkey als Cache und Geo-Index, SeaweedFS mit Pre-Signed URLs, Kacheln als PMTiles | 06 | `t07` |
| [08-iac-and-operations](08-iac-and-operations/README.md) | OpenTofu mit Docker, Pipeline im eigenen Fork, Beobachtbarkeit mit Grafana | 02, 07 | `t08` |

Die Schritte `09-serverless`, `10-analytics` und `11-machine-learning` folgen.

## Zuordnung zu den Terminen

| Termin | Hier | Beim Anbieter (`cloud-labs-<anbieter>`) |
|---|---|---|
| 1 | `00-setup`, `01-placefinder` | `01-account` |
| 2 | `02-container` | `02-vm` |
| 3 | `03-kubernetes` | `03-container-service`, Teil 1 |
| 4 | `04-cluster-network` (Demo; für Teilnehmer Zusatz) | `04-network` |
| 5 | `05-rest-api` | `03-container-service`, Teil 2; Zusatz API-Gateway |
| 6 | `06-postgis` | Zusatz: `05-storage`, Datenbank |
| 7 | `07-cache-and-storage` (Kacheln Pflicht, Valkey Zusatz) | `05-storage`, Bucket |
| 8 | `08-iac-and-operations` (OpenTofu in der Wartezeit) | `01-account` beim neuen Anbieter, `06-infrastructure-as-code` |

## Werkzeuge

| Datei | Aufgabe |
|---|---|
| `tools/check-tools.sh` | Versionen der Werkzeuge im Dev Container und den Nachbarordner `placefinder` prüfen |
| `tools/smoke-test.sh` | REST-API von PlaceFinder gegen eine URL prüfen: lokal, im Cluster, beim Anbieter |
| `tools/rate-limit-test.sh` | viele Anfragen gleichzeitig senden und die Antworten zählen (200 und 429) |
| `tools/check-neutral.sh` | prüfen, dass dieses Repository keinen Cloud-Anbieter nennt |
| `lib/common.sh` | gemeinsame Funktionen aller Skripte, auch der Anbieter-Repositories |
| `.devcontainer/` | Dockerfile des Dev Containers für alle Repositories, Konfiguration ohne Anbieter |

`.state/` hält, was die Skripte anlegen oder herunterladen: GeoNames-Dateien, Kacheln und OpenStreetMap-Auszüge unter `.state/data/`, die Kurs-CA aus `04-cluster-network`. Der Ordner ist in `.gitignore` eingetragen.

## Daten und Lizenzen

- GeoNames (`cities15000`): CC BY 4.0, Namensnennung „GeoNames“
- OpenStreetMap: ODbL; Kacheln von Protomaps
- Geodaten werden nie eingecheckt, sondern von den Skripten geladen.

## Konventionen

Anleitungen auf Deutsch, Skripte, Kommentare und Commit-Messages auf Englisch. Die Shell-Skripte sind mit ShellCheck geprüft, die OpenTofu-Dateien mit `tofu fmt`. Die Dateien stammen aus den Ordnern `t02` bis `t08` der Anbieter-Repositories (Stand der Commits „Roll out the own t05 state in the session“); ihre frühere Historie steht dort.
