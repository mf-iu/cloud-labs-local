#!/usr/bin/env bash

# Show the cache of PlaceFinder (tag t07 or later) at work: start PlaceFinder
# with Valkey from compose.yaml, send three searches twice each and compare
# Cache-Status and response times, run the smoke test (tools/smoke-test.sh)
# with the cache and show what Valkey holds. The server stops afterwards.
#
# Usage: ./test-cache.sh [--port <port>]
#   --port  port of the local server (default 8007)
#
# The places come from DATABASE_URL if it is set, otherwise from the local
# database (service db in compose.yaml of PlaceFinder) if it runs, otherwise
# from the GeoNames file in memory. Valkey runs as service valkey in the same
# compose.yaml (/workspaces/placefinder or PLACEFINDER_DIR); the script
# empties its cache first.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/common.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

USAGE="Usage: ./test-cache.sh [--port <port>]"
port=8007

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Go through the arguments one by one: case runs the branch whose pattern
# matches $1 (* matches anything), shift moves on to the next argument.
while (( $# )); do
    case "$1" in
        --port) (( $# > 1 )) || die "$USAGE"; port=$2; shift ;;
        *) die "Unknown argument $1. $USAGE" ;;
    esac
    shift
done

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require uv curl python3 docker

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

placefinder="$PLACEFINDER_DIR"

[[ -f "$placefinder/compose.yaml" ]] \
    || die "PlaceFinder not found in $placefinder. Clone your fork next to this repository."

# Does any file in src mention VALKEY_URL? --quiet: only the exit code counts.
grep --quiet --recursive VALKEY_URL "$placefinder/src" \
    || die "PlaceFinder in $placefinder has no cache yet. Finish the exercise or check out tag t07 (git switch --detach t07)."

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

compose() {
    docker compose --file "$placefinder/compose.yaml" "$@"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

vcli() {
    # Run valkey-cli in the container of the service valkey; -T: no terminal
    compose exec -T valkey valkey-cli "$@"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# the local database counts only if it runs
# No DATABASE_URL given, but the service db of compose.yaml runs: use the local
# database. --line-regexp matches only the whole line db.
if [[ -z "${DATABASE_URL:-}" ]] && compose ps --status running --services 2>/dev/null | grep --quiet --line-regexp db; then
    DATABASE_URL=$LOCAL_DATABASE_URL
fi
DATABASE_URL="${DATABASE_URL:-}"

base="http://127.0.0.1:$port"
if curl --silent --output /dev/null --max-time 2 "$base/"; then
    die "Port $port is in use. Stop the other server or choose another port, e.g. --port 8008."
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "Starting Valkey (service valkey in compose.yaml) and emptying the cache ..."
compose up --detach --wait valkey
vcli flushdb >/dev/null

tmp=$(mktemp --directory)
server=""

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Stop the server and remove the temporary folder; trap runs this function
# when the script ends (EXIT), also after an error or Ctrl+C
# shellcheck disable=SC2329  # called by the trap below
cleanup() {
    if [[ -n "$server" ]]; then
        # wait waits until the process has ended; || true: no error if it is
        # gone already
        kill "$server" 2>/dev/null || true   # uv passes the signal on to uvicorn
        wait "$server" 2>/dev/null || true
    fi
    rm --recursive --force "$tmp"
}

trap cleanup EXIT

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if [[ -n "$DATABASE_URL" ]]; then
    # ${DATABASE_URL##*@} removes everything up to the last @: user and password
    # do not show up
    store="the database at ${DATABASE_URL##*@}"
    # env is an array with the variables for the server
    env=(DATABASE_URL="$DATABASE_URL")
else
    store="the GeoNames file in memory"
    env=(DATA_FILE="$(download_cities)")
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "Starting PlaceFinder on port $port with $store and the cache in Valkey ..."
# ( ... ) runs in a subshell, so cd does not change the folder of this script.
# env sets the variables for uv; exec replaces the subshell, so that kill stops
# the server itself. & runs it all in the background.
(cd "$placefinder" && exec env "${env[@]}" VALKEY_URL=valkey://localhost:6379/0 \
    uv run uvicorn placefinder.main:app --host 127.0.0.1 --port "$port") >"$tmp/server.log" 2>&1 &
# $! is the process id of the last command started in the background
server=$!
start=$SECONDS

until curl --fail --silent --output /dev/null --max-time 2 "$base/health"; do
    # kill -0 sends no signal, it only checks that the process still runs
    if ! kill -0 "$server" 2>/dev/null || (( SECONDS - start > 120 )); then
        server=""
        tail --lines 15 "$tmp/server.log" >&2
        die "PlaceFinder did not start, see its output above."
    fi
    sleep 1
done

grep --max-count 1 "Caching searches" "$tmp/server.log" >&2 || warn "PlaceFinder does not report a cache."
log "GET /health $(curl --silent "$base/health")"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# one request: value of Cache-Status and time in milliseconds
# request <path>
request() {
    local seconds
    seconds=$(curl --silent --output /dev/null --dump-header "$tmp/headers" --max-time 30 \
                   --write-out '%{time_total}' "$base$1")
    # Find the header Cache-Status in the saved headers and print it with the
    # time in ms; :<36 and :6.1f set width and decimals
    python3 -c 'import sys
status = next((l.split(":", 1)[1].strip() for l in open(sys.argv[1])
               if l.lower().startswith("cache-status:")), "-")
print(f"{status:<36} {float(sys.argv[2]) * 1000:6.1f} ms")' "$tmp/headers" "$seconds"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "Each search twice: the first goes to the store, the second comes from Valkey"
for path in "/v1/places?q=Erfurt" "/v1/places?lon=11.03&lat=50.98&radius=25000" \
            "/v1/places?bbox=10.9,50.9,11.2,51.1&limit=100"; do
    for _ in 1 2; do
        printf '  %-52s %s\n' "GET $path" "$(request "$path")"
    done
done

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

result=0
# $? is the exit code of the last command; keep it and show the cache anyway
"$LOCAL_LABS/tools/smoke-test.sh" "$base" || result=$?

log "What Valkey holds now (keys, time to live, hits and misses, memory):"
# --scan lists the keys step by step, without blocking Valkey like KEYS would
vcli --scan --pattern 'placefinder:*' >"$tmp/keys"
printf '  %s keys, for example:\n' "$(wc --lines <"$tmp/keys")"
head --lines 3 "$tmp/keys" | sed 's/^/    /'
printf '  TTL of placefinder:v1:/v1/places?q=Erfurt: %s s\n' "$(vcli ttl 'placefinder:v1:/v1/places?q=Erfurt')"
# || true: no error if a line is missing
vcli info stats | grep --extended-regexp '^keyspace_(hits|misses)' || true
vcli info memory | grep '^used_memory_human' || true

# The exit code of the smoke test is the result of this script
exit "$result"
