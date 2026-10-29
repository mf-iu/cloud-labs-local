# 03 – Kubernetes lokal mit k3d

**Ziel:** PlaceFinder läuft mit drei Replikaten in einem lokalen Kubernetes-Cluster, den k3d im Dev Container anlegt: Manifest anwenden, neue Version ausrollen, Konfiguration ändern, dasselbe mit Helm, auf Wunsch mit Autoscaler.

**Baut auf:** [02-container](../02-container/README.md) · **Stand:** `t03` oder später (Musterlösung: Tag `t03`, Ordner `deploy/`) · **Kosten:** keine – alles läuft im Dev Container. Drei Nodes brauchen zusammen rund 1,5 bis 2 GB Arbeitsspeicher; unter WSL ggf. die Grenze in `.wslconfig` erhöhen.

| Skript | Aufgabe |
|---|---|
| `cluster-up.sh` | Cluster `pf` anlegen (1 Server, 2 Agents, k3s 1.36, nur mit den nötigen Diensten) oder wieder starten |
| `load-image.sh` | Image `placefinder:<version>` aus `../placefinder` bauen und in die Nodes laden |
| `cluster-down.sh` | Cluster löschen; die Images bleiben in Docker |
| `cluster-recreate.sh` | prüfen, ob der Cluster zu `cluster-up.sh` passt, und ihn sonst neu anlegen; PlaceFinder wird wieder ausgerollt |

PlaceFinder enthält ab Tag `t03` unter `deploy/`:

| Datei | Inhalt |
|---|---|
| `deploy/k8s/placefinder.yaml` | Deployment mit drei Replikaten, Probes, Requests und Limit; Service; ConfigMap – Musterlösung der Übung |
| `deploy/hpa.yaml` | Horizontal Pod Autoscaler (Zusatzaufgabe) |
| `deploy/helm/placefinder/` | Helm-Chart mit denselben drei Objekten |
| `deploy/helm/values-dev.yaml`, `values-prod.yaml` | Werte je Umgebung für das Chart |

## Cluster anlegen und Manifest anwenden (Übung im Termin)

```bash
cd /workspaces/cloud-labs-local/03-kubernetes
./cluster-up.sh                         # beim ersten Mal 1–2 Minuten (k3s-Image laden)
./load-image.sh                         # placefinder:<version>, Version aus pyproject.toml
cd /workspaces/placefinder
kubectl apply --filename deploy/k8s/    # eigenes Manifest aus der Übung
kubectl get pods --output wide          # drei Pods, verteilt auf die Nodes
kubectl port-forward svc/placefinder 8000:80   # läuft weiter; zweites Terminal öffnen
curl "http://localhost:8000/places?q=Erfurt"
```

Die Nodes sind selbst Container mit eigenem containerd; Images aus Docker sehen sie nicht. Deshalb lädt `load-image.sh` das Image in jeden Node (`k3d image import`). `port-forward` verbindet mit genau einem Pod. Wird dieser Pod ersetzt (Update, Löschen), bricht die Verbindung ab; dann den Befehl erneut starten.

Die Musterlösung: `git diff t03 -- deploy/` im Fork (Remote `upstream` aus [00-setup](../00-setup/README.md)).

**Probes:** Die Readiness Probe fragt `/health`. Ist die Datenbank (ab Termin 6) nicht erreichbar, bekommt der Pod keine Anfragen mehr, bleibt aber am Leben. Ab Tag `t08` fragt die Liveness Probe `/livez`, das nur den Prozess prüft: Ein Ausfall der Datenbank soll nicht alle Pods gleichzeitig neu starten.

## Neue Version ausrollen

```bash
cd /workspaces/placefinder
uv version --bump patch --no-sync                   # Version in pyproject.toml und uv.lock erhöhen
../cloud-labs-local/03-kubernetes/load-image.sh     # baut die neue Version, lädt sie in den Cluster
kubectl set image deployment/placefinder api=placefinder:$(uv version --short)
kubectl rollout status deployment/placefinder
curl http://localhost:8000/                         # neue Version (port-forward neu starten)
kubectl rollout undo deployment/placefinder         # zurück zur vorigen Version
git restore pyproject.toml uv.lock                  # Version im Repository wieder wie vorher
```

## Konfiguration ändern

Die ConfigMap `placefinder-config` liefert `LOG_LEVEL` und `DATA_FILE` als Umgebungsvariablen. PlaceFinder liest sie nur beim Start, deshalb startet `rollout restart` die Pods neu:

```bash
# in deploy/k8s/placefinder.yaml: LOG_LEVEL: debug
kubectl apply --filename deploy/k8s/
kubectl rollout restart deployment/placefinder
kubectl logs deployment/placefinder --follow       # nach einer Suche: "Search q=Erfurt: …"
```

## Helm (Selbstlernphase)

Das Chart erzeugt dieselben Objekte, benannt nach dem Release: Release `pf` → `pf-placefinder`, die ConfigMap `pf-placefinder-config`. Es stört das Manifest aus `deploy/k8s/` deshalb nicht.

```bash
helm lint deploy/helm/placefinder
helm template pf deploy/helm/placefinder --values deploy/helm/values-dev.yaml   # nur anzeigen
helm upgrade --install pf deploy/helm/placefinder --values deploy/helm/values-dev.yaml
helm upgrade --install pf deploy/helm/placefinder --values deploy/helm/values-prod.yaml
helm history pf                                     # zwei Revisionen
helm rollback pf 1                                  # zurück zu den dev-Werten
helm uninstall pf
```

Die Annotation `checksum/config` im Deployment ändert sich mit der ConfigMap; deshalb startet `helm upgrade` die Pods neu, wenn sich nur die Konfiguration ändert. Mit `--set image.repository=ghcr.io/<github-user>/placefinder` laden die Nodes das Image aus der GitHub Container Registry statt des importierten.

## Zusatz: Autoscaler

```bash
kubectl apply --filename deploy/hpa.yaml
kubectl get hpa --watch                             # zweites Terminal
kubectl run load --rm --stdin --tty --image=busybox:1.37 -- \
  sh -c 'while true; do wget --quiet --output-document /dev/null "http://placefinder/v1/places?q=B"; done'
```

Mit Last steigt die Zahl der Replikate auf bis zu sechs; nach dem Ende der Last (Strg+C) sinkt sie nach etwa fünf Minuten wieder auf zwei. Ein erneutes `kubectl apply --filename deploy/k8s/` setzt die Replikate zunächst auf drei zurück, danach regelt der HPA wieder. Entfernen: `kubectl delete --filename deploy/hpa.yaml`. Vor Tag `t05` gibt es `/v1/places` noch nicht; dann `/places?q=B` verwenden.

## Typische Probleme

- `ErrImagePull` oder `ImagePullBackOff`: Das Image ist nicht in den Nodes. `./load-image.sh` nach `./cluster-up.sh` ausführen; Tag im Manifest und Version müssen übereinstimmen.
- Pods bleiben `Pending`: zu wenig Speicher, `kubectl describe pod <name>` zeigt den Grund.
- Nach einem Neubau des Dev Containers kennt `kubectl` den Cluster nicht mehr: `./cluster-up.sh` startet ihn und trägt ihn wieder ein.
- `cluster-up.sh` warnt `Cluster pf: port 8443 does not lead to node port 30443`, `… network policy controller is switched off` oder `… Traefik of k3s runs`: Der Cluster stammt von einer älteren Fassung des Skripts. Für diese Übung stört das nicht, [04-cluster-network](../04-cluster-network/README.md) braucht aber Port und NetworkPolicies, und beides lässt sich nachträglich nicht ändern. `./cluster-recreate.sh` löscht den Cluster, legt ihn mit gleich vielen Agents neu an und rollt PlaceFinder aus `deploy/k8s/` wieder aus; Helm-Releases und den Autoscaler danach selbst wieder einrichten.
- `Port 8443 is taken by: k3d-net-serverlb`: Der Cluster `net` einer früheren Fassung der Gateway-Demo belegt den Port. `./cluster-recreate.sh` löscht ihn nach Rückfrage.
- `kubectl get pods --all-namespaces` zeigt nur `coredns`, `metrics-server` und `local-path-provisioner` in `kube-system`, kein `traefik` oder `svclb-…`: So ist es gewollt. `cluster-up.sh` schaltet den Traefik von k3s, seinen Helm-Controller, ServiceLB und den Load Balancer von k3d ab, weil die Übung sie nicht braucht. Den Zugang von außen ergänzt [04-cluster-network](../04-cluster-network/README.md) im selben Cluster.

## Aufräumen

```bash
./cluster-down.sh      # nach Termin 4: der Cluster trägt dann auch das Gateway
```

Wer mit [04-cluster-network](../04-cluster-network/README.md) weitermacht, lässt den Cluster stehen; angehalten kostet er nur Plattenplatz (`k3d cluster stop pf`).

## Fragen zum Weiterdenken

- Was geschieht, wenn ein Node ausfällt (`docker stop k3d-pf-agent-0`)? Wann entstehen die Pods neu?
- Warum gibt es Readiness und Liveness Probe getrennt?
- Wann lohnt ein Helm-Chart statt einfacher Manifeste?

Weiter mit [04-cluster-network](../04-cluster-network/README.md).
