#!/usr/bin/env bash
# Exécute le .gitlab-ci.yml avec gitlab-ci-local, lui-même dans un conteneur (gitlab/Dockerfile).
# Les jobs sont de vrais conteneurs Docker lancés sur l'hôte. Ce n'est PAS un vrai GitLab : voir « Limites » du README.
# Utilisation : scripts/gitlab-local.sh [job ...]   (sans argument : tout le pipeline)
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
docker build -q -t easypharma-gitlab-ci-local gitlab >/dev/null
start=$(date +%s)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD":/workspace \
  easypharma-gitlab-ci-local --volume /var/run/docker.sock:/var/run/docker.sock "$@"
echo "duree murale totale : $(( $(date +%s) - start )) s"
