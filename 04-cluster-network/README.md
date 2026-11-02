# 04 – Netze im Cluster: Gateway API, TLS, NetworkPolicies

**Ziel:** PlaceFinder ist über HTTPS erreichbar: Ein Gateway nach der Gateway API nimmt die Anfragen im Cluster `pf` entgegen, beendet TLS mit einem Zertifikat, das cert-manager aus einer eigenen Kurs-CA ausstellt, und leitet sie an den Service von PlaceFinder. NetworkPolicies lassen nur das Gateway zu PlaceFinder. Dazu die Diagnose einer HTTPS-Anfrage Schritt für Schritt.

In Termin 4 zeigt die Demo diesen Aufbau; für Teilnehmer ist der Schritt **Zusatz** – freiwillig und ohne Folgen für spätere Termine.

**Baut auf:** [03-kubernetes](../03-kubernetes/README.md) · **Stand:** `t03` oder später · **Kosten:** keine – alles läuft im Dev Container. Traefik und cert-manager brauchen zusätzlich rund 300 MB Arbeitsspeicher.

| Skript oder Datei | Aufgabe |
|---|---|
| `gateway-up.sh` | Gateway API, Traefik, PlaceFinder, cert-manager, Kurs-CA, Gateway und Route im Cluster `pf` einrichten; mehrfach aufrufbar |
| `gateway-down.sh` | alles davon wieder entfernen; der Cluster und PlaceFinder bleiben |
| `diagnose.sh` | DNS, TCP, TLS und Zertifikat eines Hosts anzeigen |
| `k8s/` | Werte für Traefik und cert-manager, Issuer, Gateway, HTTPRoute, NetworkPolicies |

**Vorher prüfen:** `../03-kubernetes/cluster-recreate.sh` vergleicht den Cluster `pf` mit der aktuellen Fassung von `cluster-up.sh`. Passt er, ändert das Skript nichts; stammt er von einer älteren Fassung (ohne Port 8443 oder NetworkPolicies), legt es ihn nach Rückfrage neu an und rollt PlaceFinder wieder aus.

## Gateway API und TLS

```bash
cd /workspaces/cloud-labs-local/04-cluster-network
./gateway-up.sh      # beim ersten Mal 3–5 Minuten
curl --cacert ../.state/course-ca.crt --resolve placefinder.test:8443:127.0.0.1 \
  "https://placefinder.test:8443/places?q=Erfurt"
```

`gateway-up.sh` baut die Demo aus Termin 4 nach:

1. Cluster `pf` aus [03-kubernetes](../03-kubernetes/README.md), angelegt oder gestartet mit `cluster-up.sh`. Port 8443 des Dev Containers führt auf Port 30443 des Server-Nodes.
2. Die Gateway API besteht aus Ressourcentypen (Custom Resource Definitions, CRDs) des Kubernetes-Projekts – `GatewayClass`, `Gateway`, `HTTPRoute` – und einer Implementierung. Das Skript installiert die Typen in Version 1.6.1 und Traefik mit Helm als Implementierung (`k8s/traefik-values.yaml`); Traefik legt die GatewayClass `traefik` an und lauscht auf Node-Port 30443.
3. PlaceFinder mit dem Manifest aus Termin 3 (`deploy/k8s/` im Repository `placefinder`); fehlt das Image, baut es `../03-kubernetes/load-image.sh`.
4. cert-manager mit Helm, Gateway-API-Unterstützung über `k8s/cert-manager-values.yaml`.
5. Eine eigene Kurs-CA in `../.state/course-ca.crt` (30 Tage gültig, wird danach neu angelegt) als Secret für den ClusterIssuer `k8s/issuer.yaml`.
6. Gateway (`k8s/gateway.yaml`) und HTTPRoute (`k8s/route.yaml`); cert-manager legt das Zertifikat `pf-tls` von selbst an, weil das Gateway eine Annotation dafür trägt.
7. Eine Anfrage über HTTPS, geprüft gegen die Kurs-CA.

`--resolve` ersetzt den DNS-Eintrag für `placefinder.test` (die Endung `.test` ist für Tests reserviert), `--cacert` vertraut der Kurs-CA. Ohne `--cacert` bricht `curl` mit einem Zertifikatsfehler ab; `curl --verbose` zeigt Handshake, Zertifikat und Aussteller.

```bash
kubectl get gatewayclass,gateway,httproute
kubectl describe certificate pf-tls       # ausgestellt von course-ca, Laufzeit, Erneuerung
openssl x509 -in ../.state/course-ca.crt -noout -subject -enddate
kubectl --namespace traefik get pods,services   # Traefik mit Node-Port 30443
```

**Gateway API statt Ingress:** Der ältere Typ `Ingress` beschreibt Eingang und Routen in einem Objekt. Die Gateway API trennt die Rollen: Die GatewayClass gehört dem Betreiber der Implementierung, das Gateway (Port, Hostname, Zertifikat) dem Betreiber des Clusters, die HTTPRoute dem Team der Anwendung.

## NetworkPolicies

```bash
kubectl apply --filename k8s/networkpolicies.yaml
curl --cacert ../.state/course-ca.crt --resolve placefinder.test:8443:127.0.0.1 \
  "https://placefinder.test:8443/places?q=Erfurt"          # geht weiter: über das Gateway
kubectl run test --rm --stdin --tty --image=busybox:1.37 -- \
  wget --timeout 3 --quiet --output-document - http://placefinder   # blockiert
kubectl delete --filename k8s/networkpolicies.yaml
```

`default-deny` verbietet allen Pods im Namespace `default` eingehenden Verkehr, `placefinder-from-gateway` erlaubt PlaceFinder Port 8000 aus dem Namespace `traefik`. k3s setzt NetworkPolicies mit einem eingebauten Controller durch; `cluster-up.sh` lässt ihn dafür eingeschaltet.

## Diagnose

```bash
./diagnose.sh                          # www.openstreetmap.org
./diagnose.sh https://<eigene-url>     # z. B. der Dienst beim Anbieter aus Termin 3
```

Das Skript zeigt nacheinander die DNS-Antwort mit TTL und Resolver, die Delegation ab der Root-Zone (`dig +trace`), Verbindungsaufbau und TLS-Handshake (`curl --verbose`), die Zeit bis zu jedem Schritt (`curl --write-out`) und die Zertifikatskette (`openssl s_client`). Blockiert das Netz DNS-Anfragen an andere Server als den eigenen Resolver (manche Firmen- und Hochschulnetze), bleibt der Abschnitt `dig +trace` leer.

## Typische Probleme

- `Cluster pf was created by an older cluster-up.sh`: Dem Cluster fehlen Port 8443 oder NetworkPolicies, oder er hat noch den Traefik von k3s. `../03-kubernetes/cluster-recreate.sh` legt ihn neu an und rollt PlaceFinder wieder aus, danach `./gateway-up.sh`.
- Keine GatewayClass `traefik`: `kubectl --namespace traefik get pods` – läuft Traefik? `kubectl --namespace traefik logs deployment/traefik` zeigt Fehler beim Gateway-Provider.
- Zertifikat nicht `Ready`: `kubectl describe certificate pf-tls` und `kubectl --namespace cert-manager logs deployment/cert-manager`.
- `curl` erreicht nichts: Läuft der Befehl im Terminal des Dev Containers? Port 8443 gibt es nur dort.
- Pods bleiben `Pending`: Mit Traefik und cert-manager wird der Speicher knapp; `kubectl describe pod <name>` zeigt den Grund.

## Aufräumen

```bash
./gateway-down.sh                      # Gateway, cert-manager und Traefik; der Cluster bleibt
../03-kubernetes/cluster-down.sh       # oder gleich den ganzen Cluster
```

## Fragen zum Weiterdenken

- Wo endet TLS in diesem Aufbau, und was müsste man tun, damit auch der Weg vom Gateway zum Pod verschlüsselt ist?
- Warum vertraut der Browser der Kurs-CA nicht, und was ändert ein ACME-Issuer wie Let's Encrypt daran?
- Welche Firewall-Regel aus der Netz-Übung beim Anbieter (Termin 4) entspricht `placefinder-from-gateway`?

Weiter mit [05-rest-api](../05-rest-api/README.md).
