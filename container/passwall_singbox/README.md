# passwall_singbox

单个 sing-box 作为代理入口，Caddy 仅作为 Compose 内部 fallback/masquerade 网站：

- TCP 443：Trojan，认证失败 fallback 到 `caddy:80`
- UDP 443：Hysteria 2，未认证 HTTP/3 masquerade 到 `caddy:80`
- TCP 8443：AnyTLS
- TCP 8444：VMess WebSocket + TLS，路径 `/phpmyadmin`
- TCP 80：不开放
- TCP/UDP 38458：Snell v5，独立 PSK，仅供个人使用

证书由独立 acme.sh 容器通过 Cloudflare DNS-01 签发和续期。`CF_DNS_API_TOKEN` 必须是独立的最小权限 Token，至少具有目标 Zone 的 DNS 编辑权限。

## KV 用户格式

现有 `{id,email,description}` 数组可以直接使用。默认映射：

- Trojan：密码为 `id`
- Hysteria 2：密码为 `email:id`，兼容原官方 Hysteria `userpass`
- AnyTLS：密码为 `id`
- VMess：UUID 为 `id`

推荐逐步改成独立凭据：

```json
{
  "id": "default-uuid",
  "email": "user",
  "enabled": true,
  "protocols": {
    "trojan": {"enabled": true, "password": "trojan-password"},
    "hysteria2": {"enabled": true, "password": "hy2-password"},
    "anytls": {"enabled": true, "password": "anytls-password"},
    "vmess": {"enabled": true, "id": "vmess-uuid"}
  }
}
```

Hysteria 2 的最终客户端密码始终生成成 `email:password`。

## 启动

```bash
cp .env.sample .env
# 填写 .env
docker compose run --rm cert-setup
docker compose run --rm setup
docker compose run --rm --no-deps sing-box check -c /conf/config.json
docker compose up -d
```

## Elasticsearch 访问上报

- sing-box 的 Trojan、Hysteria 2、AnyTLS、VMess 统一写入 `proxy-access-v3` Data Stream。
- 上报成功连接、失败连接和 Trojan fallback，包含用户、来源 IP/端口、目标、TCP/UDP、协议和连接 ID。
- Elasticsearch ingest pipeline 补充来源及目标 GeoIP/ASN。
- backing index 按 1 天或 20 GB rollover，保留 30 天。
- Snell 使用独立 PSK，不接入 KV 多用户模型，也不上报访问日志。
