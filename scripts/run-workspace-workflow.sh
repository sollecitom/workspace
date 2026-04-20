#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: run-workspace-workflow.sh <step>..." >&2
    exit 1
fi

map_step() {
    case "$1" in
        pull|update|build|rebuild|cleanup|install|reinstall|push)
            printf '%s-workspace\n' "$1"
            ;;
        refresh)
            printf '%s\n' "update-workspace"
            ;;
        refresh-local)
            printf '%s\n' "build-workspace"
            ;;
        publish)
            printf '%s\n' "build-and-publish-workspace"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

for step in "$@"; do
    just "$(map_step "$step")"
done
