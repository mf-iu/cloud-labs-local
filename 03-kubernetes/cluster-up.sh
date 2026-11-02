#!/usr/bin/env bash

# Create the local Kubernetes cluster with k3d: one server (control plane)
# and two agents (worker nodes), each a container in the Docker Engine of the
# dev container. Starts the cluster if it exists. Only what the labs need is
# switched on (see K3S_ARGS). Port 8443 leads to the gateway that
# ../04-cluster-network/gateway-up.sh adds later.
#
# Usage: ./cluster-up.sh [number_of_agents]   (default: 2)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/common.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

CLUSTER=pf

# Kubernetes version of the nodes; newer ones: https://docs.k3s.io/release-notes
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.36.5-k3s1}"

# Port 8443 of the dev container to node port 30443 of the server node, where
# the Traefik of 04-cluster-network listens for HTTPS
HTTPS_PORT=8443
GATEWAY_NODE_PORT=30443

number_of_agents="${1:-2}"

# Kept: CoreDNS (service names),
#       metrics-server (kubectl top, autoscaler),
#       local-path-provisioner (volumes, e.g. CloudNativePG) and the
#       network policy controller (NetworkPolicies, 04-cluster-network).
# Flannel (pod network), kube-proxy (services) and containerd run inside k3s on every node.
# Switched off: the Traefik of k3s and its Helm controller (04-cluster-network
# installs Traefik with Helm, in the version the course uses) and ServiceLB
# (the gateway is reached through the node port).
# An array of options for k3d; @server:* passes each one to the k3s of all
# server nodes
K3S_ARGS=(--k3s-arg "--disable=traefik@server:*"
          --k3s-arg "--disable=servicelb@server:*"
          --k3s-arg "--disable-helm-controller@server:*")
require docker k3d kubectl
docker info >/dev/null 2>&1 || die "Docker is not running. Use the terminal of the dev container."

# three nodes need about 1.5 to 2 GB of memory (Windows Subsystem for Linux,
# WSL: see .wslconfig)
# /proc/meminfo lists the memory of the machine in kB; awk takes the line
# MemAvailable and prints its value in MB
available=$(awk '/^MemAvailable/ { print int($2 / 1024) }' /proc/meminfo)
(( available >= 2500 )) || warn "Only ${available} MB of memory available; the cluster may be slow."

if k3d_cluster_exists "$CLUSTER"; then
    log "Cluster $CLUSTER exists; starting it in case it is stopped ..."

    k3d cluster start "$CLUSTER"

    # after a rebuild of the dev container the kubeconfig entry is gone
    k3d kubeconfig merge "$CLUSTER" --kubeconfig-merge-default \
                                    --kubeconfig-switch-context >/dev/null

    # created by an older version of this script?
    while read -r problem; do
        warn "Cluster $CLUSTER: $problem. Before 04-cluster-network: ./cluster-recreate.sh"
    # <(cmd) passes the output of cmd like a file; the loop reads it line by
    # line
    done < <(k3d_cluster_problems "$CLUSTER" "$HTTPS_PORT" "$GATEWAY_NODE_PORT")
else
    # tr turns the line breaks between the names into spaces
    users=$(port_users "$HTTPS_PORT" | tr '\n' ' ')
    [[ -z "$users" ]] \
        || die "Port $HTTPS_PORT is taken by: $users(cluster net of an earlier gateway demo? ./cluster-recreate.sh deletes it)"

    log "Creating cluster $CLUSTER with 1 server and $number_of_agents agents ($K3S_IMAGE) ..."
    # --no-lb: no load balancer container in front of the API, one server is
    # enough; the port goes straight to the server node
    # --port host:node@server:0:direct forwards port 8443 of the dev container
    # to node port 30443 of the first server node. "direct" publishes the port
    # on that node's container; the default "proxy" would need the load
    # balancer that --no-lb switches off.
    k3d cluster create "$CLUSTER" --agents "$number_of_agents" \
                                  --image "$K3S_IMAGE" \
                                  --no-lb "${K3S_ARGS[@]}" \
                                  --port "$HTTPS_PORT:$GATEWAY_NODE_PORT@server:0:direct"
fi

kubectl config use-context "k3d-$CLUSTER" >/dev/null

log "Waiting until all nodes are ready ..."
kubectl wait --for condition=Ready nodes --all --timeout 120s >/dev/null
kubectl get nodes --output wide

cat <<INFO

Next:    ./load-image.sh
         kubectl apply --filename ../../placefinder/deploy/k8s/
Remove:  ./cluster-down.sh
INFO
