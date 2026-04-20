#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -eq 0 ]; then
    echo "Usage: run-just-workflow.sh <recipe>..." >&2
    exit 1
fi

for recipe in "$@"; do
    just "$recipe"
done
