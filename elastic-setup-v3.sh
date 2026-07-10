#!/bin/sh
set -eu

apk add --no-cache curl >/dev/null

: "${ELASTICSEARCH_HOSTS:?ELASTICSEARCH_HOSTS is required}"
: "${ELASTICSEARCH_USERNAME:?ELASTICSEARCH_USERNAME is required}"
: "${ELASTICSEARCH_PASSWORD:?ELASTICSEARCH_PASSWORD is required}"

ES=${ELASTICSEARCH_HOSTS%%,*}

es() {
  method=$1
  path=$2
  curl -fsS -k -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
    -X "$method" "$ES$path" -H 'Content-Type: application/json' --data-binary @-
}

es PUT /_ilm/policy/proxy-access-v3-retention <<'JSON'
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_primary_shard_size": "20gb",
            "max_age": "1d"
          }
        }
      },
      "delete": {
        "min_age": "30d",
        "actions": {"delete": {}}
      }
    }
  }
}
JSON

es PUT /_index_template/proxy-access-v3 <<'JSON'
{
  "index_patterns": ["proxy-access-v3*"],
  "data_stream": {},
  "priority": 600,
  "template": {
    "settings": {
      "index.default_pipeline": "proxy-access-v3",
      "index.lifecycle.name": "proxy-access-v3-retention"
    },
    "mappings": {
      "dynamic": false,
      "properties": {
        "@timestamp": {"type": "date"},
        "ecs.version": {"type": "keyword"},
        "event.kind": {"type": "keyword"},
        "event.category": {"type": "keyword"},
        "event.type": {"type": "keyword"},
        "event.action": {"type": "keyword"},
        "event.outcome": {"type": "keyword"},
        "event.start": {"type": "date"},
        "event.end": {"type": "date"},
        "event.duration": {"type": "long"},
        "event.provider": {"type": "keyword"},
        "event.dataset": {"type": "keyword"},
        "observer.name": {"type": "keyword"},
        "observer.hostname": {"type": "keyword"},
        "observer.type": {"type": "keyword"},
        "service.name": {"type": "keyword"},
        "service.version": {"type": "keyword"},
        "container.id": {"type": "keyword"},
        "container.name": {"type": "keyword"},
        "container.image.name": {"type": "keyword"},
        "user.name": {"type": "keyword"},
        "source.ip": {"type": "ip"},
        "source.port": {"type": "long"},
        "source.address": {"type": "keyword"},
        "source.bytes": {"type": "long"},
        "source.geo.continent_name": {"type": "keyword"},
        "source.geo.country_iso_code": {"type": "keyword"},
        "source.geo.country_name": {"type": "keyword"},
        "source.geo.region_iso_code": {"type": "keyword"},
        "source.geo.region_name": {"type": "keyword"},
        "source.geo.city_name": {"type": "keyword"},
        "source.geo.location": {"type": "geo_point"},
        "source.as.number": {"type": "long"},
        "source.as.organization.name": {"type": "keyword"},
        "destination.address": {"type": "keyword"},
        "destination.domain": {"type": "keyword"},
        "destination.ip": {"type": "ip"},
        "destination.port": {"type": "long"},
        "destination.bytes": {"type": "long"},
        "destination.geo.country_iso_code": {"type": "keyword"},
        "destination.geo.country_name": {"type": "keyword"},
        "destination.geo.region_name": {"type": "keyword"},
        "destination.geo.city_name": {"type": "keyword"},
        "destination.geo.location": {"type": "geo_point"},
        "destination.as.number": {"type": "long"},
        "destination.as.organization.name": {"type": "keyword"},
        "network.transport": {"type": "keyword"},
        "network.protocol": {"type": "keyword"},
        "network.type": {"type": "keyword"},
        "network.direction": {"type": "keyword"},
        "network.bytes": {"type": "long"},
        "proxy.protocol": {"type": "keyword"},
        "proxy.inbound_tag": {"type": "keyword"},
        "proxy.outbound_tag": {"type": "keyword"},
        "proxy.connection_id": {"type": "keyword"},
        "proxy.udp_mode": {"type": "keyword"},
        "proxy.uot": {"type": "boolean"},
        "proxy.uot_handshake_address": {"type": "keyword"},
        "proxy.fallback": {"type": "boolean"},
        "proxy.fallback_target": {"type": "keyword"},
        "proxy.masquerade": {"type": "boolean"},
        "proxy.masquerade_target": {"type": "keyword"},
        "error.type": {"type": "keyword"},
        "error.code": {"type": "keyword"},
        "error.message": {"type": "match_only_text"},
        "log.level": {"type": "keyword"},
        "log.original": {"type": "match_only_text"}
      }
    }
  }
}
JSON

es PUT /_ingest/pipeline/proxy-access-v3 <<'JSON'
{
  "description": "GeoIP and ASN enrichment for normalized sing-box access events",
  "processors": [
    {"geoip": {"field": "source.ip", "target_field": "source.geo", "ignore_missing": true}},
    {"geoip": {"field": "source.ip", "target_field": "source.as", "database_file": "GeoLite2-ASN.mmdb", "properties": ["asn", "organization_name"], "ignore_missing": true}},
    {"rename": {"field": "source.as.asn", "target_field": "source.as.number", "ignore_missing": true}},
    {"rename": {"field": "source.as.organization_name", "target_field": "source.as.organization.name", "ignore_missing": true}},
    {"geoip": {"field": "destination.ip", "target_field": "destination.geo", "ignore_missing": true}},
    {"geoip": {"field": "destination.ip", "target_field": "destination.as", "database_file": "GeoLite2-ASN.mmdb", "properties": ["asn", "organization_name"], "ignore_missing": true}},
    {"rename": {"field": "destination.as.asn", "target_field": "destination.as.number", "ignore_missing": true}},
    {"rename": {"field": "destination.as.organization_name", "target_field": "destination.as.organization.name", "ignore_missing": true}}
  ]
}
JSON

if ! curl -fsS -k -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" "$ES/_data_stream/proxy-access-v3" >/dev/null 2>&1; then
  curl -fsS -k -u "$ELASTICSEARCH_USERNAME:$ELASTICSEARCH_PASSWORD" \
    -X PUT "$ES/_data_stream/proxy-access-v3"
fi

es PUT /proxy-access-v3/_settings <<'JSON'
{
  "index.lifecycle.name": "proxy-access-v3-retention"
}
JSON
