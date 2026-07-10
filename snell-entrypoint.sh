#!/bin/sh
set -eu

: "${SNELL_PSK:?SNELL_PSK is required}"

cat > /tmp/snell-server.conf <<EOF
[snell-server]
listen = ${SNELL_LISTEN:-0.0.0.0:38458}
psk = ${SNELL_PSK}
ipv6 = ${SNELL_IPV6:-false}
EOF

exec snell-server -c /tmp/snell-server.conf
