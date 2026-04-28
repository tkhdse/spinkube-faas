#!/usr/bin/env bash
set -euo pipefail

# k3s bootstrap script
# Modes:
#   server: install k3s control-plane/server
#   agent : join node as worker/agent
#
# Examples:
#   ./k3s-bootstrap.sh server
#   ./k3s-bootstrap.sh agent --server-url https://10.0.0.10:6443 --token K10...::server:...
#
# Optional env:
#   INSTALL_K3S_VERSION=v1.30.5+k3s1

ROLE="${1:-}"
shift || true

SERVER_URL=""
TOKEN=""
K3S_VERSION="${INSTALL_K3S_VERSION:-}"

usage() {
  cat <<EOF
Usage:
  $0 server [--node-ip <ip>] [--flannel-iface <iface>]
  $0 agent  --server-url <https://server:6443> --token <token> [--node-ip <ip>] [--flannel-iface <iface>]

Options:
  --server-url      k3s server URL for agent join (required in agent mode)
  --token           k3s node token for agent join (required in agent mode)
  --node-ip         advertise specific node IP
  --flannel-iface   network interface for flannel
  -h, --help        show this help

Notes:
- Run as root or with sudo.
- Open firewall port 6443/TCP to the server from agents.
EOF
}

NODE_IP=""
FLANNEL_IFACE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-url) SERVER_URL="${2:-}"; shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --node-ip) NODE_IP="${2:-}"; shift 2 ;;
    --flannel-iface) FLANNEL_IFACE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$ROLE" ]]; then
  usage
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or: sudo $0 ...)"
  exit 1
fi

log() { echo -e "\n[k3s-bootstrap] $*"; }

check_deps() {
  command -v curl >/dev/null 2>&1 || { echo "curl is required"; exit 1; }
  command -v systemctl >/dev/null 2>&1 || { echo "systemctl is required"; exit 1; }
}

build_install_args() {
  local args=()
  [[ -n "$NODE_IP" ]] && args+=("--node-ip" "$NODE_IP")
  [[ -n "$FLANNEL_IFACE" ]] && args+=("--flannel-iface" "$FLANNEL_IFACE")
  echo "${args[*]:-}"
}

install_server() {
  log "Installing k3s server"
  local extra_args
  extra_args="$(build_install_args)"

  if [[ -n "$K3S_VERSION" ]]; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s - server --write-kubeconfig-mode 644 $extra_args
  else
    curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644 $extra_args
  fi

  log "Waiting for k3s server service"
  systemctl is-active --quiet k3s || { echo "k3s service is not active"; systemctl status k3s --no-pager; exit 1; }

  local token
  token="$(cat /var/lib/rancher/k3s/server/node-token)"

  local server_ip
  server_ip="$(hostname -I | awk '{print $1}')"

  log "k3s server installed successfully"
  echo "Server URL: https://${server_ip}:6443"
  echo "Node token: ${token}"
  echo
  echo "Join command for workers:"
  echo "curl -sfL https://get.k3s.io | K3S_URL=https://${server_ip}:6443 K3S_TOKEN='${token}' sh -"
  echo
  echo "Check cluster:"
  echo "sudo k3s kubectl get nodes -o wide"
}

install_agent() {
  [[ -z "$SERVER_URL" ]] && { echo "--server-url is required in agent mode"; exit 1; }
  [[ -z "$TOKEN" ]] && { echo "--token is required in agent mode"; exit 1; }

  log "Installing k3s agent and joining cluster"
  local extra_args
  extra_args="$(build_install_args)"

  if [[ -n "$K3S_VERSION" ]]; then
    curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" K3S_URL="$SERVER_URL" K3S_TOKEN="$TOKEN" sh -s - agent $extra_args
  else
    curl -sfL https://get.k3s.io | K3S_URL="$SERVER_URL" K3S_TOKEN="$TOKEN" sh -s - agent $extra_args
  fi

  log "Waiting for k3s-agent service"
  systemctl is-active --quiet k3s-agent || { echo "k3s-agent service is not active"; systemctl status k3s-agent --no-pager; exit 1; }

  log "Node joined successfully"
  echo "Verify from server: sudo k3s kubectl get nodes -o wide"
}

main() {
  check_deps

  case "$ROLE" in
    server) install_server ;;
    agent) install_agent ;;
    *)
      echo "Invalid role: $ROLE"
      usage
      exit 1
      ;;
  esac
}

main "$@"