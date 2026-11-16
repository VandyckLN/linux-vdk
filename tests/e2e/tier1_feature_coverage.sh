#!/usr/bin/env bash
# ==============================================================================
# Lumen OS E2E — Tier 1: Feature Coverage (tests/e2e/tier1_feature_coverage.sh)
# 30 Tests: 5 tests per feature area across F1 to F6
# ==============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common harness
source "${SCRIPT_DIR}/harness.sh"

suite_init "Tier 1: Feature Coverage (F1 - F6)"

if [[ -z "${SANDBOX_DIR:-}" ]]; then
    create_test_sandbox "tier1"
    enable_mock_root_tools
    trap "disable_mock_root_tools; cleanup_test_sandbox" EXIT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 130" INT
    trap "disable_mock_root_tools; cleanup_test_sandbox; exit 1" TERM
fi

# ==============================================================================
# FEATURE F1: Modular .deb Packaging (5 tests)
# ==============================================================================

# T1-F1-01: Control File RFC 822 Compliance
test_case_start "T1_F1_01" "Debian control files RFC 822 structure and metadata"
control_file="${WORKSPACE_ROOT}/packaging/debian/control"
if [[ -f "$control_file" ]]; then
    assert_contains "$control_file" "Package: lumen-shell" "lumen-shell package stanza required"
    assert_contains "$control_file" "Package: lumen-compositor" "lumen-compositor package stanza required"
    assert_contains "$control_file" "Package: lumen-system" "lumen-system package stanza required"
    assert_contains "$control_file" "Package: lumen-dev-stack" "lumen-dev-stack package stanza required"
    assert_contains "$control_file" "Package: lumen-welcome" "lumen-welcome package stanza required"
    assert_contains "$control_file" "Package: lumen-desktop" "lumen-desktop metapackage stanza required"
    assert_contains "$control_file" "Architecture:" "Architecture field required"
    assert_contains "$control_file" "Maintainer:" "Maintainer field required"
    assert_contains "$control_file" "Description:" "Description field required"
else
    test_case_skip "packaging/debian/control not yet present"
fi
test_case_end

# T1-F1-02: Filesystem Layout & Binary Mapping
test_case_start "T1_F1_02" "Binary wrappers and staging directory layout specs"
templates_dir="${WORKSPACE_ROOT}/packaging/templates"
if [[ -d "$templates_dir" ]]; then
    assert_file_exists "${templates_dir}/lumen-shell" "lumen-shell wrapper template required"
    assert_file_exists "${templates_dir}/lumen-welcome" "lumen-welcome wrapper template required"
    assert_file_exists "${templates_dir}/lumen-session-hyprland" "lumen-session-hyprland template required"
    assert_file_exists "${templates_dir}/lumen-dev-setup" "lumen-dev-setup template required"
    assert_file_exists "${templates_dir}/lumen-system-tune" "lumen-system-tune template required"
else
    test_case_skip "packaging/templates not yet present"
fi
test_case_end

# T1-F1-03: Package Compilation Script
test_case_start "T1_F1_03" "Modular Debian build script syntax and executable permissions"
build_debs_script="${WORKSPACE_ROOT}/packaging/build-debs.sh"
if [[ -f "$build_debs_script" ]]; then
    assert_file_executable "$build_debs_script" "build-debs.sh must be executable"
    assert_syntax_valid "$build_debs_script" "sh"
else
    test_case_skip "packaging/build-debs.sh not yet present"
fi
test_case_end

# T1-F1-04: Local APT Repo Generation
test_case_start "T1_F1_04" "Local APT repository indexer script verification"
repo_script="${WORKSPACE_ROOT}/packaging/create-local-repo.sh"
if [[ -f "$repo_script" ]]; then
    assert_file_executable "$repo_script" "create-local-repo.sh must be executable"
    assert_syntax_valid "$repo_script" "sh"
else
    test_case_skip "packaging/create-local-repo.sh not yet present"
fi
test_case_end

# T1-F1-05: Packaging Convenience Wrapper
test_case_start "T1_F1_05" "Packaging root wrapper script syntax and permissions"
pkg_wrapper="${WORKSPACE_ROOT}/scripts/package-debs.sh"
if [[ -f "$pkg_wrapper" ]]; then
    assert_file_executable "$pkg_wrapper" "package-debs.sh must be executable"
    assert_syntax_valid "$pkg_wrapper" "sh"
else
    test_case_skip "scripts/package-debs.sh not yet present"
fi
test_case_end


# ==============================================================================
# FEATURE F2: Calamares Installer & Branding (5 tests)
# ==============================================================================

# T1-F2-01: Master Settings Sequence Structure
test_case_start "T1_F2_01" "Calamares settings.conf sequence and branding definition"
settings_file="${WORKSPACE_ROOT}/installer/calamares/settings.conf"
if [[ -f "$settings_file" ]]; then
    assert_syntax_valid "$settings_file" "yaml"
    assert_contains "$settings_file" "branding:[[:space:]]*lumen" "settings.conf must set branding to lumen"
    assert_contains "$settings_file" "welcome" "settings sequence must include welcome"
    assert_contains "$settings_file" "partition" "settings sequence must include partition"
    assert_contains "$settings_file" "users" "settings sequence must include users"
    assert_contains "$settings_file" "unpackfs" "settings sequence must include unpackfs"
    assert_contains "$settings_file" "bootloader" "settings sequence must include bootloader"
else
    test_case_skip "installer/calamares/settings.conf not yet present"
fi
test_case_end

# T1-F2-02: Branding Descriptor Completeness
test_case_start "T1_F2_02" "Calamares branding.desc metadata and presentation specs"
branding_desc="${WORKSPACE_ROOT}/installer/calamares/branding/lumen/branding.desc"
if [[ -f "$branding_desc" ]]; then
    assert_syntax_valid "$branding_desc" "yaml"
    assert_contains "$branding_desc" "componentName:[[:space:]]*lumen" "componentName must be lumen"
    assert_contains "$branding_desc" "Lumen OS" "Product name must contain Lumen OS"
    assert_file_exists "$(dirname "$branding_desc")/stylesheet.qss" "Branding directory must contain stylesheet.qss"
    assert_contains "$branding_desc" "slideshow" "slideshow must be specified in branding descriptor"
else
    test_case_skip "installer/calamares/branding/lumen/branding.desc not yet present"
fi
test_case_end

# T1-F2-03: Curved Glass Qt6 Stylesheet Aesthetic
test_case_start "T1_F2_03" "Curved Glass Qt6 stylesheet styling and QSS syntax"
qss_file="${WORKSPACE_ROOT}/installer/calamares/branding/lumen/stylesheet.qss"
if [[ -f "$qss_file" ]]; then
    assert_syntax_valid "$qss_file" "css"
    assert_contains "$qss_file" "rgba\(" "QSS must contain rgba translucency definitions"
    assert_contains "$qss_file" "border-radius" "QSS must define border-radius"
    assert_contains "$qss_file" "QPushButton" "QSS must style QPushButton"
    assert_contains "$qss_file" "QProgressBar" "QSS must style QProgressBar"
else
    test_case_skip "installer/calamares/branding/lumen/stylesheet.qss not yet present"
fi
test_case_end

# T1-F2-04: Core Module Configurations
test_case_start "T1_F2_04" "Calamares core module configurations syntax and presence"
modules_dir="${WORKSPACE_ROOT}/installer/calamares/modules"
if [[ -d "$modules_dir" ]]; then
    assert_file_exists "${modules_dir}/welcome.conf" "welcome.conf must exist"
    assert_file_exists "${modules_dir}/partition.conf" "partition.conf must exist"
    assert_file_exists "${modules_dir}/users.conf" "users.conf must exist"
    assert_file_exists "${modules_dir}/unpackfs.conf" "unpackfs.conf must exist"
    assert_file_exists "${modules_dir}/bootloader.conf" "bootloader.conf must exist"
    assert_syntax_valid "${modules_dir}/welcome.conf" "yaml"
    assert_syntax_valid "${modules_dir}/users.conf" "yaml"
else
    test_case_skip "installer/calamares/modules directory not yet present"
fi
test_case_end

# T1-F2-05: Postinstall & Wayland Wrapper
test_case_start "T1_F2_05" "Calamares postinstall hook and Wayland launch script"
postinstall="${WORKSPACE_ROOT}/installer/calamares/scripts/lumen-postinstall.sh"
launcher="${WORKSPACE_ROOT}/installer/calamares/scripts/launch-calamares.sh"
if [[ -f "$postinstall" && -f "$launcher" ]]; then
    assert_file_executable "$postinstall" "lumen-postinstall.sh must be executable"
    assert_file_executable "$launcher" "launch-calamares.sh must be executable"
    assert_syntax_valid "$postinstall" "sh"
    assert_syntax_valid "$launcher" "sh"
    assert_contains "$launcher" "QT_QPA_PLATFORM" "launch script must configure Qt platform"
    assert_contains "$postinstall" "skel" "postinstall hook must configure skeleton profile"
else
    test_case_skip "Calamares scripts not yet present"
fi
test_case_end


# ==============================================================================
# FEATURE F3: ISO Generation Pipeline (5 tests)
# ==============================================================================

# T1-F3-01: ISO Build Script Syntax & Strict Mode
test_case_start "T1_F3_01" "ISO build script syntax and strict safety settings"
build_iso_script="${WORKSPACE_ROOT}/scripts/build-iso.sh"
if [[ -f "$build_iso_script" ]]; then
    assert_file_executable "$build_iso_script" "build-iso.sh must be executable"
    assert_syntax_valid "$build_iso_script" "sh"
    assert_contains "$build_iso_script" "set -e" "build-iso.sh must operate under strict error handling"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end

# T1-F3-02: Debootstrap Minbase & Mirror Definition
test_case_start "T1_F3_02" "Debootstrap minbase configuration and mirror definitions"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "debootstrap" "build-iso.sh must invoke debootstrap"
    assert_contains "$build_iso_script" "minbase" "build-iso.sh must specify variant minbase"
    assert_contains "$build_iso_script" "amd64" "build-iso.sh must target amd64 architecture"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end

# T1-F3-03: Casper Manifests & Live User Setup
test_case_start "T1_F3_03" "Casper live session user and package manifest generation"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "filesystem.manifest" "build-iso.sh must generate filesystem manifests"
    assert_contains "$build_iso_script" "lumen" "build-iso.sh must configure live user lumen"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end

# T1-F3-04: SquashFS Zstandard Compression Specs
test_case_start "T1_F3_04" "SquashFS zstd compression parameters and block size"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "mksquashfs" "build-iso.sh must call mksquashfs"
    assert_contains "$build_iso_script" "zstd" "build-iso.sh must specify zstd compression"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end

# T1-F3-05: Dual Bootloader & Xorriso Command
test_case_start "T1_F3_05" "Dual UEFI and legacy BIOS bootloader mastering commands"
if [[ -f "$build_iso_script" ]]; then
    assert_contains "$build_iso_script" "xorriso" "build-iso.sh must invoke xorriso"
    assert_contains "$build_iso_script" "mkisofs" "build-iso.sh must use mkisofs emulation"
    assert_contains "$build_iso_script" "sha256" "build-iso.sh must compute sha256 checksum"
else
    test_case_skip "scripts/build-iso.sh not yet present"
fi
test_case_end


# ==============================================================================
# FEATURE F4: GitHub Actions CI Automation (5 tests)
# ==============================================================================

# T1-F4-01: CI Workflow Syntax & Triggers
test_case_start "T1_F4_01" "GitHub Actions workflow YAML syntax and execution triggers"
workflow_file="${WORKSPACE_ROOT}/.github/workflows/build-iso.yml"
if [[ -f "$workflow_file" ]]; then
    assert_syntax_valid "$workflow_file" "yaml"
    assert_contains "$workflow_file" "workflow_dispatch" "CI must support workflow_dispatch trigger"
    assert_contains "$workflow_file" "push" "CI must trigger on push"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end

# T1-F4-02: Runner Disk Cleanup Step
test_case_start "T1_F4_02" "Runner disk space reclamation commands in CI workflow"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "Free disk space|Disk space|cleanup|rm -rf" "CI must include disk cleanup step"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end

# T1-F4-03: Host Dependency Installation Step
test_case_start "T1_F4_03" "Host build dependencies installation step in CI workflow"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "debootstrap" "CI must install debootstrap"
    assert_contains "$workflow_file" "xorriso" "CI must install xorriso"
    assert_contains "$workflow_file" "squashfs-tools" "CI must install squashfs-tools"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end

# T1-F4-04: Build Script Execution Sequencing
test_case_start "T1_F4_04" "Packaging script execution precedes ISO build script in CI"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "package-debs.sh|build-debs.sh" "CI must execute packaging"
    assert_contains "$workflow_file" "build-iso.sh" "CI must execute build-iso.sh"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end

# T1-F4-05: Artifact Upload Specification
test_case_start "T1_F4_05" "CI artifact upload configuration targeting ISO and checksum"
if [[ -f "$workflow_file" ]]; then
    assert_contains "$workflow_file" "upload-artifact" "CI must use upload-artifact action"
    assert_contains "$workflow_file" "lumen-os-26.04-amd64.iso" "CI artifact upload must target ISO file"
else
    test_case_skip ".github/workflows/build-iso.yml not yet present"
fi
test_case_end


# ==============================================================================
# FEATURE F5: QEMU Test Script & Runner (5 tests)
# ==============================================================================

# T1-F5-01: QEMU Runner Syntax & Help Output
test_case_start "T1_F5_01" "QEMU test script syntax and CLI help option"
qemu_script="${WORKSPACE_ROOT}/scripts/test-iso-qemu.sh"
if [[ -f "$qemu_script" ]]; then
    assert_file_executable "$qemu_script" "test-iso-qemu.sh must be executable"
    assert_syntax_valid "$qemu_script" "sh"
    assert_exit_code 0 bash "$qemu_script" --help
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end

# T1-F5-02: UEFI Boot Mode Flag Parsing
test_case_start "T1_F5_02" "QEMU runner UEFI boot mode and OVMF firmware support"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "uefi" "QEMU script must support --uefi"
    assert_contains "$qemu_script" "OVMF" "QEMU script must reference OVMF firmware"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end

# T1-F5-03: Legacy BIOS Boot Mode Execution
test_case_start "T1_F5_03" "QEMU runner legacy BIOS boot mode support"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "bios" "QEMU script must support --bios"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end

# T1-F5-04: Headless Mode & Resource Allocation
test_case_start "T1_F5_04" "QEMU runner headless display and RAM/SMP allocation flags"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "headless" "QEMU script must support --headless"
    assert_contains "$qemu_script" "ram" "QEMU script must support --ram"
    assert_contains "$qemu_script" "smp" "QEMU script must support --smp"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end

# T1-F5-05: KVM Detection & TCG Fallback
test_case_start "T1_F5_05" "Hardware virtualization KVM check with TCG software fallback"
if [[ -f "$qemu_script" ]]; then
    assert_contains "$qemu_script" "/dev/kvm" "QEMU script must check /dev/kvm"
    assert_contains "$qemu_script" "tcg" "QEMU script must support tcg fallback"
else
    test_case_skip "scripts/test-iso-qemu.sh not yet present"
fi
test_case_end


# ==============================================================================
# FEATURE F6: Practical User Build Guide (5 tests)
# ==============================================================================

# T1-F6-01: User Guide Presence & Structure
test_case_start "T1_F6_01" "User build documentation presence and core structural sections"
guide_file="${WORKSPACE_ROOT}/docs/BUILD_ISO.md"
if [[ -f "$guide_file" ]]; then
    assert_file_not_empty "$guide_file" "BUILD_ISO.md must not be empty"
    assert_contains "$guide_file" "Prerequisite|Requirements" "Docs must cover prerequisites"
    assert_contains "$guide_file" "WSL2" "Docs must cover WSL2"
    assert_contains "$guide_file" "GitHub Actions" "Docs must cover GitHub Actions"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# T1-F6-02: Prerequisites Package Command
test_case_start "T1_F6_02" "Host system package prerequisites documented in build guide"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "debootstrap" "Docs must list debootstrap prerequisite"
    assert_contains "$guide_file" "xorriso" "Docs must list xorriso prerequisite"
    assert_contains "$guide_file" "squashfs-tools" "Docs must list squashfs-tools prerequisite"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# T1-F6-03: WSL2 Loopless Build Guidance
test_case_start "T1_F6_03" "WSL2 environment guidance and loop device constraints"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "loop|WSL" "Docs must document WSL2 loop device handling"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# T1-F6-04: Executable Snippet Consistency
test_case_start "T1_F6_04" "Documented commands align with project script entrypoints"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "build-iso.sh" "Docs must reference build-iso.sh"
    assert_contains "$guide_file" "package-debs.sh" "Docs must reference package-debs.sh"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# T1-F6-05: Checksum Verification Guide
test_case_start "T1_F6_05" "ISO image SHA256 checksum verification instructions in docs"
if [[ -f "$guide_file" ]]; then
    assert_contains "$guide_file" "sha256sum" "Docs must document sha256sum verification"
    assert_contains "$guide_file" "lumen-os-26.04-amd64.iso" "Docs must document ISO artifact name"
else
    test_case_skip "docs/BUILD_ISO.md not yet present"
fi
test_case_end

# Finalize Suite
suite_finish
