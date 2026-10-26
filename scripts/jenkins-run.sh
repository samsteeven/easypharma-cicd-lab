#!/usr/bin/env bash
# Déclenche le job Jenkins, attend la fin et affiche le résultat et la durée de chaque étape.
# Utilisation : scripts/jenkins-run.sh [paramètre=valeur ...]   (ex. RUN_SONAR=false)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
J=http://localhost:8080
JOB=easypharma-backend
AUTH="admin:$JENKINS_ADMIN_PASSWORD"
jar=$(mktemp)
crumb=$(curl -s -c "$jar" -u "$AUTH" "$J/crumbIssuer/api/json" | python -c 'import sys,json; d=json.load(sys.stdin); print(d["crumbRequestField"]+":"+d["crumb"])')

next=$(curl -s -u "$AUTH" "$J/job/$JOB/api/json" | python -c 'import sys,json; print(json.load(sys.stdin)["nextBuildNumber"])')

# Dès que le job a des paramètres, seule l'URL buildWithParameters est acceptée (sans paramètre : valeurs par défaut).
if [ $# -gt 0 ]; then
  query=$(printf '%s&' "$@")
  url="$J/job/$JOB/buildWithParameters?${query%&}"
else
  url="$J/job/$JOB/buildWithParameters"
fi
code=$(curl -s -b "$jar" -u "$AUTH" -H "$crumb" -X POST "$url" -o /dev/null -w '%{http_code}')
if [ "$code" = "400" ] && [ $# -eq 0 ]; then
  # Après un redémarrage, JCasC recrée le job sans ses paramètres (ils ne sont connus qu'après une première exécution) :
  # seule l'URL « build » est alors acceptée.
  code=$(curl -s -b "$jar" -u "$AUTH" -H "$crumb" -X POST "$J/job/$JOB/build" -o /dev/null -w '%{http_code}')
fi
echo "declenchement : HTTP $code"
if [ "$code" != "201" ]; then
  echo "Jenkins a refuse le declenchement"
  exit 1
fi

echo "build #$next..."
deadline=$((SECONDS + 1500))
while [ $SECONDS -lt $deadline ]; do
  building=$(curl -s -u "$AUTH" "$J/job/$JOB/$next/api/json" 2>/dev/null \
    | python -c 'import sys,json; print(json.load(sys.stdin).get("building","wait"))' 2>/dev/null || echo wait)
  [ "$building" = "False" ] && break
  sleep 5
done

curl -s -u "$AUTH" "$J/job/$JOB/$next/wfapi/describe" | python -c '
import sys, json
d = json.load(sys.stdin)
print("resultat :", d["status"], "| duree totale : %.1f s" % (d["durationMillis"] / 1000))
for s in d["stages"]:
    print("  %-28s %-10s %6.1f s" % (s["name"], s["status"], s["durationMillis"] / 1000))
'
