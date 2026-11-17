#!/usr/bin/env bash
# ==============================================================================
# Lumen OS — Gerador Modular de Pacotes Debian
# ==============================================================================
# Compila os 6 pacotes Debian (lumen-shell, lumen-compositor, lumen-system,
# lumen-dev-stack, lumen-welcome, lumen-desktop) usando dpkg-deb --build
# com --root-owner-group para um empacotamento hermético e sem root.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="1.0.0-1ubuntu1"
OUTPUT_DIR="${1:-$WORKSPACE_ROOT/dist/debs}"
BUILD_ROOT="$WORKSPACE_ROOT/dist/build"

echo "=== Lumen OS Package Builder ==="
echo "Versão: $VERSION"
echo "Diretório de saída: $OUTPUT_DIR"
echo "Staging do build: $BUILD_ROOT"

mkdir -p "$OUTPUT_DIR" "$BUILD_ROOT"

# Garante que o dpkg-deb esteja disponível
if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "ERRO: dpkg-deb não encontrado. Instale o dpkg." >&2
    exit 1
fi

# Define os pacotes a gerar
PACKAGES=(
    "lumen-shell"
    "lumen-compositor"
    "lumen-system"
    "lumen-dev-stack"
    "lumen-welcome"
    "lumen-desktop"
)

# Função auxiliar para preparar os arquivos e aplicar as permissões Debian
stage_package() {
    local pkg="$1"
    local stage_dir="$BUILD_ROOT/$pkg"

    echo "--- Preparando pacote: $pkg ---"
    rm -rf "$stage_dir"
    mkdir -p "$stage_dir/DEBIAN"

    case "$pkg" in
        lumen-shell)
            mkdir -p "$stage_dir/usr/share/lumen-os/shell" \
                     "$stage_dir/usr/share/lumen-os/config" \
                     "$stage_dir/etc/lumen" \
                     "$stage_dir/usr/bin" \
                     "$stage_dir/usr/share/applications"

            # Copia o código do shell
            cp -r "$WORKSPACE_ROOT/shell/"* "$stage_dir/usr/share/lumen-os/shell/"
            cp "$WORKSPACE_ROOT/config/shell.default.json" "$stage_dir/usr/share/lumen-os/config/shell.default.json"
            cp "$WORKSPACE_ROOT/config/shell.default.json" "$stage_dir/etc/lumen/shell.default.json"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-shell" "$stage_dir/usr/bin/lumen-shell"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-shell.desktop" "$stage_dir/usr/share/applications/lumen-shell.desktop"

            cat <<EOF > "$stage_dir/DEBIAN/control"
Package: lumen-shell
Version: $VERSION
Section: x11
Priority: optional
Architecture: all
Maintainer: Lumen OS Developers <contact@lumenos.dev>
Provides: distro-shell
Depends: python3 (>= 3.10), python3-gi (>= 3.42), gir1.2-gtk-4.0, gir1.2-gtk4layershell-1.0, libgtk4-layer-shell0
Recommends: kitty, fonts-jetbrains-mono
Suggests: hyprland (>= 0.53) | wayfire (>= 0.10), wl-clipboard
Description: Shell de desktop Curved Glass do Lumen OS
 Um shell de desktop moderno, focado em desenvolvedores, feito com GTK4 e gtk4-layer-shell.
 Traz métricas do sistema em tempo real (/proc CPU, RAM, portas abertas, socket do Docker),
 alternância dinâmica entre barra lateral vertical recolhível e dock horizontal,
 e estilo de vidro nativo acelerado por GPU.
EOF
            ;;

        lumen-compositor)
            mkdir -p "$stage_dir/usr/share/lumen-os/compositor/hyprland" \
                     "$stage_dir/usr/share/lumen-os/compositor/wayfire" \
                     "$stage_dir/etc/skel/.config/hypr" \
                     "$stage_dir/etc/skel/.config" \
                     "$stage_dir/usr/bin" \
                     "$stage_dir/usr/share/wayland-sessions"

            # Copia as configurações do compositor
            cp "$WORKSPACE_ROOT/packaging/templates/hyprland.conf" "$stage_dir/usr/share/lumen-os/compositor/hyprland/hyprland.conf"
            cp "$WORKSPACE_ROOT/packaging/templates/wayfire.ini" "$stage_dir/usr/share/lumen-os/compositor/wayfire/wayfire.ini"
            cp "$WORKSPACE_ROOT/packaging/templates/hyprland.conf" "$stage_dir/etc/skel/.config/hypr/hyprland.conf"
            cp "$WORKSPACE_ROOT/packaging/templates/wayfire.ini" "$stage_dir/etc/skel/.config/wayfire.ini"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-session-hyprland" "$stage_dir/usr/bin/lumen-session-hyprland"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-session-wayfire" "$stage_dir/usr/bin/lumen-session-wayfire"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-hyprland.desktop" "$stage_dir/usr/share/wayland-sessions/lumen-hyprland.desktop"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-wayfire.desktop" "$stage_dir/usr/share/wayland-sessions/lumen-wayfire.desktop"

            cat <<EOF > "$stage_dir/DEBIAN/control"
Package: lumen-compositor
Version: $VERSION
Section: x11
Priority: optional
Architecture: all
Maintainer: Lumen OS Developers <contact@lumenos.dev>
Provides: distro-compositor
Depends: hyprland (>= 0.53) | wayfire (>= 0.10), lumen-shell (= $VERSION) | distro-shell, kitty, xdg-desktop-portal-hyprland | xdg-desktop-portal-wlr, xdg-desktop-portal
Recommends: wayfire, waybar, wl-clipboard
Description: Sessão do compositor Wayland do Lumen OS
 Configuração do Hyprland e integração de fallback com o Wayfire, com
 shaders de blur na GPU e integração com o tema curved glass.
EOF
            ;;

        lumen-system)
            mkdir -p "$stage_dir/usr/share/lumen-os/system/sysctl" \
                     "$stage_dir/usr/share/lumen-os/system/zram" \
                     "$stage_dir/usr/share/lumen-os/system/apt" \
                     "$stage_dir/etc/sysctl.d" \
                     "$stage_dir/etc/systemd" \
                     "$stage_dir/etc/apt/preferences.d" \
                     "$stage_dir/usr/bin"

            cp "$WORKSPACE_ROOT/system/apply-system-tuning.sh" "$stage_dir/usr/share/lumen-os/system/apply-system-tuning.sh"
            cp "$WORKSPACE_ROOT/system/sysctl/99-lumen-dev.conf" "$stage_dir/usr/share/lumen-os/system/sysctl/99-lumen-dev.conf"
            cp "$WORKSPACE_ROOT/system/zram/zram-generator.conf" "$stage_dir/usr/share/lumen-os/system/zram/zram-generator.conf"
            cp "$WORKSPACE_ROOT/system/apt/99-no-snap" "$stage_dir/usr/share/lumen-os/system/apt/99-no-snap"
            cp "$WORKSPACE_ROOT/system/sysctl/99-lumen-dev.conf" "$stage_dir/etc/sysctl.d/99-lumen-dev.conf"
            cp "$WORKSPACE_ROOT/system/zram/zram-generator.conf" "$stage_dir/etc/systemd/zram-generator.conf"
            cp "$WORKSPACE_ROOT/system/apt/99-no-snap" "$stage_dir/etc/apt/preferences.d/99-no-snap"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-system-tune" "$stage_dir/usr/bin/lumen-system-tune"

            # Script de mantenedor postinst
            sed '/#DEBHELPER#/d' "$WORKSPACE_ROOT/packaging/debian/lumen-system.postinst" > "$stage_dir/DEBIAN/postinst"
            chmod 0755 "$stage_dir/DEBIAN/postinst"

            cat <<EOF > "$stage_dir/DEBIAN/control"
Package: lumen-system
Version: $VERSION
Section: admin
Priority: optional
Architecture: all
Maintainer: Lumen OS Developers <contact@lumenos.dev>
Provides: distro-system
Depends: procps, systemd-zram-generator
Recommends: apt
Suggests: snapd
Description: Ajuste e otimização de desempenho do sistema Lumen OS
 Ajusta os parâmetros de kernel do Ubuntu 26.04 para cargas de desenvolvimento:
 watchers de arquivos inotify, swappiness 10, vfs_cache_pressure, buffers de rede,
 geração automática de swap zram e pinning APT opcional para bloquear o snap.
EOF
            ;;

        lumen-dev-stack)
            mkdir -p "$stage_dir/usr/share/lumen-os/dev-stack/starship" \
                     "$stage_dir/usr/share/lumen-os/dev-stack/tmux" \
                     "$stage_dir/usr/share/lumen-os/dev-stack/kitty" \
                     "$stage_dir/usr/share/lumen-os/dev-stack/neovim" \
                     "$stage_dir/etc/skel/.config/tmux" \
                     "$stage_dir/etc/skel/.config/kitty" \
                     "$stage_dir/etc/skel/.config/nvim" \
                     "$stage_dir/etc/profile.d" \
                     "$stage_dir/usr/bin"

            cp "$WORKSPACE_ROOT/dev-stack/packages.list" "$stage_dir/usr/share/lumen-os/dev-stack/packages.list"
            cp "$WORKSPACE_ROOT/dev-stack/setup-dev-env.sh" "$stage_dir/usr/share/lumen-os/dev-stack/setup-dev-env.sh"
            cp "$WORKSPACE_ROOT/dev-stack/starship/starship.toml" "$stage_dir/usr/share/lumen-os/dev-stack/starship/starship.toml"
            cp "$WORKSPACE_ROOT/dev-stack/tmux/tmux.conf" "$stage_dir/usr/share/lumen-os/dev-stack/tmux/tmux.conf"
            cp "$WORKSPACE_ROOT/dev-stack/kitty/kitty.conf" "$stage_dir/usr/share/lumen-os/dev-stack/kitty/kitty.conf"
            cp "$WORKSPACE_ROOT/dev-stack/neovim/init.lua" "$stage_dir/usr/share/lumen-os/dev-stack/neovim/init.lua"

            cp "$WORKSPACE_ROOT/dev-stack/starship/starship.toml" "$stage_dir/etc/skel/.config/starship.toml"
            cp "$WORKSPACE_ROOT/dev-stack/tmux/tmux.conf" "$stage_dir/etc/skel/.config/tmux/tmux.conf"
            cp "$WORKSPACE_ROOT/dev-stack/kitty/kitty.conf" "$stage_dir/etc/skel/.config/kitty/kitty.conf"
            cp "$WORKSPACE_ROOT/dev-stack/neovim/init.lua" "$stage_dir/etc/skel/.config/nvim/init.lua"

            cp "$WORKSPACE_ROOT/packaging/templates/lumen-dev.sh" "$stage_dir/etc/profile.d/lumen-dev.sh"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-dev-setup" "$stage_dir/usr/bin/lumen-dev-setup"

            cat <<EOF > "$stage_dir/DEBIAN/control"
Package: lumen-dev-stack
Version: $VERSION
Section: devel
Priority: optional
Architecture: all
Maintainer: Lumen OS Developers <contact@lumenos.dev>
Provides: distro-dev-stack
Depends: git, curl, wget, ripgrep, fd-find, fzf, jq, btop, tmux, neovim, build-essential, ca-certificates, unzip, fonts-jetbrains-mono
Recommends: kitty
Description: Stack de ambiente de desenvolvimento do Lumen OS
 Dotfiles selecionados para desenvolvedores, integrações de ambiente de shell,
 ferramentas CLI de produtividade e orquestração automatizada de runtimes.
EOF
            ;;

        lumen-welcome)
            mkdir -p "$stage_dir/usr/share/lumen-os/welcome" \
                     "$stage_dir/usr/bin" \
                     "$stage_dir/usr/share/applications" \
                     "$stage_dir/etc/xdg/autostart" \
                     "$stage_dir/usr/share/polkit-1/actions"

            cp -r "$WORKSPACE_ROOT/welcome/"* "$stage_dir/usr/share/lumen-os/welcome/"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-welcome" "$stage_dir/usr/bin/lumen-welcome"
            cp "$WORKSPACE_ROOT/packaging/templates/lumen-welcome.desktop" "$stage_dir/usr/share/applications/lumen-welcome.desktop"
            cp "$WORKSPACE_ROOT/packaging/templates/dev.lumenos.welcome.desktop" "$stage_dir/usr/share/applications/dev.lumenos.welcome.desktop"
            cp "$WORKSPACE_ROOT/packaging/templates/dev.lumenos.welcome.desktop" "$stage_dir/etc/xdg/autostart/dev.lumenos.welcome.desktop"
            cp "$WORKSPACE_ROOT/packaging/templates/dev.lumenos.welcome.policy" "$stage_dir/usr/share/polkit-1/actions/dev.lumenos.welcome.policy"

            cat <<EOF > "$stage_dir/DEBIAN/control"
Package: lumen-welcome
Version: $VERSION
Section: x11
Priority: optional
Architecture: all
Maintainer: Lumen OS Developers <contact@lumenos.dev>
Provides: distro-welcome
Depends: python3 (>= 3.10), python3-gi (>= 3.42), gir1.2-gtk-4.0, lumen-shell (= $VERSION) | distro-shell, pkexec, polkitd
Recommends: lumen-system (= $VERSION) | distro-system, lumen-dev-stack (= $VERSION) | distro-dev-stack
Description: Assistente de boas-vindas do 1º boot do Lumen OS
 Assistente interativo para a configuração inicial do sistema. Permite escolher
 a orientação do shell (barra lateral ou dock), o editor principal (Neovim,
 VS Code, Zed, Cursor), runtimes de programação via mise e aplicar ajustes
 de kernel para desenvolvimento.
EOF
            ;;

        lumen-desktop)
            mkdir -p "$stage_dir/usr/share/doc/lumen-desktop"
            cat <<EOF > "$stage_dir/usr/share/doc/lumen-desktop/README"
Lumen OS Metapackage
====================
This metapackage brings together all core components of the Lumen OS
desktop environment.
EOF

            cat <<EOF > "$stage_dir/DEBIAN/control"
Package: lumen-desktop
Version: $VERSION
Section: metapackages
Priority: optional
Architecture: all
Maintainer: Lumen OS Developers <contact@lumenos.dev>
Provides: distro-desktop
Depends: lumen-shell (= $VERSION) | distro-shell, lumen-compositor (= $VERSION) | distro-compositor, lumen-system (= $VERSION) | distro-system, lumen-dev-stack (= $VERSION) | distro-dev-stack, lumen-welcome (= $VERSION) | distro-welcome
Recommends: greetd | sddm | gdm3
Description: Metapacote do ambiente de desktop completo do Lumen OS
 Metapacote completo que reúne todos os componentes do Lumen OS:
 Curved Glass Shell, configuração do compositor Hyprland/Wayfire, otimizações
 de sistema dev-first, stack base de desenvolvimento e assistente de boas-vindas.
EOF
            ;;

        *)
            echo "ERRO: Pacote desconhecido: $pkg" >&2
            exit 1
            ;;
    esac

    # Remove arquivos de cache do Python do conteúdo do pacote
    find "$stage_dir" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$stage_dir" -name "*.pyc" -delete 2>/dev/null || true

    # Padroniza as permissões Debian:
    # 0755 para diretórios, 0644 para arquivos comuns, 0755 para binários executáveis e scripts
    find "$stage_dir" -type d -exec chmod 0755 {} +
    find "$stage_dir" -type f -exec chmod 0644 {} +
    if [[ -d "$stage_dir/usr/bin" ]]; then
        find "$stage_dir/usr/bin" -type f -exec chmod 0755 {} +
    fi
    find "$stage_dir" -name "*.sh" -exec chmod 0755 {} +
    chmod 0755 "$stage_dir/DEBIAN"
    chmod 0644 "$stage_dir/DEBIAN/control"
    if [[ -f "$stage_dir/DEBIAN/postinst" ]]; then
        chmod 0755 "$stage_dir/DEBIAN/postinst"
    fi
}

# Gera todos os pacotes
for pkg in "${PACKAGES[@]}"; do
    stage_package "$pkg"
    pkg_deb="$OUTPUT_DIR/${pkg}_${VERSION}_all.deb"
    echo "Gerando pacote binário: $pkg_deb"
    dpkg-deb --build --root-owner-group "$BUILD_ROOT/$pkg" "$pkg_deb"
    ls -lh "$pkg_deb"
done

echo ""
echo "=== Os 6 pacotes Debian foram compilados com sucesso em $OUTPUT_DIR ==="
