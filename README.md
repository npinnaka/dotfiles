# Dotfiles

A modular, cross-platform dotfiles framework supporting **macOS** and **Ubuntu 26.04 (amd64 / arm64)**.

---

## Features

- **Cross-Platform**: Native platform adapters for macOS (Homebrew bundles) and Ubuntu 26.04 (APT, GPG-pinned vendor repositories, and verified release binaries).
- **Profile-Driven**: Layered profiles (`home` vs. `work`) supporting customized package sets and Git identity inclusions.
- **Desktop & Headless Modes**: Automatic display detection with explicit `--desktop` and `--headless` overrides for servers, containers, or SSH sessions.
- **Safe & Idempotent Linking**: Atomic symlink creation with automatic timestamped backups (`<path>.bak.<timestamp>`) for pre-existing configurations.
- **Transactional State Journaling**: Every managed symlink, file, and newly installed package is tracked in an append-only journal (`~/.local/state/dotfiles/journal.tsv`).
- **Conservative Teardown**: `uninstall.sh` safely reverts only dotfiles-managed configurations and restores backed-up files by default, preserving system packages and user data unless `--remove-packages` is explicitly requested.

---

## Quick Install

Clone and run the setup script for your desired profile:

```bash
git clone https://github.com/npinnaka/dotfiles.git ~/dotfiles && cd ~/dotfiles

# For Home environment
./setup.sh home

# For Work environment
./setup.sh work
```

---

## Usage & Options

### Setup (`./setup.sh`)

```bash
./setup.sh <home|work> [OPTIONS]
```

#### Arguments & Flags:
- `<home|work>`: Target profile (required).
- `--dry-run`: Previews all package installations, symlinks, shell changes, and runtime steps without making any system modifications.
- `--desktop`: Forces desktop application installations, GUI tools, fonts, and editor bindings.
- `--headless`: Installs only CLI tools, shell integrations, and terminal configurations (skips GUI apps and fonts).
- `--skip-cluster`: Skips local Kubernetes Kind cluster creation for the `home` profile.
- `-h, --help`: Displays help and usage information.

#### Examples:
```bash
# Preview home setup in dry-run mode
./setup.sh home --dry-run

# Run work profile in headless mode
./setup.sh work --headless
```

---

### Uninstallation (`./uninstall.sh`)

```bash
./uninstall.sh [OPTIONS]
```

#### Default Behavior (Configuration-Only):
By default, `./uninstall.sh` reverts dotfiles-managed symbolic links, removes the managed shell block from `~/.zshrc`, unsets Git identity includes, and restores any original configuration backups. Pre-existing system packages, package managers, virtual environments (`~/.venv`), IDEs, containers, and clusters are preserved.

#### Flags:
- `--dry-run`: Previews configuration and package removals without making changes.
- `--remove-packages`: Removes only newly installed, dotfiles-owned eligible packages tracked in the state journal.
- `-h, --help`: Displays uninstaller usage.

#### Examples:
```bash
# Preview uninstallation without touching files
./uninstall.sh --dry-run

# Revert configurations and clean symlinks
./uninstall.sh

# Revert configurations and remove managed packages
./uninstall.sh --remove-packages
```

---

## Configuration & Architecture

### Managed Applications & Paths

| Component | Repository Source | macOS Target | Linux / Ubuntu Target |
|---|---|---|---|
| **Starship** | `.config/starship.toml` | `~/.config/starship.toml` | `~/.config/starship.toml` |
| **Ghostty** | `.config/ghostty/config` / `config.ubuntu` | `~/Library/Application Support/com.mitchellh.ghostty/` | `~/.config/ghostty/` |
| **Zed Settings** | `.config/zed/settings.json` | `~/.config/zed/settings.json` | `~/.config/zed/settings.json` |
| **Zed Keymap** | `.config/zed/keymap.json` / `keymap.ubuntu.json` | `~/.config/zed/keymap.json` | `~/.config/zed/keymap.json` |
| **Shell Snippet** | `.config/zsh/snippet` | Managed block in `~/.zshrc` | Managed block in `~/.zshrc` |
| **Git Identity** | `.config/git/<profile>.gitconfig` | Global `include.path` | Global `include.path` |

### Git Identity Management
Git identity files (`.config/git/home.gitconfig` and `.config/git/work.gitconfig`) are applied via `git config --global include.path`. This keeps your identity settings version-controlled while preserving existing global `user.*` settings.

---

## Testing & Validation

The codebase includes automated tests powered by [BATS](https://github.com/bats-core/bats-core) and static analysis with `shellcheck`:

```bash
# Run all linters, syntax checks, and BATS test suites
bash tests/validate.bash
```
