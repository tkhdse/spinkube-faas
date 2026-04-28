#!/usr/bin/env bash
set -euo pipefail

# Installs: k3s agent and joins it to an existing server
#
# Usage:
#   sudo ./setup_worker.sh --server-url https://<server-ip>:6443 --token '<node-token>'
#
# Optional env:
#   INSTALL_K3S_VERSION=v1.30.5+k3s1

SERVER_URL=""
TOKEN=""

log(){ echo -e "\n[setup_worker] $*"; }

usage() {
  cat <<EOF
Usage:
  sudo $0 --server-url https://<server-ip>:6443 --token '<node-token>'

Options:
  --server-url   k3s server URL (required)
  --token        k3s node token (required)
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)."
    exit 1
  fi
}

install_pkgs_rhel() {
  log "Installing base packages (RHEL)"
  dnf -y install curl ca-certificates
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-url) SERVER_URL="${2:-}"; shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

main() {
  need_root
  install_pkgs_rhel

  if [[ -z "${SERVER_URL}" || -z "${TOKEN}" ]]; then
    usage
    exit 1
  fi

  log "Installing k3s agent and joining cluster"
  curl -sfL https://get.k3s.io | K3S_URL="${SERVER_URL}" K3S_TOKEN="${TOKEN}" sh -s - agent

  systemctl is-active --quiet k3s-agent
  log "Joined successfully. Verify from server: kubectl get nodes -o wide"
}

main "$@"