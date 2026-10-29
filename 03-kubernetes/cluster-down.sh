#!/usr/bin/env bash
# Delete the local k3d cluster with everything running in it.
# The images stay in Docker (docker images placefinder).
# Usage: ./cluster-down.sh
source "$(dirname "$0")/../lib/common.sh"

CLUSTER=pf
require k3d
if ! k3d_cluster_exists "$CLUSTER"; then
  log "No cluster $CLUSTER."
  exit 0
fi
confirm "Delete the k3d cluster $CLUSTER with all pods?" || exit 0
k3d cluster delete "$CLUSTER"
log "Done."
