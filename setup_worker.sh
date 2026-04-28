#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# setup_worker.sh
#
# Purpose:
#   Install k3s agent using /srv/k3s and join an existing server
#
# Usage:
#   sudo ./setup_worker.sh --server-url https://<server-ip>:6443 --token '<token>'
#
# Optional env:
#   INSTALL_K3S_VERSION=v1.30.5+k3s1
#   K3S_DATA_DIR=/srv/k3s

K3S_DATA_DIR="${K3S_DATA_DIR:-/srv/k3s}"
SERVER_URL=""
TOKEN=""

log() {
  echo -e "\n[setup_worker] $*"
}

usage() {
  cat <<EOF
Usage:
  sudo $0 --server-url https://<server-ip>:6443 --token '<token>'

Options:
  --server-url   k3s server URL (required)
  --token        k3s node token (required)
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

install_base_packages() {
  log "Installing base packages"
  dnf -y install curl ca-certificates
}

prepare_data_dir() {
  log "Preparing k3s data directory at ${K3S_DATA_DIR}"
  mkdir -p "${K3S_DATA_DIR}"
  chmod 755 "${K3S_DATA_DIR}"
}

install_k3s_agent() {
  log "Installing k3s agent with data dir ${K3S_DATA_DIR}"
  curl -sfL https://get.k3s.io | \
    K3S_URL="${SERVER_URL}" \
    K3S_TOKEN="${TOKEN}" \
    sh -s - agent --data-dir "${K3S_DATA_DIR}"

  systemctl is-active --quiet k3s-agent
  log "Worker joined successfully"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server-url)
      SERVER_URL="${2:-}"
      shift 2
      ;;
    --token)
      TOKEN="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

main() {
  need_root

  if [[ -z "${SERVER_URL}" || -z "${TOKEN}" ]]; then
    usage
    exit 1
  fi

  install_base_packages
  prepare_data_dir
  install_k3s_agent
}

main "$@"