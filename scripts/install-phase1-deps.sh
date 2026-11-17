#!/usr/bin/env bash
set -euo pipefail

echo "Instalando dependências da Fase 1 no Ubuntu 26.04 LTS..."
sudo apt-get update
sudo apt-get install -y \
  python3-gi \
  gir1.2-gtk-4.0 \
  gir1.2-gtk4layershell-1.0 \
  libgtk4-layer-shell0 \
  hyprland \
  kitty

echo "Dependências instaladas! Agora você pode rodar:"
echo "  ./scripts/run-preview.sh          # Preview GTK4 em janela"
echo "  ./scripts/run-nested-hyprland.sh  # Hyprland + Curved Shell em janela Wayland"
