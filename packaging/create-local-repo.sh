#!/usr/bin/env bash
# ==============================================================================
# Lumen OS — Local Offline APT Repository Generator
# ==============================================================================
# Gera os arquivos de índice Packages e Packages.gz de um repositório APT offline
# usando dpkg-scanpackages, com fallback automático em Python 3 se o dpkg-dev
# não estiver instalado. Também gera um arquivo Release para uso do APT sem avisos.
# Suporta o modo --verify para validar um pool de repositório existente.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_REPO_DIR="$WORKSPACE_ROOT/dist/debs"
REPO_DIR="$DEFAULT_REPO_DIR"
VERIFY_ONLY=false

usage() {
    cat <<EOF
Uso: $(basename "$0") [OPÇÕES] [REPO_DIR]

Gera os índices de repositório APT Debian (Packages, Packages.gz, Release)
para instalação offline de pacotes.

Argumentos:
  REPO_DIR             Diretório com os pacotes .deb (padrão: dist/debs)

Opções:
  --verify             Verifica a validade do índice do repositório sem regenerá-lo
  -h, --help           Mostra esta ajuda e sai

EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify)
            VERIFY_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            REPO_DIR="$1"
            shift
            ;;
    esac
done

REPO_DIR="$(mkdir -p "$REPO_DIR" && cd "$REPO_DIR" && pwd)"

echo "=== Lumen OS Local APT Repository Generator ==="
echo "Diretório do repositório de destino: $REPO_DIR"

verify_repo() {
    local target="$1"
    echo "Verificando o repositório APT em: $target..."
    if [[ ! -f "$target/Packages" ]]; then
        echo "ERRO: $target/Packages não existe!" >&2
        return 1
    fi
    if [[ ! -f "$target/Packages.gz" ]]; then
        echo "ERRO: $target/Packages.gz não existe!" >&2
        return 1
    fi
    if [[ ! -f "$target/Release" ]]; then
        echo "ERRO: $target/Release não existe!" >&2
        return 1
    fi

    # Testa a integridade do gzip
    if ! gzip -t "$target/Packages.gz"; then
        echo "ERRO: $target/Packages.gz está corrompido!" >&2
        return 1
    fi

    # Conta os pacotes no índice
    local count
    count=$(grep -c "^Package: " "$target/Packages" || true)
    echo "Verificado(s) $count pacote(s) indexado(s) em Packages."
    if [[ "$count" -eq 0 ]]; then
        echo "AVISO: o índice do repositório está vazio (0 pacotes)." >&2
        return 1
    fi

    # Verifica se o Packages.gz tem stanzas
    local gz_count
    gz_count=$(zcat "$target/Packages.gz" | grep -c "^Package: " || true)
    if [[ "$gz_count" -ne "$count" ]]; then
        echo "ERRO: contagem divergente entre Packages ($count) e Packages.gz ($gz_count)!" >&2
        return 1
    fi

    echo "Verificação do repositório APROVADA ($count pacotes indexados)."
    return 0
}

if [[ "$VERIFY_ONLY" == true ]]; then
    verify_repo "$REPO_DIR"
    exit 0
fi

# Localiza os pacotes deb
mapfile -t DEBS < <(find "$REPO_DIR" -maxdepth 1 -name "*.deb" -type f | sort)
DEB_COUNT=${#DEBS[@]}

if [[ "$DEB_COUNT" -eq 0 ]]; then
    echo "ERROR: No .deb files found in $REPO_DIR!" >&2
    echo "Gere os pacotes antes de criar o índice do repositório." >&2
    exit 1
fi

echo "Encontrado(s) $DEB_COUNT pacote(s) para indexar."

# Gera o índice Packages
if command -v dpkg-scanpackages >/dev/null 2>&1; then
    echo "Gerando o índice Packages com dpkg-scanpackages..."
    (
        cd "$REPO_DIR"
        dpkg-scanpackages -m . /dev/null > Packages 2>/dev/null || dpkg-scanpackages -m . /dev/null > Packages
    )
else
    echo "dpkg-scanpackages não encontrado; usando o gerador embutido em Python 3 como fallback..."
    python3 - "$REPO_DIR" <<'PYEOF'
import os
import sys
import glob
import hashlib
import subprocess

repo_dir = sys.argv[1]
debs = sorted(glob.glob(os.path.join(repo_dir, "*.deb")))

if not debs:
    sys.stderr.write("No .deb packages found in " + repo_dir + "\n")
    sys.exit(1)

entries = []
for deb_path in debs:
    deb_name = os.path.basename(deb_path)
    try:
        res = subprocess.run(["dpkg-deb", "-f", deb_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
        control_fields = res.stdout.strip()
    except Exception as e:
        sys.stderr.write(f"Falha ao inspecionar {deb_name}: {e}\n")
        sys.exit(1)

    file_size = os.path.getsize(deb_path)
    with open(deb_path, "rb") as f:
        content = f.read()
    md5 = hashlib.md5(content).hexdigest()
    sha1 = hashlib.sha1(content).hexdigest()
    sha256 = hashlib.sha256(content).hexdigest()

    entry = (
        f"{control_fields}\n"
        f"Filename: ./{deb_name}\n"
        f"Size: {file_size}\n"
        f"MD5sum: {md5}\n"
        f"SHA1: {sha1}\n"
        f"SHA256: {sha256}\n"
    )
    entries.append(entry)

out_path = os.path.join(repo_dir, "Packages")
with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(entries) + "\n")

print(f"Fallback Python indexou {len(entries)} pacote(s).")
PYEOF
fi

# Compacta Packages em Packages.gz
echo "Compactando o índice Packages (gzip -9nc)..."
gzip -9nc "$REPO_DIR/Packages" > "$REPO_DIR/Packages.gz"

# Gera o arquivo de metadados Release
echo "Gerando o arquivo de metadados Release..."
PKG_SIZE=$(stat -c%s "$REPO_DIR/Packages")
PKG_SHA256=$(sha256sum "$REPO_DIR/Packages" | awk '{print $1}')
PKG_MD5=$(md5sum "$REPO_DIR/Packages" | awk '{print $1}')

PKG_GZ_SIZE=$(stat -c%s "$REPO_DIR/Packages.gz")
PKG_GZ_SHA256=$(sha256sum "$REPO_DIR/Packages.gz" | awk '{print $1}')
PKG_GZ_MD5=$(md5sum "$REPO_DIR/Packages.gz" | awk '{print $1}')

cat <<EOF > "$REPO_DIR/Release"
Archive: resolute
Version: 26.04
Component: main
Origin: Lumen OS
Label: Lumen OS Offline Repository
Architecture: amd64 all
Date: $(date -Ru)
MD5Sum:
 ${PKG_MD5} ${PKG_SIZE} Packages
 ${PKG_GZ_MD5} ${PKG_GZ_SIZE} Packages.gz
SHA256:
 ${PKG_SHA256} ${PKG_SIZE} Packages
 ${PKG_GZ_SHA256} ${PKG_GZ_SIZE} Packages.gz
EOF

verify_repo "$REPO_DIR"
echo "=== Repositório APT local gerado com sucesso em: $REPO_DIR ==="
