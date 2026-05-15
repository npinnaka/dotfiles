#!/bin/bash

# setup.sh - Dotfiles setup script

set -e

# Colors for a beautiful interface
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Progress bar function
# Arguments: current_step total_steps message
draw_progress_bar() {
    local current=$1
    local total=$2
    local message=$3
    local width=40
    local percentage=0
    if [ $total -gt 0 ]; then
        percentage=$((current * 100 / total))
    fi
    local completed=0
    if [ $total -gt 0 ]; then
        completed=$((current * width / total))
    fi
    local remaining=$((width - completed))

    printf "\r\033[K${CYAN}Progress: [${GREEN}"
    printf "%${completed}s" | tr ' ' '='
    printf "${NC}"
    printf "%${remaining}s" | tr ' ' '-'
    printf "${CYAN}] %d%% - %s${NC}" "$percentage" "$message"
}

# Function to ensure sudo privileges and keep-alive
ensure_sudo() {
    if [ -z "$SUDO_PID" ]; then
        # Check if we already have sudo privileges
        if ! sudo -n true 2>/dev/null; then
            printf "  ${BLUE}Sudo privileges required for installation. Please enter your password:${NC}\n"
            sudo -v
        fi
        # Keep-alive: update existing `sudo` time stamp until the script has finished
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        export SUDO_PID
        # Ensure sudo session is cleared on exit
        trap 'kill $SUDO_PID 2>/dev/null || true; sudo -k' EXIT
    fi
}

# Function to install items from a Brewfile with progress
install_brew_items() {
    local file=$1
    if [ ! -f "$file" ]; then return; fi

    ensure_sudo

    # Count total items for progress bar
    local total_items
    total_items=$(grep -cE "^(tap|brew|cask) " "$file" || true)
    local current_item=0

    printf "    ${CYAN}Processing $(basename "$file")...${NC}\n"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^tap[[:space:]]+[\"\']?([^\"\'[:space:]]+)[\"\']?(.*) ]]; then
            local tap="${BASH_REMATCH[1]}"
            local args="${BASH_REMATCH[2]}"
            current_item=$((current_item + 1))
            draw_progress_bar $current_item $total_items "Tapping $tap..."
            if brew tap $tap $args >> "$LOG_FILE" 2>&1; then
                INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "tap: $tap")
            else
                printf "\n    ${RED}[ERROR] Failed to tap $tap. Check $LOG_FILE${NC}\n"
            fi
        elif [[ "$line" =~ ^brew[[:space:]]+[\"\']?([^\"\'[:space:]]+)[\"\']?(.*) ]]; then
            local formula="${BASH_REMATCH[1]}"
            local args="${BASH_REMATCH[2]}"
            current_item=$((current_item + 1))
            draw_progress_bar $current_item $total_items "Installing $formula..."
            if brew install $formula $args >> "$LOG_FILE" 2>&1; then
                INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "brew: $formula")
            else
                printf "\n    ${RED}[ERROR] Failed to install $formula. Check $LOG_FILE${NC}\n"
            fi
        elif [[ "$line" =~ ^cask[[:space:]]+[\"\']?([^\"\']+)[\"\']?(.*) ]]; then
            local cask="${BASH_REMATCH[1]}"
            local args="${BASH_REMATCH[2]}"
            current_item=$((current_item + 1))
            draw_progress_bar $current_item $total_items "Installing $cask..."
            if brew install --cask "$cask" $args >> "$LOG_FILE" 2>&1; then
                INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "cask: $cask")
            else
                printf "\n    ${RED}[ERROR] Failed to install $cask. Check $LOG_FILE${NC}\n"
            fi
        fi
    done < "$file"

    printf "\n    ${GREEN}[OK] Completed $(basename "$file")${NC}\n"
}

USAGE="Usage: ./setup.sh [home|work]"

# Main execution logic
main() {
    local BUNDLE_TYPE=$1
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local LOG_FILE="$HOME/.dotfiles_setup.log"

    # Initialize log file
    printf "Dotfiles setup started at $(date)\n" > "$LOG_FILE"
    printf "Environment: $BUNDLE_TYPE\n\n" >> "$LOG_FILE"

    # Redirect stdout and stderr to log file, while keeping output on terminal
    # We use a subshell to pipe all output to tee
    if [ -z "$DOTFILES_LOGGING" ]; then
        export DOTFILES_LOGGING=1
        local SCRIPT_PATH
        if [[ "$0" == /* ]]; then
            SCRIPT_PATH="$0"
        else
            SCRIPT_PATH="$PWD/${0#./}"
        fi
        "$SCRIPT_PATH" "$@" 2>&1 | tee -a "$LOG_FILE"
        exit $?
    fi

    if [ -z "$1" ]; then
        printf "${YELLOW}$USAGE${NC}\n"
        exit 1
    fi

    local BREWFILE="$SCRIPT_DIR/Brewfile.$BUNDLE_TYPE"

    INSTALLED_PACKAGES=()

    if [ ! -f "$BREWFILE" ]; then
        printf "${YELLOW}Error: $BREWFILE not found.${NC}\n"
        printf "$USAGE\n"
        exit 1
    fi

    local TOTAL_STEPS=9
    local CURRENT_STEP=0

    printf "${BOLD}${BLUE}Starting dotfiles setup for ${CYAN}$BUNDLE_TYPE${BLUE}...${NC}\n\n"

    # Step 1: Homebrew dependencies
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Installing Homebrew dependencies...${NC}\n"

    ensure_sudo

    local BREW_PATH=""
    if command -v brew >/dev/null 2>&1; then
        BREW_PATH=$(command -v brew)
    elif [ -f "/opt/homebrew/bin/brew" ]; then
        BREW_PATH="/opt/homebrew/bin/brew"
    elif [ -f "/usr/local/bin/brew" ]; then
        BREW_PATH="/usr/local/bin/brew"
    fi

    if [ -z "$BREW_PATH" ]; then
        printf "    ${CYAN}Homebrew not found. Installing...${NC}\n"
        # Non-interactive brew install
        # We use a temporary script to capture output and handle potential non-zero exit without crashing the main script due to set -e
        local INSTALL_CMD='NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        if eval "$INSTALL_CMD" >> "$LOG_FILE" 2>&1; then
            printf "    ${GREEN}Homebrew installation script finished successfully.${NC}\n"
        else
            printf "    ${RED}Homebrew installation script failed or was interrupted. Check $LOG_FILE for details.${NC}\n"
        fi
        
        # Detect where it was installed
        if [[ -f /opt/homebrew/bin/brew ]]; then
            BREW_PATH="/opt/homebrew/bin/brew"
        elif [[ -f /usr/local/bin/brew ]]; then
            BREW_PATH="/usr/local/bin/brew"
        fi

        if [ -n "$BREW_PATH" ]; then
            eval "$($BREW_PATH shellenv)"
        fi
    fi

    if [ -n "$BREW_PATH" ] && command -v brew >/dev/null 2>&1; then
        # Ensure shellenv is applied if we found it via path but it's not in current PATH
        eval "$($BREW_PATH shellenv)"
        if [ -f "$SCRIPT_DIR/Brewfile.common" ]; then
            install_brew_items "$SCRIPT_DIR/Brewfile.common"
        else
            printf "    ${YELLOW}Brewfile.common not found. Skipping.${NC}\n"
        fi
        install_brew_items "$BREWFILE"
    else
        printf "    ${RED}Homebrew installation failed or was not found. Skipping package installation.${NC}\n"
    fi

    # Step 2: Config directories
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Creating configuration directories..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Creating configuration directories...${NC}\n"
    mkdir -p "$HOME/.config"
    mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"
    mkdir -p "$HOME/Library/Application Support/Code/User"
    mkdir -p "$HOME/.config/zed"

    # Step 3: Symbolic links
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Creating symbolic links..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Creating symbolic links...${NC}\n"
    ln -sf "$SCRIPT_DIR/.config/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
    ln -sf "$SCRIPT_DIR/.config/starship.toml" "$HOME/.config/starship.toml"
    ln -sf "$SCRIPT_DIR/.config/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"
    ln -sf "$SCRIPT_DIR/.config/vscode/keybindings.json" "$HOME/Library/Application Support/Code/User/keybindings.json"
    ln -sf "$SCRIPT_DIR/.config/zed/settings.json" "$HOME/.config/zed/settings.json"
    ln -sf "$SCRIPT_DIR/.config/zed/keymap.json" "$HOME/.config/zed/keymap.json"

    # Step 4: VS Code Extensions
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Installing VS Code extensions...${NC}\n"
    if command -v code >/dev/null 2>&1; then
        local VS_EXTENSIONS=("golang.Go" "tomasvitorino.intellij-idea-keybindings" "anthropic.claude-code")
        local total_ext=${#VS_EXTENSIONS[@]}
        local current_ext=0
        for ext in "${VS_EXTENSIONS[@]}"; do
            current_ext=$((current_ext + 1))
            draw_progress_bar $current_ext $total_ext "Installing VS Code extension: $ext..."
            if code --install-extension "$ext" --force >> "$LOG_FILE" 2>&1; then
                INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "vscode-ext: $ext")
            else
                printf "\n    ${RED}Failed to install VS Code extension: $ext. Check $LOG_FILE for details.${NC}\n" >> "$LOG_FILE"
            fi
        done
        printf "\n    ${GREEN}[OK] VS Code extensions processed${NC}\n"
    else
        printf "    ${YELLOW}VS Code (code) not found. Skipping extensions.${NC}\n"
    fi

    # Step 5: IntelliJ IDEA Plugins
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Checking for IntelliJ IDEA plugins...${NC}\n"
    # Check common installation paths
    local IDEA_PATHS=(
        "/Applications/IntelliJ IDEA.app/Contents/MacOS/idea"
        "/Applications/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea"
        "$HOME/Applications/JetBrains Toolbox/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea"
    )

    local FOUND_IDEA=""
    for path in "${IDEA_PATHS[@]}"; do
        if [ -x "$path" ]; then
            FOUND_IDEA="$path"
            break
        fi
    done

    # If not found in standard paths, try to find it via mdfind (macOS only)
    if [ -z "$FOUND_IDEA" ] && command -v mdfind >/dev/null 2>&1; then
        local MDI_PATH
        MDI_PATH=$(mdfind "kMDItemCFBundleIdentifier == 'com.jetbrains.intellij'" | head -n 1)
        if [ -n "$MDI_PATH" ] && [ -x "$MDI_PATH/Contents/MacOS/idea" ]; then
            FOUND_IDEA="$MDI_PATH/Contents/MacOS/idea"
        elif [ -n "$MDI_PATH" ] && [ -x "$MDI_PATH/Contents/MacOS/intellij" ]; then
             FOUND_IDEA="$MDI_PATH/Contents/MacOS/intellij"
        fi
    fi

    if [ -z "$FOUND_IDEA" ] && command -v idea >/dev/null 2>&1; then
        FOUND_IDEA="idea"
    fi

    if [ -n "$FOUND_IDEA" ]; then
        local IDEA_PLUGINS=("com.anthropic.claudecode" "com.github.copilot" "org.jetbrains.plugins.go")
        local total_idea=${#IDEA_PLUGINS[@]}
        local current_idea=0
        for plugin in "${IDEA_PLUGINS[@]}"; do
            current_idea=$((current_idea + 1))
            draw_progress_bar $current_idea $total_idea "Installing IntelliJ plugin: $plugin..."
            if "$FOUND_IDEA" installPlugins "$plugin" >> "$LOG_FILE" 2>&1; then
                INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "intellij-plugin: $plugin")
            else
                printf "\n    ${RED}Failed to install IntelliJ plugin: $plugin. Check $LOG_FILE for details.${NC}\n" >> "$LOG_FILE"
            fi
        done
        printf "\n    ${GREEN}[OK] IntelliJ plugins installation triggered via $FOUND_IDEA${NC}\n"
    else
        printf "    ${YELLOW}IntelliJ IDEA not found yet. Use JetBrains Toolbox to install it, then rerun to install plugins.${NC}\n"
    fi

    # Step 6: Backup .zshrc
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Handling .zshrc backup..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Handling .zshrc backup...${NC}\n"
    local ZSH_SNIPPET="$SCRIPT_DIR/.config/zsh/snippet"
    if [ -f "$ZSH_SNIPPET" ]; then
        if [ -f "$HOME/.zshrc" ]; then
            if [ ! -f "$HOME/.zshrc_pre_script_copy" ]; then
                cp "$HOME/.zshrc" "$HOME/.zshrc_pre_script_copy"
                printf "    ${GREEN}Backup created at ~/.zshrc_pre_script_copy${NC}\n"
            else
                printf "    ${YELLOW}Backup already exists. Skipping.${NC}\n"
            fi
        fi
    fi

    # Step 7: Update .zshrc
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Updating ~/.zshrc..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Updating ~/.zshrc...${NC}\n"
    if [ -f "$ZSH_SNIPPET" ]; then
        # Check if snippet content is already in .zshrc
        # We look for a unique comment from the snippet
        if ! grep -qF "# .zshrc snippets for Ghostty and Homebrew tools" ~/.zshrc 2>/dev/null; then
            printf '\n# Added by dotfiles setup script\n' >> ~/.zshrc
            cat "$ZSH_SNIPPET" >> ~/.zshrc
            printf "    ${GREEN}[OK] Snippet content copied to ~/.zshrc successfully.${NC}\n"
        else
            printf "    ${CYAN}Snippet content already present in ~/.zshrc.${NC}\n"
        fi
    fi

    # Step 8: Python Virtual Environment
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Setting up Python virtual environment...${NC}\n"
    if command -v python3 >/dev/null 2>&1; then
        local VENV_PATH="$HOME/.venv"
        if [ ! -d "$VENV_PATH" ]; then
            draw_progress_bar 1 1 "Creating virtual environment at $VENV_PATH..."
            if python3 -m venv "$VENV_PATH" >> "$LOG_FILE" 2>&1; then
                printf "\n    ${GREEN}[OK] Virtual environment created at $VENV_PATH${NC}\n"
                INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "python-venv: $VENV_PATH")
            else
                printf "\n    ${RED}Failed to create virtual environment. Check $LOG_FILE for details.${NC}\n" >> "$LOG_FILE"
            fi
        else
            printf "    ${CYAN}Virtual environment already exists at $VENV_PATH${NC}\n"
        fi
    else
        printf "    ${YELLOW}python3 not found. Skipping virtual environment setup.${NC}\n"
    fi

    # Step 9: Git Configuration
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Configuring Git...${NC}\n"
    draw_progress_bar 1 1 "Setting up .gitconfig..."
    git config --global core.pager delta
    git config --global interactive.diffFilter "delta --color-only"
    git config --global delta.navigate true
    git config --global delta.side-by-side true
    git config --global merge.conflictstyle diff3
    git config --global diff.colorMoved default
    printf "\n    ${GREEN}[OK] Git configuration updated.${NC}\n"

    if [ ${#INSTALLED_PACKAGES[@]} -gt 0 ]; then
        printf "\n${BOLD}${BLUE}Package Installation Summary:${NC}\n"
        for section in tap brew cask vscode-ext intellij-plugin python-venv; do
            local items=()
            for item in "${INSTALLED_PACKAGES[@]}"; do
                [[ "${item%%:*}" == "$section" ]] && items=("${items[@]}" "$item")
            done
            if [ ${#items[@]} -gt 0 ]; then
                printf "\n  ${BOLD}${CYAN}${section}:${NC}\n"
                for entry in "${items[@]}"; do
                    printf "    ${GREEN}[OK]${NC} %s\n" "${entry#*: }"
                done
            fi
        done
    fi

    printf "\n\n${BOLD}${GREEN}[DONE] Setup complete! Please restart your terminal.${NC}\n"
    printf "\n${CYAN}Detailed log available at: ${BOLD}$LOG_FILE${NC}\n"

    # Cleanup sudo session and background process explicitly
    if [ -n "$SUDO_PID" ]; then
        kill "$SUDO_PID" 2>/dev/null || true
        sudo -k
    fi
}

main "$@"
