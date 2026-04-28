#!/usr/bin/env bash
set -euo pipefail

# Installs: k3s server + helm
# Deploys into cluster: cert-manager, runtime-class-manager, spin-operator (+ CRDs), SpinAppExecutor, Shim (spin)
#
# Usage:
#   sudo ./setup_server.sh
#
# Optional env:
#   INSTALL_K3S_VERSION=v1.30.5+k3s1
#   SPIN_OPERATOR_VERSION=0.6.1
#   RCM_VERSION=0.2.0

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SPIN_OPERATOR_VERSION="${SPIN_OPERATOR_VERSION:-0.6.1}"
RCM_VERSION="${RCM_VERSION:-0.2.0}"

log(){ echo -e "\n[setup_server] $*"; }

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (sudo)."
    exit 1
  fi
}

install_pkgs_rhel() {
  log "Installing base packages (RHEL)"
  dnf -y install curl ca-certificates tar gzip jq git openssl
}

install_k3s_server() {
  log "Installing k3s server"
  curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644
  systemctl is-active --quiet k3s

  log "k3s nodes"
  k3s kubectl get nodes -o wide

  local token server_ip
  token="$(cat /var/lib/rancher/k3s/server/node-token)"
  server_ip="$(hostname -I | awk '{print $1}')"

  log "Worker join info"
  echo "SERVER_URL=https://${server_ip}:6443"
  echo "NODE_TOKEN=${token}"
  echo
  echo "On each worker run:"
  echo "  sudo ./setup_worker.sh --server-url https://${server_ip}:6443 --token '${token}'"
}

install_helm() {
  if command -v helm >/dev/null 2>&1; then
    log "Helm already installed: $(helm version --short 2>/dev/null || true)"
    return
  fi

  log "Installing Helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  helm version --short
}

kcfg() {
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
}

install_cert_manager() {
  log "Installing cert-manager"
  helm repo add jetstack https://charts.jetstack.io >/dev/null
  helm repo update >/dev/null
  helm upgrade --install cert-manager jetstack/cert-manager \
    -n cert-manager --create-namespace \
    --set crds.enabled=true \
    --wait

  kubectl get pods -n cert-manager
}

install_runtime_class_manager() {
  log "Installing runtime-class-manager (RCM)"
  helm upgrade --install runtime-class-manager \
    -n runtime-class-manager --create-namespace \
    --version "${RCM_VERSION}" \
    oci://ghcr.io/spinframework/charts/runtime-class-manager

  kubectl get pods -n runtime-class-manager
}

install_spin_shim() {
  log "Installing Spin shim via RCM Shim CR"
  kubectl apply -f "https://raw.githubusercontent.com/spinframework/runtime-class-manager/refs/tags/v${RCM_VERSION}/config/samples/sample_shim_spin.yaml"

  log "NOTE: label worker nodes for shim install (run after workers join):"
  echo "  kubectl label node <worker1> spin=true"
  echo "  kubectl label node <worker2> spin=true"
  echo "  kubectl label node <worker3> spin=true"
}

install_spin_operator() {
  log "Installing Spin Operator CRDs"
  kubectl apply -f "https://github.com/spinframework/spin-operator/releases/download/v${SPIN_OPERATOR_VERSION}/spin-operator.crds.yaml"

  log "Installing Spin Operator (Helm)"
  helm upgrade --install spin-operator \
    -n spin-operator --create-namespace \
    --version "${SPIN_OPERATOR_VERSION}" \
    --wait \
    oci://ghcr.io/spinframework/charts/spin-operator

  kubectl get pods -n spin-operator

  log "Installing SpinAppExecutor"
  kubectl apply -f "https://github.com/spinframework/spin-operator/releases/download/v${SPIN_OPERATOR_VERSION}/spin-operator.shim-executor.yaml"

  kubectl get spinappexecutors
}

verify_cluster_bits() {
  log "Verification summary"
  kubectl get nodes -o wide
  kubectl get runtimeclass || true
  kubectl get shim.runtime.spinkube.dev -A || true
  kubectl get spinappexecutors || true
}

main() {
  need_root
  install_pkgs_rhel
  install_k3s_server
  install_helm
  kcfg

  # cluster add-ons
  install_cert_manager
  install_runtime_class_manager
  install_spin_shim
  install_spin_operator
  verify_cluster_bits

  log "Done. Next: join workers, then label them spin=true."
}

main "$@"