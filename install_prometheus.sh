#!/usr/bin/env bash
set -euo pipefail

# Installs kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
# Usage:
#   ./install_prometheus.sh
# Optional env vars:
#   RELEASE_NAME=kube-prom
#   NAMESPACE=monitoring
#   GRAFANA_NODEPORT=32000
#   PROM_NODEPORT=32090

RELEASE_NAME="${RELEASE_NAME:-kube-prom}"
NAMESPACE="${NAMESPACE:-monitoring}"
GRAFANA_NODEPORT="${GRAFANA_NODEPORT:-32000}"
PROM_NODEPORT="${PROM_NODEPORT:-32090}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: Required command not found: $1"
    exit 1
  }
}

echo "[1/6] Checking prerequisites..."
need_cmd kubectl
need_cmd helm

echo "[2/6] Ensuring cluster is reachable..."
kubectl get nodes >/dev/null

echo "[3/6] Adding/updating Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "[4/6] Installing kube-prometheus-stack..."
helm upgrade --install "$RELEASE_NAME" prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort="$GRAFANA_NODEPORT" \
  --set prometheus.service.type=NodePort \
  --set prometheus.service.nodePort="$PROM_NODEPORT" \
  --wait

echo "[5/6] Waiting for rollout..."
kubectl -n "$NAMESPACE" rollout status deploy/"$RELEASE_NAME"-grafana --timeout=300s
kubectl -n "$NAMESPACE" get pods

echo "[6/6] Done."
echo
echo "Prometheus namespace: $NAMESPACE"
echo "Grafana NodePort:     $GRAFANA_NODEPORT"
echo "Prometheus NodePort:  $PROM_NODEPORT"
echo
echo "Get server node IP:"
echo "  kubectl get nodes -o wide"
echo
echo "Open in browser:"
echo "  Grafana   -> http://<server-node-ip>:${GRAFANA_NODEPORT}"
echo "  Prometheus-> http://<server-node-ip>:${PROM_NODEPORT}"
echo
echo "Grafana admin password:"
echo "  kubectl -n $NAMESPACE get secret ${RELEASE_NAME}-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"