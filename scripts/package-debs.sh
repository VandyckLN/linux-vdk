#!/usr/bin/env bash
# ==============================================================================
# Lumen OS — Master Debian Packaging Entrypoint
# ==============================================================================
# Builds all 6 modular Debian packages and generates the local offline APT
# repository pool (Packages, Packages.gz, Release).
# Idempotent, safe, and structured with strict error handling.
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
Usage: $(basename "$0") [OPTIONS]

Compile Lumen OS Debian packages and generate the offline APT repository index.

Options:
  --clean              Clean dist/ build directories before compiling
  --skip-repo          Compile .deb packages but skip repository index generation
  --output-dir <DIR>   Set destination directory for .deb packages (default: dist/debs)
  -v, --verbose        Enable verbose output
  -h, --help           Show this help message and exit

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
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

echo "======================================================================"
echo " Lumen OS — Modular Debian Packaging & Repository Generator"
echo "======================================================================"
echo "Workspace root: $WORKSPACE_ROOT"
echo "Output directory: $OUTPUT_DIR"

# 1. Pre-flight dependency check
echo "[1/4] Checking packaging pre-requisites..."
MISSING_TOOLS=()
for tool in dpkg-deb gzip awk; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        MISSING_TOOLS+=("$tool")
    fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    echo "ERROR: Missing required packaging utilities: ${MISSING_TOOLS[*]}" >&2
    echo "Install with: sudo apt-get install -y dpkg gzip gawk" >&2
    exit 1
fi

if ! command -v dpkg-scanpackages >/dev/null 2>&1; then
    echo "Notice: dpkg-scanpackages not found (dpkg-dev not installed). Python 3 fallback will be used."
fi

# 2. Clean build if requested
if [[ "$CLEAN_BUILD" == true ]]; then
    echo "[2/4] Cleaning build artifacts..."
    rm -rf "$WORKSPACE_ROOT/dist/build" "$OUTPUT_DIR"
fi

mkdir -p "$OUTPUT_DIR"

# 3. Build .deb packages
echo "[3/4] Building modular Debian packages..."
BUILD_SCRIPT="$WORKSPACE_ROOT/packaging/build-debs.sh"
if [[ ! -x "$BUILD_SCRIPT" ]]; then
    if [[ -f "$BUILD_SCRIPT" ]]; then
        bash "$BUILD_SCRIPT" "$OUTPUT_DIR"
    else
        echo "ERROR: Package build script not found at: $BUILD_SCRIPT" >&2
        exit 1
    fi
else
    "$BUILD_SCRIPT" "$OUTPUT_DIR"
fi

# 4. Generate Local Repository Index
if [[ "$SKIP_REPO" == false ]]; then
    echo "[4/4] Creating offline APT repository index..."
    REPO_SCRIPT="$WORKSPACE_ROOT/packaging/create-local-repo.sh"
    if [[ ! -x "$REPO_SCRIPT" ]]; then
        if [[ -f "$REPO_SCRIPT" ]]; then
            bash "$REPO_SCRIPT" "$OUTPUT_DIR"
        else
            echo "ERROR: Repository generator script not found at: $REPO_SCRIPT" >&2
            exit 1
        fi
    else
        "$REPO_SCRIPT" "$OUTPUT_DIR"
    fi
else
    echo "[4/4] Skipping repository index creation (--skip-repo specified)."
fi

# 5. Build Summary and Manifest
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
)

ALL_PRESENT=true
printf "%-20s %-16s %-12s %s\n" "PACKAGE" "VERSION" "SIZE" "SHA256 (first 16)"
printf "%-20s %-16s %-12s %s\n" "--------------------" "----------------" "------------" "----------------"

for pkg in "${EXPECTED_PACKAGES[@]}"; do
    MATCH=$(find "$OUTPUT_DIR" -maxdepth 1 -name "${pkg}_*.deb" | head -n 1)
    if [[ -n "$MATCH" && -f "$MATCH" ]]; then
        VER=$(dpkg-deb -f "$MATCH" Version 2>/dev/null || echo "unknown")
        SZ=$(stat -c%s "$MATCH" 2>/dev/null || echo "unknown")
        CSUM=$(sha256sum "$MATCH" | awk '{print substr($1, 1, 16)}')
        printf "%-20s %-16s %-12s %s\n" "$pkg" "$VER" "${SZ} B" "$CSUM..."
    else
        printf "%-20s %-16s %-12s %s\n" "$pkg" "MISSING" "-" "-"
        ALL_PRESENT=false
    fi
done

echo "======================================================================"
if [[ "$ALL_PRESENT" == false ]]; then
    echo "ERROR: One or more expected packages were not built!" >&2
    exit 1
fi

echo "Build complete. Output staged at: $OUTPUT_DIR"
exit 0
