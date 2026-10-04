#!/bin/bash
# Shared execution helpers. Compatible with the macOS system Bash (3.2).

DRY_RUN=${DRY_RUN:-0}
ACTION_PLANNED=0
ACTION_INSTALLED=0
ACTION_PRESENT=0
ACTION_SKIPPED=0
ACTION_FAILED=0

log() {
    printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

report() {
    local status=$1
    shift
    case "$status" in
        PLANNED) ACTION_PLANNED=$((ACTION_PLANNED + 1)) ;;
        INSTALLED) ACTION_INSTALLED=$((ACTION_INSTALLED + 1)) ;;
        PRESENT) ACTION_PRESENT=$((ACTION_PRESENT + 1)) ;;
        SKIPPED) ACTION_SKIPPED=$((ACTION_SKIPPED + 1)) ;;
        FAILED) ACTION_FAILED=$((ACTION_FAILED + 1)) ;;
    esac
    log "[$status] $*"
}

fail() {
    report FAILED "$*" >&2
    return 1
}

draw_progress_bar() {
    printf '\n[%s/%s] %s\n' "$1" "$2" "$3"
}

print_command() {
    printf '    '
    printf '%q ' "$@"
    printf '\n'
}

file_checksum() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum < "$1" | awk '{print $1}'
    else
        shasum -a 256 < "$1" | awk '{print $1}'
    fi
}

# Redirects and compound mutations belong inside a function passed to run,
# never outside this guard (a shell opens redirects before calling a function).
run() {
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "$1"
        print_command "$@"
        return 0
    fi
    "$@"
}

run_privileged() {
    if [ "$DRY_RUN" = 1 ]; then
        run sudo "$@"
    elif [ "$(id -u)" = 0 ]; then
        "$@"
    else
        # No up-front sudo session, keep-alive, or credential invalidation.
        sudo -- "$@"
    fi
}

init_paths() {
    local operation=$1
    USER_HOME=$HOME
    if [ "${DOTFILES_TESTING:-0}" = 1 ]; then
        USER_HOME=${DOTFILES_TEST_HOME:?DOTFILES_TEST_HOME is required for tests}
    fi
    CONFIG_HOME=${XDG_CONFIG_HOME:-$USER_HOME/.config}
    DATA_HOME=${XDG_DATA_HOME:-$USER_HOME/.local/share}
    STATE_DIR=${XDG_STATE_HOME:-$USER_HOME/.local/state}/dotfiles
    BIN_HOME=$USER_HOME/.local/bin
    LOG_FILE=$USER_HOME/.dotfiles_${operation}.log
    export USER_HOME CONFIG_HOME DATA_HOME STATE_DIR BIN_HOME LOG_FILE
    local path
    for path in "$USER_HOME" "$CONFIG_HOME" "$DATA_HOME" "$STATE_DIR" "$SCRIPT_DIR"; do
        case "$path" in
            /*) ;;
            *) fail "Paths must be absolute: $path"; return 1 ;;
        esac
        case "$path" in
            *$'\t'*|*$'\n'*|*$'\r'*) fail 'Tabs/newlines in paths are not supported.'; return 1 ;;
        esac
    done
}

check_user() {
    if [ "$DRY_RUN" != 1 ] && [ "${DOTFILES_TESTING:-0}" != 1 ] && [ "$(id -u)" = 0 ]; then
        fail 'Run as your normal user, not root. Sudo is requested only for system packages.'
        return 1
    fi
}

initialize_log() {
    [ ! -L "$LOG_FILE" ] || { fail "Refusing symlink log: $LOG_FILE"; return 1; }
    (umask 077; : >> "$LOG_FILE")
}

with_logging() {
    if [ "$DRY_RUN" = 1 ]; then
        "$@"
        return $?
    fi
    run initialize_log || return $?
    local codes
    # Keep errexit inside the workflow, but capture both pipeline statuses in
    # the parent. There is no recursive entrypoint or inherited logging flag.
    set +e
    (set -e; "$@") 2>&1 | tee -a "$LOG_FILE"
    codes=("${PIPESTATUS[@]}")
    set -e
    [ "${codes[0]}" = 0 ] || return "${codes[0]}"
    return "${codes[1]}"
}

summary() {
    printf '\nSummary: %s planned, %s installed, %s present, %s skipped, %s failed.\n' \
        "$ACTION_PLANNED" "$ACTION_INSTALLED" "$ACTION_PRESENT" "$ACTION_SKIPPED" "$ACTION_FAILED"
}