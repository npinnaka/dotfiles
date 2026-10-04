#!/usr/bin/env bats

load test_helper

setup() {
    setup_sandbox
}

@test "uninstall workflow cleans up symlinks and state journal" {
    allow_logging_tee
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        mkdir -p "$DOTFILES_TEST_HOME/src" "$CONFIG_HOME"
        echo "target content" > "$DOTFILES_TEST_HOME/src/starship.toml"
        echo "original content" > "$CONFIG_HOME/starship.toml"

        config_link "$DOTFILES_TEST_HOME/src/starship.toml" "$CONFIG_HOME/starship.toml"
        config_setup_zsh

        [ -f "$STATE_DIR/journal.tsv" ]
        [ -L "$CONFIG_HOME/starship.toml" ]

        config_uninstall
        state_cleanup
        [ ! -f "$STATE_DIR/journal.tsv" ]
        [ -f "$CONFIG_HOME/starship.toml" ]
        [ ! -L "$CONFIG_HOME/starship.toml" ]
        [ "$(cat "$CONFIG_HOME/starship.toml")" = "original content" ]
    '
    assert_status 0
}

@test "state_cleanup preserves journal when packages remain" {
    allow_logging_tee
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        mkdir -p "$DOTFILES_TEST_HOME/src" "$CONFIG_HOME"
        echo "target content" > "$DOTFILES_TEST_HOME/src/starship.toml"
        config_link "$DOTFILES_TEST_HOME/src/starship.toml" "$CONFIG_HOME/starship.toml"
        state_record package apt:curl owned eligible

        config_uninstall
        state_cleanup
        [ -f "$STATE_DIR/journal.tsv" ]
        [ "$(state_value package apt:curl)" = owned ]
        [ -z "$(state_value symlink "$CONFIG_HOME/starship.toml")" ]
    '
    assert_status 0
}

@test "runtime_purge removes recorded virtual environments and kind clusters" {
    allow_logging_tee
    run_module runtime '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        mkdir -p "$USER_HOME/.venv/bin"
        touch "$USER_HOME/.venv/bin/activate"
        state_record venv "$USER_HOME/.venv" created -
        state_record cluster "kind" podman -

        [ -d "$USER_HOME/.venv" ]
        [ "$(state_value venv "$USER_HOME/.venv")" = created ]
        [ "$(state_value cluster "kind")" = podman ]

        # Mock kind command
        kind() {
            case "$1" in
                get) echo "kind" ;;
                delete) echo "Deleted cluster $3" ;;
            esac
        }

        runtime_purge

        [ ! -d "$USER_HOME/.venv" ]
        [ -z "$(state_value venv "$USER_HOME/.venv")" ]
        [ -z "$(state_value cluster "kind")" ]
    '
    assert_status 0
}

@test "uninstall --purge-runtimes and --purge-all dry-run previews" {
    mock_platform Linux x86_64
    run_uninstall --dry-run --purge-runtimes
    assert_status 0
    assert_output_contains "ubuntu"
    assert_output_contains "Purge recorded Python virtual environments"
    assert_no_preview_side_effects

    run_uninstall --dry-run --purge-all
    assert_status 0
    assert_output_contains "ubuntu"
    assert_output_contains "Full purge (config, packages, runtimes)"
    assert_output_contains "Purge recorded Python virtual environments"
    assert_no_preview_side_effects

    run_uninstall --dry-run --purge
    assert_status 0
    assert_output_contains "Full purge (config, packages, runtimes)"
    assert_no_preview_side_effects
}
