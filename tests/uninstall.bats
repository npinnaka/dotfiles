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
