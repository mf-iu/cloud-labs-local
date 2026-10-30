#!/usr/bin/env bash

# Build the PlaceFinder image from the repository next to this one and upload
# it to the GitHub Container Registry, from where the container services of
# the cloud (session 3 on) and other computers can pull it.
#
# Usage: ./publish-image.sh [--tag <name>] [version]
#   version  image tag, default: version in pyproject.toml of PlaceFinder
#   --tag    second tag, the name of the course state, default: t03
#            (the state the container service of session 3 runs; t05 for
#            session 5 ...)
#
# Pushes $PLACEFINDER_IMAGE:<version> and $PLACEFINDER_IMAGE:<name>.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/common.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

USAGE="Usage: ./publish-image.sh [--tag <name>] [version]"
state_tag=t03
version=""

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Go through the arguments one by one: case runs the branch whose pattern
# matches $1 (* matches anything), shift moves on to the next argument.
while (( $# )); do
    case "$1" in
        --tag) (( $# > 1 )) || die "$USAGE"; state_tag=$2; shift ;;
        -*) die "Unknown option $1. $USAGE" ;;
        *) version=$1 ;;
    esac
    shift
done

require docker python3 gh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# check before the build, which takes a while
require_github_user
gh auth status >/dev/null 2>&1 || die "Not logged in to GitHub. Run: gh auth login"
# gh auth status lists the scopes of the token on stderr, hence 2>&1
gh auth status 2>&1 | grep --quiet "write:packages" \
    || die "The GitHub token cannot upload packages. Run: gh auth refresh --scopes write:packages"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# If no version is given, extract it from PlaceFinder's pyproject.toml
version=${version:-$(placefinder_version)}

image="placefinder:$version"
build_placefinder_image "$version"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "Logging in to ghcr.io as $GITHUB_USER ..."
# gh prints its token; --password-stdin lets docker read it from the pipe, so it
# never shows up in the process list
gh auth token | docker login ghcr.io --username "$GITHUB_USER" --password-stdin >/dev/null

log "Pushing PlaceFinder image to ghcr.io ..."
for tag in "$version" "$state_tag"; do
    docker tag "$image" "$PLACEFINDER_IMAGE:$tag"
    docker push "$PLACEFINDER_IMAGE:$tag"
done

if check_public_image "$PLACEFINDER_IMAGE:$state_tag"; then
    log "$PLACEFINDER_IMAGE:$state_tag is public."
else
    warn "$PLACEFINDER_IMAGE is private. Make it public on GitHub: Packages → placefinder → Package settings → Change visibility."
fi

log "Done: $PLACEFINDER_IMAGE:$version and :$state_tag"
