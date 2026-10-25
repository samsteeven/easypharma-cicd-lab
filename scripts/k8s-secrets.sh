#!/usr/bin/env bash
# Crée le secret « easypharma-secrets » (JWT_SECRET, DATABASE_PASSWORD) avec des valeurs aléatoires, hors de Git.
# En production : External Secrets, Sealed Secrets ou le coffre de l'équipe. Rien n'est affiché.
set -euo pipefail
NS=${1:-easypharma}
CTX=kind-easypharma

kubectl --context "$CTX" get namespace "$NS" >/dev/null 2>&1 || kubectl --context "$CTX" create namespace "$NS"
if kubectl --context "$CTX" -n "$NS" get secret easypharma-secrets >/dev/null 2>&1; then
  echo "Le secret existe déjà dans $NS."
  exit 0
fi
kubectl --context "$CTX" -n "$NS" create secret generic easypharma-secrets \
  --from-literal=JWT_SECRET="$(python -c 'import secrets,base64; print(base64.b64encode(secrets.token_bytes(48)).decode())')" \
  --from-literal=DATABASE_PASSWORD="$(python -c 'import secrets; print(secrets.token_hex(12))')" >/dev/null
echo "Secret créé dans $NS."
