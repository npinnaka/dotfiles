#!/usr/bin/env bats

load test_helper

setup() {
    setup_sandbox
}

@test "config_link creates symlink and records it in state" {
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        mkdir -p "$DOTFILES_TEST_HOME/source_dir"
        echo "hello" > "$DOTFILES_TEST_HOME/source_dir/file.txt"
        config_link "$DOTFILES_TEST_HOME/source_dir/file.txt" "$DOTFILES_TEST_HOME/target_dir/file.txt"
        [ -L "$DOTFILES_TEST_HOME/target_dir/file.txt" ]
        [ "$(readlink "$DOTFILES_TEST_HOME/target_dir/file.txt")" = "$DOTFILES_TEST_HOME/source_dir/file.txt" ]
        [ "$(state_value symlink "$DOTFILES_TEST_HOME/target_dir/file.txt")" = "$DOTFILES_TEST_HOME/source_dir/file.txt" ]
    '
    assert_status 0
}

@test "config_link backs up existing target file and replaces with symlink" {
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        mkdir -p "$DOTFILES_TEST_HOME/src" "$DOTFILES_TEST_HOME/dst"
        echo "src" > "$DOTFILES_TEST_HOME/src/app.conf"
        echo "original" > "$DOTFILES_TEST_HOME/dst/app.conf"
        config_link "$DOTFILES_TEST_HOME/src/app.conf" "$DOTFILES_TEST_HOME/dst/app.conf"
        [ -L "$DOTFILES_TEST_HOME/dst/app.conf" ]
        [ "$(cat "$DOTFILES_TEST_HOME/dst/app.conf")" = "src" ]
        backup=$(state_value backup "$DOTFILES_TEST_HOME/dst/app.conf")
        [ -n "$backup" ]
        [ "$(cat "$backup")" = "original" ]
    '
    assert_status 0
}

@test "config_setup_zsh handles non-existent, legacy, and existing .zshrc" {
    # 1. Non-existent .zshrc
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        config_setup_zsh
        [ -f "$USER_HOME/.zshrc" ]
        grep -q "# >>> dotfiles >>>" "$USER_HOME/.zshrc"
        [ "$(state_value file "$USER_HOME/.zshrc")" = "created" ]
    '
    assert_status 0

    # 2. Existing user .zshrc
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        echo "export FOO=bar" > "$USER_HOME/.zshrc"
        config_setup_zsh
        grep -q "export FOO=bar" "$USER_HOME/.zshrc"
        grep -q "# >>> dotfiles >>>" "$USER_HOME/.zshrc"
        backup=$(state_value backup "$USER_HOME/.zshrc")
        [ -n "$backup" ]
        [ "$(cat "$backup")" = "export FOO=bar" ]
    '
    assert_status 0

    # 3. Idempotent re-run
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        echo "export FOO=bar" > "$USER_HOME/.zshrc"
        config_setup_zsh
        config_setup_zsh
        [ "$(grep -c "# >>> dotfiles >>>" "$USER_HOME/.zshrc")" = 1 ]
    '
    assert_status 0

    # 4. Migrate legacy snippet
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        printf "export OLD=1\n# .zshrc snippets for Ghostty and Homebrew tools\nexport PATH=/old\n" > "$USER_HOME/.zshrc"
        config_setup_zsh
        grep -q "export OLD=1" "$USER_HOME/.zshrc"
        grep -q "# >>> dotfiles >>>" "$USER_HOME/.zshrc"
        [ "$(grep -c "# .zshrc snippets for Ghostty" "$USER_HOME/.zshrc")" = 0 ]
    '
    assert_status 0
}

@test "config_setup_git toggles profile includes cleanly" {
    rm -f "$STUB_BIN/git"
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        config_setup_git home
        git config --global --get-all include.path | grep -q "home.gitconfig"
        ! git config --global --get-all include.path | grep -q "work.gitconfig"
        config_setup_git work
        git config --global --get-all include.path | grep -q "work.gitconfig"
        ! git config --global --get-all include.path | grep -q "home.gitconfig"
    '
    assert_status 0
}

@test "config_uninstall restores backups and removes managed snippet" {
    rm -f "$STUB_BIN/git"
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        mkdir -p "$DOTFILES_TEST_HOME/src" "$CONFIG_HOME"
        echo "new starship" > "$DOTFILES_TEST_HOME/src/starship.toml"
        echo "old starship" > "$CONFIG_HOME/starship.toml"
        echo "custom content" > "$USER_HOME/.zshrc"

        config_link "$DOTFILES_TEST_HOME/src/starship.toml" "$CONFIG_HOME/starship.toml"
        config_setup_zsh
        config_setup_git home

        [ -L "$CONFIG_HOME/starship.toml" ]
        grep -q "# >>> dotfiles >>>" "$USER_HOME/.zshrc"

        config_uninstall

        [ ! -L "$CONFIG_HOME/starship.toml" ]
        [ -f "$CONFIG_HOME/starship.toml" ]
        [ "$(cat "$CONFIG_HOME/starship.toml")" = "old starship" ]
        [ "$(cat "$USER_HOME/.zshrc" | tr -d " \n")" = "customcontent" ]
        ! git config --global --get-all include.path 2>/dev/null | grep -q "home.gitconfig"
    '
    assert_status 0
}

@test "config_setup_links handles desktop and headless modes" {
    run_module config '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        config_setup_links home headless
        [ -L "$CONFIG_HOME/starship.toml" ]
        [ ! -L "$CONFIG_HOME/ghostty/config" ]

        config_setup_links home desktop
        [ -L "$CONFIG_HOME/ghostty/config" ]
        [ -L "$CONFIG_HOME/ghostty/common.conf" ]
        [ -L "$CONFIG_HOME/zed/settings.json" ]
        [ -L "$CONFIG_HOME/zed/keymap.json" ]
    '
    assert_status 0
}
