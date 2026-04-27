#!/usr/bin/env bash
set -euo pipefail

repo_name="${1:-}"
if [ -z "$repo_name" ]; then
    echo "Usage: run-generate-license-snapshot.sh <repo-name>" >&2
    exit 2
fi

max_workers="${LICENSE_AUDIT_MAX_WORKERS:-}"
if [ -z "$max_workers" ]; then
    case "$repo_name" in
        swissknife) max_workers=1 ;;
        *) max_workers=2 ;;
    esac
fi

exec ./gradlew \
    --quiet \
    --warning-mode none \
    --no-configuration-cache \
    --no-parallel \
    --max-workers="$max_workers" \
    -Dkotlin.compiler.execution.strategy=in-process \
    aggregateLicenseDependencySnapshot \
    --init-script ../scripts/cyclonedx-init.gradle
