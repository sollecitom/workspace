#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="$workspace_root/tools"
binary="$tools_dir/modules/license-audit/app/build/install/tools-license-audit-app/bin/tools-license-audit-app"

(
    cd "$tools_dir"
    ./gradlew --quiet --warning-mode none --no-configuration-cache :tools-license-audit-app:installDist
)

exec "$binary" workspace "$@"
