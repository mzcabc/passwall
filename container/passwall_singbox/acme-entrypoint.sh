#!/bin/sh
set -eu

: "${DOMAIN:?DOMAIN is required}"
: "${CF_DNS_API_TOKEN:?CF_DNS_API_TOKEN is required}"
: "${KV_ACCOUNT_ID:?KV_ACCOUNT_ID is required}"

export CF_Token="$CF_DNS_API_TOKEN"
export CF_Account_ID="$KV_ACCOUNT_ID"

issue_and_install() {
  /usr/local/bin/acme.sh --home /acme.sh --issue \
    --server letsencrypt \
    --dns dns_cf \
    --domain "$DOMAIN" \
    --keylength ec-256 || true

  # acme.sh returns 2 when an existing certificate is not due for renewal.
  # Treat that as success, but never continue without an issued certificate.
  test -s "/acme.sh/${DOMAIN}_ecc/fullchain.cer"
  test -s "/acme.sh/${DOMAIN}_ecc/${DOMAIN}.key"

  /usr/local/bin/acme.sh --home /acme.sh --install-cert \
    --domain "$DOMAIN" \
    --ecc \
    --key-file /certs/privkey.pem.new \
    --fullchain-file /certs/fullchain.pem.new

  chmod 600 /certs/privkey.pem.new
  chmod 644 /certs/fullchain.pem.new
  mv -f /certs/privkey.pem.new /certs/privkey.pem
  mv -f /certs/fullchain.pem.new /certs/fullchain.pem
}

issue_and_install

if [ "${1:-}" = "daemon" ]; then
  while true; do
    sleep 43200
    /usr/local/bin/acme.sh --cron --home /acme.sh
    issue_and_install
  done
fi
