#!/bin/bash
# uninstall.sh - Conservative, ownership-aware dotfiles removal.

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
        'Usage: ./uninstall.sh [--dry-run] [--remove-packages] [--purge-runtimes] [--purge-all] [-h|--help]' \
        'Default: revert only managed configuration; preserve packages and user data.' \
        '  --dry-run             Preview without writes, downloads, sudo, or service changes.' \
        '  --remove-packages     Remove only recorded, newly installed eligible packages.' \
        '  --purge-runtimes      Purge recorded developer runtimes (Python venv, Kind clusters).' \
        '  --purge-all, --purge  Complete uninstallation (revert config, remove packages, purge runtimes).' \
        'Package managers and pre-existing system packages are retained.'
}

parse_args() {
    DRY_RUN=0 REMOVE_PACKAGES=0 PURGE_RUNTIMES=0 SHOW_HELP=0
    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=1 ;;
            --remove-packages) REMOVE_PACKAGES=1 ;;
            --purge-runtimes) PURGE_RUNTIMES=1 ;;
            --purge|--purge-all) REMOVE_PACKAGES=1; PURGE_RUNTIMES=1 ;;
            -h|--help) SHOW_HELP=1 ;;
            *) fail "Unknown argument: $arg"; return 2 ;;
        esac
    done
}

uninstall_workflow() {
    local mode_desc="Configuration-only by default"
    if [ "$REMOVE_PACKAGES" = 1 ] && [ "$PURGE_RUNTIMES" = 1 ]; then
        mode_desc="Full purge (config, packages, runtimes)"
    elif [ "$REMOVE_PACKAGES" = 1 ]; then
        mode_desc="Configuration and packages"
    elif [ "$PURGE_RUNTIMES" = 1 ]; then
        mode_desc="Configuration and runtimes"
    fi

    log "Platform: $PLATFORM | Architecture: $ARCH | Mode: $mode_desc"
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED 'Remove exact-target managed links and recognized shell blocks; restore unchanged backups and Git values.'
        if [ "$REMOVE_PACKAGES" = 1 ]; then
            platform_remove_owned_packages "$STATE_DIR"
        else
            report SKIPPED 'Packages retained (use --remove-packages or --purge-all to remove recorded eligible packages).'
        fi
        if [ "$PURGE_RUNTIMES" = 1 ]; then
            runtime_purge
        else
            report SKIPPED 'Virtual environments, IDEs, containers, images and clusters are preserved (use --purge-runtimes or --purge-all to purge).'
        fi
        summary
        log '[DONE] Preview complete; no changes made.'
        return 0
    fi

    local total_steps=3
    [ "$PURGE_RUNTIMES" = 1 ] && total_steps=4

    draw_progress_bar 1 "$total_steps" 'Reverting configuration and symlinks'
    config_uninstall || return $?

    draw_progress_bar 2 "$total_steps" 'Removing packages (if requested)'
    if [ "$REMOVE_PACKAGES" = 1 ]; then
        platform_remove_owned_packages "$STATE_DIR" || return $?
    else
        report SKIPPED 'Packages retained (use --remove-packages or --purge-all to remove recorded eligible packages).'
    fi

    if [ "$PURGE_RUNTIMES" = 1 ]; then
        draw_progress_bar 3 "$total_steps" 'Purging runtime environments'
        runtime_purge || return $?
        draw_progress_bar 4 "$total_steps" 'Cleaning state journal'
    else
        report SKIPPED 'Virtual environments, IDEs, containers, images and clusters are preserved (use --purge-runtimes or --purge-all to purge).'
        draw_progress_bar 3 "$total_steps" 'Cleaning state journal'
    fi

    state_cleanup || return $?
    summary
    log '[DONE] Uninstallation complete!'
}

main() {
    parse_args "$@"
    if [ "$SHOW_HELP" = 1 ]; then print_help; return 0; fi
    detect_platform
    init_paths uninstall
    state_validate
    check_user
    load_platform
    with_logging uninstall_workflow
}

main "$@"