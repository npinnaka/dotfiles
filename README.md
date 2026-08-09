# Dotfiles

My personal dotfiles for macOS.

## Ghostty & Terminal Setup

I use [Ghostty](https://ghostty.org/) as my primary terminal with a suite of modern CLI tools.

### Quick Install

You can clone this repository and run the setup script in one command:

```bash
git clone https://github.com/npinnaka/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./setup.sh home
```

### Installation

**Homebrew is the single source of truth.** All packages, casks, and fonts are installed natively via `brew bundle` from the profile's Brewfiles (`Brewfile.common` + `Brewfile.<profile>`). The script also creates configuration directories, sets up symbolic links (backing up any existing real files first), updates your `~/.zshrc`, configures a per-profile git identity, and creates a Python virtual environment in `~/.venv`. IntelliJ IDEA plugins are installed if IDEA is found. Your sudo password is requested once up front and kept alive for the rest of the run. All operations are logged to `~/.dotfiles_setup.log`.

You must specify whether this is a `home` or `work` environment:

```bash
# For home setup
./setup.sh home

# For work setup
./setup.sh work
```

#### Profiles

The positional `home`/`work` argument selects which Brewfile is layered on top of `Brewfile.common` **and** which git identity is applied (see below).

#### Dry run

Preview every package, symlink, and git action without changing anything:

```bash
./setup.sh home --dry-run
./setup.sh work --dry-run
```

The script is safe to re-run: existing real configs are backed up to `<path>.bak.<timestamp>` before linking, stale symlinks are refreshed, and the `~/.zshrc` snippet is only appended once.

#### Git identity

Each profile includes a versioned identity file via `git config --global include.path`:

| Profile | File |
|---|---|
| `home` | `.config/git/home.gitconfig` |
| `work` | `.config/git/work.gitconfig` |

Edit these files with your real name/email (and optional signing key). Because they are pulled in via `include.path`, your existing global `user.*` settings are never clobbered.

### Uninstallation

To revert all changes, including restoring your `~/.zshrc`, removing symbolic links, and **optionally uninstalling Homebrew and all its packages**. All operations are logged to `~/.dotfiles_uninstall.log`.

```bash
./uninstall.sh
```

> **Warning**: The uninstallation script is powerful. It allows you to remove all Homebrew packages and casks, and even uninstall Homebrew itself from your system. Each destructive action requires explicit confirmation.

Manual installation of Homebrew dependencies (if you don't want to use the script):

```bash
# For home setup
brew bundle --file=Brewfile.common
brew bundle --file=Brewfile.home

# For work setup
brew bundle --file=Brewfile.common
brew bundle --file=Brewfile.work
```

### Configuration

#### Ghostty

The configuration is located at `.config/ghostty/config`.

To apply the configuration on macOS:

```bash
mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"
ln -s "$(pwd)/.config/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
```

#### Shell (zsh)
The setup script copies the Homebrew initialization and tool configurations from `.config/zsh/snippet` directly into your `~/.zshrc`. This ensures that your shell is correctly configured even on new machines, handling both Intel and Apple Silicon paths for Homebrew.

To apply this manually:

```bash
cat .config/zsh/snippet >> ~/.zshrc
```

#### Prompt (Starship)

The configuration is located at `.config/starship.toml`.

To apply the configuration:

```bash
mkdir -p ~/.config
ln -s "$(pwd)/.config/starship.toml" ~/.config/starship.toml
```

### Included Tools

The `Brewfile.common` includes a variety of tools shared across both environments:

- **Terminal & Editor**: Ghostty, Zed, JetBrains Toolbox (for IntelliJ IDEA management).
- **Fonts**: JetBrains Mono Nerd Font.
- **Shell Plugins**: zsh-autosuggestions, zsh-autocomplete, zsh-syntax-highlighting, zsh-you-should-use.
- **CLI Tools**: `fzf`, `zoxide`, `lazygit`, `yazi`, `eza`, `bat`, `btop`, `dust`, `ripgrep`, `git-delta`, `jq`, `tree`.
- **Infrastructure**: AWS CLI, OpenTofu, protobuf, Python (Homebrew), Docker Desktop, Bruno.

> **Note**: IntelliJ IDEA is managed via **JetBrains Toolbox** to ensure consistent updates and version management. If you need to install plugins automatically, ensure IntelliJ is installed through the Toolbox first.
