#!/usr/bin/env bash
set -eu

if [ "${DOTFILES_TESTING:-}" != 1 ]; then
    printf 'tee fixture requires DOTFILES_TESTING=1\n' >&2
    exit 98
fi

if [ "${DOTFILES_TEST_TEE_STATUS:-0}" -eq 0 ]; then
    exec "${DOTFILES_TEST_REAL_TEE:?the real tee path is required}" "$@"
fi

# Drain the pipe so a fixture failure does not cause an unrelated SIGPIPE.
cat > /dev/null
exit "$DOTFILES_TEST_TEE_STATUS"