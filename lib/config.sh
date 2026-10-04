#!/bin/bash
# lib/config.sh - Portable symlink, shell RC, and Git identity management.

set -e

config_link() {
    local source=$1 target=$2
    local target_dir
    target_dir=$(dirname "$target")

    if [ -L "$target" ]; then
        local current_dest
        current_dest=$(readlink "$target")
        if [ "$current_dest" = "$source" ]; then
            if [ "$DRY_RUN" != 1 ]; then
                state_record symlink "$target" "$source" - || return $?
            fi
            report PRESENT "Symlink $target -> $source"
            return 0
        fi
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        local timestamp backup_file
        timestamp=$(date +%Y%m%d%H%M%S)
        backup_file="$target.bak.$timestamp"
        if [ "$DRY_RUN" = 1 ]; then
            report PLANNED "Backup existing $target to $backup_file and symlink to $source"
            return 0
        fi
        run mv "$target" "$backup_file" || return $?
        state_record backup "$target" "$backup_file" - || return $?
    fi

    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "Symlink $target -> $source"
        return 0
    fi

    [ -d "$target_dir" ] || run mkdir -p "$target_dir" || return $?
    run ln -s "$source" "$target" || return $?
    state_record symlink "$target" "$source" - || return $?
    report INSTALLED "Symlink $target -> $source"
}

config_setup_links() {
    local profile=$1 gui_mode=$2

    # Starship configuration (portable across macOS and Linux)
    config_link "$SCRIPT_DIR/.config/starship.toml" "$CONFIG_HOME/starship.toml" || return $?

    if [ "$gui_mode" = headless ]; then
        report SKIPPED "Desktop application configuration and IDE plugins (headless mode)."
        return 0
    fi

    # Ghostty configuration
    if [ "$PLATFORM" = macos ]; then
        local ghostty_dest="$USER_HOME/Library/Application Support/com.mitchellh.ghostty"
        config_link "$SCRIPT_DIR/.config/ghostty/config" "$ghostty_dest/config" || return $?
        config_link "$SCRIPT_DIR/.config/ghostty/common.conf" "$ghostty_dest/common.conf" || return $?
    else
        config_link "$SCRIPT_DIR/.config/ghostty/config.ubuntu" "$CONFIG_HOME/ghostty/config" || return $?
        config_link "$SCRIPT_DIR/.config/ghostty/common.conf" "$CONFIG_HOME/ghostty/common.conf" || return $?

        # Configure GNOME system monospace font for GNOME Terminal and GTK apps
        if command -v gsettings >/dev/null 2>&1; then
            if [ "$DRY_RUN" = 1 ]; then
                report PLANNED "Set GNOME system monospace font to 'JetBrainsMono Nerd Font 10'"
                report PLANNED "Set Ghostty as default GNOME terminal shortcut (Ctrl+Alt+T)"
            else
                gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font 10' 2>/dev/null || true
                report PRESENT "GNOME system monospace font 'JetBrainsMono Nerd Font 10'"

                # Set Ghostty terminal shortcut on GNOME desktop
                gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "['']" 2>/dev/null || true
                gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty/ name "'Ghostty Terminal'" 2>/dev/null || true
                gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty/ command "'ghostty'" 2>/dev/null || true
                gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty/ binding "'<Control><Alt>t'" 2>/dev/null || true
                gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/ghostty/']" 2>/dev/null || true
                report PRESENT "GNOME Ghostty terminal shortcut (Ctrl+Alt+T)"
            fi
        fi

        # Default terminal desktop associations (Ghostty)
        if command -v xdg-mime >/dev/null 2>&1; then
            if [ "$DRY_RUN" = 1 ]; then
                report PLANNED "Set Ghostty as default handler for terminal schemes and desktop applications"
            else
                xdg-mime default com.mitchellh.ghostty.desktop application/x-terminal-emulator 2>/dev/null || true
                xdg-mime default com.mitchellh.ghostty.desktop x-scheme-handler/terminal 2>/dev/null || true
                report PRESENT "Default terminal desktop associations (Ghostty)"
            fi
        fi
    fi

    # Zed editor configuration
    config_link "$SCRIPT_DIR/.config/zed/settings.json" "$CONFIG_HOME/zed/settings.json" || return $?
    if [ "$PLATFORM" = macos ]; then
        config_link "$SCRIPT_DIR/.config/zed/keymap.json" "$CONFIG_HOME/zed/keymap.json" || return $?
    else
        config_link "$SCRIPT_DIR/.config/zed/keymap.ubuntu.json" "$CONFIG_HOME/zed/keymap.json" || return $?
    fi
}

config_setup_zsh() {
    local zshrc="$USER_HOME/.zshrc"
    local snippet="$SCRIPT_DIR/.config/zsh/snippet"
    local start_marker="# >>> dotfiles >>>"
    local end_marker="# <<< dotfiles <<<"

    local managed_block
    managed_block=$(cat <<EOF
$start_marker
# Managed by dotfiles. Do not edit this block manually.
if [ -f "$snippet" ]; then
    source "$snippet"
fi
$end_marker
EOF
)

    if [ -f "$zshrc" ]; then
        if grep -qF "$start_marker" "$zshrc"; then
            local current_block
            current_block=$(awk "/^$start_marker\$/,/^$end_marker\$/" "$zshrc")
            if [ "$current_block" = "$managed_block" ]; then
                report PRESENT "zsh snippet in $zshrc"
                return 0
            fi
            if [ "$DRY_RUN" = 1 ]; then
                report PLANNED "Update managed dotfiles block in $zshrc"
                return 0
            fi
            local tmp_zshrc
            tmp_zshrc=$(mktemp "$USER_HOME/.zshrc.tmp.XXXXXX") || return $?
            DOTFILES_START_MARKER=$start_marker DOTFILES_END_MARKER=$end_marker DOTFILES_MANAGED_BLOCK=$managed_block awk '
                BEGIN { start = ENVIRON["DOTFILES_START_MARKER"]; end = ENVIRON["DOTFILES_END_MARKER"]; repl = ENVIRON["DOTFILES_MANAGED_BLOCK"] }
                $0 == start { in_block=1; print repl; next }
                $0 == end { in_block=0; next }
                !in_block { print }
            ' "$zshrc" > "$tmp_zshrc" || { rm -f "$tmp_zshrc"; return 1; }
            chmod --reference="$zshrc" "$tmp_zshrc" 2>/dev/null || chmod 0644 "$tmp_zshrc"
            mv "$tmp_zshrc" "$zshrc" || return $?
            report INSTALLED "Updated managed dotfiles block in $zshrc"
            return 0
        fi

        # Legacy unmanaged snippet detection
        if grep -qF "# .zshrc snippets for Ghostty and Homebrew tools" "$zshrc"; then
            if [ "$DRY_RUN" = 1 ]; then
                report PLANNED "Migrate legacy dotfiles snippet in $zshrc to delimited block"
                return 0
            fi
            local timestamp backup_file
            timestamp=$(date +%Y%m%d%H%M%S)
            backup_file="$zshrc.bak.$timestamp"
            run cp "$zshrc" "$backup_file" || return $?
            state_record backup "$zshrc" "$backup_file" - || return $?

            local tmp_zshrc
            tmp_zshrc=$(mktemp "$USER_HOME/.zshrc.tmp.XXXXXX") || return $?
            DOTFILES_LEGACY_MARKER="# .zshrc snippets for Ghostty and Homebrew tools" DOTFILES_MANAGED_BLOCK=$managed_block awk '
                BEGIN { marker = ENVIRON["DOTFILES_LEGACY_MARKER"]; repl = ENVIRON["DOTFILES_MANAGED_BLOCK"] }
                index($0, marker) { seen=1; print repl; next }
                !seen { print }
            ' "$zshrc" > "$tmp_zshrc" || { rm -f "$tmp_zshrc"; return 1; }
            chmod --reference="$zshrc" "$tmp_zshrc" 2>/dev/null || chmod 0644 "$tmp_zshrc"
            mv "$tmp_zshrc" "$zshrc" || return $?
            report INSTALLED "Migrated legacy dotfiles snippet in $zshrc"
            return 0
        fi

        # User has an existing .zshrc without dotfiles content
        if [ "$DRY_RUN" = 1 ]; then
            report PLANNED "Configure zsh snippet in $zshrc with backup"
            return 0
        fi
        local timestamp backup_file
        timestamp=$(date +%Y%m%d%H%M%S)
        backup_file="$zshrc.bak.$timestamp"
        run cp "$zshrc" "$backup_file" || return $?
        state_record backup "$zshrc" "$backup_file" - || return $?
        printf '\n%s\n' "$managed_block" >> "$zshrc" || return $?
        report INSTALLED "Appended dotfiles snippet to $zshrc"
        return 0
    fi

    # No .zshrc exists
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "Create $zshrc with dotfiles snippet"
        return 0
    fi
    printf '%s\n' "$managed_block" > "$zshrc" || return $?
    state_record file "$zshrc" "created" - || return $?
    report INSTALLED "Created $zshrc with dotfiles snippet"
}

config_setup_git() {
    local profile=$1
    local git_profile="$SCRIPT_DIR/.config/git/$profile.gitconfig"
    local other_profile="work"
    [ "$profile" = work ] && other_profile="home"
    local other_git_profile="$SCRIPT_DIR/.config/git/$other_profile.gitconfig"

    # Delta pager global settings (if delta is present or dry-run preview)
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "Configure global git delta pager and diff settings"
    elif command -v delta >/dev/null 2>&1; then
        run git config --global core.pager delta || return $?
        run git config --global interactive.diffFilter "delta --color-only" || return $?
        run git config --global delta.navigate true || return $?
        run git config --global delta.side-by-side true || return $?
        run git config --global merge.conflictstyle diff3 || return $?
        run git config --global diff.colorMoved default || return $?
    fi

    if [ ! -f "$git_profile" ]; then
        report SKIPPED "No profile gitconfig at $git_profile. Skipping identity."
        return 0
    fi

    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "Configure Git identity include for profile: $profile"
        return 0
    fi

    # Unset other profile include if previously set
    if git config --global --get-all include.path 2>/dev/null | grep -qFx "$other_git_profile"; then
        run git config --global --unset-all include.path "$other_git_profile" || true
    fi

    # Add profile include if not already present
    if git config --global --get-all include.path 2>/dev/null | grep -qFx "$git_profile"; then
        report PRESENT "Git profile identity for $profile"
    else
        run git config --global --add include.path "$git_profile" || return $?
        state_record git-include "include.path" "$git_profile" - || return $?
        report INSTALLED "Git profile identity for $profile"
    fi
}

config_uninstall() {
    # 1. Revert symlinks
    local target source _extra
    while IFS=$'\t' read -r target source _extra; do
        [ -n "$target" ] || continue
        if [ -L "$target" ]; then
            local current_dest
            current_dest=$(readlink "$target" 2>/dev/null || true)
            if [ "$current_dest" = "$source" ]; then
                run rm "$target" || true
                local backup
                backup=$(state_value backup "$target")
                if [ -n "$backup" ] && [ -e "$backup" ]; then
                    run mv "$backup" "$target" || true
                    report INSTALLED "Restored $target from backup"
                else
                    report INSTALLED "Removed symlink $target"
                fi
            fi
        fi
        state_forget symlink "$target" || true
        state_forget backup "$target" || true
    done <<EOF
$(state_each symlink)
EOF

    # Clean legacy symlinks if state had no records
    local legacy_targets=(
        "$CONFIG_HOME/starship.toml"
        "$CONFIG_HOME/ghostty/config"
        "$CONFIG_HOME/ghostty/common.conf"
        "$CONFIG_HOME/zed/settings.json"
        "$CONFIG_HOME/zed/keymap.json"
        "$USER_HOME/Library/Application Support/com.mitchellh.ghostty/config"
        "$USER_HOME/Library/Application Support/com.mitchellh.ghostty/common.conf"
    )
    local target
    for target in "${legacy_targets[@]}"; do
        if [ -L "$target" ]; then
            local dest
            dest=$(readlink "$target" 2>/dev/null || true)
            case "$dest" in
                "$SCRIPT_DIR"*)
                    run rm "$target" || true
                    report INSTALLED "Removed unjournaled dotfiles symlink $target"
                    ;;
            esac
        fi
    done

    # 2. Revert .zshrc managed block
    local zshrc="$USER_HOME/.zshrc"
    local start_marker="# >>> dotfiles >>>"
    local end_marker="# <<< dotfiles <<<"
    if [ -f "$zshrc" ] && grep -qF "$start_marker" "$zshrc"; then
        local tmp_zshrc
        tmp_zshrc=$(mktemp "$USER_HOME/.zshrc.tmp.XXXXXX") || return $?
        DOTFILES_START_MARKER=$start_marker DOTFILES_END_MARKER=$end_marker awk '
            BEGIN { start = ENVIRON["DOTFILES_START_MARKER"]; end = ENVIRON["DOTFILES_END_MARKER"] }
            $0 == start { in_block=1; next }
            $0 == end { in_block=0; next }
            !in_block { print }
        ' "$zshrc" > "$tmp_zshrc" || { rm -f "$tmp_zshrc"; return 1; }
        chmod --reference="$zshrc" "$tmp_zshrc" 2>/dev/null || chmod 0644 "$tmp_zshrc"
        mv "$tmp_zshrc" "$zshrc" || return $?

        # If .zshrc is completely empty or just whitespace and was created by us, remove it
        if [ "$(state_value file "$zshrc")" = created ] && [ ! -s "$zshrc" ]; then
            run rm -f "$zshrc" || true
            report INSTALLED "Removed created ~/.zshrc"
        else
            local backup
            backup=$(state_value backup "$zshrc")
            if [ -n "$backup" ] && [ -f "$backup" ] && cmp -s "$zshrc" "$backup" 2>/dev/null; then
                run rm -f "$backup" || true
            fi
            report INSTALLED "Removed dotfiles snippet from ~/.zshrc"
        fi
        state_forget file "$zshrc" || true
        state_forget backup "$zshrc" || true
    fi

    # 3. Revert Git identity includes
    run git config --global --unset-all include.path "$SCRIPT_DIR/.config/git/home.gitconfig" 2>/dev/null || true
    run git config --global --unset-all include.path "$SCRIPT_DIR/.config/git/work.gitconfig" 2>/dev/null || true
    state_forget git-include "include.path" || true
    report INSTALLED "Removed dotfiles Git profile includes"
}
