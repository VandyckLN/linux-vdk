#!/usr/bin/env bash
# ==============================================================================
# Lumen OS E2E — Tier 3: Cross-Feature Integration (tests/e2e/tier3_cross_feature.sh)
# 6 Pairwise integration tests validating bilateral architectural contracts
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common harness
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
# Pair 1: Packaging (F1) <-> Calamares (F2) Alignment
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR1_PACKAGING_CALAMARES" "Packaging binaries align with Calamares live autostart and post-install hook"
postinstall_script="${WORKSPACE_ROOT}/installer/calamares/scripts/lumen-postinstall.sh"
launch_script="${WORKSPACE_ROOT}/installer/calamares/scripts/launch-calamares.sh"
control_file="${WORKSPACE_ROOT}/packaging/debian/control"
templates_dir="${WORKSPACE_ROOT}/packaging/templates"

if [[ -f "$postinstall_script" && -f "$launch_script" && -f "$control_file" ]]; then
    # 1. Verify binaries and environment in launch-calamares.sh
    assert_contains "$launch_script" "calamares" "Launch script must invoke calamares"
    assert_contains "$launch_script" "WAYLAND_DISPLAY" "Launch script must handle Wayland display"
    assert_contains "$launch_script" "QT_QPA_PLATFORM" "Launch script must configure Qt Wayland platform"

    # 2. Verify postinstall hook aligns with packaged paths and user structure
    assert_contains "$postinstall_script" "skel" "Postinstall hook must configure /etc/skel"
    assert_contains "$postinstall_script" "1000" "Postinstall hook must target UID 1000 user"

    # 3. Verify packages declare expected Lumen components
    assert_contains "$control_file" "Package: lumen-shell" "Control file must declare lumen-shell"
    assert_contains "$control_file" "Package: lumen-compositor" "Control file must declare lumen-compositor"
    assert_contains "$control_file" "Package: lumen-system" "Control file must declare lumen-system"
    assert_contains "$control_file" "Package: lumen-dev-stack" "Control file must declare lumen-dev-stack"
    assert_contains "$control_file" "Package: lumen-welcome" "Control file must declare lumen-welcome"
    assert_contains "$control_file" "Package: lumen-desktop" "Control file must declare lumen-desktop"

    # 4. Verify templates provide necessary runtime entrypoints
    if [[ -d "$templates_dir" ]]; then
        assert_file_exists "${templates_dir}/lumen-shell" "lumen-shell entrypoint template required"
        assert_file_exists "${templates_dir}/lumen-session-hyprland" "hyprland session entrypoint required"
        assert_file_exists "${templates_dir}/lumen-system-tune" "system tune entrypoint required"
    fi
else
    test_case_skip "Calamares or packaging files pending"
fi
test_case_end


# ------------------------------------------------------------------------------
# Pair 2: Packaging/Calamares (F1/F2) <-> ISO Builder (F3)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR2_PACKAGING_CALAMARES_ISO_BUILDER" "Local repo pool and Calamares configs staged into ISO filesystem"
build_iso_script="${WORKSPACE_ROOT}/scripts/build-iso.sh"

if [[ -f "$build_iso_script" ]]; then
    # 1. Local Repo Ingestion in ISO Builder
    assert_contains "$build_iso_script" "debs" "ISO builder must stage local package debs"
    assert_contains "$build_iso_script" "lumen-desktop" "ISO builder must install metapackage lumen-desktop"

    # 2. Calamares Config & Branding Staging
    assert_contains "$build_iso_script" "calamares" "ISO builder must stage Calamares configs"
    assert_contains "$build_iso_script" "branding" "ISO builder must stage Calamares branding"
    assert_contains "$build_iso_script" "lumen-postinstall.sh" "ISO builder must stage postinstall script"

    # 3. Live Casper Autostart Staging
    assert_contains "$build_iso_script" "launch-calamares.sh" "ISO builder must stage live autostart launcher"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end


# ------------------------------------------------------------------------------
# Pair 3: ISO Builder (F3) <-> CI Automation (F4)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR3_ISO_BUILDER_CI_WORKFLOW" "CI workflow steps, dependencies, and artifacts align with ISO build pipeline"
workflow_file="${WORKSPACE_ROOT}/.github/workflows/build-iso.yml"

if [[ -f "$workflow_file" ]]; then
    # 1. Workflow Triggers
    assert_contains "$workflow_file" "workflow_dispatch" "CI must support manual trigger"

    # 2. Sequential Build Step Invocations
    assert_contains "$workflow_file" "package-debs.sh|build-debs.sh" "CI must execute packaging"
    assert_contains "$workflow_file" "build-iso.sh" "CI must execute build-iso.sh"

    # 3. Dependency Installation
    assert_contains "$workflow_file" "debootstrap" "CI must install debootstrap"
    assert_contains "$workflow_file" "xorriso" "CI must install xorriso"
    assert_contains "$workflow_file" "squashfs-tools" "CI must install squashfs-tools"

    # 4. Artifact Output & Checksum Contract
    assert_contains "$workflow_file" "lumen-os-26.04-amd64.iso" "CI artifact upload must target ISO output"
    assert_contains "$workflow_file" "upload-artifact" "CI must upload ISO artifact"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end


# ------------------------------------------------------------------------------
# Pair 4: ISO Builder (F3) <-> QEMU Runner (F5)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR4_ISO_BUILDER_QEMU_RUNNER" "QEMU runner validates default ISO path, UEFI/BIOS dual boot, and test disk"
qemu_script="${WORKSPACE_ROOT}/scripts/test-iso-qemu.sh"

if [[ -f "$qemu_script" ]]; then
    # 1. Default ISO Path Agreement
    assert_contains "$qemu_script" "lumen-os-26.04-amd64.iso" "QEMU runner default ISO must match build-iso.sh output"

    # 2. Dual Boot Support
    assert_contains "$qemu_script" "uefi" "QEMU runner must support --uefi boot"
    assert_contains "$qemu_script" "bios" "QEMU runner must support --bios boot"
    assert_contains "$qemu_script" "OVMF" "QEMU runner must support OVMF firmware"

    # 3. Test Disk Provisioning for Installer Testing
    assert_contains "$qemu_script" "qemu-img|create-disk|drive" "QEMU runner must support test disk provisioning"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end


# ------------------------------------------------------------------------------
# Pair 5: Packaging/ISO (F1/F3) <-> Documentation (F6)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR5_PACKAGING_ISO_DOCUMENTATION" "User documentation references real script paths, flags, and outputs"
doc_file="${WORKSPACE_ROOT}/docs/BUILD_ISO.md"

if [[ -f "$doc_file" ]]; then
    # 1. Script Path Consistency in Docs
    assert_contains "$doc_file" "package-debs.sh" "Docs must reference package-debs.sh"
    assert_contains "$doc_file" "build-iso.sh" "Docs must reference build-iso.sh"
    assert_contains "$doc_file" "test-iso-qemu.sh" "Docs must reference test-iso-qemu.sh"

    # 2. Prerequisite Completeness
    assert_contains "$doc_file" "debootstrap" "Docs must list debootstrap prerequisite"
    assert_contains "$doc_file" "squashfs-tools" "Docs must list squashfs-tools prerequisite"
    assert_contains "$doc_file" "xorriso" "Docs must list xorriso prerequisite"

    # 3. Output Path Matching
    assert_contains "$doc_file" "lumen-os-26.04-amd64.iso" "Docs must document correct ISO filename"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end


# ------------------------------------------------------------------------------
# Pair 6: Calamares (F2) <-> QEMU Runner (F5)
# ------------------------------------------------------------------------------
test_case_start "T3_PAIR6_CALAMARES_QEMU_ENVIRONMENT" "QEMU runner provides Wayland virtual graphics, sufficient RAM, and headless mode"
if [[ -f "$qemu_script" ]]; then
    # 1. RAM Allocation parameter
    assert_contains "$qemu_script" "ram" "QEMU runner must support RAM parameter"

    # 2. Virtual Graphics Support for Wayland / KMS
    assert_contains "$qemu_script" "virtio|vga|gpu" "QEMU runner must configure graphics adapter"

    # 3. Headless Support for Automated CI Testing
    assert_contains "$qemu_script" "headless" "QEMU runner must support --headless flag"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end

# Finalize Suite
suite_finish
