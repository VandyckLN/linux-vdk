#!/usr/bin/env bash
# =============================================================================
# Lumen OS — Hook de Pós-Instalação do Calamares (chroot)
# Instalado em: /usr/local/bin/lumen-postinstall.sh
# Invocado por: shellprocess@postinstall do Calamares dentro do chroot de destino
# =============================================================================
set -euo pipefail

echo "=========================================================="
echo " [Lumen OS] Iniciando a Configuração do Ambiente Pós-Instalação"
echo "=========================================================="

# 1. Descobrir o usuário principal
TARGET_USER="${1:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "\${USER}" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}' /etc/passwd || echo "")
fi
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    TARGET_USER="$(id -nu 1000 2>/dev/null || echo "lumen")"
fi

TARGET_UID=$(getent passwd "$TARGET_USER" | cut -d: -f3 || echo "1000")
TARGET_GID=$(getent passwd "$TARGET_USER" | cut -d: -f4 || echo "1000")
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 || echo "/home/$TARGET_USER")

echo "[Lumen PostInstall] Usuário de destino: $TARGET_USER (UID: $TARGET_UID, Home: $TARGET_HOME)"

# 2. Adicionar o usuário aos grupos necessários
REQUIRED_GROUPS=("sudo" "adm" "cdrom" "dip" "plugdev" "audio" "video" "render" "netdev" "docker")
for grp in "${REQUIRED_GROUPS[@]}"; do
    if getent group "$grp" >/dev/null 2>&1; then
        usermod -aG "$grp" "$TARGET_USER" 2>/dev/null || true
    fi
done

# 3. Localizar os assets de configuração de origem
LUMEN_SHARE="/usr/share/lumen-os"
if [[ ! -d "$LUMEN_SHARE" ]]; then
    if [[ -d "/etc/lumen-os" ]]; then
        LUMEN_SHARE="/etc/lumen-os"
    elif [[ -d "/opt/lumen-os" ]]; then
        LUMEN_SHARE="/opt/lumen-os"
    fi
fi

# 4. Provisionar o skeleton (/etc/skel) e a home do usuário de destino
TARGET_DIRS=(
    "/etc/skel/.config/hypr"
    "/etc/skel/.config/kitty"
    "/etc/skel/.config/tmux"
    "/etc/skel/.config/nvim"
    "/etc/skel/.config/lumen-os"
    "/etc/skel/.config/autostart"
    "/etc/skel/.local/bin"
    "/etc/skel/projetos"
    "$TARGET_HOME/.config/hypr"
    "$TARGET_HOME/.config/kitty"
    "$TARGET_HOME/.config/tmux"
    "$TARGET_HOME/.config/nvim"
    "$TARGET_HOME/.config/lumen-os"
    "$TARGET_HOME/.config/autostart"
    "$TARGET_HOME/.local/bin"
    "$TARGET_HOME/projetos"
)
for d in "${TARGET_DIRS[@]}"; do
    mkdir -p "$d"
done

# Provisiona a configuração do Kitty
if [[ -f "$LUMEN_SHARE/dev-stack/kitty/kitty.conf" ]]; then
    install -m 644 "$LUMEN_SHARE/dev-stack/kitty/kitty.conf" /etc/skel/.config/kitty/kitty.conf
    install -m 644 "$LUMEN_SHARE/dev-stack/kitty/kitty.conf" "$TARGET_HOME/.config/kitty/kitty.conf"
fi

# Provisiona a configuração do Starship
if [[ -f "$LUMEN_SHARE/dev-stack/starship/starship.toml" ]]; then
    install -m 644 "$LUMEN_SHARE/dev-stack/starship/starship.toml" /etc/skel/.config/starship.toml
    install -m 644 "$LUMEN_SHARE/dev-stack/starship/starship.toml" "$TARGET_HOME/.config/starship.toml"
fi

# Provisiona a configuração do Tmux
if [[ -f "$LUMEN_SHARE/dev-stack/tmux/tmux.conf" ]]; then
    install -m 644 "$LUMEN_SHARE/dev-stack/tmux/tmux.conf" /etc/skel/.config/tmux/tmux.conf
    install -m 644 "$LUMEN_SHARE/dev-stack/tmux/tmux.conf" "$TARGET_HOME/.config/tmux/tmux.conf"
fi

# Provisiona a configuração do Neovim
if [[ -f "$LUMEN_SHARE/dev-stack/neovim/init.lua" ]]; then
    install -m 644 "$LUMEN_SHARE/dev-stack/neovim/init.lua" /etc/skel/.config/nvim/init.lua
    install -m 644 "$LUMEN_SHARE/dev-stack/neovim/init.lua" "$TARGET_HOME/.config/nvim/init.lua"
fi

# Provisiona a configuração padrão do Shell
if [[ -f "$LUMEN_SHARE/shell/config/shell.default.json" ]]; then
    install -m 644 "$LUMEN_SHARE/shell/config/shell.default.json" /etc/skel/.config/lumen-os/shell.json
    install -m 644 "$LUMEN_SHARE/shell/config/shell.default.json" "$TARGET_HOME/.config/lumen-os/shell.json"
elif [[ -f "/usr/share/lumen-os/config/shell.default.json" ]]; then
    install -m 644 "/usr/share/lumen-os/config/shell.default.json" /etc/skel/.config/lumen-os/shell.json
    install -m 644 "/usr/share/lumen-os/config/shell.default.json" "$TARGET_HOME/.config/lumen-os/shell.json"
fi

# Provisiona as configurações do compositor (Hyprland e Wayfire) com sanitização de caminhos
if [[ -f "$LUMEN_SHARE/compositor/hyprland/hyprland.conf" ]]; then
    sed -e 's|\$HOME/projetos/Distro|/usr/share/lumen-os|g' \
        -e 's|python3 -m shell.main|lumen-shell|g' \
        "$LUMEN_SHARE/compositor/hyprland/hyprland.conf" > /etc/skel/.config/hypr/hyprland.conf
    cp /etc/skel/.config/hypr/hyprland.conf "$TARGET_HOME/.config/hypr/hyprland.conf"
fi

if [[ -f "$LUMEN_SHARE/compositor/wayfire/wayfire.ini" ]]; then
    sed 's|PYTHONPATH=.* python3 -m shell.main|lumen-shell|g' \
        "$LUMEN_SHARE/compositor/wayfire/wayfire.ini" > /etc/skel/.config/wayfire.ini
    cp /etc/skel/.config/wayfire.ini "$TARGET_HOME/.config/wayfire.ini"
fi

# Provisiona o Dev Init no .bashrc
for bashrc in "/etc/skel/.bashrc" "$TARGET_HOME/.bashrc"; do
    if [[ ! -f "$bashrc" ]]; then
        touch "$bashrc" 2>/dev/null || true
    fi
    if [[ -f "$bashrc" ]] && ! grep -q "LUMEN OS DEV INIT" "$bashrc"; then
        cat >> "$bashrc" <<'EOF'

# >>> LUMEN OS DEV INIT >>>
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
command -v mise >/dev/null 2>&1 && eval "$(mise activate bash)"
# <<< LUMEN OS DEV INIT <<<
EOF
    fi
done

# 5. Ativar o ajuste de sistema (sysctl + zram)
echo "[Lumen PostInstall] Ativando o ajuste de sysctl e zram..."
if [[ -f "$LUMEN_SHARE/system/sysctl/99-lumen-dev.conf" ]]; then
    install -Dm 644 "$LUMEN_SHARE/system/sysctl/99-lumen-dev.conf" /etc/sysctl.d/99-lumen-dev.conf
    sysctl -p /etc/sysctl.d/99-lumen-dev.conf 2>/dev/null || true
    sysctl --system 2>/dev/null || true
fi

if [[ -f "$LUMEN_SHARE/system/zram/zram-generator.conf" ]]; then
    install -Dm 644 "$LUMEN_SHARE/system/zram/zram-generator.conf" /etc/systemd/zram-generator.conf
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable systemd-zram-setup@zram0.service 2>/dev/null || true
fi

if [[ -f "$LUMEN_SHARE/system/apt/99-no-snap" ]]; then
    install -Dm 644 "$LUMEN_SHARE/system/apt/99-no-snap" /etc/apt/preferences.d/99-no-snap
fi

# 6. Instalar o autostart do assistente de 1º boot (autolimitado)
echo "[Lumen PostInstall] Instalando o autostart do assistente de 1º boot..."
mkdir -p /etc/xdg/autostart /usr/share/applications

# Remove qualquer entrada de autostart duplicada e sem proteção instalada pelo empacotamento
rm -f /etc/xdg/autostart/dev.lumenos.welcome.desktop

cat > /etc/xdg/autostart/lumen-welcome.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Lumen OS Welcome
GenericName=Assistente de Configuração do 1º Boot
Comment=Configure o Curved Glass Shell e o ambiente de desenvolvimento
Exec=sh -c 'test ! -f "$HOME/.config/lumen-os/onboarding.done" && exec /usr/bin/lumen-welcome || exit 0'
Icon=lumen-welcome
Terminal=false
Categories=System;Settings;Utility;
StartupNotify=true
X-GNOME-Autostart-enabled=true
EOF
chmod 644 /etc/xdg/autostart/lumen-welcome.desktop
cp /etc/xdg/autostart/lumen-welcome.desktop /etc/skel/.config/autostart/
cp /etc/xdg/autostart/lumen-welcome.desktop "$TARGET_HOME/.config/autostart/"

cat > /usr/share/applications/lumen-welcome.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Lumen OS Welcome
GenericName=Assistente de Configuração do 1º Boot
Comment=Configure o Curved Glass Shell e o ambiente de desenvolvimento
Exec=/usr/bin/lumen-welcome
Icon=lumen-welcome
Terminal=false
Categories=System;Settings;Utility;
StartupNotify=true
EOF
chmod 644 /usr/share/applications/lumen-welcome.desktop

# 7. Definir o target padrão do systemd como gráfico
systemctl set-default graphical.target 2>/dev/null || true

# 8. Atualizar o initramfs e o bootloader GRUB
if command -v update-initramfs >/dev/null 2>&1; then
    echo "[Lumen PostInstall] Atualizando o initramfs dos kernels instalados..."
    update-initramfs -u -k all 2>/dev/null || update-initramfs -c -k all 2>/dev/null || true
fi

if command -v update-grub >/dev/null 2>&1; then
    echo "[Lumen PostInstall] Atualizando a configuração do bootloader GRUB..."
    update-grub 2>/dev/null || true
fi

# 9. Limpar artefatos da mídia live
echo "[Lumen PostInstall] Limpando artefatos do instalador live..."
rm -f /etc/skel/Desktop/install-lumen.desktop /etc/skel/.config/autostart/launch-calamares.desktop
rm -f "$TARGET_HOME/Desktop/install-lumen.desktop" 2>/dev/null || true
rm -f "$TARGET_HOME/.config/autostart/launch-calamares.desktop" 2>/dev/null || true
rm -f /etc/sudoers.d/casper /etc/sudoers.d/99-casper 2>/dev/null || true
rm -f /etc/xdg/autostart/dev.lumenos.welcome.desktop 2>/dev/null || true

# 10. Corrigir permissões da home
chown -R "$TARGET_UID:$TARGET_GID" "$TARGET_HOME" 2>/dev/null || true
chmod 700 "$TARGET_HOME" 2>/dev/null || true

echo "=========================================================="
echo " [Lumen OS] Pós-Instalação Concluída com Sucesso"
echo "=========================================================="
exit 0
