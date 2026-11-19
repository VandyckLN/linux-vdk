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

test_case_start "T3_PAIR7_ROOT_ANTES_DO_USUARIO" "Etapas de root do setup-dev-env rodam antes das etapas de usuário"
setup_script="${WORKSPACE_ROOT}/dev-stack/setup-dev-env.sh"
last_root_line="$(grep -n 'as_root ' "$setup_script" | tail -n 1 | cut -d: -f1)"
dotfiles_line="$(grep -nF 'install -m 644 "$ROOT_DIR/dev-stack/kitty/kitty.conf"' "$setup_script" | head -n 1 | cut -d: -f1)"
mise_line="$(grep -nF 'mise.run' "$setup_script" | head -n 1 | cut -d: -f1)"
assert_eq "1" "$([[ -n "$last_root_line" && -n "$dotfiles_line" && -n "$mise_line" ]] && echo 1 || echo 0)" "As linhas de referência devem existir no script"
assert_eq "1" "$([[ "$last_root_line" -lt "$dotfiles_line" ]] && echo 1 || echo 0)" "O último as_root (${last_root_line}) deve vir antes dos dotfiles (${dotfiles_line})"
assert_eq "1" "$([[ "$last_root_line" -lt "$mise_line" ]] && echo 1 || echo 0)" "O último as_root (${last_root_line}) deve vir antes do mise (${mise_line})"
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
# Sem os plugins wayland-shell-integration o hyprpolkitagent aborta ao abrir
# a janela de senha (o pacote do Ubuntu não declara essa dependência).
need("lumen-compositor", "qt6-wayland")
# Mandacaru (EDR) com eBPF vem por padrão no desktop.
need("lumen-desktop", "mandacaru (>= 0.4.0)")
need("lumen-desktop", "python3-bpfcc")
# Aviso sonoro e popup dos alertas do Mandacaru: áudio, notificação e tema de sons.
for dep in ("pipewire", "pipewire-pulse", "wireplumber", "mako-notifier", "libnotify-bin",
            "sound-theme-freedesktop"):
    need("lumen-desktop", dep)

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

# T3-PAIR8: Mandacaru no repositório local e na ISO
test_case_start "T3_PAIR8_FETCH_ANTES_DO_INDICE" "package-debs.sh baixa o Mandacaru depois do build e antes do índice"
order_out="$(python3 -I - "${WORKSPACE_ROOT}/scripts/package-debs.sh" <<'PYEOF' 2>&1
import sys
src = open(sys.argv[1], encoding="utf-8").read()
b, f, r = (src.find(x) for x in ("build-debs.sh", "fetch-third-party.sh", "create-local-repo.sh"))
print("ok" if -1 not in (b, f, r) and b < f < r else f"ordem errada: build={b} fetch={f} repo={r}")
PYEOF
)"
assert_eq "ok" "$order_out" "O fetch deve ficar entre o build-debs.sh e o create-local-repo.sh"
assert_contains "${WORKSPACE_ROOT}/scripts/package-debs.sh" '"mandacaru"' "O manifesto deve listar o mandacaru"
test_case_end

test_case_start "T3_PAIR8_ISO_INSTALA_HEADERS" "build-iso.sh instala linux-headers-generic junto do kernel"
assert_contains "${WORKSPACE_ROOT}/scripts/build-iso.sh" "linux-generic linux-headers-generic" "Os headers do kernel são necessários para o eBPF do Mandacaru"
test_case_end

test_case_start "T3_PAIR8_ISO_EXIGE_EDR" "build-iso.sh falha se o Mandacaru não entrar no chroot"
# Um dist/debs antigo (sem mandacaru) geraria uma ISO sem EDR em silêncio; a spec proíbe.
edr_out="$(python3 -I - "${WORKSPACE_ROOT}/scripts/build-iso.sh" <<'PYEOF' 2>&1
import re
import sys
src = open(sys.argv[1], encoding="utf-8").read()
inst = src.find("apt-get install -y lumen-desktop")
chk = re.search(r"dpkg -s mandacaru python3-bpfcc linux-headers-generic", src)
print("ok" if inst != -1 and chk and chk.start() > inst else "falta a checagem dpkg -s depois do install do lumen-desktop")
PYEOF
)"
assert_eq "ok" "$edr_out" "A ISO nunca pode sair sem o Mandacaru"
test_case_end

# T3-PAIR9: vigia do Mandacaru na sessão, no pacote e na ISO
test_case_start "T3_PAIR9_SESSAO_SOBE_VIGIA" "Os dois hyprland.conf sobem o mako e o vigia do Mandacaru"
for conf in "${WORKSPACE_ROOT}/packaging/templates/hyprland.conf" "${WORKSPACE_ROOT}/compositor/hyprland/hyprland.conf"; do
    assert_contains "$conf" "^exec-once = mako$" "mako sobe na sessão ($conf)"
done
assert_contains "${WORKSPACE_ROOT}/packaging/templates/hyprland.conf" "^exec-once = /usr/bin/lumen-edr-notify$" "Vigia instalado sobe na sessão"
assert_contains "${WORKSPACE_ROOT}/compositor/hyprland/hyprland.conf" "^exec-once = python3 -m shell\.edr_notify$" "Vigia de desenvolvimento sobe na sessão"
test_case_end

test_case_start "T3_PAIR9_JANELA_QUARENTENA_FLUTUANTE" "Os dois hyprland.conf abrem a janela da quarentena flutuante e no centro"
for conf in "${WORKSPACE_ROOT}/packaging/templates/hyprland.conf" "${WORKSPACE_ROOT}/compositor/hyprland/hyprland.conf"; do
    assert_contains "$conf" "^windowrule = float on, match:class io\.github\.vandyckln\.lumen\.quarentena$" "Janela da quarentena flutuante ($conf)"
    assert_contains "$conf" "^windowrule = center on, match:class io\.github\.vandyckln\.lumen\.quarentena$" "Janela da quarentena centralizada ($conf)"
done
test_case_end

test_case_start "T3_PAIR9_PACOTE_INSTALA_VIGIA" "build-debs.sh instala o lumen-edr-notify em /usr/bin no lumen-shell"
vig_out="$(python3 -I - "${WORKSPACE_ROOT}/packaging/build-debs.sh" <<'PYEOF' 2>&1
import sys
src = open(sys.argv[1], encoding="utf-8").read()
ini = src.find("lumen-shell)")
fim = src.find(";;", ini)
bloco = src[ini:fim] if ini != -1 else ""
alvo = 'cp "$WORKSPACE_ROOT/packaging/templates/lumen-edr-notify" "$stage_dir/usr/bin/lumen-edr-notify"'
print("ok" if alvo in bloco else "o bloco do lumen-shell não copia o lumen-edr-notify")
PYEOF
)"
assert_eq "ok" "$vig_out" "O pacote lumen-shell leva o lançador do vigia"
test_case_end

test_case_start "T3_PAIR9_GRUPO_MANDACARU" "Usuário da live e usuário instalado entram no grupo mandacaru"
assert_contains "${WORKSPACE_ROOT}/scripts/build-iso.sh" "useradd -m -s /bin/bash -G sudo,video,audio,render,mandacaru " "Live no grupo mandacaru"
assert_contains "${WORKSPACE_ROOT}/installer/calamares/modules/users.conf" "^ *- mandacaru$" "Calamares põe o usuário no grupo mandacaru"
test_case_end

test_case_start "T3_PAIR9_GRUPO_DEPOIS_DO_EDR" "O useradd da live vem depois do install do lumen-desktop (que cria o grupo)"
ord_out="$(python3 -I - "${WORKSPACE_ROOT}/scripts/build-iso.sh" <<'PYEOF' 2>&1
import sys
src = open(sys.argv[1], encoding="utf-8").read()
inst = src.find("apt-get install -y lumen-desktop")
add = src.find("useradd -m -s /bin/bash -G sudo,video,audio,render,mandacaru")
print("ok" if inst != -1 and add > inst else "o useradd com mandacaru precisa vir depois do apt-get install -y lumen-desktop")
PYEOF
)"
assert_eq "ok" "$ord_out" "Sem o grupo criado, o useradd falharia"
test_case_end

test_case_start "T3_PAIR9_GUARDA_VERSAO_E_AVISO" "O guarda do chroot exige o Mandacaru do lock e os pacotes do aviso"
# Chroot reaproveitado (sem --clean) responde "already the newest version" ao lumen-desktop
# e deixaria a ISO com o Mandacaru velho e sem PipeWire/mako, em silêncio.
guard_out="$(python3 -I - "${WORKSPACE_ROOT}/scripts/build-iso.sh" <<'PYEOF' 2>&1
import re
import sys
src = open(sys.argv[1], encoding="utf-8").read()
erros = []
if not re.search(r"MANDACARU_MIN=.*mandacaru\.lock", src):
    erros.append("MANDACARU_MIN nao vem do mandacaru.lock")
inst = src.find("apt-get install -y lumen-desktop")
cmp_ = src.find("dpkg --compare-versions")
if cmp_ == -1 or cmp_ < inst or "$MANDACARU_MIN" not in src[cmp_:cmp_ + 200]:
    erros.append("falta dpkg --compare-versions contra $MANDACARU_MIN depois do install")
m = re.search(r"dpkg -s ([^>|]+)>/dev/null", src)
pkgs = set(m.group(1).split()) if m else set()
falta = {"mandacaru", "python3-bpfcc", "linux-headers-generic", "pipewire", "mako-notifier", "libnotify-bin"} - pkgs
if falta:
    erros.append("dpkg -s sem: " + " ".join(sorted(falta)))
print("ok" if not erros else "; ".join(erros))
PYEOF
)"
assert_eq "ok" "$guard_out" "ISO nunca sai com o EDR velho ou sem o aviso"
test_case_end

test_case_start "T3_PAIR9_LOCK_ATENDE_DEPENDS" "O Mandacaru do lock atende o mínimo exigido pelo lumen-desktop"
# Depends acima do lock = apt-get install -y lumen-desktop insatisfeito e ISO que não monta.
lockdep_out="$(python3 -I - "${WORKSPACE_ROOT}" <<'PYEOF' 2>&1
import re
import sys
root = sys.argv[1]
lock = open(f"{root}/packaging/third-party/mandacaru.lock", encoding="utf-8").read()
m = re.search(r"^MANDACARU_VERSION=([0-9.]+)$", lock, re.M)
ver = tuple(int(x) for x in m.group(1).split(".")) if m else None
erros = []
for arq in ("packaging/build-debs.sh", "packaging/debian/control"):
    mins = re.findall(r"mandacaru \(>= ([0-9.]+)\)", open(f"{root}/{arq}", encoding="utf-8").read())
    if not mins:
        erros.append(f"{arq}: sem mandacaru (>= ...)")
    for v in mins:
        if ver is None or ver < tuple(int(x) for x in v.split(".")):
            erros.append(f"{arq}: exige {v}, lock tem {m.group(1) if m else 'nada'}")
print("ok" if not erros else "; ".join(erros))
PYEOF
)"
assert_eq "ok" "$lockdep_out" "Lock e Depends coerentes"
test_case_end

test_case_start "T3_PAIR9_USERMOD_FORA_DO_IF" "A live entra no grupo mandacaru mesmo com usuário já existente"
um_out="$(python3 -I - "${WORKSPACE_ROOT}/scripts/build-iso.sh" <<'PYEOF' 2>&1
import sys
src = open(sys.argv[1], encoding="utf-8").read()
ini = src.find("if ! id -u $LIVE_USER")
fim = src.find("\nfi\n", ini)
um = src.find("usermod -aG mandacaru $LIVE_USER")
print("ok" if ini != -1 and fim != -1 and um > fim else "falta usermod -aG mandacaru $LIVE_USER depois do bloco do useradd")
PYEOF
)"
assert_eq "ok" "$um_out" "Chroot reaproveitado também põe a live no grupo"
test_case_end

# Finaliza a suíte
suite_finish
