#!/usr/bin/env bash
set -euo pipefail

flow="${1:-all}"
state_dir=".workspace-run-state"

display_path() {
    local path="$1"
    case "$path" in
        ./*)
            printf '%s\n' "$path"
            ;;
        *)
            printf './%s\n' "$path"
            ;;
    esac
}

if [ ! -d "$state_dir" ]; then
    echo "No workspace run state exists at $(display_path "$state_dir")."
    exit 0
fi

if [ "$flow" = "all" ]; then
    rm -rf "$state_dir"
    echo "Removed all workspace run state from $(display_path "$state_dir")."
    exit 0
fi

rm -f \
    "${state_dir}/${flow}.state" \
    "${state_dir}/${flow}.update-summary" \
    "${state_dir}/${flow}.internal-update-summary"

echo "Removed workspace run state for '${flow}' from $(display_path "$state_dir")."
