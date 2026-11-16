#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

INSTALL_CLI=false
INSTALL_DOTFILES=false
INSTALL_MISE=false
INSTALL_DOCKER=false
RUNTIMES=""
EDITOR_CHOICE=""

usage() {
  cat <<EOF
Uso: $0 [opcoes]
  --all               Executa cli + dotfiles + mise + docker
  --cli               Instala ferramentas CLI base (dev-stack/packages.list)
  --dotfiles          Instala configs de Kitty, Starship, tmux e Neovim
  --mise              Instala o gerenciador de runtimes mise
  --runtimes LIST     Runtimes via mise separados por virgula (ex: node@lts,python@3.12,go@latest,rust@latest)
  --docker            Instala docker.io + docker-compose-v2 e adiciona usuario ao grupo docker
  --editor NAME       Instala editor: neovim | vscode | zed | cursor
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      INSTALL_CLI=true
      INSTALL_DOTFILES=true
      INSTALL_MISE=true
      INSTALL_DOCKER=true
      ;;
    --cli) INSTALL_CLI=true ;;
    --dotfiles) INSTALL_DOTFILES=true ;;
    --mise) INSTALL_MISE=true ;;
    --docker) INSTALL_DOCKER=true ;;
    --runtimes)
      RUNTIMES="${2:-}"
      shift
      ;;
    --editor)
      EDITOR_CHOICE="${2:-}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opcao desconhecida: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "$INSTALL_CLI" == true ]]; then
  echo "[Dev Stack] Instalando pacotes CLI base..."
  mapfile -t PKGS < <(grep -vE '^\s*(#|$)' "$ROOT_DIR/dev-stack/packages.list")
  sudo apt-get update
  sudo apt-get install -y "${PKGS[@]}"
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
fi

if [[ "$INSTALL_DOTFILES" == true ]]; then
  echo "[Dev Stack] Aplicando dotfiles (Kitty, Starship, tmux, Neovim)..."
  mkdir -p "$HOME/.config/kitty" "$HOME/.config/tmux" "$HOME/.config/nvim"
  install -m 644 "$ROOT_DIR/dev-stack/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf"
  install -m 644 "$ROOT_DIR/dev-stack/starship/starship.toml" "$HOME/.config/starship.toml"
  install -m 644 "$ROOT_DIR/dev-stack/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
  install -m 644 "$ROOT_DIR/dev-stack/neovim/init.lua" "$HOME/.config/nvim/init.lua"

  if ! command -v starship >/dev/null 2>&1; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
  fi

  if ! grep -q "LUMEN OS DEV INIT" "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" <<'BASHRC'

# >>> LUMEN OS DEV INIT >>>
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"
command -v starship >/dev/null 2>&1 && eval "$(starship init bash)"
command -v mise >/dev/null 2>&1 && eval "$(mise activate bash)"
# <<< LUMEN OS DEV INIT <<<
BASHRC
  fi
fi

if [[ "$INSTALL_MISE" == true ]]; then
  echo "[Dev Stack] Instalando mise..."
  if ! command -v mise >/dev/null 2>&1; then
    curl -fsSL https://mise.run | sh
  fi
  export PATH="$HOME/.local/bin:$PATH"
  if [[ -n "$RUNTIMES" ]]; then
    IFS=',' read -ra RT_LIST <<< "$RUNTIMES"
    for rt in "${RT_LIST[@]}"; do
      echo "[Dev Stack] Instalando runtime $rt via mise..."
      mise use --global "$rt"
    done
  fi
fi

if [[ "$INSTALL_DOCKER" == true ]]; then
  echo "[Dev Stack] Instalando Docker..."
  sudo apt-get update
  sudo apt-get install -y docker.io docker-compose-v2
  sudo usermod -aG docker "$USER"
fi

case "$EDITOR_CHOICE" in
  "") ;;
  neovim)
    sudo apt-get install -y neovim
    ;;
  vscode)
    echo "[Dev Stack] Instalando Visual Studio Code via repositorio Microsoft APT..."
    sudo apt-get install -y wget gpg
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/packages.microsoft.gpg >/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
    sudo apt-get update
    sudo apt-get install -y code
    ;;
  zed)
    echo "[Dev Stack] Instalando Zed Editor..."
    curl -f https://zed.dev/install.sh | sh
    ;;
  cursor)
    echo "[Dev Stack] Baixe o pacote .deb oficial do Cursor em https://cursor.com/downloads"
    ;;
  *)
    echo "Editor desconhecido: $EDITOR_CHOICE" >&2
    exit 1
    ;;
esac

echo "[Dev Stack] Concluido!"
