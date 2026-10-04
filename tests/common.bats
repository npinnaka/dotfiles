#!/usr/bin/env bats

load test_helper

setup() {
    setup_sandbox
}

@test "common exposes its public helpers and a numeric dry-run default" {
    run_module common '
        declare -F run run_privileged log report with_logging init_paths
        [ "$DRY_RUN" = 0 ]
    '
    assert_status 0
    assert_no_preview_side_effects
}

@test "init_paths derives default XDG locations from the gated test home" {
    run_module common '
        DRY_RUN=1
        init_paths setup
        [ "$USER_HOME" = "$DOTFILES_TEST_HOME" ]
        [ "$CONFIG_HOME" = "$USER_HOME/.config" ]
        [ "$DATA_HOME" = "$USER_HOME/.local/share" ]
        case "$STATE_DIR" in "$USER_HOME/.local/state/"*) ;; *) exit 1 ;; esac
        [ "$LOG_FILE" = "$USER_HOME/.dotfiles_setup.log" ]
        [ "$SCRIPT_DIR" = "$1" ]
    ' "$PROJECT_ROOT"
    assert_status 0
    assert_no_preview_side_effects
}

@test "init_paths honors explicit XDG locations without creating them in dry-run" {
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg config"
    export XDG_DATA_HOME="$BATS_TEST_TMPDIR/xdg data"
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg state"
    run_module common '
        DRY_RUN=1
        init_paths uninstall
        [ "$USER_HOME" = "$DOTFILES_TEST_HOME" ]
        [ "$CONFIG_HOME" = "$XDG_CONFIG_HOME" ]
        [ "$DATA_HOME" = "$XDG_DATA_HOME" ]
        case "$STATE_DIR" in "$XDG_STATE_HOME/"*) ;; *) exit 1 ;; esac
        [ "$LOG_FILE" = "$USER_HOME/.dotfiles_uninstall.log" ]
    '
    assert_status 0
    [ ! -e "$XDG_CONFIG_HOME" ]
    [ ! -e "$XDG_DATA_HOME" ]
    [ ! -e "$XDG_STATE_HOME" ]
    assert_no_preview_side_effects
}

@test "empty XDG values use defaults from USER_HOME" {
    export XDG_CONFIG_HOME='' XDG_DATA_HOME='' XDG_STATE_HOME=''
    run_module common '
        DRY_RUN=1
        init_paths setup
        [ "$CONFIG_HOME" = "$USER_HOME/.config" ]
        [ "$DATA_HOME" = "$USER_HOME/.local/share" ]
        case "$STATE_DIR" in "$USER_HOME/.local/state/"*) ;; *) exit 1 ;; esac
    '
    assert_status 0
    assert_no_preview_side_effects
}

@test "DOTFILES_TEST_HOME is ignored unless DOTFILES_TESTING is exactly 1" {
    local gate
    for gate in unset 0 true; do
        run_module common '
            DRY_RUN=1
            if [ "$1" = unset ]; then
                unset DOTFILES_TESTING
            else
                DOTFILES_TESTING=$1
            fi
            init_paths setup
            [ "$USER_HOME" = "$HOME" ]
            [ "$USER_HOME" != "$DOTFILES_TEST_HOME" ]
        ' "$gate"
        assert_status 0
    done
    assert_no_preview_side_effects
}

@test "run executes arguments literally and preserves the child failure status" {
    run_module common '
        DRY_RUN=0
        child() { printf "<%s>\n" "$@"; return 37; }
        run child "argument with spaces" "*.literal" ""
    '
    assert_status 37
    assert_output_contains '<argument with spaces>'
    assert_output_contains '<*.literal>'
    assert_output_contains '<>'
    assert_no_preview_side_effects
}

@test "run and run_privileged do not execute anything in dry-run" {
    run_module common '
        DRY_RUN=1
        child() { : > "$DOTFILES_TEST_HOME/should-not-exist"; }
        run child
        run_privileged child
        run curl https://invalid.example.test/never-fetch
        run_privileged apt-get install never-install
    '
    assert_status 0
    assert_no_preview_side_effects
}

@test "log and report emit literal messages" {
    run_module common '
        log "log marker: 100% %s"
        report planned "report marker: 100% %s"
    '
    assert_status 0
    assert_output_contains 'log marker: 100% %s'
    assert_output_contains 'report marker: 100% %s'
    assert_output_matches 'planned'
    assert_no_preview_side_effects
}

@test "with_logging captures stdout and stderr and forwards all arguments" {
    allow_logging_tee
    run_module common '
        DRY_RUN=0
        LOG_FILE="$BATS_TEST_TMPDIR/run.log"
        child() {
            printf "<%s>\n" "$@"
            printf "%s\n" "stderr marker" >&2
        }
        with_logging child "argument with spaces" "*.literal" ""
    '
    assert_status 0
    assert_output_contains '<argument with spaces>'
    assert_output_contains '<*.literal>'
    assert_output_contains '<>'
    assert_output_contains 'stderr marker'
    local logged
    logged="$(< "$BATS_TEST_TMPDIR/run.log")"
    [[ "$logged" == *'<argument with spaces>'* ]]
    [[ "$logged" == *'<*.literal>'* ]]
    [[ "$logged" == *'<>'* ]]
    [[ "$logged" == *'stderr marker'* ]]
    assert_no_preview_side_effects
}

@test "with_logging preserves an exact child failure even with errexit enabled" {
    allow_logging_tee
    run_module common '
        DRY_RUN=0
        LOG_FILE="$BATS_TEST_TMPDIR/failure.log"
        child() { printf "%s\n" "child failed"; return 37; }
        with_logging child
    '
    assert_status 37
    assert_output_contains 'child failed'
    [ "$(< "$BATS_TEST_TMPDIR/failure.log")" = 'child failed' ]
    assert_no_preview_side_effects
}

@test "with_logging propagates a tee failure when the child succeeds" {
    allow_logging_tee 74
    run_module common '
        DRY_RUN=0
        LOG_FILE="$BATS_TEST_TMPDIR/failure.log"
        child() { printf "%s\n" marker; }
        with_logging child
    '
    assert_status 74
    assert_no_preview_side_effects
}

@test "with_logging does not mask a child failure with a tee failure" {
    allow_logging_tee 74
    run_module common '
        DRY_RUN=0
        LOG_FILE="$BATS_TEST_TMPDIR/failure.log"
        child() { printf "%s\n" marker; return 37; }
        with_logging child
    '
    assert_status 37
    assert_no_preview_side_effects
}

@test "with_logging bypasses tee and log creation entirely in dry-run" {
    run_module common '
        DRY_RUN=1
        LOG_FILE="$DOTFILES_TEST_HOME/not-created/run.log"
        child() { printf "%s\n" "preview marker"; return 29; }
        with_logging child
    '
    assert_status 29
    assert_output_contains 'preview marker'
    assert_no_preview_side_effects
}