# 02 – Container und Compose

**Ziel:** PlaceFinder läuft als Container. Das Image ist klein, ohne root, auf Schwachstellen geprüft und liegt auf Wunsch in der GitHub Container Registry, von wo es die Container-Dienste der Cloud ab Termin 3 laden. Compose startet PlaceFinder zusammen mit einem zweiten Dienst.

**Baut auf:** [01-placefinder](../01-placefinder/README.md) · **Stand:** `t02` oder später (Musterlösung: Tag `t02`) · **Kosten:** keine

| Skript | Aufgabe |
|---|---|
| `publish-image.sh` | Image aus `../placefinder` bauen und als `:<version>` und `:t03` nach ghcr.io laden; `--tag t05` für den Stand von Termin 5 usw. |

Alle Befehle laufen im Terminal des Dev Containers im Verzeichnis `/workspaces/placefinder`. Die Musterlösung lässt sich mit der eigenen vergleichen: `git diff t02 -- Dockerfile compose.yaml` (Remote `upstream` aus [00-setup](../00-setup/README.md)).

**Zwei Docker-Instanzen:** Der Dev Container hat eine eigene Docker Engine (Docker in Docker). Images, die dort gebaut werden, sieht Docker in der Ubuntu-Shell von WSL nicht, und umgekehrt. Im Kurs laufen alle Container-Übungen im Dev Container. Auch eine Anmeldung bei Docker Hub gilt nur für die Instanz, in der sie ausgeführt wurde.

## Image bauen und starten (Übung im Termin)

```bash
cd /workspaces/placefinder
version=$(uv version --short)                # Version aus pyproject.toml, z. B. 0.2.0
docker build --tag "placefinder:$version" .  # erster Build einige Minuten
docker history "placefinder:$version"        # Schichten mit Größe
docker run --rm --publish 8000:8000 "placefinder:$version"
curl "http://localhost:8000/places?q=Erfurt" # in einem zweiten Terminal
```

Das `Dockerfile` der Musterlösung hat drei Stufen:

| Stufe | Aufgabe |
|---|---|
| `data` | lädt die GeoNames-Datei (`cities15000`) und entpackt sie nach `/data` |
| `build` | installiert mit uv die Abhängigkeiten genau nach `uv.lock`, dann PlaceFinder selbst als Paket |
| Runtime | übernimmt nur die virtuelle Umgebung und die Daten, entfernt pip, läuft als Benutzer `app` ohne root |

Die Daten gehören damit zum Image (rund 8 MB). So startet der Container überall ohne Download, auch auf den Container-Diensten der Cloud; aktuelle Daten gibt es mit einem neuen Build. Eine andere Datei wählt `--build-arg GEONAMES_FILE=cities5000`. `.dockerignore` hält `.git`, `.venv`, `data/` und `tests/` aus dem Build-Kontext heraus.

Ändert sich nur der Code unter `src/`, baut Docker nur die letzten Schichten neu; ändert sich `uv.lock`, auch die Abhängigkeiten.

## Docker Hub: anmelden oder nicht?

Die Images `python:3.14-slim` und `busybox` kommen von Docker Hub. Docker Hub begrenzt die Downloads (Pulls) innerhalb von 6 Stunden:

| Zugriff | Pulls je 6 Stunden | gezählt je |
|---|---|---|
| ohne Anmeldung | 100 | öffentliche IP-Adresse (IPv4) bzw. IPv6-/64-Netz |
| mit kostenlosem Docker-Konto | 200 | Konto |

Ein Pull ist ein Image (ein Manifest), nicht jede Schicht; bei Images für mehrere Architekturen zählt jede geladene Architektur. Das aktuelle Limit steht unter [Docker Hub pull usage and limits](https://docs.docker.com/docker-hub/usage/pulls/).

**Entscheidungshilfe:** Wer zu Hause über einen eigenen Anschluss arbeitet, kommt ohne Anmeldung aus. In einem Hochschul- oder Firmennetz teilen sich dagegen oft alle Rechner eine öffentliche IP-Adresse; dann zählen die Pulls aller zusammen, und das anonyme Limit ist schnell erreicht. Dort lohnt die Anmeldung.

**Anmelden** (kostenloses Konto auf [hub.docker.com](https://hub.docker.com)), im Terminal des Dev Containers:

```bash
docker login      # Bestätigung im Browser oder Benutzername und Zugangstoken
docker logout     # Anmeldung wieder entfernen
```

Die Zugangsdaten speichert Docker unverschlüsselt in `~/.docker/config.json` des Containers. Wer Benutzername und Token eingibt, legt dafür auf Docker Hub ein Personal Access Token mit der Berechtigung *Public Repo Read-only* an, nicht das Passwort. Nach einem Neubau des Dev Containers ist die Anmeldung zu wiederholen; die Images selbst bleiben erhalten.

**Fehler `toomanyrequests`:** Die Meldung beim Bauen oder Starten bedeutet, dass das Limit erreicht ist.

- Anmelden und den Befehl wiederholen; ab dann zählt das eigene Kontingent.
- Oder warten: Das Limit bezieht sich auf die letzten 6 Stunden, frühere Pulls fallen nach und nach heraus.
- Bereits geladene Images bleiben in der Docker Engine des Dev Containers (`docker images`). Befehle, die ausdrücklich neu laden (`docker build --pull`, `docker compose pull`), bis dahin vermeiden.

Wie viele Pulls noch übrig sind, zeigt eine Abfrage, die selbst nicht mitzählt (ohne Anmeldung: Kontingent der eigenen IP-Adresse):

```bash
token=$(curl --silent "https://auth.docker.io/token?service=registry.docker.io&scope=repository:ratelimitpreview/test:pull" | jq --raw-output .token)
curl --silent --head --header "Authorization: Bearer $token" \
  https://registry-1.docker.io/v2/ratelimitpreview/test/manifests/latest | grep --ignore-case ratelimit
```

`ratelimit-limit: 100;w=21600` heißt 100 Pulls in 21600 Sekunden (6 Stunden), `ratelimit-remaining` ist der Rest. Fehlen diese Zeilen, gilt für die Adresse kein Limit.

## Compose: zwei Dienste (Selbstlernphase)

`compose.yaml` startet zwei Dienste: PlaceFinder (`api`) und `web`, einen winzigen Webserver aus dem offiziellen Image `busybox` (rund 2 MB). Ab `t06` kommt die Datenbank `db` dazu ([06-postgis](../06-postgis/README.md)), ab `t07` der Cache `valkey` und der Object Storage `seaweedfs` ([07-cache-and-storage](../07-cache-and-storage/README.md)).

> **Warum ein zweiter Dienst, der nichts mit PlaceFinder zu tun hat?**
> Mit nur einem Dienst wäre `compose.yaml` ein längerer `docker run`-Befehl. Erst mit zwei Diensten zeigt sich, was Compose leistet:
> ein gemeinsames Netz, in dem der Dienstname zugleich der Hostname ist; eine Startreihenfolge mit Healthcheck; ein benanntes Volume, das Daten über `docker compose down` hinaus hält.
> `web` ist dafür bewusst klein und unabhängig – PlaceFinder ruft ihn nicht auf.

```bash
cd /workspaces/placefinder                    # compose.yaml liegt hier
docker ps                                     # läuft noch ein Container auf Port 8000? stoppen
docker compose up --detach                    # bauen (falls nötig) und starten
docker compose ps                             # web: healthy, api: running (ab t06 auch db, ab t07 valkey, seaweedfs)
curl http://localhost:8080/                   # Startseite von web, liegt im Volume
docker compose exec api python -c "import urllib.request; print(urllib.request.urlopen('http://web:8080/').read().decode())"
docker compose exec web sh -c 'echo "Changed" > /www/index.html'
docker compose down                           # Container und Netz weg, das Volume www bleibt
docker compose up --detach
curl http://localhost:8080/                   # zeigt weiter "Changed"
docker compose down --volumes                 # zusätzlich das Volume löschen
```

- **Netz:** Der Aufruf aus `api` erreicht `web` über den Dienstnamen als Hostnamen (`http://web:8080/`); Port 8080 auf dem Rechner braucht er dafür nicht.
- **Reihenfolge:** `api` startet erst, wenn `web` den Healthcheck besteht (`wget` auf die Startseite), ab `t06` auch `db` (`pg_isready`), ab `t07` auch `valkey` (`valkey-cli ping`).
- **Volume:** `web` legt die Startseite beim ersten Start im Volume `www` an. Änderungen überstehen `docker compose down`; erst `down --volumes` löscht sie.

## Zusatz: Image verkleinern und prüfen

Zum Vergleich ein Image mit nur einer Stufe auf Basis von `python:3.14` bauen (ohne Daten, nur für den Größenvergleich):

```bash
docker build --tag placefinder:single --file - . <<'EOF'
FROM python:3.14
COPY --from=ghcr.io/astral-sh/uv:0.12.21 /uv /bin/uv
WORKDIR /app
COPY . .
RUN uv sync --locked --no-dev
CMD [".venv/bin/uvicorn", "placefinder.main:app", "--host", "0.0.0.0"]
EOF
docker images placefinder                                        # Größen vergleichen
trivy image --severity HIGH,CRITICAL "placefinder:$version"      # Schwachstellen
trivy image --severity HIGH,CRITICAL placefinder:single
syft "placefinder:$version"                                      # alle Pakete im Image (SBOM)
```

Fehlt `trivy` im Dev Container, geht es auch mit dem Image von Trivy:
`docker run --rm --volume /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.74.0 image --severity HIGH,CRITICAL placefinder:<version>`
(feste Version: Einige Trivy-Images vom März 2026 waren manipuliert, deshalb nie ohne Tag)

### Trivy-Bericht lesen

Trivy listet die Funde je Ziel: die Pakete des Betriebssystems (`debian`) und Python-Pakete (`python-pkg`). Wichtig sind die Spalten *Status* und *Fixed Version*:

| Status | Bedeutung | Was tun? |
|---|---|---|
| `fixed` | Es gibt eine korrigierte Version (*Fixed Version*). | Paket bzw. Base-Image aktualisieren und neu bauen |
| `affected` | Betroffen, aber noch keine Korrektur verfügbar. | abwarten; später mit `docker build --pull` neu bauen |
| `fix_deferred` | Die Distribution hat die Korrektur zurückgestellt, meist wegen geringer Auswirkung. | prüfen, ob die Anwendung das Paket überhaupt nutzt |

Bei PlaceFinder (Stand `t02`) sind alle Python-Pakete der virtuellen Umgebung ohne Befund. Die Funde im Debian-Teil des Base-Images (z. B. `util-linux`, `ncurses`, `systemd`) haben keine *Fixed Version*. PlaceFinder nutzt diese Programme nicht, und der Container läuft ohne root – die Funde sind vorhanden, aber praktisch nicht erreichbar.

Die Python-Funde des Base-Images (`msgpack`, `urllib3`, `setuptools`) stammen aus pip, das diese Pakete in sich mitbringt. Im laufenden Container wird pip nicht gebraucht; die Runtime-Stufe entfernt es deshalb. Prüfen lässt sich die Herkunft eines Funds über den Pfad im JSON-Bericht:

```bash
trivy image --format json "placefinder:$version" \
  | jq --raw-output '.Results[] | .Vulnerabilities[]? | "\(.PkgName) \(.InstalledVersion) \(.PkgPath // "-")"'
```

Nur Funde mit verfügbarer Korrektur zeigt `trivy image --ignore-unfixed …` – so wird in CI-Pipelines oft geprüft (Termin 8). Weniger Funde haben Base-Images mit weniger Paketen, etwa Distroless-Images.

## Image in die GitHub Container Registry laden

Optional in Termin 2, nötig ab Termin 3: Die Container-Dienste der Cloud laden das Image von dort.

```bash
gh auth login                                 # einmalig, falls noch nicht angemeldet
gh auth refresh --scopes write:packages       # Recht zum Hochladen von Paketen
cd /workspaces/cloud-labs-local/02-container
./publish-image.sh                            # placefinder:<version> und :t03
./publish-image.sh --tag t05                  # ab Termin 5: derselbe Weg für den Stand t05
```

`publish-image.sh` baut den ausgecheckten Stand von `/workspaces/placefinder` und lädt ihn als `ghcr.io/<github-user>/placefinder:<version>` und `:t03` hoch (`GITHUB_USER` aus `config.env`). Ein neues Paket ist zunächst privat: auf GitHub unter *Packages* → *placefinder* → *Package settings* → *Change visibility* auf **Public** stellen. Das Skript prüft am Ende, ob das geklappt hat. Ab Termin 8 lädt die Pipeline des Forks die Images hoch ([08-iac-and-operations](../08-iac-and-operations/README.md)).

Von Hand:

```bash
gh auth token | docker login ghcr.io --username <github-user> --password-stdin
docker tag "placefinder:$version" ghcr.io/<github-user>/placefinder:t03
docker push ghcr.io/<github-user>/placefinder:t03
```

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `no configuration file provided: not found` | Das Terminal steht nicht im Verzeichnis mit `compose.yaml`. | `cd /workspaces/placefinder` |
| `Bind for 0.0.0.0:8000 failed: port is already allocated` | Ein anderer Container belegt Port 8000, meist der aus `docker run` der Übung. | `docker ps`, den Container mit `docker stop <name>` beenden, dann `docker compose up --detach` |
| `Temporary failure in name resolution` beim Aufruf von `web` | Der Container `api` hat nach einem fehlgeschlagenen Start kein vollständiges Netz. | `docker compose down`, dann `docker compose up --detach` |
| `toomanyrequests` | Download-Limit von Docker Hub erreicht | siehe [Docker Hub: anmelden oder nicht?](#docker-hub-anmelden-oder-nicht) |
| `The GitHub token cannot upload packages` | Dem Token der GitHub CLI fehlt das Recht `write:packages`. | `gh auth refresh --scopes write:packages` |

## Fragen zum Weiterdenken

- Warum gehören die GeoNames-Daten ins Image und nicht in ein Volume? Wann wäre es umgekehrt besser?
- Was ändert sich am Angriffspunkt, wenn der Container ohne root läuft?
- Was unterscheidet ein Image-Tag wie `:t03` von einem Digest (`@sha256:…`)?

Weiter mit [03-kubernetes](../03-kubernetes/README.md).
