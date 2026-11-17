# Projeto: Lumen OS — Empacotamento da Distro e Pipeline de ISO

## Arquitetura
- **Base da Distribuição**: Ubuntu 26.04.1 LTS (Resolute Raccoon), Linux `x86_64`.
- **Ambiente de Desktop**: Shell Curved Glass próprio (GTK4 + Layer-Shell) rodando sobre o Hyprland 0.53 (compositor Wayland), com fallback para o Wayfire.
- **Camada de Empacotamento**: Pacotes Debian `.deb` modulares (`lumen-shell`, `lumen-compositor`, `lumen-system`, `lumen-dev-stack`, `lumen-welcome` e o pacote guarda-chuva `lumen-desktop`) organizados em `/usr/share/lumen-os/`, com pontos de entrada em `/usr/bin/`. Índice de repositório APT local offline para instalação sem rede.
- **Camada do Instalador**: Calamares 3.3.14 (Qt 6 / KF6) configurado com o branding visual Curved Glass (`branding.desc`, `stylesheet.qss`, slideshow de apresentação em QML) e implantação automatizada do ambiente pós-instalação (`lumen-postinstall.sh`).
- **Motor de Geração da ISO**: `debootstrap (minbase)` + `casper 26.04` + `mksquashfs (zstd)` + GRUB 2 unificado (ESP UEFI `efi.img` + MBR híbrido El Torito para BIOS) + `xorriso`.
- **CI / Automação / Validação**: Workflow do GitHub Actions (`build-iso.yml`), executor de VM QEMU multimodo (`test-iso-qemu.sh`) e Guia de Build para o usuário (`docs/BUILD_ISO.md`).

## Inventário de Funcionalidades
| # | Funcionalidade | Descrição | Marco | Origem |
|---|----------------|-----------|-------|--------|
| 1 | Receitas Modulares de Empacotamento .deb | Controle e regras de empacotamento Debian para shell, compositor, system, dev-stack e welcome | M1 | R1 |
| 2 | Metapacote e Aliases Virtuais | Pacote guarda-chuva `lumen-desktop` e pacotes virtuais `distro-*` para resolução limpa de dependências | M1 | R1 |
| 3 | Build Automatizado de .deb e Repositório APT Local | Scripts para compilar os pacotes e gerar o pool APT offline (`Packages.gz`) | M1 | R1 |
| 4 | Configuração Mestre e Fluxo do Calamares | `settings.conf` definindo a sequência de execução, a integração do branding e as etapas fora do chroot | M2 | R2 |
| 5 | Branding Qt6 Curved Glass e Tema QSS | `branding.desc` e `stylesheet.qss` do Qt 6 implementando vidro fosco, bordas especulares e estilo dos CTAs | M2 | R2 |
| 6 | Slideshow de Apresentação QML do Calamares | Apresentação dinâmica em QML mostrando o shell, a stack dev e os recursos do Lumen OS durante a instalação | M2 | R2 |
| 7 | Configuração dos Módulos Principais do Calamares | Configurações de `welcome`, `locale`, `keyboard`, `partition`, `users`, `unpackfs`, `bootloader` | M2 | R2 |
| 8 | Hooks de Pós-Instalação e Wrapper Wayland | `lumen-postinstall.sh`, `launch-calamares.sh` e lançador desktop para a sessão live | M2 | R2 |
| 9 | Script Idempotente de Build da ISO | `scripts/build-iso.sh` com debootstrap minbase, traps de montagem e configuração do usuário live do casper | M3 | R3 |
| 10 | Geração do SquashFS e dos Manifestos do Casper | `mksquashfs` com compressão zstd, `filesystem.manifest` e `filesystem.manifest-remove` | M3 | R3 |
| 11 | Bootloader Duplo Unificado (UEFI + BIOS) | Arquitetura GRUB 2 unificada com `efi.img` (FAT) e imagem MBR El Torito | M3 | R3 |
| 12 | Imagem Mestre Xorriso e Checksum | Comando `xorriso -as mkisofs` gerando ISO-9660 híbrida e checksum sha256 | M3 | R3 |
| 13 | Automação de CI no GitHub Actions | `.github/workflows/build-iso.yml` com limpeza de disco do runner, cache do rootfs e publicação de release | M4 | R4 |
| 14 | Script Automatizado de Teste no QEMU | `scripts/test-iso-qemu.sh` com detecção de KVM/TCG, descoberta do OVMF e disco virtual de teste | M4 | R5 |
| 15 | Guia Completo de Build para o Usuário | `docs/BUILD_ISO.md` cobrindo build nativo no Ubuntu, build sem loop no WSL2, QEMU e gatilhos do CI | M4 | R6 |
| 16 | Suíte de Testes E2E Caixa-Preta | Suíte de testes multinível abrangente verificando empacotamento, Calamares, ISO, CI e QEMU | M5 | Trilha E2E |
| 17 | Endurecimento Adversarial (Tier 5) | Testes adversariais caixa-branca, casos de borda, testes negativos e verificação forense | M5 | Marco Final |

## Marcos
| # | Nome | Escopo | Dependências | Status |
|---|------|--------|--------------|--------|
| 1 | M1: Empacotamento Debian (.deb) | Definições de pacotes, scripts de build, geração do repositório local | nenhuma | CONCLUÍDO |
| 2 | M2: Instalador Calamares e Branding | Configurações, módulos, QSS/QML Curved Glass, hook de pós-instalação | M1 | CONCLUÍDO |
| 3 | M3: Pipeline de Geração da ISO | build-iso.sh idempotente, debootstrap, casper, squashfs, GRUB dual-boot | M1, M2 | EM_ANDAMENTO |
| 4 | M4: CI, QEMU e Documentação do Usuário | Workflow do GitHub Actions, executor de testes QEMU, guia BUILD_ISO.md | M3 | PLANEJADO |
| 5 | M5: Validação E2E e Endurecimento Adversarial | 100% dos testes E2E aprovados (Tiers 1-4) + Tier 5 de Endurecimento Adversarial | M1, M2, M3, M4 | PLANEJADO |

## Contratos de Interface

### M1 ↔ M2 (Empacotamento ↔ Calamares)
- **Raiz de Instalação dos Pacotes**: Todos os componentes próprios do Lumen são instalados em `/usr/share/lumen-os/<módulo>/`.
- **Binários do Sistema**: Wrappers executáveis criados em `/usr/bin/` (`lumen-shell`, `lumen-welcome`, `lumen-session-hyprland`, `lumen-dev-setup`, `lumen-system-tune`).
- **Destino da Pós-Instalação**: O `shellprocess@postinstall` do Calamares invoca `/usr/local/bin/lumen-postinstall.sh` dentro do chroot, copiando as configurações de skeleton para `/etc/skel` e para a home do usuário de destino (`UID 1000`).

### M1/M2 ↔ M3 (Empacotamento/Calamares ↔ Gerador da ISO)
- **Caminho do Repositório Local**: Pacotes locais preparados em `dist/debs/` e indexados via `dpkg-scanpackages` em `/opt/lumen-repo/` ou injetados durante a configuração do chroot.
- **Implantação do Calamares**: Configurações do Calamares instaladas em `/etc/calamares/` e o branding em `/usr/share/calamares/branding/lumen/`.
- **Usuário Live**: O Casper provisiona o usuário live padrão `lumen` (sudo NOPASSWD) com entrada de autostart do Calamares (`launch-calamares.sh`).
- **Manifestos do Sistema de Arquivos**: O Casper gera `/casper/filesystem.manifest` e `/casper/filesystem.manifest-remove` durante o Estágio 4.

### M3 ↔ M4 (Gerador da ISO ↔ CI e QEMU)
- **Artefato ISO de Saída**: ISO gerada estritamente em `dist/lumen-os-26.04-amd64.iso`, com checksum em `dist/lumen-os-26.04-amd64.iso.sha256`.
- **Invocação das Dependências no CI**: `sudo ./scripts/package-debs.sh` seguido de `sudo ./scripts/build-iso.sh`.
- **Invocação do QEMU**: `./scripts/test-iso-qemu.sh [caminho-da-iso]` aceitando `--bios`, `--uefi`, `--ram`, `--smp`, `--headless`.

## Estrutura do Código
```
/home/vandyck/projetos/Distro/
├── packaging/
│   ├── debian/                         # control, rules e specs de instalação Debian
│   ├── templates/                      # Binários, entradas desktop, polkit
│   ├── build-debs.sh                   # Script modular de build dos pacotes
│   └── create-local-repo.sh            # Gerador do Packages.gz
├── installer/
│   └── calamares/
│       ├── settings.conf               # Configuração mestre do Calamares
│       ├── modules/                    # Configurações dos módulos (*.conf)
│       ├── branding/lumen/             # Descritor de branding, QSS, slideshow QML
│       └── scripts/                    # launch-calamares.sh, lumen-postinstall.sh
├── scripts/
│   ├── package-debs.sh                 # Wrapper de conveniência para o empacotamento
│   ├── build-iso.sh                    # Script mestre de geração da ISO
│   └── test-iso-qemu.sh                # Lançador automatizado de testes no QEMU
├── .github/
│   └── workflows/
│       └── build-iso.yml               # Workflow de CI do GitHub Actions
├── docs/
│   └── BUILD_ISO.md                    # Guia prático para o usuário
└── tests/
    └── e2e/                            # Suíte de testes E2E de trilha dupla
```
