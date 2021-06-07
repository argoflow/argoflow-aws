#!/bin/bash
DISTRIBUTION_PATH="./distribution"
COOKIE_SECRET=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(16)).decode())')
OIDC_CLIENT_ID=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
OIDC_CLIENT_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

kubectl create secret generic -n auth oauth2-proxy --from-literal=client-id=${OIDC_CLIENT_ID} --from-literal=client-secret=${OIDC_CLIENT_SECRET} --from-literal=cookie-secret=${COOKIE_SECRET} --dry-run=client -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/dex/oauth2-proxy-secret.yaml
kubectl create secret generic -n auth oauth2-proxy --from-literal=client-id=${OIDC_CLIENT_ID} --from-literal=client-secret=${OIDC_CLIENT_SECRET} --from-literal=cookie-secret=${COOKIE_SECRET} --dry-run=client -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/oauth2-proxy-secret.yaml

DATABASE_PASS=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
POSTGRESQL_PASS=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
KEYCLOAK_ADMIN_PASS=$(python3 -c 'import secrets; print(secrets.token_hex(16))')
KEYCLOAK_MANAGEMENT_PASS=$(python3 -c 'import secrets; print(secrets.token_hex(16))')

kubectl create secret generic -n auth keycloak-secret --from-literal=admin-password=${KEYCLOAK_ADMIN_PASS} --from-literal=database-password=${DATABASE_PASS} --from-literal=management-password=${KEYCLOAK_MANAGEMENT_PASS} --dry-run=client -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/keycloak-secret.yaml
kubectl create secret generic -n auth keycloak-postgresql --from-literal=postgresql-password=${DATABASE_PASS} --from-literal=postgresql-postgres-password=${POSTGRESQL_PASS} --dry-run=client -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/postgresql-secret.yaml

email=${email:-admin@argoflow.org}
username=${username:-admin}
firstname=${firstname:-admin}
lastname=${lastname:-admin}
password=${password:-$(python3 -c 'import secrets; print(secrets.token_hex(16))')}

while [ $# -gt 0 ]; do

   if [[ $1 == *"--"* ]]; then
        param="${1/--/}"
        declare $param="$2"
        # echo $1 $2 // Optional to see the parameter:value result
   fi

  shift
done

ADMIN_PASS_DEX=$(python3 -c "from passlib.hash import bcrypt; print(bcrypt.using(rounds=12, ident='2y').hash(\"${password}\"))")

yq eval -i ".data.ADMIN = \"${email}\"" ${DISTRIBUTION_PATH}/kubeflow/notebooks/profile-controller_access-management/patch-admin.yaml

yq eval ".staticClients[0].id = \"${OIDC_CLIENT_ID}\" | .staticClients[0].secret = \"${OIDC_CLIENT_SECRET}\" | .staticPasswords[0].hash = \"${ADMIN_PASS_DEX}\" | .staticPasswords[0].email = \"${email}\" | .staticPasswords[0].username = \"${username}\"" ${DISTRIBUTION_PATH}/oidc-auth/overlays/dex/dex-config-template.yaml | kubectl create secret generic -n auth dex-config --dry-run=client --from-file=config.yaml=/dev/stdin -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/dex/dex-config-secret.yaml
yq eval -j -P ".users[0].username = \"${username}\" | .users[0].email = \"${email}\" | .users[0].firstName = \"${firstname}\" | .users[0].lastName = \"${lastname}\" | .users[0].credentials[0].value = \"${password}\" | .clients[0].clientId = \"${OIDC_CLIENT_ID}\" | .clients[0].secret = \"${OIDC_CLIENT_SECRET}\"" ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/kubeflow-realm-template.json | kubectl create secret generic -n auth kubeflow-realm --dry-run=client --from-file=kubeflow-realm.json=/dev/stdin -o json | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/oidc-auth/overlays/keycloak/kubeflow-realm-secret.yaml

kubectl create secret generic -n monitoring grafana-admin-secret --from-literal=admin-user=${username} --from-literal=admin-password=${password} --dry-run=client -o yaml | kubeseal | yq eval -P > ${DISTRIBUTION_PATH}/monitoring-resources/grafana-admin-secret.yaml
