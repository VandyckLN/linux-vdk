#!/usr/bin/env bash
# ==============================================================================
# Lumen OS — Master Debian Packaging Entrypoint
# ==============================================================================
# Gera os 6 pacotes Debian modulares e o pool do repositório APT offline
# local (Packages, Packages.gz, Release).
# Idempotente, seguro e estruturado com tratamento de erros estrito.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

OUTPUT_DIR="$WORKSPACE_ROOT/dist/debs"
CLEAN_BUILD=false
SKIP_REPO=false
VERBOSE=false

usage() {
    cat <<EOF
Uso: $(basename "$0") [OPÇÕES]

Compila os pacotes Debian do Lumen OS e gera o índice do repositório APT offline.

Opções:
  --clean              Limpa os diretórios de build em dist/ antes de compilar
  --skip-repo          Compila os pacotes .deb mas pula a geração do índice do repositório
  --output-dir <DIR>   Define o diretório de destino dos pacotes .deb (padrão: dist/debs)
  -v, --verbose        Ativa a saída detalhada
  -h, --help           Mostra esta ajuda e sai

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --skip-repo)
            SKIP_REPO=true
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1" >&2
            usage
            exit 1
            ;;
    esac
done

echo "======================================================================"
echo " Lumen OS — Modular Debian Packaging & Repository Generator"
echo "======================================================================"
echo "Raiz do workspace: $WORKSPACE_ROOT"
echo "Diretório de saída: $OUTPUT_DIR"

# 1. Verificação prévia de dependências
echo "[1/5] Verificando os pré-requisitos de empacotamento..."
MISSING_TOOLS=()
for tool in dpkg-deb gzip awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    echo "ERRO: utilitários de empacotamento obrigatórios ausentes: ${MISSING_TOOLS[*]}" >&2
    echo "Instale com: sudo apt-get install -y dpkg gzip gawk" >&2
    exit 1
fi

if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
    echo "Aviso: dpkg-scanpackages não encontrado (dpkg-dev não instalado). O fallback em Python 3 será usado."
fi

# 2. Build limpo, se solicitado
if [[ "$CLEAN_BUILD" == true ]]; then
    echo "[2/5] Limpando artefatos de build..."
    rm -rf "$WORKSPACE_ROOT/dist/build" "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"

# 3. Gerar os pacotes .deb
echo "[3/5] Gerando os pacotes Debian modulares..."
BUILD_SCRIPT="$WORKSPACE_ROOT/packaging/build-debs.sh"
if [[ ! -x "$BUILD_SCRIPT" ]]; then
    if [[ -f "$BUILD_SCRIPT" ]]; then
        bash "$BUILD_SCRIPT" "$OUTPUT_DIR"
    else
        echo "ERRO: script de build de pacotes não encontrado em: $BUILD_SCRIPT" >&2
        exit 1
    fi
else
    "$BUILD_SCRIPT" "$OUTPUT_DIR"
fi

# 4. Baixar e conferir os pacotes de terceiros (Mandacaru)
echo "[4/5] Baixando e conferindo o Mandacaru (EDR)..."
FETCH_SCRIPT="$WORKSPACE_ROOT/packaging/fetch-third-party.sh"
if [[ ! -x "$FETCH_SCRIPT" ]]; then
    if [[ -f "$FETCH_SCRIPT" ]]; then
        bash "$FETCH_SCRIPT" "$OUTPUT_DIR"
    else
        echo "ERRO: script de download de terceiros não encontrado em: $FETCH_SCRIPT" >&2
        exit 1
    fi
else
    "$FETCH_SCRIPT" "$OUTPUT_DIR"
fi

# 5. Gerar o índice do repositório local
if [[ "$SKIP_REPO" == false ]]; then
    echo "[5/5] Criando o índice do repositório APT offline..."
    REPO_SCRIPT="$WORKSPACE_ROOT/packaging/create-local-repo.sh"
    if [[ ! -x "$REPO_SCRIPT" ]]; then
        if [[ -f "$REPO_SCRIPT" ]]; then
            bash "$REPO_SCRIPT" "$OUTPUT_DIR"
        else
            echo "ERRO: script gerador do repositório não encontrado em: $REPO_SCRIPT" >&2
            exit 1
        fi
    else
        "$REPO_SCRIPT" "$OUTPUT_DIR"
    fi
else
    echo "[5/5] Pulando a criação do índice do repositório (--skip-repo informado)."
fi

# 6. Resumo do build e manifesto
echo ""
echo "======================================================================"
echo " Lumen OS Packaging Build Manifest"
echo "======================================================================"
EXPECTED_PACKAGES=(
    "lumen-shell"
    "lumen-compositor"
    "lumen-system"
    "lumen-dev-stack"
    "lumen-welcome"
    "lumen-desktop"
    "mandacaru"
)

ALL_PRESENT=true
printf "%-20s %-16s %-12s %s\n" "PACOTE" "VERSÃO" "TAMANHO" "SHA256 (16 primeiros)"
printf "%-20s %-16s %-12s %s\n" "--------------------" "----------------" "------------" "----------------"

for pkg in "${EXPECTED_PACKAGES[@]}"; do
    MATCH=$(find "$OUTPUT_DIR" -maxdepth 1 -name "${pkg}_*.deb" | head -n 1)
    if [[ -n "$MATCH" && -f "$MATCH" ]]; then
        VER=$(dpkg-deb -f "$MATCH" Version 2>/dev/null || echo "desconhecida")
        SZ=$(stat -c%s "$MATCH" 2>/dev/null || echo "desconhecido")
        CSUM=$(sha256sum "$MATCH" | awk '{print substr($1, 1, 16)}')
        printf "%-20s %-16s %-12s %s\n" "$pkg" "$VER" "${SZ} B" "$CSUM..."
    else
        printf "%-20s %-16s %-12s %s\n" "$pkg" "AUSENTE" "-" "-"
        ALL_PRESENT=false
    fi
done

echo "======================================================================"
if [[ "$ALL_PRESENT" == false ]]; then
    echo "ERRO: um ou mais pacotes esperados não foram gerados!" >&2
    exit 1
fi

echo "Build concluído. Saída preparada em: $OUTPUT_DIR"
exit 0
