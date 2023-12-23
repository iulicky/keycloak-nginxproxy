#!/usr/bin/env bash

# define your variables here OR export as environment variables  
NGINX_HOST="<your.nginx.local.ip or hostname>"
IDENTITY="<your_nginx_admin_user_email>"
NGINX_PASSWORD="<your_nginx_admin_user_password>"
NGINX_PORT="81"

NGINX_TOKEN_FULL=$(curl -X POST \
    "http://${NGINX_HOST}:${NGINX_PORT}/api/tokens" \
    -H "Content-Type: application/json" \
    -d "{\"type\": \"password\", \"identity\": \"${IDENTITY}\", \"secret\": \"${NGINX_PASSWORD}\"}"
)


NGINX_TOKEN=$(echo $NGINX_TOKEN_FULL | jq -r .token)

## check assigned tokens
curl -X GET "http://${NGINX_HOST}:${NGINX_PORT}/api/tokens" \
      -H "Authorization: Bearer $NGINX_TOKEN" \
      -H 'accept: application/json' | jq

## check current proxy hosts with settings
curl -X GET "http://${NGINX_HOST}:${NGINX_PORT}/api/nginx/proxy-hosts" \
      -H "Authorization: Bearer $NGINX_TOKEN" \
      -H 'accept: application/json' | jq

