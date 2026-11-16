#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_SRC="$ROOT_DIR/compositor/hyprland/hyprland.conf"
TEMP_CONF="/tmp/lumen-hyprland-nested.conf"

# Substitui o exec-once para usar o caminho absoluto do workspace atual
sed "s|python3 -m shell.main|PYTHONPATH=$ROOT_DIR python3 -m shell.main|g" "$CONF_SRC" > "$TEMP_CONF"

echo "Iniciando sessao Hyprland aninhada com o Curved Glass Shell..."
exec Hyprland -c "$TEMP_CONF"
