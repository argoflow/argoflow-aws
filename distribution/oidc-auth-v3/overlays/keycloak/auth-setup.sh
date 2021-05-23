#!/bin/bash

COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(16)).decode())')
OIDC_CLIENT_ID="oauth2-proxy"
OIDC_CLIENT_SECRET="129789cf-c0b6-466b-87fa-512a60b2fd9a"

kubectl create secret generic -n auth oauth2-proxy --from-literal=client-id=${OIDC_CLIENT_ID} --from-literal=client-secret=${OIDC_CLIENT_SECRET} --from-literal=cookie-secret=${COOKIE_SECRET} --dry-run=client -o yaml | kubeseal | yq eval -P > oauth2-proxy-secret.yaml

# read -p 'Email: ' EMAIL
# read -p 'Username: ' USERNAME

# ADMIN_PASS=$(python3 -c 'from passlib.hash import bcrypt; import getpass; print(bcrypt.using(rounds=12, ident="2y").hash(getpass.getpass()))')

# read -p 'GitLab Client ID: ' GITLAB_ID
# read -p 'GitLab Client Secret: ' GITLAB_SECRET

# yq eval ".staticClients[0].id = \"${OIDC_CLIENT_ID}\" | .staticClients[0].secret = \"${OIDC_CLIENT_SECRET}\" | .staticPasswords[0].hash = \"${ADMIN_PASS}\" | .staticPasswords[0].email = \"${EMAIL}\" | .staticPasswords[0].username = \"${USERNAME}\" | .connectors[0].config.clientID = \"${GITLAB_ID}\" | .connectors[0].config.clientSecret = \"${GITLAB_SECRET}\"" dex-config-template.yaml | kubectl create secret generic -n auth dex-config --dry-run=client --from-file=config.yaml=/dev/stdin -o yaml | kubeseal | yq eval -P > dex-config-secret.yaml
