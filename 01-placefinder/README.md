# 01 – PlaceFinder starten

**Ziel:** PlaceFinder läuft im Dev Container, die Ortssuche antwortet, die Tests sind grün. PlaceFinder ist die Beispielanwendung des Kurses: ein Dienst zur Ortssuche auf Basis von GeoNames, der von Termin zu Termin wächst. Jeder Stand ist im Fork als Tag vorhanden (`t01`, `t02` …).

**Baut auf:** [00-setup](../00-setup/README.md) · **Stand:** `t01` oder später · **Kosten:** keine

## Starten

Im Terminal des Dev Containers:

```bash
cd /workspaces/placefinder
./start.sh                # lädt beim ersten Aufruf cities15000 nach data/, Server auf Port 8000
```

Von Hand geht es so:

```bash
data/download.sh                             # GeoNames cities15000 nach data/
uv run fastapi dev src/placefinder/main.py   # Entwicklungsserver auf Port 8000, lädt Änderungen neu
```

Beim ersten Start legt uv eine virtuelle Umgebung unter `.venv` an und installiert die Abhängigkeiten genau in den Versionen aus `uv.lock`. Mit `cities15000` (alle Orte ab 15.000 Einwohnern, rund 34.000) belegt PlaceFinder rund 130 MB Arbeitsspeicher und startet in etwa einer Sekunde. Weitere Optionen von `start.sh`, etwa eine andere GeoNames-Datei: README von PlaceFinder, Abschnitt *Einrichtung*.

## Ausprobieren

In einem zweiten Terminal (Stand `t01`, Version 0 der API):

```bash
curl "http://localhost:8000/places?q=Erfurt"
curl "http://localhost:8000/places?q=München&limit=3"   # findet Munich über die alternativen Namen
curl http://localhost:8000/                             # Name, Version, Quellenangabe
```

Die interaktive API-Dokumentation steht unter http://localhost:8000/docs; VS Code leitet den Port aus dem Dev Container weiter. Ab Tag `t05` gibt es die REST-API v1 unter `/v1/places` (README von PlaceFinder, Abschnitt *REST-API v1*).

## Tests

```bash
uv run pytest             # Tests
uv run ruff check         # Linter
```

## Einen anderen Stand ansehen

```bash
git tag                          # die Ausbaustufen im Fork
git switch --detach t01          # Stand von Termin 1
git switch master                # zurück
```

## Fragen zum Weiterdenken

- Was passiert beim Start mit den Daten, und was bedeutet das für eine zweite Instanz auf einem anderen Rechner?
- Welche der fünf Merkmale von Cloud Computing nach NIST würde ein Betrieb von PlaceFinder auf dem eigenen Notebook verfehlen?

Weiter mit [02-container](../02-container/README.md).
