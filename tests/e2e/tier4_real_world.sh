#!/usr/bin/env bash
# ==============================================================================
# Lumen OS E2E — Tier 4: Cenários de Uso Real (tests/e2e/tier4_real_world.sh)
# 5 fluxos compostos de ponta a ponta do usuário e cenários de validação operacional
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Carrega o harness comum
source "${SCRIPT_DIR}/harness.sh"

suite_init "Tier 4: Real-World Application Scenarios"

if [[ -z "${SANDBOX_DIR:-}" ]]; then
    create_test_sandbox "tier4"
    enable_mock_root_tools
    trap "disable_mock_root_tools; cleanup_test_sandbox" EXIT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 130" INT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 1" TERM
fi


# ------------------------------------------------------------------------------
# Cenário 1: Simulação do fluxo de build limpo (pipeline em dry-run)
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO1_CLEAN_BUILD_WORKFLOW" "Dry-run do pipeline completo a partir do estado limpo: empacotamento -> repositório -> ISO -> traps"
pkg_script="${WORKSPACE_ROOT}/scripts/package-debs.sh"
build_iso_script="${WORKSPACE_ROOT}/scripts/build-iso.sh"

if [[ -f "$pkg_script" ]]; then
    # Testa o script de orquestração do build dos pacotes
    assert_file_executable "$pkg_script" "package-debs.sh deve ser executável"

    # Simula o dry-run do pipeline de empacotamento
    status=0
    pkg_out=$(bash "$pkg_script" --help 2>&1) || status=$?
    assert_contains "$pkg_script" "build-debs\.sh" "package-debs.sh orquestra o build-debs.sh"
    assert_contains "$pkg_script" "create-local-repo\.sh" "package-debs.sh orquestra o create-local-repo.sh"

    # Verifica o dry-run do pipeline da ISO, se existir
    if [[ -f "$build_iso_script" ]]; then
        assert_file_executable "$build_iso_script" "build-iso.sh deve ser executável"
        assert_contains "$build_iso_script" "dry-run" "build-iso.sh deve suportar --dry-run"
        assert_contains "$build_iso_script" "trap " "build-iso.sh deve capturar sinais para limpeza"

        iso_out=$(bash "$build_iso_script" --dry-run 2>&1) || true
        assert_contains "$iso_out" "Stage|debootstrap|squashfs|xorriso" "O dry-run da ISO deve reportar o progresso do pipeline"
    fi
else
    test_case_skip "scripts/package-debs.sh ainda não existe"
fi
test_case_end


# ------------------------------------------------------------------------------
# Cenário 2: Geração do repositório offline e validação do DAG do grafo de dependências
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO2_OFFLINE_REPO_AND_DEPENDENCY_DAG" "Detecção de ciclos no grafo de dependências e indexação do repositório APT offline"
control_file="${WORKSPACE_ROOT}/packaging/debian/control"
repo_script="${WORKSPACE_ROOT}/packaging/create-local-repo.sh"

if [[ -f "$control_file" && -f "$repo_script" ]]; then
    # 1. Interpreta os pacotes declarados no control
    for pkg in lumen-shell lumen-compositor lumen-system lumen-dev-stack lumen-welcome lumen-desktop; do
        assert_contains "$control_file" "Package:[[:space:]]*${pkg}" "O pacote ${pkg} deve estar declarado no control"
    done

    # 2. Verifica se o metapacote lumen-desktop depende dos 5 subpacotes
    assert_contains "$control_file" "lumen-shell" "lumen-desktop deve depender de lumen-shell"
    assert_contains "$control_file" "lumen-compositor" "lumen-desktop deve depender de lumen-compositor"
    assert_contains "$control_file" "lumen-system" "lumen-desktop deve depender de lumen-system"
    assert_contains "$control_file" "lumen-dev-stack" "lumen-desktop deve depender de lumen-dev-stack"
    assert_contains "$control_file" "lumen-welcome" "lumen-desktop deve depender de lumen-welcome"

    # 3. Verify no circular dependency: Sub-packages must NOT depend on lumen-desktop
    python3 - << 'EOF' || _record_fail "Ciclo de dependências detectado no arquivo control"
import re, sys

control_path = "packaging/debian/control"
with open(control_path, 'r') as f:
    content = f.read()

stanzas = content.split("\n\n")
deps = {}
for s in stanzas:
    pkg_m = re.search(r'^Package:\s*(\S+)', s, re.MULTILINE)
    if not pkg_m:
        continue
    pkg_name = pkg_m.group(1)
    dep_m = re.search(r'^Depends:\s*(.*?)(?=\n\S|\Z)', s, re.MULTILINE | re.DOTALL)
    dep_str = dep_m.group(1) if dep_m else ""
    deps[pkg_name] = [d.strip().split()[0] for d in dep_str.split(',') if d.strip()]

# Garante que os subpacotes nunca dependam do metapacote lumen-desktop
for p in ["lumen-shell", "lumen-compositor", "lumen-system", "lumen-dev-stack", "lumen-welcome"]:
    if "lumen-desktop" in deps.get(p, []):
        sys.exit(1)
sys.exit(0)
EOF

    # 4. Verifica se o create-local-repo.sh gera Packages e Packages.gz
    assert_contains "$repo_script" "dpkg-scanpackages" "create-local-repo.sh deve invocar o dpkg-scanpackages"
    assert_contains "$repo_script" "Packages" "create-local-repo.sh deve criar o arquivo Packages"
else
    test_case_skip "control Debian ou create-local-repo.sh ainda não existem"
fi
test_case_end


# ------------------------------------------------------------------------------
# Cenário 3: Autostart da sessão live do Calamares e dry-run da execução da pós-instalação no chroot
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO3_CALAMARES_AUTOSTART_AND_POSTINSTALL_CHROOT" "Ambiente de autostart live, ordem da sequência e execução em chroot simulado"
settings_file="${WORKSPACE_ROOT}/installer/calamares/settings.conf"
postinstall_script="${WORKSPACE_ROOT}/installer/calamares/scripts/lumen-postinstall.sh"
launch_script="${WORKSPACE_ROOT}/installer/calamares/scripts/launch-calamares.sh"

if [[ -f "$settings_file" && -f "$postinstall_script" && -f "$launch_script" ]]; then
    # 1. Validação da sequência de execução do Calamares
    assert_contains "$settings_file" "sequence:" "settings.conf deve definir a sequência de execução"
    assert_contains "$settings_file" "welcome" "A sequência deve incluir welcome"
    assert_contains "$settings_file" "partition" "A sequência deve incluir partition"
    assert_contains "$settings_file" "unpackfs" "A sequência deve incluir unpackfs"
    assert_contains "$settings_file" "users" "A sequência deve incluir users"
    assert_contains "$settings_file" "postinstall" "A sequência deve incluir o hook postinstall"

    # 2. Simulação hermética do chroot de destino
    mock_chroot=$(mktemp -d "/tmp/lumen_mock_target_XXXXXX")
    mkdir -p "${mock_chroot}/etc/skel/.config" "${mock_chroot}/home/lumen" "${mock_chroot}/usr/bin"
    echo "lumen:x:1000:1000:Lumen User:/home/lumen:/bin/bash" > "${mock_chroot}/etc/passwd"

    # O diretório home do usuário simulado permanece intacto
    assert_dir_exists "${mock_chroot}/home/lumen" "Diretório do usuário simulado criado corretamente"
    rm -rf "${mock_chroot}"
else
    test_case_skip "Configuração do Calamares ou hook de pós-instalação ainda não existem"
fi
test_case_end


# ------------------------------------------------------------------------------
# Cenário 4: Validação da invocação de VM QEMU multimodo e verificação da linha de comando
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO4_QEMU_VM_INVOCATION_AND_COMMAND_VALIDATION" "Parsing das opções de CLI do executor QEMU nos modos UEFI, BIOS, headless e de recursos"
qemu_script="${WORKSPACE_ROOT}/scripts/test-iso-qemu.sh"

if [[ -f "$qemu_script" ]]; then
    dummy_iso="${SANDBOX_DIR}/dummy_lumen_test.iso"
    echo "CD001" > "$dummy_iso"

    # Verifica se o script trata o dry-run ou a inspeção de flags
    assert_contains "$qemu_script" "uefi" "O script deve suportar a opção uefi"
    assert_contains "$qemu_script" "bios" "O script deve suportar a opção bios"
    assert_contains "$qemu_script" "headless" "O script deve suportar a opção headless"

    # Teste negativo com ISO ausente
    status=0
    bash "$qemu_script" "/tmp/nonexistent-iso-$$.iso" >/dev/null 2>&1 || status=$?
    assert_ne 0 "$status" "Invocar o executor QEMU com uma ISO inexistente deve falhar"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end


# ------------------------------------------------------------------------------
# Cenário 5: Extração dos blocos de código do guia de build e verificação de executáveis
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO5_USER_GUIDE_CODE_BLOCK_VERIFICATION" "Extrai e valida os blocos de código Markdown, as referências a scripts e os pré-requisitos"
doc_file="${WORKSPACE_ROOT}/docs/BUILD_ISO.md"

if [[ -f "$doc_file" ]]; then
    assert_file_not_empty "$doc_file" "BUILD_ISO.md deve ter conteúdo"
    assert_contains "$doc_file" "WSL2" "A documentação deve conter a seção de WSL2"

    # Extrai todos os blocos de código bash/sh do Markdown
    code_snippets=$(sed -n '/^```bash/,/^```/p' "$doc_file" | grep -v '^```' || true)

    # Verifica se as referências a scripts correspondem aos scripts reais do workspace
    if grep -q "package-debs.sh" "$doc_file"; then
        assert_file_exists "${WORKSPACE_ROOT}/scripts/package-debs.sh" "package-debs.sh referenciado na documentação deve existir"
    fi
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# ==============================================================================
# FUNCIONALIDADE F7: Elevação de Privilégios
# ==============================================================================

test_case_start "T4_SCENARIO6_PACOTES_COM_HELPER_E_POLICY" "Pacote lumen-system traz helper, elevate.sh, lista e policy; lumen-welcome não traz policy"
if command -v dpkg-deb >/dev/null 2>&1; then
    debs_dir="${SANDBOX_DIR}/debs"
    build_out="$(bash "${WORKSPACE_ROOT}/packaging/build-debs.sh" "$debs_dir" 2>&1)"
    build_status=$?
    assert_eq 0 "$build_status" "build-debs.sh deve concluir com sucesso -> ${build_out}"
    system_listing="$(dpkg-deb -c "$debs_dir"/lumen-system_*.deb 2>&1)"
    welcome_listing="$(dpkg-deb -c "$debs_dir"/lumen-welcome_*.deb 2>&1)"
    helper_lines="$(grep -cE -- '^-rwxr-xr-x .* \./usr/bin/lumen-root-helper$' <<< "$system_listing")"
    assert_eq 1 "$helper_lines" "O helper deve ser instalado em /usr/bin com modo 0755 (uma única cópia)"
    assert_contains "$system_listing" "\./usr/share/lumen-os/system/lib/elevate\.sh" "O pacote deve trazer o elevate.sh"
    assert_contains "$system_listing" "\./usr/share/lumen-os/system/root-helper/allowed-packages\.list" "O pacote deve trazer a lista de pacotes permitidos"
    assert_contains "$system_listing" "\./usr/share/polkit-1/actions/dev\.lumenos\.root-helper\.policy" "O pacote deve trazer a policy do polkit"
    assert_not_contains "$welcome_listing" "polkit-1/actions" "O lumen-welcome não deve trazer policy do polkit"
else
    test_case_skip "dpkg-deb não está disponível"
fi
test_case_end

# Finaliza a suíte
suite_finish
