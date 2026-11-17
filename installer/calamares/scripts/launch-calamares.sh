#!/usr/bin/env bash
# ==============================================================================
# launch-calamares.sh — Wrapper de execução como root do Calamares no Wayland/Hyprland
# Cuida da preservação do ambiente, dos sockets Wayland e da autorização do XWayland.
# ==============================================================================
set -euo pipefail

# Destino de log dinâmico: adia /var/log até rodar como root (UID 0) para evitar
# erros de permissão quando invocado por um usuário live sem privilégios com /var/log em modo 0755.
if [ "$(id -u)" -eq 0 ]; then
    LOG_FILE="/var/log/calamares-launcher.log"
else
    LOG_FILE="${TMPDIR:-/tmp}/calamares-launcher.log"
fi

touch "${LOG_FILE}" 2>/dev/null || LOG_FILE="/dev/null"
if [ "${LOG_FILE}" != "/dev/null" ]; then
    exec 2> >(tee -a "${LOG_FILE}" >&2)
fi

echo "[launch-calamares] Inicializando sessão do instalador em $(date -u +'%Y-%m-%dT%H:%M:%SZ')..." >> "${LOG_FILE}" 2>/dev/null || true

# Se estiver rodando como usuário live sem privilégios, prepara o acesso ao display e eleva
if [ "$(id -u)" -ne 0 ]; then
    # Concede acesso local de root ao servidor XWayland / X11 se o xhost estiver disponível
    if command -v xhost >/dev/null 2>&1; then
        xhost +SI:localuser:root >/dev/null 2>&1 || true
    fi

    # Define a plataforma preferida: Wayland nativo primeiro, com fallback para X11/XCB
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland;xcb}"
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DISPLAY="${DISPLAY:-:0}"

    echo "[launch-calamares] Elevando privilégios via sudo -E..." >> "${LOG_FILE}" 2>/dev/null || true
    exec sudo -E \
        WAYLAND_DISPLAY="${WAYLAND_DISPLAY}" \
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
        DISPLAY="${DISPLAY}" \
        QT_QPA_PLATFORM="${QT_QPA_PLATFORM}" \
        "$0" "$@"
fi

# ------------------------------------------------------------------------------
# Rodando como ROOT (UID 0)
# ------------------------------------------------------------------------------
# Garante que /root/.cache exista com as permissões corretas
mkdir -p /root/.cache /root/.config
chmod 700 /root/.cache /root/.config

# Evita avisos do Qt 6 sobre o dono do XDG_RUNTIME_DIR ao rodar sob Wayland
if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    # Se o runtime dir do usuário existir, garante que o root acesse o socket wayland
    if [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; then
        # Garante o link de socket de fallback em /run/user/0, se criado
        mkdir -p /run/user/0
        chmod 700 /run/user/0
        ln -sf "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" "/run/user/0/${WAYLAND_DISPLAY}" 2>/dev/null || true
        export XDG_RUNTIME_DIR="/run/user/0"
    fi
fi

# Garante que QT_QPA_PLATFORM esteja definido
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland;xcb}"

CALAMARES_BIN="$(command -v calamares || echo "/usr/bin/calamares")"

if [ ! -x "${CALAMARES_BIN}" ]; then
    echo "[launch-calamares] ERRO: binário do Calamares não encontrado em ${CALAMARES_BIN}" >&2
    exit 1
fi

echo "[launch-calamares] Iniciando o Calamares (${CALAMARES_BIN}) com os argumentos: $*" >> "${LOG_FILE}" 2>/dev/null || true

# Executa o Calamares com log de depuração ativado por padrão nas sessões live
exec "${CALAMARES_BIN}" -d "$@"
