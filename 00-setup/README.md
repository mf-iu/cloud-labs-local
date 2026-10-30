# 00 – Einrichtung

**Ziel:** Die Repositories liegen nebeneinander in `~/kurs`, der Dev Container läuft, der eigene Fork von PlaceFinder hat alle Tags, und `tools/check-tools.sh` meldet alle Werkzeuge.

## Voraussetzungen

- Windows mit WSL 2 (Ubuntu 24.04), darin Docker Engine; VS Code mit der Erweiterung *Dev Containers*. Alles andere steckt im Dev Container.
- Ein Konto auf GitHub
- Ab Termin 1 ein Konto beim eigenen Cloud-Anbieter – Einrichtung im Schritt `01-account` des Anbieter-Repositorys. Für die Schritte hier ist es nicht nötig.

## 1. Fork von PlaceFinder

[PlaceFinder](https://github.com/mf-iu/placefinder) auf GitHub forken. Dabei **„Copy the master branch only“ abwählen** – sonst fehlen im Fork die Tags der Ausbaustufen (`t01`, `t02` …), mit denen die Übungen arbeiten. Eigene Pipelines und das Abschlussprojekt laufen im Fork.

## 2. Repositories klonen

Im Ubuntu-Terminal von WSL, nicht im Container:

```bash
mkdir --parents ~/kurs && cd ~/kurs
git clone https://github.com/mf-iu/cloud-labs-local.git
git clone https://github.com/mf-iu/cloud-labs-<anbieter>.git        # Repository des eigenen Anbieters
git clone https://github.com/<github-user>/placefinder.git          # eigener Fork
cd placefinder
git remote add upstream https://github.com/mf-iu/placefinder.git    # die Musterlösungen
git fetch upstream --tags
```

Die drei Ordner müssen nebeneinander liegen: Die Skripte finden sich gegenseitig über den Elternordner.

## 3. Dev Container starten

Der Dev Container enthält alle Werkzeuge der Übungen: Python 3.12 mit uv, eine eigene Docker Engine im Container (Docker in Docker), kubectl, Helm, k3d, OpenTofu, Trivy, Syft, cosign, psql, osm2pgsql, pmtiles und die GitHub CLI. Alle Teilnehmer arbeiten so mit denselben Werkzeugen in denselben Versionen; ein Neubau stellt jederzeit den Ausgangszustand her.

Welchen Ordner öffnen?

| Ordner | Dev Container | wann |
|---|---|---|
| `cloud-labs-<anbieter>` | „Cloud-Kurs: \<Anbieter\>“: alle Werkzeuge und die CLI des Anbieters | Regelfall ab Termin 1 |
| `cloud-labs-local` | „Cloud-Kurs: lokal“: alle Werkzeuge ohne Anbieter-CLI, schneller gebaut | ohne Cloud-Konto |

Beide bauen dasselbe Dockerfile aus `cloud-labs-local/.devcontainer/`; das Anbieter-Repository ergänzt nur seine CLI und hängt deren Anmeldedaten ein.

```bash
code ~/kurs/cloud-labs-<anbieter>     # oder: code ~/kurs/cloud-labs-local
```

VS Code öffnet den Ordner in WSL und meldet „Folder contains a Dev Container configuration file“: **Reopen in Container** wählen. Ohne Meldung: F1 → „Dev Containers: Reopen in Container“. Der erste Start baut das Image und dauert 10–15 Minuten, danach startet der Container in Sekunden. Unten links zeigt VS Code dann „Dev Container: Cloud-Kurs: …“.

**Was erhalten bleibt:** Der Container sieht den ganzen Ordner `~/kurs` unter `/workspaces`, also auch `/workspaces/cloud-labs-local` und `/workspaces/placefinder` – egal, welches Repository geöffnet ist. SSH-Schlüssel (`~/.ssh`) und die Anmeldung beim Anbieter liegen in WSL und überstehen einen Neubau. Docker-Images und k3d-Cluster liegen in einem Volume des Containers; `docker login` (Docker Hub) ist nach einem Neubau zu wiederholen.

**Aktualisieren:** Ändert sich `.devcontainer/` in einem der Repositories, in VS Code F1 → „Dev Containers: Rebuild Container“.

## 4. Arbeiten im Terminal des Containers

- **Terminal öffnen:** Strg+Ö (deutsche Tastatur; auf einer US-Tastatur Strg+Backtick) oder *Terminal* → *New Terminal*. Die Eingabeaufforderung zeigt den Benutzer `vscode` und einen Pfad unter `/workspaces`, z. B. `vscode ➜ /workspaces/cloud-labs-<anbieter> (master) $`. Nach dem ersten Bau zeigt ein Terminal die Ausgabe von `tools/check-tools.sh`; mit einer Taste schließen und ein neues öffnen.
- **Ordner:** Jedes Terminal startet im geöffneten Repository. Lokale Schritte laufen in `/workspaces/cloud-labs-local`, Schritte beim Anbieter in `/workspaces/cloud-labs-<anbieter>`, PlaceFinder liegt in `/workspaces/placefinder`. Es sind dieselben Dateien wie in WSL unter `~/kurs`.
- **Mehrere Terminals:** mit **+** im Terminalbereich ein weiteres öffnen, mit Strg+Umschalt+5 nebeneinander teilen – praktisch für PlaceFinder: `uv run fastapi dev …` im einen, `curl` im anderen Terminal. Ein laufendes Programm beendet Strg+C, ein Terminal `exit` oder das Papierkorb-Symbol.
- **Ports:** Ports wie 8000 leitet VS Code automatisch weiter (Reiter *Ports* neben *Terminal*); `http://localhost:8000` funktioniert dann auch im Browser unter Windows.
- **Container oder WSL:** Im Container stehen alle Kurswerkzeuge zur Verfügung, aber nicht die eigene Shell-Konfiguration aus WSL. Befehle außerhalb des Containers laufen im Ubuntu-Fenster, z. B. `git clone` vor dem ersten Start und `ssh-keygen`; `wsl --shutdown` in der PowerShell. Zeigt VS Code unten links nur „WSL: Ubuntu-24.04“, ist der Ordner ohne Container geöffnet: F1 → „Dev Containers: Reopen in Container“.
- **Nach einem Neustart:** VS Code öffnet den Ordner meist wieder im Container. Sonst *File* → *Open Recent* und den Eintrag mit „[Dev Container]“ wählen.

## 5. Einstellungen und Prüfung

Im Terminal des Dev Containers:

```bash
cd /workspaces/cloud-labs-local
cp config.example.env config.env      # GITHUB_USER eintragen
tools/check-tools.sh                  # alle Werkzeuge da? placefinder daneben?
```

`config.env` enthält hier nur den GitHub-Benutzer und den Namen des Images auf ghcr.io; was nur die Cloud braucht, steht in der `config.env` des Anbieter-Repositorys (Schritt `01-account` dort). Beide Dateien und der Ordner `.state/` gehören nur auf den eigenen Rechner und sind in `.gitignore` eingetragen.

Weiter mit [01-placefinder](../01-placefinder/README.md).

## Typische Probleme

| Meldung | Ursache | Abhilfe |
|---|---|---|
| `MISSING placefinder` in `check-tools.sh` | Der Fork liegt nicht neben `cloud-labs-local`. | in WSL nach `~/kurs/placefinder` klonen |
| „Reopen in Container“ im Anbieter-Repository: Dockerfile nicht gefunden | `cloud-labs-local` fehlt neben dem Anbieter-Repository; dessen Dev Container baut das Dockerfile von dort. | in WSL nach `~/kurs/cloud-labs-local` klonen, dann erneut „Reopen in Container“ |
| Anbieter-Skripte melden `cloud-labs-local not found` | wie oben | wie oben |
| `git tag` im Fork zeigt nichts | Beim Forken war „Copy the master branch only“ angehakt. | `git fetch upstream --tags`, dann `git push origin --tags` |
| Der erste Bau bricht mit `toomanyrequests` ab | Download-Limit von Docker Hub erreicht | siehe [02-container](../02-container/README.md#docker-hub-anmelden-oder-nicht) |
