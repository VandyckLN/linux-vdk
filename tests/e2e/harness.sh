#!/usr/bin/env bash
# ==============================================================================
# Harness Comum de Testes E2E do Lumen OS (tests/e2e/harness.sh)
# Fornece asserções, estilo ANSI, logs, gerenciamento de sandbox,
# ferramentas de root simuladas, ciclo de vida dos casos de teste e gerador JUnit XML sem dependências.
# ==============================================================================
set -uo pipefail

# Evita que o arquivo seja carregado (source) em duplicidade
if [[ -n "${LUMEN_HARNESS_SOURCED:-}" ]]; then
    return 0
fi
readonly LUMEN_HARNESS_SOURCED=1

# ------------------------------------------------------------------------------
# 1. Estilo do Terminal e Configuração de Cores
# ------------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" && "${COLOR_OUTPUT:-1}" == "1" ]]; then
    readonly CLR_RESET=$'\033[0m'
    readonly CLR_RED=$'\033[0;31m'
    readonly CLR_GREEN=$'\033[0;32m'
    readonly CLR_YELLOW=$'\033[0;33m'
    readonly CLR_BLUE=$'\033[0;34m'
    readonly CLR_CYAN=$'\033[0;36m'
    readonly CLR_WHITE=$'\033[1;37m'
    readonly CLR_BOLD=$'\033[1m'
    readonly CLR_DIM=$'\033[2m'
else
    readonly CLR_RESET=''
    readonly CLR_RED=''
    readonly CLR_GREEN=''
    readonly CLR_YELLOW=''
    readonly CLR_BLUE=''
    readonly CLR_CYAN=''
    readonly CLR_WHITE=''
    readonly CLR_BOLD=''
    readonly CLR_DIM=''
fi

# ------------------------------------------------------------------------------
# 2. Estado Global e Métricas dos Testes
# ------------------------------------------------------------------------------
SUITE_NAME=""
SUITE_START_TIME=0
SUITE_TOTAL=0
SUITE_PASSED=0
SUITE_FAILED=0
SUITE_SKIPPED=0

CURRENT_TEST_ID=""
CURRENT_TEST_DESC=""
CURRENT_TEST_START=0
CURRENT_TEST_FAILED=0
CURRENT_TEST_SKIPPED=0
CURRENT_TEST_SKIP_REASON=""
CURRENT_TEST_FAIL_MSG=""
CURRENT_TEST_OUTPUT=""

# Arrays acumuladores para o relatório JUnit XML
declare -a REPORT_IDS=()
declare -a REPORT_DESCS=()
declare -a REPORT_STATUSES=()   # "PASS", "FAIL", "SKIP"
declare -a REPORT_DURATIONS=()
declare -a REPORT_MESSAGES=()
declare -a REPORT_CLASSES=()

# Variáveis de configuração
VERBOSE=${VERBOSE:-0}
QUIET=${QUIET:-0}
LOG_FILE=${LOG_FILE:-""}
XML_REPORT_FILE=${XML_REPORT_FILE:-""}
LAST_CMD_OUTPUT=""
SANDBOX_DIR=""
MOCK_LOG_DIR=""
ORIGINAL_PATH="${ORIGINAL_PATH:-$PATH}"

# ------------------------------------------------------------------------------
# 3. Subsistema de Logs
# ------------------------------------------------------------------------------
_log_write() {
    local level="$1"
    local color="$2"
    shift 2
    local message="$*"
    local formatted="[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] ${message}"
    
    if [[ "$QUIET" -eq 0 || "$level" == "ERROR" ]]; then
        printf "%s%s%s\n" "${color}" "${formatted}" "${CLR_RESET}"
    fi

    if [[ -n "$LOG_FILE" ]]; then
        printf "%s\n" "${formatted}" >> "$LOG_FILE"
    fi
}

log_info()    { _log_write "INFO"    "${CLR_CYAN}" "$@"; }
log_success() { _log_write "SUCCESS" "${CLR_GREEN}" "$@"; }
log_warn()    { _log_write "WARN"    "${CLR_YELLOW}" "$@"; }
log_error()   { _log_write "ERROR"   "${CLR_RED}" "$@"; }
log_debug()   { if [[ "$VERBOSE" -eq 1 ]]; then _log_write "DEBUG" "${CLR_DIM}" "$@"; fi; }

# ------------------------------------------------------------------------------
# 4. Gerenciamento de Sandbox e Traps
# ------------------------------------------------------------------------------
create_test_sandbox() {
    local prefix="${1:-lumen-e2e}"
    SANDBOX_DIR=$(mktemp -d "/tmp/${prefix}-XXXXXX")
    MOCK_LOG_DIR="${SANDBOX_DIR}/mock_logs"
    mkdir -p "${MOCK_LOG_DIR}"
    export SANDBOX_DIR MOCK_LOG_DIR
    log_debug "Sandbox de teste criada: ${SANDBOX_DIR}"
}

cleanup_test_sandbox() {
    if [[ -n "${ORIGINAL_PATH:-}" && "${PATH}" != "${ORIGINAL_PATH}" ]]; then
        PATH="${ORIGINAL_PATH}"
        export PATH
    fi

    if [[ -n "${SANDBOX_DIR:-}" && -d "${SANDBOX_DIR}" ]]; then
        log_debug "Limpando a sandbox de teste: ${SANDBOX_DIR}"
        rm -rf "${SANDBOX_DIR}"
        SANDBOX_DIR=""
    fi
}

# ------------------------------------------------------------------------------
# 5. Subsistema de Simulação (Mock) de Comandos de Root e do Sistema
# ------------------------------------------------------------------------------
enable_mock_root_tools() {
    local mock_dir="${1:-${SANDBOX_DIR:-/tmp}/mock_bin}"
    mkdir -p "${mock_dir}"
    if [[ -z "${MOCK_LOG_DIR:-}" ]]; then
        MOCK_LOG_DIR="${SANDBOX_DIR:-/tmp}/mock_logs"
    fi
    mkdir -p "${MOCK_LOG_DIR}"

    # Mock: sudo (repassa a chamada sem elevação de root)
    cat << 'EOF' > "${mock_dir}/sudo"
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
    case "$1" in
        -E|-i|-s) shift ;;
        -u) shift 2 ;;
        *) break ;;
    esac
done
exec "$@"
EOF

    # Mock: debootstrap
    cat << 'EOF' > "${mock_dir}/debootstrap"
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG_DIR:-/tmp}/debootstrap.calls"
target=""
for arg in "$@"; do
    if [[ "$arg" != -* && ! "$arg" =~ ^http && "$arg" != "noble" && "$arg" != "resolute" ]]; then
        target="$arg"
    fi
done
if [[ -n "$target" ]]; then
    mkdir -p "$target"/{bin,sbin,etc/apt,usr/bin,var/lib/dpkg}
    echo 'PRETTY_NAME="Ubuntu 26.04 LTS (Resolute Raccoon)"' > "$target/etc/os-release"
    touch "$target/var/lib/dpkg/status"
fi
exit "${MOCK_DEBOOTSTRAP_EXIT:-0}"
EOF

    # Mock: mksquashfs
    cat << 'EOF' > "${mock_dir}/mksquashfs"
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG_DIR:-/tmp}/mksquashfs.calls"
src=""
dest=""
for arg in "$@"; do
    if [[ "$arg" != -* ]]; then
        if [[ -z "$src" ]]; then src="$arg";
        elif [[ -z "$dest" ]]; then dest="$arg"; fi
    fi
done
if [[ -n "$dest" ]]; then
    mkdir -p "$(dirname "$dest")"
    printf "sqsh\x00\x00\x00\x00" > "$dest"
    head -c 512 /dev/zero >> "$dest" 2>/dev/null || true
fi
exit "${MOCK_MKSQUASHFS_EXIT:-0}"
EOF

    # Mock: xorriso
    cat << 'EOF' > "${mock_dir}/xorriso"
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG_DIR:-/tmp}/xorriso.calls"
iso_out=""
prev=""
for arg in "$@"; do
    if [[ "$prev" == "-o" || "$prev" == "-output" ]]; then
        iso_out="$arg"
    fi
    prev="$arg"
done
if [[ -n "$iso_out" ]]; then
    mkdir -p "$(dirname "$iso_out")"
    printf "CD001" > "$iso_out"
    head -c 2048 /dev/zero >> "$iso_out" 2>/dev/null || true
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$(dirname "$iso_out")" && sha256sum "$(basename "$iso_out")" > "$(basename "$iso_out").sha256")
    fi
fi
exit "${MOCK_XORRISO_EXIT:-0}"
EOF

    # Mock: qemu-system-x86_64
    cat << 'EOF' > "${mock_dir}/qemu-system-x86_64"
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG_DIR:-/tmp}/qemu.calls"
exit "${MOCK_QEMU_EXIT:-0}"
EOF

    # Mock: qemu-img
    cat << 'EOF' > "${mock_dir}/qemu-img"
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG_DIR:-/tmp}/qemu-img.calls"
# Se estiver criando um disco, cria um arquivo fictício
if [[ "$1" == "create" ]]; then
    disk_file="${@: -2:1}"
    if [[ "$disk_file" == -* ]]; then disk_file="${@: -1}"; fi
    mkdir -p "$(dirname "$disk_file")" 2>/dev/null || true
    touch "$disk_file" 2>/dev/null || true
fi
exit 0
EOF

    # Mock: chroot (hermético: registra a invocação e sai com 0 sem executar comandos do host)
    cat << 'EOF' > "${mock_dir}/chroot"
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG_DIR:-/tmp}/chroot.calls"
exit 0
EOF

    # Mock: mount e umount
    cat << 'EOF' > "${mock_dir}/mount"
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG_DIR:-/tmp}/mount.calls"
exit 0
EOF
    cat << 'EOF' > "${mock_dir}/umount"
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG_DIR:-/tmp}/umount.calls"
exit 0
EOF

    # Mock: losetup
    cat << 'EOF' > "${mock_dir}/losetup"
#!/usr/bin/env bash
echo "$@" >> "${MOCK_LOG_DIR:-/tmp}/losetup.calls"
if [[ "$1" == "-f" || "$1" == "--find" ]]; then
    echo "/dev/loop99"
fi
exit 0
EOF

    chmod +x "${mock_dir}"/*
    export ORIGINAL_PATH="${ORIGINAL_PATH:-$PATH}"
    export PATH="${mock_dir}:${PATH}"
    log_debug "Ferramentas de root simuladas ativadas em: ${mock_dir}"
}

disable_mock_root_tools() {
    if [[ -n "${ORIGINAL_PATH:-}" ]]; then
        export PATH="${ORIGINAL_PATH}"
        log_debug "Ferramentas de root simuladas desativadas; PATH restaurado."
    fi
}

mock_assert_called() {
    local cmd="$1"
    local msg="${2:-Esperava-se que o comando '${cmd}' tivesse sido invocado}"
    local call_file="${MOCK_LOG_DIR}/${cmd}.calls"
    if [[ ! -s "$call_file" ]]; then
        _record_fail "${msg}: '${cmd}' nunca foi chamado"
        return 1
    fi
    return 0
}

mock_assert_called_with() {
    local cmd="$1"
    local pattern="$2"
    local msg="${3:-Esperava-se que o comando '${cmd}' fosse chamado com o padrão '${pattern}'}"
    local call_file="${MOCK_LOG_DIR}/${cmd}.calls"
    if [[ ! -f "$call_file" ]] || ! grep -qE -- "$pattern" "$call_file"; then
        _record_fail "${msg}: padrão '${pattern}' não encontrado nas chamadas de ${cmd}"
        return 1
    fi
    return 0
}

mock_get_calls() {
    local cmd="$1"
    local call_file="${MOCK_LOG_DIR}/${cmd}.calls"
    if [[ -f "$call_file" ]]; then
        cat "$call_file"
    fi
}

mock_get_call_count() {
    local cmd="$1"
    local call_file="${MOCK_LOG_DIR}/${cmd}.calls"
    if [[ -f "$call_file" ]]; then
        wc -l < "$call_file" | tr -d ' '
    else
        echo 0
    fi
}

# ------------------------------------------------------------------------------
# 6. Ciclo de Vida da Suíte e dos Casos de Teste
# ------------------------------------------------------------------------------
suite_init() {
    SUITE_NAME="$1"
    SUITE_START_TIME=${EPOCHREALTIME:-$(date +%s)}
    SUITE_TOTAL=0
    SUITE_PASSED=0
    SUITE_FAILED=0
    SUITE_SKIPPED=0
    
    if [[ "$QUIET" -eq 0 ]]; then
        printf "\n%s======================================================================%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"
        printf "%s  %s%s\n" "${CLR_BOLD}${CLR_WHITE}" "${SUITE_NAME}" "${CLR_RESET}"
        printf "%s======================================================================%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"
    fi
}

test_case_start() {
    CURRENT_TEST_ID="$1"
    CURRENT_TEST_DESC="${2:-}"
    CURRENT_TEST_START=${EPOCHREALTIME:-$(date +%s)}
    CURRENT_TEST_FAILED=0
    CURRENT_TEST_SKIPPED=0
    CURRENT_TEST_SKIP_REASON=""
    CURRENT_TEST_FAIL_MSG=""
    CURRENT_TEST_OUTPUT=""

    ((SUITE_TOTAL++))
    if [[ "$VERBOSE" -eq 1 ]]; then
        printf "  %s>>> EXECUTANDO: [%s] %s%s\n" "${CLR_DIM}" "${CURRENT_TEST_ID}" "${CURRENT_TEST_DESC}" "${CLR_RESET}"
    fi
}

# Alias para test_case_start
test_start() {
    local name="$1"
    local desc="${2:-$name}"
    test_case_start "$name" "$desc"
}

_record_fail() {
    CURRENT_TEST_FAILED=1
    CURRENT_TEST_FAIL_MSG="$1"
}

test_case_fail() {
    local msg="${1:-Teste falhou}"
    _record_fail "$msg"
}

test_fail() {
    test_case_fail "$@"
}

test_case_skip() {
    local reason="${1:-Ignorado}"
    CURRENT_TEST_SKIPPED=1
    CURRENT_TEST_SKIP_REASON="$reason"
}

test_skip() {
    test_case_skip "$@"
}

test_case_pass() {
    # No-op if not already failed
    :
}

test_pass() {
    test_case_pass "$@"
    test_case_end
}

test_case_end() {
    local end_time=${EPOCHREALTIME:-$(date +%s)}
    local duration
    duration=$(awk -v s="${CURRENT_TEST_START}" -v e="${end_time}" 'BEGIN {printf "%.3f", e - s}')
    local class_name="${SUITE_NAME// /_}"

    REPORT_IDS+=("${CURRENT_TEST_ID}")
    REPORT_DESCS+=("${CURRENT_TEST_DESC}")
    REPORT_CLASSES+=("${class_name}")
    REPORT_DURATIONS+=("${duration}")

    if [[ "$CURRENT_TEST_SKIPPED" -eq 1 ]]; then
        ((SUITE_SKIPPED++))
        REPORT_STATUSES+=("SKIP")
        REPORT_MESSAGES+=("${CURRENT_TEST_SKIP_REASON}")
        if [[ "$QUIET" -eq 0 ]]; then
            printf "  %s[SKIP]%s %s: %s %s(%s)%s\n" \
                "${CLR_YELLOW}${CLR_BOLD}" "${CLR_RESET}" \
                "${CURRENT_TEST_ID}" "${CURRENT_TEST_DESC}" \
                "${CLR_DIM}" "${CURRENT_TEST_SKIP_REASON}" "${CLR_RESET}"
        fi
    elif [[ "$CURRENT_TEST_FAILED" -eq 1 ]]; then
        ((SUITE_FAILED++))
        REPORT_STATUSES+=("FAIL")
        REPORT_MESSAGES+=("${CURRENT_TEST_FAIL_MSG}")
        printf "  %s[FAIL]%s %s: %s\n" \
            "${CLR_RED}${CLR_BOLD}" "${CLR_RESET}" \
            "${CURRENT_TEST_ID}" "${CURRENT_TEST_DESC}"
        printf "         %s-> %s%s\n" "${CLR_RED}" "${CURRENT_TEST_FAIL_MSG}" "${CLR_RESET}"
    else
        ((SUITE_PASSED++))
        REPORT_STATUSES+=("PASS")
        REPORT_MESSAGES+=("")
        if [[ "$QUIET" -eq 0 ]]; then
            printf "  %s[PASS]%s %s: %s %s(%ss)%s\n" \
                "${CLR_GREEN}${CLR_BOLD}" "${CLR_RESET}" \
                "${CURRENT_TEST_ID}" "${CURRENT_TEST_DESC}" \
                "${CLR_DIM}" "${duration}" "${CLR_RESET}"
        fi
    fi
}

suite_finish() {
    local end_time=${EPOCHREALTIME:-$(date +%s)}
    local total_duration
    total_duration=$(awk -v s="${SUITE_START_TIME}" -v e="${end_time}" 'BEGIN {printf "%.2f", e - s}')

    printf "%s----------------------------------------------------------------------%s\n" "${CLR_CYAN}" "${CLR_RESET}"
    printf "%s  Resumo da Suíte: %s%s\n" "${CLR_BOLD}" "${SUITE_NAME}" "${CLR_RESET}"
    printf "    Total de Testes: %s%d%s\n" "${CLR_BOLD}" "${SUITE_TOTAL}" "${CLR_RESET}"
    printf "    Aprovados:       %s%d%s\n" "${CLR_GREEN}" "${SUITE_PASSED}" "${CLR_RESET}"
    printf "    Falharam:        %s%d%s\n" "${CLR_RED}" "${SUITE_FAILED}" "${CLR_RESET}"
    printf "    Ignorados:       %s%d%s\n" "${CLR_YELLOW}" "${SUITE_SKIPPED}" "${CLR_RESET}"
    printf "    Duração:         %ss\n" "${total_duration}"
    printf "%s======================================================================%s\n" "${CLR_CYAN}" "${CLR_RESET}"

    if [[ -n "$XML_REPORT_FILE" ]]; then
        generate_junit_xml "$XML_REPORT_FILE" "$total_duration"
    fi

    if [[ "$SUITE_FAILED" -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Alias para suite_finish com título personalizado
print_tier_summary() {
    suite_finish
}

# ------------------------------------------------------------------------------
# 7. Biblioteca de Funções de Asserção
# ------------------------------------------------------------------------------

assert_file_exists() {
    local file="$1"
    local msg="${2:-Asserção falhou: Esperava-se que o arquivo existisse}"
    if [[ ! -f "$file" ]]; then
        _record_fail "${msg} -> Arquivo regular ausente: ${file}"
        return 1
    fi
    return 0
}

assert_file_not_exists() {
    local file="$1"
    local msg="${2:-Asserção falhou: Esperava-se que o arquivo NÃO existisse}"
    if [[ -e "$file" ]]; then
        _record_fail "${msg} -> Arquivo inesperado existe: ${file}"
        return 1
    fi
    return 0
}

assert_dir_exists() {
    local dir="$1"
    local msg="${2:-Asserção falhou: Esperava-se que o diretório existisse}"
    if [[ ! -d "$dir" ]]; then
        _record_fail "${msg} -> Diretório ausente: ${dir}"
        return 1
    fi
    return 0
}

assert_dir_not_exists() {
    local dir="$1"
    local msg="${2:-Asserção falhou: Esperava-se que o diretório NÃO existisse}"
    if [[ -d "$dir" ]]; then
        _record_fail "${msg} -> Diretório inesperado existe: ${dir}"
        return 1
    fi
    return 0
}

assert_file_executable() {
    local file="$1"
    local msg="${2:-Asserção falhou: Esperava-se que o arquivo fosse executável}"
    if [[ ! -x "$file" ]]; then
        _record_fail "${msg} -> Arquivo não é executável: ${file}"
        return 1
    fi
    return 0
}

assert_file_not_empty() {
    local file="$1"
    local msg="${2:-Asserção falhou: Esperava-se que o arquivo não estivesse vazio}"
    if [[ ! -s "$file" ]]; then
        _record_fail "${msg} -> Arquivo ausente ou vazio (0 bytes): ${file}"
        return 1
    fi
    return 0
}

assert_file_size_gt() {
    local file="$1"
    local min_bytes="$2"
    local msg="${3:-Asserção falhou: Tamanho do arquivo abaixo do limite}"
    if [[ ! -f "$file" ]]; then
        _record_fail "${msg} -> Arquivo não encontrado: ${file}"
        return 1
    fi
    local size
    size=$(wc -c < "$file" | tr -d ' ')
    if [[ "$size" -le "$min_bytes" ]]; then
        _record_fail "${msg} -> Tamanho do arquivo ${file} (${size}B) <= limite (${min_bytes}B)"
        return 1
    fi
    return 0
}

assert_contains() {
    local target="$1"
    local pattern="$2"
    local msg="${3:-Asserção falhou: Padrão não encontrado}"
    if [[ -f "$target" ]]; then
        if ! grep -qE -- "$pattern" "$target"; then
            _record_fail "${msg} -> Padrão '${pattern}' não encontrado no arquivo '${target}'"
            return 1
        fi
    else
        if [[ ! "$target" =~ $pattern ]]; then
            _record_fail "${msg} -> Padrão '${pattern}' não encontrado na string"
            return 1
        fi
    fi
    return 0
}

# Alias com ordem de parâmetros (padrão, arquivo)
assert_file_contains() {
    local pattern="$1"
    local file="$2"
    local msg="${3:-Asserção falhou: Padrão não encontrado no arquivo}"
    assert_contains "$file" "$pattern" "$msg"
}

assert_not_contains() {
    local target="$1"
    local pattern="$2"
    local msg="${3:-Asserção falhou: Padrão proibido encontrado}"
    if [[ -f "$target" ]]; then
        if grep -qE -- "$pattern" "$target"; then
            _record_fail "${msg} -> Padrão proibido '${pattern}' encontrado no arquivo '${target}'"
            return 1
        fi
    else
        if [[ "$target" =~ $pattern ]]; then
            _record_fail "${msg} -> Padrão proibido '${pattern}' encontrado na string"
            return 1
        fi
    fi
    return 0
}

assert_matches_regex() {
    local string="$1"
    local regex="$2"
    local msg="${3:-Asserção falhou: Regex não corresponde}"
    if [[ ! "$string" =~ $regex ]]; then
        _record_fail "${msg} -> String não corresponde à regex '${regex}'"
        return 1
    fi
    return 0
}

# Alias com ordem de parâmetros (regex, string)
assert_match() {
    local regex="$1"
    local string="$2"
    local msg="${3:-Asserção falhou: Falha na correspondência da regex}"
    assert_matches_regex "$string" "$regex" "$msg"
}

assert_exit_code() {
    local expected="$1"
    shift
    local cmd=("$@")
    local output
    local status=0

    output=$("${cmd[@]}" 2>&1) || status=$?
    LAST_CMD_OUTPUT="$output"

    if [[ "$status" -ne "$expected" ]]; then
        _record_fail "Código de saída esperado ${expected}, mas obtido ${status} ao executar: ${cmd[*]} (Saída: ${output:0:200})"
        return 1
    fi
    return 0
}

assert_command_output_contains() {
    local pattern="$1"
    shift
    local cmd=("$@")
    local output
    output=$("${cmd[@]}" 2>&1) || true
    LAST_CMD_OUTPUT="$output"
    if [[ ! "$output" =~ $pattern ]]; then
        _record_fail "A saída do comando não corresponde ao padrão '${pattern}'. Executado: ${cmd[*]}"
        return 1
    fi
    return 0
}

assert_command_output_not_contains() {
    local pattern="$1"
    shift
    local cmd=("$@")
    local output
    output=$("${cmd[@]}" 2>&1) || true
    LAST_CMD_OUTPUT="$output"
    if [[ "$output" =~ $pattern ]]; then
        _record_fail "Padrão proibido '${pattern}' encontrado na saída do comando. Executado: ${cmd[*]}"
        return 1
    fi
    return 0
}

assert_syntax_valid() {
    local file="$1"
    local lang="${2:-auto}"

    if [[ ! -f "$file" ]]; then
        _record_fail "Não foi possível validar a sintaxe: arquivo não encontrado: ${file}"
        return 1
    fi

    if [[ "$lang" == "auto" ]]; then
        case "$file" in
            *.sh|*.bash) lang="sh" ;;
            *.py)        lang="py" ;;
            *.json)      lang="json" ;;
            *.yml|*.yaml)lang="yaml" ;;
            *.conf|*.ini|*.desc) lang="ini" ;;
            *.qss|*.css) lang="css" ;;
            *) lang="sh" ;;
        esac
    fi

    case "$lang" in
        sh|bash)
            local err
            if ! err=$(bash -n "$file" 2>&1); then
                _record_fail "Erro de sintaxe Bash em ${file}: ${err}"
                return 1
            fi
            ;;
        py|python)
            local err
            if ! err=$(python3 -m py_compile "$file" 2>&1); then
                _record_fail "Erro de sintaxe Python em ${file}: ${err}"
                return 1
            fi
            ;;
        json)
            local err
            if ! err=$(python3 -m json.tool "$file" > /dev/null 2>&1); then
                _record_fail "Erro de sintaxe JSON em ${file}: ${err}"
                return 1
            fi
            ;;
        yaml|yml)
            local err
            if ! err=$(python3 -c "import yaml; yaml.safe_load(open('$file', 'r'))" 2>&1); then
                _record_fail "Erro de sintaxe YAML em ${file}: ${err}"
                return 1
            fi
            ;;
        ini|conf|desc)
            if [[ ! -s "$file" ]]; then
                _record_fail "Arquivo de configuração vazio: ${file}"
                return 1
            fi
            ;;
        css|qss)
            local open_b close_b
            open_b=$(grep -o '{' "$file" | wc -l)
            close_b=$(grep -o '}' "$file" | wc -l)
            if [[ "$open_b" -ne "$close_b" ]]; then
                _record_fail "Chaves desbalanceadas na folha de estilo ${file}: {=${open_b}, }=${close_b}"
                return 1
            fi
            ;;
    esac
    return 0
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-Asserção falhou: Valores diferentes}"
    if [[ "$expected" != "$actual" ]]; then
        _record_fail "${msg} -> Esperado: '${expected}', Obtido: '${actual}'"
        return 1
    fi
    return 0
}

assert_ne() {
    local unexpected="$1"
    local actual="$2"
    local msg="${3:-Asserção falhou: Esperava-se que os valores fossem diferentes}"
    if [[ "$unexpected" == "$actual" ]]; then
        _record_fail "${msg} -> Correspondência inesperada: '${actual}'"
        return 1
    fi
    return 0
}

assert_ge() {
    local val1="$1"
    local val2="$2"
    local msg="${3:-Asserção falhou: Esperava-se val1 >= val2}"
    if [[ "$val1" -lt "$val2" ]]; then
        _record_fail "${msg} -> ${val1} < ${val2}"
        return 1
    fi
    return 0
}

assert_gt() {
    local val1="$1"
    local val2="$2"
    local msg="${3:-Asserção falhou: Esperava-se val1 > val2}"
    if [[ "$val1" -le "$val2" ]]; then
        _record_fail "${msg} -> ${val1} <= ${val2}"
        return 1
    fi
    return 0
}

assert_symlink_points_to() {
    local symlink="$1"
    local expected="$2"
    local msg="${3:-Asserção falhou: Destino do symlink diverge}"
    if [[ ! -L "$symlink" ]]; then
        _record_fail "${msg} -> O caminho não é um symlink: ${symlink}"
        return 1
    fi
    local actual
    actual=$(readlink "$symlink")
    if [[ "$actual" != "$expected" ]]; then
        _record_fail "${msg} -> O symlink aponta para '${actual}', esperado '${expected}'"
        return 1
    fi
    return 0
}

assert_json_key_value() {
    local json_file="$1"
    local key="$2"
    local expected="$3"
    local msg="${4:-Asserção falhou: Valor JSON diverge}"
    if [[ ! -f "$json_file" ]]; then
        _record_fail "${msg} -> Arquivo JSON ausente: ${json_file}"
        return 1
    fi
    local actual
    actual=$(python3 -c "import json; d=json.load(open('$json_file')); print(d.get('$key', ''))" 2>/dev/null)
    if [[ "$actual" != "$expected" ]]; then
        _record_fail "${msg} -> Chave '${key}': esperado '${expected}', obtido '${actual}'"
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# 8. Geração e Agregação de JUnit XML sem Dependências
# ------------------------------------------------------------------------------
_xml_escape() {
    local str="$1"
    local restore_patsub=0
    if shopt -q patsub_replacement 2>/dev/null; then
        restore_patsub=1
        shopt -u patsub_replacement 2>/dev/null || true
    fi
    str="${str//&/&amp;}"
    str="${str//</&lt;}"
    str="${str//>/&gt;}"
    str="${str//\"/&quot;}"
    str="${str//\'/&apos;}"
    if [[ "$restore_patsub" -eq 1 ]]; then
        shopt -s patsub_replacement 2>/dev/null || true
    fi
    printf "%s" "$str"
}

generate_junit_xml() {
    local out_file="$1"
    local duration="${2:-0.00}"
    mkdir -p "$(dirname "$out_file")"

    local esc_suite_name
    esc_suite_name=$(_xml_escape "${SUITE_NAME}")

    cat << EOF > "$out_file"
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="LumenOS_E2E" tests="${SUITE_TOTAL}" failures="${SUITE_FAILED}" errors="0" skipped="${SUITE_SKIPPED}" time="${duration}">
  <testsuite name="${esc_suite_name}" tests="${SUITE_TOTAL}" failures="${SUITE_FAILED}" errors="0" skipped="${SUITE_SKIPPED}" time="${duration}">
EOF

    local i
    for ((i=0; i<${#REPORT_IDS[@]}; i++)); do
        local id="${REPORT_IDS[$i]}"
        local desc="${REPORT_DESCS[$i]}"
        local class="${REPORT_CLASSES[$i]}"
        local status="${REPORT_STATUSES[$i]}"
        local t="${REPORT_DURATIONS[$i]}"
        local msg="${REPORT_MESSAGES[$i]}"

        local esc_name
        esc_name=$(_xml_escape "${id}: ${desc}")
        local esc_class
        esc_class=$(_xml_escape "${class}")

        if [[ "$status" == "PASS" ]]; then
            printf '    <testcase name="%s" classname="%s" time="%s" />\n' \
                "$esc_name" "$esc_class" "$t" >> "$out_file"
        elif [[ "$status" == "SKIP" ]]; then
            local esc_msg
            esc_msg=$(_xml_escape "$msg")
            printf '    <testcase name="%s" classname="%s" time="%s">\n      <skipped message="%s" />\n    </testcase>\n' \
                "$esc_name" "$esc_class" "$t" "$esc_msg" >> "$out_file"
        else
            local esc_msg
            esc_msg=$(_xml_escape "$msg")
            printf '    <testcase name="%s" classname="%s" time="%s">\n      <failure message="%s" type="AssertionFailure"><![CDATA[%s]]></failure>\n    </testcase>\n' \
                "$esc_name" "$esc_class" "$t" "$esc_msg" "$msg" >> "$out_file"
        fi
    done

    cat << EOF >> "$out_file"
  </testsuite>
</testsuites>
EOF
    log_debug "Relatório JUnit XML gerado em: ${out_file}"
}

aggregate_junit_xml() {
    local out_file="$1"
    shift
    local input_files=("$@")

    if [[ ${#input_files[@]} -eq 0 ]]; then
        log_warn "aggregate_junit_xml: No input XML reports provided."
        return 0
    fi

    mkdir -p "$(dirname "$out_file")"

    python3 - "${out_file}" "${input_files[@]}" << 'PYEOF'
import sys
import xml.etree.ElementTree as ET

out_file = sys.argv[1]
in_files = sys.argv[2:]

root = ET.Element("testsuites", {
    "name": "LumenOS_E2E",
    "tests": "0",
    "failures": "0",
    "errors": "0",
    "skipped": "0",
    "time": "0.00"
})

total_tests = 0
total_failures = 0
total_errors = 0
total_skipped = 0
total_time = 0.0

for path in in_files:
    try:
        tree = ET.parse(path)
        doc_root = tree.getroot()
        suites = doc_root.findall('./testsuite') if doc_root.tag == 'testsuites' else ([doc_root] if doc_root.tag == 'testsuite' else doc_root.findall('.//testsuite'))
        for suite in suites:
            total_tests += int(suite.get('tests', 0))
            total_failures += int(suite.get('failures', 0))
            total_errors += int(suite.get('errors', 0))
            total_skipped += int(suite.get('skipped', 0))
            try:
                total_time += float(suite.get('time', 0.0))
            except (ValueError, TypeError):
                pass
            root.append(suite)
    except Exception as e:
        print(f"Aviso: falha ao agregar o XML de {path}: {e}", file=sys.stderr)

root.set("tests", str(total_tests))
root.set("failures", str(total_failures))
root.set("errors", str(total_errors))
root.set("skipped", str(total_skipped))
root.set("time", f"{total_time:.2f}")

if hasattr(ET, "indent"):
    ET.indent(root, space="  ", level=0)

tree = ET.ElementTree(root)
tree.write(out_file, encoding="utf-8", xml_declaration=True)
PYEOF

    log_debug "Relatório JUnit XML agregado gerado em: ${out_file}"
}
