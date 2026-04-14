#!/usr/bin/env bash
set -euo pipefail

command_name="${1:?missing command}"
modules="${2:-}"
publishable_modules="${3:-}"
start_dir="$(pwd)"
summary_file=""

cleanup() {
    cd "$start_dir"
    if [ -n "$summary_file" ]; then
        rm -f "$summary_file"
    fi
}

trap cleanup EXIT

cd_module() {
    local module="$1"
    if [ "$module" = "workspace" ]; then
        cd "$start_dir"
    else
        cd "$start_dir/$module"
    fi
}

print_header() {
    local action="$1"
    local module="$2"
    echo ""
    echo "========================================"
    echo "$action $module..."
    echo "========================================"
}

case "$command_name" in
    update)
        summary_file=$(mktemp)
        for module in $modules; do
            print_header "Updating" "$module"
            cd_module "$module"
            git add -A && (git diff --quiet HEAD || git commit -am "WIP") || true
            just pull
            just update-all
            just build
            module_summary=$(./gradlew -q updateSummary 2>/dev/null || true)
            if printf '%s\n' "$module_summary" | grep -q '[^[:space:]]'; then
                echo "$module" >> "$summary_file"
                while IFS= read -r line; do
                    [ -n "$line" ] || continue
                    printf '  %s\n' "$line" >> "$summary_file"
                done <<< "$module_summary"
            else
                echo "$module: No dependencies were updated." >> "$summary_file"
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
        ;;
    pull|reset|push|rebuild|build)
        for module in $modules; do
            case "$command_name" in
                pull) print_header "Pulling" "$module" ;;
                reset) print_header "Resetting" "$module" ;;
                push) print_header "Pushing" "$module" ;;
                rebuild) print_header "Rebuilding" "$module" ;;
                build) print_header "Building" "$module" ;;
            esac
            cd_module "$module"
            case "$command_name" in
                pull)
                    git add -A && (git diff --quiet HEAD || git commit -am "WIP") || true
                    just pull
                    just build
                    ;;
                reset)
                    git clean -fdx && git reset --hard
                    just build
                    ;;
                push)
                    just push
                    ;;
                rebuild)
                    just rebuild
                    ;;
                build)
                    just build
                    ;;
            esac
            echo "✓ $module ${command_name}ed successfully"
        done
        echo ""
        case "$command_name" in
            pull) echo "✓ All modules pulled successfully!" ;;
            reset) echo "✓ All modules reset successfully!" ;;
            push) echo "✓ All modules pushed successfully!" ;;
            rebuild) echo "✓ All modules rebuilt successfully!" ;;
            build) echo "✓ All modules built successfully!" ;;
        esac
        ;;
    build-and-publish)
        for module in $modules; do
            print_header "Building" "$module"
            cd_module "$module"
            just build
            [[ " $publishable_modules " =~ " $module " ]] && just publish || true
            echo "✓ $module built and published successfully"
        done
        echo ""
        echo "✓ All modules built and published successfully!"
        ;;
    reinstall)
        print_header "Building" "workspace"
        cd "$start_dir"
        just build
        echo "✓ workspace built successfully"

        for module in $modules; do
            print_header "Cloning" "$module"
            rm -rf "$start_dir/$module"
            cd "$start_dir"
            git clone "git@github.com:sollecitom/$module.git"
            echo "✓ $module cloned"
        done

        for module in $modules; do
            print_header "Building" "$module"
            cd "$start_dir/$module"
            just build
            echo "✓ $module built successfully"
        done

        echo ""
        echo "✓ All modules reinstalled successfully!"
        ;;
    *)
        echo "Unknown command: $command_name" >&2
        exit 1
        ;;
esac
