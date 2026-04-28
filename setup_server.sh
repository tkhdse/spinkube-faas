#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# setup_server.sh
#
# Purpose:
#   1. Install k3s server using /srv/k3s as data dir
#   2. Install Helm
#   3. Install cert-manager
#   4. Install Runtime Class Manager
#   5. Install Spin Operator CRDs + controller + SpinAppExecutor
#   6. Print worker join command
#
# Usage:
#   sudo ./setup_server.sh
#
# Optional env:
#   INSTALL_K3S_VERSION=v1.30.5+k3s1
#   K3S_DATA_DIR=/srv/k3s
#   SPIN_OPERATOR_VERSION=0.6.1
#   RCM_VERSION=0.2.0
#   CERT_MANAGER_TIMEOUT=10m

K3S_DATA_DIR="${K3S_DATA_DIR:-/srv/k3s}"
SPIN_OPERATOR_VERSION="${SPIN_OPERATOR_VERSION:-0.6.1}"
RCM_VERSION="${RCM_VERSION:-0.2.0}"
CERT_MANAGER_TIMEOUT="${CERT_MANAGER_TIMEOUT:-10m}"

log() {
  echo -e "\n[setup_server] $*"
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)." >&2
    exit 1
  fi
}

run() {
  echo "+ $*"
  "$@"
}

install_base_packages() {
  log "Installing base packages"
  dnf -y install curl ca-certificates tar gzip jq git openssl
}

prepare_data_dir() {
  log "Preparing k3s data directory at ${K3S_DATA_DIR}"
  mkdir -p "${K3S_DATA_DIR}"
  chmod 755 "${K3S_DATA_DIR}"
}

install_k3s_server() {
  log "Installing k3s server with data dir ${K3S_DATA_DIR}"
  curl -sfL https://get.k3s.io | sh -s - server \
    --data-dir "${K3S_DATA_DIR}" \
    --write-kubeconfig-mode 644

  run systemctl is-active --quiet k3s
  run /usr/local/bin/k3s kubectl get nodes -o wide
}

install_helm() {
  if [[ -x /usr/local/bin/helm ]]; then
    log "Helm already installed: $(/usr/local/bin/helm version --short 2>/dev/null || true)"
    return
  fi

  log "Installing Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  run /usr/local/bin/helm version --short
}

kcfg() {
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
}

check_schedulable_nodes() {
  log "Checking for schedulable nodes"
  kubectl get nodes -o wide
  kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.taints}{"\n"}{end}'
}

install_cert_manager() {
  log "Installing cert-manager"
  /usr/local/bin/helm repo add jetstack https://charts.jetstack.io >/dev/null
  /usr/local/bin/helm repo update >/dev/null

  /usr/local/bin/helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --create-namespace \
    --set crds.enabled=true \
    --wait \
    --timeout "${CERT_MANAGER_TIMEOUT}"

  kubectl get pods -n cert-manager
}

install_runtime_class_manager() {
  log "Installing runtime-class-manager"
  /usr/local/bin/helm upgrade --install runtime-class-manager \
    --namespace runtime-class-manager \
    --create-namespace \
    --version "${RCM_VERSION}" \
    oci://ghcr.io/spinframework/charts/runtime-class-manager

  kubectl get pods -n runtime-class-manager
}

install_spin_shim_cr() {
  log "Installing Spin shim CR"
  kubectl apply -f "https://raw.githubusercontent.com/spinframework/runtime-class-manager/refs/tags/v${RCM_VERSION}/config/samples/sample_shim_spin.yaml"

  log "After workers join, label only worker nodes with spin=true"
  echo "Example:"
  echo "  kubectl label node <worker1> spin=true"
  echo "  kubectl label node <worker2> spin=true"
  echo "  kubectl label node <worker3> spin=true"
}

install_spin_operator() {
  log "Installing Spin Operator CRDs"
  kubectl apply -f "https://github.com/spinframework/spin-operator/releases/download/v${SPIN_OPERATOR_VERSION}/spin-operator.crds.yaml"

  log "Installing Spin Operator"
  /usr/local/bin/helm upgrade --install spin-operator \
    --namespace spin-operator \
    --create-namespace \
    --version "${SPIN_OPERATOR_VERSION}" \
    --wait \
    oci://ghcr.io/spinframework/charts/spin-operator

  kubectl get pods -n spin-operator

  log "Installing SpinAppExecutor"
  kubectl apply -f "https://github.com/spinframework/spin-operator/releases/download/v${SPIN_OPERATOR_VERSION}/spin-operator.shim-executor.yaml"

  kubectl get spinappexecutors
}

print_join_info() {
  log "Printing worker join information"

  local token
  token="$(cat "${K3S_DATA_DIR}/server/node-token")"

  local server_ip
  server_ip="$(hostname -I | awk '{print $1}')"

  echo
  echo "Worker join command:"
  echo "sudo ./setup_worker.sh --server-url https://${server_ip}:6443 --token '${token}'"
  echo
}

verify() {
  log "Verification summary"
  kubectl get nodes -o wide
  kubectl get pods -A
  kubectl get runtimeclass || true
  kubectl get shim.runtime.spinkube.dev -A || true
  kubectl get spinappexecutors || true

  echo
  echo "Next steps:"
  echo "1. Run setup_worker.sh on each worker"
  echo "2. Label workers with spin=true"
  echo "3. Verify shim/runtimeclass readiness"
  echo "4. Deploy a SpinApp"
}

main() {
  need_root
  install_base_packages
  prepare_data_dir
  install_k3s_server
  install_helm
  kcfg
  check_schedulable_nodes
  install_cert_manager
  install_runtime_class_manager
  install_spin_shim_cr
  install_spin_operator
  print_join_info
  verify
}

main "$@"