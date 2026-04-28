#!/usr/bin/env bash
set -euo pipefail

# Rejoin THIS host as k3s worker using DEFAULT data dir.
# Required env:
#   K3S_URL=https://<control-plane-ip>:6443
#   K3S_TOKEN=<node-token>
#
# Usage:
#   sudo K3S_URL=... K3S_TOKEN=... ./rejoin_node_default.sh

[[ -n "${K3S_URL:-}" ]] || { echo "K3S_URL is required"; exit 1; }
[[ -n "${K3S_TOKEN:-}" ]] || { echo "K3S_TOKEN is required"; exit 1; }

echo "[1/5] stopping old agent"
sudo systemctl disable --now k3s-agent 2>/dev/null || true
sudo /usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || true

echo "[2/5] cleaning old state"
sudo rm -rf /etc/rancher/k3s /srv/k3s /var/lib/rancher/k3s /var/lib/kubelet /var/lib/cni /etc/cni/net.d

echo "[3/5] installing k3s agent with DEFAULT data-dir"
curl -sfL https://get.k3s.io | K3S_URL="${K3S_URL}" K3S_TOKEN="${K3S_TOKEN}" sh -s - agent

echo "[4/5] enabling agent"
sudo systemctl enable --now k3s-agent

echo "[5/5] local verify"
sudo systemctl --no-pager --full status k3s-agent | sed -n '1,25p'
echo "OK: rejoin complete on $(hostname -f)"