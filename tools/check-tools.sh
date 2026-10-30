#!/usr/bin/env bash

# Show the versions of the course tools and check the minimum versions,
# and check that PlaceFinder is cloned next to this repository.
# Runs when the dev container is created; run it again at any time.
# Needs no config.env. The CLI of a cloud provider is checked by
# 01-account/check-cli.sh in the repository of that provider.
#
# Usage: tools/check-tools.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Without errexit: a missing tool is reported, and the script goes on with the
# next one
set -o nounset -o pipefail

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Absolute path of the folder above this script, i.e. of the repository
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# report <status> <tool> <text>
report() {
    local color=32
    # { ...; } groups commands: both run if the status is not OK (31 = red, 32 =
    # green)
    [[ "$1" == OK ]] || { color=31; failed=1; }
    # %-8s prints the text left-aligned in a column 8 characters wide
    printf '  \033[1;%sm%-8s\033[0m %-10s %s\n' "$color" "$1" "$2" "$3"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# version_ge 2.32.1 2.32 -> true
version_ge() {
    # Sort both versions as versions (2.9 before 2.10); if the minimum comes
    # first, the version is high enough
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort --version-sort | head --lines 1)" == "$2" ]]
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# check <tool> <minimum version or -> <command printing the version ...>
check() {
    local tool=$1 min=$2 version
    # shift 2 drops tool and minimum; "$@" is then the command that prints the
    # version
    shift 2
    if ! command -v "$tool" >/dev/null 2>&1; then
        report MISSING "$tool" "not installed"
        return
    fi

    # sed reads the whole output, so the tool never gets SIGPIPE
    # Run the command and keep the first number like 1.2 or 1.2.3 of its output
    version="$("$@" 2>&1 | grep --only-matching --extended-regexp '[0-9]+\.[0-9]+(\.[0-9]+)?' | sed --quiet 1p)"
    if [[ "$min" != - ]] && ! version_ge "${version:-0}" "$min"; then
        report "TOO OLD" "$tool" "${version:-unknown}, at least $min needed"
    else
        report OK "$tool" "${version:-installed}"
    fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

printf '\033[1;36m==>\033[0m Tools for the labs\n'
check python3   3.12 python3 --version
check uv        -    uv --version
check git       -    git --version
check curl      -    curl --version
check jq        -    jq --version
check dig       -    dig -v
check openssl   -    openssl version
check ssh       -    ssh -V
check shellcheck -   shellcheck --version
check docker    -    docker --version
check trivy     -    trivy --version
check syft      -    syft version
check cosign    -    cosign version
check kubectl   -    kubectl version --client
check helm      -    helm version --short
check k3d       -    k3d version
check psql      -    psql --version
check osm2pgsql -    osm2pgsql --version
check osmium    -    osmium --version
check pmtiles   -    pmtiles version
check tofu      1.10 tofu version
check gh        -    gh --version

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The Docker Engine of the dev container starts together with the container
if command -v docker >/dev/null 2>&1; then
    # Try for up to 30 seconds; _ is a variable whose value is not needed
    for _ in $(seq 1 30); do
        docker info >/dev/null 2>&1 && break
        sleep 1
    done

    if docker info >/dev/null 2>&1; then
        # --format picks one field of the output with a Go template
        report OK "dockerd" "Docker Engine $(docker info --format '{{.ServerVersion}}') is running"
    else
        report MISSING "dockerd" "Docker Engine does not answer (docker info)"
    fi
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# PlaceFinder next to this repository (/workspaces/placefinder)
placefinder="${PLACEFINDER_DIR:-$repo_root/../placefinder}"
if [[ -f "$placefinder/pyproject.toml" ]]; then
    report OK "placefinder" "$(cd "$placefinder" && pwd)"
else
    report MISSING "placefinder" "clone your fork next to this repository (00-setup)"
fi

if (( failed )); then
    printf '\n\033[1;31mSome tools are missing or too old.\033[0m Rebuild the dev container\n'
    printf '(VS Code: "Dev Containers: Rebuild Container") or install them.\n'
    exit 1
fi

printf '\nAll tools are ready. Next steps: 00-setup/README.md\n'
