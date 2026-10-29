#!/usr/bin/env bash
# Load GeoNames places into PostgreSQL with PostGIS: table, COPY, geography
# column and indexes.
# Usage: ./load-cities.sh [name | file]
#   name: GeoNames dump without ".zip": cities15000 (default), DE, allCountries ...
#   file: a GeoNames text file that is already on this computer
# Uses DATABASE_URL if it is set, otherwise the local database from
# compose.yaml of PlaceFinder (service db).
source "$(dirname "$0")/../lib/common.sh"

DATABASE_URL="${DATABASE_URL:-$LOCAL_DATABASE_URL}"

arg="${1:-cities15000}"
if [[ -f "$arg" ]]; then
  file="$(realpath "$arg")"
else
  file="$(download_geonames "${arg%.txt}")"
fi
[[ -s "$file" ]] || die "File not found or empty: $file"
cd "$(dirname "$0")"

log "Creating table places ..."
psql_run "$DATABASE_URL" --set ON_ERROR_STOP=1 --file schema.sql

log "Importing $(wc --lines <"$file") places from $(basename "$file") with COPY ..."
# CSV format with a tab delimiter turns empty fields into NULL.
# The quote character \x01 never occurs in the data.
psql_run "$DATABASE_URL" --set ON_ERROR_STOP=1 --command \
  "\\copy places FROM '$file' WITH (FORMAT csv, DELIMITER E'\\t', QUOTE E'\\x01')"

log "Creating geography column and indexes ..."
psql_run "$DATABASE_URL" --set ON_ERROR_STOP=1 --file indexes.sql

log "Done. Example queries: ./query.sh   PlaceFinder with this database: ./test-api.sh"
