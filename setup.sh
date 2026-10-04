#!/bin/bash
# setup.sh - Shared dotfiles setup with native OS adapters.

set -e
set -o pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/platform.sh
. "$SCRIPT_DIR/lib/platform.sh"
# shellcheck source=lib/state.sh
. "$SCRIPT_DIR/lib/state.sh"
# shellcheck source=lib/config.sh
. "$SCRIPT_DIR/lib/config.sh"
# shellcheck source=lib/runtime.sh
. "$SCRIPT_DIR/lib/runtime.sh"

print_help() {
    printf '%s\n' \
        'Usage: ./setup.sh <home|work> [--dry-run] [--desktop|--headless] [--skip-cluster]' \
        'Supports macOS and Ubuntu 26.04 (amd64/arm64).' \
        '  --dry-run       Preview without writes, downloads, sudo, or service changes.' \
        '  --desktop       Include GUI applications, fonts, and desktop configuration.' \
        '  --headless      CLI configuration and tools only.' \
        '  --skip-cluster  Do not create a home-profile kind cluster.' \
        '  -h, --help      Show help.'
}

parse_args() {
    PROFILE='' MODE=auto DRY_RUN=0 SKIP_CLUSTER=0 SHOW_HELP=0
    local arg
    for arg in "$@"; do
        case "$arg" in
            home|work)
                [ -z "$PROFILE" ] || { fail 'Specify exactly one profile.'; return 2; }
                PROFILE=$arg ;;
            --dry-run) DRY_RUN=1 ;;
            --skip-cluster) SKIP_CLUSTER=1 ;;
            --desktop|--headless)
                if [ "$MODE" != auto ] && [ "$MODE" != "${arg#--}" ]; then
                    fail '--desktop and --headless conflict.'; return 2
                fi
                MODE=${arg#--} ;;
            -h|--help) SHOW_HELP=1 ;;
            *) fail "Unknown argument: $arg"; return 2 ;;
        esac
    done
    if [ "$SHOW_HELP" != 1 ] && [ -z "$PROFILE" ]; then
        fail 'A home or work profile is required.'; return 2
    fi
}

setup_workflow() {
    log "Platform: $PLATFORM | Architecture: $ARCH | Profile: $PROFILE | Mode: $GUI_MODE"
    draw_progress_bar 1 4 'Installing profile packages'
    platform_install_packages "$PROFILE" "$GUI_MODE" || return $?
    draw_progress_bar 2 4 'Configuring shell and applications'
    config_setup_links "$PROFILE" "$GUI_MODE" || return $?
    config_setup_zsh || return $?
    config_setup_git "$PROFILE" || return $?
    draw_progress_bar 3 4 'Configuring desktop and editors'
    runtime_setup_idea_plugins "$GUI_MODE" || return $?
    draw_progress_bar 4 4 'Configuring runtimes and containers'
    runtime_setup_python_venv || return $?
    runtime_setup_rtk || return $?
    runtime_setup_containers "$PLATFORM" "$PROFILE" "$SKIP_CLUSTER" || return $?
    summary
    if [ "$DRY_RUN" = 1 ]; then
        log '[DONE] Preview complete; no changes made.'
    else
        log '[DONE] Setup complete!'
    fi
}

main() {
    parse_args "$@"
    if [ "$SHOW_HELP" = 1 ]; then print_help; return 0; fi
    detect_platform
    resolve_gui_mode
    init_paths setup
    state_validate
    check_user
    load_platform
    with_logging setup_workflow
}

main "$@"