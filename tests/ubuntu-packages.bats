#!/usr/bin/env bats

load test_helper

setup() {
    setup_sandbox
    export DOTFILES_APT_DATABASE="$BATS_TEST_TMPDIR/packages"
    export DOTFILES_APT_LOG="$BATS_TEST_TMPDIR/apt.log"
    : > "$DOTFILES_APT_DATABASE"
    local tool
    for tool in apt-get apt-cache dpkg-query sudo; do
        rm "$STUB_BIN/$tool"
        ln -s "$PROJECT_ROOT/tests/stubs/ubuntu-package-command.bash" "$STUB_BIN/$tool"
    done
}

@test "Ubuntu manifests layer profiles and select no desktop records in headless mode" {
    run_module platforms/ubuntu '
        ubuntu_manifest work headless
    '
    assert_status 0
    [[ "$output" != *$'\tdesktop\t'* ]]
    assert_output_contains $'corretto@21\tcli\tvendor\tcorretto21\trequired'
    assert_output_contains $'claude-code\tcli\trelease\tclaude-code\trequired'
    assert_output_contains $'yq\tcli\trelease\tyq\trequired'
    assert_output_contains $'kind\tcli\tapt\tkind\trequired'
    assert_output_contains $'gh\tcli\tapt\tgh\trequired'
    assert_no_preview_side_effects
}

@test "Ubuntu native names retain AWS v2 tooling, batcat, dust and TypeScript dispositions" {
    run_module platforms/ubuntu 'ubuntu_manifest work desktop'
    assert_status 0
    assert_output_contains $'awscli\tcli\tapt\tawscli\trequired'
    assert_output_contains $'bat\tcli\tapt\tbat\trequired'
    assert_output_contains $'dust\tcli\tapt\tdu-dust\trequired'
    assert_output_contains $'tsc\tcli\tapt\tnode-typescript\trequired'
    assert_output_contains 'GitHub Desktop has no official Linux distribution'
    [[ "$output" != *$'\tapt\tyq\t'* ]]
    assert_no_preview_side_effects
}

@test "Ubuntu manifest deduplicates common profile requests" {
    run_module platforms/ubuntu '
        fixture=$BATS_TEST_TMPDIR/inventory
        mkdir -p "$fixture/packages/ubuntu"
        printf "one\tcli\tapt\tgit\trequired\n" > "$fixture/packages/ubuntu/common.tsv"
        printf "one\tcli\tapt\tgit\trequired\ntwo\tcli\tapt\tgit\trequired\n" > "$fixture/packages/ubuntu/home.tsv"
        SCRIPT_DIR=$fixture
        ubuntu_manifest home headless
    '
    assert_status 0
    assert_output_equals $'one\tcli\tapt\tgit\trequired'
}

@test "Ubuntu rejects conflicting and executable manifest records" {
    run_module platforms/ubuntu '
        fixture=$BATS_TEST_TMPDIR/inventory
        mkdir -p "$fixture/packages/ubuntu"
        printf "one\tcli\tapt\tgit\trequired\n" > "$fixture/packages/ubuntu/common.tsv"
        printf "one\tcli\tapt\tcurl\trequired\n" > "$fixture/packages/ubuntu/home.tsv"
        SCRIPT_DIR=$fixture
        ubuntu_manifest home headless
    '
    assert_failure
    run_module platforms/ubuntu 'ubuntu_release_available "touch $DOTFILES_TEST_HOME/pwned"'
    assert_failure
    [ ! -e "$DOTFILES_TEST_HOME/pwned" ]
}

@test "APT ownership preserves pre-existing packages and protects foundational dependencies" {
    printf 'git installed\n' > "$DOTFILES_APT_DATABASE"
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        ubuntu_install_apt git jq curl
        [ "$(state_value package apt:git)" = preexisting ]
        [ "$(state_value package apt:jq)" = owned ]
        [ "$(state_extra package apt:jq)" = eligible ]
        [ "$(state_extra package apt:curl)" = protected ]
        ubuntu_install_apt git jq curl
        [ "$(state_value package apt:jq)" = owned ]
    '
    assert_status 0
    [ "$(wc -l < "$DOTFILES_APT_LOG" | tr -d ' ')" = 1 ]
    assert_no_forbidden_commands
}

@test "APT partial failures preserve the exact failure and journal successfully installed packages" {
    export DOTFILES_APT_PARTIAL=jq DOTFILES_APT_EXIT=42
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        ubuntu_install_apt jq bat
    '
    assert_status 42
    run_module state '
        init_paths setup
        [ "$(state_value package apt:jq)" = owned ]
        [ -z "$(state_value package apt:bat)" ]
        [ "$(state_value package-attempt apt:bat)" = absent ]
    '
    assert_status 0
    assert_no_forbidden_commands
}

@test "APT half-configured packages remain owned but do not report success" {
    export DOTFILES_APT_STATUS=half-configured
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        ubuntu_install_apt jq
    '
    assert_failure
    assert_output_contains 'partially configured'
    run_module state 'init_paths setup; state_value package apt:jq'
    assert_output_equals owned
}

@test "APT preview performs no package queries, writes or installations" {
    run_module platforms/ubuntu '
        DRY_RUN=1
        ubuntu_install_apt git zsh jq
    '
    assert_status 0
    [ ! -e "$DOTFILES_APT_LOG" ]
    [ ! -s "$DOTFILES_APT_DATABASE" ]
    assert_no_preview_side_effects
}

@test "asset links refuse to replace a foreign executable" {
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        printf foreign > "$USER_HOME/tool"
        ubuntu_asset_link /managed/tool "$USER_HOME/tool" tool
    '
    assert_failure
    [ "$(< "$DOTFILES_TEST_HOME/tool")" = foreign ]
}

@test "verified release metadata covers required CLI recipes on both architectures" {
    run_module platforms/ubuntu '
        for ARCH in amd64 arm64; do
            for id in uv kubectl tofu zsh-autocomplete zsh-you-should-use yazi rtk claude-code jenv nodenv node-build prettier vault yq; do
                ubuntu_release_available "$id" || exit 1
                [ "${#RELEASE_SHA256}" = 64 ] || exit 1
            done
        done
    '
    assert_status 0
    assert_no_preview_side_effects
}

@test "a checksum mismatch cannot extract or activate a release" {
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        RELEASE_ID=kubectl RELEASE_VERSION=test RELEASE_FORMAT=binary RELEASE_MEMBER=kubectl
        RELEASE_URL=https://example.invalid/kubectl RELEASE_SHA256=0000000000000000000000000000000000000000000000000000000000000000
        curl() {
            while [ "$#" -gt 0 ]; do
                if [ "$1" = --output ]; then printf tampered > "$2"; return; fi
                shift
            done
            return 1
        }
        ubuntu_install_release_action kubectl
    '
    assert_failure
    assert_output_contains 'SHA256 mismatch'
    [ ! -e "$DOTFILES_TEST_HOME/.local/bin/kubectl" ]
    [ ! -e "$DOTFILES_TEST_HOME/.local/share/dotfiles/packages/kubectl-test" ]
    assert_no_forbidden_commands
}

@test "missing optional artifacts are skipped but required architecture gaps fail" {
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        ARCH=unsupported
        DRY_RUN=1
        ubuntu_install_release lapce optional
    '
    assert_status 0
    assert_output_contains '[SKIPPED]'
    run_module platforms/ubuntu '
        ARCH=unsupported
        DRY_RUN=1
        ubuntu_install_release uv required
    '
    assert_failure
    assert_no_preview_side_effects
}

@test "release metadata contains only complete unique explicit version and architecture records" {
    run awk -F '\t' '
        /^#/ || NF == 0 { next }
        NF != 8 || $2 == "latest" || $3 !~ /^(amd64|arm64|all)$/ ||
            $4 !~ /^https:\/\// || length($5) != 64 || $5 ~ /[^0-9a-f]/ ||
            $6 !~ /^(binary|tar.gz|tar.xz|zip|deb)$/ || seen[$1 SUBSEP $3]++ { exit 1 }
    ' "$PROJECT_ROOT/packages/ubuntu/releases.tsv"
    assert_status 0
}

@test "both Ubuntu profiles preview on both architectures without installed package tools" {
    make_minimal_path
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        DRY_RUN=1
        PATH=$1
        for ARCH in amd64 arm64; do
            for profile in home work; do
                for mode in headless desktop; do
                    platform_install_packages "$profile" "$mode" || exit 1
                done
            done
        done
    ' "$MINIMAL_PATH"
    assert_status 0
    assert_output_contains 'corretto21'
    assert_output_contains 'claude-code'
    assert_output_contains 'brave'
    assert_no_preview_side_effects
}

@test "APT retries reconcile an absent attempt before recording an installed package" {
    printf 'jq installed\n' > "$DOTFILES_APT_DATABASE"
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        state_record package-attempt apt:jq absent eligible
        ubuntu_install_apt jq
        [ "$(state_value package apt:jq)" = owned ]
    '
    assert_status 0
    [ ! -e "$DOTFILES_APT_LOG" ]
    assert_no_forbidden_commands
}

@test "manifests reject unsafe APT operands before any package mutation" {
    run_module platforms/ubuntu '
        fixture=$BATS_TEST_TMPDIR/inventory
        mkdir -p "$fixture/packages/ubuntu"
        printf "one\tcli\tapt\t--allow-unauthenticated\trequired\n" > "$fixture/packages/ubuntu/common.tsv"
        : > "$fixture/packages/ubuntu/home.tsv"
        SCRIPT_DIR=$fixture
        ubuntu_manifest home headless
    '
    assert_failure
    assert_no_preview_side_effects
}

@test "required manual entries and invalid installation modes are rejected" {
    run_module platforms/ubuntu 'ubuntu_manifest home typo'
    assert_failure
    run_module platforms/ubuntu '
        fixture=$BATS_TEST_TMPDIR/inventory
        mkdir -p "$fixture/packages/ubuntu"
        printf "one\tcli\tmanual\tinstall it yourself\trequired\n" > "$fixture/packages/ubuntu/common.tsv"
        : > "$fixture/packages/ubuntu/home.tsv"
        SCRIPT_DIR=$fixture
        ubuntu_manifest home headless
    '
    assert_failure
    assert_no_preview_side_effects
}

@test "a recorded release is rechecked instead of trusting a modified managed tree" {
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        ARCH=amd64
        ubuntu_release_available kubectl
        destination=$DATA_HOME/dotfiles/packages/kubectl-$RELEASE_VERSION
        mkdir -p "$destination"
        printf original > "$destination/kubectl"
        chmod 0755 "$destination/kubectl"
        state_record asset-tree "$destination" "$(ubuntu_tree_checksum "$destination")" kubectl
        state_record release kubectl "$RELEASE_VERSION" "$destination"
        printf modified > "$destination/kubectl"
        ubuntu_install_release kubectl required
    '
    assert_failure
    [ ! -e "$DOTFILES_TEST_HOME/.local/bin/kubectl" ]
    assert_no_forbidden_commands
}

@test "release metadata rejects mutable versions and duplicate architecture matches" {
    run_module platforms/ubuntu '
        fixture=$BATS_TEST_TMPDIR/inventory
        mkdir -p "$fixture/packages/ubuntu"
        printf "kubectl\tlatest\tamd64\thttps://example.invalid/kubectl\t%064d\tbinary\tkubectl\tkubectl\n" 0 > "$fixture/packages/ubuntu/releases.tsv"
        SCRIPT_DIR=$fixture ARCH=amd64
        ubuntu_release_available kubectl
    '
    assert_failure
    run_module platforms/ubuntu '
        fixture=$BATS_TEST_TMPDIR/inventory
        mkdir -p "$fixture/packages/ubuntu"
        printf "kubectl\t1.0\t%s\thttps://example.invalid/kubectl\t%064d\tbinary\tkubectl\tkubectl\n" amd64 0 all 0 > "$fixture/packages/ubuntu/releases.tsv"
        SCRIPT_DIR=$fixture ARCH=amd64
        ubuntu_release_available kubectl
    '
    assert_failure
    assert_no_preview_side_effects
}

@test "an unrecorded existing release directory with valid member is adopted and activated" {
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        ARCH=amd64
        ubuntu_release_available zsh-autocomplete
        destination=$DATA_HOME/dotfiles/packages/zsh-autocomplete-$RELEASE_VERSION
        mkdir -p "$destination/$RELEASE_MEMBER"
        ubuntu_install_release zsh-autocomplete required
        [ "$(state_value release zsh-autocomplete)" = "$RELEASE_VERSION" ]
        [ "$(state_extra asset-tree "$destination")" = zsh-autocomplete ]
    '
    assert_status 0
}

@test "an unrecorded existing release directory missing member is rejected" {
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        ARCH=amd64
        ubuntu_release_available zsh-autocomplete
        destination=$DATA_HOME/dotfiles/packages/zsh-autocomplete-$RELEASE_VERSION
        mkdir -p "$destination"
        ubuntu_install_release zsh-autocomplete required
    '
    assert_failure
}

@test "ubuntu_install_deb ensures .deb suffix before invoking apt-get" {
    run_module platforms/ubuntu '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        ARCH=amd64
        RELEASE_COMMAND=testpkg
        deb_dir=$BATS_TEST_TMPDIR/pkg
        mkdir -p "$deb_dir/DEBIAN"
        printf "Package: testpkg\nVersion: 1.0\nArchitecture: amd64\nMaintainer: test\nDescription: test\n" > "$deb_dir/DEBIAN/control"
        if command -v dpkg-deb >/dev/null 2>&1; then
            dpkg-deb --build "$deb_dir" "$BATS_TEST_TMPDIR/archive" >/dev/null 2>&1
        else
            cat <<'\''EOF'\'' > "$BATS_TEST_TMPDIR/stub-bin/dpkg-deb"
#!/bin/bash
case "$1" in
    --field)
        case "$3" in
            Package) printf "testpkg\n" ;;
            Architecture) printf "amd64\n" ;;
        esac
        ;;
    *) exit 0 ;;
esac
EOF
            chmod +x "$BATS_TEST_TMPDIR/stub-bin/dpkg-deb"
            touch "$BATS_TEST_TMPDIR/archive"
        fi
        ubuntu_install_deb "$BATS_TEST_TMPDIR/archive"
        [ "$(state_value package apt:testpkg)" = owned ]
        grep -q "testpkg.deb" "$DOTFILES_APT_LOG"
    '
    assert_status 0
}