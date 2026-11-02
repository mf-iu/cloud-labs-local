#!/usr/bin/env bash

# Radius search in Valkey and in PostGIS side by side. Loads the places of
# GeoNames cities15000 into a geo index of Valkey (GEOADD: a sorted set whose
# score is a 52-bit geohash), searches around Erfurt with GEOSEARCH and does
# the same with ST_DWithin in PostGIS, if there is a database.
#
# Usage: ./geosearch.sh [radius in km]   (default 25)
#
# Valkey runs as service valkey in compose.yaml of PlaceFinder
# (/workspaces/placefinder or PLACEFINDER_DIR). The database comes from
# DATABASE_URL, otherwise it is the local one (service db) if it runs;
# without a database, only Valkey is shown.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/common.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

KEY=placefinder:geo:cities15000
ERFURT_LON=11.03
ERFURT_LAT=50.98
radius="${1:-25}"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# =~ compares with a regular expression: only digits
[[ "$radius" =~ ^[0-9]+$ ]] || die "Usage: ./geosearch.sh [radius in km]"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require docker python3

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

placefinder="$PLACEFINDER_DIR"
[[ -f "$placefinder/compose.yaml" ]] \
    || die "PlaceFinder not found in $placefinder. Clone your fork next to this repository."

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

compose() {
    docker compose --file "$placefinder/compose.yaml" "$@"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

vcli() {
    # Run valkey-cli in the container of the service valkey; -T: no terminal, so
    # that a pipe can feed it
    compose exec -T valkey valkey-cli "$@"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# --wait returns once the service is healthy
compose up --detach --wait valkey

file="$(download_cities)"
log "Loading $(wc --lines <"$file") places into $KEY with GEOADD ..."
vcli del "$KEY" >/dev/null

# mass insertion: all commands in the protocol of Valkey (Redis Serialization
# Protocol, RESP) in one stream
# python3 - reads the program from stdin, here the heredoc up to PYTHON; the
# arguments after - are sys.argv[1:]. valkey-cli --pipe sends the generated
# commands to Valkey in one go.
python3 - "$file" "$KEY" <<'PYTHON' | compose exec -T valkey valkey-cli --pipe
import sys

def command(*args):
    parts = [f"*{len(args)}\r\n".encode()]
    for arg in args:
        data = str(arg).encode()
        parts.append(b"$%d\r\n%s\r\n" % (len(data), data))
    return b"".join(parts)

path, key = sys.argv[1:]
with open(path, encoding="utf-8") as places:
    for line in places:
        f = line.rstrip("\n").split("\t")
        # GEOADD key longitude latitude member; member: geonameid:name
        sys.stdout.buffer.write(command("GEOADD", key, f[5], f[4], f"{f[0]}:{f[1]}"))
PYTHON

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# zcard: number of members of the sorted set; memory usage: its size in bytes
printf '  %s places, %s bytes in Valkey\n' "$(vcli zcard "$KEY")" "$(vcli memory usage "$KEY")"
printf '  Erfurt: geohash %s, score %s\n' "$(vcli geohash "$KEY" 2929670:Erfurt)" \
       "$(vcli zscore "$KEY" 2929670:Erfurt)"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "Valkey: the ten nearest places within $radius km of Erfurt (GEOSEARCH, km)"
# valkey-cli prints name and distance on two lines; paste - - joins every two
# lines, sed indents them
vcli geosearch "$KEY" fromlonlat "$ERFURT_LON" "$ERFURT_LAT" byradius "$radius" km \
    asc count 10 withdist | paste --delimiters ' ' - - | sed 's/^/  /'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# No DATABASE_URL given, but the service db of compose.yaml runs: use the local
# database. --line-regexp matches only the whole line db.
if [[ -z "${DATABASE_URL:-}" ]] && compose ps --status running --services 2>/dev/null | grep --quiet --line-regexp db; then
    DATABASE_URL=$LOCAL_DATABASE_URL
fi

if [[ -z "${DATABASE_URL:-}" ]]; then
    warn "No database for the comparison with PostGIS: start it (docker compose up --detach db) and load the places (../06-postgis/load-cities.sh)."
    exit 0
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

log "PostGIS: the same search (ST_DWithin, km)"
# Only the rows, without headers and alignment, fields separated by a space
psql_run "$DATABASE_URL" --no-psqlrc --quiet --tuples-only --no-align --field-separator ' ' \
         --command "
  SELECT geonameid || ':' || name, round((ST_Distance(geom, p) / 1000)::numeric, 4)
  FROM places, CAST(ST_MakePoint($ERFURT_LON, $ERFURT_LAT) AS geography) AS p
  WHERE ST_DWithin(geom, p, $radius * 1000)
  ORDER BY geom <-> p LIMIT 10" | sed 's/^/  /'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

cat <<'INFO'

Valkey computes distances on a sphere (haversine), PostGIS with geography on
the WGS 84 ellipsoid: the distances differ by up to about 0.5 %.
INFO
