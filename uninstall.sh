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

print_help() {
    printf '%s\n' \
        'Usage: ./uninstall.sh [--dry-run] [--remove-packages] [-h|--help]' \
        'Default: revert only managed configuration; preserve packages and user data.' \
        '  --dry-run          Preview without writes, downloads, sudo, or service changes.' \
        '  --remove-packages  Remove only recorded, newly installed eligible packages.' \
        'Package managers, virtual environments, IDEs, containers and clusters are retained.'
}

parse_args() {
    DRY_RUN=0 REMOVE_PACKAGES=0 SHOW_HELP=0
    local arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=1 ;;
            --remove-packages) REMOVE_PACKAGES=1 ;;
            -h|--help) SHOW_HELP=1 ;;
            *) fail "Unknown argument: $arg"; return 2 ;;
        esac
    done
}

uninstall_workflow() {
    log "Platform: $PLATFORM | Architecture: $ARCH | Configuration-only by default"
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED 'Remove exact-target managed links and recognized shell blocks; restore unchanged backups and Git values.'
        if [ "$REMOVE_PACKAGES" = 1 ]; then
            platform_remove_owned_packages "$STATE_DIR"
        else
            report SKIPPED 'Packages retained (use --remove-packages to remove recorded eligible packages).'
        fi
        report SKIPPED 'Virtual environments, IDEs, third-party initialization data, containers, images and clusters are preserved.'
        summary
        log '[DONE] Preview complete; no changes made.'
        return 0
    fi

    draw_progress_bar 1 3 'Reverting configuration and symlinks'
    config_uninstall || return $?

    draw_progress_bar 2 3 'Removing packages (if requested)'
    if [ "$REMOVE_PACKAGES" = 1 ]; then
        platform_remove_owned_packages "$STATE_DIR" || return $?
    else
        report SKIPPED 'Packages retained (use --remove-packages to remove recorded eligible packages).'
    fi

    draw_progress_bar 3 3 'Cleaning state journal'
    state_cleanup || return $?
    report SKIPPED 'Virtual environments, IDEs, third-party initialization data, containers, images and clusters are preserved.'
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