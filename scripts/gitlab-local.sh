#!/usr/bin/env bash
# Exécute le .gitlab-ci.yml avec gitlab-ci-local, lui-même dans un conteneur (gitlab/Dockerfile).
# Les jobs sont de vrais conteneurs Docker lancés sur l'hôte. Ce n'est PAS un vrai GitLab : voir « Limites » du README.
# Utilisation : scripts/gitlab-local.sh [job ...]   (sans argument : tout le pipeline)
set -euo pipefail
cd "$(dirname "$0")/.."
export MSYS_NO_PATHCONV=1
docker build -q -t easypharma-gitlab-ci-local gitlab >/dev/null

# Variables du pipeline pour gitlab-ci-local, régénérées à chaque exécution à partir de .env : un jeton SonarQube
# recopié une fois à la main devient faux dès que le serveur est recréé (HTTP 401 à l'analyse).
set -a; . ./.env; set +a
{ echo "SONAR_TOKEN: \"$SONAR_TOKEN\""; echo 'SONAR_HOST_URL: "http://host.docker.internal:9000"'; } > .gitlab-ci-local-variables.yml
start=$(date +%s)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD":/workspace \
  easypharma-gitlab-ci-local --volume /var/run/docker.sock:/var/run/docker.sock "$@"
echo "duree murale totale : $(( $(date +%s) - start )) s"
