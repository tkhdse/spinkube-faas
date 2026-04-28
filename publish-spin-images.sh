#!/usr/bin/env bash
set -euo pipefail

# Publish Spin OCI artifacts for all actions in bench-actions.json to GHCR.
#
# Place this script in: /home/tkhadse2/spinkube-faas/publish_spin_images.sh
#
# Expected layout:
#   /home/tkhadse2/spinkube-faas/bench-actions.json
#   /home/tkhadse2/spinkube-faas/spin-actions/bench-float/spin.toml
#   /home/tkhadse2/spinkube-faas/spin-actions/bench-json/spin.toml
#   ... etc for every action key in bench-actions.json
#
# Required env:
#   GHCR_USER=tkhadse2
#   GHCR_PAT=<github_pat_with_read/write_packages>

CONFIG="${CONFIG:-/home/tkhadse2/spinkube-faas/bench-actions.json}"
ACTIONS_ROOT="${ACTIONS_ROOT:-/home/tkhadse2/spinkube-faas/spin-actions}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1"; exit 1; }; }

need jq
need spin
need docker

[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG"; exit 1; }
[[ -d "$ACTIONS_ROOT" ]] || { echo "Actions root not found: $ACTIONS_ROOT"; exit 1; }
[[ -n "${GHCR_USER:-}" ]] || { echo "Set GHCR_USER"; exit 1; }
[[ -n "${GHCR_PAT:-}" ]] || { echo "Set GHCR_PAT"; exit 1; }

echo "Logging into ghcr.io with docker..."
printf '%s' "$GHCR_PAT" | docker login ghcr.io -u "$GHCR_USER" --password-stdin >/dev/null

echo "Logging into ghcr.io with spin..."
spin registry login ghcr.io -u "$GHCR_USER" -p "$GHCR_PAT" >/dev/null

echo "Reading actions from $CONFIG..."
mapfile -t PAIRS < <(jq -r '.actions | to_entries[] | "\(.key)|\(.value)"' "$CONFIG")

if [[ "${#PAIRS[@]}" -eq 0 ]]; then
  echo "No actions found in $CONFIG"
  exit 1
fi

for pair in "${PAIRS[@]}"; do
  ACTION="${pair%%|*}"
  IMAGE="${pair#*|}"
  APP_DIR="${ACTIONS_ROOT}/${ACTION}"

  echo
  echo "==> ${ACTION}"
  echo "    dir:   ${APP_DIR}"
  echo "    image: ${IMAGE}"

  [[ -d "$APP_DIR" ]] || { echo "Missing app directory: $APP_DIR"; exit 1; }
  [[ -f "$APP_DIR/spin.toml" ]] || { echo "Missing spin.toml in: $APP_DIR"; exit 1; }

  pushd "$APP_DIR" >/dev/null
  spin build
  spin registry push "$IMAGE"
  popd >/dev/null

  echo "Verifying image exists: $IMAGE"
  docker manifest inspect "$IMAGE" >/dev/null
  echo "OK: $IMAGE"
done

echo
echo "All Spin images published successfully."