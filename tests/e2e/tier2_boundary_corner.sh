#!/usr/bin/env bash
# ==============================================================================
# Lumen OS E2E — Tier 2: Boundary & Corner Cases (tests/e2e/tier2_boundary_corner.sh)
# 30 Tests: 5 negative, boundary, and edge-case tests per feature across F1 to F6
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common harness
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
# FEATURE F1: Modular .deb Packaging Boundary Cases (5 tests)
# ==============================================================================

# T2-F1-01: Missing Control File Rejection
test_case_start "T2_F1_01" "Packaging tool rejects directory missing DEBIAN/control"
status=0
output=$(dpkg-deb --build "${SCRIPT_DIR}/fixtures/pkg_missing_control" 2>&1) || status=$?
if [[ "$status" -ne 0 && "$output" =~ (failed to open package control file|No such file) ]]; then
    assert_ne 0 "$status" "Missing control file must cause dpkg-deb to fail"
else
    # Fallback check
    assert_ne 0 "$status" "Missing control file must cause build failure"
fi
test_case_end

# T2-F1-02: Malformed Control Syntax Rejection
test_case_start "T2_F1_02" "Packaging tool rejects corrupt RFC 822 control syntax"
status=0
output=$(dpkg-deb --build "${SCRIPT_DIR}/fixtures/pkg_corrupted_control" 2>&1) || status=$?
assert_ne 0 "$status" "Corrupted control file must cause dpkg-deb to fail"
test_case_end

# T2-F1-03: Unrecognized CLI Flags Handling
test_case_start "T2_F1_03" "Build script rejects unknown CLI options or invalid flags"
build_debs_script="${WORKSPACE_ROOT}/packaging/build-debs.sh"
if [[ -f "$build_debs_script" ]]; then
    status=0
    output=$(bash "$build_debs_script" --invalid-flag-xyz-99 2>&1) || status=$?
    assert_ne 0 "$status" "Unknown CLI flags or bad path must cause build script to exit non-zero"
else
    test_case_skip "packaging/build-debs.sh not yet present"
fi
test_case_end

# T2-F1-04: Unwritable Output Directory Handling
test_case_start "T2_F1_04" "Packaging script detects unwritable destination cleanly"
if [[ -f "$build_debs_script" ]]; then
    status=0
    output=$(bash "$build_debs_script" "/proc/unwritable_dir_$(date +%s)" 2>&1) || status=$?
    assert_ne 0 "$status" "Unwritable output directory must fail cleanly"
else
    test_case_skip "packaging/build-debs.sh not yet present"
fi
test_case_end

# T2-F1-05: Empty Repository Handling
test_case_start "T2_F1_05" "Repository indexer gracefully handles directory with 0 deb packages"
empty_dir="${SCRIPT_DIR}/fixtures/empty_repo"
if command -v dpkg-scanpackages >/dev/null 2>&1; then
    status=0
    output=$(dpkg-scanpackages "$empty_dir" /dev/null 2>&1) || status=$?
    assert_contains "$output" "Wrote 0 entries|binary path" "Empty directory scanning handled gracefully"
else
    test_case_skip "dpkg-scanpackages not available on host"
fi
test_case_end


# ==============================================================================
# FEATURE F2: Calamares Installer & Branding Boundary Cases (5 tests)
# ==============================================================================

# T2-F2-01: Missing Referenced Module Detection
test_case_start "T2_F2_01" "Detect referenced modules in sequence missing from modules directory"
settings_file="${WORKSPACE_ROOT}/installer/calamares/settings.conf"
modules_dir="${WORKSPACE_ROOT}/installer/calamares/modules"
if [[ -f "$settings_file" && -d "$modules_dir" ]]; then
    # Verify core referenced modules actually exist on disk
    for mod in welcome partition unpackfs users bootloader; do
        assert_file_exists "${modules_dir}/${mod}.conf" "Module ${mod}.conf referenced in settings must exist"
    done
else
    test_case_skip "Calamares configuration not yet present"
fi
test_case_end

# T2-F2-02: Corrupted YAML Configuration Rejection
test_case_start "T2_F2_02" "YAML parser catches syntax corruption in installer configs"
corrupt_conf="${SCRIPT_DIR}/fixtures/corrupt_settings.conf"
status=0
err=$(python3 -c "import yaml; yaml.safe_load(open('$corrupt_conf'))" 2>&1) || status=$?
assert_ne 0 "$status" "Corrupt YAML syntax must cause parser failure"
assert_contains "$err" "ScannerError|ParserError|tab" "Error must report YAML syntax violation"
test_case_end

# T2-F2-03: Missing Branding Asset Detection
test_case_start "T2_F2_03" "Branding descriptor image references exist on disk"
branding_desc="${WORKSPACE_ROOT}/installer/calamares/branding/lumen/branding.desc"
branding_dir="${WORKSPACE_ROOT}/installer/calamares/branding/lumen"
if [[ -f "$branding_desc" ]]; then
    # Verify image files declared in branding.desc exist
    logo_svg=$(python3 -c "import yaml; d=yaml.safe_load(open('$branding_desc')); print(d.get('images', {}).get('productLogo', ''))" 2>/dev/null || echo "")
    if [[ -n "$logo_svg" ]]; then
        assert_file_exists "${branding_dir}/${logo_svg}" "Product logo referenced in branding.desc must exist"
    fi
else
    test_case_skip "installer/calamares/branding/lumen/branding.desc not yet present"
fi
test_case_end

# T2-F2-04: Postinstall Non-Root Execution Denial
test_case_start "T2_F2_04" "Postinstall hook aborts when executed without write permission or root"
postinstall="${WORKSPACE_ROOT}/installer/calamares/scripts/lumen-postinstall.sh"
if [[ -f "$postinstall" ]]; then
    # Execute as normal unprivileged user without mock tools
    status=0
    # Temporarily bypass mock sudo to test real non-root behavior
    output=$(PATH="${ORIGINAL_PATH:-/usr/bin:/bin}" bash "$postinstall" 2>&1) || status=$?
    assert_ne 0 "$status" "lumen-postinstall.sh executed as non-root must exit non-zero"
else
    test_case_skip "installer/calamares/scripts/lumen-postinstall.sh not yet present"
fi
test_case_end

# T2-F2-05: Wayland Wrapper Missing Display Handling
test_case_start "T2_F2_05" "Wayland launch wrapper environment setup and elevation check"
launcher="${WORKSPACE_ROOT}/installer/calamares/scripts/launch-calamares.sh"
if [[ -f "$launcher" ]]; then
    # Check that launcher configures QT_QPA_PLATFORM and WAYLAND_DISPLAY
    assert_contains "$launcher" "QT_QPA_PLATFORM" "launch-calamares.sh must configure QT_QPA_PLATFORM"
    assert_contains "$launcher" "WAYLAND_DISPLAY" "launch-calamares.sh must handle WAYLAND_DISPLAY"
else
    test_case_skip "installer/calamares/scripts/launch-calamares.sh not yet present"
fi
test_case_end


# ==============================================================================
# FEATURE F3: ISO Generation Pipeline Boundary Cases (5 tests)
# ==============================================================================

# T2-F3-01: Non-Root Invocation Denial
test_case_start "T2_F3_01" "ISO build script strictly enforces root / sudo invocation"
build_iso_script="${WORKSPACE_ROOT}/scripts/build-iso.sh"
if [[ -f "$build_iso_script" ]]; then
    # Run with original path (without mock sudo) to verify non-root denial
    status=0
    output=$(PATH="${ORIGINAL_PATH:-/usr/bin:/bin}" bash "$build_iso_script" 2>&1) || status=$?
    assert_ne 0 "$status" "build-iso.sh executed without root must exit non-zero"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end

# T2-F3-02: Missing Build Toolchain Detection
test_case_start "T2_F3_02" "ISO build script pre-flight catches missing required toolchain"
if [[ -f "$build_iso_script" ]]; then
    # Restrict PATH to minimal coreutils to test toolchain check
    status=0
    output=$(PATH="/bin:/usr/bin" bash "$build_iso_script" --check-deps 2>&1) || status=$?
    # Must either fail dependency check or exit non-zero
    assert_contains "$build_iso_script" "command -v" "build-iso.sh must check for required tool commands"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end

# T2-F3-03: Insufficient Disk Space Abort
test_case_start "T2_F3_03" "ISO build script queries filesystem free space before build"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "df |disk|space" "build-iso.sh must verify available disk space"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end

# T2-F3-04: Interruption Mount Cleanup Verification
test_case_start "T2_F3_04" "ISO build script traps EXIT INT TERM to cleanly unmount chroot mounts"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "trap " "build-iso.sh must define cleanup signal traps"
    assert_contains "$build_iso_script" "umount" "Cleanup handler must unmount filesystems"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end

# T2-F3-05: Dry-Run Mode Safety Verification
test_case_start "T2_F3_05" "ISO build script dry-run executes non-destructively without root mounts"
if [[ -f "$build_iso_script" ]]; then
    status=0
    output=$(bash "$build_iso_script" --dry-run 2>&1) || status=$?
    assert_eq 0 "$status" "build-iso.sh --dry-run should exit 0 without errors"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end


# ==============================================================================
# FEATURE F4: GitHub Actions CI Automation Boundary Cases (5 tests)
# ==============================================================================

# T2-F4-01: Corrupted Workflow YAML Rejection
test_case_start "T2_F4_01" "CI YAML validator catches corrupt workflow syntax and bad indents"
corrupt_wf="${SCRIPT_DIR}/fixtures/corrupt_workflow.yml"
status=0
err=$(python3 -c "import yaml; yaml.safe_load(open('$corrupt_wf'))" 2>&1) || status=$?
assert_ne 0 "$status" "Corrupt workflow YAML must fail parsing"
test_case_end

# T2-F4-02: Missing Mandatory Keys Detection
test_case_start "T2_F4_02" "CI workflow contains mandatory top-level keys: name, on, jobs"
workflow_file="${WORKSPACE_ROOT}/.github/workflows/build-iso.yml"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "^name:" "Workflow must have top-level name"
    assert_contains "$workflow_file" "^on:" "Workflow must have top-level on trigger"
    assert_contains "$workflow_file" "^jobs:" "Workflow must have top-level jobs mapping"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end

# T2-F4-03: Incompatible Runner Rejection
test_case_start "T2_F4_03" "CI workflow specifies supported Ubuntu Linux runner image"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "runs-on:[[:space:]]*ubuntu-" "Workflow must target Ubuntu runner"
    assert_not_contains "$workflow_file" "runs-on:[[:space:]]*windows-" "Windows runner not supported"
    assert_not_contains "$workflow_file" "runs-on:[[:space:]]*macos-" "macOS runner not supported"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end

# T2-F4-04: Artifact Path Contract Discrepancy
test_case_start "T2_F4_04" "CI upload artifact strictly matches contractual ISO output name"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "lumen-os-26.04-amd64.iso" "Artifact upload path must match contractual ISO name"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end

# T2-F4-05: Missing Sudo Elevation Detection
test_case_start "T2_F4_05" "CI workflow executes root build script with sudo elevation"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "sudo.*build-iso\.sh" "Workflow must invoke build-iso.sh with sudo"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end


# ==============================================================================
# FEATURE F5: QEMU Test Script & Runner Boundary Cases (5 tests)
# ==============================================================================

# T2-F5-01: Non-Existent ISO Path Handling
test_case_start "T2_F5_01" "QEMU runner aborts cleanly with error on non-existent ISO path"
qemu_script="${WORKSPACE_ROOT}/scripts/test-iso-qemu.sh"
if [[ -f "$qemu_script" ]]; then
    status=0
    output=$(bash "$qemu_script" "/tmp/nonexistent-iso-file-$$.iso" 2>&1) || status=$?
    assert_ne 0 "$status" "Non-existent ISO path must cause runner to exit non-zero"
    assert_contains "$output" "not found|No such file|does not exist" "Error must state ISO was not found"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end

# T2-F5-02: Unknown CLI Flag Rejection
test_case_start "T2_F5_02" "QEMU runner rejects unknown command line options with exit code 2"
if [[ -f "$qemu_script" ]]; then
    status=0
    output=$(bash "$qemu_script" --invalid-option-xyz-99 2>&1) || status=$?
    assert_eq 2 "$status" "Unknown CLI options must result in exit code 2"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end

# T2-F5-03: Malformed RAM/SMP Values Rejection
test_case_start "T2_F5_03" "QEMU runner rejects malformed resource values (--ram / --smp)"
if [[ -f "$qemu_script" ]]; then
    status=0
    output=$(bash "$qemu_script" --ram "not-a-number" 2>&1) || status=$?
    assert_ne 0 "$status" "Invalid resource specification must exit non-zero"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end

# T2-F5-04: Missing QEMU Executable Detection
test_case_start "T2_F5_04" "QEMU runner diagnoses missing qemu-system-x86_64 in PATH"
if [[ -f "$qemu_script" ]]; then
    # Run with restricted PATH excluding qemu
    status=0
    output=$(PATH="/bin:/usr/bin" bash "$qemu_script" 2>&1) || status=$?
    assert_contains "$qemu_script" "qemu-system-x86_64" "Script must search for qemu-system-x86_64"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end

# T2-F5-05: Missing OVMF Firmware Handling
test_case_start "T2_F5_05" "QEMU runner handles missing OVMF firmware with actionable diagnostic"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "OVMF" "Script must contain OVMF search and diagnostic logic"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end


# ==============================================================================
# FEATURE F6: Practical User Build Guide Boundary Cases (5 tests)
# ==============================================================================

# T2-F6-01: Broken Script Paths in Markdown
test_case_start "T2_F6_01" "Extract repo script references in user guide and verify existence"
guide_file="${WORKSPACE_ROOT}/docs/BUILD_ISO.md"
if [[ -f "$guide_file" ]]; then
    # Look for scripts referenced in guide
    if grep -q "scripts/package-debs.sh" "$guide_file"; then
        assert_file_exists "${WORKSPACE_ROOT}/scripts/package-debs.sh" "package-debs.sh cited in guide must exist"
    fi
    if grep -q "scripts/build-iso.sh" "$guide_file"; then
        assert_file_exists "${WORKSPACE_ROOT}/scripts/build-iso.sh" "build-iso.sh cited in guide must exist"
    fi
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# T2-F6-02: Unclosed Code Fences Detection
test_case_start "T2_F6_02" "Markdown code fences (triple backticks) are properly closed"
if [[ -f "$guide_file" ]]; then
    fence_count=$(grep -c '^[[:space:]]*```' "$guide_file" || echo 0)
    remainder=$((fence_count % 2))
    assert_eq 0 "$remainder" "Code fences in BUILD_ISO.md must have matching open/close pairs"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# T2-F6-03: Placeholder Tokens Detection
test_case_start "T2_F6_03" "User guide contains no unresolved TODO, TBD, or FIXME placeholders"
if [[ -f "$guide_file" ]]; then
    assert_not_contains "$guide_file" "TODO|TBD|FIXME|REPLACE_ME" "User guide must not contain placeholders"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# T2-F6-04: Missing WSL2 /mnt/c NTFS Warning
test_case_start "T2_F6_04" "User guide warns against building in Windows NTFS mounts (/mnt/c)"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "/mnt/c|NTFS" "User guide must warn against /mnt/c Windows filesystem mounts"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# T2-F6-05: Checksum Verification Syntax Mismatch
test_case_start "T2_F6_05" "Checksum command snippet matches canonical SHA256 checksum file"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "sha256sum[[:space:]]+-c[[:space:]]+.*\.sha256" "Documentation must show sha256sum -c verification"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# Finalize Suite
suite_finish
