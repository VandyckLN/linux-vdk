#!/usr/bin/env bash
# ==============================================================================
# Lumen OS E2E — Tier 1: Cobertura de Funcionalidades (tests/e2e/tier1_feature_coverage.sh)
# 30 Testes: 5 testes por área funcional, de F1 a F6
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Carrega o harness comum
source "${SCRIPT_DIR}/harness.sh"

suite_init "Tier 1: Feature Coverage (F1 - F6)"

if [[ -z "${SANDBOX_DIR:-}" ]]; then
    create_test_sandbox "tier1"
    enable_mock_root_tools
    trap "disable_mock_root_tools; cleanup_test_sandbox" EXIT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 130" INT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 1" TERM
fi

# ==============================================================================
# FUNCIONALIDADE F1: Empacotamento .deb Modular (5 testes)
# ==============================================================================

# T1-F1-01: Conformidade dos arquivos control com a RFC 822
test_case_start "T1_F1_01" "Estrutura RFC 822 e metadados dos arquivos control Debian"
control_file="${WORKSPACE_ROOT}/packaging/debian/control"
if [[ -f "$control_file" ]]; then
    assert_contains "$control_file" "Package: lumen-shell" "stanza do pacote lumen-shell é obrigatória"
    assert_contains "$control_file" "Package: lumen-compositor" "stanza do pacote lumen-compositor é obrigatória"
    assert_contains "$control_file" "Package: lumen-system" "stanza do pacote lumen-system é obrigatória"
    assert_contains "$control_file" "Package: lumen-dev-stack" "stanza do pacote lumen-dev-stack é obrigatória"
    assert_contains "$control_file" "Package: lumen-welcome" "stanza do pacote lumen-welcome é obrigatória"
    assert_contains "$control_file" "Package: lumen-desktop" "stanza do metapacote lumen-desktop é obrigatória"
    assert_contains "$control_file" "Architecture:" "Campo Architecture é obrigatório"
    assert_contains "$control_file" "Maintainer:" "Campo Maintainer é obrigatório"
    assert_contains "$control_file" "Description:" "Campo Description é obrigatório"
else
    test_case_skip "packaging/debian/control ainda não existe"
fi
test_case_end

# T1-F1-02: Layout do sistema de arquivos e mapeamento de binários
test_case_start "T1_F1_02" "Especificação dos wrappers binários e do layout do diretório de staging"
templates_dir="${WORKSPACE_ROOT}/packaging/templates"
if [[ -d "$templates_dir" ]]; then
    assert_file_exists "${templates_dir}/lumen-shell" "Template do wrapper lumen-shell é obrigatório"
    assert_file_exists "${templates_dir}/lumen-welcome" "Template do wrapper lumen-welcome é obrigatório"
    assert_file_exists "${templates_dir}/lumen-session-hyprland" "Template lumen-session-hyprland é obrigatório"
    assert_file_exists "${templates_dir}/lumen-dev-setup" "Template lumen-dev-setup é obrigatório"
    assert_file_exists "${templates_dir}/lumen-system-tune" "Template lumen-system-tune é obrigatório"
else
    test_case_skip "packaging/templates ainda não existe"
fi
test_case_end

# T1-F1-03: Script de compilação dos pacotes
test_case_start "T1_F1_03" "Sintaxe e permissão de execução do script modular de build Debian"
build_debs_script="${WORKSPACE_ROOT}/packaging/build-debs.sh"
if [[ -f "$build_debs_script" ]]; then
    assert_file_executable "$build_debs_script" "build-debs.sh deve ser executável"
    assert_syntax_valid "$build_debs_script" "sh"
else
    test_case_skip "packaging/build-debs.sh ainda não existe"
fi
test_case_end

# T1-F1-04: Geração do repositório APT local
test_case_start "T1_F1_04" "Verificação do script indexador do repositório APT local"
repo_script="${WORKSPACE_ROOT}/packaging/create-local-repo.sh"
if [[ -f "$repo_script" ]]; then
    assert_file_executable "$repo_script" "create-local-repo.sh deve ser executável"
    assert_syntax_valid "$repo_script" "sh"
else
    test_case_skip "packaging/create-local-repo.sh ainda não existe"
fi
test_case_end

# T1-F1-05: Wrapper de conveniência do empacotamento
test_case_start "T1_F1_05" "Sintaxe e permissões do script wrapper de empacotamento"
pkg_wrapper="${WORKSPACE_ROOT}/scripts/package-debs.sh"
if [[ -f "$pkg_wrapper" ]]; then
    assert_file_executable "$pkg_wrapper" "package-debs.sh deve ser executável"
    assert_syntax_valid "$pkg_wrapper" "sh"
else
    test_case_skip "scripts/package-debs.sh ainda não existe"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F2: Instalador Calamares e Branding (5 testes)
# ==============================================================================

# T1-F2-01: Estrutura da sequência das configurações mestre
test_case_start "T1_F2_01" "Sequência e definição de branding do settings.conf do Calamares"
settings_file="${WORKSPACE_ROOT}/installer/calamares/settings.conf"
if [[ -f "$settings_file" ]]; then
    assert_syntax_valid "$settings_file" "yaml"
    assert_contains "$settings_file" "branding:[[:space:]]*lumen" "settings.conf deve definir o branding como lumen"
    assert_contains "$settings_file" "welcome" "A sequência do settings deve incluir welcome"
    assert_contains "$settings_file" "partition" "A sequência do settings deve incluir partition"
    assert_contains "$settings_file" "users" "A sequência do settings deve incluir users"
    assert_contains "$settings_file" "unpackfs" "A sequência do settings deve incluir unpackfs"
    assert_contains "$settings_file" "bootloader" "A sequência do settings deve incluir bootloader"
else
    test_case_skip "installer/calamares/settings.conf ainda não existe"
fi
test_case_end

# T1-F2-02: Completude do descritor de branding
test_case_start "T1_F2_02" "Metadados e especificação de apresentação do branding.desc do Calamares"
branding_desc="${WORKSPACE_ROOT}/installer/calamares/branding/lumen/branding.desc"
if [[ -f "$branding_desc" ]]; then
    assert_syntax_valid "$branding_desc" "yaml"
    assert_contains "$branding_desc" "componentName:[[:space:]]*lumen" "componentName deve ser lumen"
    assert_contains "$branding_desc" "Lumen OS" "Product name must contain Lumen OS"
    assert_file_exists "$(dirname "$branding_desc")/stylesheet.qss" "O diretório de branding deve conter stylesheet.qss"
    assert_contains "$branding_desc" "slideshow" "O slideshow deve estar especificado no descritor de branding"
else
    test_case_skip "installer/calamares/branding/lumen/branding.desc ainda não existe"
fi
test_case_end

# T1-F2-03: Estética da folha de estilo Qt6 Curved Glass
test_case_start "T1_F2_03" "Estilo e sintaxe QSS da folha de estilo Qt6 Curved Glass"
qss_file="${WORKSPACE_ROOT}/installer/calamares/branding/lumen/stylesheet.qss"
if [[ -f "$qss_file" ]]; then
    assert_syntax_valid "$qss_file" "css"
    assert_contains "$qss_file" "rgba\(" "O QSS deve conter definições de translucidez rgba"
    assert_contains "$qss_file" "border-radius" "O QSS deve definir border-radius"
    assert_contains "$qss_file" "QPushButton" "O QSS deve estilizar QPushButton"
    assert_contains "$qss_file" "QProgressBar" "O QSS deve estilizar QProgressBar"
else
    test_case_skip "installer/calamares/branding/lumen/stylesheet.qss ainda não existe"
fi
test_case_end

# T1-F2-04: Configurações dos módulos principais
test_case_start "T1_F2_04" "Sintaxe e presença das configurações dos módulos principais do Calamares"
modules_dir="${WORKSPACE_ROOT}/installer/calamares/modules"
if [[ -d "$modules_dir" ]]; then
    assert_file_exists "${modules_dir}/welcome.conf" "welcome.conf deve existir"
    assert_file_exists "${modules_dir}/partition.conf" "partition.conf deve existir"
    assert_file_exists "${modules_dir}/users.conf" "users.conf deve existir"
    assert_file_exists "${modules_dir}/unpackfs.conf" "unpackfs.conf deve existir"
    assert_file_exists "${modules_dir}/bootloader.conf" "bootloader.conf deve existir"
    assert_syntax_valid "${modules_dir}/welcome.conf" "yaml"
    assert_syntax_valid "${modules_dir}/users.conf" "yaml"
else
    test_case_skip "Diretório installer/calamares/modules ainda não existe"
fi
test_case_end

# T1-F2-05: Pós-instalação e wrapper Wayland
test_case_start "T1_F2_05" "Hook de pós-instalação do Calamares e script de lançamento no Wayland"
postinstall="${WORKSPACE_ROOT}/installer/calamares/scripts/lumen-postinstall.sh"
launcher="${WORKSPACE_ROOT}/installer/calamares/scripts/launch-calamares.sh"
if [[ -f "$postinstall" && -f "$launcher" ]]; then
    assert_file_executable "$postinstall" "lumen-postinstall.sh deve ser executável"
    assert_file_executable "$launcher" "launch-calamares.sh deve ser executável"
    assert_syntax_valid "$postinstall" "sh"
    assert_syntax_valid "$launcher" "sh"
    assert_contains "$launcher" "QT_QPA_PLATFORM" "O script de lançamento deve configurar a plataforma Qt"
    assert_contains "$postinstall" "skel" "O hook de pós-instalação deve configurar o perfil skeleton"
else
    test_case_skip "Scripts do Calamares ainda não existem"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F3: Pipeline de Geração da ISO (5 testes)
# ==============================================================================

# T1-F3-01: Sintaxe e modo estrito do script de build da ISO
test_case_start "T1_F3_01" "Sintaxe e configurações de segurança estritas do script de build da ISO"
build_iso_script="${WORKSPACE_ROOT}/scripts/build-iso.sh"
if [[ -f "$build_iso_script" ]]; then
    assert_file_executable "$build_iso_script" "build-iso.sh deve ser executável"
    assert_syntax_valid "$build_iso_script" "sh"
    assert_contains "$build_iso_script" "set -e" "build-iso.sh deve operar com tratamento de erros estrito"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end

# T1-F3-02: Debootstrap minbase e definição de mirror
test_case_start "T1_F3_02" "Configuração do debootstrap minbase e definições de mirror"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "debootstrap" "build-iso.sh deve invocar o debootstrap"
    assert_contains "$build_iso_script" "minbase" "build-iso.sh deve especificar a variante minbase"
    assert_contains "$build_iso_script" "amd64" "build-iso.sh deve ter como alvo a arquitetura amd64"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end

# T1-F3-03: Manifestos do Casper e configuração do usuário live
test_case_start "T1_F3_03" "Usuário da sessão live do Casper e geração do manifesto de pacotes"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "filesystem.manifest" "build-iso.sh deve gerar os manifestos do sistema de arquivos"
    assert_contains "$build_iso_script" "lumen" "build-iso.sh deve configurar o usuário live lumen"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end

# T1-F3-04: Especificação da compressão Zstandard do SquashFS
test_case_start "T1_F3_04" "Parâmetros de compressão zstd e tamanho de bloco do SquashFS"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "mksquashfs" "build-iso.sh deve chamar o mksquashfs"
    assert_contains "$build_iso_script" "zstd" "build-iso.sh deve especificar a compressão zstd"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end

# T1-F3-05: Bootloader duplo e comando do xorriso
test_case_start "T1_F3_05" "Comandos de masterização do bootloader duplo UEFI e BIOS legado"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "xorriso" "build-iso.sh deve invocar o xorriso"
    assert_contains "$build_iso_script" "mkisofs" "build-iso.sh deve usar a emulação mkisofs"
    assert_contains "$build_iso_script" "sha256" "build-iso.sh deve calcular o checksum sha256"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F4: Automação de CI no GitHub Actions (5 testes)
# ==============================================================================

# T1-F4-01: Sintaxe e gatilhos do workflow de CI
test_case_start "T1_F4_01" "Sintaxe YAML e gatilhos de execução do workflow do GitHub Actions"
workflow_file="${WORKSPACE_ROOT}/.github/workflows/build-iso.yml"
if [[ -f "$workflow_file" ]]; then
    assert_syntax_valid "$workflow_file" "yaml"
    assert_contains "$workflow_file" "workflow_dispatch" "O CI deve suportar o gatilho workflow_dispatch"
    assert_contains "$workflow_file" "push" "O CI deve ser disparado no push"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end

# T1-F4-02: Etapa de limpeza de disco do runner
test_case_start "T1_F4_02" "Comandos de recuperação de espaço em disco do runner no workflow de CI"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "Free disk space|Disk space|cleanup|rm -rf" "O CI deve incluir uma etapa de limpeza de disco"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end

# T1-F4-03: Etapa de instalação das dependências do host
test_case_start "T1_F4_03" "Etapa de instalação das dependências de build do host no workflow de CI"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "debootstrap" "O CI deve instalar o debootstrap"
    assert_contains "$workflow_file" "xorriso" "O CI deve instalar o xorriso"
    assert_contains "$workflow_file" "squashfs-tools" "O CI deve instalar o squashfs-tools"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end

# T1-F4-04: Sequência de execução dos scripts de build
test_case_start "T1_F4_04" "A execução do script de empacotamento precede o script de build da ISO no CI"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "package-debs.sh|build-debs.sh" "O CI deve executar o empacotamento"
    assert_contains "$workflow_file" "build-iso.sh" "O CI deve executar o build-iso.sh"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end

# T1-F4-05: Especificação do upload de artefatos
test_case_start "T1_F4_05" "Configuração do upload de artefatos do CI com a ISO e o checksum"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "upload-artifact" "O CI deve usar a action upload-artifact"
    assert_contains "$workflow_file" "lumen-os-26.04-amd64.iso" "CI artifact upload must target ISO file"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F5: Script e Executor de Testes QEMU (5 testes)
# ==============================================================================

# T1-F5-01: Sintaxe e saída de ajuda do executor QEMU
test_case_start "T1_F5_01" "Sintaxe e opção de ajuda da CLI do script de testes QEMU"
qemu_script="${WORKSPACE_ROOT}/scripts/test-iso-qemu.sh"
if [[ -f "$qemu_script" ]]; then
    assert_file_executable "$qemu_script" "test-iso-qemu.sh deve ser executável"
    assert_syntax_valid "$qemu_script" "sh"
    assert_exit_code 0 bash "$qemu_script" --help
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end

# T1-F5-02: Parsing da flag de boot UEFI
test_case_start "T1_F5_02" "Modo de boot UEFI e suporte ao firmware OVMF no executor QEMU"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "uefi" "O script QEMU deve suportar --uefi"
    assert_contains "$qemu_script" "OVMF" "O script QEMU deve referenciar o firmware OVMF"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end

# T1-F5-03: Execução no modo de boot BIOS legado
test_case_start "T1_F5_03" "Suporte ao modo de boot BIOS legado no executor QEMU"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "bios" "O script QEMU deve suportar --bios"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end

# T1-F5-04: Modo headless e alocação de recursos
test_case_start "T1_F5_04" "Flags de exibição headless e de alocação de RAM/SMP no executor QEMU"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "headless" "O script QEMU deve suportar --headless"
    assert_contains "$qemu_script" "ram" "O script QEMU deve suportar --ram"
    assert_contains "$qemu_script" "smp" "O script QEMU deve suportar --smp"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end

# T1-F5-05: Detecção de KVM e fallback para TCG
test_case_start "T1_F5_05" "Verificação de virtualização por hardware (KVM) com fallback para TCG em software"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "/dev/kvm" "O script QEMU deve verificar /dev/kvm"
    assert_contains "$qemu_script" "tcg" "O script QEMU deve suportar o fallback tcg"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F6: Guia Prático de Build para o Usuário (5 testes)
# ==============================================================================

# T1-F6-01: Presença e estrutura do guia do usuário
test_case_start "T1_F6_01" "Presença da documentação de build do usuário e seções estruturais principais"
guide_file="${WORKSPACE_ROOT}/docs/BUILD_ISO.md"
if [[ -f "$guide_file" ]]; then
    assert_file_not_empty "$guide_file" "BUILD_ISO.md não pode estar vazio"
    assert_contains "$guide_file" "Prerequisite|Requirements" "A documentação deve cobrir os pré-requisitos"
    assert_contains "$guide_file" "WSL2" "A documentação deve cobrir o WSL2"
    assert_contains "$guide_file" "GitHub Actions" "A documentação deve cobrir o GitHub Actions"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# T1-F6-02: Comando de pacotes de pré-requisito
test_case_start "T1_F6_02" "Pré-requisitos de pacotes do sistema host documentados no guia de build"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "debootstrap" "A documentação deve listar o pré-requisito debootstrap"
    assert_contains "$guide_file" "xorriso" "A documentação deve listar o pré-requisito xorriso"
    assert_contains "$guide_file" "squashfs-tools" "A documentação deve listar o pré-requisito squashfs-tools"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# T1-F6-03: Orientações de build sem loop no WSL2
test_case_start "T1_F6_03" "Orientações para o ambiente WSL2 e restrições de loop device"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "loop|WSL" "A documentação deve explicar o tratamento de loop device no WSL2"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# T1-F6-04: Consistência dos trechos executáveis
test_case_start "T1_F6_04" "Os comandos documentados correspondem aos pontos de entrada dos scripts do projeto"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "build-iso.sh" "A documentação deve referenciar o build-iso.sh"
    assert_contains "$guide_file" "package-debs.sh" "A documentação deve referenciar o package-debs.sh"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# T1-F6-05: Guia de verificação do checksum
test_case_start "T1_F6_05" "Instruções de verificação do checksum SHA256 da imagem ISO na documentação"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "sha256sum" "A documentação deve explicar a verificação com sha256sum"
    assert_contains "$guide_file" "lumen-os-26.04-amd64.iso" "Docs must document ISO artifact name"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# ==============================================================================
# FUNCIONALIDADE F7: Elevação de Privilégios
# ==============================================================================

# T1-F7-01: Helper de root
test_case_start "T1_F7_01" "Helper de root existe, é executável e tem sintaxe bash válida"
helper="${WORKSPACE_ROOT}/system/lumen-root-helper"
assert_file_executable "$helper"
assert_syntax_valid "$helper" "sh"
test_case_end

# T1-F7-02: Lista de pacotes permitidos
test_case_start "T1_F7_02" "Lista de pacotes permitidos existe e não está vazia"
assert_file_not_empty "${WORKSPACE_ROOT}/system/root-helper/allowed-packages.list"
test_case_end

# T1-F7-03: Biblioteca de elevação
test_case_start "T1_F7_03" "elevate.sh existe e tem sintaxe bash válida"
assert_file_exists "${WORKSPACE_ROOT}/system/lib/elevate.sh"
assert_syntax_valid "${WORKSPACE_ROOT}/system/lib/elevate.sh" "sh"
test_case_end

# T1-F7-04: Policy do polkit
test_case_start "T1_F7_04" "Policy do polkit é XML válido e autoriza o lumen-root-helper"
policy_file="${WORKSPACE_ROOT}/packaging/templates/dev.lumenos.root-helper.policy"
policy_out="$(python3 -I -c '
import sys
import xml.etree.ElementTree as ET

action = ET.parse(sys.argv[1]).getroot().find("action[@id=\"dev.lumenos.root-helper\"]")
if action is None:
    print("ação dev.lumenos.root-helper ausente")
    sys.exit(1)
annotes = {a.get("key"): (a.text or "").strip() for a in action.findall("annotate")}
defaults = {d.tag: (d.text or "").strip() for d in action.find("defaults")}
print(annotes.get("org.freedesktop.policykit.exec.path"))
print(annotes.get("org.freedesktop.policykit.exec.allow_gui"))
print(defaults.get("allow_active"))
' "$policy_file" 2>&1)"
assert_eq "/usr/bin/lumen-root-helper
true
auth_admin_keep" "$policy_out" "A policy deve apontar para o helper, permitir GUI e usar auth_admin_keep"
assert_file_not_exists "${WORKSPACE_ROOT}/packaging/templates/dev.lumenos.welcome.policy" "A policy antiga do lumen-welcome não deve mais existir"
test_case_end

# ==============================================================================
# FUNCIONALIDADE F8: Interface do Shell e do Welcome
# ==============================================================================

# T1-F8-01: Botões de vidro zeram o background-image do tema
# O tema padrão do GTK4 pinta botões com background-image claro; se a regra só
# define background-color, o branco do tema cobre o vidro e o texto some.
test_case_start "T1_F8_01" "Regras de botão de vidro zeram o background-image do tema GTK"
css_out="$(python3 -I - "${WORKSPACE_ROOT}/shell/styles/curved_glass.css" "${WORKSPACE_ROOT}/welcome/welcome_window.py" <<'PY' 2>&1
import re
import sys

shell_css = open(sys.argv[1], encoding="utf-8").read()
welcome_src = open(sys.argv[2], encoding="utf-8").read()
extra = re.search(r'EXTRA_CSS = b"""(.*?)"""', welcome_src, re.S)
css = shell_css + "\n" + (extra.group(1) if extra else "")
css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)

rules = {}
for selector, body in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
    for sel in selector.split(","):
        rules.setdefault(sel.strip(), []).append(body)

problems = []
for cls in (".icon-btn", ".nav-item", ".sub-item", ".orientation-pill", ".choice-card"):
    bodies = rules.get(cls)
    if not bodies:
        problems.append(f"{cls}: regra base ausente")
        continue
    joined = " ".join(bodies)
    if not re.search(r"background-image\s*:", joined):
        problems.append(f"{cls}: background-color sem zerar background-image")
print("\n".join(problems) or "ok")
PY
)"
assert_eq "ok" "$css_out" "Toda regra base de botão de vidro deve definir background-image"
test_case_end

# T1-F8-02: Barra reserva espaço na tela
test_case_start "T1_F8_02" "Config padrão reserva a zona exclusiva da barra (não cobre as janelas)"
zone="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["bar"]["exclusive_zone"])' "${WORKSPACE_ROOT}/config/shell.default.json" 2>&1)"
assert_eq "True" "$zone" "bar.exclusive_zone deve ser true por padrão"
test_case_end

# T1-F8-03: Nome do perfil vem do usuário do sistema
test_case_start "T1_F8_03" "Perfil mostra o usuário real quando a config não define um nome"
name_out="$(cd "$WORKSPACE_ROOT" && python3 -c '
import json, os, pwd
from shell.config_store import display_name
entry = pwd.getpwuid(os.getuid())
esperado = entry.pw_gecos.split(",")[0].strip() or entry.pw_name
padrao = json.load(open("config/shell.default.json"))["user"]
print(padrao.get("name", "") == "")
print(display_name({}) == esperado)
print(display_name({"name": "   "}) == esperado)
print(display_name({"name": "Ana Dev"}))
' 2>&1)"
assert_eq "True
True
True
Ana Dev" "$name_out" "Sem nome configurado, o perfil deve usar o nome real do usuário"
test_case_end

# T1-F8-04: Botões do welcome sempre visíveis
test_case_start "T1_F8_04" "Botões Fechar/Aplicar do welcome ficam fora da área de rolagem"
layout_out="$(python3 -I - "${WORKSPACE_ROOT}/welcome/welcome_window.py" <<'PY' 2>&1
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read()
build = src.split("def _build_ui", 1)[1].split("\n    def ", 1)[0]
checks = {
    "conteúdo rolável dentro do card": re.search(r"card\.append\(scroll\)", build),
    "ações fixas no card": re.search(r"card\.append\(actions\)", build),
    "ações não ficam no conteúdo rolável": not re.search(r"content\.append\(actions\)", build),
}
print("\n".join(k for k, ok in checks.items() if not ok) or "ok")
PY
)"
assert_eq "ok" "$layout_out" "A linha de ações deve ficar fora do ScrolledWindow"
test_case_end

# T1-F8-06: Texto legível no card selecionado
# O card selecionado tem fundo claro; os rótulos internos têm classes próprias com
# cor branca, então precisam de uma regra escura específica para o estado selecionado.
test_case_start "T1_F8_06" "Rótulos do card selecionado do welcome usam cor escura"
sel_out="$(python3 -I - "${WORKSPACE_ROOT}/welcome/welcome_window.py" <<'PY' 2>&1
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read()
css = re.search(r'EXTRA_CSS = b"""(.*?)"""', src, re.S).group(1)
faltando = []
for label in (".profile-name", ".profile-subtitle"):
    m = re.search(r"\.choice-card\.selected\s+" + re.escape(label) + r"[^{]*\{([^}]*)\}", css)
    if not m or not re.search(r"color:\s*(#1|rgba\(\s*2[0-9],)", m.group(1)):
        faltando.append(label)
print("\n".join(faltando) or "ok")
PY
)"
assert_eq "ok" "$sel_out" "Rótulos dentro do .choice-card.selected precisam de cor escura"
test_case_end

# T1-F8-07: Módulos Python do shell e do welcome compilam
test_case_start "T1_F8_07" "Todos os módulos Python do shell e do welcome compilam"
while IFS= read -r py_file; do
    assert_syntax_valid "$py_file" "py"
done < <(find "${WORKSPACE_ROOT}/shell" "${WORKSPACE_ROOT}/welcome" -name '*.py' -not -path '*/__pycache__/*' | sort)
test_case_end

# T1-F8-05: Textos com acentuação correta
test_case_start "T1_F8_05" "Textos visíveis do welcome usam acentuação correta"
assert_not_contains "$(cat "${WORKSPACE_ROOT}/welcome/stack_installer.py")" "Repositorio" "Escreva 'Repositório' com acento"
test_case_end

# ==============================================================================
# FUNCIONALIDADE F9: Mandacaru (EDR) por padrão
# ==============================================================================

# T1-F9-01
test_case_start "T1_F9_01" "mandacaru.lock fixa versão, URL https e SHA256"
lock="${WORKSPACE_ROOT}/packaging/third-party/mandacaru.lock"
assert_contains "$lock" "^MANDACARU_VERSION=0\.2\.0$" "Versão fixada em 0.2.0"
assert_contains "$lock" "^MANDACARU_URL=https://github\.com/VandyckLN/mandacaru/releases/download/v0\.2\.0/mandacaru_0\.2\.0_all\.deb$" "URL https da release v0.2.0"
assert_contains "$lock" "^MANDACARU_SHA256=[0-9a-f]{64}$" "SHA256 com 64 caracteres hex"
assert_contains "$lock" "^MANDACARU_SHA256=3942e8e764005c18458c26985c940c7e5c081e4c896e00be18fcf09becbc90bf$" "SHA256 da release v0.2.0"
test_case_end

# T1-F9-02
test_case_start "T1_F9_02" "fetch-third-party.sh existe, é executável e tem sintaxe bash válida"
assert_file_executable "${WORKSPACE_ROOT}/packaging/fetch-third-party.sh"
assert_syntax_valid "${WORKSPACE_ROOT}/packaging/fetch-third-party.sh" "sh"
assert_contains "${WORKSPACE_ROOT}/packaging/fetch-third-party.sh" "set -euo pipefail" "Modo estrito obrigatório"
test_case_end

# ==============================================================================
# FUNCIONALIDADE F10: Vigia do Mandacaru (lumen-edr-notify)
# ==============================================================================

# T1-F10-01
test_case_start "T1_F10_01" "Lançador lumen-edr-notify é executável e chama o módulo do vigia"
launcher="${WORKSPACE_ROOT}/packaging/templates/lumen-edr-notify"
assert_file_executable "$launcher"
assert_syntax_valid "$launcher" "sh"
assert_contains "$launcher" "exec /usr/bin/python3 -m shell\.edr_notify" "Chama python3 -m shell.edr_notify"
test_case_end

# T1-F10-02
test_case_start "T1_F10_02" "shell.default.json traz a seção edr com os padrões da spec"
assert_exit_code 0 python3 -c '
import json, sys
e = json.load(open(sys.argv[1]))["edr"]
assert e == {"socket": "/run/mandacaru/alerts.sock", "notify_min_severity": "MEDIUM", "sound": True}, e
' "${WORKSPACE_ROOT}/config/shell.default.json"
test_case_end

# T1-F10-03
test_case_start "T1_F10_03" "Severidade inválida na config cai para MEDIUM"
assert_exit_code 0 python3 -c '
import sys
sys.path.insert(0, sys.argv[1])
from shell.edr_notify import load_settings
sock, sev, som = load_settings({"edr": {"notify_min_severity": "pânico"}})
assert (sock, sev, som) == ("/run/mandacaru/alerts.sock", "MEDIUM", True), (sock, sev, som)
' "${WORKSPACE_ROOT}"
test_case_end

# Finaliza a suíte
suite_finish
