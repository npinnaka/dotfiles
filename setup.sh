#!/bin/bash

# setup.sh - Dotfiles setup script

set -e

# Colors for a beautiful interface
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Running output: print a timestamped line for every action so the user can
# follow exactly what the script is doing in real time (also captured in the log).
log() {
    printf "${CYAN}[%s]${NC} %s\n" "$(date +%H:%M:%S)" "$*"
}

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

# Wrapper that echoes mutating commands in --dry-run mode instead of running them
run() {
    if [ -n "$DRY_RUN" ]; then
        printf "    ${YELLOW}DRY-RUN:${NC} %s\n" "$*"
    else
        "$@"
    fi
}

# Idempotent symlink helper: backs up an existing non-symlink target before linking.
# Usage: link_config <repo_src> <system_dst>
link_config() {
    local src=$1 dst=$2
    log "Linking $src -> $dst"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        local backup="$dst.bak.$(date +%s)"
        printf "    ${YELLOW}Backing up existing $dst -> $backup${NC}\n"
        run mv "$dst" "$backup"
    fi
    run ln -sfn "$src" "$dst"
    printf "    ${GREEN}[OK] Linked $dst${NC}\n"
}

# Install every entry of a Brewfile natively via `brew bundle`.
install_brewfile() {
    local file=$1
    if [ ! -f "$file" ]; then
        printf "    ${YELLOW}$(basename "$file") not found. Skipping.${NC}\n"
        return
    fi
    # Route GUI casks into the user's ~/Applications so installs never require sudo
    # (and a later uninstall won't prompt for a password per app).
    mkdir -p "$HOME/Applications"
    export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"

    # Resolve the brew binary by absolute path and re-apply its shellenv for
    # every bundle call. Relying on `brew` being on PATH is fragile: a prior
    # `brew bundle` (or a partially failed install) can leave the current shell
    # without `brew` on PATH, which produced "brew: command not found" on the
    # second Brewfile. Looking it up here makes each call self-sufficient.
    local BREW_BIN
    BREW_BIN=$(command -v brew 2>/dev/null || true)
    if [ -z "$BREW_BIN" ]; then
        local candidate
        for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            if [ -x "$candidate" ]; then
                BREW_BIN="$candidate"
                break
            fi
        done
    fi
    if [ -z "$BREW_BIN" ]; then
        log "[ERROR] Homebrew not found; cannot install $(basename "$file")."
        return
    fi
    # Re-apply shellenv so dependent tools (and brew's own subcommands) are on PATH.
    eval "$("$BREW_BIN" shellenv)"

    log "Running brew bundle for $(basename "$file") (streaming output below)..."
    # Stream brew bundle output live to the terminal (and the log) so every
    # formula/cask install is visible as it happens. PIPESTATUS preserves
    # brew's real exit code through the tee pipe.
    local brew_rc
    if [ -n "$DRY_RUN" ]; then
        run "$BREW_BIN" bundle --file="$file"
        brew_rc=$?
    else
        "$BREW_BIN" bundle --file="$file" --verbose 2>&1 | tee -a "$LOG_FILE"
        # Capture brew's real exit code immediately: any later test command
        # (e.g. the `[ ... ]` below) would otherwise overwrite PIPESTATUS.
        brew_rc=${PIPESTATUS[0]}
    fi
    if [ "$brew_rc" -eq 0 ]; then
        INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "brewfile: $(basename "$file")")
        log "[OK] Completed $(basename "$file")"
    else
        log "[ERROR] brew bundle reported issues for $(basename "$file"). Check $LOG_FILE"
    fi
}

USAGE="Usage: ./setup.sh <home|work> [--dry-run] [-h|--help]"

print_help() {
    printf "%s\n\n" "$USAGE"
    printf "Provision this machine from the dotfiles repo using Homebrew as the\n"
    printf "single source of truth.\n\n"
    printf "Arguments:\n"
    printf "  home          Use Brewfile.common + Brewfile.home and the home git identity.\n"
    printf "  work          Use Brewfile.common + Brewfile.work and the work git identity.\n\n"
    printf "Options:\n"
    printf "  --dry-run     Print every package, symlink, and git action without changing anything.\n"
    printf "  -h, --help    Show this help message and exit.\n\n"
    printf "Examples:\n"
    printf "  ./setup.sh home\n"
    printf "  ./setup.sh work --dry-run\n"
}

# Main execution logic
main() {
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local LOG_FILE="$HOME/.dotfiles_setup.log"

    # Parse arguments: a positional profile (home|work) and an optional --dry-run flag
    local BUNDLE_TYPE=""
    DRY_RUN=""
    local arg
    for arg in "$@"; do
        case "$arg" in
            -h|--help) print_help; exit 0 ;;
            --dry-run) DRY_RUN=1 ;;
            home|work) BUNDLE_TYPE="$arg" ;;
            *) ;;
        esac
    done

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

    if [ -z "$BUNDLE_TYPE" ]; then
        printf "${YELLOW}$USAGE${NC}\n"
        exit 1
    fi

    if [ -n "$DRY_RUN" ]; then
        printf "${BOLD}${YELLOW}[DRY-RUN] No changes will be made.${NC}\n\n"
    else
        # Acquire sudo once up front; a keep-alive then refreshes the timestamp
        # for the rest of the run so the password is never requested again.
        ensure_sudo
    fi

    local BREWFILE="$SCRIPT_DIR/Brewfile.$BUNDLE_TYPE"

    INSTALLED_PACKAGES=()

    if [ ! -f "$BREWFILE" ]; then
        printf "${YELLOW}Error: $BREWFILE not found.${NC}\n"
        printf "$USAGE\n"
        exit 1
    fi

    local TOTAL_STEPS=8
    local CURRENT_STEP=0

    printf "${BOLD}${BLUE}Starting dotfiles setup for ${CYAN}$BUNDLE_TYPE${BLUE}...${NC}\n\n"

    # Step 1: Homebrew dependencies
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Installing Homebrew dependencies...${NC}\n"

    ensure_sudo

    log "Detecting existing Homebrew installation..."
    local BREW_PATH=""
    if command -v brew >/dev/null 2>&1; then
        BREW_PATH=$(command -v brew)
    elif [ -f "/opt/homebrew/bin/brew" ]; then
        BREW_PATH="/opt/homebrew/bin/brew"
    elif [ -f "/usr/local/bin/brew" ]; then
        BREW_PATH="/usr/local/bin/brew"
    fi
    [ -n "$BREW_PATH" ] && log "Found Homebrew at $BREW_PATH"

    if [ -z "$BREW_PATH" ]; then
        printf "    ${CYAN}Homebrew not found. Installing...${NC}\n"
        # Non-interactive brew install
        # We use a temporary script to capture output and handle potential non-zero exit without crashing the main script due to set -e
        log "Downloading and running the Homebrew installer (output streams below)..."
        local INSTALL_CMD='NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        if eval "$INSTALL_CMD" 2>&1 | tee -a "$LOG_FILE"; then
            log "Homebrew installation script finished successfully."
        else
            log "Homebrew installation script failed or was interrupted. Check $LOG_FILE for details."
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
        log "Installing common packages (Brewfile.common)..."
        install_brewfile "$SCRIPT_DIR/Brewfile.common"
        log "Installing $BUNDLE_TYPE packages ($(basename "$BREWFILE"))..."
        install_brewfile "$BREWFILE"
    else
        printf "    ${RED}Homebrew installation failed or was not found. Skipping package installation.${NC}\n"
    fi

    # Step 2: Config directories
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Creating configuration directories..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Creating configuration directories...${NC}\n"
    for d in "$HOME/.config" "$HOME/Library/Application Support/com.mitchellh.ghostty" "$HOME/.config/zed" "$HOME/.local/bin" "$HOME/bin"; do
        log "Ensuring directory exists: $d"
        mkdir -p "$d"
    done

    # Step 3: Symbolic links
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Creating symbolic links..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Creating symbolic links...${NC}\n"
    link_config "$SCRIPT_DIR/.config/ghostty/config" "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
    link_config "$SCRIPT_DIR/.config/starship.toml" "$HOME/.config/starship.toml"
    link_config "$SCRIPT_DIR/.config/zed/settings.json" "$HOME/.config/zed/settings.json"
    link_config "$SCRIPT_DIR/.config/zed/keymap.json" "$HOME/.config/zed/keymap.json"

    # Step 4: IntelliJ IDEA Plugins
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
        log "Found IntelliJ IDEA at $FOUND_IDEA"
        for plugin in "${IDEA_PLUGINS[@]}"; do
            current_idea=$((current_idea + 1))
            log "Installing IntelliJ plugin ($current_idea/$total_idea): $plugin..."
            draw_progress_bar $current_idea $total_idea "Installing IntelliJ plugin: $plugin..."
            if run "$FOUND_IDEA" installPlugins "$plugin" >> "$LOG_FILE" 2>&1; then
                INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "intellij-plugin: $plugin")
                log "Installed IntelliJ plugin: $plugin"
            else
                log "Failed to install IntelliJ plugin: $plugin. Check $LOG_FILE for details."
            fi
        done
        printf "\n    ${GREEN}[OK] IntelliJ plugins installation triggered via $FOUND_IDEA${NC}\n"
    else
        printf "    ${YELLOW}IntelliJ IDEA not found yet. Use JetBrains Toolbox to install it, then rerun to install plugins.${NC}\n"
    fi

    # Step 5: Backup .zshrc
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Handling .zshrc backup..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Handling .zshrc backup...${NC}\n"
    local ZSH_SNIPPET="$SCRIPT_DIR/.config/zsh/snippet"
    if [ -f "$ZSH_SNIPPET" ]; then
        if [ -f "$HOME/.zshrc" ]; then
            if [ ! -f "$HOME/.zshrc_pre_script_copy" ]; then
                log "Backing up ~/.zshrc to ~/.zshrc_pre_script_copy"
                run cp "$HOME/.zshrc" "$HOME/.zshrc_pre_script_copy"
                printf "    ${GREEN}Backup created at ~/.zshrc_pre_script_copy${NC}\n"
            else
                printf "    ${YELLOW}Backup already exists. Skipping.${NC}\n"
            fi
        fi
    fi

    # Step 6: Update .zshrc
    CURRENT_STEP=$((CURRENT_STEP + 1))
    draw_progress_bar 1 1 "Updating ~/.zshrc..."
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Updating ~/.zshrc...${NC}\n"
    if [ -f "$ZSH_SNIPPET" ]; then
        # Check if snippet content is already in .zshrc
        # We look for a unique comment from the snippet
        if ! grep -qF "# .zshrc snippets for Ghostty and Homebrew tools" ~/.zshrc 2>/dev/null; then
            if [ -n "$DRY_RUN" ]; then
                printf "    ${YELLOW}DRY-RUN:${NC} append %s to ~/.zshrc\n" "$ZSH_SNIPPET"
            else
                log "Appending dotfiles snippet to ~/.zshrc"
                printf '\n# Added by dotfiles setup script\n' >> ~/.zshrc
                cat "$ZSH_SNIPPET" >> ~/.zshrc
            fi
            printf "    ${GREEN}[OK] Snippet content copied to ~/.zshrc successfully.${NC}\n"
        else
            printf "    ${CYAN}Snippet content already present in ~/.zshrc.${NC}\n"
        fi
    fi

    # Step 7: Python Virtual Environment
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Setting up Python virtual environment...${NC}\n"
    # Prefer `uv` (installed via Brewfile.common) to create the venv; fall back to
    # the stdlib `python3 -m venv` if uv isn't available for some reason.
    local VENV_PATH="$HOME/.venv"
    if command -v uv >/dev/null 2>&1; then
        if [ ! -d "$VENV_PATH" ]; then
            log "Creating Python virtual environment at $VENV_PATH using uv..."
            draw_progress_bar 1 1 "Creating virtual environment at $VENV_PATH..."
            if run uv venv "$VENV_PATH" >> "$LOG_FILE" 2>&1; then
                printf "\n    ${GREEN}[OK] Virtual environment created at $VENV_PATH (uv)${NC}\n"
                INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "python-venv: $VENV_PATH")
            else
                printf "\n    ${RED}Failed to create virtual environment with uv. Check $LOG_FILE for details.${NC}\n"
            fi
        else
            printf "    ${CYAN}Virtual environment already exists at $VENV_PATH${NC}\n"
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if [ ! -d "$VENV_PATH" ]; then
            log "uv not found; creating Python virtual environment at $VENV_PATH using python3..."
            draw_progress_bar 1 1 "Creating virtual environment at $VENV_PATH..."
            if run python3 -m venv "$VENV_PATH" >> "$LOG_FILE" 2>&1; then
                printf "\n    ${GREEN}[OK] Virtual environment created at $VENV_PATH${NC}\n"
                INSTALLED_PACKAGES=("${INSTALLED_PACKAGES[@]}" "python-venv: $VENV_PATH")
            else
                printf "\n    ${RED}Failed to create virtual environment. Check $LOG_FILE for details.${NC}\n" >> "$LOG_FILE"
            fi
        else
            printf "    ${CYAN}Virtual environment already exists at $VENV_PATH${NC}\n"
        fi
    else
        printf "    ${YELLOW}Neither uv nor python3 found. Skipping virtual environment setup.${NC}\n"
    fi

    # Step 8: Git Configuration
    CURRENT_STEP=$((CURRENT_STEP + 1))
    printf "\n  ${BLUE}[Step $CURRENT_STEP/$TOTAL_STEPS] Configuring Git...${NC}\n"
    draw_progress_bar 1 1 "Setting up .gitconfig..."
    log "Applying global git config (delta pager, diff options)..."
    run git config --global core.pager delta
    run git config --global interactive.diffFilter "delta --color-only"
    run git config --global delta.navigate true
    run git config --global delta.side-by-side true
    run git config --global merge.conflictstyle diff3
    run git config --global diff.colorMoved default

    # Per-profile git identity via an include.path (versioned, non-destructive)
    local GIT_PROFILE="$SCRIPT_DIR/.config/git/$BUNDLE_TYPE.gitconfig"
    if [ -f "$GIT_PROFILE" ]; then
        run git config --global include.path "$GIT_PROFILE"
        printf "\n    ${GREEN}[OK] Git identity included from $GIT_PROFILE${NC}\n"
    else
        printf "\n    ${YELLOW}No profile gitconfig at $GIT_PROFILE. Skipping identity.${NC}\n"
    fi
    printf "    ${GREEN}[OK] Git configuration updated.${NC}\n"

    if [ ${#INSTALLED_PACKAGES[@]} -gt 0 ]; then
        printf "\n${BOLD}${BLUE}Package Installation Summary:${NC}\n"
        for section in brewfile intellij-plugin python-venv; do
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
