#!/bin/bash
set -e
[ "${DOTFILES_TESTING:-0}" = 1 ] || exit 98
tool=${0##*/}
case "$tool" in
    sudo)
        [ "${1:-}" != -- ] || shift
        exec "$@"
        ;;
    dpkg-query)
        package=${!#}
        awk -v package="$package" '$1 == package { print $2; found=1 } END { exit !found }' "$DOTFILES_APT_DATABASE"
        ;;
    apt-cache)
        printf '  Candidate: 1.0\n'
        ;;
    apt-get)
        printf '%s\n' "$*" >> "$DOTFILES_APT_LOG"
        action=$1
        shift
        [ "$action" = install ] || exit "${DOTFILES_APT_EXIT:-0}"
        for package in "$@"; do
            case "$package" in -*) continue ;; esac
            case "$package" in
                */*)
                    if [ "${package##*.}" != deb ]; then
                        printf 'E: Unsupported file %s given on commandline\n' "$package" >&2
                        exit 100
                    fi
                    ;;
            esac
            if [ -n "${DOTFILES_APT_PARTIAL:-}" ] && [ "$package" != "$DOTFILES_APT_PARTIAL" ]; then continue; fi
            pkg_name=$package
            if [ -f "$package" ] && [ "${package##*.}" = deb ]; then
                pkg_name=$(dpkg-deb --field "$package" Package 2>/dev/null || printf '%s\n' "$package")
            fi
            printf '%s %s\n' "$pkg_name" "${DOTFILES_APT_STATUS:-installed}" >> "$DOTFILES_APT_DATABASE"
        done
        exit "${DOTFILES_APT_EXIT:-0}"
        ;;
    *) exit 97 ;;
esac