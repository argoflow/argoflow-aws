read -p 'Username: ' USERNAME
read -p 'Password: ' ADMIN_PASS

kubectl create secret generic -n monitoring grafana-admin-secret --from-literal=admin-user=${USERNAME} --from-literal=admin-password=${ADMIN_PASS} --dry-run=client -o yaml | kubeseal | yq eval -P > grafana-admin-secret.yaml