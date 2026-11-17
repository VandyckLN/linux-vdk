#!/usr/bin/env bash
# ==============================================================================
# Executor Mestre de Testes E2E do Lumen OS (tests/e2e/run-e2e-tests.sh)
# Despachante mestre das suítes de testes de integração de ponta a ponta multinível.
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${WORKSPACE_ROOT}"

# Parâmetros padrão
TIER="all"
VERBOSE=0
QUIET=0
LOG_FILE=""
XML_REPORT_FILE="${SCRIPT_DIR}/reports/e2e-results.xml"
DRY_RUN=0

# Imprime as informações de uso
usage() {
    cat << EOF
Executor Unificado de Testes E2E do Lumen OS

Uso:
  bash tests/e2e/run-e2e-tests.sh [OPTIONS]

Opções:
  --tier <1|2|3|4|all>   Seleciona o tier de testes a executar (padrão: all)
                         1: Cobertura de Funcionalidades (≥30 testes)
                         2: Casos de Limite e de Canto (≥30 testes)
                         3: Integração Entre Funcionalidades (≥6 testes)
                         4: Cenários de Uso Real (≥5 testes)
  -v, --verbose          Ativa logs detalhados dos testes e mensagens de depuração
  -q, --quiet            Modo silencioso, exibe apenas o resumo mínimo dos resultados
  -l, --log <arquivo>    Grava o log detalhado de execução no caminho indicado
  -x, --xml <arquivo>    Gera relatório JUnit XML (padrão: tests/e2e/reports/e2e-results.xml)
  --no-color             Desativa a formatação de cores ANSI
  --dry-run              Verifica o ambiente e os arquivos de teste sem executar asserções
  -h, --help             Mostra esta ajuda e sai com código 0

Códigos de Saída:
  0: Todos os testes passaram com sucesso
  1: Uma ou mais asserções falharam
  2: Argumento de CLI inválido ou falha crítica de ambiente
EOF
    exit 0
}

# Interpreta as opções da CLI
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)
            if [[ -z "${2:-}" ]]; then echo "Erro: --tier exige um argumento" >&2; exit 2; fi
            TIER="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        -l|--log)
            if [[ -z "${2:-}" ]]; then echo "Erro: --log exige um caminho de arquivo" >&2; exit 2; fi
            LOG_FILE="$2"
            shift 2
            ;;
        -x|--xml)
            if [[ -z "${2:-}" ]]; then echo "Erro: --xml exige um caminho de arquivo" >&2; exit 2; fi
            XML_REPORT_FILE="$2"
            shift 2
            ;;
        --no-color)
            export NO_COLOR=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Erro: opção não reconhecida: $1" >&2
            echo "Execute 'bash tests/e2e/run-e2e-tests.sh --help' para ver o uso." >&2
            exit 2
            ;;
    esac
done

# Valida a seleção de tier
case "$TIER" in
    1|2|3|4|all) ;;
    *)
        echo "Erro: tier inválido '${TIER}'. Deve ser 1, 2, 3, 4 ou all." >&2
        exit 2
        ;;
esac

# Carrega o harness comum de testes
if [[ ! -f "${SCRIPT_DIR}/harness.sh" ]]; then
    echo "Erro Crítico: biblioteca do harness não encontrada em ${SCRIPT_DIR}/harness.sh" >&2
    exit 2
fi

# Exporta os parâmetros para os scripts filhos de cada tier
MASTER_XML_REPORT_FILE="${XML_REPORT_FILE}"
XML_REPORT_DIR="$(dirname "${MASTER_XML_REPORT_FILE}")"
mkdir -p "${XML_REPORT_DIR}"
export VERBOSE QUIET LOG_FILE XML_REPORT_FILE DRY_RUN
source "${SCRIPT_DIR}/harness.sh"

# Verificação prévia do ambiente
verify_prerequisites() {
    log_debug "Verificando os pré-requisitos do ambiente..."
    local missing=0
    for cmd in bash python3 grep sed awk mktemp find; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Comando essencial do sistema ausente: $cmd"
            missing=1
        fi
    done
    if [[ "$missing" -eq 1 ]]; then
        log_error "Falha na verificação do ambiente. Ferramentas obrigatórias ausentes."
        exit 2
    fi
}
verify_prerequisites

# Cria a sandbox do executor global
create_test_sandbox "lumen-e2e-master"
enable_mock_root_tools

# Handlers de limpeza e de traps de sinais
cleanup_all() {
    disable_mock_root_tools
    cleanup_test_sandbox
}

handle_sigint() {
    log_warn "Interrompido por SIGINT (Ctrl+C). Limpando e saindo..."
    cleanup_all
    exit 130
}

handle_sigterm() {
    log_warn "Interrompido por SIGTERM. Limpando e saindo..."
    cleanup_all
    exit 1
}

trap cleanup_all EXIT
trap handle_sigint INT
trap handle_sigterm TERM

# Contadores gerais entre os tiers
MASTER_START_TIME=${EPOCHREALTIME:-$(date +%s)}
TOTAL_TIERS_RUN=0
TOTAL_TIERS_FAILED=0

execute_tier() {
    local tier_num="$1"
    local script_name="$2"
    local tier_xml="$3"
    local full_path="${SCRIPT_DIR}/${script_name}"

    if [[ ! -f "$full_path" ]]; then
        log_warn "Script de testes do Tier ${tier_num} não encontrado: ${script_name} (Planejado)"
        return 0
    fi

    ((TOTAL_TIERS_RUN++))
    log_info "Executando o Tier ${tier_num}: ${script_name}..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "Modo dry-run: Tier ${tier_num} verificado."
        return 0
    fi

    local tier_status=0
    # Executa em subshell para preservar o isolamento e emitir o XML de cada tier
    (
        export LUMEN_RUN_TIER="${tier_num}"
        export XML_REPORT_FILE="${tier_xml}"
        bash "${full_path}"
    ) || tier_status=$?

    if [[ "$tier_status" -ne 0 ]]; then
        ((TOTAL_TIERS_FAILED++))
        log_error "Tier ${tier_num} falhou com código de saída: ${tier_status}"
    else
        log_success "Tier ${tier_num} passou sem erros."
    fi
    return "$tier_status"
}

# Determina os tiers a executar
TIERS_TO_RUN=()
case "$TIER" in
    1) TIERS_TO_RUN+=( "1:tier1_feature_coverage.sh" ) ;;
    2) TIERS_TO_RUN+=( "2:tier2_boundary_corner.sh" ) ;;
    3) TIERS_TO_RUN+=( "3:tier3_cross_feature.sh" ) ;;
    4) TIERS_TO_RUN+=( "4:tier4_real_world.sh" ) ;;
    all)
        TIERS_TO_RUN+=(
            "1:tier1_feature_coverage.sh"
            "2:tier2_boundary_corner.sh"
            "3:tier3_cross_feature.sh"
            "4:tier4_real_world.sh"
        )
        ;;
esac

# Executa os tiers
FINAL_EXIT_CODE=0
declare -a GENERATED_TIER_XMLS=()

for entry in "${TIERS_TO_RUN[@]}"; do
    IFS=":" read -r t_num t_script <<< "$entry"
    t_xml="${XML_REPORT_DIR}/tier${t_num}-results.xml"
    rm -f "$t_xml"
    tier_status=0
    execute_tier "$t_num" "$t_script" "$t_xml" || tier_status=$?
    if [[ "$tier_status" -ne 0 ]]; then
        FINAL_EXIT_CODE=1
        if [[ "$tier_status" -eq 130 || "$tier_status" -eq 143 ]]; then
            log_warn "Tier ${t_num} recebeu sinal de término (${tier_status}). Abortando a execução."
            exit "$tier_status"
        fi
    fi
    if [[ -f "$t_xml" ]]; then
        GENERATED_TIER_XMLS+=( "$t_xml" )
    fi
done

# Agrega os relatórios XML de cada tier no relatório XML mestre
if [[ "$DRY_RUN" -eq 0 && "${#GENERATED_TIER_XMLS[@]}" -gt 0 && -n "${MASTER_XML_REPORT_FILE}" ]]; then
    log_info "Agregando ${#GENERATED_TIER_XMLS[@]} relatório(s) de tier em ${MASTER_XML_REPORT_FILE}..."
    aggregate_junit_xml "${MASTER_XML_REPORT_FILE}" "${GENERATED_TIER_XMLS[@]}"
fi

MASTER_END_TIME=${EPOCHREALTIME:-$(date +%s)}
MASTER_DURATION=$(awk -v s="${MASTER_START_TIME}" -v e="${MASTER_END_TIME}" 'BEGIN {printf "%.2f", e - s}')

# Banner do Resumo Final
printf "\n%s======================================================================%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"
printf "%s  EXECUTOR DE TESTES E2E DO LUMEN OS — RESUMO DA EXECUÇÃO%s\n" "${CLR_BOLD}${CLR_WHITE}" "${CLR_RESET}"
printf "%s======================================================================%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"
printf "  Tiers Executados: %d\n" "$TOTAL_TIERS_RUN"
printf "  Tiers com Falha:  %d\n" "$TOTAL_TIERS_FAILED"
printf "  Duração Total:    %ss\n" "$MASTER_DURATION"

if [[ "$FINAL_EXIT_CODE" -eq 0 ]]; then
    printf "  Status Final:     %s[TODOS OS TIERS PASSARAM]%s\n" "${CLR_BOLD}${CLR_GREEN}" "${CLR_RESET}"
else
    printf "  Status Final:     %s[FALHAS DETECTADAS]%s\n" "${CLR_BOLD}${CLR_RED}" "${CLR_RESET}"
fi
printf "%s======================================================================%s\n\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"

exit "$FINAL_EXIT_CODE"
