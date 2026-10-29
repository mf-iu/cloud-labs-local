#!/usr/bin/env bash
# Remove what gateway-up.sh added to cluster pf: Gateway, HTTPRoute, issuer,
# NetworkPolicies, cert-manager and Traefik. The cluster and PlaceFinder
# stay; ../03-kubernetes/cluster-down.sh deletes everything. The course CA
# stays in .state for the next run; it is valid for 30 days.
# Usage: ./gateway-down.sh
source "$(dirname "$0")/../lib/common.sh"

CLUSTER=pf
K8S="$(cd "$(dirname "$0")" && pwd)/k8s"
require k3d kubectl helm
if ! k3d_cluster_exists "$CLUSTER"; then
  log "No cluster $CLUSTER."
  exit 0
fi
confirm "Remove gateway, cert-manager and Traefik from cluster $CLUSTER?" || exit 0
kubectl config use-context "k3d-$CLUSTER" >/dev/null
kubectl delete --ignore-not-found --filename "$K8S/networkpolicies.yaml" \
  --filename "$K8S/route.yaml" --filename "$K8S/gateway.yaml" --filename "$K8S/issuer.yaml" 2>/dev/null || true
kubectl delete secret pf-tls --ignore-not-found
for release in cert-manager traefik; do
  if helm status "$release" --namespace "$release" >/dev/null 2>&1; then
    helm uninstall "$release" --namespace "$release" --wait
  fi
  kubectl delete namespace "$release" --ignore-not-found
done
log "Done. The CRDs of the Gateway API and cert-manager stay; cluster-down.sh removes them with the cluster."
