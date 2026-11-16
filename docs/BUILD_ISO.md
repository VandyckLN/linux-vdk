# Como Gerar Sua Própria ISO do Linux VDK

Sim, você consegue gerar a sua própria `.iso` bootável e instalável (UEFI + BIOS legada) diretamente a partir deste repositório — tanto **localmente no Ubuntu 26.04 / WSL2** quanto **remotamente pelo GitHub Actions** sem pesar na sua máquina.

---

## Opção 1: Gerar a ISO Localmente (Ubuntu 26.04 / WSL2)

### 1. Pré-requisitos (Prerequisites / Requirements)
* Pelo menos **15 GB livres** em disco dentro do sistema de arquivos nativo Linux (`~/projetos/...`, **nunca** em `/mnt/c` ou partições NTFS do Windows, pois o `debootstrap` exige permissões POSIX e symlinks nativos e fica extremamente lento em NTFS).
* Ubuntu 24.04 / 26.04 (nativo ou WSL2).
* Pacotes necessários no host:

```bash
sudo apt-get update
sudo apt-get install -y \
  debootstrap \
  squashfs-tools \
  xorriso \
  grub-pc-bin \
  grub-efi-amd64-bin \
  mtools \
  dosfstools \
  dpkg-dev \
  debhelper \
  fakeroot
```

> **Nota sobre WSL2 e dispositivos `loop`:**
> O pipeline `scripts/build-iso.sh` foi desenhado **sem depender de `losetup` / loop devices** (a imagem EFI FAT é montada com `mkfs.vfat` + `mcopy`), funcionando inclusive dentro do WSL2 e containers. Certifique-se apenas de que você tem permissão `sudo` para `debootstrap` e `chroot`.

### 2. Empacotar os módulos `.deb`
Gera os 6 pacotes `.deb` (`lumen-shell`, `lumen-compositor`, `lumen-system`, `lumen-dev-stack`, `lumen-welcome` e `lumen-desktop`) e o repositório APT local em `dist/debs/`:

```bash
cd /home/vandyck/projetos/Distro
./scripts/package-debs.sh
```

### 3. Construir a ISO instalável
Para validar pré-requisitos sem modificar nada:

```bash
./scripts/build-iso.sh --dry-run
```

Para gerar a ISO real:

```bash
sudo ./scripts/build-iso.sh
```

Ao final, os artefatos estarão em:
* `dist/linux-vdk-26.04-amd64.iso` (e symlink de compatibilidade `dist/lumen-os-26.04-amd64.iso`)
* `dist/linux-vdk-26.04-amd64.iso.sha256`

Para validar a integridade da ISO gerada:

```bash
sha256sum -c dist/linux-vdk-26.04-amd64.iso.sha256
```

*(Use `sudo ./scripts/build-iso.sh --clean` se quiser recriar o chroot do zero.)*

---

## 4. Testar a ISO em VM (QEMU/KVM)
Instale o QEMU e o firmware UEFI (OVMF) caso ainda não tenha:

```bash
sudo apt-get install -y qemu-system-x86 ovmf
```

Rode a ISO em modo **UEFI** (com fallback automático para `tcg` se `/dev/kvm` não estiver ativo no WSL2):

```bash
./scripts/test-iso-qemu.sh --uefi
```

Ou em modo **Legacy BIOS** / **Headless**:

```bash
./scripts/test-iso-qemu.sh --bios
./scripts/test-iso-qemu.sh --headless --ram 2048 --smp 2
```

---

## Opção 2: Gerar a ISO Automaticamente no GitHub Actions

Se você não quiser baixar pacotes e compactar o `squashfs` localmente:

1. Envie o repositório para o seu GitHub.
2. Acesse a aba **Actions** → **Build Linux VDK ISO** (`.github/workflows/build-iso.yml`).
3. Clique em **Run workflow** (`workflow_dispatch`) — ou faça `git push` na branch `main`.
4. Quando o job terminar, baixe o artefato **`linux-vdk-26.04-amd64-iso`** com a `.iso`, o `.sha256` e os `.deb`s prontos para gravar em pendrive (Ventoy / Rufus / `dd`) ou testar em VM.
