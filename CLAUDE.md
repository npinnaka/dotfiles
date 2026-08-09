# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal macOS dotfiles repository. The two entry-point scripts manage everything: `setup.sh` installs and `uninstall.sh` reverts. All tool configurations live under `.config/` and are **symlinked** (not copied) to their application-expected locations by `setup.sh`.

## Setup & Teardown

```bash
# Install for home or work environment
./setup.sh home
./setup.sh work

# Preview all actions without changing anything
./setup.sh home --dry-run

# Show usage/help for either script
./setup.sh --help
./uninstall.sh --help

# Fully revert — removes all Homebrew packages system-wide (destructive)
./uninstall.sh
```

The positional `home`/`work` argument is the **profile**: it selects the layered Brewfile and the git identity that gets applied. `--dry-run` routes every mutating command through a `run()` wrapper that echoes instead of executing.

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
| `Brewfile.home` | Home-only (Chrome, Brave, Junie, Rectangle) |
| `Brewfile.work` | Work-only (Corretto 21, pgAdmin4, vault, node, jenv, etc.) |

Packages are installed natively with `brew bundle --file=...` — there is no custom parser.

### `setup.sh` flow (10 steps)

1. Install Homebrew packages, casks, and fonts via `brew bundle` (`Brewfile.common` + the profile Brewfile)
2. Create config directories (`~/.config`, Ghostty, Zed)
3. Symlink all configs from `.config/` to their app locations via `link_config` (backs up existing real files; see table below)
4. Install IntelliJ plugins (`com.anthropic.claudecode`, `com.github.copilot`, `org.jetbrains.plugins.go`) via `idea installPlugins` (skipped if IDEA not found)
5. Back up `~/.zshrc` to `~/.zshrc_pre_script_copy`
6. Append `<repo>/.config/zsh/snippet` to `~/.zshrc` (guarded by a grep marker; idempotent)
7. Create a Python virtual environment at `~/.venv` (uses Python installed via Homebrew)
8. Configure Git: global delta settings + per-profile identity via `git config --global include.path .config/git/<profile>.gitconfig`
9. Initialize `rtk` globally via `rtk init -g` (skipped if `rtk` is not installed)
10. Set up a Podman machine (init + start) and, on the `home` profile only, create a local Kubernetes cluster via `kind` (using the Podman provider)

### Symlink map (created by `setup.sh`)

| Repo path | System path |
|---|---|
| `.config/ghostty/config` | `~/Library/Application Support/com.mitchellh.ghostty/config` |
| `.config/starship.toml` | `~/.config/starship.toml` |
| `.config/zed/settings.json` | `~/.config/zed/settings.json` |
| `.config/zed/keymap.json` | `~/.config/zed/keymap.json` |

Git identity files (`.config/git/home.gitconfig`, `.config/git/work.gitconfig`) are **not** symlinked; they are referenced via `include.path` so they stay versioned and editable in the repo.

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
- **Dry-run safety**: Route every mutating command through the `run()` wrapper so `--dry-run` can preview it. Use `link_config <src> <dst>` for symlinks — it backs up non-symlink targets to `<dst>.bak.<timestamp>` and is safe to re-run.
- **Git identity**: Apply per-profile identity with `git config --global include.path` (never clobber `user.*` directly); `uninstall.sh` unsets these includes on teardown.

### `.config/zsh/snippet`

The zsh configuration block appended to `~/.zshrc`. It uses `brew --prefix` for portability between Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`) Macs. Plugin load order matters: `zsh-autocomplete` must be sourced before other plugins; `zsh-syntax-highlighting` must be last.
