#!/usr/bin/env bash
# Show the cache of PlaceFinder (tag t07 or later) at work: start PlaceFinder
# with Valkey from compose.yaml, send three searches twice each and compare
# Cache-Status and response times, run the smoke test (tools/smoke-test.sh)
# with the cache and show what Valkey holds. The server stops afterwards.
#
# Usage: ./test-cache.sh [--port <port>]
#   --port  port of the local server (default 8007)
# The places come from DATABASE_URL if it is set, otherwise from the local
# database (service db in compose.yaml of PlaceFinder) if it runs, otherwise
# from the GeoNames file in memory. Valkey runs as service valkey in the same
# compose.yaml (/workspaces/placefinder or PLACEFINDER_DIR); the script
# empties its cache first.
source "$(dirname "$0")/../lib/common.sh"

USAGE="Usage: ./test-cache.sh [--port <port>]"
port=8007
while (( $# )); do
  case "$1" in
    --port) (( $# > 1 )) || die "$USAGE"; port=$2; shift ;;
    *) die "Unknown argument $1. $USAGE" ;;
  esac
  shift
done
require uv curl python3 docker

placefinder="$PLACEFINDER_DIR"
[[ -f "$placefinder/compose.yaml" ]] \
  || die "PlaceFinder not found in $placefinder. Clone your fork next to this repository."
grep --quiet --recursive VALKEY_URL "$placefinder/src" \
  || die "PlaceFinder in $placefinder has no cache yet. Finish the exercise or check out tag t07 (git switch --detach t07)."
compose() { docker compose --file "$placefinder/compose.yaml" "$@"; }
vcli() { compose exec -T valkey valkey-cli "$@"; }

# the local database counts only if it runs
if [[ -z "${DATABASE_URL:-}" ]] && compose ps --status running --services 2>/dev/null | grep --quiet --line-regexp db; then
  DATABASE_URL=$LOCAL_DATABASE_URL
fi
DATABASE_URL="${DATABASE_URL:-}"
base="http://127.0.0.1:$port"
if curl --silent --output /dev/null --max-time 2 "$base/"; then
  die "Port $port is in use. Stop the other server or choose another port, e.g. --port 8008."
fi

log "Starting Valkey (service valkey in compose.yaml) and emptying the cache ..."
compose up --detach --wait valkey
vcli flushdb >/dev/null

tmp=$(mktemp --directory)
server=""
# shellcheck disable=SC2329  # called by the trap below
cleanup() {
  if [[ -n "$server" ]]; then
    kill "$server" 2>/dev/null || true   # uv passes the signal on to uvicorn
    wait "$server" 2>/dev/null || true
  fi
  rm --recursive --force "$tmp"
}
trap cleanup EXIT

if [[ -n "$DATABASE_URL" ]]; then
  store="the database at ${DATABASE_URL##*@}"
  env=(DATABASE_URL="$DATABASE_URL")
else
  store="the GeoNames file in memory"
  env=(DATA_FILE="$(download_cities)")
fi
log "Starting PlaceFinder on port $port with $store and the cache in Valkey ..."
(cd "$placefinder" && exec env "${env[@]}" VALKEY_URL=valkey://localhost:6379/0 \
  uv run uvicorn placefinder.main:app --host 127.0.0.1 --port "$port") >"$tmp/server.log" 2>&1 &
server=$!
start=$SECONDS
until curl --fail --silent --output /dev/null --max-time 2 "$base/health"; do
  if ! kill -0 "$server" 2>/dev/null || (( SECONDS - start > 120 )); then
    server=""
    tail --lines 15 "$tmp/server.log" >&2
    die "PlaceFinder did not start, see its output above."
  fi
  sleep 1
done
grep --max-count 1 "Caching searches" "$tmp/server.log" >&2 || warn "PlaceFinder does not report a cache."
log "GET /health $(curl --silent "$base/health")"

# one request: value of Cache-Status and time in milliseconds
request() {   # request <path>
  local seconds
  seconds=$(curl --silent --output /dev/null --dump-header "$tmp/headers" --max-time 30 \
    --write-out '%{time_total}' "$base$1")
  python3 -c 'import sys
status = next((l.split(":", 1)[1].strip() for l in open(sys.argv[1])
               if l.lower().startswith("cache-status:")), "-")
print(f"{status:<36} {float(sys.argv[2]) * 1000:6.1f} ms")' "$tmp/headers" "$seconds"
}
log "Each search twice: the first goes to the store, the second comes from Valkey"
for path in "/v1/places?q=Erfurt" "/v1/places?lon=11.03&lat=50.98&radius=25000" \
            "/v1/places?bbox=10.9,50.9,11.2,51.1&limit=100"; do
  for _ in 1 2; do
    printf '  %-52s %s\n' "GET $path" "$(request "$path")"
  done
done

result=0
"$LOCAL_LABS/tools/smoke-test.sh" "$base" || result=$?

log "What Valkey holds now (keys, time to live, hits and misses, memory):"
vcli --scan --pattern 'placefinder:*' >"$tmp/keys"
printf '  %s keys, for example:\n' "$(wc --lines <"$tmp/keys")"
head --lines 3 "$tmp/keys" | sed 's/^/    /'
printf '  TTL of placefinder:v1:/v1/places?q=Erfurt: %s s\n' "$(vcli ttl 'placefinder:v1:/v1/places?q=Erfurt')"
vcli info stats | grep --extended-regexp '^keyspace_(hits|misses)' || true
vcli info memory | grep '^used_memory_human' || true
exit "$result"
