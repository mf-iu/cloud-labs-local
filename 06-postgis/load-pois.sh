#!/usr/bin/env bash
# Import points of interest from an OpenStreetMap extract with osm2pgsql.
# Usage: ./load-pois.sh [region]
#   region: path on download.geofabrik.de without "-latest.osm.pbf",
#   default: europe/germany/thueringen (about 150 MB)
# Tested with osm2pgsql 1.11 and 2.3. Uses DATABASE_URL if it is set,
# otherwise the local database (like load-cities.sh).
source "$(dirname "$0")/../lib/common.sh"
require osm2pgsql

DATABASE_URL="${DATABASE_URL:-$LOCAL_DATABASE_URL}"

region="${1:-europe/germany/thueringen}"
pbf="$DATA_DIR/$(basename "$region")-latest.osm.pbf"
if [[ ! -s "$pbf" ]]; then
  log "Downloading $region from Geofabrik ..."
  curl --fail --silent --show-error --location --output "$pbf" "https://download.geofabrik.de/$region-latest.osm.pbf"
fi
cd "$(dirname "$0")"

log "Importing points of interest with osm2pgsql ..."
osm2pgsql --output=flex --style=pois.lua --database="$DATABASE_URL" "$pbf"

log "Creating geography column and index ..."
psql_run "$DATABASE_URL" --set ON_ERROR_STOP=1 --file pois.sql

log "Done: table pois. Data © OpenStreetMap contributors (ODbL)."
