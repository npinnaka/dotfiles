#!/bin/bash

# uninstall.sh - Dotfiles uninstall script

set -e

# Colors for a beautiful interface
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Progress bar function
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

    printf "\r\033[K${CYAN}Progress: [${RED}"
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
            printf "  ${BLUE}Sudo privileges required for uninstallation. Please enter your password:${NC}\n"
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

# Function to uninstall all Homebrew items with progress
uninstall_all_brew() {
    if ! command -v brew >/dev/null 2>&1; then
        printf "    ${YELLOW}Homebrew not found. Skipping.${NC}\n"
        return
    fi

    printf "\n  ${YELLOW}[WARNING] This will remove ALL Homebrew packages on this system, not just those installed by this repo.${NC}\n"
    printf "  Type ${BOLD}YES${NC} to confirm: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        printf "  ${CYAN}Aborted.${NC}\n"
        return
    fi

    ensure_sudo

    local formulas=() casks=()
    local formulas_raw casks_raw
    formulas_raw=$(brew list --formulae || true)
    casks_raw=$(brew list --casks || true)
    
    while IFS= read -r f; do [[ -n "$f" ]] && formulas=("${formulas[@]}" "$f"); done <<EOF
$formulas_raw
EOF
    while IFS= read -r c; do [[ -n "$c" ]] && casks=("${casks[@]}" "$c"); done <<EOF
$casks_raw
EOF
    
    local total_items=$(( ${#formulas[@]} + ${#casks[@]} ))
    local current_item=0

    for formula in "${formulas[@]}"; do
        current_item=$((current_item + 1))
        draw_progress_bar $current_item $total_items "Removing $formula..."
        if brew remove --force "$formula" --ignore-dependencies >> "$LOG_FILE" 2>&1; then
            UNINSTALLED_PACKAGES=("${UNINSTALLED_PACKAGES[@]}" "brew: $formula")
        else
            printf "\n    ${RED}Error removing $formula. Check $LOG_FILE for details.${NC}\n" >> "$LOG_FILE"
        fi
    done

    for cask in "${casks[@]}"; do
        current_item=$((current_item + 1))
        draw_progress_bar $current_item $total_items "Removing $cask..."
        if brew remove --force --cask "$cask" --ignore-dependencies >> "$LOG_FILE" 2>&1; then
            UNINSTALLED_PACKAGES=("${UNINSTALLED_PACKAGES[@]}" "cask: $cask")
        else
            printf "\n    ${RED}Error removing $cask. Check $LOG_FILE for details.${NC}\n" >> "$LOG_FILE"
        fi
    done

    printf "\n    ${RED}Cleaning up cache...${NC}\n"
    draw_progress_bar 1 1 "Brew cleanup..."
    if brew cleanup --prune=all >> "$LOG_FILE" 2>&1; then
        printf "\n    ${GREEN}[OK] Homebrew cleanup complete${NC}\n"
    else
        printf "\n    ${YELLOW}Homebrew cleanup reported some issues. Check $LOG_FILE.${NC}\n" >> "$LOG_FILE"
    fi
}

# Function to uninstall Homebrew itself
uninstall_homebrew_itself() {
    local BREW_PATH=""
    if [ -f "/usr/local/bin/brew" ]; then
        BREW_PATH="/usr/local/bin/brew"
    elif [ -f "/opt/homebrew/bin/brew" ]; then
        BREW_PATH="/opt/homebrew/bin/brew"
    fi

    if [ -z "$BREW_PATH" ] && ! command -v brew >/dev/null 2>&1; then
        printf "    ${CYAN}Homebrew not found. Skipping.${NC}\n"
        return
    fi

    printf "\n  ${YELLOW}[WARNING] This will UNINSTALL Homebrew itself from your system.${NC}\n"
    printf "  Type ${BOLD}UNINSTALL${NC} to confirm: "
    read -r confirm
    if [[ "$confirm" != "UNINSTALL" ]]; then
        printf "  ${CYAN}Skipping Homebrew uninstallation.${NC}\n"
        return
    fi

    printf "    ${CYAN}Uninstalling Homebrew...${NC}\n"
    ensure_sudo
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" >> "$LOG_FILE" 2>&1

    # Final cleanup of common Homebrew directories if they still exist and are empty
    sudo rm -rf /usr/local/Homebrew /usr/local/Caskroom /usr/local/bin/brew /usr/local/share/doc/homebrew 2>/dev/null || true
    sudo rm -rf /opt/homebrew 2>/dev/null || true

    printf "    ${GREEN}[OK] Homebrew uninstalled.${NC}\n"
}

USAGE="Usage: ./uninstall.sh [-h|--help]"

print_help() {
    printf "%s\n\n" "$USAGE"
    printf "Revert the dotfiles setup: restore ~/.zshrc, remove symlinks, and remove\n"
    printf "the per-profile git identity includes. Optionally uninstalls all Homebrew\n"
    printf "packages and Homebrew itself — each destructive action is confirmation-gated.\n\n"
    printf "Options:\n"
    printf "  -h, --help    Show this help message and exit.\n\n"
    printf "Example:\n"
    printf "  ./uninstall.sh\n"
}

# Main execution logic
main() {
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help) print_help; exit 0 ;;
            *) ;;
        esac
    done

    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local LOG_FILE="$HOME/.dotfiles_uninstall.log"

    # Initialize log file
    printf "Dotfiles uninstallation started at $(date)\n\n" > "$LOG_FILE"

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

    printf "${BOLD}${RED}Starting dotfiles uninstallation...${NC}\n\n"

    UNINSTALLED_PACKAGES=()

    local TOTAL_STEPS=5
    local CURRENT_STEP=0

    # Step 1: Restore .zshrc
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Restoring ~/.zshrc..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Restoring ~/.zshrc...${NC}\n"

    BACKUP="$HOME/.zshrc_pre_script_copy"
    if [ -f "$BACKUP" ]; then
        mv "$BACKUP" "$HOME/.zshrc"
        printf "    ${GREEN}Restored from backup.${NC}\n"
    else
        ZSH_SNIPPET="$SCRIPT_DIR/.config/zsh/snippet"
        if [ -f "$HOME/.zshrc" ]; then
            # Use a more portable sed approach for deleting lines
            sed -i '' "/# Added by dotfiles setup script/d" "$HOME/.zshrc"
            sed -i '' "/source \"${ZSH_SNIPPET//\//\\/}\"/d" "$HOME/.zshrc"
            printf "    ${YELLOW}Backup not found. Removed snippet manually.${NC}\n"
        fi
    fi

    # Step 2: Cleanup symbolic links and directories
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Cleaning up links and directories..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Cleaning up links and directories...${NC}\n"

    local LINKS=(
        "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
        "$HOME/.config/starship.toml"
        "$HOME/.config/zed/settings.json"
        "$HOME/.config/zed/keymap.json"
    )

    for link in "${LINKS[@]}"; do
        if [ -L "$link" ]; then
            if rm "$link"; then
                printf "    ${GREEN}Removed link: $link${NC}\n" >> "$LOG_FILE"
            else
                printf "    ${RED}Failed to remove link: $link${NC}\n" >> "$LOG_FILE"
            fi
        elif [ -e "$link" ]; then
            printf "    ${YELLOW}Path exists but is not a symbolic link: $link. Skipping.${NC}\n" >> "$LOG_FILE"
        else
            printf "    ${CYAN}Link not found, skipping: $link${NC}\n" >> "$LOG_FILE"
        fi
    done

    local DIRS=(
        "$HOME/Library/Application Support/com.mitchellh.ghostty"
        "$HOME/.config/zed"
    )

    for dir in "${DIRS[@]}"; do
        if [ -d "$dir" ]; then
            if rmdir "$dir" 2>/dev/null; then
                printf "    ${GREEN}Removed empty directory: $dir${NC}\n" >> "$LOG_FILE"
            else
                printf "    ${CYAN}Directory not empty, kept: $dir${NC}\n" >> "$LOG_FILE"
            fi
        fi
    done

    # Step 3: Remove per-profile git identity includes
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Removing git identity includes..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Removing git identity includes...${NC}\n"
    if command -v git >/dev/null 2>&1; then
        local profile
        for profile in home work; do
            local GIT_PROFILE="$SCRIPT_DIR/.config/git/$profile.gitconfig"
            # Remove the include.path entry if it points at this repo's profile gitconfig
            git config --global --unset-all include.path "^$(printf '%s' "$GIT_PROFILE" | sed 's/[][\\.*^$/]/\\&/g')$" 2>/dev/null || true
        done
        printf "    ${GREEN}[OK] Removed profile git includes (if present).${NC}\n"
    else
        printf "    ${YELLOW}git not found. Skipping.${NC}\n"
    fi

    # Step 4: Homebrew uninstallation (packages)
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Uninstalling Homebrew dependencies...${NC}\n"
    uninstall_all_brew

    # Step 5: Uninstall Homebrew itself
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Uninstalling Homebrew itself...${NC}\n"
    uninstall_homebrew_itself

    if [ ${#UNINSTALLED_PACKAGES[@]} -gt 0 ]; then
        printf "\n${BOLD}${RED}Package Uninstallation Summary:${NC}\n"
        for section in brew cask; do
            items=()
            for item in "${UNINSTALLED_PACKAGES[@]}"; do
                [[ "${item%%:*}" == "$section" ]] && items=("${items[@]}" "${item#*: }")
            done
            if [ ${#items[@]} -gt 0 ]; then
                printf "\n  ${BOLD}${CYAN}${section}:${NC}\n"
                for name in "${items[@]}"; do
                    printf "    ${RED}[X]${NC} %s\n" "$name"
                done
            fi
        done
    fi

    printf "\n\n${BOLD}${GREEN}[DONE] Uninstallation complete!${NC}\n"
    printf "\n${CYAN}Detailed log available at: ${BOLD}$LOG_FILE${NC}\n"

    # Cleanup sudo session and background process explicitly
    if [ -n "$SUDO_PID" ]; then
        kill "$SUDO_PID" 2>/dev/null || true
        sudo -k
    fi
}

main "$@"
