#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="$workspace_root/tools"
binary="$tools_dir/modules/license-audit/app/build/install/tools-license-audit-app/bin/tools-license-audit-app"

needs_install=0

if [ ! -x "$binary" ]; then
    needs_install=1
else
    while IFS= read -r source_file; do
        needs_install=1
        break
    done < <(
        find \
            "$tools_dir/modules/license-audit/app/src/main" \
            -type f \
            \( -name '*.kt' -o -name '*.kts' \) \
            -newer "$binary" \
            -print
    )

    for source_file in \
        "$tools_dir/modules/license-audit/app/build.gradle.kts" \
        "$tools_dir/settings.gradle.kts" \
        "$tools_dir/gradle/libs.versions.toml"; do
        if [ "$source_file" -nt "$binary" ]; then
            needs_install=1
            break
        fi
    done
fi

if [ "$needs_install" -eq 1 ]; then
    (
        cd "$tools_dir"
        ./gradlew --quiet --warning-mode none --no-configuration-cache :tools-license-audit-app:installDist
    )
fi

exec "$binary" workspace "$@"
