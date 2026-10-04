#!/usr/bin/env bats

load test_helper

setup() {
    setup_sandbox
}

@test "Darwin normalizes x86_64 and arm64 without reading Linux release data" {
    local raw expected
    for raw in x86_64 arm64; do
        case "$raw" in x86_64) expected=amd64 ;; arm64) expected=arm64 ;; esac
        mock_platform Darwin "$raw" "$FIXTURES_DIR/os-release/ubuntu-24.04"
        run_module platform 'detect_platform; printf "%s %s\n" "$PLATFORM" "$ARCH"'
        assert_status 0
        assert_output_equals "macos $expected"
    done
    assert_no_preview_side_effects
}

@test "Ubuntu 26.04 normalizes x86_64, aarch64 and arm64" {
    local raw expected
    for raw in x86_64 aarch64 arm64; do
        case "$raw" in x86_64) expected=amd64 ;; *) expected=arm64 ;; esac
        mock_platform Linux "$raw"
        run_module platform 'detect_platform; printf "%s %s\n" "$PLATFORM" "$ARCH"'
        assert_status 0
        assert_output_equals "ubuntu $expected"
    done
    assert_no_preview_side_effects
}

@test "Linux rejects old Ubuntu, derivatives and incomplete release files" {
    local fixture
    for fixture in ubuntu-24.04 ubuntu-derivative missing-version; do
        mock_platform Linux x86_64 "$FIXTURES_DIR/os-release/$fixture"
        run_module platform 'detect_platform'
        assert_failure
    done
    assert_no_preview_side_effects
}

@test "Linux rejects a missing release file" {
    mock_platform Linux x86_64 "$BATS_TEST_TMPDIR/no-os-release"
    run_module platform 'detect_platform'
    assert_failure
    assert_no_preview_side_effects
}

@test "unsupported operating systems and architectures are rejected" {
    mock_platform FreeBSD x86_64
    run_module platform 'detect_platform'
    assert_failure
    mock_platform Linux mips64
    run_module platform 'detect_platform'
    assert_failure
    assert_no_preview_side_effects
}

@test "platform test hooks are ignored outside the exact testing gate" {
    run_module platform '
        unset DOTFILES_TESTING DOTFILES_TEST_UNAME DOTFILES_TEST_ARCH DOTFILES_TEST_OS_RELEASE
        detect_platform
        printf "%s %s\n" "$PLATFORM" "$ARCH"
    '
    local baseline_status="$status" baseline_output="$output" gate
    for gate in unset 0 true; do
        run_module platform '
            if [ "$1" = unset ]; then
                unset DOTFILES_TESTING
            else
                DOTFILES_TESTING=$1
            fi
            DOTFILES_TEST_UNAME=UnsupportedTestOS
            DOTFILES_TEST_ARCH=unsupported-test-arch
            DOTFILES_TEST_OS_RELEASE="$BATS_TEST_TMPDIR/not-a-release-file"
            detect_platform
            printf "%s %s\n" "$PLATFORM" "$ARCH"
        ' "$gate"
        assert_status "$baseline_status"
        assert_output_equals "$baseline_output"
    done
    assert_no_preview_side_effects
}

@test "auto mode defaults macOS to desktop even over SSH" {
    export SSH_CONNECTION='192.0.2.1 1234 192.0.2.2 22'
    run_module platform 'PLATFORM=macos; MODE=auto; resolve_gui_mode; printf "%s\n" "$GUI_MODE"'
    assert_status 0
    assert_output_equals desktop
}

@test "auto mode defaults Ubuntu without a display to headless" {
    run_module platform 'PLATFORM=ubuntu; MODE=auto; resolve_gui_mode; printf "%s\n" "$GUI_MODE"'
    assert_status 0
    assert_output_equals headless
}

@test "auto mode recognizes an X11 display or a Wayland display" {
    export DISPLAY=:42
    run_module platform 'PLATFORM=ubuntu; MODE=auto; resolve_gui_mode; printf "%s\n" "$GUI_MODE"'
    assert_status 0
    assert_output_equals desktop
    unset DISPLAY
    export WAYLAND_DISPLAY=wayland-test
    run_module platform 'PLATFORM=ubuntu; MODE=auto; resolve_gui_mode; printf "%s\n" "$GUI_MODE"'
    assert_status 0
    assert_output_equals desktop
}

@test "any SSH session indicator makes Ubuntu auto mode headless despite a display" {
    local indicator
    for indicator in SSH_CONNECTION SSH_CLIENT SSH_TTY; do
        run_module platform '
            export "$1=present" DISPLAY=:42 WAYLAND_DISPLAY=wayland-test
            PLATFORM=ubuntu
            MODE=auto
            resolve_gui_mode
            printf "%s\n" "$GUI_MODE"
        ' "$indicator"
        assert_status 0
        assert_output_equals headless
    done
}

@test "explicit desktop and headless modes override auto detection" {
    export SSH_CONNECTION='192.0.2.1 1234 192.0.2.2 22'
    run_module platform 'PLATFORM=ubuntu; MODE=desktop; resolve_gui_mode; printf "%s\n" "$GUI_MODE"'
    assert_status 0
    assert_output_equals desktop
    run_module platform 'PLATFORM=macos; MODE=headless; resolve_gui_mode; printf "%s\n" "$GUI_MODE"'
    assert_status 0
    assert_output_equals headless
}

@test "an unknown GUI mode is rejected" {
    run_module platform 'PLATFORM=ubuntu; MODE=invalid; resolve_gui_mode'
    assert_failure
    assert_no_preview_side_effects
}