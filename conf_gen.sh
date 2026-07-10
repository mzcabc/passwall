#!/bin/ash
apk add --no-cache jq > /dev/null 2>&1

# Keep the legacy array compatible with Cloudflare KV/gq while allowing optional
# per-protocol overrides under .protocols.
DISABLED_USERS_JSON=$(printf '%s' "${DISABLED_USERS:-}" | jq -Rc 'split(",") | map(select(length > 0))')
ACTIVE_USERS=$(jq -c --argjson disabled "$DISABLED_USERS_JSON" '[
  .[]
  | select(.enabled // true)
  | select(.email as $email | ($disabled | index($email) | not))
]' /users.json)

# v2ray config: only pass fields understood by VMess.
USER_DATA=$(echo "$ACTIVE_USERS" | jq -c '[.[] | select(.protocols.vmess.enabled // true) | {
  id: (.protocols.vmess.id // .id),
  email: .email,
  level: 0
}]')
sed -e 's|"##_USERS_##"|'"$USER_DATA"'|g' /v2ray.tmpl.json > /conf/v2ray.json

# hysteria config: replace userpass placeholder with users from users.json
HY_USERS=$(echo "$ACTIVE_USERS" | jq -r '[.[] | select(.protocols.hysteria2.enabled // true) | "    " + .email + ": " + (.protocols.hysteria2.password // .id)] | join("\n")')
awk -v users="$HY_USERS" -v secret="$HYSTERIA_API_SECRET" '
  {gsub(/    ##_HYSTERIA_USERS_##/, users); gsub(/##_HYSTERIA_API_SECRET_##/, secret); print}
' /hysteria.tmpl.yml > /conf/hysteria.yml

# AnyTLS config.
ANYTLS_USERS=$(echo "$ACTIVE_USERS" | jq -c '[.[] | select(.protocols.anytls.enabled // true) | {
  name: .email,
  password: (.protocols.anytls.password // .id)
}]')
sed -e 's|"##_ANYTLS_USERS_##"|'"$ANYTLS_USERS"'|g' /anytls.tmpl.json > /conf/anytls.json

jq -e . /conf/v2ray.json >/dev/null
jq -e . /conf/anytls.json >/dev/null
