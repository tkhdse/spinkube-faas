#!/usr/bin/env bash
set -euo pipefail

# Rejoin this host as a fresh k3s worker.
# Usage:
#   sudo ./rejoin-k3s-worker.sh \
#     --server https://<CONTROL_PLANE_IP>:6443 \
#     --token <NODE_TOKEN> \
#     [--data-dir /srv/k3s]
#
# Example:
#   sudo ./rejoin-k3s-worker.sh \
#     --server https://172.22.152.174:6443 \
#     --token K10abc...::server:xyz \
#     --data-dir /srv/k3s

SERVER_URL=""
NODE_TOKEN=""
DATA_DIR="/srv/k3s"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)
      SERVER_URL="${2:-}"; shift 2 ;;
    --token)
      NODE_TOKEN="${2:-}"; shift 2 ;;
    --data-dir)
      DATA_DIR="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --server <https://IP:6443> --token <node-token> [--data-dir /srv/k3s]"
      exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1 ;;
  esac
done

if [[ -z "$SERVER_URL" || -z "$NODE_TOKEN" ]]; then
  echo "ERROR: --server and --token are required." >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

echo "==> Stopping old k3s agent if present"
systemctl disable --now k3s-agent 2>/dev/null || true
/usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true

echo "==> Cleaning stale k3s/kubelet/cni state"
rm -rf /etc/rancher/k3s \
       /var/lib/rancher/k3s \
       /var/lib/kubelet \
       /var/lib/cni \
       /etc/cni/net.d \
       "$DATA_DIR"

echo "==> Installing/rejoining k3s agent"
curl -sfL https://get.k3s.io | K3S_URL="$SERVER_URL" K3S_TOKEN="$NODE_TOKEN" sh -s - agent --data-dir "$DATA_DIR"

echo "==> Enabling and starting agent"
systemctl enable --now k3s-agent

echo "==> Local verification"
systemctl --no-pager --full status k3s-agent | sed -n '1,25p' || true
echo "Rejoin complete for host: $(hostname -f)"