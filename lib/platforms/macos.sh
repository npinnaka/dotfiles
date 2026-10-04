#!/bin/bash

macos_find_brew() {
    local brew
    if brew=$(command -v brew); then
        printf '%s\n' "$brew"
        return 0
    fi
    for brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$brew" ]; then
            printf '%s\n' "$brew"
            return 0
        fi
    done
    return 1
}

macos_bootstrap_homebrew() {
    local installer
    installer=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || return $?
    NONINTERACTIVE=1 /bin/bash -c "$installer"
}

macos_activate_homebrew() {
    local shellenv
    shellenv=$("$1" shellenv bash) || return $?
    eval "$shellenv"
}

macos_package_present() {
    local versions
    versions=$(run "$1" list "--$2" --versions "$3") || return $?
    [ -n "$versions" ]
}

macos_package_eligibility() {
    local name=${2##*/}
    case "$1:$name" in
        brew:brew|brew:homebrew|brew:bash|brew:zsh|brew:git|brew:curl|brew:ca-certificates|\
        brew:openssl|brew:openssl@*|brew:ruby|brew:ruby@*|brew:python|brew:python@*|\
        brew:node|brew:node@*|brew:go|brew:go@*|brew:uv|cask:corretto@*)
            printf '%s\n' protected ;;
        *) printf '%s\n' eligible ;;
    esac
}

platform_install_packages() {
    local profile=$1 gui_mode=$2 brew manager_before=present file kind provider package
    local requested before index status eligibility appdir bundle_status=0 bookkeeping_status=0
    local packages=() kinds=() before_states=()
    local DOTFILES_GUI=$gui_mode HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
    printf -v appdir '%q' "--appdir=$USER_HOME/Applications"
    local HOMEBREW_CASK_OPTS="$appdir${HOMEBREW_CASK_OPTS:+ $HOMEBREW_CASK_OPTS}"
    export DOTFILES_GUI HOMEBREW_NO_AUTO_UPDATE HOMEBREW_NO_INSTALL_CLEANUP HOMEBREW_CASK_OPTS

    case "$profile" in home|work) ;; *) fail "Invalid profile: $profile"; return 2 ;; esac
    case "$gui_mode" in desktop|headless) ;; *) fail "Invalid GUI mode: $gui_mode"; return 2 ;; esac
    state_validate || return $?

    if ! brew=$(macos_find_brew); then
        manager_before=absent
        if [ "$DRY_RUN" = 1 ]; then
            report PLANNED 'Bootstrap Homebrew with https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh (NONINTERACTIVE=1).'
        fi
        if run macos_bootstrap_homebrew; then
            if [ "$DRY_RUN" = 1 ]; then
                case "$ARCH" in
                    arm64) brew=/opt/homebrew/bin/brew ;;
                    *) brew=/usr/local/bin/brew ;;
                esac
            elif ! brew=$(macos_find_brew); then
                fail 'Homebrew bootstrap completed, but brew was not found on PATH or in the standard prefixes.'
                return 1
            fi
        else
            status=$?
            report FAILED "Homebrew bootstrap failed (exit $status)." >&2
            return "$status"
        fi
    fi

    record_package manager homebrew "$manager_before" protected || return $?
    if run macos_activate_homebrew "$brew"; then
        :
    else
        status=$?
        report FAILED "Homebrew activation failed (exit $status)." >&2
        return "$status"
    fi

    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED 'Snapshot requested formulae/casks with native brew bundle list; preserve preexisting packages and foundations.'
        for file in "$SCRIPT_DIR/Brewfile.common" "$SCRIPT_DIR/Brewfile.$profile"; do
            run env DOTFILES_GUI="$gui_mode" HOMEBREW_CASK_OPTS="$HOMEBREW_CASK_OPTS" "$brew" bundle --file="$file"
        done
        return 0
    fi

    # Capture both bundles before either runs: a common dependency may also be
    # explicitly requested by the profile. Let Homebrew evaluate the Ruby DSL.
    for file in "$SCRIPT_DIR/Brewfile.common" "$SCRIPT_DIR/Brewfile.$profile"; do
        for kind in formula cask; do
            provider=brew
            [ "$kind" != cask ] || provider=cask
            requested=$(run "$brew" bundle list --file="$file" "--$kind") || return $?
            while IFS= read -r package; do
                [ -n "$package" ] || continue
                if macos_package_present "$brew" "$kind" "$package"; then
                    before=present
                    record_package "$provider" "$package" "$before" protected || return $?
                else
                    status=$?
                    [ "$status" = 1 ] || return "$status"
                    before=absent
                fi
                index=${#packages[@]}
                packages[index]=$package
                kinds[index]=$kind
                before_states[index]=$before
            done <<< "$requested"
        done
    done

    for file in "$SCRIPT_DIR/Brewfile.common" "$SCRIPT_DIR/Brewfile.$profile"; do
        if run env DOTFILES_GUI="$gui_mode" HOMEBREW_CASK_OPTS="$HOMEBREW_CASK_OPTS" "$brew" bundle --file="$file"; then
            report INSTALLED "Homebrew bundle ${file##*/} ($gui_mode)"
        else
            bundle_status=$?
            break
        fi
    done

    # A failed bundle can still install packages. Journal only requested items
    # actually present afterwards; implicit dependencies are never owned.
    for ((index = 0; index < ${#packages[@]}; index++)); do
        package=${packages[index]}
        kind=${kinds[index]}
        provider=brew
        [ "$kind" != cask ] || provider=cask
        if macos_package_present "$brew" "$kind" "$package"; then
            eligibility=$(macos_package_eligibility "$provider" "$package")
            if record_package "$provider" "$package" "${before_states[index]}" "$eligibility"; then
                if [ "${before_states[index]}" = present ]; then
                    report PRESENT "Homebrew $kind $package"
                else
                    report INSTALLED "Homebrew $kind $package"
                fi
            else
                bookkeeping_status=$?
            fi
        else
            status=$?
            if [ "$status" != 1 ]; then
                bookkeeping_status=$status
                report FAILED "Could not inspect Homebrew $kind $package (exit $status)." >&2
            elif [ "$bundle_status" = 0 ]; then
                [ "$bookkeeping_status" != 0 ] || bookkeeping_status=1
                report FAILED "Homebrew $kind $package is missing after a successful bundle." >&2
            fi
        fi
    done
    if [ "$bundle_status" != 0 ]; then
        report FAILED "Homebrew bundle failed (exit $bundle_status); partial installations were checked for ownership." >&2
        return "$bundle_status"
    fi
    return "$bookkeeping_status"
}

platform_find_idea_launcher() {
    local path
    for path in \
        "/Applications/IntelliJ IDEA.app/Contents/MacOS/idea" \
        "/Applications/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea" \
        "/Applications/IntelliJ IDEA Community Edition.app/Contents/MacOS/idea" \
        "$USER_HOME/Applications/IntelliJ IDEA.app/Contents/MacOS/idea" \
        "$USER_HOME/Applications/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea" \
        "$USER_HOME/Applications/JetBrains Toolbox/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea" \
        "$USER_HOME/Applications/JetBrains Toolbox/IntelliJ IDEA Community Edition.app/Contents/MacOS/idea"; do
        if [ -x "$path" ]; then
            printf '%s\n' "$path"
            return 0
        fi
    done
    if command -v mdfind >/dev/null 2>&1; then
        local mdi_path
        mdi_path=$(mdfind "kMDItemCFBundleIdentifier == 'com.jetbrains.intellij*'" 2>/dev/null | head -n 1)
        if [ -n "$mdi_path" ] && [ -x "$mdi_path/Contents/MacOS/idea" ]; then
            printf '%s\n' "$mdi_path/Contents/MacOS/idea"
            return 0
        fi
    fi
    if command -v idea >/dev/null 2>&1; then
        command -v idea
        return 0
    fi
    return 1
}

platform_prepare_containers() {
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED 'Prepare Podman machine (init/start) on macOS.'
        return 0
    fi
    if command -v podman >/dev/null 2>&1; then
        if ! podman machine list --format '{{.Name}}' 2>/dev/null | grep -q 'podman-machine-default'; then
            run podman machine init || return $?
            report INSTALLED 'Podman machine initialized'
        fi
        if ! podman machine list --format '{{.Running}}' 2>/dev/null | grep -q 'true'; then
            run podman machine start || return $?
            report INSTALLED 'Podman machine started'
        else
            report PRESENT 'Podman machine already running'
        fi
    else
        report SKIPPED 'podman is not available; skipping container runtime setup.'
    fi
}

platform_ghostty_config_dir() {
    printf '%s\n' "$USER_HOME/Library/Application Support/com.mitchellh.ghostty"
}

platform_remove_owned_packages() {
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED 'Remove only recorded, newly installed eligible Homebrew packages; preserve Homebrew.'
        return 0
    fi
    local brew
    brew=$(macos_find_brew) || { report SKIPPED 'Homebrew not found; skipping package removal.'; return 0; }
    local key val extra
    while IFS=$'\t' read -r key val extra; do
        [ -n "$key" ] || continue
        [ "$val" = owned ] || continue
        [ "$extra" = eligible ] || continue
        local provider=${key%%:*}
        local pkg=${key#*:}
        case "$provider" in
            brew)
                if run "$brew" remove --force "$pkg" --ignore-dependencies; then
                    report INSTALLED "Removed Homebrew formula $pkg"
                    state_forget package "$key" || true
                fi
                ;;
            cask)
                if run "$brew" remove --force --cask "$pkg" --ignore-dependencies; then
                    report INSTALLED "Removed Homebrew cask $pkg"
                    state_forget package "$key" || true
                fi
                ;;
        esac
    done <<EOF
$(state_each package)
EOF
}