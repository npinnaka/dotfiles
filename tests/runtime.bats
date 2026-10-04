#!/usr/bin/env bats

load test_helper

setup() {
    setup_sandbox
}

@test "runtime_setup_python_venv preserves existing environment" {
    run_module runtime '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        mkdir -p "$USER_HOME/.venv/bin"
        touch "$USER_HOME/.venv/bin/activate"
        runtime_setup_python_venv
        [ -f "$USER_HOME/.venv/bin/activate" ]
    '
    assert_status 0
    assert_output_contains "Python virtual environment"
}

@test "runtime_setup_idea_plugins skips in headless mode" {
    run_module runtime '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        runtime_setup_idea_plugins headless
    '
    assert_status 0
    assert_output_contains "IntelliJ IDEA plugins (headless mode)"
}

@test "runtime_setup_containers skips cluster for work profile or skip-cluster flag" {
    run_module runtime '
        . "$SCRIPT_DIR/lib/state.sh"
        platform_prepare_containers() { return 0; }
        init_paths setup
        runtime_setup_containers ubuntu work 0
    '
    assert_status 0
    assert_output_contains "Local cluster creation (work profile or --skip-cluster)"

    run_module runtime '
        . "$SCRIPT_DIR/lib/state.sh"
        platform_prepare_containers() { return 0; }
        init_paths setup
        runtime_setup_containers ubuntu home 1
    '
    assert_status 0
    assert_output_contains "Local cluster creation (work profile or --skip-cluster)"
}
