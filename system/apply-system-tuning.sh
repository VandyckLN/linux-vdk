#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NO_SNAP="${1:-}"

echo "[Lumen OS] Aplicando otimizações de sistema (sysctl + zram)..."

sudo install -Dm644 "$ROOT_DIR/system/sysctl/99-lumen-dev.conf" /etc/sysctl.d/99-lumen-dev.conf
sudo sysctl --system >/dev/null

sudo apt-get update
sudo apt-get install -y systemd-zram-generator
sudo install -Dm644 "$ROOT_DIR/system/zram/zram-generator.conf" /etc/systemd/zram-generator.conf
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service || true

if [[ "$NO_SNAP" == "--no-snap" ]]; then
  echo "[Lumen OS] Aplicando pinning APT para bloquear snapd..."
  sudo install -Dm644 "$ROOT_DIR/system/apt/99-no-snap" /etc/apt/preferences.d/99-no-snap
fi

echo "[Lumen OS] Otimizações aplicadas com sucesso."
