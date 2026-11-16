#!/usr/bin/env bash
# ==============================================================================
# Lumen OS E2E Master Test Runner (tests/e2e/run-e2e-tests.sh)
# Master dispatcher for multi-tier end-to-end integration test suites.
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${WORKSPACE_ROOT}"

# Default parameters
TIER="all"
VERBOSE=0
QUIET=0
LOG_FILE=""
XML_REPORT_FILE="${SCRIPT_DIR}/reports/e2e-results.xml"
DRY_RUN=0

# Print usage information
usage() {
    cat << EOF
Lumen OS Unified E2E Test Runner

Usage:
  bash tests/e2e/run-e2e-tests.sh [OPTIONS]

Options:
  --tier <1|2|3|4|all>   Select test tier to execute (default: all)
                         1: Feature Coverage (≥30 tests)
                         2: Boundary & Corner Cases (≥30 tests)
                         3: Cross-Feature Integration (≥6 tests)
                         4: Real-World Scenarios (≥5 tests)
  -v, --verbose          Enable detailed test logs and debug messages
  -q, --quiet            Quiet mode, display minimal summary results only
  -l, --log <file>       Write detailed execution log to specified path
  -x, --xml <file>       Generate JUnit XML report (default: tests/e2e/reports/e2e-results.xml)
  --no-color             Disable ANSI color formatting
  --dry-run              Verify environment and test files without running assertions
  -h, --help             Show this help message and exit 0

Exit Codes:
  0: All tests passed successfully
  1: One or more test assertions failed
  2: Invalid CLI argument or critical environment failure
EOF
    exit 0
}

# Parse CLI options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)
            if [[ -z "${2:-}" ]]; then echo "Error: --tier requires an argument" >&2; exit 2; fi
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
            if [[ -z "${2:-}" ]]; then echo "Error: --log requires a file path" >&2; exit 2; fi
            LOG_FILE="$2"
            shift 2
            ;;
        -x|--xml)
            if [[ -z "${2:-}" ]]; then echo "Error: --xml requires a file path" >&2; exit 2; fi
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
            echo "Error: Unrecognized option: $1" >&2
            echo "Run 'bash tests/e2e/run-e2e-tests.sh --help' for usage." >&2
            exit 2
            ;;
    esac
done

# Validate tier selection
case "$TIER" in
    1|2|3|4|all) ;;
    *)
        echo "Error: Invalid tier '${TIER}'. Must be 1, 2, 3, 4, or all." >&2
        exit 2
        ;;
esac

# Source common test harness
if [[ ! -f "${SCRIPT_DIR}/harness.sh" ]]; then
    echo "Critical Error: Harness library not found at ${SCRIPT_DIR}/harness.sh" >&2
    exit 2
fi

# Export parameters for child tier scripts
MASTER_XML_REPORT_FILE="${XML_REPORT_FILE}"
XML_REPORT_DIR="$(dirname "${MASTER_XML_REPORT_FILE}")"
mkdir -p "${XML_REPORT_DIR}"
export VERBOSE QUIET LOG_FILE XML_REPORT_FILE DRY_RUN
source "${SCRIPT_DIR}/harness.sh"

# Pre-flight environment check
verify_prerequisites() {
    log_debug "Checking environment prerequisites..."
    local missing=0
    for cmd in bash python3 grep sed awk mktemp find; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Missing required core system command: $cmd"
            missing=1
        fi
    done
    if [[ "$missing" -eq 1 ]]; then
        log_error "Environment verification failed. Missing required tools."
        exit 2
    fi
}
verify_prerequisites

# Create sandbox for global runner
create_test_sandbox "lumen-e2e-master"
enable_mock_root_tools

# Cleanup and signal trap handlers
cleanup_all() {
    disable_mock_root_tools
    cleanup_test_sandbox
}

handle_sigint() {
    log_warn "Interrupted by SIGINT (Ctrl+C). Cleaning up and exiting..."
    cleanup_all
    exit 130
}

handle_sigterm() {
    log_warn "Interrupted by SIGTERM. Cleaning up and exiting..."
    cleanup_all
    exit 1
}

trap cleanup_all EXIT
trap handle_sigint INT
trap handle_sigterm TERM

# Overall counters across tiers
MASTER_START_TIME=${EPOCHREALTIME:-$(date +%s)}
TOTAL_TIERS_RUN=0
TOTAL_TIERS_FAILED=0

execute_tier() {
    local tier_num="$1"
    local script_name="$2"
    local tier_xml="$3"
    local full_path="${SCRIPT_DIR}/${script_name}"

    if [[ ! -f "$full_path" ]]; then
        log_warn "Tier ${tier_num} test script not found: ${script_name} (Planned)"
        return 0
    fi

    ((TOTAL_TIERS_RUN++))
    log_info "Executing Tier ${tier_num}: ${script_name}..."

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log_info "Dry-run mode: Tier ${tier_num} verified."
        return 0
    fi

    local tier_status=0
    # Execute in subshell to preserve isolation and emit per-tier XML
    (
        export LUMEN_RUN_TIER="${tier_num}"
        export XML_REPORT_FILE="${tier_xml}"
        bash "${full_path}"
    ) || tier_status=$?

    if [[ "$tier_status" -ne 0 ]]; then
        ((TOTAL_TIERS_FAILED++))
        log_error "Tier ${tier_num} failed with exit code: ${tier_status}"
    else
        log_success "Tier ${tier_num} passed cleanly."
    fi
    return "$tier_status"
}

# Determine tiers to run
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

# Execute tiers
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
            log_warn "Tier ${t_num} received termination signal (${tier_status}). Aborting execution."
            exit "$tier_status"
        fi
    fi
    if [[ -f "$t_xml" ]]; then
        GENERATED_TIER_XMLS+=( "$t_xml" )
    fi
done

# Aggregate per-tier XML reports into master XML report
if [[ "$DRY_RUN" -eq 0 && "${#GENERATED_TIER_XMLS[@]}" -gt 0 && -n "${MASTER_XML_REPORT_FILE}" ]]; then
    log_info "Aggregating ${#GENERATED_TIER_XMLS[@]} tier report(s) into ${MASTER_XML_REPORT_FILE}..."
    aggregate_junit_xml "${MASTER_XML_REPORT_FILE}" "${GENERATED_TIER_XMLS[@]}"
fi

MASTER_END_TIME=${EPOCHREALTIME:-$(date +%s)}
MASTER_DURATION=$(awk -v s="${MASTER_START_TIME}" -v e="${MASTER_END_TIME}" 'BEGIN {printf "%.2f", e - s}')

# Master Final Summary Banner
printf "\n%s======================================================================%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"
printf "%s  LUMEN OS E2E TEST RUNNER — EXECUTION SUMMARY%s\n" "${CLR_BOLD}${CLR_WHITE}" "${CLR_RESET}"
printf "%s======================================================================%s\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"
printf "  Tiers Executed:   %d\n" "$TOTAL_TIERS_RUN"
printf "  Tiers Failed:     %d\n" "$TOTAL_TIERS_FAILED"
printf "  Total Duration:   %ss\n" "$MASTER_DURATION"

if [[ "$FINAL_EXIT_CODE" -eq 0 ]]; then
    printf "  Final Status:     %s[ALL TIERS PASSED]%s\n" "${CLR_BOLD}${CLR_GREEN}" "${CLR_RESET}"
else
    printf "  Final Status:     %s[FAILURES DETECTED]%s\n" "${CLR_BOLD}${CLR_RED}" "${CLR_RESET}"
fi
printf "%s======================================================================%s\n\n" "${CLR_BOLD}${CLR_CYAN}" "${CLR_RESET}"

exit "$FINAL_EXIT_CODE"
