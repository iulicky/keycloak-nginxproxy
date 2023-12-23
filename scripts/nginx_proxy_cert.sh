#!/usr/bin/env bash

NGINX_HOST="<your.nginx.local.ip or hostname>"
NGINX_PORT="81"
IDENTITY="<your_nginx_admin_user_email>"
NGINX_PASSWORD="<your_nginx_admin_user_password>"

DOMAIN_NAMES="domain.example.com" #domain which will host https certificate from lets encrypt
FORWARD_HOST="<your.keycloak.local.ip or hostname>"
FORWARD_PORT="8080" #local keycloak port where listens to nginx reverse proxy calls
EMAIL="<admin@example.com>"

NGINX_TOKEN_FULL=$(curl -X POST \
    "http://${NGINX_HOST}:${NGINX_PORT}/api/tokens" \
    -H "Content-Type: application/json" \
    -d "{\"type\": \"password\", \"identity\": \"${IDENTITY}\", \"secret\": \"${NGINX_PASSWORD}\"}"
)

NGINX_TOKEN=$(echo $NGINX_TOKEN_FULL | jq -r .token)



## create your nginx proxy host for keycloak with letsencrypt certificate for domain domain.example.com
curl -X POST "http://${NGINX_HOST}:${NGINX_PORT}/api/nginx/proxy-hosts" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $NGINX_TOKEN" \
  -H 'accept: application/json' \
  -d @- <<EOF
{
  "domain_names": ["${DOMAIN_NAMES}"],
  "forward_scheme": "http",
  "forward_host": "${FORWARD_HOST}",
  "forward_port": "${FORWARD_PORT}",
  "caching_enabled": true,
  "block_exploits": true,
  "allow_websocket_upgrade": true,
  "access_list_id": "0",
  "certificate_id": "new",
  "ssl_forced": true,
  "meta": {
    "letsencrypt_email": "${EMAIL}",
    "letsencrypt_agree": true,
    "dns_challenge": false
  },
  "advanced_config": "",
  "locations": [],
  "http2_support": true,
  "hsts_enabled": true,
  "hsts_subdomains": true
}
EOF
