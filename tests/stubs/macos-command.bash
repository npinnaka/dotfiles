#!/usr/bin/env bash
set -eu

if [ "${DOTFILES_TESTING:-0}" != 1 ]; then
    printf 'macOS command fixtures require DOTFILES_TESTING=1\n' >&2
    exit 98
fi
: "${DOTFILES_TEST_HOME:?}"
: "${DOTFILES_MACOS_FIXTURE:?}"
: "${DOTFILES_MACOS_LOG:?}"
case "$DOTFILES_MACOS_FIXTURE" in
    "$DOTFILES_TEST_HOME/"*) ;;
    *) exit 98 ;;
esac

tool=${0##*/}
{
    printf '%s\t%s' "$tool" "${DOTFILES_GUI:-unset}"
    printf '\t%s' "$@"
    printf '\n'
} >> "$DOTFILES_MACOS_LOG"

if [ "$tool" = curl ]; then
    [ "$#" = 2 ] && [ "$1" = -fsSL ] &&
        [ "$2" = https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh ] || exit 96
    # Expand these variables only when the downloaded fixture is executed.
    # shellcheck disable=SC2016
    printf '%s\n' \
        'printf "bootstrap\t%s\n" "${NONINTERACTIVE:-unset}" >> "$DOTFILES_MACOS_LOG"' \
        'printf installed > "$DOTFILES_MACOS_FIXTURE/bootstrapped"' \
        'exit "${DOTFILES_MACOS_INSTALL_STATUS:-0}"'
    exit "${DOTFILES_MACOS_CURL_STATUS:-0}"
fi

[ "$tool" = brew ] || exit 96
if [ "$1" = shellenv ]; then
    [ "$#" = 2 ] && [ "$2" = bash ] || exit 96
    [ "${DOTFILES_MACOS_SHELLENV_STATUS:-0}" = 0 ] || exit "$DOTFILES_MACOS_SHELLENV_STATUS"
    printf 'export HOMEBREW_PREFIX=%q\n' "$DOTFILES_MACOS_BREW_PREFIX"
    printf 'export HOMEBREW_CELLAR=%q\n' "$DOTFILES_MACOS_BREW_PREFIX/Cellar"
    printf 'export HOMEBREW_REPOSITORY=%q\n' "$DOTFILES_MACOS_BREW_PREFIX/Homebrew"
    # shellcheck disable=SC2016
    printf 'export PATH=%q:"$PATH"\n' "$DOTFILES_MACOS_BREW_PREFIX/bin:$DOTFILES_MACOS_BREW_PREFIX/sbin"
    exit 0
fi

if [ "$1" = list ]; then
    [ "$#" = 4 ] && [ "$3" = --versions ] || exit 96
    case "$2" in --formula) kind=formula ;; --cask) kind=cask ;; *) exit 96 ;; esac
    phase=before
    [ ! -e "$DOTFILES_MACOS_FIXTURE/bundle-started" ] || phase=after
    if [ "${DOTFILES_MACOS_INSPECT_PHASE:-}" = "$phase" ] &&
        [ "${DOTFILES_MACOS_INSPECT_PACKAGE:-}" = "$kind:$4" ]; then
        printf 'Injected installed-package query failure\n' >&2
        exit "$DOTFILES_MACOS_INSPECT_STATUS"
    fi
    [ -f "$DOTFILES_MACOS_FIXTURE/$kind/$4" ] || exit "${DOTFILES_MACOS_ABSENT_STATUS:-1}"
    # Homebrew reports canonical formula names even when an alias was requested.
    name=$4
    [ "$name" != python ] || name=python@3.14
    printf '%s 1.0\n' "$name"
    exit 0
fi

[ "$1" = bundle ] || exit 96
shift
action=install
if [ "${1:-}" = list ]; then
    action=list
    shift
fi
kind='' file=''
for argument in "$@"; do
    case "$argument" in
        --file=*) file=${argument#--file=} ;;
        --formula) kind=formula ;;
        --cask) kind=cask ;;
        *) exit 96 ;;
    esac
done
[ -f "$file" ] || exit 96
file=${file##*/}

# Model native Bundle output, not a parser for the project's Brewfiles.
requested() {
    case "$file:$1" in
        Brewfile.common:formula) printf '%s\n' python jq kind ;;
        Brewfile.common:cask)
            if [ "${DOTFILES_GUI:-desktop}" = desktop ]; then
                printf '%s\n' ghostty font-jetbrains-mono-nerd-font
            fi ;;
        Brewfile.home:formula) ;;
        Brewfile.home:cask)
            if [ "${DOTFILES_GUI:-desktop}" = desktop ]; then
                printf '%s\n' brave-browser google-chrome rectangle
            fi ;;
        Brewfile.work:formula) printf '%s\n' node yq ;;
        Brewfile.work:cask)
            printf '%s\n' claude-code corretto@21
            if [ "${DOTFILES_GUI:-desktop}" = desktop ]; then printf '%s\n' pgadmin4; fi ;;
        *) exit 96 ;;
    esac
}

if [ "$action" = list ]; then
    [ "${DOTFILES_MACOS_LIST_STATUS:-0}" = 0 ] || exit "$DOTFILES_MACOS_LIST_STATUS"
    requested "$kind"
    exit 0
fi

[ -z "$kind" ] || exit 96
: > "$DOTFILES_MACOS_FIXTURE/bundle-started"
printf '%s\n' "${HOMEBREW_CASK_OPTS:-}" > "$DOTFILES_MACOS_FIXTURE/cask-options-$file"
if [ -f "$STATE_DIR/journal.tsv" ]; then
    cp "$STATE_DIR/journal.tsv" "$DOTFILES_MACOS_FIXTURE/before-$file.tsv"
fi
if [ "$file" = "${DOTFILES_MACOS_FAIL_FILE:-Brewfile.work}" ] &&
    [ "${DOTFILES_MACOS_BUNDLE_STATUS:-0}" != 0 ]; then
    if [ -n "${DOTFILES_MACOS_PARTIAL_FORMULA:-}" ]; then
        printf '2\n' > "$DOTFILES_MACOS_FIXTURE/formula/$DOTFILES_MACOS_PARTIAL_FORMULA"
    fi
    if [ -n "${DOTFILES_MACOS_PARTIAL_CASK:-}" ]; then
        printf '2\n' > "$DOTFILES_MACOS_FIXTURE/cask/$DOTFILES_MACOS_PARTIAL_CASK"
    fi
    exit "$DOTFILES_MACOS_BUNDLE_STATUS"
fi

for kind in formula cask; do
    while IFS= read -r package; do
        [ -n "$package" ] || continue
        [ "$kind:$package" != "${DOTFILES_MACOS_OMIT_PACKAGE:-}" ] || continue
        printf '2\n' > "$DOTFILES_MACOS_FIXTURE/$kind/$package"
    done < <(requested "$kind")
done
if [ "$file" = Brewfile.common ]; then
    printf '1\n' > "$DOTFILES_MACOS_FIXTURE/formula/openssl@3"
    if [ -n "${DOTFILES_MACOS_DEPENDENCY_FORMULA:-}" ]; then
        printf '1\n' > "$DOTFILES_MACOS_FIXTURE/formula/$DOTFILES_MACOS_DEPENDENCY_FORMULA"
    fi
fi