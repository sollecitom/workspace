#!/usr/bin/env just --justfile

set quiet

# Project modules (order matters: dependencies first)
publishable := "gradle-plugins acme-schema-catalogue swissknife pillar"
non_publishable := "tools examples facts backend-skeleton modulith-example element-service-example"
all_modules := publishable + " " + non_publishable

# Git operations
reset-all:
    git fetch origin && git reset --hard origin/main && git clean -f -d

push:
    git add -A && (git diff --quiet HEAD || git commit -am "WIP") && git push origin main

pull:
    git pull

# Build operations
build:
    ./gradlew build

rebuild:
    ./gradlew --refresh-dependencies --rerun-tasks clean build

# Dependency updates
update-dependencies:
    ./gradlew versionCatalogUpdate

update-gradle:
    ./gradlew wrapper --gradle-version latest --distribution-type all

update-all:
    just update-dependencies && just update-gradle

# Workspace operations
@update-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    summary_file=$(mktemp)
    trap 'cd "$start_dir"; rm -f "$summary_file"' EXIT

    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Updating $module..."
        echo "========================================"
        cd "$start_dir/$module"
        git add -A && (git diff --quiet HEAD || git commit -am "WIP") || true

        # Snapshot versions before update
        toml="gradle/libs.versions.toml"
        before=""
        if [ -f "$toml" ]; then
            before=$(mktemp)
            cp "$toml" "$before"
        fi

        just pull
        just update-all
        just build

        # Diff versions after update
        if [ -n "$before" ] && [ -f "$toml" ]; then
            changes=$(diff "$before" "$toml" | grep "^[<>]" | grep -v "^[<>] #" || true)
            if [ -n "$changes" ]; then
                echo "$module" >> "$summary_file"
                # Parse old and new versions
                diff "$before" "$toml" | while IFS= read -r line; do
                    case "$line" in
                        "< "*)
                            key=$(echo "${line#< }" | cut -d= -f1 | xargs)
                            old_val=$(echo "${line#< }" | cut -d= -f2- | xargs | tr -d '"')
                            # Find corresponding new value
                            new_line=$(grep "^${key} *=" "$toml" 2>/dev/null || true)
                            if [ -n "$new_line" ]; then
                                new_val=$(echo "$new_line" | cut -d= -f2- | xargs | tr -d '"')
                                if [ "$old_val" != "$new_val" ]; then
                                    echo "  $key: $old_val → $new_val" >> "$summary_file"
                                fi
                            else
                                echo "  $key: $old_val (removed)" >> "$summary_file"
                            fi
                            ;;
                        "> "*)
                            key=$(echo "${line#> }" | cut -d= -f1 | xargs)
                            # Only report if it's a new entry (not already handled as a change)
                            if [ -n "$before" ] && ! grep -q "^${key} *=" "$before" 2>/dev/null; then
                                new_val=$(echo "${line#> }" | cut -d= -f2- | xargs | tr -d '"')
                                echo "  $key: (new) $new_val" >> "$summary_file"
                            fi
                            ;;
                    esac
                done
            fi
            rm -f "$before"
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
        echo "║  No dependency changes detected."
        echo "║"
    fi
    echo "╚══════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "✓ All modules updated successfully!"

@pull-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Pulling $module..."
        echo "========================================"
        cd "$start_dir/$module"
        git add -A && (git diff --quiet HEAD || git commit -am "WIP") || true
        just pull
        just build
        echo "✓ $module pulled successfully"
    done
    echo ""
    echo "✓ All modules pulled successfully!"

@reset-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Resetting $module..."
        echo "========================================"
        cd "$start_dir/$module"
        git clean -fdx && git reset --hard
        just build
        echo "✓ $module reset successfully"
    done
    echo ""
    echo "✓ All modules reset successfully!"

@push-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Pushing $module..."
        echo "========================================"
        cd "$start_dir/$module"
        just push
        echo "✓ $module pushed successfully"
    done
    echo ""
    echo "✓ All modules pushed successfully!"

@build-and-publish-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Building $module..."
        echo "========================================"
        cd "$start_dir/$module"
        just build
        [[ " {{publishable}} " =~ " $module " ]] && just publish || true
        echo "✓ $module built and published successfully"
    done
    echo ""
    echo "✓ All modules built and published successfully!"

@rebuild-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Rebuilding $module..."
        echo "========================================"
        cd "$start_dir/$module"
        just rebuild
        echo "✓ $module rebuilt successfully"
    done
    echo ""
    echo "✓ All modules rebuilt successfully!"

@build-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
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
    echo "✓ All modules built successfully!"

@reinstall-workspace:
    #!/usr/bin/env bash
    set -euo pipefail
    start_dir="$(pwd)"
    trap 'cd "$start_dir"' EXIT
    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Reinstalling $module..."
        echo "========================================"
        rm -rf "$start_dir/$module"
        cd "$start_dir"
        git clone "git@github.com:sollecitom/$module.git"
        cd "$start_dir/$module"
        just build
        echo "✓ $module reinstalled successfully"
    done
    echo ""
    echo "✓ All modules reinstalled successfully!"
