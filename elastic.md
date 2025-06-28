## ingest pipeline


```
PUT _ingest/pipeline/v2fly-log
{
  "description": "Parse proxy log fields from message",
  "processors": [
    {
      "dissect": {
        "field": "message",
        "pattern": "%{}/%{}/%{} %{}:%{}:%{} %{user.ip}:%{} accepted %{query.protocol}:%{query.url} [%{proxy.policy}] email: %{user.name}",
        "ignore_failure": true
      }
    },
    {
      "remove": {
        "field": "message",
        "if": "false && ctx.user.name != null",
        "description": """remove "message" (off)"""
      }
    },
    {
      "remove": {
        "field": [
          "input",
          "ecs",
          "docker",
          "log",
          "container",
          "agent.id",
          "agent.ephemeral_id",
          "stream",
          "agent.name"
        ],
        "ignore_failure": true
      }
    },
    {
      "geoip": {
        "field": "user.ip",
        "target_field": "user.geo",
        "ignore_missing": true
      }
    },
    {
      "script": {
        "source": """if (ctx.query?.url != null && ctx.query.url.startsWith("http") == false) {
ctx.query.url = "http://" + ctx.query.url;
}""",
        "description": "将url转换为完整uri"
      }
    },
    {
      "uri_parts": {
        "field": "query.url",
        "target_field": "query.uri_parts"
      }
    },
    {
      "registered_domain": {
        "field": "query.uri_parts.domain",
        "target_field": "query.domain_parts"
      }
    }
  ],
  "version": 20250628
}

```

## index template

```
PUT _index_template/proxy-access-template
{
  "index_patterns": [
    "proxy-access-*"
  ],
  "template": {
    "mappings": {
      "properties": {
        "proxy": {
          "type": "object",
          "properties": {
            "policy": {
              "type": "keyword"
            }
          }
        },
        "query": {
          "type": "object",
          "properties": {
            "protocol": {
              "type": "keyword"
            },
            "domain_parts": {
              "dynamic": true,
              "type": "object",
              "enabled": true,
              "properties": {
                "registered_domain": {
                  "type": "keyword"
                },
                "domain": {
                  "type": "keyword"
                }
              },
              "subobjects": true
            },
            "url": {
              "type": "text",
              "fields": {
                "keyword": {
                  "ignore_above": 256,
                  "type": "keyword"
                }
              }
            }
          }
        },
        "host": {
          "type": "object",
          "properties": {
            "name": {
              "type": "keyword"
            }
          }
        },
        "user": {
          "type": "object",
          "properties": {
            "geo": {
              "type": "object",
              "properties": {
                "city_name": {
                  "type": "keyword"
                },
                "country_name": {
                  "type": "keyword"
                },
                "location": {
                  "type": "geo_point"
                },
                "region_name": {
                  "type": "keyword"
                }
              }
            },
            "ip": {
              "type": "ip"
            },
            "name": {
              "type": "keyword"
            }
          }
        }
      }
    }
  },
  "composed_of": [],
  "priority": 500
}
```