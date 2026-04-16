#!/usr/bin/env bash
set -euo pipefail

mode="${1:-install}"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1

require_command() {
    local command_name="$1"
    local description="$2"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "Missing required command: $description ($command_name)" >&2
        exit 1
    fi
}

require_homebrew() {
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is required for workspace bootstrap and Temurin management." >&2
        echo "Install Homebrew first, then rerun the workspace command." >&2
        exit 1
    fi
}

brew_formula() {
    local formula="$1"

    if brew list --formula "$formula" >/dev/null 2>&1; then
        brew upgrade "$formula"
    else
        brew install "$formula"
    fi
}

brew_cask() {
    local cask="$1"

    if brew list --cask "$cask" >/dev/null 2>&1; then
        brew upgrade --cask "$cask"
    else
        brew install --cask "$cask"
    fi
}

ensure_workspace_cli_tools() {
    echo "Ensuring workspace CLI tools are installed..."
    brew_formula just
    brew_formula jq
}

ensure_temurin() {
    echo "Ensuring Temurin JDK is installed via Homebrew..."
    brew_cask temurin
    echo "Installed JDK version:"
    /usr/libexec/java_home -V 2>&1
}

verify_runtime_requirements() {
    require_command bash "Bash"
    require_command git "Git"
    require_command curl "curl"
    require_command docker "Docker"

    if ! docker buildx version >/dev/null 2>&1; then
        echo "Docker buildx is required by workspace base-image resolution." >&2
        exit 1
    fi
}

require_homebrew

case "$mode" in
    install|update)
        ensure_workspace_cli_tools
        ensure_temurin
        verify_runtime_requirements
        ;;
    update-java)
        ensure_temurin
        ;;
    check)
        verify_runtime_requirements
        require_command just "Just"
        require_command jq "jq"
        ;;
    *)
        echo "Unknown mode: $mode" >&2
        exit 1
        ;;
esac
