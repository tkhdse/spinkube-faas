#!/usr/bin/env bash
set -euo pipefail

CFG="${1:-bench-actions.json}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing $1"; exit 1; }; }
need jq
need kubectl

NS="$(jq -r '.namespace' "$CFG")"
EXECUTOR="$(jq -r '.executor' "$CFG")"
REPLICAS="$(jq -r '.replicas' "$CFG")"

kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

jq -r '.actions | to_entries[] | "\(.key) \(.value)"' "$CFG" | while read -r NAME IMAGE; do
  cat <<EOF | kubectl apply -n "$NS" -f -
apiVersion: core.spinkube.dev/v1alpha1
kind: SpinApp
metadata:
  name: ${NAME}
spec:
  image: ${IMAGE}
  executor: ${EXECUTOR}
  replicas: ${REPLICAS}
EOF
done

echo "Waiting for deployments..."
for NAME in $(jq -r '.actions | keys[]' "$CFG"); do
  kubectl -n "$NS" rollout status "deploy/${NAME}" --timeout=180s
done

echo "Done."
kubectl -n "$NS" get spinapps
kubectl -n "$NS" get svc