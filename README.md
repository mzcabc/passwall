```shell
apt update
apt install docker.io docker-compose

git clone https://github.com/mzcabc/passwall.git

cd passwall

mv .env.sample .env

# edit .env

docker-compose up -d
```

## sing-box multi-protocol stack

The production-tested sing-box stack is available in
[`container/passwall_singbox`](container/passwall_singbox/README.md). It provides:

- Trojan on TCP 443 with Caddy fallback
- Hysteria 2 on UDP 443 with Caddy masquerade
- AnyTLS on TCP 8443
- VMess WebSocket with TLS on TCP 8444
- optional Snell v5 on TCP/UDP 38458
- Cloudflare KV user generation and Elasticsearch `proxy-access-v3` reporting
