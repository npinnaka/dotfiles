# Dotfiles

My personal dotfiles for macOS.

## Ghostty & Terminal Setup

I use [Ghostty](https://ghostty.org/) as my primary terminal with a suite of modern CLI tools.

### Quick Install

You can clone this repository and run the setup script in one command:

```bash
git clone https://github.com/yourusername/dotfiles.git ~/dotfiles && cd ~/dotfiles && ./setup.sh home
```

### Installation

The setup script automates the installation of Homebrew dependencies, creates necessary configuration directories, sets up symbolic links, and updates your `~/.zshrc`. It also installs VS Code extensions (including Claude Code) and IntelliJ IDEA plugins if the respective applications are found. Additionally, it creates a Python virtual environment in `~/.venv` which is automatically activated via your shell configuration. All operations are logged to `~/.dotfiles_setup.log` for troubleshooting.

You must specify whether this is a `home` or `work` environment:

```bash
# For home setup
./setup.sh home

# For work setup
./setup.sh work
```

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

- **Terminal & Editor**: Ghostty, Zed, VS Code, JetBrains Toolbox (for IntelliJ IDEA management).
- **Fonts**: JetBrains Mono Nerd Font.
- **Shell Plugins**: zsh-autosuggestions, zsh-autocomplete, zsh-syntax-highlighting, zsh-you-should-use.
- **CLI Tools**: `atlas` (Atlas CLI), `fzf`, `zoxide`, `lazygit`, `yazi`, `eza`, `bat`, `btop`, `dust`, `ripgrep`, `delta`.
- **Infrastructure**: AWS CLI (includes Python), Docker Desktop, pgAdmin4, Bruno.

> **Note**: IntelliJ IDEA is managed via **JetBrains Toolbox** to ensure consistent updates and version management. If you need to install plugins automatically, ensure IntelliJ is installed through the Toolbox first.
