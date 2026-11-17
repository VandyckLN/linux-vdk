#!/usr/bin/env bash
# Biblioteca para ser carregada com `source`: oferece a função as_root.
# Não define set -e/-u e não usa exit; o chamador controla o modo do shell.
#
# Uso: as_root <ação> [args...]
# Variáveis lidas:
#   LUMEN_ELEVATE          "pkexec" ativa o pkexec (fluxo gráfico); vazio usa sudo
#   LUMEN_ROOT_HELPER_BIN  helper instalado (padrão /usr/bin/lumen-root-helper)

# Helper do repositório, resolvido relativo a este arquivo (não ao cwd do chamador)
_LUMEN_ELEVATE_REPO_HELPER="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/lumen-root-helper"

as_root() {
    local helper_bin="${LUMEN_ROOT_HELPER_BIN:-/usr/bin/lumen-root-helper}"
    local status=0

    if [[ "${LUMEN_ELEVATE:-}" == "pkexec" && "$EUID" -ne 0 ]]; then
        # O polkit só autoriza o caminho instalado: sem fallback para o repo ou sudo
        if [[ ! -e "$helper_bin" ]]; then
            echo "O pkexec precisa do lumen-root-helper instalado (pacote lumen-system). Pelo terminal, execute o script diretamente que a elevação será feita via sudo." >&2
            return 1
        fi
        pkexec "$helper_bin" "$@" || status=$?
        case "$status" in
            126) echo "Autenticação cancelada. Nada foi alterado." >&2 ;;
            # O hyprpolkitagent devolve 127 (não 126) quando a janela é cancelada.
            127) echo "Autenticação cancelada ou negada. Nada foi alterado." >&2 ;;
        esac
        return "$status"
    fi

    # Sem instalação, usa o helper do checkout
    [[ -e "$helper_bin" ]] || helper_bin="$_LUMEN_ELEVATE_REPO_HELPER"

    if [[ "$EUID" -eq 0 ]]; then
        "$helper_bin" "$@" || status=$?
    else
        sudo "$helper_bin" "$@" || status=$?
    fi
    return "$status"
}
