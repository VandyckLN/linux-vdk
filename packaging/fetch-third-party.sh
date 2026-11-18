#!/usr/bin/env bash
# ==============================================================================
# Lumen OS — Download de pacotes de terceiros
# ==============================================================================
# Baixa a .deb do Mandacaru (EDR) fixada em packaging/third-party/mandacaru.lock,
# confere o SHA256 e copia para o diretório de saída (o repositório APT local).
# Um cache em dist/cache evita baixar de novo e permite rebuild offline.
#
# Uso: fetch-third-party.sh <diretório-de-saída>
# Variáveis: MANDACARU_LOCK, MANDACARU_URL, MANDACARU_SHA256, LUMEN_CACHE_DIR
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LOCK_FILE="${MANDACARU_LOCK:-$SCRIPT_DIR/third-party/mandacaru.lock}"
CACHE_DIR="${LUMEN_CACHE_DIR:-$WORKSPACE_ROOT/dist/cache}"

die() {
    echo "ERRO: $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || die "uso: $(basename "$0") <diretório-de-saída>"
OUTPUT_DIR="$1"
[[ -f "$LOCK_FILE" ]] || die "arquivo de versão não encontrado: $LOCK_FILE"

# O .lock é lido como dado (chave=valor), nunca carregado com source.
lock_version="" lock_url="" lock_sha=""
while IFS='=' read -r chave valor || [[ -n "$chave" ]]; do
    chave="${chave%$'\r'}"
    valor="${valor%$'\r'}"
    case "$chave" in
        MANDACARU_VERSION) lock_version="$valor" ;;
        MANDACARU_URL) lock_url="$valor" ;;
        MANDACARU_SHA256) lock_sha="$valor" ;;
    esac
done < "$LOCK_FILE"

VERSION="$lock_version"
URL="${MANDACARU_URL:-$lock_url}"
SHA256="${MANDACARU_SHA256:-$lock_sha}"

[[ -n "$VERSION" ]] || die "chave ausente no mandacaru.lock: MANDACARU_VERSION"
[[ -n "$URL" ]] || die "chave ausente no mandacaru.lock: MANDACARU_URL"
[[ -n "$SHA256" ]] || die "chave ausente no mandacaru.lock: MANDACARU_SHA256"

DEB_NAME="mandacaru_${VERSION}_all.deb"
CACHED="$CACHE_DIR/$DEB_NAME"
PARTIAL="$CACHED.part"

sha_of() {
    sha256sum "$1" | awk '{print $1}'
}

mkdir -p "$CACHE_DIR"

if [[ -f "$CACHED" && "$(sha_of "$CACHED")" == "$SHA256" ]]; then
    echo "[mandacaru] usando o cache: $CACHED"
else
    echo "[mandacaru] baixando a versão $VERSION de $URL"
    if ! curl --fail --silent --show-error --location --proto '=https,file' -o "$PARTIAL" "$URL"; then
        rm -f "$PARTIAL"
        die "não foi possível baixar o mandacaru de $URL"
    fi
    obtido="$(sha_of "$PARTIAL")"
    if [[ "$obtido" != "$SHA256" ]]; then
        rm -f "$PARTIAL"
        die "checksum do mandacaru não confere: esperado $SHA256, obtido $obtido"
    fi
    mv -f "$PARTIAL" "$CACHED"
fi

mkdir -p "$OUTPUT_DIR"
cp -f "$CACHED" "$OUTPUT_DIR/$DEB_NAME"
echo "[mandacaru] versão $VERSION pronta em $OUTPUT_DIR/$DEB_NAME"
