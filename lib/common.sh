#!/usr/bin/env bash

# Shared helpers for all lab scripts: the ones in this repository and the
# ones in the provider repositories, which source this file through their
# lib/provider.sh. Nothing in here knows a cloud provider.
# Source this file from a script; do not execute it directly.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Shell idioms used in all lab scripts, explained once here:
#
#   cmd || die "..."    die runs only if cmd fails (exit code other than 0)
#   cmd && next         next runs only if cmd succeeds
#   [[ -f path ]]       test: -f file exists, -s file is not empty,
#                       -n text is not empty, -z text is empty; == compares
#                       texts, also with patterns: * stands for any text
#   x=$(cmd)            x gets the output of cmd
#   >/dev/null 2>&1     discard the output (stdout, 1) and errors (stderr, 2)
#   2>/dev/null         discard only the error messages
#   >&2                 write to stderr instead of stdout
#   $1, $2, $#          first and second argument, number of arguments
#   "$@"                all arguments, each one kept as it is (with spaces)
#   ${x:-default}       the value of x, or default if x is not set or empty
#   local x             a variable that exists only inside the function
#   (( a > b ))         arithmetic with whole numbers
#   cmd \               the command goes on in the next line
#   <<EOF ... EOF       a text of several lines as input of a command
#                       (heredoc); with <<'EOF', $x in it is not replaced

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Stop at the first command that fails (errexit), also inside functions and
# subshells (errtrace), at a variable that is not set (nounset) and when any
# command of a pipeline fails (pipefail), not only the last one.
set -o errexit -o errtrace -o nounset -o pipefail

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# This repository. REPO_ROOT is the repository of the calling script.
# A provider repository sets it before sourcing this file.
# ${BASH_SOURCE[0]} is this file, even when another script sources it; cd into
# its parent folder and pwd give the absolute path.
LOCAL_LABS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$LOCAL_LABS}"

# Ids of created resources, per repository
STATE_DIR="$REPO_ROOT/.state"

# Downloads (GeoNames, OpenStreetMap, map tiles) exist only here
DATA_DIR="$LOCAL_LABS/.state/data"
# --parents: no error if the folders exist; missing parent folders are created
mkdir --parents "$STATE_DIR" "$DATA_DIR"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# PlaceFinder next to this repository (/workspaces/placefinder in the dev
# container), or wherever PLACEFINDER_DIR points
# realpath turns the path into an absolute one without ../, --canonicalize-
# missing even if the folder does not exist (yet)
PLACEFINDER_DIR="$(realpath --canonicalize-missing "${PLACEFINDER_DIR:-$LOCAL_LABS/../placefinder}")"

# PostgreSQL with PostGIS, service db in compose.yaml of PlaceFinder
# shellcheck disable=SC2034  # used by 06-postgis and 07-cache-and-storage
LOCAL_DATABASE_URL="postgresql://pf:pf@localhost:5432/pf"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Personal settings (copied from config.example.env, never committed).
# Most local scripts need none; those that do check the values themselves.
if [[ -f "$LOCAL_LABS/config.env" ]]; then
    # source runs the file in this shell, so the variables it sets stay set here
    # shellcheck source=/dev/null
    source "$LOCAL_LABS/config.env"
fi

GITHUB_USER="${GITHUB_USER:-}"

# Image names must be lowercase, GitHub user names need not be
PLACEFINDER_IMAGE="${PLACEFINDER_IMAGE:-}"
# ${x,,} is the value of x in lowercase
PLACEFINDER_IMAGE="${PLACEFINDER_IMAGE,,}"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log() {
    # printf replaces %s with the message ("$*": all arguments as one text);
    # \033[...m are ANSI codes for colour and bold, \033[0m resets them. >&2: to
    # stderr, so that stdout stays free for results.
    printf '\033[1;36m==>\033[0m %s\n' "$*" >&2
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

warn() {
    printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

die() {
    printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2
    exit 1
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# trap runs the quoted command whenever a command fails (ERR); $LINENO and
# $BASH_COMMAND are the line and the text of the failed command
trap 'warn "Command failed in line $LINENO: $BASH_COMMAND"' ERR

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Fail early if a required command is missing
require() {
    local cmd
    for cmd in "$@"; do
        # command -v prints the path of a program and fails if there is none
        command -v "$cmd" >/dev/null 2>&1 || die "Command not found: $cmd"
    done
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Ask before doing something expensive or destructive.
# Set ASSUME_YES=1 to skip all questions.
confirm() {
    # ASSUME_YES=1 answers every question with yes; return 0 means success
    [[ "${ASSUME_YES:-0}" == 1 ]] && return 0

    local answer
    # -p shows the question, -r keeps backslashes in the answer
    read -r -p "$1 [y/N] " answer
    # =~ compares with a regular expression: does the answer start with y, Y, j
    # or J? The result of the last command is the result of the function.
    [[ "$answer" =~ ^[yYjJ] ]]
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Fail with a hint if config.env lacks the GitHub user
require_github_user() {
    [[ -n "$GITHUB_USER" && "$GITHUB_USER" != your-github-user ]] \
        || die "Set GITHUB_USER in $LOCAL_LABS/config.env (copy config.example.env first)."
    # Only if PLACEFINDER_IMAGE is empty: derive it from the GitHub user
    [[ -n "$PLACEFINDER_IMAGE" ]] || PLACEFINDER_IMAGE="ghcr.io/${GITHUB_USER,,}/placefinder"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# State files remember the ids of created resources for later scripts
state_file() {
    echo "$STATE_DIR/$1.env"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# save_state <lab> <key> <value>
save_state() {
    # Appends (>>) a line KEY=value; %q quotes the value so that load_state can
    # read it back with source, even with spaces in it
    printf '%s=%q\n' "$2" "$3" >>"$(state_file "$1")"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# load_state <lab>
load_state() {
    local file
    file="$(state_file "$1")"
    if [[ -f "$file" ]]; then
        # defines the variables saved by save_state, e.g. INSTANCE_ID
        # shellcheck source=/dev/null
        source "$file"
    fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

clear_state() {
    rm --force "$(state_file "$1")"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Replace a placeholder like __REPO__ in a template file and print the result
# render <file> KEY=value ...
render() {
    local file=$1 text pair
    # shift drops the first argument; "$@" then holds only the KEY=value pairs
    shift

    # bash 5.2 would otherwise treat "&" in the value as the matched text
    shopt -u patsub_replacement 2>/dev/null || true

    text="$(cat "$file")"
    for pair in "$@"; do
        # ${pair%%=*} is the text before the first "=" (KEY), ${pair#*=} the
        # text after it (value); ${text//a/b} replaces every a in text with b
        text="${text//__${pair%%=*}__/${pair#*=}}"
    done

    printf '%s\n' "$text"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Check that a Git repository can be cloned anonymously and contains the tag
# or branch, e.g. before a new machine clones it
# check_repo_ref <repository url> <tag or branch>
check_repo_ref() {
    local repo=$1 ref=$2
    log "Checking $repo for '$ref' ..."
    # A variable set right before a command applies to that command only. git
    # must not ask for a password, and -c credential.helper= ignores saved
    # credentials: the check sees the repository as a new machine does.
    GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote --exit-code \
        "$repo" "refs/tags/$ref" "refs/heads/$ref" >/dev/null 2>&1 \
        || die "Cannot read '$ref' from $repo. Check GITHUB_USER in config.env, make the repository public and push the tags (git push origin --tags)."
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Digest of an image on ghcr.io that can be pulled without logging in, e.g.
# sha256:4f2c...; fails if the image does not exist or is private. New
# packages on GitHub are private until their visibility is changed.
# public_image_digest <ghcr.io/owner/name:tag or @digest>
public_image_digest() {
    local image=$1 repo ref token
    [[ "$image" == ghcr.io/* ]] || return 1

    # Split the image name. ${x#a} removes a from the start of x, ${x%a} from
    # the end; ## and %% remove the longest match, * stands for any text.
    # ghcr.io/o/n:t03 gives repo o/n and ref t03, ghcr.io/o/n@sha256:... gives
    # ref sha256:...
    repo=${image#ghcr.io/}
    if [[ "$repo" == *@* ]]; then
        ref=${repo#*@} repo=${repo%%@*}
    elif [[ "${repo##*/}" == *:* ]]; then
        ref=${repo##*:} repo=${repo%:*}
    else
        ref=latest
    fi

    # Anonymous token for reading the repository; python3 prints the field token
    # of the JSON answer
    token=$(curl --fail --silent --max-time 10 "https://ghcr.io/token?scope=repository:$repo:pull" \
        | python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])' 2>/dev/null) || return 1

    # HEAD request: only the headers of the manifest. tr removes the carriage
    # returns at the line ends of HTTP; awk prints the value of the header
    # Docker-Content-Digest and fails (exit 1) if there is none.
    curl --fail --silent --head --max-time 10 \
         --header "Authorization: Bearer $token" \
         --header "Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json" \
         "https://ghcr.io/v2/$repo/manifests/$ref" \
         | tr --delete '\r' | awk 'tolower($1) == "docker-content-digest:" { print $2; found = 1 } END { exit !found }'
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Check that an image can be pulled without logging in; images outside ghcr.io are not checked.
# check_public_image <ghcr.io/owner/name:tag>
check_public_image() {
    [[ "$1" == ghcr.io/* ]] || return 0
    public_image_digest "$1" >/dev/null
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Version in pyproject.toml of PlaceFinder, e.g. 0.5.0
placefinder_version() {
    [[ -f "$PLACEFINDER_DIR/pyproject.toml" ]] \
        || die "PlaceFinder not found in $PLACEFINDER_DIR. Clone your fork next to this repository (or set PLACEFINDER_DIR)."
    # tomllib is the TOML parser of Python; sys.argv[1] is the path given after
    # the program
    python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["project"]["version"])' \
        "$PLACEFINDER_DIR/pyproject.toml"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Build placefinder:<version> from the checked-out state of PlaceFinder
# build_placefinder_image <version>
build_placefinder_image() {
    require docker
    [[ -f "$PLACEFINDER_DIR/Dockerfile" ]] \
        || die "No Dockerfile in $PLACEFINDER_DIR. PlaceFinder needs tag t02 or later."
    log "Building placefinder:$1 from $PLACEFINDER_DIR ..."
    docker build --tag "placefinder:$1" "$PLACEFINDER_DIR"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Does a local k3d cluster with this name exist?
# k3d_cluster_exists <name>
k3d_cluster_exists() {
    # python3 ends with exit code 0 (success) if a cluster in the JSON list has
    # this name, otherwise with 1
    k3d cluster list --output json 2>/dev/null \
        | python3 -c 'import json, sys; sys.exit(not any(c["name"] == sys.argv[1] for c in json.load(sys.stdin)))' "$1"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Print why an existing k3d cluster does not match 03-kubernetes/cluster-up.sh,
# one reason per line; print nothing if it matches. Reads the server container,
# so it also works while the cluster is stopped. Neither a port nor the k3s
# options can be changed later: a cluster that does not match must be created
# anew (03-kubernetes/cluster-recreate.sh).
# k3d_cluster_problems <name> <host port> <node port>
k3d_cluster_problems() {
    local server="k3d-$1-server-0" args
    # --format picks fields of the container with a Go template: here the
    # arguments the server node started with. { ...; } groups two commands: both
    # run if docker inspect fails.
    args=$(docker inspect --format '{{join .Config.Cmd " "}}' "$server" 2>/dev/null) \
        || { echo "no server container $server"; return 0; }

    # port bindings of the server node: {"30443/tcp": [{"HostIp": "", "HostPort": "8443"}]}
    # python3 ends with exit code 0 if the host port leads to the node port
    docker inspect --format '{{json .HostConfig.PortBindings}}' "$server" \
        | python3 -c 'import json, sys; b = json.load(sys.stdin) or {}; sys.exit(not any(x.get("HostPort") == sys.argv[1] for x in b.get(sys.argv[2] + "/tcp") or []))' "$2" "$3" \
        || echo "port $2 does not lead to node port $3 (needed for the gateway of 04-cluster-network)"

    # *x* means "contains x"; the spaces around $args and the option find it
    # only as a whole word
    [[ " $args " != *" --disable-network-policy "* ]] \
        || echo "the network policy controller is switched off (NetworkPolicies of 04-cluster-network have no effect)"
    [[ " $args " == *" --disable=traefik "* ]] \
        || echo "the Traefik of k3s runs (it competes with the Traefik that 04-cluster-network installs)"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Names of the containers that publish this port of the dev container
# port_users <host port>
port_users() {
    # awk prints the first field (the name) of every line that contains
    # :<port>->, as in 0.0.0.0:8443->30443/tcp
    docker ps --format '{{.Names}} {{.Ports}}' | awk -v port=":$1->" 'index($0, port) { print $1 }'
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Wait until a URL answers with a 2xx or 3xx status. Failed attempts are
# expected while a new server installs the application, so they are not
# printed; a progress line appears once a minute.
# wait_for_http <url> [timeout seconds]
wait_for_http() {
    # $SECONDS counts the seconds since the shell started
    local url=$1 timeout=${2:-300} start=$SECONDS
    log "Waiting for $url (up to ${timeout}s; no answer yet is normal at first) ..."

    # until repeats the loop as long as the command fails; --fail makes curl
    # fail on HTTP errors such as 502
    until curl --fail --silent --output /dev/null --max-time 5 "$url"; do
        if (( SECONDS - start > timeout )); then
            warn "No answer from $url after ${timeout}s"
            return 1
        fi

        sleep 10

        # Once a minute: the remainder of the seconds divided by 60 is below 10,
        # and one round takes 10 seconds
        if (( (SECONDS - start) % 60 < 10 )); then
            log "... still waiting ($(( (SECONDS - start) / 60 )) min)"
        fi
    done

    log "$url answers after $(( SECONDS - start ))s."
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Download a GeoNames dump (CC BY 4.0) into .state/data and print the path of
# its text file, e.g. download_geonames DE -> .state/data/DE.txt
# download_geonames <name>
download_geonames() {
    local name=$1 txt="$DATA_DIR/$1.txt"
    if [[ ! -s "$txt" ]]; then
        log "Downloading $name from GeoNames ..."
        curl --fail --silent --show-error --location --output "$DATA_DIR/$name.zip" "https://download.geonames.org/export/dump/$name.zip"
        # Unpack with Python; unzip is not installed everywhere
        python3 -m zipfile --extract "$DATA_DIR/$name.zip" "$DATA_DIR"
    fi
    echo "$txt"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Download GeoNames cities15000 into .state/data
download_cities() {
    download_geonames cities15000
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Run psql locally or, if it is not installed, in a container
psql_run() {
    if command -v psql >/dev/null 2>&1; then
        psql "$@"
    else
        require docker
        # --network host: the container reaches the database on localhost. The
        # volumes show both repositories at the same path inside the container,
        # so psql finds files given as arguments. --env PGOPTIONS passes the
        # options of the caller on.
        docker run --rm --interactive --network host --env PGOPTIONS \
            --volume "$LOCAL_LABS:$LOCAL_LABS" --volume "$REPO_ROOT:$REPO_ROOT" --workdir "$PWD" \
            postgres:18-alpine psql "$@"
    fi
}
