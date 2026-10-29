#!/usr/bin/env bash
# Run the example queries, or open an interactive psql session with --interactive.
# Usage: ./query.sh [--interactive]
# Uses DATABASE_URL if it is set, otherwise the local database (like load-cities.sh).
source "$(dirname "$0")/../lib/common.sh"

DATABASE_URL="${DATABASE_URL:-$LOCAL_DATABASE_URL}"
cd "$(dirname "$0")"

if [[ "${1:-}" == "--interactive" || "${1:-}" == "-i" ]]; then
  psql_run "$DATABASE_URL"
else
  psql_run "$DATABASE_URL" --file queries.sql
fi
