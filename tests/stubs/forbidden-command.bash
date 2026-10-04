#!/usr/bin/env bash
set -eu

: "${DOTFILES_TEST_COMMAND_LOG:?a sandbox command log is required}"
if [ "${DOTFILES_TESTING:-}" != 1 ]; then
    printf 'command guard requires DOTFILES_TESTING=1\n' >&2
    exit 98
fi

{
    printf '%s' "${0##*/}"
    for argument in "$@"; do
        printf '\t%s' "$argument"
    done
    printf '\n'
} >> "$DOTFILES_TEST_COMMAND_LOG"
printf 'forbidden command invoked: %s\n' "${0##*/}" >&2
exit 97