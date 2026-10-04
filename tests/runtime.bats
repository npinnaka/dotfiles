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

@test "runtime_setup_containers creates kind cluster with podman provider and records state" {
    run_module runtime '
        . "$SCRIPT_DIR/lib/state.sh"
        platform_prepare_containers() { return 0; }
        init_paths setup
        rm -f "$STUB_BIN/kind"
        kind() {
            if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
                return 0
            fi
            if [ "$1" = "create" ] && [ "$2" = "cluster" ] && [ "$3" = "--name" ] && [ "$4" = "kind" ]; then
                [ "$KIND_EXPERIMENTAL_PROVIDER" = "podman" ] || exit 1
                return 0
            fi
            exit 1
        }
        export -f kind
        runtime_setup_containers macos home 0
        [ "$(state_value cluster kind)" = "podman" ]
    '
    assert_status 0
    assert_output_contains "Kind Kubernetes cluster 'kind'"
}

@test "runtime_setup_containers detects existing kind cluster with podman provider" {
    run_module runtime '
        . "$SCRIPT_DIR/lib/state.sh"
        platform_prepare_containers() { return 0; }
        init_paths setup
        rm -f "$STUB_BIN/kind"
        kind() {
            if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
                [ "$KIND_EXPERIMENTAL_PROVIDER" = "podman" ] || exit 1
                echo "kind"
                return 0
            fi
            if [ "$1" = "create" ]; then
                echo "ERROR: node(s) already exist" >&2
                exit 1
            fi
            exit 1
        }
        export -f kind
        runtime_setup_containers macos home 0
        [ "$(state_value cluster kind)" = "podman" ]
    '
    assert_status 0
    assert_output_contains "Kind Kubernetes cluster 'kind'"
}

@test "runtime_purge deletes kind cluster with podman provider" {
    run_module runtime '
        . "$SCRIPT_DIR/lib/state.sh"
        init_paths setup
        state_record cluster "kind" "podman" -
        rm -f "$STUB_BIN/kind"
        kind() {
            if [ "$1" = "get" ] && [ "$2" = "clusters" ]; then
                [ "$KIND_EXPERIMENTAL_PROVIDER" = "podman" ] || exit 1
                echo "kind"
                return 0
            fi
            if [ "$1" = "delete" ] && [ "$2" = "cluster" ] && [ "$3" = "--name" ] && [ "$4" = "kind" ]; then
                [ "$KIND_EXPERIMENTAL_PROVIDER" = "podman" ] || exit 1
                return 0
            fi
            exit 1
        }
        export -f kind
        runtime_purge
        [ -z "$(state_value cluster kind)" ]
    '
    assert_status 0
    assert_output_contains "Deleted Kind cluster kind"
}
