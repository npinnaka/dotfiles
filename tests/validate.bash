#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
export BATS_SHELL="${BATS_SHELL:-/bin/bash}"

shopt -s nullglob
bash_files=(setup.sh uninstall.sh lib/*.sh lib/platforms/*.sh tests/*.bash tests/stubs/*.bash tests/integration/*.bash)
for source_file in "${bash_files[@]}"; do
    "$BATS_SHELL" -n "$source_file"
done
shellcheck --shell=bash -x "${bash_files[@]}"

zsh -f -n .config/zsh/snippet

while IFS= read -r -d '' source_file; do
    zsh -f -n "$source_file"
done < <(git ls-files -z -- '*.zsh' '*.zshrc' '*.zshenv' '*.zprofile' '*.zlogin' '*.zlogout')

bats tests