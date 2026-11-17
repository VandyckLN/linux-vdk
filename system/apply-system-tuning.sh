#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NO_SNAP="${1:-}"

# shellcheck source=system/lib/elevate.sh
source "$ROOT_DIR/system/lib/elevate.sh"

echo "[Lumen OS] Aplicando otimizações de sistema (sysctl + zram)..."

if [[ "$NO_SNAP" == "--no-snap" ]]; then
  echo "[Lumen OS] Aplicando pinning APT para bloquear snapd..."
  as_root system-tune --no-snap
else
  as_root system-tune
fi

echo "[Lumen OS] Otimizações aplicadas com sucesso."
