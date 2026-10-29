#!/usr/bin/env bash
# Start PlaceFinder (tag t06 or later) on this computer with the database
# and check its API with the smoke test (tools/smoke-test.sh): the same API as with
# the places in memory, now answered from PostgreSQL with PostGIS. At the end,
# response times of three typical requests; the server stops afterwards.
#
# Usage: ./test-api.sh [--port <port>]
#   --port  port of the local server (default 8006)
# Uses DATABASE_URL if it is set, otherwise the local database from
# compose.yaml of PlaceFinder (service db). PlaceFinder is expected next to
# this repository (/workspaces/placefinder), or in PLACEFINDER_DIR.
source "$(dirname "$0")/../lib/common.sh"

USAGE="Usage: ./test-api.sh [--port <port>]"
port=8006
while (( $# )); do
  case "$1" in
    --port) (( $# > 1 )) || die "$USAGE"; port=$2; shift ;;
    *) die "Unknown argument $1. $USAGE" ;;
  esac
  shift
done

DATABASE_URL="${DATABASE_URL:-$LOCAL_DATABASE_URL}"
require uv curl python3

placefinder="$PLACEFINDER_DIR"
[[ -f "$placefinder/pyproject.toml" ]] \
  || die "PlaceFinder not found in $placefinder. Clone your fork next to this repository."
grep --quiet --recursive DATABASE_URL "$placefinder/src" \
  || die "PlaceFinder in $placefinder does not read DATABASE_URL yet. Finish the exercise or check out tag t06 (git switch --detach t06)."
base="http://127.0.0.1:$port"
if curl --silent --output /dev/null --max-time 2 "$base/"; then
  die "Port $port is in use. Stop the other server or choose another port, e.g. --port 8007."
fi

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

log "Starting PlaceFinder from $(realpath "$placefinder") on port $port ..."
# DATA_FILE names a file that does not exist: a PlaceFinder that ignored
# DATABASE_URL and loaded the places from its file would not start.
(cd "$placefinder" && DATABASE_URL="$DATABASE_URL" DATA_FILE="$tmp/no-such-file.txt" \
  exec uv run uvicorn placefinder.main:app --host 127.0.0.1 --port "$port") >"$tmp/server.log" 2>&1 &
server=$!

start=$SECONDS
until curl --fail --silent --output /dev/null --max-time 2 "$base/health"; do
  if ! kill -0 "$server" 2>/dev/null; then
    server=""
    tail --lines 15 "$tmp/server.log" >&2
    if grep --quiet "timeout expired" "$tmp/server.log"; then
      warn "The database does not answer. Is it running? A database in the cloud may no longer accept your IP address."
    fi
    die "PlaceFinder did not start, see its output above."
  fi
  if (( SECONDS - start > 120 )); then
    tail --lines 15 "$tmp/server.log" >&2
    die "No answer from PlaceFinder after 120 s."
  fi
  sleep 1
done
log "PlaceFinder answers after $(( SECONDS - start )) s: GET /health $(curl --silent "$base/health")"
# the log line of the sample solution, e.g. "Using PostGIS at <host>:5432/placefinder"
grep --max-count 1 "PostGIS" "$tmp/server.log" >&2 || true

result=0
"$LOCAL_LABS/tools/smoke-test.sh" "$base" || result=$?

# median of five requests in milliseconds; every request needs at least one
# round trip to the database, so a database in the cloud shows its distance
median_ms() {   # median_ms <path>
  local times=()
  for _ in 1 2 3 4 5; do
    times+=("$(curl --silent --output /dev/null --max-time 30 --write-out '%{time_total}' "$base$1")")
  done
  python3 -c 'import statistics, sys; print(round(statistics.median(map(float, sys.argv[1:])) * 1000))' "${times[@]}"
}
log "Response times (median of five requests):"
for path in "/v1/places/2929670" "/v1/places?q=Erfurt" "/v1/places?lon=11.03&lat=50.98&radius=25000"; do
  printf '  %-48s %5s ms\n' "GET $path" "$(median_ms "$path")"
done
exit "$result"
