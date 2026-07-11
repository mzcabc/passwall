#!/bin/sh
set -eu

missing=0

require() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "missing required environment variable: $name" >&2
    missing=1
  fi
}

require KV_AUTH
require KV_ACCOUNT_ID
require KV_NAMESPACE_ID
require KV_KEY_NAME
require DOMAIN
require HOSTNAME
require CF_DNS_API_TOKEN
require SNELL_PSK
require ELASTICSEARCH_HOSTS
require ELASTICSEARCH_USERNAME
require ELASTICSEARCH_PASSWORD

case "${DOMAIN:-}" in
  proxy.example.com|example.com)
    echo "DOMAIN must be set to the real proxy domain" >&2
    missing=1
    ;;
esac

case "${HOSTNAME:-}" in
  proxy-node)
    echo "HOSTNAME must be set to the real observer host name" >&2
    missing=1
    ;;
esac

case "${SNELL_PORT:-38458}" in
  *[!0-9]*|"")
    echo "SNELL_PORT must be a numeric TCP/UDP port" >&2
    missing=1
    ;;
esac

case "${ES_SSL_VERIFY:-false}" in
  true|false) ;;
  *)
    echo "ES_SSL_VERIFY must be true or false" >&2
    missing=1
    ;;
esac

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "passwall environment is valid"
