#!/usr/bin/env bash
# ==============================================================================
# Lumen OS E2E — Tier 3: Integração Entre Funcionalidades (tests/e2e/tier3_cross_feature.sh)
# 6 testes de integração par a par validando contratos arquiteturais bilaterais
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Carrega o harness comum
source "${SCRIPT_DIR}/harness.sh"

suite_init "Tier 3: Cross-Feature Integration (Pairwise)"

if [[ -z "${SANDBOX_DIR:-}" ]]; then
    create_test_sandbox "tier3"
    enable_mock_root_tools
    trap "disable_mock_root_tools; cleanup_test_sandbox" EXIT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 130" INT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 1" TERM
fi

# ------------------------------------------------------------------------------
# Par 1: Alinhamento Empacotamento (F1) <-> Calamares (F2)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR1_PACKAGING_CALAMARES" "Os binários empacotados se alinham ao autostart live e ao hook de pós-instalação do Calamares"
postinstall_script="${WORKSPACE_ROOT}/installer/calamares/scripts/lumen-postinstall.sh"
launch_script="${WORKSPACE_ROOT}/installer/calamares/scripts/launch-calamares.sh"
control_file="${WORKSPACE_ROOT}/packaging/debian/control"
templates_dir="${WORKSPACE_ROOT}/packaging/templates"

if [[ -f "$postinstall_script" && -f "$launch_script" && -f "$control_file" ]]; then
    # 1. Verifica os binários e o ambiente no launch-calamares.sh
    assert_contains "$launch_script" "calamares" "O script de lançamento deve invocar o calamares"
    assert_contains "$launch_script" "WAYLAND_DISPLAY" "O script de lançamento deve tratar o display Wayland"
    assert_contains "$launch_script" "QT_QPA_PLATFORM" "O script de lançamento deve configurar a plataforma Qt Wayland"

    # 2. Verifica se o hook de pós-instalação se alinha aos caminhos empacotados e à estrutura de usuário
    assert_contains "$postinstall_script" "skel" "O hook de pós-instalação deve configurar o /etc/skel"
    assert_contains "$postinstall_script" "1000" "O hook de pós-instalação deve ter como alvo o usuário UID 1000"

    # 3. Verifica se os pacotes declaram os componentes Lumen esperados
    assert_contains "$control_file" "Package: lumen-shell" "O arquivo control deve declarar lumen-shell"
    assert_contains "$control_file" "Package: lumen-compositor" "O arquivo control deve declarar lumen-compositor"
    assert_contains "$control_file" "Package: lumen-system" "O arquivo control deve declarar lumen-system"
    assert_contains "$control_file" "Package: lumen-dev-stack" "O arquivo control deve declarar lumen-dev-stack"
    assert_contains "$control_file" "Package: lumen-welcome" "O arquivo control deve declarar lumen-welcome"
    assert_contains "$control_file" "Package: lumen-desktop" "O arquivo control deve declarar lumen-desktop"

    # 4. Verifica se os templates fornecem os pontos de entrada de runtime necessários
    if [[ -d "$templates_dir" ]]; then
        assert_file_exists "${templates_dir}/lumen-shell" "Template do ponto de entrada lumen-shell é obrigatório"
        assert_file_exists "${templates_dir}/lumen-session-hyprland" "Ponto de entrada da sessão hyprland é obrigatório"
        assert_file_exists "${templates_dir}/lumen-system-tune" "Ponto de entrada de ajuste do sistema é obrigatório"
    fi
else
    test_case_skip "Arquivos do Calamares ou de empacotamento pendentes"
fi
test_case_end


# ------------------------------------------------------------------------------
# Par 2: Empacotamento/Calamares (F1/F2) <-> Gerador da ISO (F3)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR2_PACKAGING_CALAMARES_ISO_BUILDER" "Pool do repositório local e configurações do Calamares preparados no sistema de arquivos da ISO"
build_iso_script="${WORKSPACE_ROOT}/scripts/build-iso.sh"

if [[ -f "$build_iso_script" ]]; then
    # 1. Ingestão do repositório local no gerador da ISO
    assert_contains "$build_iso_script" "debs" "O gerador da ISO deve preparar os debs dos pacotes locais"
    assert_contains "$build_iso_script" "lumen-desktop" "O gerador da ISO deve instalar o metapacote lumen-desktop"

    # 2. Preparação das configurações e do branding do Calamares
    assert_contains "$build_iso_script" "calamares" "O gerador da ISO deve preparar as configurações do Calamares"
    assert_contains "$build_iso_script" "branding" "O gerador da ISO deve preparar o branding do Calamares"
    assert_contains "$build_iso_script" "lumen-postinstall.sh" "O gerador da ISO deve preparar o script de pós-instalação"

    # 3. Preparação do autostart live do Casper
    assert_contains "$build_iso_script" "launch-calamares.sh" "O gerador da ISO deve preparar o lançador de autostart live"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end


# ------------------------------------------------------------------------------
# Par 3: Gerador da ISO (F3) <-> Automação de CI (F4)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR3_ISO_BUILDER_CI_WORKFLOW" "Etapas, dependências e artefatos do workflow de CI se alinham ao pipeline de build da ISO"
workflow_file="${WORKSPACE_ROOT}/.github/workflows/build-iso.yml"

if [[ -f "$workflow_file" ]]; then
    # 1. Gatilhos do workflow
    assert_contains "$workflow_file" "workflow_dispatch" "O CI deve suportar o gatilho manual"

    # 2. Invocações sequenciais das etapas de build
    assert_contains "$workflow_file" "package-debs.sh|build-debs.sh" "O CI deve executar o empacotamento"
    assert_contains "$workflow_file" "build-iso.sh" "O CI deve executar o build-iso.sh"

    # 3. Instalação das dependências
    assert_contains "$workflow_file" "debootstrap" "O CI deve instalar o debootstrap"
    assert_contains "$workflow_file" "xorriso" "O CI deve instalar o xorriso"
    assert_contains "$workflow_file" "squashfs-tools" "O CI deve instalar o squashfs-tools"

    # 4. Contrato de saída de artefatos e checksum
    assert_contains "$workflow_file" "lumen-os-26.04-amd64.iso" "CI artifact upload must target ISO output"
    assert_contains "$workflow_file" "upload-artifact" "O CI deve publicar o artefato da ISO"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end


# ------------------------------------------------------------------------------
# Par 4: Gerador da ISO (F3) <-> Executor QEMU (F5)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR4_ISO_BUILDER_QEMU_RUNNER" "O executor QEMU valida o caminho padrão da ISO, o dual boot UEFI/BIOS e o disco de teste"
qemu_script="${WORKSPACE_ROOT}/scripts/test-iso-qemu.sh"

if [[ -f "$qemu_script" ]]; then
    # 1. Concordância do caminho padrão da ISO
    assert_contains "$qemu_script" "lumen-os-26.04-amd64.iso" "A ISO padrão do executor QEMU deve corresponder à saída do build-iso.sh"

    # 2. Suporte a dual boot
    assert_contains "$qemu_script" "uefi" "O executor QEMU deve suportar boot --uefi"
    assert_contains "$qemu_script" "bios" "O executor QEMU deve suportar boot --bios"
    assert_contains "$qemu_script" "OVMF" "O executor QEMU deve suportar o firmware OVMF"

    # 3. Provisionamento do disco de teste para testar o instalador
    assert_contains "$qemu_script" "qemu-img|create-disk|drive" "O executor QEMU deve suportar o provisionamento de disco de teste"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end


# ------------------------------------------------------------------------------
# Par 5: Empacotamento/ISO (F1/F3) <-> Documentação (F6)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR5_PACKAGING_ISO_DOCUMENTATION" "A documentação do usuário referencia caminhos, flags e saídas reais dos scripts"
doc_file="${WORKSPACE_ROOT}/docs/BUILD_ISO.md"

if [[ -f "$doc_file" ]]; then
    # 1. Consistência dos caminhos de scripts na documentação
    assert_contains "$doc_file" "package-debs.sh" "A documentação deve referenciar o package-debs.sh"
    assert_contains "$doc_file" "build-iso.sh" "A documentação deve referenciar o build-iso.sh"
    assert_contains "$doc_file" "test-iso-qemu.sh" "A documentação deve referenciar o test-iso-qemu.sh"

    # 2. Completude dos pré-requisitos
    assert_contains "$doc_file" "debootstrap" "A documentação deve listar o pré-requisito debootstrap"
    assert_contains "$doc_file" "squashfs-tools" "A documentação deve listar o pré-requisito squashfs-tools"
    assert_contains "$doc_file" "xorriso" "A documentação deve listar o pré-requisito xorriso"

    # 3. Correspondência do caminho de saída
    assert_contains "$doc_file" "lumen-os-26.04-amd64.iso" "A documentação deve informar o nome de arquivo correto da ISO"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end


# ------------------------------------------------------------------------------
# Par 6: Calamares (F2) <-> Executor QEMU (F5)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR6_CALAMARES_QEMU_ENVIRONMENT" "O executor QEMU fornece gráficos virtuais para Wayland, RAM suficiente e modo headless"
if [[ -f "$qemu_script" ]]; then
    # 1. Parâmetro de alocação de RAM
    assert_contains "$qemu_script" "ram" "O executor QEMU deve suportar o parâmetro de RAM"

    # 2. Suporte a gráficos virtuais para Wayland / KMS
    assert_contains "$qemu_script" "virtio|vga|gpu" "O executor QEMU deve configurar o adaptador gráfico"

    # 3. Suporte a headless para testes automatizados no CI
    assert_contains "$qemu_script" "headless" "O executor QEMU deve suportar a flag --headless"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end

# ==============================================================================
# FUNCIONALIDADE F7: Elevação de Privilégios
# ==============================================================================

test_case_start "T3_PAIR7_SCRIPTS_SEM_SUDO_DIRETO" "Scripts de setup não chamam sudo diretamente"
for script in "${WORKSPACE_ROOT}/system/apply-system-tuning.sh" "${WORKSPACE_ROOT}/dev-stack/setup-dev-env.sh"; do
    assert_not_contains "$script" '(^|[^_[:alnum:]])sudo[[:space:]]' "O script não deve chamar sudo diretamente (use as_root)"
    assert_contains "$script" "system/lib/elevate.sh" "O script deve carregar a biblioteca elevate.sh"
done
test_case_end

test_case_start "T3_PAIR7_PACOTES_NA_LISTA_PERMITIDA" "Todo pacote instalado pelos scripts consta na lista permitida"
missing_out="$(python3 -I - "${WORKSPACE_ROOT}/dev-stack/setup-dev-env.sh" "${WORKSPACE_ROOT}/dev-stack/packages.list" "${WORKSPACE_ROOT}/system/root-helper/allowed-packages.list" <<'PYEOF' 2>&1
import shlex
import sys

setup_path, packages_path, allowed_path = sys.argv[1:4]


def read_list(path):
    items = set()
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.replace("\r", "").strip()
            if line and not line.startswith("#"):
                items.add(line)
    return items


wanted = read_list(packages_path)
with open(setup_path, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.replace("\r", "").strip()
        if "as_root apt-install" not in line:
            continue
        tokens = shlex.split(line, comments=True)
        idx = tokens.index("apt-install")
        for tok in tokens[idx + 1:]:
            if tok.startswith("$") or tok.startswith('"$') or "${" in tok:
                continue
            wanted.add(tok)

missing = sorted(wanted - read_list(allowed_path))
if missing:
    print("fora da lista permitida: " + " ".join(missing))
    sys.exit(1)
PYEOF
)"
missing_status=$?
assert_eq 0 "$missing_status" "Pacotes ausentes de allowed-packages.list -> ${missing_out}"
test_case_end

test_case_start "T3_PAIR7_ASSISTENTE_DEFINE_PKEXEC" "O assistente executa os scripts com LUMEN_ELEVATE=pkexec"
elev_out="$(WORKSPACE_ROOT="$WORKSPACE_ROOT" python3 -I -c '
import os
import sys

os.environ.pop("LUMEN_ELEVATE", None)
sys.path.insert(0, os.environ["WORKSPACE_ROOT"])
from welcome.stack_installer import run_commands

out = []
run_commands([["bash", "-c", "echo ELEV=$LUMEN_ELEVATE"]], out.append)
print("\n".join(out))
' 2>&1)"
assert_contains "$elev_out" "ELEV=pkexec" "run_commands deve exportar LUMEN_ELEVATE=pkexec para o comando"
test_case_end

test_case_start "T3_PAIR7_DEPENDS_SINCRONIZADOS" "Os Depends do control e do build-debs.sh são iguais"
deps_out="$(python3 -I - "${WORKSPACE_ROOT}/packaging/debian/control" "${WORKSPACE_ROOT}/packaging/build-debs.sh" <<'PYEOF' 2>&1
import re
import sys

control_path, build_path = sys.argv[1:3]
VERSION = "1.0.0-1ubuntu1"


def norm(text):
    return sorted(p.strip() for p in text.split(",") if p.strip())


control = {}
with open(control_path, encoding="utf-8") as fh:
    stanzas = fh.read().replace("\r", "").split("\n\n")
for stanza in stanzas:
    name = re.search(r"^Package: (\S+)", stanza, re.M)
    dep = re.search(r"^Depends:(.*(?:\n[ \t].*)*)", stanza, re.M)
    if name and dep:
        items = [d for d in norm(dep.group(1).replace("\n", " ")) if d != "${misc:Depends}"]
        control[name.group(1)] = items

build = {}
with open(build_path, encoding="utf-8") as fh:
    text = fh.read().replace("\r", "")
for block in re.findall(r'cat <<EOF > "\$stage_dir/DEBIAN/control"\n(.*?)\nEOF', text, re.S):
    name = re.search(r"^Package: (\S+)", block, re.M)
    dep = re.search(r"^Depends: (.*)$", block, re.M)
    if name and dep:
        build[name.group(1)] = norm(dep.group(1).replace("$VERSION", VERSION))

errors = []
for pkg in sorted(set(control) | set(build)):
    if control.get(pkg) != build.get(pkg):
        errors.append("%s: control=%s build-debs=%s" % (pkg, control.get(pkg), build.get(pkg)))


def need(pkg, dep):
    if dep not in build.get(pkg, []) or dep not in control.get(pkg, []):
        errors.append("%s deve depender de %s" % (pkg, dep))


need("lumen-system", "pkexec")
need("lumen-system", "polkitd")
need("lumen-dev-stack", "lumen-system (= %s)" % VERSION)
need("lumen-compositor", "hyprpolkitagent")

if errors:
    print("\n".join(errors))
    sys.exit(1)
PYEOF
)"
deps_status=$?
assert_eq 0 "$deps_status" "Depends divergentes -> ${deps_out}"
test_case_end

test_case_start "T3_PAIR7_SESSOES_INICIAM_AGENTE_POLKIT" "As sessões Hyprland e Wayfire iniciam o agente do polkit"
assert_contains "${WORKSPACE_ROOT}/compositor/hyprland/hyprland.conf" "^exec-once[[:space:]]*=[[:space:]]*/usr/libexec/hyprpolkitagent" "O hyprland.conf do compositor deve iniciar o hyprpolkitagent"
assert_contains "${WORKSPACE_ROOT}/packaging/templates/hyprland.conf" "^exec-once[[:space:]]*=[[:space:]]*/usr/libexec/hyprpolkitagent" "O template hyprland.conf deve iniciar o hyprpolkitagent"
assert_contains "${WORKSPACE_ROOT}/compositor/wayfire/wayfire.ini" "^polkit[[:space:]]*=[[:space:]]*/usr/libexec/hyprpolkitagent" "O wayfire.ini do compositor deve iniciar o hyprpolkitagent"
assert_contains "${WORKSPACE_ROOT}/packaging/templates/wayfire.ini" "^polkit[[:space:]]*=[[:space:]]*/usr/libexec/hyprpolkitagent" "O template wayfire.ini deve iniciar o hyprpolkitagent"
test_case_end

# Finaliza a suíte
suite_finish
