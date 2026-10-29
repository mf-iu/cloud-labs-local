#!/usr/bin/env bash
# Network diagnosis for a host name in the order of a request: DNS answer,
# delegation from the root, TCP and TLS handshake, timing, certificate chain.
# Usage: ./diagnose.sh [host or https URL]   (default: www.openstreetmap.org)
set -o errexit -o nounset -o pipefail
host="${1:-www.openstreetmap.org}"
host="${host#https://}"
host="${host%%/*}"
for cmd in dig curl openssl; do
  command -v "$cmd" >/dev/null || { echo "Command not found: $cmd" >&2; exit 1; }
done

section() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }
# sed instead of head: it reads all input, so no SIGPIPE stops the script
first() { sed --quiet "1,${1}p"; }

section "DNS: answer with TTL, resolver and query time (dig)"
dig +noall +answer +stats "$host" A | grep --extended-regexp --invert-match '^;; (WHEN|MSG SIZE)|^$' || true
dig +short "$host" AAAA

section "DNS: delegation from the root (dig +trace, shortened)"
dig +trace +nodnssec "$host" | grep --extended-regexp 'IN\s+(NS|A|CNAME)\s' | tail --lines 12 \
  || echo "No trace: the network may block DNS queries to other servers than its resolver."

section "TCP and TLS: connection, handshake and response headers (curl --verbose)"
curl --silent --show-error --verbose --output /dev/null "https://$host/" 2>&1 \
  | grep --extended-regexp '^\*|^< ' | first 40 || true

section "Timing: time from the start until each step is done (curl --write-out)"
curl --silent --show-error --output /dev/null --write-out \
'DNS answer       %{time_namelookup} s
TCP connected    %{time_connect} s
TLS handshake    %{time_appconnect} s
First byte       %{time_starttransfer} s
Complete         %{time_total} s
Server           %{remote_ip} port %{remote_port}, HTTP/%{http_version}, status %{http_code}
' "https://$host/" || true

section "TLS certificate chain (openssl s_client)"
openssl s_client -connect "$host:443" -servername "$host" -showcerts </dev/null 2>/dev/null \
  | grep --extended-regexp 'Protocol|Cipher|^ *[0-9] s:|^ *i:|^ *v:' | first 16 || true
