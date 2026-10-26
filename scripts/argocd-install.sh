#!/usr/bin/env bash
# Installe ArgoCD (version fixée) dans le cluster kind et déclare l'application EasyPharma.
# Pour économiser la mémoire (Docker : 8 Go), on arrête Dex (SSO), les notifications et l'ApplicationSet,
# dont ce laboratoire n'a pas besoin.
set -euo pipefail
cd "$(dirname "$0")/.."
CTX=kind-easypharma
ARGOCD_VERSION=v3.5.6
K="kubectl --context $CTX"

$K get namespace argocd >/dev/null 2>&1 || $K create namespace argocd
# --server-side : les CRD d'ArgoCD dépassent la taille d'annotation acceptée par un apply classique.
$K apply -n argocd --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_VERSION/manifests/install.yaml" >/dev/null
$K -n argocd scale deployment argocd-dex-server argocd-notifications-controller argocd-applicationset-controller --replicas=0 >/dev/null

echo "Attente d'ArgoCD…"
$K -n argocd rollout status deployment/argocd-server --timeout=300s
$K -n argocd rollout status deployment/argocd-repo-server --timeout=300s
$K -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

$K apply -f argocd/application.yaml
echo "Application déclarée : kubectl --context $CTX -n argocd get applications"
