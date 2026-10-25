#!/usr/bin/env bash
# Déclenche le job Jenkins, attend la fin et affiche le résultat et la durée de chaque étape.
# Utilisation : scripts/jenkins-run.sh [paramètre=valeur ...]   (ex. RUN_SONAR=false)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
J=http://localhost:8080
JOB=easypharma-backend
jar=$(mktemp)
crumb=$(curl -s -c "$jar" -u "admin:$JENKINS_ADMIN_PASSWORD" "$J/crumbIssuer/api/json" | python -c 'import sys,json; d=json.load(sys.stdin); print(d["crumbRequestField"]+":"+d["crumb"])')

last=$(curl -s -u "admin:$JENKINS_ADMIN_PASSWORD" "$J/job/$JOB/api/json" | python -c 'import sys,json; print((json.load(sys.stdin).get("lastBuild") or {}).get("number",0))')
if [ $# -gt 0 ]; then
  query=$(printf '%s&' "$@"); url="$J/job/$JOB/buildWithParameters?${query%&}"
else
  url="$J/job/$JOB/build"
fi
curl -s -b "$jar" -u "admin:$JENKINS_ADMIN_PASSWORD" -H "$crumb" -X POST "$url" -o /dev/null -w 'déclenchement : HTTP %{http_code}\n'

n=$((last+1))
echo "build #$n…"
while true; do
  info=$(curl -s -u "admin:$JENKINS_ADMIN_PASSWORD" "$J/job/$JOB/$n/api/json" 2>/dev/null || true)
  building=$(echo "$info" | python -c 'import sys,json; d=json.load(sys.stdin); print(d.get("building","wait"))' 2>/dev/null || echo wait)
  [ "$building" = "False" ] && break
  sleep 5
done
curl -s -u "admin:$JENKINS_ADMIN_PASSWORD" "$J/job/$JOB/$n/wfapi/describe" | python -c '
import sys, json
d = json.load(sys.stdin)
print("résultat :", d["status"], "| durée totale : %.1f s" % (d["durationMillis"]/1000))
for s in d["stages"]:
    print("  %-28s %-10s %6.1f s" % (s["name"], s["status"], s["durationMillis"]/1000))
'
