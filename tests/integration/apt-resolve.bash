#!/bin/bash
# Repository-only APT index download and transaction simulation; no root/install.
set -e
set -o pipefail

root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
arch=${1:?Usage: apt-resolve.bash amd64|arm64 [package ...]}
shift
case "$arch" in
    amd64) mirror=https://archive.ubuntu.com/ubuntu ;;
    arm64) mirror=https://ports.ubuntu.com/ubuntu-ports ;;
    *) printf 'Unsupported architecture: %s\n' "$arch" >&2; exit 2 ;;
esac
keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg
[ -f "$keyring" ] || { printf 'Ubuntu archive keyring is required.\n' >&2; exit 1; }
workspace=$root/.tools/apt-$arch
mkdir -p "$workspace/etc/apt/preferences.d" "$workspace/var/lib/apt/lists/partial" \
    "$workspace/var/cache/apt/archives/partial" "$workspace/var/log/apt"
printf 'deb [arch=%s signed-by=%s] %s resolute main universe restricted multiverse\n' \
    "$arch" "$keyring" "$mirror" > "$workspace/etc/apt/sources.list"
[ -e "$workspace/status" ] || : > "$workspace/status"
options=(-o "Dir=$workspace" -o "Dir::State::status=$workspace/status"
    -o "Dir::Etc::sourcelist=$workspace/etc/apt/sources.list"
    -o Dir::Etc::sourceparts=- -o Dir::Etc::parts=- -o Dir::Etc::main=-
    -o "APT::Architecture=$arch" -o "APT::Architectures::=$arch"
    -o APT::Get::List-Cleanup=0 -o Acquire::Languages=none)
apt-get "${options[@]}" update
if [ "$#" = 0 ]; then
    packages=()
    while IFS= read -r package; do packages=("${packages[@]}" "$package"); done < <(
        awk -F '\t' '$3 == "apt" { print $4 }' "$root/packages/ubuntu/common.tsv" \
            "$root/packages/ubuntu/home.tsv" "$root/packages/ubuntu/work.tsv" | sort -u
    )
    set -- "${packages[@]}"
fi
apt-cache "${options[@]}" policy "$@" > "$workspace/candidates.log"
apt-get "${options[@]}" --simulate --no-install-recommends install "$@" > "$workspace/simulation.log"
printf 'Resolved %s requested native packages for Ubuntu 26.04/%s; candidates and simulation: %s\n' "$#" "$arch" "$workspace"