#!/usr/bin/env bash
# ==============================================================================
# Linux VDK (Ubuntu 26.04 LTS Minimal) - Pipeline Reproduzível de Geração de ISO
# Abordagem: debootstrap (minbase) + squashfs (zstd) + xorriso (UEFI + BIOS)
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-$ROOT_DIR/build/iso-work}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist}"
ISO_NAME="${ISO_NAME:-linux-vdk-26.04-amd64.iso}"
COMPAT_ISO_LINK="${COMPAT_ISO_LINK:-lumen-os-26.04-amd64.iso}"
UBUNTU_SUITE="${UBUNTU_SUITE:-resolute}"
UBUNTU_MIRROR="${UBUNTU_MIRROR:-http://archive.ubuntu.com/ubuntu}"
ARCH="amd64"
LIVE_USER="lumen"
HOSTNAME_LIVE="linux-vdk"

DRY_RUN=false
CLEAN_WORK=false

usage() {
  cat <<EOF
Linux VDK — Gerador de ISO Instalavel (Ubuntu 26.04 LTS Minimal)

Uso:
  sudo $0 [opções]

Opções:
  --work-dir DIR    Diretório temporário de chroot/staging (padrão: build/iso-work)
  --output PATH     Caminho da ISO final (padrão: dist/$ISO_NAME)
  --clean           Remove o diretório de trabalho antes de iniciar
  --dry-run         Valida pré-requisitos e exibe plano sem executar rootfs/ISO
  -h, --help        Exibe esta ajuda e sai

Exemplos:
  sudo ./scripts/build-iso.sh
  ./scripts/build-iso.sh --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --work-dir)
      WORK_DIR="${2:?--work-dir exige um caminho}"
      shift 2
      ;;
    --output)
      ISO_OUT_PATH="${2:?--output exige um caminho}"
      OUT_DIR="$(dirname "$ISO_OUT_PATH")"
      ISO_NAME="$(basename "$ISO_OUT_PATH")"
      shift 2
      ;;
    --clean)
      CLEAN_WORK=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[erro] Opção desconhecida: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

ISO_PATH="$OUT_DIR/$ISO_NAME"
CHROOT_DIR="$WORK_DIR/chroot"
STAGING_DIR="$WORK_DIR/staging"
DEBS_DIR="$ROOT_DIR/dist/debs"

log() {
  echo "[Linux VDK ISO] $*"
}

check_prerequisites() {
  local required_cmds=(debootstrap mksquashfs xorriso grub-mkstandalone mcopy mkfs.vfat sha256sum)
  local missing=()
  for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[erro] Ferramentas ausentes no host: ${missing[*]}" >&2
    echo "Instale no Ubuntu/WSL2 com:" >&2
    echo "  sudo apt-get update && sudo apt-get install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools dpkg-dev" >&2
    return 1
  fi
  return 0
}

cleanup_mounts() {
  local mnt
  for mnt in "$CHROOT_DIR/dev/pts" "$CHROOT_DIR/dev" "$CHROOT_DIR/proc" "$CHROOT_DIR/sys" "$CHROOT_DIR/mnt/debs"; do
    if mountpoint -q "$mnt" 2>/dev/null; then
      umount -lf "$mnt" || true
    fi
  done
}
trap cleanup_mounts EXIT INT TERM

if [[ "$DRY_RUN" == true ]]; then
  log "Modo --dry-run ativado."
  check_prerequisites || log "Aviso: rode o comando apt-get acima antes do build real."
  log "Plano de build:"
  log "  1. Empacotar .debs em $DEBS_DIR (scripts/package-debs.sh)"
  log "  2. Bootstrap Ubuntu $UBUNTU_SUITE ($ARCH, minbase) em $CHROOT_DIR"
  log "  3. Instalar kernel, casper, calamares, lumen-desktop e configurar usuário live '$LIVE_USER'"
  log "  4. Gerar filesystem.manifest e compactar filesystem.squashfs (zstd)"
  log "  5. Montar boot dual UEFI + BIOS (xorriso -as mkisofs) -> $ISO_PATH + .sha256"
  exit 0
fi

if [[ "$EUID" -ne 0 ]]; then
  echo "[erro] Execute com sudo para realizar debootstrap e chroot: sudo $0" >&2
  exit 1
fi

check_prerequisites

if [[ "$CLEAN_WORK" == true && -d "$WORK_DIR" ]]; then
  log "Limpando diretório de trabalho $WORK_DIR..."
  cleanup_mounts
  rm -rf "$WORK_DIR"
fi

mkdir -p "$CHROOT_DIR" "$STAGING_DIR"/{casper,boot/grub,EFI/boot,isolinux} "$OUT_DIR"

# 1. Garantir pacotes .deb compilados
if [[ ! -d "$DEBS_DIR" ]] || ! compgen -G "$DEBS_DIR/*.deb" >/dev/null; then
  log "Construindo pacotes .deb do Linux VDK..."
  bash "$ROOT_DIR/scripts/package-debs.sh"
fi

# 2. Debootstrap Ubuntu 26.04 Minimal
if [[ ! -f "$CHROOT_DIR/etc/os-release" ]]; then
  log "Executando debootstrap ($UBUNTU_SUITE / $ARCH / variant=minbase)..."
  debootstrap --arch="$ARCH" --variant=minbase "$UBUNTU_SUITE" "$CHROOT_DIR" "$UBUNTU_MIRROR"
else
  log "Chroot já existente em $CHROOT_DIR (reaproveitando; use --clean para recriar)."
fi

# 3. Configurar APT, mounts e instalar base + Linux VDK + Calamares
cat > "$CHROOT_DIR/etc/apt/sources.list" <<EOF
deb $UBUNTU_MIRROR $UBUNTU_SUITE main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_SUITE-updates main restricted universe multiverse
deb $UBUNTU_MIRROR $UBUNTU_SUITE-security main restricted universe multiverse
EOF

cp -L /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

# Igual ao Ubuntu Desktop: sem este netplan, o 10-globally-managed-devices.conf
# do NetworkManager deixa a rede cabeada "unmanaged" (live e sistema instalado).
install -d -m755 "$CHROOT_DIR/etc/netplan"
cat > "$CHROOT_DIR/etc/netplan/01-network-manager-all.yaml" <<'EOF'
network:
  version: 2
  renderer: NetworkManager
EOF
chmod 600 "$CHROOT_DIR/etc/netplan/01-network-manager-all.yaml"
mkdir -p "$CHROOT_DIR/mnt/debs"
mount --bind "$DEBS_DIR" "$CHROOT_DIR/mnt/debs"
mount --bind /dev "$CHROOT_DIR/dev"
mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
mount -t proc proc "$CHROOT_DIR/proc"
mount -t sysfs sysfs "$CHROOT_DIR/sys"

log "Instalando kernel, live-boot (casper), Calamares e pacotes Linux VDK no chroot..."
chroot "$CHROOT_DIR" /bin/bash -euo pipefail -c "
export DEBIAN_FRONTEND=noninteractive
echo '$HOSTNAME_LIVE' > /etc/hostname
apt-get update
apt-get install -y --no-install-recommends \
  linux-generic linux-headers-generic casper discover laptop-detect os-prober \
  network-manager sudo locales ca-certificates \
  grub-pc-bin grub-efi-amd64-bin shim-signed \
  calamares qml6-module-qtquick-controls

# Instala repositório local de pacotes .deb do Linux VDK
echo 'deb [trusted=yes] file:/mnt/debs ./' > /etc/apt/sources.list.d/linux-vdk-local.list
apt-get update
apt-get install -y lumen-desktop
# A ISO nunca sai sem o EDR: um dist/debs antigo (sem mandacaru) cairia aqui.
dpkg -s mandacaru python3-bpfcc linux-headers-generic >/dev/null || {
  echo 'ERRO: o Mandacaru (EDR) não foi instalado no chroot. Rode ./scripts/package-debs.sh --clean e gere a ISO de novo.' >&2
  exit 1
}
rm -f /etc/apt/sources.list.d/linux-vdk-local.list

# Copia configuração do Calamares com branding Linux VDK
mkdir -p /etc/calamares
"

cp -a "$ROOT_DIR/installer/calamares/." "$CHROOT_DIR/etc/calamares/"
install -Dm755 "$ROOT_DIR/installer/calamares/scripts/launch-calamares.sh" \
  "$CHROOT_DIR/usr/local/bin/launch-calamares.sh"
install -Dm755 "$ROOT_DIR/installer/calamares/scripts/lumen-postinstall.sh" \
  "$CHROOT_DIR/usr/local/bin/lumen-postinstall.sh"
install -Dm644 "$ROOT_DIR/installer/calamares/install-lumen.desktop" \
  "$CHROOT_DIR/usr/share/applications/install-lumen.desktop"
install -Dm644 "$ROOT_DIR/installer/calamares/install-lumen.desktop" \
  "$CHROOT_DIR/etc/xdg/autostart/install-lumen.desktop"

chroot "$CHROOT_DIR" /bin/bash -euo pipefail -c "
# Configura usuário live ($LIVE_USER) sem senha para sessão live
if ! id -u $LIVE_USER >/dev/null 2>&1; then
  useradd -m -s /bin/bash -G sudo,video,audio,render,mandacaru $LIVE_USER
  passwd -d $LIVE_USER
fi
echo '$LIVE_USER ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-$LIVE_USER-live
chmod 440 /etc/sudoers.d/99-$LIVE_USER-live

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
"

# Gera manifests antes de desmontar
log "Gerando filesystem.manifest..."
chroot "$CHROOT_DIR" dpkg-query -W --showformat='${Package} ${Version}\n' > "$STAGING_DIR/casper/filesystem.manifest"
cp "$STAGING_DIR/casper/filesystem.manifest" "$STAGING_DIR/casper/filesystem.manifest-desktop"

cleanup_mounts

# O resolv.conf do host só servia para o apt dentro do chroot. Se for para a
# ISO, a sessão live herda o DNS do host (ex.: 10.255.255.254 do WSL) e fica
# sem resolver nomes; sem ele, o NetworkManager gera o arquivo no boot.
rm -f "$CHROOT_DIR/etc/resolv.conf"

# 4. Copiar kernel/initrd e compactar rootfs com zstd
log "Copiando kernel e initrd para staging..."
cp "$CHROOT_DIR"/boot/vmlinuz-* "$STAGING_DIR/casper/vmlinuz"
cp "$CHROOT_DIR"/boot/initrd.img-* "$STAGING_DIR/casper/initrd"

log "Compactando rootfs em filesystem.squashfs (zstd)..."
mksquashfs "$CHROOT_DIR" "$STAGING_DIR/casper/filesystem.squashfs" \
  -comp zstd -Xcompression-level 6 -noappend -wildcards \
  -e "boot/*" "proc/*" "sys/*" "dev/*" "mnt/*" "tmp/*"

printf "%s\n" "$(du -sx --block-size=1 "$CHROOT_DIR" | cut -f1)" > "$STAGING_DIR/casper/filesystem.size"

# 5. Bootloader Dual (UEFI + Legacy BIOS) sem depender de loop devices (compatível com WSL2)
log "Configurando boot dual UEFI e Legacy BIOS..."
cat > "$STAGING_DIR/boot/grub/grub.cfg" <<EOF
# O grub-mkstandalone embute este arquivo num memdisk; sem o search, o root
# fica no (memdisk) e o GRUB não encontra /casper/vmlinuz na mídia.
search --no-floppy --set=root --file /casper/filesystem.squashfs
set default="0"
set timeout=5

menuentry "Linux VDK 26.04 LTS (Live + Instalador)" {
    linux /casper/vmlinuz boot=casper quiet splash ---
    initrd /casper/initrd
}

menuentry "Linux VDK 26.04 LTS (Modo Seguro / Nomodeset)" {
    linux /casper/vmlinuz boot=casper nomodeset ---
    initrd /casper/initrd
}
EOF

# Imagem EFI FAT sem loop device (usando mkfs.vfat + mcopy)
grub-mkstandalone \
  --format=x86_64-efi \
  --output="$WORK_DIR/bootx64.efi" \
  --locales="" \
  --fonts="" \
  "boot/grub/grub.cfg=$STAGING_DIR/boot/grub/grub.cfg"

cp "$WORK_DIR/bootx64.efi" "$STAGING_DIR/EFI/boot/bootx64.efi"
dd if=/dev/zero of="$STAGING_DIR/boot/grub/efi.img" bs=1M count=8 status=none
mkfs.vfat "$STAGING_DIR/boot/grub/efi.img" >/dev/null
mmd -i "$STAGING_DIR/boot/grub/efi.img" ::/EFI ::/EFI/boot
mcopy -i "$STAGING_DIR/boot/grub/efi.img" "$WORK_DIR/bootx64.efi" ::/EFI/boot/bootx64.efi

# Imagem El Torito Legacy BIOS
grub-mkstandalone \
  --format=i386-pc \
  --output="$WORK_DIR/core.img" \
  --install-modules="linux normal iso9660 biosdisk memdisk search tar ls" \
  --modules="linux normal iso9660 biosdisk" \
  --locales="" \
  --fonts="" \
  "boot/grub/grub.cfg=$STAGING_DIR/boot/grub/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img "$WORK_DIR/core.img" > "$STAGING_DIR/boot/grub/bios.img"

# 6. Gerar ISO híbrida com xorriso
log "Gerando imagem ISO híbrida em $ISO_PATH..."
xorriso -as mkisofs \
  -iso-level 3 \
  -full-iso9660-filenames \
  -R -J \
  -volid "LINUX_VDK_26_04" \
  -eltorito-boot boot/grub/bios.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --eltorito-catalog boot/grub/boot.cat \
  -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
  -output "$ISO_PATH" \
  "$STAGING_DIR"

(
  cd "$OUT_DIR"
  sha256sum "$ISO_NAME" > "${ISO_NAME}.sha256"
  if [[ "$ISO_NAME" != "$COMPAT_ISO_LINK" ]]; then
    ln -sf "$ISO_NAME" "$COMPAT_ISO_LINK"
  fi
)

log "ISO gerada com sucesso!"
log "  Arquivo: $ISO_PATH"
log "  SHA256:  ${ISO_PATH}.sha256"
