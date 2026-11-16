#!/usr/bin/env bash
# ==============================================================================
# Lumen OS — Local Offline APT Repository Generator
# ==============================================================================
# Generates Packages and Packages.gz index files for an offline APT repository
# using dpkg-scanpackages with an automatic Python 3 fallback if dpkg-dev
# is not installed. Also generates a Release file for warning-free APT usage.
# Supports --verify mode to validate an existing repository pool.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_REPO_DIR="$WORKSPACE_ROOT/dist/debs"
REPO_DIR="$DEFAULT_REPO_DIR"
VERIFY_ONLY=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [REPO_DIR]

Generate Debian APT repository indexes (Packages, Packages.gz, Release)
for offline package installation.

Arguments:
  REPO_DIR             Directory containing .deb packages (default: dist/debs)

Options:
  --verify             Verify repository index validity without regenerating
  -h, --help           Show this help message and exit

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
echo "Target repository directory: $REPO_DIR"

verify_repo() {
    local target="$1"
    echo "Verifying APT repository at: $target..."
    if [[ ! -f "$target/Packages" ]]; then
        echo "ERROR: $target/Packages does not exist!" >&2
        return 1
    fi
    if [[ ! -f "$target/Packages.gz" ]]; then
        echo "ERROR: $target/Packages.gz does not exist!" >&2
        return 1
    fi
    if [[ ! -f "$target/Release" ]]; then
        echo "ERROR: $target/Release does not exist!" >&2
        return 1
    fi

    # Test gzip integrity
    if ! gzip -t "$target/Packages.gz"; then
        echo "ERROR: $target/Packages.gz is corrupted!" >&2
        return 1
    fi

    # Count packages in index
    local count
    count=$(grep -c "^Package: " "$target/Packages" || true)
    echo "Verified $count package(s) indexed in Packages."
    if [[ "$count" -eq 0 ]]; then
        echo "WARNING: Repository index is empty (0 packages)." >&2
        return 1
    fi

    # Check Packages.gz has stanzas
    local gz_count
    gz_count=$(zcat "$target/Packages.gz" | grep -c "^Package: " || true)
    if [[ "$gz_count" -ne "$count" ]]; then
        echo "ERROR: Packages ($count) and Packages.gz ($gz_count) count mismatch!" >&2
        return 1
    fi

    echo "Repository verification PASSED ($count packages indexed)."
    return 0
}

if [[ "$VERIFY_ONLY" == true ]]; then
    verify_repo "$REPO_DIR"
    exit 0
fi

# Find deb packages
mapfile -t DEBS < <(find "$REPO_DIR" -maxdepth 1 -name "*.deb" -type f | sort)
DEB_COUNT=${#DEBS[@]}

if [[ "$DEB_COUNT" -eq 0 ]]; then
    echo "ERROR: No .deb files found in $REPO_DIR!" >&2
    echo "Please build packages before creating repository index." >&2
    exit 1
fi

echo "Found $DEB_COUNT package(s) to index."

# Generate Packages index
if command -v dpkg-scanpackages >/dev/null 2>&1; then
    echo "Generating Packages index using dpkg-scanpackages..."
    (
        cd "$REPO_DIR"
        dpkg-scanpackages -m . /dev/null > Packages 2>/dev/null || dpkg-scanpackages -m . /dev/null > Packages
    )
else
    echo "dpkg-scanpackages not found; using embedded Python 3 generator fallback..."
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
        sys.stderr.write(f"Failed to inspect {deb_name}: {e}\n")
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

print(f"Python fallback indexed {len(entries)} package(s).")
PYEOF
fi

# Compress Packages to Packages.gz
echo "Compressing Packages index (gzip -9nc)..."
gzip -9nc "$REPO_DIR/Packages" > "$REPO_DIR/Packages.gz"

# Generate Release metadata file
echo "Generating Release metadata file..."
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
echo "=== Local APT repository generated successfully at: $REPO_DIR ==="
