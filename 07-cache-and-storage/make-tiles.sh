#!/usr/bin/env bash

# Cut the map tiles around Erfurt out of the daily planet build of Protomaps
# into one PMTiles file. pmtiles extract reads only the parts it needs from
# the file of about 130 GB, with HTTP range requests.
#
# Usage: ./make-tiles.sh [bbox [maxzoom]]
#   bbox     min_lon,min_lat,max_lon,max_lat (default 10.90,50.90,11.20,51.10:
#            Erfurt), written to .state/data/erfurt.pmtiles; another bbox
#            goes to .state/data/region.pmtiles
#   maxzoom  highest zoom level in the file (default 14); the map shows
#            higher levels by scaling the tiles of level 14
#
# Map data © OpenStreetMap contributors (Open Database License, ODbL), tiles by
# Protomaps.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/common.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

BUILDS=https://build-metadata.protomaps.dev/builds.json
ERFURT=10.90,50.90,11.20,51.10
bbox="${1:-$ERFURT}"
maxzoom="${2:-14}"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# =~ compares with a regular expression: four numbers, possibly negative,
# separated by commas
[[ "$bbox" =~ ^-?[0-9.]+,-?[0-9.]+,-?[0-9.]+,-?[0-9.]+$ ]] \
    || die "bbox must be min_lon,min_lat,max_lon,max_lat, e.g. $ERFURT"

if ! [[ "$maxzoom" =~ ^[0-9]+$ ]] || (( maxzoom > 15 )); then
    die "maxzoom must be 0 to 15"
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require pmtiles curl python3

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if [[ "$bbox" == "$ERFURT" ]]; then
    out="$DATA_DIR/erfurt.pmtiles"
else
    out="$DATA_DIR/region.pmtiles"
fi

# the newest daily build, e.g. 20261018.pmtiles
# builds.json lists the builds; the highest key is the newest one
build=$(curl --fail --silent --show-error --max-time 30 "$BUILDS" \
    | python3 -c 'import json, sys; print(max(b["key"] for b in json.load(sys.stdin)))')

log "Extracting $bbox up to zoom $maxzoom from the Protomaps build $build ..."
pmtiles extract "https://build.protomaps.com/$build" "$out" --bbox="$bbox" --maxzoom="$maxzoom"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# du prints size and name; cut --fields 1 keeps the size
log "Wrote $out ($(du --human-readable "$out" | cut --fields 1)):"
pmtiles show "$out" | grep --extended-regexp 'tile type|bounds|min zoom|max zoom|tile contents count|addressed tiles count' || true

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

file="../.state/data/$(basename "$out")"

cat <<INFO

Next: into object storage and onto the map
  uv run local-s3.py upload $file
  uv run local-s3.py map tiles/$(basename "$out")
INFO
