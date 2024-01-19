#!/bin/ash

USER_DATA=$(awk '{printf "%s", $0}' /users.json)
sed -e 's|"##_USERS_##"|'"$USER_DATA"'|g' /v2ray-server.json > /conf/v2ray-server.json