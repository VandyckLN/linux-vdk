# Linux VDK (Ubuntu 26.04 LTS • Dev Edition)

Distro Linux leve, instalável e voltada para programação, baseada no **Ubuntu 26.04 LTS**, com interface **Curved Glass** capaz de alternar em tempo real entre **Barra Lateral** (recolhível/expansível) e **Barra Horizontal**.

## Estrutura do Projeto

### Fase 1 — Interface Curved Glass & Compositor
- `shell/` — Shell nativo em **GTK4 + `gtk4-layer-shell`** (Python/PyGObject) com métricas em tempo real (`/proc` CPU/RAM, portas abertas, Docker) e troca dinâmica entre lateral e horizontal.
- `compositor/` — Configurações do **Hyprland 0.53** e **Wayfire 0.10** com `blur` real para a barra `curved-shell`.
- `preview/index.html` — Protótipo interativo no navegador.
- `config/shell.default.json` — Configuração padrão (`~/.config/lumen-os/shell.json`).

### Fase 2 — Camada Dev-First, Otimizações Ubuntu & 1º Boot
- `system/` — Tuning para programação (`99-lumen-dev.conf` com `inotify` e `swappiness`), `zram-generator.conf` e pinning opcional `--no-snap`.
- `dev-stack/` — Dotfiles enxutos (**Kitty**, **Starship**, **tmux**, **Neovim**), `packages.list` e `setup-dev-env.sh` com **`mise`**, **Docker** e editores.
- `welcome/` — Assistente de 1º Boot em **GTK4 Curved Glass**.

### Fase 3 — Empacotamento `.deb`, Calamares, ISO & CI
- `packaging/` & `scripts/package-debs.sh` — Gera os 6 pacotes `.deb` e o repositório APT local em `dist/debs/`.
- `installer/calamares/` — Instalador gráfico Calamares com tema *Curved Glass* e branding **Linux VDK**.
- `scripts/build-iso.sh` — Pipeline reproduzível (`debootstrap` + `squashfs` + `xorriso`) com boot dual **UEFI + BIOS**.
- `scripts/test-iso-qemu.sh` — Teste automatizado da ISO em QEMU/KVM (UEFI/BIOS).
- `.github/workflows/build-iso.yml` — Workflow de CI para gerar e publicar a ISO no GitHub Actions.
- `docs/BUILD_ISO.md` — Guia passo a passo completo para gerar sua própria ISO.

## Comandos Rápidos

```bash
# Preview do Shell e Assistente de 1º Boot
./scripts/run-preview.sh
./scripts/run-welcome.sh --dry-run

# Empacotar .debs e rodar suíte E2E
./scripts/package-debs.sh
bash tests/e2e/run-e2e-tests.sh

# Gerar sua própria ISO (veja docs/BUILD_ISO.md)
sudo ./scripts/build-iso.sh
./scripts/test-iso-qemu.sh --uefi
```
