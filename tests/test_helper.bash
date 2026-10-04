# shellcheck shell=bash
# Bats supplies status and output when run returns.
# shellcheck disable=SC2154

setup_sandbox() {
    export ORIGINAL_HOME="$HOME"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
    FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
    TEST_SHELL="${BATS_SHELL:-/bin/bash}"
    STUB_BIN="$BATS_TEST_TMPDIR/stub-bin"
    export DOTFILES_TESTING=1
    export DOTFILES_TEST_HOME="$BATS_TEST_TMPDIR/home with spaces"
    export DOTFILES_TEST_COMMAND_LOG="$BATS_TEST_TMPDIR/forbidden-commands.log"
    export DOTFILES_TEST_REAL_TEE
    DOTFILES_TEST_REAL_TEE="$(type -P tee)"
    export LC_ALL=C

    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME
    unset DISPLAY WAYLAND_DISPLAY SSH_CONNECTION SSH_CLIENT SSH_TTY
    unset DRY_RUN PLATFORM ARCH MODE GUI_MODE LOG_FILE USER_HOME
    unset CONFIG_HOME DATA_HOME STATE_DIR DOTFILES_TEST_TEE_STATUS

    mkdir -p "$DOTFILES_TEST_HOME" "$STUB_BIN"
    local tool
    for tool in sudo doas curl wget brew apt apt-get apt-cache apt-mark \
        dpkg dpkg-query add-apt-repository snap flatpak systemctl loginctl \
        launchctl service uv uvx pip pip3 pipx podman docker kubectl kind \
        k3d minikube helm colima limactl git npm npx python python3 \
        corepack yarn pnpm node go rustup cargo gem bundle mise asdf \
        pyenv fnm nvm gsettings dconf fc-cache chsh usermod groupadd \
        useradd adduser update-alternatives update-ca-certificates \
        softwareupdate xcode-select xcodebuild defaults dscl dseditgroup tee; do
        ln -s "$PROJECT_ROOT/tests/stubs/forbidden-command.bash" "$STUB_BIN/$tool"
    done
    export PATH="$STUB_BIN:$PATH"
    mock_platform Linux x86_64
}

mock_platform() {
    export DOTFILES_TEST_UNAME="$1"
    export DOTFILES_TEST_ARCH="$2"
    export DOTFILES_TEST_OS_RELEASE="${3:-$FIXTURES_DIR/os-release/ubuntu-26.04}"
}

run_module() {
    local module="$1" program="$2"
    shift 2
    # Expand the prelude in the child shell, not in the Bats process.
    # shellcheck disable=SC2016
    run "$TEST_SHELL" -c '
        set -e
        SCRIPT_DIR=$1
        module=$2
        shift 2
        . "$SCRIPT_DIR/lib/common.sh"
        if [ "$module" != common ]; then
            . "$SCRIPT_DIR/lib/$module.sh"
        fi
        '"$program" dotfiles-test "$PROJECT_ROOT" "$module" "$@"
}

run_setup() {
    run "$TEST_SHELL" "$PROJECT_ROOT/setup.sh" "$@"
}

run_uninstall() {
    run "$TEST_SHELL" "$PROJECT_ROOT/uninstall.sh" "$@"
}

allow_logging_tee() {
    rm "$STUB_BIN/tee"
    ln -s "$PROJECT_ROOT/tests/stubs/tee.bash" "$STUB_BIN/tee"
    export DOTFILES_TEST_TEE_STATUS="${1:-0}"
}

make_minimal_path() {
    MINIMAL_PATH="$BATS_TEST_TMPDIR/minimal-bin"
    mkdir -p "$MINIMAL_PATH"
    local tool resolved
    for tool in bash sh env basename dirname readlink realpath uname awk sed \
        cut tr cat date head tail sort uniq wc id whoami pwd test expr printf \
        mkdir touch cp mv rm ln chmod; do
        resolved="$(type -P "$tool" || :)"
        if [ -n "$resolved" ]; then
            ln -s "$resolved" "$MINIMAL_PATH/$tool"
        fi
    done
}

assert_status() {
    if [ "$status" -ne "$1" ]; then
        printf 'expected status %s, got %s:\n%s\n' "$1" "$status" "$output" >&2
        return 1
    fi
}

assert_failure() {
    if [ "$status" -eq 0 ]; then
        printf 'expected failure, got success:\n%s\n' "$output" >&2
        return 1
    fi
}

assert_output_equals() {
    if [ "$output" != "$1" ]; then
        printf 'expected output:\n%s\nactual output:\n%s\n' "$1" "$output" >&2
        return 1
    fi
}

assert_output_contains() {
    case "$output" in
        *"$1"*) ;;
        *) printf 'output lacks %s:\n%s\n' "$1" "$output" >&2; return 1 ;;
    esac
}

assert_output_matches() {
    local normalized
    normalized="$(printf '%s\n' "$output" | tr '[:upper:]' '[:lower:]')"
    if ! [[ "$normalized" =~ $1 ]]; then
        printf 'output does not match %s:\n%s\n' "$1" "$output" >&2
        return 1
    fi
}

assert_no_forbidden_commands() {
    if [ -e "$DOTFILES_TEST_COMMAND_LOG" ]; then
        printf 'forbidden commands were invoked:\n%s\n' "$(< "$DOTFILES_TEST_COMMAND_LOG")" >&2
        return 1
    fi
}

assert_home_untouched() {
    [ "$HOME" = "$ORIGINAL_HOME" ]
    [ -d "$DOTFILES_TEST_HOME" ]
    if [ -n "$(command ls -A "$DOTFILES_TEST_HOME")" ]; then
        printf 'the test home was modified: %s\n' "$DOTFILES_TEST_HOME" >&2
        return 1
    fi
}

assert_no_preview_side_effects() {
    assert_no_forbidden_commands
    assert_home_untouched
}

assert_setup_preview() {
    assert_status 0
    assert_output_contains "$1"
    assert_output_contains "$2"
    assert_output_contains "$3"
    assert_output_contains "$4"
    assert_output_matches '(package|brew|apt|brewfile)'
    assert_output_matches '(runtime|uv|python|node)'
    assert_output_matches '(config|symlink|link|stow)'
    assert_no_preview_side_effects
}