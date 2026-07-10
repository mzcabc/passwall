#!/bin/ash
set -eu

apk add --no-cache jq >/dev/null

DISABLED_USERS_JSON=$(printf '%s' "${DISABLED_USERS:-}" | jq -Rc 'split(",") | map(select(length > 0))')
ACTIVE_USERS=$(jq -c --argjson disabled "$DISABLED_USERS_JSON" '[
  .[]
  | select(.enabled // true)
  | select(.email as $email | ($disabled | index($email) | not))
]' /kv/users.json)

TROJAN_USERS=$(printf '%s' "$ACTIVE_USERS" | jq -c '[
  .[] | select(.protocols.trojan.enabled // true) | {
    name: .email,
    password: (.protocols.trojan.password // .id)
  }
]')

HYSTERIA2_USERS=$(printf '%s' "$ACTIVE_USERS" | jq -c '[
  .[] | select(.protocols.hysteria2.enabled // true) | {
    name: .email,
    password: (.email + ":" + (.protocols.hysteria2.password // .id))
  }
]')

ANYTLS_USERS=$(printf '%s' "$ACTIVE_USERS" | jq -c '[
  .[] | select(.protocols.anytls.enabled // true) | {
    name: .email,
    password: (.protocols.anytls.password // .id)
  }
]')

VMESS_USERS=$(printf '%s' "$ACTIVE_USERS" | jq -c '[
  .[] | select(.protocols.vmess.enabled // true) | {
    name: .email,
    uuid: (.protocols.vmess.id // .id),
    alterId: 0
  }
]')

sed "s/##_DOMAIN_##/${DOMAIN}/g" /sing-box.tmpl.json |
  jq \
    --argjson trojan "$TROJAN_USERS" \
    --argjson hysteria2 "$HYSTERIA2_USERS" \
    --argjson anytls "$ANYTLS_USERS" \
    --argjson vmess "$VMESS_USERS" '
      .inbounds |= map(
        if .tag == "trojan-in" then .users = $trojan
        elif .tag == "hysteria2-in" then .users = $hysteria2
        elif .tag == "anytls-in" then .users = $anytls
        elif .tag == "vmess-wss-in" then .users = $vmess
        else . end
      )
    ' > /conf/config.json

jq -e . /conf/config.json >/dev/null
chmod 600 /conf/config.json
