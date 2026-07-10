# passwall

VPS proxy stack:

- Hysteria 2 on UDP 443
- VMess over WebSocket behind Caddy on TCP 443
- AnyTLS v2 on TCP 8443 by default
- Snell v5 in Docker for personal temporary use
- Filebeat shipping normalized access events to `proxy-access-v2-YYYYMM`

The normalized events for VMess, Hysteria 2 and AnyTLS include `source.ip`
and `source.port`. Hysteria stream attribution is only applied when a user has
exactly one active source session; ambiguous multi-device sessions are not
assigned a guessed address.

## User data

Cloudflare KV remains a JSON array for compatibility with `gq`. Existing entries
continue to work:

    {"id":"uuid","email":"user","description":""}

Optional per-protocol overrides and disabling are supported:

    {
      "id": "default-uuid-or-password",
      "email": "user",
      "description": "",
      "enabled": true,
      "protocols": {
        "vmess": {"enabled": true, "id": "vmess-uuid"},
        "hysteria2": {"enabled": true, "password": "hy2-password"},
        "anytls": {"enabled": true, "password": "anytls-password"}
      }
    }

If an override is omitted, `id` is used by all three main protocols.
Snell uses the node-level `SNELL_PSK` and is not part of the shared user model.

## Deploy

    apt update
    apt install docker.io docker-compose-plugin
    git clone https://github.com/mzcabc/passwall.git
    cd passwall
    mv .env.sample .env
    # edit .env
    docker compose up -d --build
