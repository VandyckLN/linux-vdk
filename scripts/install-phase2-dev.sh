#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== Fase 2: Aplicando Otimizacoes Ubuntu Dev + Stack Base ==="
"$ROOT_DIR/system/apply-system-tuning.sh"
"$ROOT_DIR/dev-stack/setup-dev-env.sh" --cli --dotfiles --mise
