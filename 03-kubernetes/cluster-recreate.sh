#!/usr/bin/env bash
# Bring the local cluster pf up to the state that 04-cluster-network needs.
# A cluster created by an older version of cluster-up.sh lacks port 8443 or
# NetworkPolicies, or still runs the Traefik of k3s; none of this can be
# changed in an existing cluster. The script checks the cluster and, only if
# it does not match cluster-up.sh, deletes it and creates it anew with the
# same number of agents. PlaceFinder from deploy/k8s is deployed again if it
# ran before; Helm releases and the autoscaler are not. It also deletes the
# cluster net of the earlier gateway demo, which holds port 8443.
# Usage: ./cluster-recreate.sh [--force] [agents]
#   --force   create the cluster anew even if it matches
#   agents    number of agents, default: as many as the cluster has now
source "$(dirname "$0")/../lib/common.sh"

CLUSTER=pf
OLD_DEMO_CLUSTER=net                              # gateway demo before cloud-labs-local
HTTPS_PORT=8443                                   # see cluster-up.sh
GATEWAY_NODE_PORT=30443
HERE=$(cd "$(dirname "$0")" && pwd)
MANIFEST="$PLACEFINDER_DIR/deploy/k8s/placefinder.yaml"
USAGE="Usage: ./cluster-recreate.sh [--force] [agents]"
force=0
agents=""
while (( $# )); do
  case "$1" in
    --force) force=1 ;;
    -*) die "Unknown option $1. $USAGE" ;;
    *) [[ "$1" =~ ^[0-9]+$ ]] || die "$USAGE"; agents=$1 ;;
  esac
  shift
done
require docker k3d kubectl python3
docker info >/dev/null 2>&1 || die "Docker is not running. Use the terminal of the dev container."

# 1 The cluster of the earlier gateway demo publishes port 8443 as well
if k3d_cluster_exists "$OLD_DEMO_CLUSTER"; then
  warn "Cluster $OLD_DEMO_CLUSTER of the earlier gateway demo exists; it holds port $HTTPS_PORT."
  confirm "Delete cluster $OLD_DEMO_CLUSTER?" || die "Cluster $CLUSTER needs port $HTTPS_PORT."
  k3d cluster delete "$OLD_DEMO_CLUSTER"
fi

# 2 Does cluster pf match cluster-up.sh?
if ! k3d_cluster_exists "$CLUSTER"; then
  log "No cluster $CLUSTER yet; creating it."
  exec "$HERE/cluster-up.sh" ${agents:+"$agents"}
fi
mapfile -t problems < <(k3d_cluster_problems "$CLUSTER" "$HTTPS_PORT" "$GATEWAY_NODE_PORT")
if (( ${#problems[@]} == 0 && ! force )); then
  log "Cluster $CLUSTER matches cluster-up.sh; nothing to do."
  exit 0
fi
for problem in "${problems[@]}"; do
  warn "Cluster $CLUSTER: $problem"
done

# 3 What runs in it now: agents, PlaceFinder, Helm releases
agents=${agents:-$(docker ps --all --quiet --filter "label=k3d.cluster=$CLUSTER" \
  --filter "label=k3d.role=agent" | wc --lines)}
redeploy=false
releases=""
log "Starting cluster $CLUSTER to see what runs in it ..."
if k3d cluster start "$CLUSTER" >/dev/null 2>&1 \
   && k3d kubeconfig merge "$CLUSTER" --kubeconfig-merge-default --kubeconfig-switch-context >/dev/null; then
  if kubectl get deployment placefinder >/dev/null 2>&1 && [[ -f "$MANIFEST" ]]; then
    redeploy=true
  fi
  if command -v helm >/dev/null 2>&1; then
    releases=$(helm list --all-namespaces --short 2>/dev/null | tr '\n' ' ')
  fi
else
  warn "Cluster $CLUSTER does not start; PlaceFinder will not be deployed again."
fi

echo
echo "Cluster $CLUSTER will be deleted and created anew with $agents agents."
if $redeploy; then
  echo "PlaceFinder is deployed again from deploy/k8s/."
fi
if [[ -n "$releases" ]]; then
  echo "Not restored: Helm releases $releases(04-cluster-network/gateway-up.sh installs its own again)."
fi
echo "Everything else running in the cluster is lost; the images stay in Docker."
confirm "Continue?" || exit 0

# 4 Delete and create
ASSUME_YES=1 "$HERE/cluster-down.sh"
"$HERE/cluster-up.sh" "$agents" >/dev/null
problems=()
mapfile -t problems < <(k3d_cluster_problems "$CLUSTER" "$HTTPS_PORT" "$GATEWAY_NODE_PORT")
(( ${#problems[@]} == 0 )) || die "The new cluster $CLUSTER does not match: ${problems[*]}"

# 5 PlaceFinder again, with the image the manifest names
if $redeploy; then
  image=$(grep --only-matching --max-count 1 'placefinder:[0-9][0-9a-z.]*' "$MANIFEST")
  if docker image inspect "$image" >/dev/null 2>&1; then
    log "Importing $image into the nodes ..."
    k3d image import "$image" --cluster "$CLUSTER"
  else
    "$HERE/load-image.sh" "${image#placefinder:}"
  fi
  kubectl apply --filename "$PLACEFINDER_DIR/deploy/k8s/"
  kubectl rollout status deployment/placefinder --timeout 180s
fi

kubectl get nodes
cat <<INFO

Cluster $CLUSTER is ready for 04-cluster-network.
Next:    ../04-cluster-network/gateway-up.sh
INFO
