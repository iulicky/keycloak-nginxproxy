#!/usr/bin/env bash

#run ./gettoken.sh $BOOK_SERVICE_CLIENT_SECRET

CLIENT_SECRET=${1}
KEYCLOAK_HOST_PORT=${2:-"<domain.example.com>"}
USER=${3:-"<your_keycloak_user>"}
PASSWORD=${4:-"<your_keycloak_password>"}


if [ -z "$CLIENT_SECRET" ]; then
    echo "Error: CLIENT_SECRET is required."
    exit 1
fi

MY_ACCESS_TOKEN_FULL=$(curl -s -k -X POST \
  "https://${KEYCLOAK_HOST_PORT}/realms/company-services/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$USER" \
  -d "password=$PASSWORD" \
  -d "grant_type=password" \
  -d "client_secret="$CLIENT_SECRET"" \
  -d "client_id=book-service"
  )

if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve the access token."
    exit 1
fi

ACCESS_TOKEN=$(echo "$MY_ACCESS_TOKEN_FULL" | jq -r .access_token)
echo "$ACCESS_TOKEN"