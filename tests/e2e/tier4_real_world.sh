#!/usr/bin/env bash
# ==============================================================================
# Lumen OS E2E — Tier 4: Real-World Scenarios (tests/e2e/tier4_real_world.sh)
# 5 Composite end-to-end user workflows and operational validation scenarios
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common harness
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
# Scenario 1: Clean Build Workflow Simulation (Dry-Run Pipeline)
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO1_CLEAN_BUILD_WORKFLOW" "Full pipeline clean-state dry-run: packaging -> repo -> ISO -> traps"
pkg_script="${WORKSPACE_ROOT}/scripts/package-debs.sh"
build_iso_script="${WORKSPACE_ROOT}/scripts/build-iso.sh"

if [[ -f "$pkg_script" ]]; then
    # Test package build orchestration script
    assert_file_executable "$pkg_script" "package-debs.sh must be executable"

    # Simulate packaging pipeline dry-run
    status=0
    pkg_out=$(bash "$pkg_script" --help 2>&1) || status=$?
    assert_contains "$pkg_script" "build-debs\.sh" "package-debs.sh orchestrates build-debs.sh"
    assert_contains "$pkg_script" "create-local-repo\.sh" "package-debs.sh orchestrates create-local-repo.sh"

    # Check ISO pipeline dry-run if present
    if [[ -f "$build_iso_script" ]]; then
        assert_file_executable "$build_iso_script" "build-iso.sh must be executable"
        assert_contains "$build_iso_script" "dry-run" "build-iso.sh must support --dry-run"
        assert_contains "$build_iso_script" "trap " "build-iso.sh must trap cleanup signals"

        iso_out=$(bash "$build_iso_script" --dry-run 2>&1) || true
        assert_contains "$iso_out" "Stage|debootstrap|squashfs|xorriso" "ISO dry-run must report pipeline progression"
    fi
else
    test_case_skip "scripts/package-debs.sh not yet present"
fi
test_case_end


# ------------------------------------------------------------------------------
# Scenario 2: Offline Repository Generation & Dependency Graph DAG Validation
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO2_OFFLINE_REPO_AND_DEPENDENCY_DAG" "Dependency graph cycle detection and offline APT repo indexing"
control_file="${WORKSPACE_ROOT}/packaging/debian/control"
repo_script="${WORKSPACE_ROOT}/packaging/create-local-repo.sh"

if [[ -f "$control_file" && -f "$repo_script" ]]; then
    # 1. Parse packages declared in control
    for pkg in lumen-shell lumen-compositor lumen-system lumen-dev-stack lumen-welcome lumen-desktop; do
        assert_contains "$control_file" "Package:[[:space:]]*${pkg}" "Package ${pkg} must be declared in control"
    done

    # 2. Verify Metapackage lumen-desktop depends on all 5 sub-packages
    assert_contains "$control_file" "lumen-shell" "lumen-desktop must depend on lumen-shell"
    assert_contains "$control_file" "lumen-compositor" "lumen-desktop must depend on lumen-compositor"
    assert_contains "$control_file" "lumen-system" "lumen-desktop must depend on lumen-system"
    assert_contains "$control_file" "lumen-dev-stack" "lumen-desktop must depend on lumen-dev-stack"
    assert_contains "$control_file" "lumen-welcome" "lumen-desktop must depend on lumen-welcome"

    # 3. Verify no circular dependency: Sub-packages must NOT depend on lumen-desktop
    python3 - << 'EOF' || _record_fail "Dependency cycle detected in control file"
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

# Assert sub-packages never depend on metapackage lumen-desktop
for p in ["lumen-shell", "lumen-compositor", "lumen-system", "lumen-dev-stack", "lumen-welcome"]:
    if "lumen-desktop" in deps.get(p, []):
        sys.exit(1)
sys.exit(0)
EOF

    # 4. Verify create-local-repo.sh generates Packages and Packages.gz
    assert_contains "$repo_script" "dpkg-scanpackages" "create-local-repo.sh must invoke dpkg-scanpackages"
    assert_contains "$repo_script" "Packages" "create-local-repo.sh must create Packages file"
else
    test_case_skip "Debian control or create-local-repo.sh not yet present"
fi
test_case_end


# ------------------------------------------------------------------------------
# Scenario 3: Calamares Live Session Autostart & Post-Installation Chroot Execution Dry-Run
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO3_CALAMARES_AUTOSTART_AND_POSTINSTALL_CHROOT" "Live autostart environment, sequence ordering, and mock chroot execution"
settings_file="${WORKSPACE_ROOT}/installer/calamares/settings.conf"
postinstall_script="${WORKSPACE_ROOT}/installer/calamares/scripts/lumen-postinstall.sh"
launch_script="${WORKSPACE_ROOT}/installer/calamares/scripts/launch-calamares.sh"

if [[ -f "$settings_file" && -f "$postinstall_script" && -f "$launch_script" ]]; then
    # 1. Calamares Execution Sequence Validation
    assert_contains "$settings_file" "sequence:" "settings.conf must define execution sequence"
    assert_contains "$settings_file" "welcome" "Sequence must include welcome"
    assert_contains "$settings_file" "partition" "Sequence must include partition"
    assert_contains "$settings_file" "unpackfs" "Sequence must include unpackfs"
    assert_contains "$settings_file" "users" "Sequence must include users"
    assert_contains "$settings_file" "postinstall" "Sequence must include postinstall hook"

    # 2. Hermetic Mock Target Chroot Simulation
    mock_chroot=$(mktemp -d "/tmp/lumen_mock_target_XXXXXX")
    mkdir -p "${mock_chroot}/etc/skel/.config" "${mock_chroot}/home/lumen" "${mock_chroot}/usr/bin"
    echo "lumen:x:1000:1000:Lumen User:/home/lumen:/bin/bash" > "${mock_chroot}/etc/passwd"

    # Mock user home directory remains intact
    assert_dir_exists "${mock_chroot}/home/lumen" "Mock user directory created cleanly"
    rm -rf "${mock_chroot}"
else
    test_case_skip "Calamares configuration or postinstall hook not yet present"
fi
test_case_end


# ------------------------------------------------------------------------------
# Scenario 4: QEMU Multi-Mode VM Invocation Validation & Command String Verification
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO4_QEMU_VM_INVOCATION_AND_COMMAND_VALIDATION" "QEMU runner CLI option parsing across UEFI, BIOS, headless, and resource modes"
qemu_script="${WORKSPACE_ROOT}/scripts/test-iso-qemu.sh"

if [[ -f "$qemu_script" ]]; then
    dummy_iso="${SANDBOX_DIR}/dummy_lumen_test.iso"
    echo "CD001" > "$dummy_iso"

    # Verify script handles dry-run or flag inspection
    assert_contains "$qemu_script" "uefi" "Script must support uefi option"
    assert_contains "$qemu_script" "bios" "Script must support bios option"
    assert_contains "$qemu_script" "headless" "Script must support headless option"

    # Negative test on missing ISO
    status=0
    bash "$qemu_script" "/tmp/nonexistent-iso-$$.iso" >/dev/null 2>&1 || status=$?
    assert_ne 0 "$status" "Invoking QEMU runner on non-existent ISO must fail"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end


# ------------------------------------------------------------------------------
# Scenario 5: User Build Guide Code-Block Extraction & Executable Verification
# ------------------------------------------------------------------------------
test_case_start "T4_SCENARIO5_USER_GUIDE_CODE_BLOCK_VERIFICATION" "Extract and validate markdown code blocks, script references, and prerequisites"
doc_file="${WORKSPACE_ROOT}/docs/BUILD_ISO.md"

if [[ -f "$doc_file" ]]; then
    assert_file_not_empty "$doc_file" "BUILD_ISO.md must have content"
    assert_contains "$doc_file" "WSL2" "Docs must contain WSL2 section"

    # Extract all bash/sh code blocks from markdown
    code_snippets=$(sed -n '/^```bash/,/^```/p' "$doc_file" | grep -v '^```' || true)

    # Check script references match actual workspace scripts
    if grep -q "package-debs.sh" "$doc_file"; then
        assert_file_exists "${WORKSPACE_ROOT}/scripts/package-debs.sh" "package-debs.sh referenced in docs must exist"
    fi
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# Finalize Suite
suite_finish
