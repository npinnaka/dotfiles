#!/usr/bin/env bats
# Programs expand in child shells; Bats intentionally isolates each test.
# shellcheck disable=SC2016,SC2030,SC2031

load test_helper

setup() {
    setup_sandbox
    mock_platform Darwin arm64
    export DOTFILES_MACOS_FIXTURE="$DOTFILES_TEST_HOME/macos-fixture"
    export DOTFILES_MACOS_LOG="$BATS_TEST_TMPDIR/macos-commands.log"
    export DOTFILES_MACOS_BREW="$STUB_BIN/brew"
    export DOTFILES_MACOS_BREW_PREFIX="$DOTFILES_MACOS_FIXTURE/brew prefix"
    unset DOTFILES_MACOS_CURL_STATUS DOTFILES_MACOS_INSTALL_STATUS
    unset DOTFILES_MACOS_BUNDLE_STATUS DOTFILES_MACOS_FAIL_FILE
    unset DOTFILES_MACOS_PARTIAL_FORMULA DOTFILES_MACOS_PARTIAL_CASK
    unset DOTFILES_MACOS_DEPENDENCY_FORMULA DOTFILES_MACOS_LIST_STATUS DOTFILES_GUI
    unset DOTFILES_MACOS_SHELLENV_STATUS DOTFILES_MACOS_OMIT_PACKAGE DOTFILES_MACOS_ABSENT_STATUS
    unset DOTFILES_MACOS_INSPECT_PHASE DOTFILES_MACOS_INSPECT_PACKAGE DOTFILES_MACOS_INSPECT_STATUS
    unset HOMEBREW_CASK_OPTS HOMEBREW_PREFIX HOMEBREW_CELLAR HOMEBREW_REPOSITORY
}

allow_macos_commands() {
    local tool
    for tool in brew curl; do
        rm "$STUB_BIN/$tool"
        ln -s "$PROJECT_ROOT/tests/stubs/macos-command.bash" "$STUB_BIN/$tool"
    done
    mkdir -p "$DOTFILES_MACOS_FIXTURE/formula" "$DOTFILES_MACOS_FIXTURE/cask"
    mkdir -p "$DOTFILES_MACOS_BREW_PREFIX/bin" "$DOTFILES_MACOS_BREW_PREFIX/sbin"
    ln -s "$PROJECT_ROOT/tests/stubs/macos-command.bash" "$DOTFILES_MACOS_BREW_PREFIX/bin/brew"
    ln -s "$STUB_BIN/uv" "$DOTFILES_MACOS_BREW_PREFIX/bin/uv"
}

run_macos() {
    local program=$1
    shift
    run_module state '
        . "$SCRIPT_DIR/lib/platforms/macos.sh"
        init_paths setup
        ARCH=arm64
        '"$program" "$@"
}

read_packages() {
    run_macos 'state_each package'
    assert_status 0
}

@test "macOS dry-run previews native bundles without even read-only package commands" {
    local profile mode
    for profile in home work; do
        for mode in desktop headless; do
            run_macos 'DRY_RUN=1; platform_install_packages "$1" "$2"' "$profile" "$mode"
            assert_status 0
            assert_output_contains "DOTFILES_GUI=$mode"
            assert_output_contains "Brewfile.common"
            assert_output_contains "Brewfile.$profile"
            assert_output_contains 'bundle'
            assert_no_preview_side_effects
        done
    done
}

@test "macOS dry-run previews official bootstrap and both bundles when tools are absent" {
    make_minimal_path
    run_macos '
        PATH=$1
        macos_find_brew() { return 1; }
        DRY_RUN=1
        platform_install_packages work headless
    ' "$MINIMAL_PATH"
    assert_status 0
    assert_output_contains 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
    assert_output_contains '/opt/homebrew/bin/brew'
    assert_output_contains 'Brewfile.common'
    assert_output_contains 'Brewfile.work'
    assert_output_contains 'DOTFILES_GUI=headless'
    assert_no_preview_side_effects
}

@test "macOS Intel dry-run selects the Intel bootstrap path without downloads or activation" {
    make_minimal_path
    run_macos '
        PATH=$1
        ARCH=amd64
        macos_find_brew() { return 1; }
        DRY_RUN=1
        platform_install_packages home desktop
    ' "$MINIMAL_PATH"
    assert_status 0
    assert_output_contains '/usr/local/bin/brew'
    assert_output_contains 'HOMEBREW_CASK_OPTS=--appdir='
    assert_output_contains 'Applications'
    [ ! -e "$DOTFILES_MACOS_LOG" ]
    assert_no_preview_side_effects
}

@test "macOS locates brew on PATH without invoking it" {
    allow_macos_commands
    run_macos 'macos_find_brew'
    assert_status 0
    assert_output_equals "$DOTFILES_MACOS_BREW"
    [ ! -e "$DOTFILES_MACOS_LOG" ]
    assert_no_forbidden_commands
}

@test "macOS discovers either native Homebrew prefix without executing brew" {
    local native
    for native in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        run_macos '
            native=$1
            command() {
                if [ "$1" = -v ] && [ "$2" = brew ]; then return 1; fi
                builtin command "$@"
            }
            [() {
                if builtin [ "$#" = 3 ] && builtin [ "$1" = -x ]; then
                    case "$2" in
                        /opt/homebrew/bin/brew|/usr/local/bin/brew)
                            builtin [ "$2" = "$native" ]; return $? ;;
                    esac
                fi
                builtin [ "$@"
            }
            macos_find_brew
        ' "$native"
        assert_status 0
        assert_output_equals "$native"
        [ ! -e "$DOTFILES_MACOS_LOG" ]
        assert_no_preview_side_effects
    done
}

@test "macOS activates Homebrew in the current shell for later shared stages" {
    allow_macos_commands
    run_macos '
        platform_install_packages home headless
        [ "$HOMEBREW_PREFIX" = "$DOTFILES_MACOS_BREW_PREFIX" ]
        [ "$HOMEBREW_CELLAR" = "$DOTFILES_MACOS_BREW_PREFIX/Cellar" ]
        [ "$HOMEBREW_REPOSITORY" = "$DOTFILES_MACOS_BREW_PREFIX/Homebrew" ]
        [ "$(command -v brew)" = "$DOTFILES_MACOS_BREW_PREFIX/bin/brew" ]
        [ "$(command -v uv)" = "$DOTFILES_MACOS_BREW_PREFIX/bin/uv" ]
    '
    assert_status 0
    [[ "$(< "$DOTFILES_MACOS_LOG")" == *$'brew\theadless\tshellenv\tbash'* ]]
    [ "$HOME" = "$ORIGINAL_HOME" ]
    assert_no_forbidden_commands
}

@test "macOS preserves a Homebrew activation failure without running bundles" {
    allow_macos_commands
    export DOTFILES_MACOS_SHELLENV_STATUS=41
    run_macos 'platform_install_packages home headless'
    assert_status 41
    [ ! -e "$DOTFILES_MACOS_FIXTURE/bundle-started" ]
    read_packages
    assert_output_contains $'manager:homebrew\tpreexisting\tprotected'
    [[ "$output" != *brew:kind* ]]
    assert_no_forbidden_commands
}

@test "macOS routes casks to user Applications with spaces and retains caller options" {
    allow_macos_commands
    export HOMEBREW_CASK_OPTS=--no-quarantine
    run_macos '
        platform_install_packages work desktop
        [ "$HOMEBREW_CASK_OPTS" = --no-quarantine ]
    '
    assert_status 0
    local expected file
    printf -v expected '%q' "--appdir=$DOTFILES_TEST_HOME/Applications"
    for file in Brewfile.common Brewfile.work; do
        [ "$(< "$DOTFILES_MACOS_FIXTURE/cask-options-$file")" = "$expected --no-quarantine" ]
    done
    [ "$HOME" = "$ORIGINAL_HOME" ]
    assert_no_forbidden_commands
}

@test "macOS headless work uses native list and bundle with CLI casks retained" {
    allow_macos_commands
    export DOTFILES_GUI=desktop
    run_macos 'platform_install_packages work headless'
    assert_status 0
    local commands
    commands=$(< "$DOTFILES_MACOS_LOG")
    [[ "$commands" == *$'brew\theadless\tbundle\tlist'*'--formula'* ]]
    [[ "$commands" == *$'brew\theadless\tbundle\tlist'*'--cask'* ]]
    [[ "$commands" == *$'brew\theadless\tbundle\t--file='"$PROJECT_ROOT/Brewfile.common"* ]]
    [[ "$commands" == *$'brew\theadless\tbundle\t--file='"$PROJECT_ROOT/Brewfile.work"* ]]
    [[ "$commands" != *$'brew\tdesktop\t'* ]]
    read_packages
    assert_output_contains $'cask:claude-code\towned\teligible'
    assert_output_contains $'cask:corretto@21\towned\tprotected'
    [[ "$output" != *ghostty* && "$output" != *font-* && "$output" != *pgadmin4* ]]
    [ "$HOME" = "$ORIGINAL_HOME" ]
    assert_no_forbidden_commands
}

@test "macOS desktop home includes GUI casks and fonts but not work packages" {
    allow_macos_commands
    run_macos 'platform_install_packages home desktop'
    assert_status 0
    read_packages
    assert_output_contains $'cask:ghostty\towned\teligible'
    assert_output_contains $'cask:font-jetbrains-mono-nerd-font\towned\teligible'
    assert_output_contains $'cask:brave-browser\towned\teligible'
    assert_output_contains $'cask:google-chrome\towned\teligible'
    assert_output_contains $'cask:rectangle\towned\teligible'
    [[ "$output" != *claude-code* && "$output" != *corretto* && "$output" != *brew:node* ]]
    assert_no_forbidden_commands
}

@test "macOS snapshots preexisting packages before upgrades and protects foundations" {
    allow_macos_commands
    touch "$DOTFILES_MACOS_FIXTURE/formula/jq" "$DOTFILES_MACOS_FIXTURE/cask/claude-code"
    run_macos 'platform_install_packages work headless'
    assert_status 0
    [ "$(< "$DOTFILES_MACOS_FIXTURE/formula/jq")" = 2 ]
    local before
    before=$(< "$DOTFILES_MACOS_FIXTURE/before-Brewfile.common.tsv")
    [[ "$before" == *$'package\tbrew:jq\tpreexisting\tprotected'* ]]
    [[ "$before" == *$'package\tcask:claude-code\tpreexisting\tprotected'* ]]
    [[ "$before" != *$'brew:kind\towned'* ]]
    read_packages
    assert_output_contains $'manager:homebrew\tpreexisting\tprotected'
    assert_output_contains $'brew:jq\tpreexisting\tprotected'
    assert_output_contains $'cask:claude-code\tpreexisting\tprotected'
    assert_output_contains $'brew:kind\towned\teligible'
    assert_output_contains $'brew:yq\towned\teligible'
    assert_output_contains $'brew:python\towned\tprotected'
    assert_output_contains $'brew:node\towned\tprotected'
    [[ "$output" != *openssl@3* ]]
    assert_no_forbidden_commands
}

@test "macOS records new packages after a partial profile bundle failure and returns its status" {
    allow_macos_commands
    touch "$DOTFILES_MACOS_FIXTURE/formula/jq" "$DOTFILES_MACOS_FIXTURE/cask/corretto@21"
    export DOTFILES_MACOS_BUNDLE_STATUS=43
    export DOTFILES_MACOS_PARTIAL_FORMULA=yq DOTFILES_MACOS_PARTIAL_CASK=claude-code
    run_macos 'platform_install_packages work headless'
    assert_status 43
    read_packages
    assert_output_contains $'brew:jq\tpreexisting\tprotected'
    assert_output_contains $'cask:corretto@21\tpreexisting\tprotected'
    assert_output_contains $'brew:kind\towned\teligible'
    assert_output_contains $'brew:yq\towned\teligible'
    assert_output_contains $'cask:claude-code\towned\teligible'
    [[ "$output" != *brew:node* ]]
    assert_no_forbidden_commands
}

@test "macOS records partial common results and preexisting profile packages without running the profile" {
    allow_macos_commands
    touch "$DOTFILES_MACOS_FIXTURE/formula/yq"
    export DOTFILES_MACOS_FAIL_FILE=Brewfile.common DOTFILES_MACOS_BUNDLE_STATUS=53
    export DOTFILES_MACOS_PARTIAL_FORMULA=kind DOTFILES_MACOS_PARTIAL_CASK=ghostty
    run_macos 'platform_install_packages work desktop'
    assert_status 53
    [ ! -e "$DOTFILES_MACOS_FIXTURE/before-Brewfile.work.tsv" ]
    read_packages
    assert_output_contains $'brew:yq\tpreexisting\tprotected'
    assert_output_contains $'brew:kind\towned\teligible'
    assert_output_contains $'cask:ghostty\towned\teligible'
    [[ "$output" != *brew:python* && "$output" != *claude-code* ]]
    assert_no_forbidden_commands
}

@test "macOS snapshots both Brewfiles before a common dependency satisfies a profile request" {
    allow_macos_commands
    export DOTFILES_MACOS_DEPENDENCY_FORMULA=yq
    run_macos 'platform_install_packages work headless'
    assert_status 0
    read_packages
    assert_output_contains $'brew:yq\towned\teligible'
    assert_no_forbidden_commands
}

@test "macOS uses native installed checks for formula aliases without claiming existing runtimes" {
    allow_macos_commands
    touch "$DOTFILES_MACOS_FIXTURE/formula/python"
    run_macos 'platform_install_packages home headless'
    assert_status 0
    read_packages
    assert_output_contains $'brew:python\tpreexisting\tprotected'
    [[ "$output" != *brew:python@3.14* ]]
    assert_no_forbidden_commands
}

@test "macOS repeated bundles keep existing ownership and literal journal data unchanged" {
    allow_macos_commands
    touch "$DOTFILES_MACOS_FIXTURE/formula/jq"
    run_macos '
        state_record config literal "$1" "$2"
        platform_install_packages home headless
        before=$(cat "$STATE_DIR/journal.tsv")
        platform_install_packages home headless
        [ "$(cat "$STATE_DIR/journal.tsv")" = "$before" ]
        [ "$(state_value config literal)" = "$1" ]
        [ "$(state_extra config literal)" = "$2" ]
        state_each package
    ' '$(touch "$DOTFILES_TEST_HOME/evaluated"); C:\cache\new' '`touch "$DOTFILES_TEST_HOME/backticks"`'
    assert_status 0
    assert_output_contains $'brew:jq\tpreexisting\tprotected'
    assert_output_contains $'brew:kind\towned\teligible'
    [ ! -e "$DOTFILES_TEST_HOME/evaluated" ]
    [ ! -e "$DOTFILES_TEST_HOME/backticks" ]
    assert_no_forbidden_commands
}

@test "macOS native bundle list failure stops before package installation" {
    allow_macos_commands
    export DOTFILES_MACOS_LIST_STATUS=32
    run_macos 'platform_install_packages home headless'
    assert_status 32
    [ ! -e "$DOTFILES_MACOS_FIXTURE/before-Brewfile.common.tsv" ]
    assert_no_forbidden_commands
}

@test "macOS fails if a successful bundle leaves a requested formula missing and journals the rest" {
    allow_macos_commands
    export DOTFILES_MACOS_OMIT_PACKAGE=formula:jq
    run_macos 'platform_install_packages home headless'
    assert_status 1
    assert_output_contains 'jq'
    read_packages
    assert_output_contains $'brew:kind\towned\teligible'
    assert_output_contains $'brew:python\towned\tprotected'
    [[ "$output" != *brew:jq* ]]
    assert_no_forbidden_commands
}

@test "macOS fails for an empty successful cask inventory after a successful bundle" {
    allow_macos_commands
    export DOTFILES_MACOS_OMIT_PACKAGE=cask:claude-code DOTFILES_MACOS_ABSENT_STATUS=0
    run_macos 'platform_install_packages work headless'
    assert_status 1
    assert_output_contains 'claude-code'
    read_packages
    assert_output_contains $'cask:corretto@21\towned\tprotected'
    assert_output_contains $'brew:yq\towned\teligible'
    [[ "$output" != *claude-code* ]]
    assert_no_forbidden_commands
}

@test "macOS installed-package query failure stops before bundles" {
    allow_macos_commands
    export DOTFILES_MACOS_INSPECT_PHASE=before DOTFILES_MACOS_INSPECT_PACKAGE=formula:jq
    export DOTFILES_MACOS_INSPECT_STATUS=34
    run_macos 'platform_install_packages home headless'
    assert_status 34
    [ ! -e "$DOTFILES_MACOS_FIXTURE/bundle-started" ]
    assert_no_forbidden_commands
}

@test "macOS post-bundle inventory failure is nonzero but does not stop reconciliation" {
    allow_macos_commands
    export DOTFILES_MACOS_INSPECT_PHASE=after DOTFILES_MACOS_INSPECT_PACKAGE=formula:jq
    export DOTFILES_MACOS_INSPECT_STATUS=35
    run_macos 'platform_install_packages home headless'
    assert_status 35
    read_packages
    assert_output_contains $'brew:kind\towned\teligible'
    assert_output_contains $'brew:python\towned\tprotected'
    [[ "$output" != *brew:jq* ]]
    assert_no_forbidden_commands
}

@test "macOS preserves bundle failure status even when post-bundle inspection also fails" {
    allow_macos_commands
    export DOTFILES_MACOS_BUNDLE_STATUS=43 DOTFILES_MACOS_PARTIAL_FORMULA=yq
    export DOTFILES_MACOS_INSPECT_PHASE=after DOTFILES_MACOS_INSPECT_PACKAGE=formula:jq
    export DOTFILES_MACOS_INSPECT_STATUS=35
    run_macos 'platform_install_packages work headless'
    assert_status 43
    read_packages
    assert_output_contains $'brew:kind\towned\teligible'
    assert_output_contains $'brew:yq\towned\teligible'
    assert_no_forbidden_commands
}

@test "macOS official bootstrap preserves a download error without executing its output" {
    allow_macos_commands
    export DOTFILES_MACOS_CURL_STATUS=37
    run_macos '
        macos_find_brew() { return 1; }
        platform_install_packages home headless
    '
    assert_status 37
    [ ! -e "$DOTFILES_MACOS_FIXTURE/bootstrapped" ]
    [ ! -e "$DOTFILES_MACOS_FIXTURE/before-Brewfile.common.tsv" ]
    assert_no_forbidden_commands
}

@test "macOS official bootstrap preserves the installer exit status" {
    allow_macos_commands
    export DOTFILES_MACOS_INSTALL_STATUS=29
    run_macos '
        macos_find_brew() { return 1; }
        platform_install_packages home headless
    '
    assert_status 29
    [[ "$(< "$DOTFILES_MACOS_LOG")" == *$'bootstrap\t1'* ]]
    [ ! -e "$DOTFILES_MACOS_FIXTURE/before-Brewfile.common.tsv" ]
    assert_no_forbidden_commands
}

@test "macOS refuses to continue if a successful bootstrap still leaves brew unavailable" {
    allow_macos_commands
    run_macos '
        macos_find_brew() { return 1; }
        platform_install_packages home headless
    '
    assert_status 1
    assert_output_contains 'brew was not found'
    [ ! -e "$DOTFILES_MACOS_FIXTURE/before-Brewfile.common.tsv" ]
    assert_no_forbidden_commands
}

@test "macOS guards bootstrap and protects a newly bootstrapped package manager" {
    allow_macos_commands
    run_macos '
        DRY_RUN=1
        run macos_bootstrap_homebrew
        [ ! -e "$DOTFILES_MACOS_LOG" ]
        DRY_RUN=0
        macos_find_brew() {
            [ -f "$DOTFILES_MACOS_FIXTURE/bootstrapped" ] || return 1
            printf "%s\n" "$DOTFILES_MACOS_BREW"
        }
        platform_install_packages home headless
        [ "$HOMEBREW_PREFIX" = "$DOTFILES_MACOS_BREW_PREFIX" ]
        [ "$(command -v uv)" = "$DOTFILES_MACOS_BREW_PREFIX/bin/uv" ]
        state_each package
    '
    assert_status 0
    assert_output_contains $'manager:homebrew\towned\tprotected'
    assert_output_contains $'brew:kind\towned\teligible'
    [ "$HOME" = "$ORIGINAL_HOME" ]
    assert_no_forbidden_commands
}

@test "macOS Ruby evaluates the actual Brewfile gates and retained package inventory" {
    [ "$(uname -s)" = Darwin ] || skip 'Optional Brewfile DSL check requires macOS Ruby'
    command -v ruby >/dev/null 2>&1 || skip 'Ruby is not available'
    run ruby "$FIXTURES_DIR/macos-brewfiles.rb" "$PROJECT_ROOT"
    assert_status 0
    assert_no_preview_side_effects
}