#!/usr/bin/env bash
# Crée le secret « easypharma-secrets » (JWT_SECRET, DATABASE_PASSWORD, RABBITMQ_PASSWORD) avec des valeurs aléatoires,
# hors de Git. Idempotent : une clé déjà présente n'est jamais modifiée (le mot de passe de PostgreSQL est déjà dans
# son volume), une clé manquante est ajoutée. Rien n'est affiché.
# En production : External Secrets, Sealed Secrets ou le coffre de l'équipe.
set -euo pipefail
NS=${1:-easypharma}
CTX=kind-easypharma
K="kubectl --context $CTX"

random_b64() { python -c 'import secrets,base64; print(base64.b64encode(secrets.token_bytes(48)).decode())'; }
random_hex() { python -c 'import secrets; print(secrets.token_hex(12))'; }

$K get namespace "$NS" >/dev/null 2>&1 || $K create namespace "$NS"

if ! $K -n "$NS" get secret easypharma-secrets >/dev/null 2>&1; then
  $K -n "$NS" create secret generic easypharma-secrets \
    --from-literal=JWT_SECRET="$(random_b64)" \
    --from-literal=DATABASE_PASSWORD="$(random_hex)" \
    --from-literal=RABBITMQ_PASSWORD="$(random_hex)" >/dev/null
  echo "Secret créé dans $NS."
  exit 0
fi

for key in JWT_SECRET DATABASE_PASSWORD RABBITMQ_PASSWORD; do
  if [ -z "$($K -n "$NS" get secret easypharma-secrets -o "jsonpath={.data.$key}")" ]; then
    value=$([ "$key" = JWT_SECRET ] && random_b64 || random_hex)
    $K -n "$NS" patch secret easypharma-secrets --type merge \
      -p "{\"stringData\":{\"$key\":\"$value\"}}" >/dev/null
    echo "Clé $key ajoutée."
  fi
done
echo "Secret à jour dans $NS."
