#!/bin/bash

os_release_value() {
    # os-release is data, not shell code. Accept only its simple quoted values.
    awk -F= -v key="$2" '$1 == key {
        value = substr($0, index($0, "=") + 1)
        gsub(/^\042|\042$/, "", value)
        gsub(/^\047|\047$/, "", value)
        print value; exit
    }' "$1"
}

detect_platform() {
    local kernel machine release_file id version
    kernel=$(uname -s)
    machine=$(uname -m)
    release_file=/etc/os-release
    if [ "${DOTFILES_TESTING:-0}" = 1 ]; then
        kernel=${DOTFILES_TEST_UNAME:-$kernel}
        machine=${DOTFILES_TEST_ARCH:-$machine}
        release_file=${DOTFILES_TEST_OS_RELEASE:-$release_file}
    fi
    case "$kernel" in
        Darwin) PLATFORM=macos ;;
        Linux)
            [ -r "$release_file" ] || { fail 'Cannot read /etc/os-release.'; return 1; }
            id=$(os_release_value "$release_file" ID)
            version=$(os_release_value "$release_file" VERSION_ID)
            if [ "$id" != ubuntu ] || [ "$version" != 26.04 ]; then
                fail "Unsupported Linux release: $id $version; Ubuntu 26.04 is required."
                return 1
            fi
            PLATFORM=ubuntu
            ;;
        *) fail "Unsupported platform: $kernel"; return 1 ;;
    esac
    case "$machine" in
        x86_64|amd64) ARCH=amd64 ;;
        aarch64|arm64) ARCH=arm64 ;;
        *) fail "Unsupported architecture: $machine (expected amd64 or arm64)."; return 1 ;;
    esac
    export PLATFORM ARCH
}

resolve_gui_mode() {
    case "${MODE:-auto}" in
        desktop|headless) GUI_MODE=$MODE ;;
        auto)
            if [ "$PLATFORM" = macos ]; then
                GUI_MODE=desktop
            elif [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]; then
                GUI_MODE=headless
            elif [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
                GUI_MODE=desktop
            else
                GUI_MODE=headless
            fi
            ;;
        *) fail "Invalid mode: $MODE"; return 1 ;;
    esac
    export GUI_MODE
}

load_platform() {
    case "$PLATFORM" in
        macos|ubuntu)
            # shellcheck source=/dev/null
            . "$SCRIPT_DIR/lib/platforms/$PLATFORM.sh"
            ;;
        *) fail 'Platform detection must precede adapter selection.'; return 1 ;;
    esac
}