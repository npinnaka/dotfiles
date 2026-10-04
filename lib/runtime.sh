#!/bin/bash
# lib/runtime.sh - Portable runtime and container configuration.

set -e

runtime_setup_python_venv() {
    local venv_path="$USER_HOME/.venv"

    if [ -d "$venv_path" ] && [ -f "$venv_path/bin/activate" ]; then
        report PRESENT "Python virtual environment at $venv_path"
        return 0
    fi

    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "Create Python environment $venv_path (preferring uv)"
        return 0
    fi

    if command -v uv >/dev/null 2>&1; then
        run uv venv "$venv_path" || return $?
    elif command -v python3 >/dev/null 2>&1; then
        run python3 -m venv "$venv_path" || return $?
    else
        fail "Neither uv nor python3 found to create virtual environment."
        return 1
    fi

    state_record venv "$venv_path" "created" - || return $?
    report INSTALLED "Python virtual environment at $venv_path"
}

runtime_setup_idea_plugins() {
    local gui_mode=$1

    if [ "$gui_mode" = headless ]; then
        report SKIPPED "IntelliJ IDEA plugins (headless mode)."
        return 0
    fi

    local launcher
    if launcher=$(platform_find_idea_launcher 2>/dev/null); then
        local plugins=("com.anthropic.claudecode" "com.github.copilot" "org.jetbrains.plugins.go")
        if [ "$DRY_RUN" = 1 ]; then
            report PLANNED "Install IntelliJ IDEA plugins: ${plugins[*]}"
            return 0
        fi
        run "$launcher" installPlugins "${plugins[@]}" || return $?
        report INSTALLED "IntelliJ IDEA plugins"
    else
        report SKIPPED "IntelliJ IDEA not found; skipping plugin installation."
    fi
}

runtime_setup_rtk() {
    if command -v rtk >/dev/null 2>&1; then
        if [ "$DRY_RUN" = 1 ]; then
            report PLANNED "Initialize rtk globally with rtk init -g"
            return 0
        fi
        run rtk init -g || return $?
        report INSTALLED "rtk global configuration"
    else
        report SKIPPED "rtk is not installed; skipping rtk init."
    fi
}

runtime_setup_containers() {
    local _platform=$1 profile=$2 skip_cluster=$3

    platform_prepare_containers || return $?

    if [ "$profile" != home ] || [ "$skip_cluster" = 1 ]; then
        report SKIPPED "Local cluster creation (work profile or --skip-cluster)."
        return 0
    fi

    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED "Reuse local Podman kind clusters or create kind after prerequisite checks."
        return 0
    fi

    if command -v kind >/dev/null 2>&1; then
        if kind get clusters 2>/dev/null | grep -qx 'kind'; then
            report PRESENT "Kind Kubernetes cluster 'kind'"
            return 0
        fi

        KIND_EXPERIMENTAL_PROVIDER=podman run kind create cluster --name kind || return $?
        state_record cluster "kind" "podman" - || return $?
        report INSTALLED "Kind Kubernetes cluster 'kind'"
    else
        report SKIPPED "kind command not found; skipping cluster creation."
    fi
}

runtime_purge() {
    local key val extra
    if [ "$DRY_RUN" = 1 ]; then
        report PLANNED 'Purge recorded Python virtual environments and local Kubernetes clusters.'
        return 0
    fi

    # Purge recorded Python virtual environments
    while IFS=$'\t' read -r key val extra; do
        [ -n "$key" ] || continue
        if [ -d "$key" ] || [ -f "$key" ] || [ -L "$key" ]; then
            run rm -rf "$key" || true
            report INSTALLED "Removed Python virtual environment $key"
        fi
        state_forget venv "$key" || true
    done <<EOF
$(state_each venv)
EOF

    # Purge recorded Kind clusters
    while IFS=$'\t' read -r key val extra; do
        [ -n "$key" ] || continue
        local cluster_name=$key
        local provider=$val
        if command -v kind >/dev/null 2>&1; then
            if kind get clusters 2>/dev/null | grep -qx "$cluster_name"; then
                if [ "$provider" = podman ]; then
                    KIND_EXPERIMENTAL_PROVIDER=podman run kind delete cluster --name "$cluster_name" || true
                else
                    run kind delete cluster --name "$cluster_name" || true
                fi
                report INSTALLED "Deleted Kind cluster $cluster_name"
            fi
        fi
        state_forget cluster "$key" || true
    done <<EOF
$(state_each cluster)
EOF
}
