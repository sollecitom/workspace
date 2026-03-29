#!/usr/bin/env just --justfile

# Project modules (order matters: dependencies first)
# gradle-plugins is no longer published during build — consumers use includeBuild
publishable := "acme-schema-catalogue swissknife pillar"
non_publishable := "gradle-plugins tools examples facts backend-skeleton modulith-example element-service-example"
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
    for module in {{all_modules}}; do
        echo ""
        echo "========================================"
        echo "Updating $module..."
        echo "========================================"
        cd "$start_dir/$module"
        git add -A && (git diff --quiet HEAD || git commit -am "WIP") || true
        just pull
        just update-all
        just build
        [[ " {{publishable}} " =~ " $module " ]] && just publish || true
        echo "✓ $module updated successfully"
    done
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
        [[ " {{publishable}} " =~ " $module " ]] && just publish || true
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
        [[ " {{publishable}} " =~ " $module " ]] && just publish || true
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
        [[ " {{publishable}} " =~ " $module " ]] && just publish || true
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
        [[ " {{publishable}} " =~ " $module " ]] && just publish || true
        echo "✓ $module reinstalled successfully"
    done
    echo ""
    echo "✓ All modules reinstalled successfully!"
