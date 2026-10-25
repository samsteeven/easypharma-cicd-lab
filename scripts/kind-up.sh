#!/usr/bin/env bash
# Phase 2 : crée le cluster kind et le relie au registre local (celui de la pile Jenkins, port 5001 sur l'hôte).
# Les noeuds kind lisent « localhost:5001/... » grâce à un fichier hosts.toml de containerd qui redirige vers le
# conteneur du registre, joint au réseau Docker « kind ».
set -euo pipefail
cd "$(dirname "$0")/.."

CLUSTER=easypharma
REGISTRY_CONTAINER=easypharma-cicd-registry-1   # voir docker-compose.yml (nom du projet + service + index)

if ! docker ps --format '{{.Names}}' | grep -qx "$REGISTRY_CONTAINER"; then
  echo "Le registre ($REGISTRY_CONTAINER) ne tourne pas : docker compose up -d registry"
  exit 1
fi

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "Le cluster $CLUSTER existe déjà."
else
  kind create cluster --config kind/cluster.yaml
fi

# Redirection de localhost:5001 vers le registre, pour chaque noeud.
for node in $(kind get nodes --name "$CLUSTER"); do
  docker exec "$node" mkdir -p /etc/containerd/certs.d/localhost:5001
  printf 'server = "http://%s:5000"\n[host."http://%s:5000"]\n  capabilities = ["pull", "resolve"]\n' \
    "$REGISTRY_CONTAINER" "$REGISTRY_CONTAINER" \
    | docker exec -i "$node" sh -c 'cat > /etc/containerd/certs.d/localhost:5001/hosts.toml'
done

# Le registre doit être joignable depuis le réseau des noeuds.
docker network connect kind "$REGISTRY_CONTAINER" 2>/dev/null || true
echo "Cluster prêt : kubectl --context kind-$CLUSTER get nodes"
