#!/usr/bin/env bash

# Check the REST API of PlaceFinder (tag t05 or later) against a base URL:
# GeoJSON, filters, pagination, caching headers, conditional requests,
# problem details (RFC 9457), CORS and the deprecation of version 0.
# Only GET requests, so it is safe against every instance.
#
# Usage: tools/smoke-test.sh [options] [base url]
#   base url   default: http://localhost:8000, the local server
#   --header   send this header with every request, e.g. an API key
#   --cacert   trust the certificates of this CA, e.g. the course CA
#   --resolve  host:port:address, as with curl, for a name without DNS entry
#
# Examples: tools/smoke-test.sh
#           tools/smoke-test.sh --cacert .state/course-ca.crt \
#             --resolve placefinder.test:8443:127.0.0.1 https://placefinder.test:8443
#
# The provider repositories call it with the address of their service.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/common.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

USAGE="Usage: tools/smoke-test.sh [--header 'Name: value'] [--cacert <file>] [--resolve <host:port:address>] [base url]"
ERFURT=2929670
ORIGIN=http://localhost:5173     # the map of PlaceFinder, allowed by CORS
PROBLEMS=https://placefinder.test/problems
headers=()   # curl options for every request: headers, CA, name resolution
base=http://localhost:8000

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Go through the arguments one by one: case runs the branch whose pattern
# matches $1 (* matches anything), shift moves on to the next argument.
while (( $# )); do
    case "$1" in
        # headers is an array of curl options; += adds an option and its value
        # as two elements
        --header) (( $# > 1 )) || die "$USAGE"; headers+=(--header "$2"); shift ;;
        --cacert)
            (( $# > 1 )) || die "$USAGE"
            [[ -f "$2" ]] || die "CA certificate not found: $2"
            headers+=(--cacert "$2"); shift ;;
        --resolve) (( $# > 1 )) || die "$USAGE"; headers+=(--resolve "$2"); shift ;;
        -*) die "Unknown option $1. $USAGE" ;;
        *) base=$1 ;;
    esac
    shift
done

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require curl python3

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# ${base%/} removes a slash at the end of the URL
base=${base%/}

# A temporary folder for headers and body; trap deletes it when the script ends
# (EXIT), also after an error
tmp=$(mktemp --directory)
trap 'rm --recursive --force "$tmp"' EXIT

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

status=""

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# GET a path (or a link of the API, which starts with /v1/) below the base URL
# fetch <path> [curl options]; sets $status, saves headers and body
fetch() {
    local path=$1
    shift
    # : does nothing; with >file it empties the file
    : >"$tmp/body"   # curl leaves the file alone if there is no body (304)
    # "${headers[@]}" inserts all elements of the array as separate arguments.
    # --dump-header saves the response headers, --write-out prints only the
    # status code. If curl fails (no connection, timeout), status gets the first
    # line of its error message.
    status=$(curl --silent --show-error --max-time 30 "${headers[@]}" "$@" \
                  --dump-header "$tmp/headers" --output "$tmp/body" --write-out '%{http_code}' \
                  "$base$path" 2>"$tmp/error") || status="error: $(head --lines 1 "$tmp/error")"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Value of a response header of the last request (names are case-insensitive)
# header <name>
header() {
    local line
    # Read the file line by line (done <file at the end of the loop); IFS= keeps
    # spaces at the start of a line
    while IFS= read -r line; do
        # Remove the carriage return at the end ($'\r' is the character itself)
        line=${line%$'\r'}
        # ${x,,} is x in lowercase: header names are case-insensitive.
        # ${line#*:} removes everything up to the first colon, ${line# } a space
        # at the start.
        if [[ "${line,,}" == "${1,,}:"* ]]; then
            line=${line#*:}
            echo "${line# }"
            return
        fi
    done <"$tmp/headers"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Evaluate a Python expression on the JSON body b of the last request
# json <expression>
json() {
    # eval evaluates the Python expression given as second argument, with the
    # parsed body as b
    python3 -c 'import json, sys; b = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' \
        "$tmp/body" "$1" 2>/dev/null || echo "(missing)"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

failed=0
# Compare and print one line OK or FAIL
# check <description> <expected> <actual>
check() {
    if [[ "$2" == "$3" ]]; then
        printf '  \033[32mOK\033[0m    %-48s %s\n' "$1" "$3"
    else
        printf '  \033[31mFAIL\033[0m  %-48s %s (expected: %s)\n' "$1" "$3" "$2"
        # $(( ... )) calculates and returns the result
        failed=$(( failed + 1 ))
    fi
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

section() {
    printf '\n\033[1m%s\033[0m\n' "$1"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

fetch /
# ${status#error: } is the message without the word error
[[ "$status" != error* ]] || die "No answer from $base: ${status#error: }"
version=$(json 'b["version"]')
# ${x/a/b} replaces the first a in x with b
log "Smoke test of PlaceFinder ${version/(missing)/(version unknown)} at $base"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

section "Search: GET /v1/places"
fetch "/v1/places?q=Erfurt"
check "q=Erfurt: status" 200 "$status"
check "media type" application/geo+json "$(header content-type)"
# $( [[ ... ]] && echo yes || echo no) turns a test into the text yes or no for
# check
check "caching header" yes "$( [[ "$(header cache-control)" == *max-age=* ]] && echo yes || echo no)"
check "FeatureCollection" FeatureCollection "$(json 'b["type"]')"
check "first feature is Erfurt" "$ERFURT" "$(json 'b["features"][0]["id"]')"
check "longitude before latitude" "[11, 51]" "$(json '[round(c) for c in b["features"][0]["geometry"]["coordinates"]]')"

fetch "/v1/places?lon=11.03&lat=50.98&radius=25000"
check "lon, lat, radius: nearest place" Erfurt "$(json 'b["features"][0]["properties"]["name"]')"
check "distance in meters" yes "$(json '"yes" if b["features"][0]["properties"]["distance"] < 1000 else "no"')"

fetch "/v1/places?bbox=10.9,50.9,11.2,51.1"
# The quotes end the Python text for a moment, so that the shell inserts $ERFURT
# into the expression
check "bbox around Erfurt contains Erfurt" yes "$(json '"yes" if any(f["id"] == '"$ERFURT"' for f in b["features"]) else "no"')"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

section "Pagination"
fetch "/v1/places?country=DE&limit=2"
check "country=DE&limit=2: features" 2 "$(json 'len(b["features"])')"
first_page=$(json '[f["id"] for f in b["features"]]')
link=$(header link)
check "header Link with rel=\"next\"" yes "$( [[ "$link" == *'rel="next"'* ]] && echo yes || echo no)"
# The href of the first link with rel next; \? below is a literal question mark,
# not a pattern
next=$(json '[l["href"] for l in b["links"] if l["rel"] == "next"][0]')
check "link next in the body" yes "$( [[ "$next" == /v1/places\?*cursor=* ]] && echo yes || echo no)"
fetch "$next"
check "next page: status" 200 "$status"
check "next page: other places" yes "$(json '"yes" if not set(f["id"] for f in b["features"]) & set('"$first_page"') else "no"')"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

section "One place: ETag and conditional request"
fetch "/v1/places/$ERFURT"
check "GET /v1/places/$ERFURT: status" 200 "$status"
check "media type" application/geo+json "$(header content-type)"
etag=$(header etag)
check "header ETag" yes "$( [[ "$etag" == *\"*\" ]] && echo yes || echo no)"
if [[ -n "$etag" ]]; then
    fetch "/v1/places/$ERFURT" --header "If-None-Match: $etag"
    check "If-None-Match: $etag" 304 "$status"
    # wc --bytes <file prints the size of the file
    check "304 without body" 0 "$(wc --bytes <"$tmp/body")"
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

section "Errors as problem details (RFC 9457)"
fetch /v1/places/1
check "unknown place: status" 404 "$status"
check "media type" application/problem+json "$(header content-type)"
check "type" "$PROBLEMS/place-not-found" "$(json 'b["type"]')"
fetch "/v1/places?bbox=11.0,50.9"
check "bbox with two numbers: status" 422 "$status"
check "type" "$PROBLEMS/invalid-bbox" "$(json 'b["type"]')"
problem=$(cat "$tmp/body")
fetch "/v1/places?limit=500"
check "limit=500: status" 422 "$status"
check "type" "$PROBLEMS/invalid-parameters" "$(json 'b["type"]')"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

section "CORS and version 0"
fetch "/v1/places?q=Erfurt" --header "Origin: $ORIGIN"
check "Origin $ORIGIN allowed" "$ORIGIN" "$(header access-control-allow-origin)"
fetch "/places?q=Erfurt"
check "GET /places (version 0): status" 200 "$status"
check "header Deprecation" yes "$( [[ -n "$(header deprecation)" ]] && echo yes || echo no)"
check "header Sunset" yes "$( [[ -n "$(header sunset)" ]] && echo yes || echo no)"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

echo
echo "Problem details for bbox=11.0,50.9:"
echo "  $problem"
echo
# (( ... )) is true if the comparison holds
(( failed == 0 )) || die "$failed checks failed."

log "All checks passed."
