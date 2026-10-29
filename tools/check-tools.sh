#!/usr/bin/env bash
# Show the versions of the course tools and check the minimum versions,
# and check that PlaceFinder is cloned next to this repository.
# Runs when the dev container is created; run it again at any time.
# Needs no config.env. The CLI of a cloud provider is checked by
# 01-account/check-cli.sh in the repository of that provider.
# Usage: tools/check-tools.sh
set -o nounset -o pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

report() {   # report <status> <tool> <text>
  local color=32
  [[ "$1" == OK ]] || { color=31; failed=1; }
  printf '  \033[1;%sm%-8s\033[0m %-10s %s\n' "$color" "$1" "$2" "$3"
}

# version_ge 2.32.1 2.32 -> true
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort --version-sort | head --lines 1)" == "$2" ]]; }

# check <tool> <minimum version or -> <command printing the version ...>
check() {
  local tool=$1 min=$2 version
  shift 2
  if ! command -v "$tool" >/dev/null 2>&1; then
    report MISSING "$tool" "not installed"
    return
  fi
  # sed reads the whole output, so the tool never gets SIGPIPE
  version="$("$@" 2>&1 | grep --only-matching --extended-regexp '[0-9]+\.[0-9]+(\.[0-9]+)?' | sed --quiet 1p)"
  if [[ "$min" != - ]] && ! version_ge "${version:-0}" "$min"; then
    report "TOO OLD" "$tool" "${version:-unknown}, at least $min needed"
  else
    report OK "$tool" "${version:-installed}"
  fi
}

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

# The Docker Engine of the dev container starts together with the container
if command -v docker >/dev/null 2>&1; then
  for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 1
  done
  if docker info >/dev/null 2>&1; then
    report OK "dockerd" "Docker Engine $(docker info --format '{{.ServerVersion}}') is running"
  else
    report MISSING "dockerd" "Docker Engine does not answer (docker info)"
  fi
fi

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
