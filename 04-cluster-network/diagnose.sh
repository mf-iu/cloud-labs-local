#!/usr/bin/env bash

# Network diagnosis for a host name in the order of a request: DNS answer,
# delegation from the root, TCP and TLS handshake, timing, certificate chain.
#
# Usage: ./diagnose.sh [host or https URL]   (default: www.openstreetmap.org)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# No lib/common.sh: the script also runs outside the dev container
set -o errexit -o nounset -o pipefail

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

host="${1:-www.openstreetmap.org}"
# ${host#https://} removes https:// at the start, ${host%%/*} everything from
# the first slash on: the host name of a URL
host="${host#https://}"
host="${host%%/*}"

for cmd in dig curl openssl; do
    # { ...; } groups both commands: they run if the program is missing
    command -v "$cmd" >/dev/null || { echo "Command not found: $cmd" >&2; exit 1; }
done

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

section() {
    printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# sed instead of head: it reads all input, so no SIGPIPE stops the script
first() {
    # --quiet prints nothing by itself; 1,Np prints lines 1 to N
    sed --quiet "1,${1}p"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

section "DNS: answer with TTL, resolver and query time (dig)"
# +noall +answer +stats: only the answer and the statistics; grep removes date,
# size and empty lines. || true: no matches is no error.
dig +noall +answer +stats "$host" A | grep --extended-regexp --invert-match '^;; (WHEN|MSG SIZE)|^$' || true
dig +short "$host" AAAA

section "DNS: delegation from the root (dig +trace, shortened)"
# \s in the regular expression is a space or tab; tail keeps the last 12 lines
dig +trace +nodnssec "$host" | grep --extended-regexp 'IN\s+(NS|A|CNAME)\s' | tail --lines 12 \
    || echo "No trace: the network may block DNS queries to other servers than its resolver."

section "TCP and TLS: connection, handshake and response headers (curl --verbose)"
# --verbose writes the steps to stderr, 2>&1 sends them into the pipe; grep
# keeps the lines starting with * (steps) and < (response headers)
curl --silent --show-error --verbose --output /dev/null "https://$host/" 2>&1 \
    | grep --extended-regexp '^\*|^< ' | first 40 || true

section "Timing: time from the start until each step is done (curl --write-out)"
# --write-out prints the text that follows (a string over several lines) with
# the %{...} fields filled in
curl --silent --show-error --output /dev/null --write-out \
'DNS answer       %{time_namelookup} s
TCP connected    %{time_connect} s
TLS handshake    %{time_appconnect} s
First byte       %{time_starttransfer} s
Complete         %{time_total} s
Server           %{remote_ip} port %{remote_port}, HTTP/%{http_version}, status %{http_code}
' "https://$host/" || true

section "TLS certificate chain (openssl s_client)"
# s_client opens a TLS connection; </dev/null ends it right away. -servername
# sends the host name (Server Name Indication, SNI), -showcerts prints the whole
# chain.
openssl s_client -connect "$host:443" -servername "$host" -showcerts </dev/null 2>/dev/null \
    | grep --extended-regexp 'Protocol|Cipher|^ *[0-9] s:|^ *i:|^ *v:' | first 16 || true
