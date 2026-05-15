# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal macOS dotfiles repository. The two entry-point scripts manage everything: `setup.sh` installs and `uninstall.sh` reverts. All tool configurations live under `.config/` and are **symlinked** (not copied) to their application-expected locations by `setup.sh`.

## Setup & Teardown

```bash
# Install for home or work environment
./setup.sh home
./setup.sh work

# Fully revert — removes all Homebrew packages system-wide (destructive)
./uninstall.sh
```

Manual Homebrew-only install (skips symlinks and zsh setup):
```bash
brew bundle --file=Brewfile.common
brew bundle --file=Brewfile.home   # or Brewfile.work
```

## Architecture

### Brewfiles

| File | Purpose |
|---|---|
| `Brewfile.common` | Shared across home and work |
| `Brewfile.home` | Home-only (Chrome, Brave, Junie) |
| `Brewfile.work` | Work-only (Corretto 21, pgAdmin4, vault, node, jenv, etc.) |

### `setup.sh` flow (8 steps)

1. Install Homebrew packages from `Brewfile.common` + the environment-specific Brewfile
2. Create config directories (`~/.config`, Ghostty, VS Code, Zed)
3. Symlink all configs from `.config/` to their app locations (see table below)
4. Install VS Code extensions (`golang.Go`, `tomasvitorino.intellij-idea-keybindings`, `anthropic.claude-code`)
5. Install IntelliJ plugins (`com.anthropic.claudecode`, `com.github.copilot`, `org.jetbrains.plugins.go`) via `idea installPlugins` (skipped if IDEA not found)
6. Back up `~/.zshrc` to `~/.zshrc_pre_script_copy`
7. Append `source <repo>/.config/zsh/snippet` to `~/.zshrc`
8. Create a Python virtual environment at `~/.venv` (uses Python installed by AWS CLI)

### Symlink map (created by `setup.sh`)

| Repo path | System path |
|---|---|
| `.config/ghostty/config` | `~/Library/Application Support/com.mitchellh.ghostty/config` |
| `.config/starship.toml` | `~/.config/starship.toml` |
| `.config/vscode/settings.json` | `~/Library/Application Support/Code/User/settings.json` |
| `.config/vscode/keybindings.json` | `~/Library/Application Support/Code/User/keybindings.json` |
| `.config/zed/settings.json` | `~/.config/zed/settings.json` |
| `.config/zed/keymap.json` | `~/.config/zed/keymap.json` |

### Development & Testing

To check for syntax errors in the scripts, run:
```bash
# Syntax check
bash -n setup.sh
bash -n uninstall.sh

# POSIX compatibility check (if needed)
sh -n setup.sh
sh -n uninstall.sh
```

### Scripting Guidelines

- **Portability**: Avoid advanced Bash-only features (e.g., `+=()` array appending). Use the portable `ARRAY=("${ARRAY[@]}" "item")` syntax instead.
- **Scoping**: Wrap script logic in a `main()` function and use `local` variables where possible.
- **Error Handling**: Use `set -e` at the top of scripts.
- **Logging**: Both `setup.sh` and `uninstall.sh` log detailed output to `~/.dotfiles_setup.log` and `~/.dotfiles_uninstall.log` respectively by re-executing the script and piping to `tee`.
- **Feedback**: Use the `draw_progress_bar` function to provide visual feedback during long-running tasks.

### `.config/zsh/snippet`

The zsh configuration block appended to `~/.zshrc`. It uses `brew --prefix` for portability between Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`) Macs. Plugin load order matters: `zsh-autocomplete` must be sourced before other plugins; `zsh-syntax-highlighting` must be last.
