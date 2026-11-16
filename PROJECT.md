# Project: Lumen OS — Distro Packaging & ISO Pipeline

## Architecture
- **Distribution Base**: Ubuntu 26.04.1 LTS (Resolute Raccoon), Linux `x86_64`.
- **Desktop Environment**: Custom Curved Glass shell (GTK4 + Layer-Shell) running atop Hyprland 0.53 (Wayland compositor) with Wayfire fallback.
- **Packaging Layer**: Modular Debian `.deb` packages (`lumen-shell`, `lumen-compositor`, `lumen-system`, `lumen-dev-stack`, `lumen-welcome`, and umbrella `lumen-desktop`) structured under `/usr/share/lumen-os/` with entrypoints in `/usr/bin/`. Offline local APT repository index for air-gapped installation.
- **Installer Layer**: Calamares 3.3.14 (Qt 6 / KF6) configured with Curved Glass visual branding (`branding.desc`, `stylesheet.qss`, QML presentation slideshow) and automated post-installation environment deployment (`lumen-postinstall.sh`).
- **ISO Generation Engine**: `debootstrap (minbase)` + `casper 26.04` + `mksquashfs (zstd)` + unified GRUB 2 (UEFI ESP `efi.img` + BIOS El Torito hybrid MBR) + `xorriso`.
- **CI / Automation / Validation**: GitHub Actions workflow (`build-iso.yml`), QEMU multi-mode VM runner (`test-iso-qemu.sh`), and User Build Guide (`docs/BUILD_ISO.md`).

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Modular .deb Packaging Recipes | Debian packaging control and rules for shell, compositor, system, dev-stack, welcome | M1 | R1 |
| 2 | Metapackage & Virtual Aliases | Umbrella `lumen-desktop` and `distro-*` virtual packages for clean dependency resolution | M1 | R1 |
| 3 | Automated .deb Build & Local APT Repo | Scripts to compile packages and generate offline APT pool (`Packages.gz`) | M1 | R1 |
| 4 | Calamares Master Settings & Flow | `settings.conf` defining execution sequence, branding integration, and unchrooted stages | M2 | R2 |
| 5 | Curved Glass Qt6 Branding & QSS Theme | `branding.desc` and Qt 6 `stylesheet.qss` implementing frosted glass, specular borders, and CTA styling | M2 | R2 |
| 6 | Calamares QML Presentation Slideshow | Dynamic QML presentation showcasing Lumen OS shell, dev stack, and features during installation | M2 | R2 |
| 7 | Calamares Core Module Configs | Configs for `welcome`, `locale`, `keyboard`, `partition`, `users`, `unpackfs`, `bootloader` | M2 | R2 |
| 8 | Post-Installation Hooks & Wayland Wrapper | `lumen-postinstall.sh`, `launch-calamares.sh`, and desktop launcher for live session | M2 | R2 |
| 9 | Idempotent ISO Build Script | `scripts/build-iso.sh` with debootstrap minbase, mount traps, casper live user configuration | M3 | R3 |
| 10 | SquashFS & Casper Manifest Generation | `mksquashfs` with zstd compression, `filesystem.manifest` and `filesystem.manifest-remove` | M3 | R3 |
| 11 | Unified Dual Bootloader (UEFI + BIOS) | Unified GRUB 2 architecture with `efi.img` (FAT) and El Torito MBR image | M3 | R3 |
| 12 | Xorriso Master Image & Checksum | `xorriso -as mkisofs` command generating hybrid ISO-9660 and sha256 checksum | M3 | R3 |
| 13 | GitHub Actions CI Automation | `.github/workflows/build-iso.yml` with runner disk cleanup, rootfs cache, and release publishing | M4 | R4 |
| 14 | Automated QEMU Test Script | `scripts/test-iso-qemu.sh` with KVM/TCG detection, OVMF discovery, and virtual test disk | M4 | R5 |
| 15 | Comprehensive User Build Guide | `docs/BUILD_ISO.md` covering native Ubuntu, WSL2 loopless build, QEMU, and CI triggers | M4 | R6 |
| 16 | E2E Opaque-Box Test Suite | Comprehensive multi-tier test suite verifying packaging, Calamares, ISO, CI, and QEMU | M5 | E2E Track |
| 17 | Adversarial Hardening (Tier 5) | White-box adversarial testing, edge cases, negative tests, and forensic verification | M5 | Final Milestone |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| 1 | M1: Debian Packaging (.deb) | Package definitions, build scripts, local repo generation | none | DONE |
| 2 | M2: Calamares Installer & Branding | Settings, modules, Curved Glass QSS/QML, postinstall hook | M1 | DONE |
| 3 | M3: ISO Generation Pipeline | Idempotent build-iso.sh, debootstrap, casper, squashfs, dual-boot GRUB | M1, M2 | IN_PROGRESS |
| 4 | M4: CI, QEMU & User Documentation | GitHub Actions workflow, QEMU test runner, BUILD_ISO.md guide | M3 | PLANNED |
| 5 | M5: E2E Validation & Adversarial Hardening | 100% E2E test pass (Tiers 1-4) + Tier 5 Adversarial Hardening | M1, M2, M3, M4 | PLANNED |

## Interface Contracts

### M1 ↔ M2 (Packaging ↔ Calamares)
- **Package Installation Root**: All Lumen custom components installed into `/usr/share/lumen-os/<module>/`.
- **System Binaries**: Executable wrappers created in `/usr/bin/` (`lumen-shell`, `lumen-welcome`, `lumen-session-hyprland`, `lumen-dev-setup`, `lumen-system-tune`).
- **Post-Install Target**: Calamares `shellprocess@postinstall` invokes `/usr/local/bin/lumen-postinstall.sh` inside chroot, copying skeleton configs to `/etc/skel` and target user home (`UID 1000`).

### M1/M2 ↔ M3 (Packaging/Calamares ↔ ISO Builder)
- **Local Repo Path**: Local packages staged at `dist/debs/` and indexed via `dpkg-scanpackages` to `/opt/lumen-repo/` or injected during chroot setup.
- **Calamares Deployment**: Calamares configurations installed to `/etc/calamares/` and branding to `/usr/share/calamares/branding/lumen/`.
- **Live User**: Casper provisions default live user `lumen` (NOPASSWD sudo) with autostart desktop entry for Calamares (`launch-calamares.sh`).
- **Filesystem Manifests**: Casper generates `/casper/filesystem.manifest` and `/casper/filesystem.manifest-remove` during Stage 4.

### M3 ↔ M4 (ISO Builder ↔ CI & QEMU)
- **Output ISO Artifact**: ISO output strictly at `dist/lumen-os-26.04-amd64.iso` and checksum `dist/lumen-os-26.04-amd64.iso.sha256`.
- **CI Dependency Invocation**: `sudo ./scripts/package-debs.sh` followed by `sudo ./scripts/build-iso.sh`.
- **QEMU Invocation**: `./scripts/test-iso-qemu.sh [path-to-iso]` accepting `--bios`, `--uefi`, `--ram`, `--smp`, `--headless`.

## Code Layout
```
/home/vandyck/projetos/Distro/
├── packaging/
│   ├── debian/                         # Debian control, rules, install specs
│   ├── templates/                      # Binaries, desktop entries, polkit
│   ├── build-debs.sh                   # Modular package build script
│   └── create-local-repo.sh            # Packages.gz generator
├── installer/
│   └── calamares/
│       ├── settings.conf               # Master Calamares configuration
│       ├── modules/                    # Module configs (*.conf)
│       ├── branding/lumen/             # Branding descriptor, QSS, QML slideshow
│       └── scripts/                    # launch-calamares.sh, lumen-postinstall.sh
├── scripts/
│   ├── package-debs.sh                 # Root convenience wrapper for packaging
│   ├── build-iso.sh                    # Master ISO generation script
│   └── test-iso-qemu.sh                # Automated QEMU test launcher
├── .github/
│   └── workflows/
│       └── build-iso.yml               # GitHub Actions CI workflow
├── docs/
│   └── BUILD_ISO.md                    # Practical User Guide
└── tests/
    └── e2e/                            # Dual-Track E2E Test Suite
```
