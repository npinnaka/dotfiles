#!/usr/bin/env bats

load test_helper

setup() {
    setup_sandbox
}

@test "state_init creates a versioned data-only journal and preserves existing records" {
    run_module state '
        DRY_RUN=0
        init_paths setup
        state_init
        [ -f "$STATE_DIR/journal.tsv" ]
        IFS= read -r header < "$STATE_DIR/journal.tsv"
        [ "$header" = "$(printf "dotfiles-state\t1")" ]
        state_record config key value extra
        before="$(cat "$STATE_DIR/journal.tsv")"
        state_init
        [ "$(cat "$STATE_DIR/journal.tsv")" = "$before" ]
    '
    assert_status 0
    assert_no_forbidden_commands
}

@test "state records persist across separate shell invocations" {
    run_module state '
        DRY_RUN=0
        init_paths setup
        state_init
        state_record config "key with spaces" "value with spaces" "extra with spaces"
    '
    assert_status 0
    run_module state '
        DRY_RUN=0
        init_paths uninstall
        state_init >/dev/null
        state_value config "key with spaces"
        state_extra config "key with spaces"
    '
    assert_status 0
    assert_output_equals $'value with spaces\nextra with spaces'
    assert_no_forbidden_commands
}

@test "recording the same kind and key replaces the record rather than duplicating it" {
    run_module state '
        DRY_RUN=0
        init_paths setup
        state_init >/dev/null
        state_record config key old old-extra >/dev/null
        state_record config key new new-extra >/dev/null
        state_each config
    '
    assert_status 0
    assert_output_equals $'key\tnew\tnew-extra'
    assert_no_forbidden_commands
}

@test "state lookups distinguish kind and exact literal keys" {
    run_module state '
        DRY_RUN=0
        init_paths setup
        state_init >/dev/null
        state_record config "key[1].*" "literal value" "literal extra" >/dev/null
        state_record config "key1-other" "different key" other >/dev/null
        state_record package "key[1].*" "different kind" other >/dev/null
        state_value config "key[1].*"
        state_extra config "key[1].*"
        state_value package "key[1].*"
    '
    assert_status 0
    assert_output_equals $'literal value\nliteral extra\ndifferent kind'
    assert_no_forbidden_commands
}

@test "state_each emits only matching key-value-extra rows, including an empty extra" {
    run_module state '
        DRY_RUN=0
        init_paths setup
        state_init >/dev/null
        state_record config one "first value" "" >/dev/null
        state_record package ignored package extra >/dev/null
        state_record config two "second value" "second extra" >/dev/null
        state_each config | sort
    '
    assert_status 0
    assert_output_equals $'one\tfirst value\t\ntwo\tsecond value\tsecond extra'
    assert_no_forbidden_commands
}

@test "state_forget removes only the requested kind and key" {
    run_module state '
        DRY_RUN=0
        init_paths setup
        state_init >/dev/null
        state_record config one first extra >/dev/null
        state_record config two second extra >/dev/null
        state_record package one package extra >/dev/null
        state_forget config one >/dev/null
        [ -z "$(state_value config one || :)" ]
        [ -z "$(state_extra config one || :)" ]
        state_each config
        state_each package
    '
    assert_status 0
    assert_output_equals $'two\tsecond\textra\none\tpackage\textra'
    assert_no_forbidden_commands
}

@test "state_record rejects tabs and newlines in every field without changing the journal" {
    run_module state '
        DRY_RUN=0
        init_paths setup
        state_init
        before="$(cat "$STATE_DIR/journal.tsv")"
        for bad in "$(printf "bad\tfield")" "$(printf "bad\nfield")"; do
            for field in kind key value extra; do
                case "$field" in
                    kind) set -- "$bad" key value extra ;;
                    key) set -- config "$bad" value extra ;;
                    value) set -- config key "$bad" extra ;;
                    extra) set -- config key value "$bad" ;;
                esac
                if state_record "$@" >/dev/null 2>&1; then
                    printf "accepted an invalid %s field\n" "$field" >&2
                    exit 1
                fi
                [ "$(cat "$STATE_DIR/journal.tsv")" = "$before" ]
            done
        done
    '
    assert_status 0
    assert_no_forbidden_commands
}

@test "state_record preserves shell metacharacters and literal backslashes" {
    local value='$(touch "$DOTFILES_TEST_HOME/evaluated"); C:\cache\new'
    local extra='`touch "$DOTFILES_TEST_HOME/backticks"` \t is text'
    run_module state '
        DRY_RUN=0
        init_paths setup
        state_init >/dev/null
        state_record config literal "$1" "$2" >/dev/null
        [ "$(state_value config literal)" = "$1" ]
        [ "$(state_extra config literal)" = "$2" ]
        [ "$(state_each config)" = "$(printf "literal\t%s\t%s" "$1" "$2")" ]
        [ ! -e "$DOTFILES_TEST_HOME/evaluated" ]
        [ ! -e "$DOTFILES_TEST_HOME/backticks" ]
    ' "$value" "$extra"
    assert_status 0
    assert_no_forbidden_commands
}

@test "journal contents are data, not executable shell input" {
    local value='$(touch "$DOTFILES_TEST_HOME/evaluated")'
    local extra='`touch "$DOTFILES_TEST_HOME/backticks"`'
    run_module state '
        DRY_RUN=0
        init_paths setup
        mkdir -p "$STATE_DIR"
        cp "$1" "$STATE_DIR/journal.tsv"
        state_init >/dev/null
        [ "$(state_value config literal)" = "$2" ]
        [ "$(state_extra config literal)" = "$3" ]
        [ "$(state_each config)" = "$(printf "literal\t%s\t%s" "$2" "$3")" ]
        [ ! -e "$DOTFILES_TEST_HOME/evaluated" ]
        [ ! -e "$DOTFILES_TEST_HOME/backticks" ]
    ' "$FIXTURES_DIR/state/data-only.tsv" "$value" "$extra"
    assert_status 0
    assert_no_forbidden_commands
}

@test "state_init rejects incompatible or executable headers without overwriting them" {
    local fixture
    for fixture in unsupported-version.tsv not-a-journal.tsv; do
        run_module state '
            DRY_RUN=0
            init_paths setup
            mkdir -p "$STATE_DIR"
            cp "$1" "$STATE_DIR/journal.tsv"
            before="$(cat "$STATE_DIR/journal.tsv")"
            if state_init; then
                printf "accepted an invalid journal header\n" >&2
                exit 1
            fi
            [ "$(cat "$STATE_DIR/journal.tsv")" = "$before" ]
            [ ! -e "$DOTFILES_TEST_HOME/evaluated" ]
        ' "$FIXTURES_DIR/state/$fixture"
        assert_status 0
    done
    assert_no_forbidden_commands
}

@test "dry-run state operations never create a journal or directories" {
    run_module state '
        DRY_RUN=1
        init_paths setup
        state_init
        state_record config key value extra
        state_forget config key
        [ ! -e "$STATE_DIR" ]
    '
    assert_status 0
    assert_no_preview_side_effects
}

@test "dry-run state operations leave an existing journal unchanged" {
    run_module state '
        DRY_RUN=0
        init_paths setup
        state_init
        state_record config key value extra
        before="$(cat "$STATE_DIR/journal.tsv")"
        DRY_RUN=1
        state_init
        state_record config key replacement replacement-extra
        state_record package added value extra
        state_forget config key
        [ "$(cat "$STATE_DIR/journal.tsv")" = "$before" ]
    '
    assert_status 0
    assert_no_forbidden_commands
}