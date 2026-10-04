#!/usr/bin/env bash
set -euo pipefail

mode="${1:-install}"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1
holds_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/policy/version-holds.txt"

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

candidate_version() {
    local kind="$1"
    local name="$2"

    if [ "$kind" = "cask" ]; then
        brew info --cask --json=v2 "$name" | jq -r '.casks[0].version'
    else
        brew info --json=v2 "$name" | jq -r '.formulae[0].versions.stable'
    fi
}

is_held() {
    local name="$1"
    local version="$2"
    local today
    local kind hold_name hold_version until reason

    [ -f "$holds_file" ] || return 1
    today="$(date +%F)"

    while read -r kind hold_name hold_version until reason; do
        if ! [[ "$until" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || [ -z "$reason" ]; then
            echo "Malformed line in $holds_file: '$kind $hold_name $hold_version $until $reason' (expected: kind name version YYYY-MM-DD reason)" >&2
            exit 1
        fi
        [ "$kind" = "brew" ] && [ "$hold_name" = "$name" ] || continue
        case "$version" in
            "$hold_version" | "$hold_version"[.,_-]*) ;;
            *) continue ;;
        esac
        if [[ "$today" > "$until" ]]; then
            echo "Hold on $name $hold_version expired on $until; upgrading. Remove it from $holds_file."
            continue
        fi
        echo "Holding $name $version until $until ($reason)."
        return 0
    done < <(grep -Ev '^[[:space:]]*(#|$)' "$holds_file")

    return 1
}

brew_formula() {
    local formula="$1"

    if brew list --formula "$formula" >/dev/null 2>&1; then
        is_held "$formula" "$(candidate_version formula "$formula")" || brew upgrade "$formula"
    else
        brew install "$formula"
    fi
}

brew_cask() {
    local cask="$1"

    if brew list --cask "$cask" >/dev/null 2>&1; then
        is_held "$cask" "$(candidate_version cask "$cask")" || brew upgrade --cask "$cask"
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
