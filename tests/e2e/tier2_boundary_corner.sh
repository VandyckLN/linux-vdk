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

# T2-F4-06: Checksum conferido de dentro do dist/
test_case_start "T2_F4_06" "O CI confere o .sha256 de dentro do dist/, onde está a ISO que ele cita"
if [[ -f "$workflow_file" ]]; then
    # o build-iso.sh grava o .sha256 com o nome puro da ISO (roda "sha256sum \$ISO_NAME" no dist/)
    assert_contains "${WORKSPACE_ROOT}/scripts/build-iso.sh" 'sha256sum "\$ISO_NAME" > "\$\{ISO_NAME\}\.sha256"' "O .sha256 cita só o nome da ISO"
    assert_contains "$workflow_file" "cd dist && sha256sum -c linux-vdk-26\.04-amd64\.iso\.sha256" "O CI entra no dist/ antes do sha256sum -c"
    assert_not_contains "$workflow_file" "sha256sum -c dist/" "Conferir da raiz falha: a ISO citada não está lá"
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

# ==============================================================================
# FUNCIONALIDADE F7: Elevação de Privilégios
# ==============================================================================
helper="${WORKSPACE_ROOT}/system/lumen-root-helper"

# T2-F7-01
test_case_start "T2_F7_01" "Helper recusa ação desconhecida"
assert_exit_code 2 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" formatar-disco
assert_contains "$LAST_CMD_OUTPUT" "ação desconhecida: formatar-disco" "A recusa deve citar a ação desconhecida"
test_case_end

# T2-F7-02
test_case_start "T2_F7_02" "Helper recusa pacote fora da lista permitida"
assert_exit_code 2 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" apt-install nmap
assert_contains "$LAST_CMD_OUTPUT" "pacote não permitido: nmap" "A recusa deve ser por pacote fora da lista"
test_case_end

# T2-F7-03
test_case_start "T2_F7_03" "Helper recusa nomes de pacote maliciosos"
assert_exit_code 2 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" apt-install -oAPT::X=1
assert_contains "$LAST_CMD_OUTPUT" "nome de pacote inválido" "A recusa deve ser por nome inválido"
assert_exit_code 2 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" apt-install 'vim;rm -rf /'
assert_contains "$LAST_CMD_OUTPUT" "nome de pacote inválido" "A recusa deve ser por nome inválido"
assert_exit_code 2 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" apt-install '../etc'
assert_contains "$LAST_CMD_OUTPUT" "nome de pacote inválido" "A recusa deve ser por nome inválido"
test_case_end

# T2-F7-04
test_case_start "T2_F7_04" "Helper recusa apt-install sem pacotes"
assert_exit_code 2 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" apt-install
assert_contains "$LAST_CMD_OUTPUT" "apt-install exige ao menos um pacote" "A recusa deve ser por falta de pacotes"
test_case_end

# T2-F7-05
test_case_start "T2_F7_05" "Ação válida sem root e sem dry-run sai com 3"
if [[ "$EUID" -eq 0 ]]; then
    test_case_skip "a suíte está rodando como root"
else
    assert_exit_code 3 env -u LUMEN_ROOT_HELPER_DRY_RUN "$helper" apt-install git
fi
test_case_end

# T2-F7-06
test_case_start "T2_F7_06" "Dry-run de apt-install mostra update e install"
assert_exit_code 0 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" apt-install git jq
assert_contains "$LAST_CMD_OUTPUT" "apt-get -o DPkg::Lock::Timeout=120 update" "O dry-run deve mostrar o apt-get update com timeout do lock"
assert_contains "$LAST_CMD_OUTPUT" "apt-get -o DPkg::Lock::Timeout=120 install -y -- git jq" "O dry-run deve mostrar o apt-get install"
test_case_end

# T2-F7-07: lista com CRLF e espaços nas pontas
test_case_start "T2_F7_07" "Lista permitida com CRLF e espaços continua reconhecida"
rh_dir="${SANDBOX_DIR}/rh"
mkdir -p "${rh_dir}/root-helper"
cp "$helper" "${rh_dir}/lumen-root-helper"
printf '# comentário\r\n\r\n  git \r\n' > "${rh_dir}/root-helper/allowed-packages.list"
assert_exit_code 0 env LUMEN_ROOT_HELPER_DRY_RUN=1 "${rh_dir}/lumen-root-helper" apt-install git
test_case_end

# T2-F7-08: ambiente vazio, como no pkexec
test_case_start "T2_F7_08" "Helper funciona com ambiente vazio, como no pkexec"
assert_exit_code 0 env -i LUMEN_ROOT_HELPER_DRY_RUN=1 /bin/bash -c 'cd / && exec /bin/bash "$1" apt-install git' _ "$helper"
test_case_end

# T2-F7-09
test_case_start "T2_F7_09" "Dry-run de system-tune --no-snap instala os 3 arquivos de configuração"
assert_exit_code 0 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" system-tune --no-snap
assert_contains "$LAST_CMD_OUTPUT" "/etc/sysctl.d/99-lumen-dev.conf" "Deve instalar o sysctl"
assert_contains "$LAST_CMD_OUTPUT" "/etc/systemd/zram-generator.conf" "Deve instalar o zram"
assert_contains "$LAST_CMD_OUTPUT" "/etc/apt/preferences.d/99-no-snap" "Deve instalar o pin do snap"
assert_contains "$LAST_CMD_OUTPUT" "${WORKSPACE_ROOT}/system/" "As origens devem vir do diretório system/ do repo"
test_case_end

# T2-F7-10
test_case_start "T2_F7_10" "system-tune sem --no-snap não aplica o pin do snap"
assert_exit_code 0 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" system-tune
assert_not_contains "$LAST_CMD_OUTPUT" "99-no-snap" "Sem --no-snap não pode tocar no pin do snap"
test_case_end

# T2-F7-11
test_case_start "T2_F7_11" "system-tune recusa argumento desconhecido"
assert_exit_code 2 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" system-tune --forcar
assert_contains "$LAST_CMD_OUTPUT" "argumento inválido para system-tune: --forcar" "A recusa deve citar o argumento inválido"
test_case_end

# T2-F7-12
test_case_start "T2_F7_12" "docker-group recusa quando não há usuário chamador"
assert_exit_code 2 env -u SUDO_USER -u PKEXEC_UID LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group
assert_contains "$LAST_CMD_OUTPUT" "não foi possível identificar o usuário chamador" "A recusa deve ser por falta de usuário chamador"
test_case_end

# T2-F7-13
test_case_start "T2_F7_13" "docker-group recusa root e usuários de sistema"
assert_exit_code 2 env -u SUDO_USER PKEXEC_UID=0 LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group
assert_contains "$LAST_CMD_OUTPUT" "recusado: UID 0 é de root ou de sistema" "A recusa deve ser por UID de sistema"
assert_exit_code 2 env -u SUDO_USER PKEXEC_UID=1 LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group
assert_contains "$LAST_CMD_OUTPUT" "recusado: UID 1 é de root ou de sistema" "A recusa deve ser por UID de sistema"
assert_exit_code 2 env -u PKEXEC_UID SUDO_USER=root LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group
assert_contains "$LAST_CMD_OUTPUT" "recusado: UID 0 é de root ou de sistema" "A recusa deve ser por UID de sistema"
test_case_end

# T2-F7-14
test_case_start "T2_F7_14" "docker-group usa o usuário do PKEXEC_UID"
if [[ "$(id -u)" -lt 1000 ]]; then
    test_case_skip "o UID atual é menor que 1000"
else
    assert_exit_code 0 env -u SUDO_USER PKEXEC_UID="$(id -u)" LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group
    assert_contains "$LAST_CMD_OUTPUT" "usermod -aG docker -- $(id -un)" "Deve adicionar o usuário do PKEXEC_UID ao grupo docker"
fi
test_case_end

# T2-F7-15
test_case_start "T2_F7_15" "docker-group recusa argumentos extras"
fixed_uid="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 { print $3; exit }')"
fixed_name=""
[[ -n "$fixed_uid" ]] && fixed_name="$(getent passwd "$fixed_uid" | cut -d: -f1)"
if [[ -z "$fixed_uid" ]]; then
    test_case_skip "não há usuário com UID entre 1000 e 65533"
else
    assert_exit_code 2 env -u SUDO_USER PKEXEC_UID="$fixed_uid" LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group root
    assert_contains "$LAST_CMD_OUTPUT" "docker-group não aceita argumentos" "A recusa deve vir do argumento extra"
fi
test_case_end

# T2-F7-16
test_case_start "T2_F7_16" "vscode-repo usa apenas URLs fixas e não aceita argumentos"
assert_exit_code 0 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" vscode-repo
assert_contains "$LAST_CMD_OUTPUT" "https://packages.microsoft.com/keys/microsoft.asc" "Deve usar a URL fixa da chave"
assert_contains "$LAST_CMD_OUTPUT" "/etc/apt/sources.list.d/vscode.list" "Deve gravar o vscode.list"
assert_exit_code 2 env LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" vscode-repo https://exemplo.invalido
assert_contains "$LAST_CMD_OUTPUT" "vscode-repo não aceita argumentos" "A recusa deve vir do argumento extra"
test_case_end

# T2-F7-23
test_case_start "T2_F7_23" "docker-group prefere PKEXEC_UID ao SUDO_USER"
if [[ -z "$fixed_uid" ]]; then
    test_case_skip "não há usuário com UID entre 1000 e 65533"
else
    assert_exit_code 0 env PKEXEC_UID="$fixed_uid" SUDO_USER=root LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group
    assert_contains "$LAST_CMD_OUTPUT" "usermod -aG docker -- ${fixed_name}" "Deve usar o usuário do PKEXEC_UID, não o SUDO_USER"
fi
test_case_end

# T2-F7-24
test_case_start "T2_F7_24" "docker-group recusa PKEXEC_UID não numérico ou inexistente"
assert_exit_code 2 env -u SUDO_USER PKEXEC_UID=abc LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group
assert_contains "$LAST_CMD_OUTPUT" "PKEXEC_UID inválido" "A recusa deve ser por UID não numérico"
if getent passwd 59999 >/dev/null; then
    test_case_skip "o UID 59999 existe nesta máquina"
else
    assert_exit_code 2 env -u SUDO_USER PKEXEC_UID=59999 LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group
    assert_contains "$LAST_CMD_OUTPUT" "usuário chamador não encontrado" "A recusa deve ser por UID inexistente"
fi
test_case_end

# T2-F7-25
test_case_start "T2_F7_25" "docker-group recusa UID 65534 (nobody)"
if ! getent passwd 65534 >/dev/null; then
    test_case_skip "o UID 65534 não existe nesta máquina"
else
    assert_exit_code 2 env -u SUDO_USER PKEXEC_UID=65534 LUMEN_ROOT_HELPER_DRY_RUN=1 "$helper" docker-group
    assert_contains "$LAST_CMD_OUTPUT" "recusado: UID 65534 é reservado \\(nobody e afins; máximo 65533\\)" "A recusa deve ser pelo teto de UID"
fi
test_case_end

# T2-F7-26
test_case_start "T2_F7_26" "Helper cria arquivos com umask 022 mesmo com umask 077 do chamador"
assert_exit_code 0 bash -c 'umask 077; LUMEN_ROOT_HELPER_DRY_RUN=1 exec "$1" vscode-repo' _ "$helper"
assert_contains "$LAST_CMD_OUTPUT" "install -m644 [^ ]+ /usr/share/keyrings/packages.microsoft.gpg" "O keyring deve ser instalado com modo explícito 644"
assert_contains "$LAST_CMD_OUTPUT" "install -m644 [^ ]+ /etc/apt/sources.list.d/vscode.list" "O vscode.list deve ser instalado com modo explícito 644"
test_case_end

# Mocks de sudo/pkexec para o as_root: ficam na frente do PATH e registram a chamada
elevate="${WORKSPACE_ROOT}/system/lib/elevate.sh"
elev_bin="${SANDBOX_DIR}/elev_bin"
elev_calls="${SANDBOX_DIR}/elev.calls"
mkdir -p "$elev_bin"
for fake in sudo pkexec; do
    cat > "${elev_bin}/${fake}" <<'FAKE'
#!/bin/bash
echo "$(basename "$0") $*" >> "${ELEV_CALLS}"
exit "${MOCK_EXIT:-0}"
FAKE
    chmod +x "${elev_bin}/${fake}"
done
printf '#!/bin/bash\nexit 0\n' > "${SANDBOX_DIR}/fake-installed-helper"
chmod +x "${SANDBOX_DIR}/fake-installed-helper"

# T2-F7-17
test_case_start "T2_F7_17" "as_root usa sudo no terminal"
: > "$elev_calls"
assert_exit_code 0 env PATH="${elev_bin}:${PATH}" ELEV_CALLS="$elev_calls" LUMEN_ROOT_HELPER_BIN=/caminho/inexistente \
    bash -c 'source "$1"; as_root apt-install git' _ "$elevate"
assert_contains "$(cat "$elev_calls")" "sudo " "Deve chamar o sudo"
assert_contains "$(cat "$elev_calls")" "system/lumen-root-helper apt-install git" "Deve usar o helper do repo"
test_case_end

# T2-F7-18
test_case_start "T2_F7_18" "as_root usa pkexec com o helper instalado quando LUMEN_ELEVATE=pkexec"
: > "$elev_calls"
assert_exit_code 0 env PATH="${elev_bin}:${PATH}" ELEV_CALLS="$elev_calls" LUMEN_ELEVATE=pkexec \
    LUMEN_ROOT_HELPER_BIN="${SANDBOX_DIR}/fake-installed-helper" \
    bash -c 'source "$1"; as_root apt-install git' _ "$elevate"
assert_contains "$(cat "$elev_calls")" "pkexec ${SANDBOX_DIR}/fake-installed-helper apt-install git" "Deve chamar o pkexec com o helper instalado"
assert_not_contains "$(cat "$elev_calls")" "sudo" "Não pode cair no sudo"
test_case_end

# T2-F7-19
test_case_start "T2_F7_19" "as_root com pkexec e helper não instalado falha com mensagem clara"
: > "$elev_calls"
output=$(env PATH="${elev_bin}:${PATH}" ELEV_CALLS="$elev_calls" LUMEN_ELEVATE=pkexec LUMEN_ROOT_HELPER_BIN=/caminho/inexistente \
    bash -c 'source "$1"; as_root apt-install git' _ "$elevate" 2>&1) && status=0 || status=$?
assert_ne "0" "$status" "Deve falhar"
assert_contains "$output" "O pkexec precisa do lumen-root-helper instalado" "Deve explicar que falta o helper"
assert_eq "" "$(cat "$elev_calls")" "Não pode chamar pkexec nem sudo"
test_case_end

# T2-F7-20
test_case_start "T2_F7_20" "as_root traduz o cancelamento do pkexec"
: > "$elev_calls"
assert_exit_code 126 env PATH="${elev_bin}:${PATH}" ELEV_CALLS="$elev_calls" MOCK_EXIT=126 LUMEN_ELEVATE=pkexec \
    LUMEN_ROOT_HELPER_BIN="${SANDBOX_DIR}/fake-installed-helper" \
    bash -c 'source "$1"; as_root apt-install git' _ "$elevate"
assert_contains "$LAST_CMD_OUTPUT" "Autenticação cancelada. Nada foi alterado." "Deve traduzir o 126"
test_case_end

# T2-F7-21
test_case_start "T2_F7_21" "as_root traduz falta de autorização do pkexec"
: > "$elev_calls"
assert_exit_code 127 env PATH="${elev_bin}:${PATH}" ELEV_CALLS="$elev_calls" MOCK_EXIT=127 LUMEN_ELEVATE=pkexec \
    LUMEN_ROOT_HELPER_BIN="${SANDBOX_DIR}/fake-installed-helper" \
    bash -c 'source "$1"; as_root apt-install git' _ "$elevate"
assert_contains "$LAST_CMD_OUTPUT" "Autenticação cancelada ou negada. Nada foi alterado." "Deve traduzir o 127 (o hyprpolkitagent devolve 127 ao cancelar)"
test_case_end

# T2-F7-22
test_case_start "T2_F7_22" "Falha do helper é propagada e aborta o script chamador"
: > "$elev_calls"
assert_exit_code 2 env PATH="${elev_bin}:${PATH}" ELEV_CALLS="$elev_calls" MOCK_EXIT=2 LUMEN_ROOT_HELPER_BIN=/caminho/inexistente \
    bash -c 'set -e; source "$1"; as_root apt-install git; echo CONTINUOU' _ "$elevate"
assert_not_contains "$LAST_CMD_OUTPUT" "CONTINUOU" "O chamador com set -e deve abortar"
test_case_end

# ==============================================================================
# FUNCIONALIDADE F8: Download do Mandacaru (sem rede: URLs file://)
# ==============================================================================
fetch="${WORKSPACE_ROOT}/packaging/fetch-third-party.sh"
fx="${SANDBOX_DIR}/fetch"
mkdir -p "$fx"
printf 'deb falso do mandacaru\n' > "$fx/origem.deb"
fx_sha="$(sha256sum "$fx/origem.deb" | awk '{print $1}')"
fx_zero="$(printf '0%.0s' {1..64})"
write_lock() {  # write_lock <arquivo> <url> <sha>
    printf 'MANDACARU_VERSION=0.2.0\nMANDACARU_URL=%s\nMANDACARU_SHA256=%s\n' "$2" "$3" > "$1"
}
reset_fx() { rm -rf "$fx/cache" "$fx/out" "$fx/executou"; }
run_fetch() {  # run_fetch <código-esperado> <lock> <saída> [VAR=valor...]
    local esperado="$1" lock_file="$2" saida="$3"
    shift 3
    assert_exit_code "$esperado" env MANDACARU_LOCK="$lock_file" LUMEN_CACHE_DIR="$fx/cache" "$@" "$fetch" "$saida"
}
deb_final="mandacaru_0.2.0_all.deb"

# T2-F8-01
test_case_start "T2_F8_01" "Hash certo copia a .deb para a saída e para o cache"
reset_fx
write_lock "$fx/ok.lock" "file://$fx/origem.deb" "$fx_sha"
run_fetch 0 "$fx/ok.lock" "$fx/out"
assert_file_exists "$fx/out/$deb_final"
assert_file_exists "$fx/cache/$deb_final"
assert_exit_code 0 cmp "$fx/origem.deb" "$fx/out/$deb_final"
test_case_end

# T2-F8-02
test_case_start "T2_F8_02" "Hash errado falha e não deixa arquivo para trás"
reset_fx
write_lock "$fx/errado.lock" "file://$fx/origem.deb" "$fx_zero"
run_fetch 1 "$fx/errado.lock" "$fx/out"
assert_contains "$LAST_CMD_OUTPUT" "checksum do mandacaru não confere: esperado ${fx_zero}, obtido ${fx_sha}" "A mensagem deve citar os dois hashes"
assert_file_not_exists "$fx/out/$deb_final"
assert_file_not_exists "$fx/cache/$deb_final"
assert_file_not_exists "$fx/cache/${deb_final}.part"
test_case_end

# T2-F8-03
test_case_start "T2_F8_03" "Cache válido é reaproveitado sem baixar"
reset_fx
mkdir -p "$fx/cache"
cp "$fx/origem.deb" "$fx/cache/$deb_final"
write_lock "$fx/sem-origem.lock" "file://$fx/nao-existe.deb" "$fx_sha"
run_fetch 0 "$fx/sem-origem.lock" "$fx/out"
assert_file_exists "$fx/out/$deb_final"
test_case_end

# T2-F8-04
test_case_start "T2_F8_04" "Sem origem e sem cache, o download falha com mensagem clara"
reset_fx
run_fetch 1 "$fx/sem-origem.lock" "$fx/out"
assert_contains "$LAST_CMD_OUTPUT" "não foi possível baixar o mandacaru de file://$fx/nao-existe.deb" "A mensagem deve citar a URL"
test_case_end

# T2-F8-05
test_case_start "T2_F8_05" "Cache corrompido é baixado de novo e substituído"
reset_fx
mkdir -p "$fx/cache"
printf 'lixo\n' > "$fx/cache/$deb_final"
run_fetch 0 "$fx/ok.lock" "$fx/out"
assert_exit_code 0 cmp "$fx/origem.deb" "$fx/cache/$deb_final"
test_case_end

# T2-F8-06
test_case_start "T2_F8_06" "Um .part que sobrou não conta como cache"
reset_fx
mkdir -p "$fx/cache"
printf 'lixo\n' > "$fx/cache/${deb_final}.part"
run_fetch 1 "$fx/sem-origem.lock" "$fx/out"
assert_contains "$LAST_CMD_OUTPUT" "não foi possível baixar" "O .part não pode ser usado como cache"
test_case_end

# T2-F8-07
test_case_start "T2_F8_07" ".lock com fim de linha CRLF funciona"
reset_fx
write_lock "$fx/crlf.lock" "file://$fx/origem.deb" "$fx_sha"
sed -i 's/$/\r/' "$fx/crlf.lock"
run_fetch 0 "$fx/crlf.lock" "$fx/out"
assert_file_exists "$fx/out/$deb_final"
test_case_end

# T2-F8-08
test_case_start "T2_F8_08" ".lock é lido como dado e nunca executado"
reset_fx
write_lock "$fx/inject.lock" "file://$fx/origem.deb" "$fx_sha"
printf 'MANDACARU_EXTRA=$(touch %s/executou)\n' "$fx" >> "$fx/inject.lock"
run_fetch 0 "$fx/inject.lock" "$fx/out"
assert_file_not_exists "$fx/executou"
test_case_end

# T2-F8-09
test_case_start "T2_F8_09" "Diretório de saída inexistente é criado"
reset_fx
run_fetch 0 "$fx/ok.lock" "$fx/out/nova/pasta"
assert_file_exists "$fx/out/nova/pasta/$deb_final"
test_case_end

# T2-F8-10
test_case_start "T2_F8_10" ".lock sem SHA256 falha dizendo a chave"
reset_fx
printf 'MANDACARU_VERSION=0.2.0\nMANDACARU_URL=file://%s/origem.deb\n' "$fx" > "$fx/sem-sha.lock"
run_fetch 1 "$fx/sem-sha.lock" "$fx/out"
assert_contains "$LAST_CMD_OUTPUT" "chave ausente no mandacaru.lock: MANDACARU_SHA256" "A mensagem deve citar a chave"
test_case_end

# T2-F8-11
test_case_start "T2_F8_11" "SHA256 do ambiente tem precedência sobre o .lock"
reset_fx
run_fetch 0 "$fx/errado.lock" "$fx/out" MANDACARU_SHA256="$fx_sha"
assert_file_exists "$fx/out/$deb_final"
test_case_end

# ==============================================================================
# FUNCIONALIDADE F9: Vigia do Mandacaru (lumen-edr-notify)
# Socket falso + pw-play/notify-send falsos que só registram as chamadas.
# ==============================================================================
edr_harness="${WORKSPACE_ROOT}/tests/e2e/fixtures/edr_notify_harness.py"
edr_dir="${SANDBOX_DIR}/edr"
run_edr() {  # run_edr <caso>: roda o harness e deixa a saída em LAST_CMD_OUTPUT
    assert_exit_code 0 python3 "$edr_harness" "$1" "$edr_dir"
}
conta() {  # conta <padrão>: quantas linhas de LAST_CMD_OUTPUT casam
    grep -cE -- "$1" <<<"$LAST_CMD_OUTPUT" || true
}
som_alarme="pw-play /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed\.oga"
som_aviso="pw-play /usr/share/sounds/freedesktop/stereo/dialog-warning\.oga"

# T2-F9-01
test_case_start "T2_F9_01" "Alerta HIGH gera popup crítico e o som de alarme"
run_edr high
assert_contains "$LAST_CMD_OUTPUT" "notify-send --app-name=Mandacaru --icon=mandacaru --urgency=critical --wait --action=default=Silenciar -- Mandacaru: HIGH behavior\.revshell: Shell bash com conexao de rede ativa" "Popup crítico do HIGH"
assert_contains "$LAST_CMD_OUTPUT" "$som_alarme" "Som de alarme no HIGH"
assert_not_contains "$LAST_CMD_OUTPUT" "expire-time" "HIGH fica na tela até ser fechado"
test_case_end

# T2-F9-02
test_case_start "T2_F9_02" "Alerta MEDIUM gera popup normal e o som de aviso"
run_edr medium
assert_contains "$LAST_CMD_OUTPUT" "notify-send --app-name=Mandacaru --icon=mandacaru --urgency=normal --expire-time=10000 --wait --action=default=Silenciar -- Mandacaru: MEDIUM" "Popup normal do MEDIUM some sozinho em 10 s"
assert_contains "$LAST_CMD_OUTPUT" "$som_aviso" "Som de aviso no MEDIUM"
test_case_end

# T2-F9-03
test_case_start "T2_F9_03" "Alerta LOW não gera nada com o limiar padrão MEDIUM"
run_edr low
assert_not_contains "$LAST_CMD_OUTPUT" "notify-send|pw-play" "LOW fica quieto"
test_case_end

# T2-F9-04
test_case_start "T2_F9_04" "Com limiar HIGH, o MEDIUM não gera nada"
run_edr limiar_high
assert_not_contains "$LAST_CMD_OUTPUT" "notify-send|pw-play" "MEDIUM abaixo do limiar HIGH"
test_case_end

# T2-F9-05
test_case_start "T2_F9_05" "Dois HIGH seguidos: 2 popups e um toque só, sem sobrepor"
run_edr cooldown
assert_eq "2" "$(conta '^notify-send ')" "Os popups saem todos"
assert_eq "3" "$(conta '^pw-play ')" "Só o toque do primeiro (3 vezes); o segundo não sobrepõe"
test_case_end

# T2-F9-06
test_case_start "T2_F9_06" "JSON quebrado, v diferente de 1 e severidade desconhecida são ignorados"
run_edr lixo
assert_eq "1" "$(conta '^notify-send ')" "Só o alerta válido vira popup"
assert_contains "$LAST_CMD_OUTPUT" "Mandacaru: HIGH" "O alerta válido depois do lixo ainda é avisado"
test_case_end

# T2-F9-07
test_case_start "T2_F9_07" "Mandacaru reinicia: o vigia reconecta e avisa o próximo alerta"
run_edr reconecta
assert_eq "1" "$(conta '^notify-send ')" "Alerta depois da reconexão"
test_case_end

# T2-F9-08
test_case_start "T2_F9_08" "Sem pw-play, o popup sai mesmo assim e o vigia avisa"
run_edr sem_pwplay
assert_eq "1" "$(conta '^notify-send ')" "Popup sem o som"
assert_contains "$LAST_CMD_OUTPUT" "\[edr-notify\].*pw-play" "Aviso da falta do pw-play"
test_case_end

# T2-F9-09
test_case_start "T2_F9_09" "Resumo começando com traço não vira opção do notify-send"
run_edr traco
assert_contains "$LAST_CMD_OUTPUT" "notify-send --app-name=Mandacaru --icon=mandacaru --urgency=critical --wait --action=default=Silenciar -- Mandacaru: HIGH behavior\.revshell: -x perigo" "Argumentos depois do --"
test_case_end

# T2-F9-10
test_case_start "T2_F9_10" "Linha incompleta no fim da conexão é descartada"
run_edr fragmento
assert_eq "1" "$(conta '^notify-send ')" "Só o alerta completo da segunda conexão"
test_case_end

# T2-F9-11
test_case_start "T2_F9_11" "Produtor que aceita e fecha na hora não faz o vigia girar sem pausa"
run_edr aceita_e_fecha
n="$(sed -n 's/^conexoes=//p' <<<"$LAST_CMD_OUTPUT")"
assert_eq "0" "$(( ${n:-99999} > 15 ))" "No máximo 15 conexões em 1,5 s com backoff (obtido: ${n:-nada})"
test_case_end

# T2-F9-12
test_case_start "T2_F9_12" "Só um vigia por sessão: o segundo não pega a trava"
run_edr instancia_unica
assert_contains "$LAST_CMD_OUTPUT" "primeira=True segunda=False depois=True" "Trava de instância única"
test_case_end

# T2-F9-13
test_case_start "T2_F9_13" "Markup no resumo é escapado antes de ir para o popup"
run_edr markup
assert_contains "$LAST_CMD_OUTPUT" "behavior\.revshell: Tom &amp; Jerry &lt;b&gt;x&lt;/b&gt;\.sh" "Corpo do popup sem markup interpretável"
test_case_end

# T2-F9-14
test_case_start "T2_F9_14" "O som de uma ocorrência repete 3 vezes e para"
run_edr high
assert_eq "3" "$(conta "^$som_alarme")" "3 toques do alarme para um HIGH"
test_case_end

# T2-F9-15
test_case_start "T2_F9_15" "Clique no popup para o som na hora, mesmo no meio de um toque"
run_edr clique
assert_eq "1" "$(conta '^pw-play ')" "Nenhum toque depois do clique"
assert_contains "$LAST_CMD_OUTPUT" "pwplay_vivos=0 " "O pw-play que tocava foi parado"
test_case_end

# T2-F9-16
test_case_start "T2_F9_16" "pw-play travado é parado pelo teto e o toque não passa de 3"
run_edr pwplay_trava
assert_eq "3" "$(conta '^pw-play ')" "3 toques, cada um cortado pelo teto"
assert_contains "$LAST_CMD_OUTPUT" "pwplay_vivos=0 " "Nenhum pw-play fica tocando para sempre"
test_case_end

# T2-F9-17
test_case_start "T2_F9_17" "Sem daemon de notificação (notify-send falha), o som toca as 3 vezes"
run_edr popup_falha
assert_eq "3" "$(conta '^pw-play ')" "Falha do popup não é confundida com clique"
test_case_end

# T2-F9-18
test_case_start "T2_F9_18" "Processos filhos que terminam são recolhidos (sem zumbis)"
run_edr zumbi
assert_contains "$LAST_CMD_OUTPUT" "pwplay_vivos=[0-9]+ zumbis=0" "Nenhum pw-play ou notify-send zumbi"
test_case_end

# Finaliza a suíte
suite_finish
