```
PUT _ingest/pipeline/v2fly
{
  "description": "2024/01/19 02:45:05 123.113.255.58:0 accepted tcp:api.xxx.com:443 [direct] email: legacy",
  "processors": [
    {
      "dissect": {
        "field": "message",
        "pattern": "%{+@timestamp} %{+@timestamp} %{proxy_client.ip}:0 accepted %{proxy_target.protocol}:%{proxy_target.url} [%{proxy_target.policy}] email: %{proxy_client.user}",
        "on_failure": [
          {
            "drop": {}
          }
        ]
      }
    },
    {
      "date": {
        "field": "@timestamp",
        "formats": [
          "yyyy/MM/ddHH:mm:ss"
        ],
        "timezone": "Asia/Shanghai",
        "ignore_failure": true
      }
    },
    {
      "geoip": {
        "field": "proxy_client.ip",
        "target_field": "proxy_client.geo",
        "ignore_failure": true
      }
    }
  ]
}
```