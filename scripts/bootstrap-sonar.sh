#!/usr/bin/env bash
# Prépare SonarQube après son premier démarrage :
#   1. attend qu'il soit prêt ; 2. remplace le mot de passe admin par défaut ; 3. crée un jeton d'analyse
#   (écrit dans .env) ; 4. déclare le webhook vers Jenkins (nécessaire à « waitForQualityGate »).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
SONAR=http://localhost:9000

echo "Attente de SonarQube…"
for i in $(seq 1 90); do
  status=$(curl -s "$SONAR/api/system/status" | python -c 'import sys,json; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)
  [ "$status" = "UP" ] && break
  sleep 5
done
[ "$status" = "UP" ] || { echo "SonarQube n'est pas prêt (statut : ${status:-aucun})"; exit 1; }

# Le mot de passe par défaut est « admin » tant qu'il n'a pas été changé.
if curl -s -o /dev/null -w '%{http_code}' -u "admin:admin" "$SONAR/api/authentication/validate" | grep -q 200 \
   && curl -s -u admin:admin "$SONAR/api/authentication/validate" | grep -q '"valid":true'; then
  curl -s -u admin:admin -X POST "$SONAR/api/users/change_password" \
       --data-urlencode "login=admin" --data-urlencode "previousPassword=admin" \
       --data-urlencode "password=$SONAR_ADMIN_PASSWORD" -o /dev/null
  echo "Mot de passe admin remplacé."
fi

if [ -z "${SONAR_TOKEN:-}" ]; then
  token=$(curl -s -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "$SONAR/api/user_tokens/generate" \
          --data-urlencode "name=jenkins-$(date +%s)" | python -c 'import sys,json; print(json.load(sys.stdin)["token"])')
  sed -i "s|^SONAR_TOKEN=.*|SONAR_TOKEN=$token|" .env
  echo "Jeton d'analyse créé et écrit dans .env."
fi

curl -s -u "admin:$SONAR_ADMIN_PASSWORD" -X POST "$SONAR/api/webhooks/create" \
     --data-urlencode "name=jenkins" --data-urlencode "url=http://jenkins:8080/sonarqube-webhook/" -o /dev/null || true
echo "Webhook Jenkins déclaré. SonarQube est prêt."
