#!/usr/bin/env bash
# ==============================================================================
# launch-calamares.sh — Wayland/Hyprland Root Execution Wrapper for Calamares
# Handles environment preservation, Wayland sockets, and XWayland authorization.
# ==============================================================================
set -euo pipefail

# Dynamic log target: defer /var/log until running as root (UID 0) to prevent
# permission errors when invoked by an unprivileged live user on mode 0755 /var/log.
if [ "$(id -u)" -eq 0 ]; then
    LOG_FILE="/var/log/calamares-launcher.log"
else
    LOG_FILE="${TMPDIR:-/tmp}/calamares-launcher.log"
fi

touch "${LOG_FILE}" 2>/dev/null || LOG_FILE="/dev/null"
if [ "${LOG_FILE}" != "/dev/null" ]; then
    exec 2> >(tee -a "${LOG_FILE}" >&2)
fi

echo "[launch-calamares] Initializing installer session at $(date -u +'%Y-%m-%dT%H:%M:%SZ')..." >> "${LOG_FILE}" 2>/dev/null || true

# If running as unprivileged live user, prepare display access and elevate
if [ "$(id -u)" -ne 0 ]; then
    # Grant local root access to XWayland / X11 server if xhost is available
    if command -v xhost >/dev/null 2>&1; then
        xhost +SI:localuser:root >/dev/null 2>&1 || true
    fi

    # Set preferred platform: native Wayland first, fallback to X11/XCB
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland;xcb}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DISPLAY="${DISPLAY:-:0}"

    echo "[launch-calamares] Elevating privileges via sudo -E..." >> "${LOG_FILE}" 2>/dev/null || true
    exec sudo -E \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
        DISPLAY="${DISPLAY}" \
        QT_QPA_PLATFORM="${QT_QPA_PLATFORM}" \
        "$0" "$@"
fi

# ------------------------------------------------------------------------------
# Running as ROOT (UID 0)
# ------------------------------------------------------------------------------
# Ensure /root/.cache exists with correct permissions
mkdir -p /root/.cache /root/.config
chmod 700 /root/.cache /root/.config

# Prevent Qt 6 XDG_RUNTIME_DIR ownership warnings if running under Wayland
if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    # If user's runtime dir exists, ensure root can access the wayland socket
    if [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; then
        # Ensure fallback socket link in /run/user/0 if created
        mkdir -p /run/user/0
        chmod 700 /run/user/0
        ln -sf "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" "/run/user/0/${WAYLAND_DISPLAY}" 2>/dev/null || true
        export XDG_RUNTIME_DIR="/run/user/0"
    fi
fi

# Ensure QT_QPA_PLATFORM is set
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland;xcb}"

CALAMARES_BIN="$(command -v calamares || echo "/usr/bin/calamares")"

if [ ! -x "${CALAMARES_BIN}" ]; then
    echo "[launch-calamares] ERROR: Calamares binary not found at ${CALAMARES_BIN}" >&2
    exit 1
fi

echo "[launch-calamares] Launching Calamares (${CALAMARES_BIN}) with arguments: $*" >> "${LOG_FILE}" 2>/dev/null || true

# Execute Calamares with debug logging enabled by default in live sessions
exec "${CALAMARES_BIN}" -d "$@"
