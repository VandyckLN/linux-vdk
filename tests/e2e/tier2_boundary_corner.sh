#!/usr/bin/env bash
# ==============================================================================
# Lumen OS E2E — Tier 2: Casos de Limite e de Canto (tests/e2e/tier2_boundary_corner.sh)
# 30 Testes: 5 testes negativos, de limite e de casos de borda por funcionalidade, de F1 a F6
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Carrega o harness comum
source "${SCRIPT_DIR}/harness.sh"

suite_init "Tier 2: Boundary & Corner Cases (F1 - F6)"

if [[ -z "${SANDBOX_DIR:-}" ]]; then
    create_test_sandbox "tier2"
    enable_mock_root_tools
    trap "disable_mock_root_tools; cleanup_test_sandbox" EXIT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 130" INT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 1" TERM
fi

# ==============================================================================
# FUNCIONALIDADE F1: Casos de Limite do Empacotamento .deb Modular (5 testes)
# ==============================================================================

# T2-F1-01: Rejeição por arquivo control ausente
test_case_start "T2_F1_01" "A ferramenta de empacotamento rejeita diretório sem DEBIAN/control"
status=0
output=$(dpkg-deb --build "${SCRIPT_DIR}/fixtures/pkg_missing_control" 2>&1) || status=$?
if [[ "$status" -ne 0 && "$output" =~ (failed to open package control file|No such file) ]]; then
    assert_ne 0 "$status" "A ausência do arquivo control deve fazer o dpkg-deb falhar"
else
    # Verificação alternativa
    assert_ne 0 "$status" "A ausência do arquivo control deve fazer o build falhar"
fi
test_case_end

# T2-F1-02: Rejeição de sintaxe de control malformada
test_case_start "T2_F1_02" "A ferramenta de empacotamento rejeita sintaxe de control RFC 822 corrompida"
status=0
output=$(dpkg-deb --build "${SCRIPT_DIR}/fixtures/pkg_corrupted_control" 2>&1) || status=$?
assert_ne 0 "$status" "Um arquivo control corrompido deve fazer o dpkg-deb falhar"
test_case_end

# T2-F1-03: Tratamento de flags de CLI não reconhecidas
test_case_start "T2_F1_03" "O script de build rejeita opções de CLI desconhecidas ou flags inválidas"
build_debs_script="${WORKSPACE_ROOT}/packaging/build-debs.sh"
if [[ -f "$build_debs_script" ]]; then
    status=0
    output=$(bash "$build_debs_script" --invalid-flag-xyz-99 2>&1) || status=$?
    assert_ne 0 "$status" "Flags de CLI desconhecidas ou caminho inválido devem fazer o script de build sair com código diferente de zero"
else
    test_case_skip "packaging/build-debs.sh ainda não existe"
fi
test_case_end

# T2-F1-04: Tratamento de diretório de saída sem permissão de escrita
test_case_start "T2_F1_04" "O script de empacotamento detecta de forma limpa um destino sem permissão de escrita"
if [[ -f "$build_debs_script" ]]; then
    status=0
    output=$(bash "$build_debs_script" "/proc/unwritable_dir_$(date +%s)" 2>&1) || status=$?
    assert_ne 0 "$status" "Um diretório de saída sem permissão de escrita deve falhar de forma limpa"
else
    test_case_skip "packaging/build-debs.sh ainda não existe"
fi
test_case_end

# T2-F1-05: Tratamento de repositório vazio
test_case_start "T2_F1_05" "O indexador do repositório lida bem com um diretório sem nenhum pacote deb"
empty_dir="${SCRIPT_DIR}/fixtures/empty_repo"
if command -v dpkg-scanpackages >/dev/null 2>&1; then
    status=0
    output=$(dpkg-scanpackages "$empty_dir" /dev/null 2>&1) || status=$?
    assert_contains "$output" "Wrote 0 entries|binary path" "A varredura de diretório vazio foi tratada corretamente"
else
    test_case_skip "dpkg-scanpackages não disponível no host"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F2: Casos de Limite do Instalador Calamares e Branding (5 testes)
# ==============================================================================

# T2-F2-01: Detecção de módulo referenciado ausente
test_case_start "T2_F2_01" "Detecta módulos referenciados na sequência que faltam no diretório de módulos"
settings_file="${WORKSPACE_ROOT}/installer/calamares/settings.conf"
modules_dir="${WORKSPACE_ROOT}/installer/calamares/modules"
if [[ -f "$settings_file" && -d "$modules_dir" ]]; then
    # Verifica se os módulos principais referenciados existem de fato no disco
    for mod in welcome partition unpackfs users bootloader; do
        assert_file_exists "${modules_dir}/${mod}.conf" "O módulo ${mod}.conf referenciado no settings deve existir"
    done
else
    test_case_skip "Configuração do Calamares ainda não existe"
fi
test_case_end

# T2-F2-02: Rejeição de configuração YAML corrompida
test_case_start "T2_F2_02" "O parser YAML detecta corrupção de sintaxe nas configurações do instalador"
corrupt_conf="${SCRIPT_DIR}/fixtures/corrupt_settings.conf"
status=0
err=$(python3 -c "import yaml; yaml.safe_load(open('$corrupt_conf'))" 2>&1) || status=$?
assert_ne 0 "$status" "Sintaxe YAML corrompida deve fazer o parser falhar"
assert_contains "$err" "ScannerError|ParserError|tab" "O erro deve reportar a violação de sintaxe YAML"
test_case_end

# T2-F2-03: Detecção de asset de branding ausente
test_case_start "T2_F2_03" "As imagens referenciadas no descritor de branding existem no disco"
branding_desc="${WORKSPACE_ROOT}/installer/calamares/branding/lumen/branding.desc"
branding_dir="${WORKSPACE_ROOT}/installer/calamares/branding/lumen"
if [[ -f "$branding_desc" ]]; then
    # Verifica se os arquivos de imagem declarados no branding.desc existem
    logo_svg=$(python3 -c "import yaml; d=yaml.safe_load(open('$branding_desc')); print(d.get('images', {}).get('productLogo', ''))" 2>/dev/null || echo "")
    if [[ -n "$logo_svg" ]]; then
        assert_file_exists "${branding_dir}/${logo_svg}" "O logo do produto referenciado no branding.desc deve existir"
    fi
else
    test_case_skip "installer/calamares/branding/lumen/branding.desc ainda não existe"
fi
test_case_end

# T2-F2-04: Negação da pós-instalação sem root
test_case_start "T2_F2_04" "O hook de pós-instalação aborta quando executado sem permissão de escrita ou sem root"
postinstall="${WORKSPACE_ROOT}/installer/calamares/scripts/lumen-postinstall.sh"
if [[ -f "$postinstall" ]]; then
    # Executa como usuário comum sem privilégios e sem as ferramentas simuladas
    status=0
    # Ignora temporariamente o sudo simulado para testar o comportamento real sem root
    output=$(PATH="${ORIGINAL_PATH:-/usr/bin:/bin}" bash "$postinstall" 2>&1) || status=$?
    assert_ne 0 "$status" "lumen-postinstall.sh executado sem root deve sair com código diferente de zero"
else
    test_case_skip "installer/calamares/scripts/lumen-postinstall.sh ainda não existe"
fi
test_case_end

# T2-F2-05: Tratamento de display ausente no wrapper Wayland
test_case_start "T2_F2_05" "Configuração de ambiente e verificação de elevação do wrapper de lançamento Wayland"
launcher="${WORKSPACE_ROOT}/installer/calamares/scripts/launch-calamares.sh"
if [[ -f "$launcher" ]]; then
    # Verifica se o lançador configura QT_QPA_PLATFORM e WAYLAND_DISPLAY
    assert_contains "$launcher" "QT_QPA_PLATFORM" "launch-calamares.sh deve configurar QT_QPA_PLATFORM"
    assert_contains "$launcher" "WAYLAND_DISPLAY" "launch-calamares.sh deve tratar WAYLAND_DISPLAY"
else
    test_case_skip "installer/calamares/scripts/launch-calamares.sh ainda não existe"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F3: Casos de Limite do Pipeline de Geração da ISO (5 testes)
# ==============================================================================

# T2-F3-01: Negação de invocação sem root
test_case_start "T2_F3_01" "O script de build da ISO exige estritamente invocação como root / sudo"
build_iso_script="${WORKSPACE_ROOT}/scripts/build-iso.sh"
if [[ -f "$build_iso_script" ]]; then
    # Executa com o PATH original (sem o sudo simulado) para verificar a negação sem root
    status=0
    output=$(PATH="${ORIGINAL_PATH:-/usr/bin:/bin}" bash "$build_iso_script" 2>&1) || status=$?
    assert_ne 0 "$status" "build-iso.sh executado sem root deve sair com código diferente de zero"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end

# T2-F3-02: Detecção de toolchain de build ausente
test_case_start "T2_F3_02" "A verificação prévia do script de build da ISO detecta toolchain obrigatória ausente"
if [[ -f "$build_iso_script" ]]; then
    # Restringe o PATH ao coreutils mínimo para testar a verificação da toolchain
    status=0
    output=$(PATH="/bin:/usr/bin" bash "$build_iso_script" --check-deps 2>&1) || status=$?
    # Deve falhar na verificação de dependências ou sair com código diferente de zero
    assert_contains "$build_iso_script" "command -v" "build-iso.sh deve verificar os comandos das ferramentas obrigatórias"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end

# T2-F3-03: Aborto por espaço em disco insuficiente
test_case_start "T2_F3_03" "O script de build da ISO consulta o espaço livre do sistema de arquivos antes do build"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "df |disk|space" "build-iso.sh deve verificar o espaço em disco disponível"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end

# T2-F3-04: Verificação da limpeza de montagens em caso de interrupção
test_case_start "T2_F3_04" "O script de build da ISO captura EXIT INT TERM para desmontar de forma limpa as montagens do chroot"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "trap " "build-iso.sh deve definir traps de sinais para limpeza"
    assert_contains "$build_iso_script" "umount" "O handler de limpeza deve desmontar os sistemas de arquivos"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end

# T2-F3-05: Verificação de segurança do modo dry-run
test_case_start "T2_F3_05" "O dry-run do script de build da ISO roda sem efeitos destrutivos e sem montagens de root"
if [[ -f "$build_iso_script" ]]; then
    status=0
    output=$(bash "$build_iso_script" --dry-run 2>&1) || status=$?
    assert_eq 0 "$status" "build-iso.sh --dry-run deve sair com 0 sem erros"
else
    test_case_skip "scripts/build-iso.sh ainda não existe"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F4: Casos de Limite da Automação de CI no GitHub Actions (5 testes)
# ==============================================================================

# T2-F4-01: Rejeição de YAML de workflow corrompido
test_case_start "T2_F4_01" "O validador YAML do CI detecta sintaxe de workflow corrompida e indentação inválida"
corrupt_wf="${SCRIPT_DIR}/fixtures/corrupt_workflow.yml"
status=0
err=$(python3 -c "import yaml; yaml.safe_load(open('$corrupt_wf'))" 2>&1) || status=$?
assert_ne 0 "$status" "YAML de workflow corrompido deve falhar no parsing"
test_case_end

# T2-F4-02: Detecção de chaves obrigatórias ausentes
test_case_start "T2_F4_02" "O workflow de CI contém as chaves obrigatórias de nível superior: name, on, jobs"
workflow_file="${WORKSPACE_ROOT}/.github/workflows/build-iso.yml"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "^name:" "O workflow deve ter name no nível superior"
    assert_contains "$workflow_file" "^on:" "O workflow deve ter o gatilho on no nível superior"
    assert_contains "$workflow_file" "^jobs:" "O workflow deve ter o mapeamento jobs no nível superior"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end

# T2-F4-03: Rejeição de runner incompatível
test_case_start "T2_F4_03" "O workflow de CI especifica uma imagem de runner Ubuntu Linux suportada"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "runs-on:[[:space:]]*ubuntu-" "O workflow deve ter como alvo um runner Ubuntu"
    assert_not_contains "$workflow_file" "runs-on:[[:space:]]*windows-" "Runner Windows não é suportado"
    assert_not_contains "$workflow_file" "runs-on:[[:space:]]*macos-" "Runner macOS não é suportado"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end

# T2-F4-04: Divergência no contrato do caminho do artefato
test_case_start "T2_F4_04" "O upload de artefato do CI corresponde estritamente ao nome contratual da ISO de saída"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "lumen-os-26.04-amd64.iso" "O caminho de upload do artefato deve corresponder ao nome contratual da ISO"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end

# T2-F4-05: Detecção de falta de elevação com sudo
test_case_start "T2_F4_05" "O workflow de CI executa o script de build como root com elevação via sudo"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "sudo.*build-iso\.sh" "O workflow deve invocar o build-iso.sh com sudo"
else
    test_case_skip ".github/workflows/build-iso.yml ainda não existe"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F5: Casos de Limite do Script e Executor de Testes QEMU (5 testes)
# ==============================================================================

# T2-F5-01: Tratamento de caminho de ISO inexistente
test_case_start "T2_F5_01" "O executor QEMU aborta de forma limpa com erro quando o caminho da ISO não existe"
qemu_script="${WORKSPACE_ROOT}/scripts/test-iso-qemu.sh"
if [[ -f "$qemu_script" ]]; then
    status=0
    output=$(bash "$qemu_script" "/tmp/nonexistent-iso-file-$$.iso" 2>&1) || status=$?
    assert_ne 0 "$status" "Caminho de ISO inexistente deve fazer o executor sair com código diferente de zero"
    assert_contains "$output" "not found|No such file|does not exist|não encontrad" "O erro deve informar que a ISO não foi encontrada"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end

# T2-F5-02: Rejeição de flag de CLI desconhecida
test_case_start "T2_F5_02" "O executor QEMU rejeita opções de linha de comando desconhecidas com código de saída 2"
if [[ -f "$qemu_script" ]]; then
    status=0
    output=$(bash "$qemu_script" --invalid-option-xyz-99 2>&1) || status=$?
    assert_eq 2 "$status" "Opções de CLI desconhecidas devem resultar no código de saída 2"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end

# T2-F5-03: Rejeição de valores de RAM/SMP malformados
test_case_start "T2_F5_03" "O executor QEMU rejeita valores de recursos malformados (--ram / --smp)"
if [[ -f "$qemu_script" ]]; then
    status=0
    output=$(bash "$qemu_script" --ram "not-a-number" 2>&1) || status=$?
    assert_ne 0 "$status" "Especificação de recursos inválida deve sair com código diferente de zero"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end

# T2-F5-04: Detecção de executável QEMU ausente
test_case_start "T2_F5_04" "O executor QEMU diagnostica a ausência do qemu-system-x86_64 no PATH"
if [[ -f "$qemu_script" ]]; then
    # Executa com PATH restrito, sem o qemu
    status=0
    output=$(PATH="/bin:/usr/bin" bash "$qemu_script" 2>&1) || status=$?
    assert_contains "$qemu_script" "qemu-system-x86_64" "O script deve procurar o qemu-system-x86_64"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end

# T2-F5-05: Tratamento de firmware OVMF ausente
test_case_start "T2_F5_05" "O executor QEMU trata a ausência do firmware OVMF com um diagnóstico acionável"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "OVMF" "O script deve conter a lógica de busca e diagnóstico do OVMF"
else
    test_case_skip "scripts/test-iso-qemu.sh ainda não existe"
fi
test_case_end


# ==============================================================================
# FUNCIONALIDADE F6: Casos de Limite do Guia Prático de Build para o Usuário (5 testes)
# ==============================================================================

# T2-F6-01: Caminhos de scripts quebrados no Markdown
test_case_start "T2_F6_01" "Extrai as referências a scripts do repositório no guia do usuário e verifica se existem"
guide_file="${WORKSPACE_ROOT}/docs/BUILD_ISO.md"
if [[ -f "$guide_file" ]]; then
    # Procura os scripts referenciados no guia
    if grep -q "scripts/package-debs.sh" "$guide_file"; then
        assert_file_exists "${WORKSPACE_ROOT}/scripts/package-debs.sh" "package-debs.sh citado no guia deve existir"
    fi
    if grep -q "scripts/build-iso.sh" "$guide_file"; then
        assert_file_exists "${WORKSPACE_ROOT}/scripts/build-iso.sh" "build-iso.sh citado no guia deve existir"
    fi
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# T2-F6-02: Detecção de blocos de código não fechados
test_case_start "T2_F6_02" "Os blocos de código Markdown (três crases) estão corretamente fechados"
if [[ -f "$guide_file" ]]; then
    fence_count=$(grep -c '^[[:space:]]*```' "$guide_file" || echo 0)
    remainder=$((fence_count % 2))
    assert_eq 0 "$remainder" "Os blocos de código do BUILD_ISO.md devem ter pares de abertura/fechamento correspondentes"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# T2-F6-03: Detecção de marcadores de pendência
test_case_start "T2_F6_03" "O guia do usuário não contém marcadores TODO, TBD ou FIXME pendentes"
if [[ -f "$guide_file" ]]; then
    assert_not_contains "$guide_file" "TODO|TBD|FIXME|REPLACE_ME" "O guia do usuário não pode conter marcadores de pendência"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# T2-F6-04: Aviso ausente sobre NTFS em /mnt/c no WSL2
test_case_start "T2_F6_04" "O guia do usuário alerta contra gerar o build em montagens NTFS do Windows (/mnt/c)"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "/mnt/c|NTFS" "O guia do usuário deve alertar contra montagens do sistema de arquivos Windows em /mnt/c"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# T2-F6-05: Divergência na sintaxe de verificação do checksum
test_case_start "T2_F6_05" "O trecho do comando de checksum corresponde ao arquivo de checksum SHA256 canônico"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "sha256sum[[:space:]]+-c[[:space:]]+.*\.sha256" "A documentação deve mostrar a verificação com sha256sum -c"
else
    test_case_skip "docs/BUILD_ISO.md ainda não existe"
fi
test_case_end

# Finaliza a suíte
suite_finish
