# 08 – Infrastruktur als Code, Pipeline und Beobachtbarkeit

**Ziel:** Infrastruktur entsteht reproduzierbar aus Code: OpenTofu startet PlaceFinder und Valkey als Container – derselbe Ablauf wie in der Cloud, ohne Konto und ohne Kosten. Eine Pipeline in GitHub Actions testet, baut, scannt und signiert das Image von PlaceFinder im eigenen Fork. Traces und Metriken zeigt Grafana.

**Baut auf:** [02-container](../02-container/README.md), [07-cache-and-storage](../07-cache-and-storage/README.md) · **Stand:** `t08` (Version 0.8.0) · **Kosten:** keine; GitHub Actions ist für öffentliche Repositories kostenlos

In Termin 8 läuft OpenTofu lokal in der Wartezeit, während beim neuen Anbieter `06-infrastructure-as-code` ausrollt.

| Datei | Aufgabe |
|---|---|
| `versions.tf` | OpenTofu ab 1.10 und der Docker-Provider; kein Backend, der State bleibt als Datei hier |
| `variables.tf` | Image, Zahl der Instanzen, Lebensdauer im Cache |
| `main.tf` | Netz, Valkey und PlaceFinder als Container |
| `outputs.tf` | Adressen der Instanzen |

Dazu gehört PlaceFinder ab Tag `t08`: die CI-Pipeline `.github/workflows/ci.yml`, Telemetrie mit OpenTelemetry und `DATABASE_INIT` (README von PlaceFinder, Abschnitte *Pipeline*, *Beobachtbarkeit* und *Datenbank selbst füllen*).

## OpenTofu mit Docker (Übung im Termin)

Die Konfiguration beschreibt, was sonst `compose.yaml` erledigt: ein Netz, Valkey und PlaceFinder als Container. Der State bleibt als Datei im Ordner (`terraform.tfstate`, nicht eingecheckt).

```bash
cd /workspaces/placefinder && docker compose build api      # Image placefinder:0.8.0 aus dem eigenen Fork
cd /workspaces/cloud-labs-local/08-iac-and-operations
tofu init                                   # lädt den Docker-Provider, legt .terraform.lock.hcl an
tofu plan                                   # was würde passieren? 5 to add
tofu apply                                  # nach Rückfrage anlegen
tofu output                                 # http://localhost:8101
curl "http://localhost:8101/v1/places?q=Erfurt" --include | grep --ignore-case cache-status
```

`docker compose build api` baut das Image unter dem Namen aus `compose.yaml`, ab Tag `t08` `placefinder:0.8.0`. Mit anderem Namen oder ohne eigenes Image: `tofu apply -var placefinder_image=ghcr.io/<github-user>/placefinder:t08`.

**Ausprobieren:**

1. **Ändern:** `tofu apply -var instances=2` – der Plan zeigt *1 to add*: ein zweiter Container auf Port 8102, der Rest bleibt.
2. **Ersetzen:** `tofu apply -var instances=2 -var cache_ttl=60` – eine geänderte Umgebungsvariable lässt sich an einem laufenden Container nicht ändern; der Plan zeigt `-/+` (*must be replaced*).
3. **Drift:** `docker rm --force pf-t08-valkey`, dann `tofu plan` – OpenTofu vergleicht den State mit der Wirklichkeit und will Valkey neu anlegen. `tofu apply` stellt den beschriebenen Zustand wieder her.
4. **State ansehen:** `tofu state list`, `tofu state show 'docker_container.placefinder[0]'`
5. **Abbauen:** `tofu destroy` – Container und Netz verschwinden, die Images bleiben (`keep_locally`).

## Pipeline im eigenen Fork

Der Tag `t08` von PlaceFinder enthält die Pipeline. In den eigenen Fork übernehmen (Remote `upstream` aus [00-setup](../00-setup/README.md)):

```bash
cd /workspaces/placefinder
git fetch upstream --tags                # Tag t08 der Musterlösung holen
git checkout t08 -- .github/workflows/ci.yml .github/dependabot.yml
uv run ruff format && uv run ruff check && uv run pytest      # vorher lokal grün?
git add .github && git commit --message "Add CI pipeline" && git push
```

Auf GitHub unter *Actions* die Workflows einmal aktivieren und den Lauf verfolgen. Auf `master` lädt der Job `image` das Image als `ghcr.io/<github-user>/placefinder:<commit>` und `:master` hoch, mit SBOM, Provenance und Signatur; nach `git push origin t08` entsteht auch `:t08`. Ein neues Paket ist privat; für die Container-Dienste der Cloud auf **Public** stellen (siehe [02-container](../02-container/README.md#image-in-die-github-container-registry-laden)). Was die Schritte tun und wie sich Signatur, SBOM und Provenance prüfen lassen: README von PlaceFinder, Abschnitt *Pipeline*.

## Beobachtbarkeit lokal

```bash
cd /workspaces/placefinder
OTEL_EXPORTER_OTLP_ENDPOINT=http://lgtm:4318 docker compose --profile observability up --detach --build
for i in $(seq 300); do                                  # Last erzeugen
  curl --silent --output /dev/null "http://localhost:8000/v1/places?q=Erf&limit=$(( i % 50 + 1 ))"
done
```

Der Dienst `lgtm` (Image `grafana/otel-lgtm`) bündelt OpenTelemetry Collector, Prometheus, Tempo, Loki und Grafana in einem Container – nur für Entwicklung und Demos. Grafana unter http://localhost:3000 öffnen (ohne Anmeldung): *Dashboards* → *RED Metrics (classic histogram)*, Auswahl `job` = `placefinder`. Unter *Explore* → *Tempo* die Traces einer Suche ansehen, unter *Explore* → *Prometheus* eigene Abfragen:

```promql
# Anteil der Anfragen ohne Serverfehler (SLI Verfügbarkeit), letzte 5 Minuten
sum(rate(http_server_request_duration_seconds_count{http_response_status_code!~"5.."}[5m]))
  / sum(rate(http_server_request_duration_seconds_count[5m]))
# Anteil der Anfragen unter 250 ms (SLI Latenz)
sum(rate(http_server_request_duration_seconds_bucket{le="0.25"}[5m]))
  / sum(rate(http_server_request_duration_seconds_count[5m]))
# Trefferquote des Caches
sum(rate(placefinder_cache_lookups_total{cache_result="hit"}[5m]))
  / sum(rate(placefinder_cache_lookups_total[5m]))
```

**Fehler sichtbar machen:** In `compose.yaml` `DATABASE_URL` und `DATABASE_INIT` einkommentieren, neu starten, dann `docker compose stop db` – die Suche antwortet mit `503`, die Fehlerrate im Dashboard steigt. Ohne Compose: `docker compose --profile observability up --detach lgtm` und PlaceFinder mit `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318 ./start.sh` starten.

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `Unable to find image 'placefinder:0.8.0'` | Das Image ist nicht gebaut. | `docker compose build api` in `/workspaces/placefinder` oder `-var placefinder_image=…` |
| `port is already allocated` auf 8101 | Ein früherer Lauf oder Compose belegt den Port. | `tofu destroy`, `docker ps` prüfen |
| Grafana zeigt keine Daten | PlaceFinder sendet nicht an `lgtm`. | `OTEL_EXPORTER_OTLP_ENDPOINT` beim Start setzen, wie oben |
| Pipeline: `denied: permission_denied` beim Hochladen | Dem Workflow fehlt `packages: write`, oder das Paket gehört einem anderen Repository. | `ci.yml` aus dem Tag `t08` übernehmen; Paket unter *Package settings* mit dem Fork verknüpfen |

## Aufräumen

```bash
tofu destroy
cd /workspaces/placefinder && docker compose --profile observability down
```

## Fragen zum Weiterdenken

- Was steht im State, und warum gehört er nicht ins Git-Repository?
- Was unterscheidet `tofu apply` von `docker compose up` – und was fehlt Compose, um Drift zu erkennen?
- Welches SLO würden Sie für PlaceFinder festlegen, und welche Metrik misst es?
