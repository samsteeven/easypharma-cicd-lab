#!/usr/bin/env bash
# Valide un Jenkinsfile déclaratif avec le linter du serveur Jenkins, avant de pousser.
# Utilisation : scripts/jenkins-lint.sh [Jenkinsfile]
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
J=http://localhost:8080
AUTH="admin:$JENKINS_ADMIN_PASSWORD"
FILE=${1:-Jenkinsfile}

jar=$(mktemp)
crumb=$(curl -s -c "$jar" -u "$AUTH" "$J/crumbIssuer/api/json" | python -c 'import sys,json; d=json.load(sys.stdin); print(d["crumbRequestField"]+":"+d["crumb"])')
curl -s -b "$jar" -u "$AUTH" -H "$crumb" -X POST -F "jenkinsfile=<$FILE" "$J/pipeline-model-converter/validate"
