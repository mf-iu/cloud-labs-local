#!/usr/bin/env bash

# Build the PlaceFinder image from the repository next to this one and load
# it into the nodes of the k3d cluster pf. The nodes run their own containerd
# and do not see the images of Docker.
#
# Usage: ./load-image.sh [version]   (default: version in pyproject.toml of PlaceFinder)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/common.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

CLUSTER=pf

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require docker k3d python3

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The version given as argument, otherwise the one in pyproject.toml of
# PlaceFinder
version=${1:-$(placefinder_version)}
image="placefinder:$version"

k3d_cluster_exists "$CLUSTER" || die "No k3d cluster $CLUSTER. Run ./cluster-up.sh first."

build_placefinder_image "$version"

log "Importing $image into the nodes of cluster $CLUSTER ..."
k3d image import "$image" --cluster "$CLUSTER"

log "Done: $image"
