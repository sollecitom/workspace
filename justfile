#!/usr/bin/env just --justfile

set quiet

# Project modules (order matters: dependencies first)
publishable := "gradle-plugins acme-schema-catalogue swissknife pillar"
non_publishable := "tools examples facts backend-skeleton modulith-example element-service-example lattice"
all_modules := publishable + " " + non_publishable
workspace_and_modules := "workspace " + all_modules

# Git operations (workspace repo only — for the justfile, CONTEXT.md, analysis files)
push:
    git add -A && (git diff --quiet HEAD || git commit -am "WIP") && git pull --rebase origin main && git push origin main

pull:
    git pull --rebase origin main

build:
    @:

rebuild:
    @:

update-all:
    @:

# Workspace operations
update-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    summary_file=$(mktemp)
    trap 'cd "$start_dir"; rm -f "$summary_file"' EXIT

    for module in {{workspace_and_modules}}; do
        echo ""
        echo "========================================"
        echo "Updating $module..."
        echo "========================================"
        if [ "$module" = "workspace" ]; then
            cd "$start_dir"
        else
            cd "$start_dir/$module"
        fi
        git add -A && (git diff --quiet HEAD || git commit -am "WIP") || true

        just pull
        just update-all
        just build
        module_summary=$(./gradlew -q updateSummary 2>/dev/null || true)
        echo "$module" >> "$summary_file"
        if printf '%s\n' "$module_summary" | grep -q '[^[:space:]]'; then
            while IFS= read -r line; do
                [ -n "$line" ] || continue
                printf '  %s\n' "$line" >> "$summary_file"
            done <<< "$module_summary"
        else
            echo "  No dependencies were updated." >> "$summary_file"
        fi

        echo "✓ $module updated successfully"
    done

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════"
    echo "║ UPDATE SUMMARY"
    echo "╠══════════════════════════════════════════════════════════════════════════════"
    if [ -s "$summary_file" ]; then
        echo "║"
        while IFS= read -r line; do
            if [[ "$line" != " "* ]]; then
                echo "║ ▸ $line"
            else
                echo "║  $line"
            fi
        done < "$summary_file"
        echo "║"
    else
        echo "║"
        echo "║  No upgrade-related changes detected."
        echo "║"
    fi
    echo "╚══════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "✓ All modules updated successfully!"

pull-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{workspace_and_modules}}; do
        echo ""
        echo "========================================"
        echo "Pulling $module..."
        echo "========================================"
        if [ "$module" = "workspace" ]; then
            cd "$start_dir"
        else
            cd "$start_dir/$module"
        fi
        git add -A && (git diff --quiet HEAD || git commit -am "WIP") || true
        just pull
        just build
        echo "✓ $module pulled successfully"
    done
    echo ""
    echo "✓ All modules pulled successfully!"

reset-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{workspace_and_modules}}; do
        echo ""
        echo "========================================"
        echo "Resetting $module..."
        echo "========================================"
        if [ "$module" = "workspace" ]; then
            cd "$start_dir"
        else
            cd "$start_dir/$module"
        fi
        git clean -fdx && git reset --hard
        just build
        echo "✓ $module reset successfully"
    done
    echo ""
    echo "✓ All modules reset successfully!"

push-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{workspace_and_modules}}; do
        echo ""
        echo "========================================"
        echo "Pushing $module..."
        echo "========================================"
        if [ "$module" = "workspace" ]; then
            cd "$start_dir"
        else
            cd "$start_dir/$module"
        fi
        just push
        echo "✓ $module pushed successfully"
    done
    echo ""
    echo "✓ All modules pushed successfully!"

build-and-publish-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{workspace_and_modules}}; do
        echo ""
        echo "========================================"
        echo "Building $module..."
        echo "========================================"
        if [ "$module" = "workspace" ]; then
            cd "$start_dir"
        else
            cd "$start_dir/$module"
        fi
        just build
        [[ " {{publishable}} " =~ " $module " ]] && just publish || true
        echo "✓ $module built and published successfully"
    done
    echo ""
    echo "✓ All modules built and published successfully!"

rebuild-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{workspace_and_modules}}; do
        echo ""
        echo "========================================"
        echo "Rebuilding $module..."
        echo "========================================"
        if [ "$module" = "workspace" ]; then
            cd "$start_dir"
        else
            cd "$start_dir/$module"
        fi
        just rebuild
        echo "✓ $module rebuilt successfully"
    done
    echo ""
    echo "✓ All modules rebuilt successfully!"

build-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{workspace_and_modules}}; do
        echo ""
        echo "========================================"
        echo "Building $module..."
        echo "========================================"
        if [ "$module" = "workspace" ]; then
            cd "$start_dir"
        else
            cd "$start_dir/$module"
        fi
        just build
        echo "✓ $module built successfully"
    done
    echo ""
    echo "✓ All modules built successfully!"

reinstall-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT

    echo ""
    echo "========================================"
    echo "Building workspace..."
    echo "========================================"
    cd "$start_dir"
    just build
    echo "✓ workspace built successfully"

    # Phase 1: Clone all projects (so includeBuild references resolve)
    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Cloning $module..."
        echo "========================================"
        rm -rf "$start_dir/$module"
        cd "$start_dir"
        git clone "git@github.com:sollecitom/$module.git"
        echo "✓ $module cloned"
    done

    # Phase 2: Build in dependency order (all sibling dirs now exist)
    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Building $module..."
        echo "========================================"
        cd "$start_dir/$module"
        just build
        echo "✓ $module built successfully"
    done

    echo ""
    echo "✓ All modules reinstalled successfully!"
