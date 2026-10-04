#!/usr/bin/env bats

load test_helper

setup() {
    setup_sandbox
}

@test "sandbox uses an explicit test home without changing HOME or stubbing uname" {
    [ "$DOTFILES_TESTING" = 1 ]
    case "$DOTFILES_TEST_HOME" in
        "$BATS_TEST_TMPDIR/"*) ;;
        *) return 1 ;;
    esac
    [ "$DOTFILES_TEST_HOME" != "$HOME" ]
    [ ! -e "$STUB_BIN/uname" ]
    assert_no_preview_side_effects
}

@test "command guard records and rejects dry-run side effects" {
    local tool
    for tool in sudo curl brew apt-get systemctl uv podman kubectl helm tee; do
        run "$STUB_BIN/$tool" 'argument with spaces'
        assert_status 97
        assert_output_contains "forbidden command invoked: $tool"
    done
    local calls
    calls="$(< "$DOTFILES_TEST_COMMAND_LOG")"
    [[ "$calls" == *$'sudo\targument with spaces'* ]]
    [[ "$calls" == *$'podman\targument with spaces'* ]]
    assert_home_untouched
}

@test "minimal PATH omits package tools but retains the real uname" {
    make_minimal_path
    local expected
    expected="$(uname -s)"
    run env PATH="$MINIMAL_PATH" "$TEST_SHELL" -c '
        for tool in sudo curl brew apt-get systemctl uv podman kubectl helm tee; do
            if command -v "$tool" >/dev/null 2>&1; then
                exit 1
            fi
        done
        uname -s
    '
    assert_status 0
    assert_output_equals "$expected"
    assert_no_preview_side_effects
}

@test "tee fixture delegates only when explicitly enabled" {
    allow_logging_tee
    run "$TEST_SHELL" -c 'printf "%s\n" marker | tee "$1"' \
        dotfiles-test "$BATS_TEST_TMPDIR/tee.log"
    assert_status 0
    assert_output_equals marker
    [ "$(< "$BATS_TEST_TMPDIR/tee.log")" = marker ]
    assert_no_preview_side_effects
}

@test "tee fixture can fail without creating a log" {
    allow_logging_tee 74
    run "$TEST_SHELL" -c 'printf "%s\n" marker | tee "$1"' \
        dotfiles-test "$BATS_TEST_TMPDIR/tee.log"
    assert_status 74
    [ ! -e "$BATS_TEST_TMPDIR/tee.log" ]
    assert_no_preview_side_effects
}