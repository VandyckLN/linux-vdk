#!/usr/bin/env bash
# ==============================================================================
# Linux VDK - Runner de Teste e Validação de ISO em QEMU/KVM (UEFI + BIOS)
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_ISO="$ROOT_DIR/dist/linux-vdk-26.04-amd64.iso"
COMPAT_ISO="$ROOT_DIR/dist/lumen-os-26.04-amd64.iso"

ISO_PATH=""
BOOT_MODE="uefi"
HEADLESS=false
RAM_MB="2048"
SMP_CORES="2"
DRY_RUN=false

usage() {
  cat <<EOF
Linux VDK — Teste da ISO em Máquina Virtual QEMU

Uso:
  $0 [opções]

Opções:
  --iso PATH        Caminho da ISO (padrão: dist/linux-vdk-26.04-amd64.iso)
  --uefi            Inicializa em modo UEFI usando firmware OVMF (padrão)
  --bios            Inicializa em modo Legacy BIOS
  --headless        Executa sem janela gráfica (-nographic / serial)
  --ram MB          Memória RAM da VM em MB (padrão: 2048)
  --smp CORES       Número de vCPUs (padrão: 2)
  --dry-run         Valida argumentos/OVMF/KVM e imprime o comando QEMU
  -h, --help        Mostra esta ajuda e sai
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iso)
      ISO_PATH="${2:?--iso exige um caminho}"
      shift 2
      ;;
    --uefi)
      BOOT_MODE="uefi"
      shift
      ;;
    --bios)
      BOOT_MODE="bios"
      shift
      ;;
    --headless)
      HEADLESS=true
      shift
      ;;
    --ram)
      RAM_MB="${2:?--ram exige valor em MB}"
      shift 2
      ;;
    --smp)
      SMP_CORES="${2:?--smp exige numero de vCPUs}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "[erro] Opção desconhecida: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -z "$ISO_PATH" ]]; then
        ISO_PATH="$1"
        shift
      else
        echo "[erro] Argumento inesperado: $1" >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$ISO_PATH" ]]; then
  if [[ -f "$DEFAULT_ISO" ]]; then
    ISO_PATH="$DEFAULT_ISO"
  elif [[ -f "$COMPAT_ISO" ]]; then
    ISO_PATH="$COMPAT_ISO"
  else
    ISO_PATH="$DEFAULT_ISO"
  fi
fi

find_ovmf() {
  local candidates=(
    "/usr/share/OVMF/OVMF_CODE_4M.fd"
    "/usr/share/OVMF/OVMF_CODE.fd"
    "/usr/share/ovmf/OVMF.fd"
    "/usr/share/qemu/OVMF.fd"
  )
  for path in "${candidates[@]}"; do
    if [[ -f "$path" ]]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

if [[ "$DRY_RUN" != true && ! -f "$ISO_PATH" ]]; then
  echo "[erro] ISO não encontrada: $ISO_PATH" >&2
  echo "Gere a ISO primeiro com: sudo ./scripts/build-iso.sh" >&2
  exit 1
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] qemu-system-x86_64 não encontrado (instale pacote qemu-system-x86)."
  else
    echo "[erro] qemu-system-x86_64 não instalado. Rode: sudo apt-get install -y qemu-system-x86 ovmf" >&2
    exit 1
  fi
fi

QEMU_ARGS=(
  -m "$RAM_MB"
  -smp "$SMP_CORES"
  -cdrom "$ISO_PATH"
  -boot d
  -net nic -net user
)

# Detecta aceleração KVM com fallback seguro para TCG em software
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
  QEMU_ARGS+=(-enable-kvm -cpu host)
else
  echo "[qemu] /dev/kvm indisponível; usando emulação tcg em software."
  QEMU_ARGS+=(-accel tcg -cpu qemu64)
fi

if [[ "$BOOT_MODE" == "uefi" ]]; then
  OVMF_PATH="$(find_ovmf || true)"
  if [[ -n "$OVMF_PATH" ]]; then
    QEMU_ARGS+=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF_PATH")
  elif [[ "$DRY_RUN" == true ]]; then
    QEMU_ARGS+=(-drive "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd")
  else
    echo "[erro] Firmware OVMF UEFI não encontrado. Instale com: sudo apt-get install -y ovmf" >&2
    exit 1
  fi
fi

if [[ "$HEADLESS" == true ]]; then
  QEMU_ARGS+=(-nographic -serial mon:stdio)
else
  QEMU_ARGS+=(-vga virtio -display gtk,gl=on)
fi

echo "[qemu] Comando: qemu-system-x86_64 ${QEMU_ARGS[*]}"
if [[ "$DRY_RUN" == true ]]; then
  exit 0
fi

exec qemu-system-x86_64 "${QEMU_ARGS[@]}"
