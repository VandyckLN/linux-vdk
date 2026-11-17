# Lumen OS developer environment profile defaults
if [ -d "$HOME/.local/bin" ]; then
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
fi

if [ -d "$HOME/.cargo/bin" ]; then
    case ":$PATH:" in
        *":$HOME/.cargo/bin:"*) ;;
        *) export PATH="$HOME/.cargo/bin:$PATH" ;;
    esac
fi

# Ativa o mise, se instalado
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
fi

# Ativa o starship, se instalado
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
fi
