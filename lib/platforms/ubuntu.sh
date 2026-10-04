#!/bin/bash
# Ubuntu 26.04 only. Manifest recipes are allowlisted, never evaluated.

ubuntu_manifest() {
    local profile=$1 mode=$2
    case "$profile" in home|work) ;; *) fail "Invalid Ubuntu profile: $profile"; return 1 ;; esac
    case "$mode" in headless|desktop) ;; *) fail "Invalid Ubuntu mode: $mode"; return 1 ;; esac
    awk -F '\t' -v mode="$mode" '
        /^#/ || NF == 0 { next }
        NF != 5 || $1 !~ /^[a-z0-9][a-z0-9@+._-]*$/ || $2 !~ /^(cli|desktop)$/ ||
            $3 !~ /^(apt|release|vendor|manual)$/ || $5 !~ /^(required|optional)$/ ||
            ($3 == "apt" && $4 !~ /^[a-z0-9][a-z0-9+.-]*$/) ||
            ($3 ~ /^(release|vendor)$/ && $4 !~ /^[a-z][a-z0-9-]*$/) ||
            ($3 == "manual" && ($4 == "" || $5 != "optional")) {
                print "Invalid manifest record: " $0 > "/dev/stderr"; exit 1
            }
        seen_id[$1] && records[$1] != $0 { print "Conflicting manifest ID: " $1 > "/dev/stderr"; exit 1 }
        { records[$1] = $0; seen_id[$1] = 1 }
        mode == "headless" && $2 == "desktop" { next }
        seen_provider[$3 SUBSEP $4] && requirements[$3 SUBSEP $4] != $5 {
            print "Conflicting manifest requirement: " $4 > "/dev/stderr"; exit 1
        }
        { requirements[$3 SUBSEP $4] = $5 }
        !seen_provider[$3 SUBSEP $4]++ { print }
    ' "$SCRIPT_DIR/packages/ubuntu/common.tsv" "$SCRIPT_DIR/packages/ubuntu/$profile.tsv"
}

ubuntu_package_status() {
    dpkg-query --show --showformat='${db:Status-Status}' "$1" 2>/dev/null || true
}

ubuntu_package_exists() {
    case "$(ubuntu_package_status "$1")" in
        installed|unpacked|half-configured|half-installed|triggers-awaited|triggers-pending) return 0 ;;
        *) return 1 ;;
    esac
}

ubuntu_candidate() {
    apt-cache policy "$1" | awk '$1 == "Candidate:" && $2 != "(none)" { found = 1 } END { exit !found }'
}

ubuntu_package_eligibility() {
    case "$1" in
        git|zsh|curl|ca-certificates|gnupg|tar|gzip|xz-utils|unzip|python3|python3-venv|uidmap|dbus-user-session|crun)
            printf 'protected\n' ;;
        *) printf 'eligible\n' ;;
    esac
}

ubuntu_package_baseline() {
    local attempt
    attempt=$(state_value package-attempt "apt:$1") || return $?
    if [ "$attempt" = absent ]; then
        printf 'absent\n'
    elif ubuntu_package_exists "$1"; then
        printf 'present\n'
    else
        printf 'absent\n'
    fi
}

ubuntu_install_apt() {
    local package before eligibility rc=0
    local missing=() baseline=()
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "APT install (only missing packages): $*"
        return 0
    fi
    for package in "$@"; do
        eligibility=$(ubuntu_package_eligibility "$package")
        before=$(ubuntu_package_baseline "$package") || return $?
        if ubuntu_package_exists "$package"; then
            record_package apt "$package" "$before" "$eligibility" || return $?
            if [ "$(ubuntu_package_status "$package")" = installed ]; then
                report PRESENT "APT $package"
                continue
            fi
        fi
        missing=("${missing[@]}" "$package")
        baseline=("${baseline[@]}" "$before")
        state_record package-attempt "apt:$package" "$before" "$eligibility" || return $?
    done
    [ "${#missing[@]}" -gt 0 ] || return 0
    run_privileged env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" || rc=$?
    local i=0
    for package in "${missing[@]}"; do
        if ubuntu_package_exists "$package"; then
            record_package apt "$package" "${baseline[$i]}" "$(ubuntu_package_eligibility "$package")" || return $?
            if [ "$(ubuntu_package_status "$package")" = installed ]; then
                report INSTALLED "APT $package"
            else
                report FAILED "APT $package is only partially configured; ownership recorded."
                [ "$rc" != 0 ] || rc=1
            fi
        elif [ "$rc" = 0 ]; then
            report FAILED "APT did not install $package."
            rc=1
        fi
        i=$((i + 1))
    done
    if [ "$rc" != 0 ]; then
        report FAILED "APT transaction exited $rc; successful partial changes were recorded."
    fi
    return "$rc"
}

ubuntu_system_file() {
    local source=$1 destination=$2 owner=$3
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        if [ -f "$destination" ] && [ ! -L "$destination" ] && cmp -s "$source" "$destination"; then
            return 0
        fi
        fail "Preserving existing repository file $destination; review it manually."
        return 1
    fi
    run_privileged install -d -m 0755 "$(dirname "$destination")" || return $?
    run_privileged install -m 0644 "$source" "$destination" || return $?
    state_record system-file "$destination" "$(file_checksum "$destination")" "$owner"
}

ubuntu_universe_files() {
    local temp=$1 mirror
    if [ "$ARCH" = amd64 ]; then mirror=https://archive.ubuntu.com/ubuntu
    else mirror=https://ports.ubuntu.com/ubuntu-ports; fi
    printf 'Types: deb\nURIs: %s\nSuites: resolute resolute-updates\nComponents: universe\nArchitectures: %s\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
        "$mirror" "$ARCH" > "$temp/universe.sources"
    if [ "$ARCH" = amd64 ]; then mirror=https://security.ubuntu.com/ubuntu; fi
    printf '\nTypes: deb\nURIs: %s\nSuites: resolute-security\nComponents: universe\nArchitectures: %s\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n' \
        "$mirror" "$ARCH" >> "$temp/universe.sources"
}

ubuntu_enable_universe() {
    ubuntu_candidate zsh-autosuggestions && return 0
    local temp
    temp=$(mktemp -d "${STATE_DIR:-/tmp}/repository.XXXXXX") || return $?
    run ubuntu_universe_files "$temp" || return $?
    ubuntu_system_file "$temp/universe.sources" /etc/apt/sources.list.d/dotfiles-ubuntu-universe.sources ubuntu-universe || return $?
    run rm -r -- "$temp" || return $?
    run_privileged apt-get update
}

ubuntu_load_release() {
    local row
    [ -f "$SCRIPT_DIR/packages/ubuntu/releases.tsv" ] || { fail 'Release inventory is missing.'; return 1; }
    row=$(awk -F '\t' -v id="$1" -v arch="$ARCH" '
        /^#/ || NF == 0 { next }
        NF != 8 || seen[$1 SUBSEP $3]++ { bad=1 }
        $1 == id && ($3 == arch || $3 == "all") { row=$0; count++ }
        END { if (bad || count > 1) exit 1; if (count == 1) print row }
    ' "$SCRIPT_DIR/packages/ubuntu/releases.tsv") || return $?
    [ -n "$row" ] || return 2
    IFS=$'\t' read -r RELEASE_ID RELEASE_VERSION RELEASE_ARCH RELEASE_URL RELEASE_SHA256 RELEASE_FORMAT RELEASE_MEMBER RELEASE_COMMAND <<EOF
$row
EOF
    [ "$RELEASE_ARCH" = "$ARCH" ] || [ "$RELEASE_ARCH" = all ] || return 1
    case "$RELEASE_VERSION" in ''|latest|stable|main|master|HEAD|*[!a-zA-Z0-9._-]*) fail 'Invalid release version.'; return 1 ;; esac
    case "$RELEASE_COMMAND" in ''|*[!a-zA-Z0-9._-]*) fail 'Invalid release command.'; return 1 ;; esac
    case "$RELEASE_MEMBER" in ''|/*|..|../*|*/../*|*/..) fail 'Unsafe release member.'; return 1 ;; esac
    case "$RELEASE_FORMAT" in binary|tar.gz|tar.xz|zip|deb) ;; *) fail 'Unsupported release format.'; return 1 ;; esac
    [ "${#RELEASE_SHA256}" = 64 ] || { fail "Missing SHA256 pin for $1."; return 1; }
    case "$RELEASE_SHA256" in *[!0-9a-f]*) fail "Invalid SHA256 for $1."; return 1 ;; esac
    case "$RELEASE_URL" in https://?*) ;; *) fail "Non-HTTPS artifact for $1."; return 1 ;; esac
}

ubuntu_tree_checksum() {
    (set -o pipefail; tar --sort=name --numeric-owner --owner=0 --group=0 -cf - -C "$1" . | sha256sum | awk '{print $1}')
}

ubuntu_asset_link() {
    local source=$1 destination=$2 owner=$3 previous
    if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source" ]; then
        return 0
    fi
    previous=$(state_value asset-link "$destination")
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        if [ -z "$previous" ] || [ ! -L "$destination" ] || [ "$(readlink "$destination")" != "$previous" ]; then
            fail "Preserving existing asset $destination; move it manually to install $owner."
            return 1
        fi
        run rm -- "$destination" || return $?
    fi
    run mkdir -p "$(dirname "$destination")" || return $?
    run ln -s "$source" "$destination" || return $?
    state_record asset-link "$destination" "$source" "$owner"
}

ubuntu_launcher_file() {
    local destination=$1 name=$2 executable=$3
    executable=${executable//\\/\\\\}
    executable=${executable//\"/\\\"}
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec="%s"\nTerminal=false\nCategories=Development;\n' \
        "$name" "$executable" > "$destination"
}

ubuntu_add_launcher() {
    local id=$1 executable=$2 destination=$DATA_HOME/applications/dotfiles-$1.desktop
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        report PRESENT "Preserving launcher $destination"
        return 0
    fi
    run mkdir -p "$(dirname "$destination")" || return $?
    run ubuntu_launcher_file "$destination" "$id" "$executable" || return $?
    state_record asset-file "$destination" "$(file_checksum "$destination")" "$id"
}

ubuntu_release_available() {
    # The inventory cannot select arbitrary functions or shell commands.
    case "$1" in
        uv|kubectl|tofu|zsh-autocomplete|zsh-you-should-use|yazi|rtk|bruno|podman-desktop|jetbrains-toolbox|lapce|nerd-font|claude-code|jenv|nodenv|node-build|prettier|vault|yq)
            ubuntu_load_release "$1" ;;
        *) fail "Unknown release recipe: $1"; return 1 ;;
    esac
}

ubuntu_extract_release() {
    local archive=$1 destination=$2 entries
    case "$RELEASE_FORMAT" in
        binary)
            cp "$archive" "$destination/$RELEASE_MEMBER" && chmod 0755 "$destination/$RELEASE_MEMBER" ;;
        tar.gz|tar.xz)
            entries=$(tar -tf "$archive") || return $?
            if printf '%s\n' "$entries" | awk '$0 ~ /^\// || $0 ~ /(^|\/)\.\.(\/|$)/ { bad=1 } END {exit !bad}'; then
                fail "Unsafe archive paths for $RELEASE_ID"; return 1
            fi
            tar -xf "$archive" -C "$destination" ;;
        zip)
            entries=$(unzip -Z1 "$archive") || return $?
            if printf '%s\n' "$entries" | awk '$0 ~ /^\// || $0 ~ /(^|\/)\.\.(\/|$)/ { bad=1 } END {exit !bad}'; then
                fail "Unsafe archive paths for $RELEASE_ID"; return 1
            fi
            unzip -q "$archive" -d "$destination" ;;
        *) fail "Unknown archive format: $RELEASE_FORMAT"; return 1 ;;
    esac
}

ubuntu_install_deb() {
    local archive=$1 package architecture before=absent rc=0 deb_file
    package=$(dpkg-deb --field "$archive" Package) || return $?
    architecture=$(dpkg-deb --field "$archive" Architecture) || return $?
    [ "$package" = "$RELEASE_COMMAND" ] || { fail 'Unexpected package in verified Debian archive.'; return 1; }
    [ "$architecture" = "$ARCH" ] || [ "$architecture" = all ] || { fail 'Debian archive architecture mismatch.'; return 1; }
    if ubuntu_package_exists "$package"; then before=present; fi
    state_record package-attempt "apt:$package" "$before" eligible || return $?
    deb_file=$archive
    if [ "${deb_file##*.}" != deb ]; then
        deb_file="$(dirname "$archive")/$package.deb"
        cp "$archive" "$deb_file" || return $?
    fi
    chmod 0755 "$(dirname "$deb_file")" 2>/dev/null || true
    chmod 0644 "$deb_file" 2>/dev/null || true
    run_privileged env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$deb_file" || rc=$?
    if ubuntu_package_exists "$package"; then record_package apt "$package" "$before" eligible || return $?; fi
    if [ "$rc" = 0 ] && [ "$(ubuntu_package_status "$package")" != installed ]; then
        fail "The verified Debian archive did not install $package successfully."; return 1
    fi
    return "$rc"
}

ubuntu_repository_action() {
    local id=$1 temp fingerprints rc=0 keyring=/etc/apt/keyrings/dotfiles-$1.gpg
    state_init || return $?
    temp=$(mktemp -d "$STATE_DIR/repository.XXXXXX") || return $?
    mkdir -m 0700 "$temp/gnupg" || return $?
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --output "$temp/key" "$VENDOR_KEY_URL" || return $?
    fingerprints=$(gpg --batch --no-options --homedir "$temp/gnupg" --show-keys --with-colons "$temp/key" |
        awk -F: '$1 == "pub" { primary=1 } primary && $1 == "fpr" { print $10; primary=0 }') || return $?
    if ! printf '%s\n' "$fingerprints" | awk -v expected="$VENDOR_FINGERPRINT" '$0 == expected { found=1 } END { exit !found }'; then
        fail "Repository signing fingerprint mismatch for $id; review upstream key rotation."
        return 1
    fi
    gpg --batch --no-options --homedir "$temp/gnupg" --import "$temp/key" || return $?
    gpg --batch --no-options --homedir "$temp/gnupg" --export "$VENDOR_FINGERPRINT" > "$temp/keyring.gpg" || return $?
    [ -s "$temp/keyring.gpg" ] || { fail "Empty signing key for $id."; return 1; }
    printf 'deb [arch=%s signed-by=%s] %s %s %s\n' "$ARCH" "$keyring" "$VENDOR_REPOSITORY" \
        "$VENDOR_SUITE" "$VENDOR_COMPONENTS" > "$temp/source.list"
    ubuntu_system_file "$temp/keyring.gpg" "$keyring" "$id" || return $?
    ubuntu_system_file "$temp/source.list" "/etc/apt/sources.list.d/dotfiles-$id.list" "$id" || return $?
    rm -r -- "$temp" || return $?
    run_privileged apt-get update || rc=$?
    return "$rc"
}

ubuntu_activate_release() {
    local id=$1 destination=$2 member
    member=$destination/$RELEASE_MEMBER
    [ -e "$member" ] || { fail "Missing installed release member: $member"; return 1; }
    case "$id" in
        zsh-autocomplete|zsh-you-should-use)
            ubuntu_asset_link "$member" "$DATA_HOME/dotfiles/plugins/$id" "$id" || return $? ;;
        node-build)
            ubuntu_asset_link "$member" "$DATA_HOME/nodenv/plugins/node-build" "$id" || return $? ;;
        nerd-font)
            ubuntu_asset_link "$member" "$DATA_HOME/fonts/JetBrainsMonoNerdFont" "$id" || return $?
            fc-cache -f "$DATA_HOME/fonts" || return $?
            case "$(fc-match -f '%{family}' 'JetBrainsMono Nerd Font')" in
                *'JetBrainsMono Nerd Font'*) ;;
                *) fail 'Installed font family did not resolve to JetBrainsMono Nerd Font.'; return 1 ;;
            esac
            ;;
        *)
            ubuntu_asset_link "$member" "$BIN_HOME/$RELEASE_COMMAND" "$id" || return $?
            case "$id" in
                uv) ubuntu_asset_link "${member%/*}/uvx" "$BIN_HOME/uvx" "$id" || return $? ;;
                yazi) ubuntu_asset_link "${member%/*}/ya" "$BIN_HOME/ya" "$id" || return $? ;;
                podman-desktop|jetbrains-toolbox|lapce) ubuntu_add_launcher "$id" "$member" || return $? ;;
            esac
            ;;
    esac
    state_record release "$id" "$RELEASE_VERSION" "$destination"
}

ubuntu_install_release_action() {
    local id=$1 temp destination checksum rc=0
    state_init || return $?
    destination=$DATA_HOME/dotfiles/packages/$id-$RELEASE_VERSION
    if [ -e "$destination" ] || [ -L "$destination" ]; then
        if [ ! -L "$destination" ] && [ -d "$destination" ]; then
            local recorded_checksum
            recorded_checksum=$(state_value asset-tree "$destination")
            if [ -n "$recorded_checksum" ]; then
                if [ "$(state_extra asset-tree "$destination")" = "$id" ] &&
                    [ "$recorded_checksum" = "$(ubuntu_tree_checksum "$destination")" ]; then
                    ubuntu_activate_release "$id" "$destination"
                    return $?
                fi
            elif [ -e "$destination/$RELEASE_MEMBER" ]; then
                state_record asset-tree "$destination" "$(ubuntu_tree_checksum "$destination")" "$id" || return $?
                ubuntu_activate_release "$id" "$destination"
                return $?
            fi
        fi
        fail "Preserving existing release directory $destination; review partial installation manually."
        return 1
    fi
    temp=$(mktemp -d "$STATE_DIR/download.XXXXXX") || return $?
    curl --fail --location --proto '=https' --tlsv1.2 --retry 3 --output "$temp/archive" "$RELEASE_URL" || {
        rc=$?; report FAILED "Download failed for $id ($RELEASE_VERSION). Staging: $temp"; return "$rc";
    }
    checksum=$(file_checksum "$temp/archive") || return $?
    [ "$checksum" = "$RELEASE_SHA256" ] || { fail "SHA256 mismatch for $id; not installing. Staging: $temp"; return 1; }
    if [ "$RELEASE_FORMAT" = deb ]; then
        ubuntu_install_deb "$temp/archive" || rc=$?
        rm -r -- "$temp"
        return "$rc"
    fi
    mkdir -p "$temp/extracted" "$(dirname "$destination")" || return $?
    ubuntu_extract_release "$temp/archive" "$temp/extracted" || return $?
    [ -e "$temp/extracted/$RELEASE_MEMBER" ] || { fail "Archive member missing for $id: $RELEASE_MEMBER"; return 1; }
    mv "$temp/extracted" "$destination" || return $?
    state_record asset-tree "$destination" "$(ubuntu_tree_checksum "$destination")" "$id" || return $?
    ubuntu_activate_release "$id" "$destination" || return $?
    rm -r -- "$temp"
}

ubuntu_install_release() {
    local id=$1 requirement=$2 rc=0
    ubuntu_release_available "$id" || rc=$?
    if [ "$rc" != 0 ]; then
        if [ "$rc" = 2 ] && [ "$requirement" = optional ]; then
            report SKIPPED "$id: no verified official Ubuntu 26.04/$ARCH artifact; install manually if supported."
            return 0
        fi
        fail "$id is required but has no verified $ARCH artifact."
        return 1
    fi
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "$id $RELEASE_VERSION ($ARCH): verify SHA256 and install $RELEASE_URL in user-owned paths."
        return 0
    fi
    local previous destination
    previous=$(state_value release "$id")
    if [ "$previous" = "$RELEASE_VERSION" ]; then
        destination=$(state_extra release "$id")
        if [ ! -L "$destination" ] && [ "$(state_extra asset-tree "$destination")" = "$id" ] &&
            [ "$(state_value asset-tree "$destination")" = "$(ubuntu_tree_checksum "$destination")" ]; then
            run ubuntu_activate_release "$id" "$destination" || return $?
            report PRESENT "$id $RELEASE_VERSION (recorded release)"
            return 0
        fi
        fail "Preserving existing release directory $destination; review partial installation manually."
        return 1
    fi
    if [ -z "$previous" ] && [ "$RELEASE_COMMAND" != '-' ] && command -v "$RELEASE_COMMAND" >/dev/null 2>&1; then
        if [ "$id" != yq ] || yq --version 2>/dev/null | awk '/mikefarah/ { found=1 } END { exit !found }'; then
            report PRESENT "$id already available; preserve the existing installation."
            return 0
        fi
        log 'The existing yq is not Mike Farah yq; install the correct tool in the user bin directory.'
    fi
    run ubuntu_install_release_action "$id" || return $?
    report INSTALLED "$id $RELEASE_VERSION"
}

ubuntu_load_vendor() {
    local row
    [ -f "$SCRIPT_DIR/packages/ubuntu/vendors.tsv" ] || { fail 'Vendor repository inventory is missing.'; return 1; }
    row=$(awk -F '\t' -v id="$1" -v arch="$ARCH" '
        /^#/ || NF == 0 { next }
        NF != 8 || seen[$1 SUBSEP $2]++ { bad=1 }
        $1 == id && ($2 == arch || $2 == "all") { row=$0; count++ }
        END { if (bad || count > 1) exit 1; if (count == 1) print row }
    ' "$SCRIPT_DIR/packages/ubuntu/vendors.tsv") || return $?
    [ -n "$row" ] || return 2
    IFS=$'\t' read -r _ VENDOR_ARCH VENDOR_PACKAGE VENDOR_KEY_URL VENDOR_FINGERPRINT VENDOR_REPOSITORY VENDOR_SUITE VENDOR_COMPONENTS <<EOF
$row
EOF
    [ "$VENDOR_ARCH" = "$ARCH" ] || [ "$VENDOR_ARCH" = all ] || return 1
    case "$VENDOR_PACKAGE" in ''|*[!a-zA-Z0-9+.-]*) fail 'Invalid vendor package name.'; return 1 ;; esac
    [ "${#VENDOR_FINGERPRINT}" = 40 ] || { fail "Missing GPG fingerprint pin for $1."; return 1; }
    case "$VENDOR_FINGERPRINT" in *[!0-9A-Fa-f]*) fail "Invalid GPG fingerprint for $1."; return 1 ;; esac
    case "$VENDOR_KEY_URL" in https://?*) ;; *) fail "Non-HTTPS key URL for $1."; return 1 ;; esac
    case "$VENDOR_REPOSITORY" in https://?*) ;; *) fail "Non-HTTPS repository for $1."; return 1 ;; esac
}

ubuntu_vendor_available() {
    case "$1" in
        brave|chrome|corretto21|pgadmin4)
            ubuntu_load_vendor "$1" ;;
        *) fail "Unknown vendor recipe: $1"; return 1 ;;
    esac
}

ubuntu_install_vendor() {
    local id=$1 requirement=$2 rc=0
    ubuntu_vendor_available "$id" || rc=$?
    if [ "$rc" != 0 ]; then
        if [ "$rc" = 2 ] && [ "$requirement" = optional ]; then
            report SKIPPED "$id: no verified official Ubuntu 26.04/$ARCH vendor repository; install manually if supported."
            return 0
        fi
        fail "$id is required but has no verified $ARCH vendor repository."
        return 1
    fi
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "$id ($ARCH): configure signed vendor repository and install $VENDOR_PACKAGE."
        return 0
    fi
    local keyring=/etc/apt/keyrings/dotfiles-$id.gpg
    local sourcelist=/etc/apt/sources.list.d/dotfiles-$id.list
    if [ ! -f "$keyring" ] || [ ! -f "$sourcelist" ]; then
        run ubuntu_repository_action "$id" || return $?
    fi
    ubuntu_install_apt "$VENDOR_PACKAGE" || return $?
}

platform_install_packages() {
    local profile=$1 mode=$2 rows id scope provider item requirement
    local apt_packages=()
    rows=$(ubuntu_manifest "$profile" "$mode") || return $?
    while IFS=$'\t' read -r id scope provider item requirement; do
        if [ "$provider" = release ] && [ "$requirement" = required ]; then
            ubuntu_release_available "$item" || { fail "No verified required release for $item/$ARCH."; return 1; }
        fi
        if [ "$provider" = vendor ] && [ "$requirement" = required ]; then
            ubuntu_vendor_available "$item" || { fail "No verified required vendor repository for $item/$ARCH."; return 1; }
        fi
    done <<EOF
$rows
EOF
    if [ "$DRY_RUN" != 1 ]; then
        state_init || return $?
        run_privileged apt-get update || return $?
        ubuntu_install_apt ca-certificates curl gnupg || return $?
        run ubuntu_enable_universe || return $?
    fi
    while IFS=$'\t' read -r id scope provider item requirement; do
        [ "$provider" = apt ] || continue
        if [ "$DRY_RUN" = 1 ]; then
            report PLANNED "APT $item ($id, $scope); preserve packages already installed."
        elif ubuntu_candidate "$item"; then
            apt_packages=("${apt_packages[@]}" "$item")
        elif [ "$requirement" = optional ]; then
            report SKIPPED "$id: no Ubuntu 26.04/$ARCH APT candidate."
        else
            fail "Missing required Ubuntu 26.04/$ARCH candidate: $item. Enable official Universe sources."
            return 1
        fi
    done <<EOF
$rows
EOF
    if [ "$DRY_RUN" != 1 ]; then
        ubuntu_install_apt "${apt_packages[@]}" || return $?
    fi
    export PATH="$BIN_HOME:$PATH"
    while IFS=$'\t' read -r id scope provider item requirement; do
        case "$provider" in
            apt) ;;
            release) ubuntu_install_release "$item" "$requirement" || return $? ;;
            vendor) ubuntu_install_vendor "$item" "$requirement" || return $? ;;
            manual) report SKIPPED "$id: $item" ;;
        esac
    done <<EOF
$rows
EOF
}

platform_find_idea_launcher() {
    local path
    if command -v idea >/dev/null 2>&1; then
        command -v idea
        return 0
    fi
    for path in \
        /opt/idea*/bin/idea.sh \
        /snap/bin/intellij-idea* \
        "$DATA_HOME/JetBrains/Toolbox/apps/intellij-idea*/bin/idea.sh" \
        "$USER_HOME/.local/share/JetBrains/Toolbox/apps/intellij-idea*/bin/idea.sh"; do
        if [ -x "$path" ]; then
            printf '%s\n' "$path"
            return 0
        fi
    done
    return 1
}

platform_prepare_containers() {
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED 'Validate rootless Podman prerequisites (subuid/subgid, crun, dbus).'
        return 0
    fi
    if command -v podman >/dev/null 2>&1; then
        local user
        user=$(id -un 2>/dev/null || whoami 2>/dev/null || printf 'user')
        if grep -q "^$user:" /etc/subuid 2>/dev/null && grep -q "^$user:" /etc/subgid 2>/dev/null; then
            report PRESENT 'Rootless subuid/subgid allocations'
        else
            report SKIPPED "No subuid/subgid mapping found for user $user."
        fi
    else
        report SKIPPED 'podman is not available; skipping rootless container setup.'
    fi
}

platform_ghostty_config_dir() {
    printf '%s\n' "$CONFIG_HOME/ghostty"
}

platform_remove_owned_packages() {
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED 'Simulate removal of recorded eligible APT packages; refuse unrelated dependency cascades.'
        return 0
    fi
    local key val extra
    local apt_to_remove=()
    while IFS=$'\t' read -r key val extra; do
        [ -n "$key" ] || continue
        [ "$val" = owned ] || continue
        [ "$extra" = eligible ] || continue
        local provider=${key%%:*}
        local pkg=${key#*:}
        case "$provider" in
            apt)
                apt_to_remove=("${apt_to_remove[@]}" "$pkg")
                ;;
        esac
    done <<EOF
$(state_each package)
EOF
    if [ "${#apt_to_remove[@]}" -gt 0 ]; then
        run_privileged env DEBIAN_FRONTEND=noninteractive apt-get remove -y --no-auto-remove "${apt_to_remove[@]}" || true
        for pkg in "${apt_to_remove[@]}"; do
            report INSTALLED "Removed APT package $pkg"
            state_forget package "apt:$pkg" || true
        done
    fi

    # Also remove owned release assets
    local _val
    while IFS=$'\t' read -r key _val extra; do
        [ -n "$key" ] || continue
        local id=$key
        local dest=$extra
        if [ -n "$dest" ] && [ -d "$dest" ]; then
            rm -rf "$dest"
            report INSTALLED "Removed release directory $dest"
        fi
        state_forget release "$id" || true
    done <<EOF
$(state_each release)
EOF

    # Remove asset symlinks
    while IFS=$'\t' read -r key val extra; do
        [ -n "$key" ] || continue
        if [ -L "$key" ]; then
            rm -f "$key"
            report INSTALLED "Removed asset symlink $key"
        fi
        state_forget asset-link "$key" || true
    done <<EOF
$(state_each asset-link)
EOF

    # Remove asset files
    while IFS=$'\t' read -r key val extra; do
        [ -n "$key" ] || continue
        if [ -f "$key" ]; then
            rm -f "$key"
            report INSTALLED "Removed asset file $key"
        fi
        state_forget asset-file "$key" || true
    done <<EOF
$(state_each asset-file)
EOF

    # Remove system files (keyrings / source lists)
    local system_files=()
    while IFS=$'\t' read -r key val extra; do
        [ -n "$key" ] || continue
        if [ -f "$key" ]; then
            system_files=("${system_files[@]}" "$key")
        fi
        state_forget system-file "$key" || true
    done <<EOF
$(state_each system-file)
EOF
    if [ "${#system_files[@]}" -gt 0 ]; then
        run_privileged rm -f "${system_files[@]}" || true
        for f in "${system_files[@]}"; do
            report INSTALLED "Removed system file $f"
        done
    fi
}