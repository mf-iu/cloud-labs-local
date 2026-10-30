#!/usr/bin/env bash

# Send many requests at once and count the answers: 200 while the rate limit
# of a gateway in front of PlaceFinder allows them, then 429 Too Many Requests.
#
# Usage: tools/rate-limit-test.sh [--requests <n>] [--parallel <n>] [--header 'Name: value'] <base url>
#   base url    the address of the gateway
#   --requests  number of requests, default: 60
#   --parallel  requests at the same time, default: 10
#   --header    send this header with every request, e.g. an API key

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/common.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

USAGE="Usage: tools/rate-limit-test.sh [--requests <n>] [--parallel <n>] [--header 'Name: value'] <base url>"
requests=60
parallel=10
headers=()
base=""

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Go through the arguments one by one: case runs the branch whose pattern
# matches $1 (| separates alternatives, * matches anything), shift moves on to
# the next argument.
while (( $# )); do
    case "$1" in
        --requests|--parallel)
            # =~ compares with a regular expression: a positive whole number
            [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || die "$1 needs a positive number. $USAGE"
            if [[ "$1" == --requests ]]; then requests=$2; else parallel=$2; fi
            shift ;;
        # headers is an array; += adds the option and its value as two elements
        --header) (( $# > 1 )) || die "$USAGE"; headers+=(--header "$2"); shift ;;
        -*) die "Unknown option $1. $USAGE" ;;
        *) base=$1 ;;
    esac
    shift
done

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require curl

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

[[ -n "$base" ]] || die "No URL. $USAGE"
# ${base%/} removes a slash at the end of the URL
url="${base%/}/health"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# A temporary file for the status codes; trap deletes it when the script ends
# (EXIT), also after an error
statuses=$(mktemp)
trap 'rm --force "$statuses"' EXIT

log "Sending $requests requests to $url, $parallel at a time ..."
start=$SECONDS
# Each curl runs in the background (& at the end). After every <parallel>
# requests, wait waits until they are all done: (( i % parallel )) is false when
# i is a multiple of parallel.
for (( i = 1; i <= requests; i++ )); do
    # --write-out prints only the status code of the answer
    curl --silent --output /dev/null --max-time 30 --write-out '%{http_code}\n' \
         "${headers[@]}" "$url" >>"$statuses" &
    (( i % parallel )) || wait
done
wait

log "Done after $(( SECONDS - start ))s. Answers by status code:"
# uniq --count counts equal lines (they must be sorted); awk prints status and
# count as a table
sort "$statuses" | uniq --count | awk '{ printf "  %s  %4d times\n", $2, $1 }'

echo
echo "One more request, with the response headers:"
# --include shows the response headers; tr removes the carriage returns of HTTP
curl --silent --show-error --include --max-time 30 "${headers[@]}" "$url" | tr --delete '\r'

echo
# --quiet prints nothing, only the exit code says whether a line is exactly 429
grep --quiet '^429$' "$statuses" \
    || die "No 429: the limit was not reached. Try more requests: --requests 200"

log "The gateway limited the requests (429). Wait a minute before the next smoke test."
