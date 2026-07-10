#!/bin/sh
set -eu

: "${ELASTICSEARCH_HOSTS:?ELASTICSEARCH_HOSTS is required}"
: "${ELASTICSEARCH_USERNAME:?ELASTICSEARCH_USERNAME is required}"
: "${ELASTICSEARCH_PASSWORD:?ELASTICSEARCH_PASSWORD is required}"

es() {
  path=$1
  if [ -n "${ELASTICSEARCH_HOST_HEADER:-}" ]; then
    curl -fsSk --max-time 30 -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
      -H "Host: $ELASTICSEARCH_HOST_HEADER" -H 'Content-Type: application/json' \
      -X PUT "${ELASTICSEARCH_HOSTS%/}$path" --data-binary @-
  else
    curl -fsSk --max-time 30 -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
      -H 'Content-Type: application/json' \
      -X PUT "${ELASTICSEARCH_HOSTS%/}$path" --data-binary @-
  fi
}

es /_ingest/pipeline/hysteria-access-v2 <<'JSON'
{
  "description": "Normalize Hysteria 2 stream events emitted by hysteria-access",
  "processors": [
    {"json": {"field": "message", "target_field": "_event"}},
    {"remove": {"field": ["event", "network", "user", "destination", "source", "proxy"], "ignore_missing": true}},
    {"rename": {"field": "_event.event", "target_field": "event"}},
    {"rename": {"field": "_event.@timestamp", "target_field": "event.created", "ignore_missing": true}},
    {"rename": {"field": "_event.network", "target_field": "network"}},
    {"rename": {"field": "_event.user", "target_field": "user"}},
    {"rename": {"field": "_event.destination", "target_field": "destination"}},
    {"rename": {"field": "_event.source", "target_field": "source", "ignore_missing": true}},
    {"rename": {"field": "_event.proxy", "target_field": "proxy"}},
    {"rename": {"field": "_event.destination_bytes", "target_field": "destination.bytes", "ignore_missing": true}},
    {"rename": {"field": "_event.event_start", "target_field": "event.start", "ignore_missing": true}},
    {"rename": {"field": "_event.source_event", "target_field": "event.provider"}},
    {"script": {
      "lang": "painless",
      "source": "if (ctx.destination?.address != null) { String a = ctx.destination.address; int p = a.lastIndexOf(':'); if (p > 0) { ctx.destination.port = Integer.parseInt(a.substring(p + 1)); String h = a.substring(0, p); if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length()-1); if (ctx.destination.domain == null || ctx.destination.domain == '') ctx.destination.domain = h; } }"
    }},
    {"date": {"field": "event.created", "formats": ["ISO8601"], "target_field": "@timestamp", "ignore_failure": true}},
    {"remove": {"field": ["_event", "message"], "ignore_missing": true}}
  ]
}
JSON

es /_ingest/pipeline/anytls-log-v2 <<'JSON'
{
  "description": "Normalize correlated AnyTLS access events emitted by anytls-access",
  "processors": [
    {"json": {"field": "message", "target_field": "_event"}},
    {"remove": {"field": ["event", "network", "user", "destination", "source", "proxy"], "ignore_missing": true}},
    {"rename": {"field": "_event.event", "target_field": "event"}},
    {"rename": {"field": "_event.@timestamp", "target_field": "event.created"}},
    {"rename": {"field": "_event.network", "target_field": "network"}},
    {"rename": {"field": "_event.user", "target_field": "user"}},
    {"rename": {"field": "_event.source", "target_field": "source"}},
    {"rename": {"field": "_event.destination", "target_field": "destination"}},
    {"rename": {"field": "_event.proxy", "target_field": "proxy"}},
    {"rename": {"field": "_event.source_event", "target_field": "event.provider"}},
    {"date": {"field": "event.created", "formats": ["ISO8601"], "target_field": "@timestamp", "ignore_failure": true}},
    {"geoip": {"field": "source.ip", "target_field": "source.geo", "ignore_missing": true}},
    {"remove": {"field": ["_event", "message"], "ignore_missing": true}}
  ]
}
JSON

es /_ingest/pipeline/v2fly-access-v2 <<'JSON'
{
  "description": "Normalize successful VMess access lines from V2Fly",
  "processors": [
    {"grok": {
      "field": "message",
      "patterns": ["^%{YEAR}/%{MONTHNUM}/%{MONTHDAY} %{TIME} %{IP:source.ip}:%{POSINT:source.port} accepted %{WORD:network.transport}:(?<destination.address>.+):(?<destination.port>[0-9]+) \\[%{DATA:proxy.policy}\\] email: %{DATA:user.name}$"],
      "ignore_failure": true
    }},
    {"drop": {"if": "ctx.user?.name == null"}},
    {"set": {"field": "event.kind", "value": "event"}},
    {"set": {"field": "event.category", "value": ["network"]}},
    {"set": {"field": "event.type", "value": ["start", "connection"]}},
    {"set": {"field": "event.action", "value": "proxy-connect"}},
    {"set": {"field": "event.outcome", "value": "success"}},
    {"set": {"field": "event.provider", "value": "v2fly"}},
    {"set": {"field": "network.protocol", "value": "vmess"}},
    {"set": {"field": "proxy.protocol", "value": "vmess-ws"}},
    {"script": {"source": "String a=ctx.destination.address; if (!(a ==~ /[0-9a-fA-F:.]+/)) ctx.destination.domain=a;"}},
    {"geoip": {"field": "source.ip", "target_field": "source.geo", "ignore_missing": true}}
  ]
}
JSON

printf '\nElasticsearch ingest pipelines installed.\n'
