#!/usr/bin/env bats

load test_helper

setup() {
    setup_sandbox
}

@test "setup help succeeds without platform checks or side effects" {
    mock_platform UnsupportedTestOS unsupported-test-arch
    run_setup --help
    assert_status 0
    assert_output_matches 'usage'
    assert_output_contains home
    assert_output_contains work
    assert_output_contains --dry-run
    assert_output_contains --desktop
    assert_output_contains --headless
    assert_output_contains --skip-cluster
    assert_no_preview_side_effects
}

@test "uninstall help succeeds without platform checks or side effects" {
    mock_platform UnsupportedTestOS unsupported-test-arch
    run_uninstall --help
    assert_status 0
    assert_output_matches 'usage'
    assert_output_contains --dry-run
    assert_output_contains --remove-packages
    assert_output_contains --purge-runtimes
    assert_output_contains --purge-all
    assert_no_preview_side_effects
}

@test "setup rejects a missing or invalid profile before any writes" {
    run_setup
    assert_failure
    assert_no_preview_side_effects
    run_setup office
    assert_failure
    assert_no_preview_side_effects
    run_setup --dry-run
    assert_failure
    assert_no_preview_side_effects
}

@test "setup rejects repeated and conflicting profiles before any writes" {
    local second
    for second in home work; do
        run_setup home "$second"
        assert_failure
        assert_no_preview_side_effects
    done
}

@test "setup rejects unknown flags with and without dry-run before any writes" {
    run_setup home --unknown-option
    assert_failure
    assert_no_preview_side_effects
    run_setup work --dry-run --unknown-option
    assert_failure
    assert_no_preview_side_effects
}

@test "setup rejects desktop and headless together in either order before any writes" {
    run_setup home --desktop --headless
    assert_failure
    assert_no_preview_side_effects
    run_setup work --headless --desktop
    assert_failure
    assert_no_preview_side_effects
}

@test "uninstall rejects unknown options and positional profiles before any writes" {
    local argument
    for argument in --unknown-option home work --desktop --headless --skip-cluster; do
        run_uninstall "$argument"
        assert_failure
        assert_no_preview_side_effects
    done
}

@test "macOS previews both profiles with desktop mode and concrete plan categories" {
    mock_platform Darwin x86_64
    local profile
    for profile in home work; do
        run_setup "$profile" --dry-run
        assert_setup_preview macos amd64 "$profile" desktop
    done
}

@test "Ubuntu previews both profiles without displays or package commands" {
    mock_platform Linux aarch64
    local profile
    for profile in home work; do
        run_setup "$profile" --dry-run
        assert_setup_preview ubuntu arm64 "$profile" headless
    done
}

@test "setup previews explicit desktop and headless mode overrides" {
    mock_platform Linux x86_64
    export SSH_CONNECTION='192.0.2.1 1234 192.0.2.2 22'
    run_setup home --dry-run --desktop
    assert_setup_preview ubuntu amd64 home desktop
    mock_platform Darwin arm64
    run_setup work --dry-run --headless
    assert_setup_preview macos arm64 work headless
}

@test "setup accepts skip-cluster in preview without invoking a cluster tool" {
    run_setup home --dry-run --headless --skip-cluster
    assert_setup_preview ubuntu amd64 home headless
    assert_output_matches 'cluster'
    assert_output_matches '(skip|disabled|excluded)'
}

@test "uninstall previews on both platforms without touching packages or files" {
    local platform expected
    for platform in Darwin Linux; do
        case "$platform" in Darwin) expected=macos ;; Linux) expected=ubuntu ;; esac
        mock_platform "$platform" x86_64
        run_uninstall --dry-run
        assert_status 0
        assert_output_contains "$expected"
        assert_output_contains amd64
        assert_output_matches '(config|symlink|link|state|journal)'
        assert_output_matches '(package|brew|apt)'
        assert_no_preview_side_effects
        run_uninstall --dry-run --remove-packages
        assert_status 0
        assert_output_contains "$expected"
        assert_output_contains amd64
        assert_output_matches '(package|brew|apt)'
        assert_no_preview_side_effects
    done
}

@test "previews succeed when package and runtime tools are genuinely absent from PATH" {
    make_minimal_path
    local platform expected mode
    for platform in Darwin Linux; do
        case "$platform" in
            Darwin) expected=macos; mode=desktop ;;
            Linux) expected=ubuntu; mode=headless ;;
        esac
        mock_platform "$platform" x86_64
        run env PATH="$MINIMAL_PATH" "$TEST_SHELL" "$PROJECT_ROOT/setup.sh" home --dry-run
        assert_setup_preview "$expected" amd64 home "$mode"
        run env PATH="$MINIMAL_PATH" "$TEST_SHELL" "$PROJECT_ROOT/uninstall.sh" --dry-run --remove-packages
        assert_status 0
        assert_output_contains "$expected"
        assert_output_contains amd64
        assert_no_preview_side_effects
    done
}

@test "unsupported platforms fail preview before any writes" {
    mock_platform Linux x86_64 "$FIXTURES_DIR/os-release/ubuntu-24.04"
    run_setup home --dry-run
    assert_failure
    assert_no_preview_side_effects
    run_uninstall --dry-run
    assert_failure
    assert_no_preview_side_effects
}

@test "all platform architecture profile and mode previews remain side-effect free" {
    local kernel platform machine arch profile mode
    for kernel in Darwin Linux; do
        case "$kernel" in Darwin) platform=macos ;; Linux) platform=ubuntu ;; esac
        for machine in x86_64 arm64; do
            case "$machine" in x86_64) arch=amd64 ;; arm64) arch=arm64 ;; esac
            mock_platform "$kernel" "$machine"
            for profile in home work; do
                for mode in desktop headless; do
                    run_setup "$profile" "--$mode" --dry-run
                    assert_setup_preview "$platform" "$arch" "$profile" "$mode"
                done
            done
        done
    done
}