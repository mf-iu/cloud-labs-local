# 05 – REST-API ergänzen und prüfen

**Ziel:** Ein eigener Stand von PlaceFinder – der Tag `t05` mit einem zusätzlichen Filter – besteht die Tests, den Smoke-Test lokal und über das Gateway im Cluster und den Vertragstest mit Schemathesis. Derselbe Stand läuft danach beim Anbieter (Schritt `03-container-service`, Teil 2, im Anbieter-Repository).

**Baut auf:** [01-placefinder](../01-placefinder/README.md), für den Weg über das Gateway [04-cluster-network](../04-cluster-network/README.md) · **Stand:** `t05` (Version 0.5.0) · **Kosten:** keine

| Werkzeug | Aufgabe |
|---|---|
| `../tools/smoke-test.sh` | REST-API prüfen: Suche, Filter, Paginierung, ETag und 304, Problem Details, CORS, veraltete Version 0 – gegen jede URL |
| `uvx schemathesis` | Anfragen aus der OpenAPI-Beschreibung erzeugen und die Antworten gegen das Schema prüfen |

## Filter ergänzen (Übung im Termin)

Einen Zweig vom Tag `t05` der Musterlösung anlegen und den Filter `min_population` mit Test ergänzen (Aufgabe auf der Übungsfolie von Termin 5; Vorbild ist der Filter `country` in `src/placefinder/api.py`):

```bash
cd /workspaces/placefinder
git fetch upstream --tags                # tag t05 of the sample solution
git switch --create filter t05           # own branch from t05
# ... add the filter and its test ...
uv run pytest
uv run fastapi dev src/placefinder/main.py                       # Terminal 1
curl "http://localhost:8000/v1/places?min_population=1000000"    # Terminal 2: the new filter
```

Ohne eigene Änderung lässt sich auch der Tag `t05` selbst verwenden.

## Smoke-Test lokal

```bash
cd /workspaces/cloud-labs-local
tools/smoke-test.sh                      # without URL: http://localhost:8000
```

Die Ausgabe zeigt je Prüfung `OK` oder `FAIL` mit dem erwarteten Wert, am Ende ein Beispiel für Problem Details. Geprüft werden Medientyp `application/geo+json`, Länge vor Breite, Umkreis und Bounding Box um Erfurt, der Link `next` im Header `Link` und im Body, `ETag` mit `304 Not Modified`, Fehler als `application/problem+json`, CORS für die Karte auf `http://localhost:5173` und die Header `Deprecation` und `Sunset` der Version 0. Den neuen Filter kennt der Smoke-Test nicht; ihn prüft `curl` von Hand.

Der Smoke-Test sendet nur GET-Anfragen und ist damit gegen jede Instanz gefahrlos; sein Exit-Code ist 1, wenn etwas fehlschlägt. Die Anbieter-Repositories rufen ihn mit der Adresse ihres Dienstes auf.

## Vertragstest mit Schemathesis

```bash
uvx schemathesis run http://localhost:8000/openapi.json \
  --exclude-checks positive_data_acceptance
```

Schemathesis erzeugt aus der OpenAPI-Beschreibung Hunderte von Anfragen und prüft Statuscodes, Medientypen und Schemas der Antworten. Die Prüfung `positive_data_acceptance` erwartet, dass jede Anfrage, die zum Schema passt, angenommen wird. Ein beliebiger `cursor` passt zum Schema, ist aber kein gültiger Cursor – die API lehnt ihn zu Recht mit 422 ab. Deshalb ist diese Prüfung ausgeschlossen. Mit `--checks all` laufen zusätzlich alle übrigen Prüfungen.

## Zusatz: über das Gateway im Cluster

Mit dem Gateway aus [04-cluster-network](../04-cluster-network/README.md) läuft derselbe Smoke-Test über HTTPS, durch Traefik und den Service bis zu den Pods. Dafür braucht der Cluster das Image des eigenen Stands:

```bash
cd /workspaces/cloud-labs-local
03-kubernetes/load-image.sh              # placefinder:0.5.0 from the checked-out branch
kubectl apply --filename ../placefinder/deploy/k8s/
kubectl rollout restart deployment/placefinder
04-cluster-network/gateway-up.sh         # if the gateway is not running yet
tools/smoke-test.sh --cacert .state/course-ca.crt \
  --resolve placefinder.test:8443:127.0.0.1 https://placefinder.test:8443
```

`rollout restart` ist nötig, weil das neue Image denselben Tag `0.5.0` trägt wie ein früher geladenes. Ein eigener Tag wäre sauberer: Termin 5 zeigt, warum Digests noch besser sind.

## Karte

Ab Tag `t05` zeigt `frontend/index.html` die Orte im sichtbaren Ausschnitt auf einer Karte:

```bash
cd /workspaces/placefinder
uv run fastapi dev src/placefinder/main.py              # Terminal 1: API auf Port 8000
python3 -m http.server 5173 --directory frontend        # Terminal 2: Karte auf Port 5173
```

Im Browser http://localhost:5173 öffnen. Mit `?api=<URL>` zeigt die Karte die Daten einer anderen Instanz, etwa des Dienstes beim eigenen Anbieter. Die API erlaubt die Karte über CORS (`CORS_ORIGINS`).

## Typische Probleme

- Smoke-Test meldet Version 0.1.x und viele `FAIL`: Der Server läuft mit einem Stand vor `t05`. `git switch` auf den eigenen Zweig, Server neu starten.
- `No answer from http://localhost:8000`: Der Server läuft nicht oder auf einem anderen Port; URL angeben, z. B. `tools/smoke-test.sh http://localhost:8001`.
- Über das Gateway: `curl: (60) SSL certificate problem` – `--cacert` fehlt oder zeigt auf eine alte Kurs-CA; `gateway-up.sh` erneut aufrufen.
- `zsh: no matches found`: URLs mit `?` immer in Anführungszeichen setzen.

## Fragen zum Weiterdenken

- Welche Antworten des Smoke-Tests dürfte ein CDN zwischenspeichern, und wie lange (`Cache-Control`)?
- Warum ist der Cursor undurchsichtig, statt einfach eine Seitennummer zu sein?
- Welche Prüfungen des Smoke-Tests würden eine Pipeline vor einem schlechten Release bewahren (Termin 8)?

Weiter mit [06-postgis](../06-postgis/README.md).
