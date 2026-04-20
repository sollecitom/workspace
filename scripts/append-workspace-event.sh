#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: append-workspace-event.sh <message>" >&2
    exit 1
fi

events_file="${WORKSPACE_UPDATE_EVENTS_FILE:-}"

if [ -z "$events_file" ]; then
    exit 0
fi

printf '%s\n' "$*" >> "$events_file"
