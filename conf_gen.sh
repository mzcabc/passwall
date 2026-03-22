#!/bin/ash
apk add --no-cache jq > /dev/null 2>&1

# v2ray config
USER_DATA=$(jq -c '.' /users.json)
sed -e 's|"##_USERS_##"|'"$USER_DATA"'|g' /v2ray.tmpl.json > /conf/v2ray.json

# hysteria config: replace userpass placeholder with users from users.json
HY_USERS=$(jq -r '[.[] | "    " + .email + ": " + .id] | join("\n")' /users.json)
awk -v users="$HY_USERS" '{gsub(/    ##_HYSTERIA_USERS_##/, users); print}' /hysteria.tmpl.yml > /conf/hysteria.yml
