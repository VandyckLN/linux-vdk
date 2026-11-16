#!/usr/bin/env bash
# ==============================================================================
# Lumen OS — Modular Debian Package Builder
# ==============================================================================
# Compiles all 6 Debian packages (lumen-shell, lumen-compositor, lumen-system,
# lumen-dev-stack, lumen-welcome, lumen-desktop) using dpkg-deb --build
# with --root-owner-group for hermetic, non-root packaging.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="1.0.0-1ubuntu1"
OUTPUT_DIR="${1:-$WORKSPACE_ROOT/dist/debs}"
BUILD_ROOT="$WORKSPACE_ROOT/dist/build"

echo "=== Lumen OS Package Builder ==="
echo "Version: $VERSION"
echo "Output directory: $OUTPUT_DIR"
echo "Build staging: $BUILD_ROOT"

mkdir -p "$OUTPUT_DIR" "$BUILD_ROOT"

# Ensure dpkg-deb is available
if ! command -v dpkg-deb >/dev/null 2>&1; then
    echo "ERROR: dpkg-deb not found. Please install dpkg." >&2
    exit 1
fi

# Define packages to build
PACKAGES=(
    "lumen-shell"
    "lumen-compositor"
    "lumen-system"
    "lumen-dev-stack"
    "lumen-welcome"
    "lumen-desktop"
)

# Helper function to stage files and apply Debian permissions
stage_package() {
    local pkg="$1"
    local stage_dir="$BUILD_ROOT/$pkg"

    echo "--- Staging package: $pkg ---"
    rm -rf "$stage_dir"
    mkdir -p "$stage_dir/DEBIAN"

    case "$pkg" in
        lumen-shell)
            mkdir -p "$stage_dir/usr/share/lumen-os/shell" \
                     "$stage_dir/usr/share/lumen-os/config" \
                     "$stage_dir/etc/lumen" \
                     "$stage_dir/usr/bin" \
                     "$stage_dir/usr/share/applications"

            # Copy shell code
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
Description: Lumen OS Curved Glass Desktop Shell
 A modern, developer-first desktop shell built with GTK4 and gtk4-layer-shell.
 Features real-time system metrics (/proc CPU, RAM, open ports, Docker socket),
 dynamic toggling between vertical collapsible sidebar and horizontal dock,
 and native GPU glass styling.
EOF
            ;;

        lumen-compositor)
            mkdir -p "$stage_dir/usr/share/lumen-os/compositor/hyprland" \
                     "$stage_dir/usr/share/lumen-os/compositor/wayfire" \
                     "$stage_dir/etc/skel/.config/hypr" \
                     "$stage_dir/etc/skel/.config" \
                     "$stage_dir/usr/bin" \
                     "$stage_dir/usr/share/wayland-sessions"

            # Copy compositor configs
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
Description: Lumen OS Wayland Compositor Session
 Hyprland configuration and Wayfire fallback integration featuring
 GPU blur shaders and curved glass theme integration.
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

            # Postinst maintainer script
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
Description: Lumen OS System Performance Tuning & Optimization
 Tunes Ubuntu 26.04 kernel parameters for development workloads:
 inotify file watchers, swappiness 10, vfs_cache_pressure, network buffers,
 automated zram swap generation, and optional APT pinning for snap blocking.
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
Description: Lumen OS Developer Environment Stack
 Curated developer dotfiles, shell environment integrations,
 CLI productivity tools, and automated runtime orchestration.
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
Description: Lumen OS First-Boot Onboarding Wizard
 Interactive onboarding wizard for initial system setup. Allows developers
 to select shell orientation (sidebar vs dock), primary code editor (Neovim,
 VS Code, Zed, Cursor), programming runtimes via mise, and apply developer
 kernel tunings.
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
Description: Lumen OS Complete Desktop Environment Metapackage
 Complete metapackage pulling together all components of Lumen OS:
 Curved Glass Shell, Hyprland/Wayfire compositor configuration, dev-first
 system optimizations, base development stack, and welcome wizard.
EOF
            ;;

        *)
            echo "ERROR: Unknown package: $pkg" >&2
            exit 1
            ;;
    esac

    # Strip python cache files from package payload
    find "$stage_dir" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$stage_dir" -name "*.pyc" -delete 2>/dev/null || true

    # Standardize Debian permissions:
    # 0755 for directories, 0644 for regular files, 0755 for executable binaries and scripts
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

# Build all packages
for pkg in "${PACKAGES[@]}"; do
    stage_package "$pkg"
    pkg_deb="$OUTPUT_DIR/${pkg}_${VERSION}_all.deb"
    echo "Building binary package: $pkg_deb"
    dpkg-deb --build --root-owner-group "$BUILD_ROOT/$pkg" "$pkg_deb"
    ls -lh "$pkg_deb"
done

echo ""
echo "=== All 6 Debian packages compiled successfully in $OUTPUT_DIR ==="
