#!/usr/bin/env bash
set -euo pipefail

command_name="${1:?missing command}"
modules="${2:-}"
publishable_modules="${3:-}"
start_dir="$(pwd)"
summary_file=""
workspace_events_file=""
base_image_policy_active=0
base_image_follow_latest=0
base_image_fallback_allowed=0
base_image_repository=""
base_image_variant=""
base_image_runtime_variant=""
base_image_current_param=""
base_image_current_runtime_param=""
base_image_candidate_param=""
base_image_candidate_runtime_param=""
base_image_candidate_tag=""
base_image_candidate_runtime_tag=""
base_image_fallback_param=""
base_image_fallback_runtime_param=""
base_image_fallback_tag=""
base_image_fallback_runtime_tag=""
base_image_latest_major=""
base_image_target_major=""
base_image_gradle_backup=""
base_image_dockerfile_backup=""
update_relevant_paths=(
    "gradle/libs.versions.toml"
    "gradle.properties"
    "gradle/wrapper/gradle-wrapper.properties"
    "container-versions.properties"
    "Dockerfile"
)

cleanup() {
    cd "$start_dir"
    if [ -n "$summary_file" ]; then
        rm -f "$summary_file"
    fi
    if [ -n "$workspace_events_file" ]; then
        rm -f "$workspace_events_file"
    fi
    if [ -n "$base_image_gradle_backup" ]; then
        rm -f "$base_image_gradle_backup"
    fi
    if [ -n "$base_image_dockerfile_backup" ]; then
        rm -f "$base_image_dockerfile_backup"
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

sanitize_gradle_output() {
    perl -pe '
        s/\e\][^\a]*(?:\a|\e\\\\)//g;
        s/\e\[[0-?]*[ -\/]*[@-~]//g;
    ' | tr -d '\000-\010\013\014\016-\037\177'
}

repo_head() {
    git rev-parse HEAD
}

repo_has_net_worktree_changes() {
    [ -n "$(git status --porcelain=v1 --untracked-files=normal)" ]
}

repo_has_update_relevant_changes() {
    [ -n "$(git status --porcelain=v1 --untracked-files=normal -- "${update_relevant_paths[@]}")" ]
}

update_build_reason() {
    local pre_pull_head="$1"
    local post_pull_head="$2"

    if [ "$pre_pull_head" != "$post_pull_head" ]; then
        printf '%s\n' "pulled commits changed HEAD"
        return 0
    fi

    if repo_has_update_relevant_changes; then
        printf '%s\n' "update-relevant files changed"
        return 0
    fi

    if repo_has_net_worktree_changes; then
        printf '%s\n' "other repo files changed"
        return 0
    fi

    return 1
}

clear_workspace_events() {
    if [ -n "$workspace_events_file" ]; then
        rm -f "$workspace_events_file"
    fi
}

append_workspace_event() {
    printf '%s\n' "$1" >> "$workspace_events_file"
}

reset_base_image_state() {
    base_image_policy_active=0
    base_image_follow_latest=0
    base_image_fallback_allowed=0
    base_image_repository=""
    base_image_variant=""
    base_image_runtime_variant=""
    base_image_current_param=""
    base_image_current_runtime_param=""
    base_image_candidate_param=""
    base_image_candidate_runtime_param=""
    base_image_candidate_tag=""
    base_image_candidate_runtime_tag=""
    base_image_fallback_param=""
    base_image_fallback_runtime_param=""
    base_image_fallback_tag=""
    base_image_fallback_runtime_tag=""
    base_image_latest_major=""
    base_image_target_major=""
    if [ -n "$base_image_gradle_backup" ]; then
        rm -f "$base_image_gradle_backup"
    fi
    if [ -n "$base_image_dockerfile_backup" ]; then
        rm -f "$base_image_dockerfile_backup"
    fi
    base_image_gradle_backup=""
    base_image_dockerfile_backup=""
}

ensure_workspace_requirements() {
    local mode="$1"
    bash "$start_dir/scripts/ensure-workspace-requirements.sh" "$mode"
}

property_value() {
    local file="$1"
    local key="$2"
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, "", $0); print $0; exit }' "$file"
}

set_property_value() {
    local file="$1"
    local key="$2"
    local value="$3"
    local tmp_file
    tmp_file=$(mktemp)

    awk -v key="$key" -v value="$value" '
        BEGIN { replaced = 0 }
        index($0, key "=") == 1 {
            print key "=" value
            replaced = 1
            next
        }
        { print }
        END {
            if (!replaced) {
                print key "=" value
            }
        }
    ' "$file" > "$tmp_file"

    mv "$tmp_file" "$file"
}

docker_hub_repository_path() {
    local repository="$1"
    if [[ "$repository" == */* ]]; then
        printf '%s\n' "$repository"
    else
        printf 'library/%s\n' "$repository"
    fi
}

fetch_matching_tags() {
    local repository="$1"
    local variant="$2"
    local repo_path
    local next_url

    repo_path=$(docker_hub_repository_path "$repository")
    next_url="https://hub.docker.com/v2/repositories/${repo_path}/tags?page_size=100"

    while [ -n "$next_url" ]; do
        local response
        response=$(curl -fsSL "$next_url")
        printf '%s' "$response" | jq -r --arg variant "$variant" '
            .results[]
            | .name
            | select(test("^[0-9]+-" + ($variant | gsub("\\."; "\\\\.")) + "$"))
        '
        next_url=$(printf '%s' "$response" | jq -r '.next // empty')
    done
}

resolve_latest_tag() {
    local repository="$1"
    local variant="$2"

    fetch_matching_tags "$repository" "$variant" \
        | awk -F- '{ print $1 " " $0 }' \
        | sort -nr \
        | awk 'NR == 1 { print $2 }'
}

resolve_tag_for_major() {
    local repository="$1"
    local variant="$2"
    local major="$3"

    fetch_matching_tags "$repository" "$variant" | awk -v expected="${major}-${variant}" '$0 == expected { print; exit }'
}

resolve_image_digest() {
    local image="$1"
    local target_architecture="amd64"
    local current_os
    local current_architecture

    current_os=$(uname -s)
    current_architecture=$(uname -m)

    if [ "$current_os" = "Darwin" ] && { [ "$current_architecture" = "arm64" ] || [ "$current_architecture" = "aarch64" ]; }; then
        target_architecture="arm64"
    fi

    docker buildx imagetools inspect "$image" --raw \
        | jq -r '
            .manifests[]
            | select(.platform.os == "linux" and .platform.architecture == "'"$target_architecture"'")
            | .digest
        ' \
        | awk 'NR == 1 { print; exit }'
}

resolve_image_reference() {
    local repository="$1"
    local tag="$2"
    local digest

    digest=$(resolve_image_digest "${repository}:${tag}")
    if [ -z "$digest" ]; then
        echo "Failed to resolve linux/amd64 digest for ${repository}:${tag}" >&2
        exit 1
    fi

    printf '%s:%s@%s\n' "$repository" "$tag" "$digest"
}

image_tag_from_ref() {
    local reference="$1"
    local without_digest

    without_digest="${reference%%@*}"
    if [ -z "$without_digest" ] || [[ "$without_digest" != *:* ]]; then
        return 0
    fi

    printf '%s\n' "${without_digest##*:}"
}

image_major_from_ref() {
    local tag
    tag=$(image_tag_from_ref "$1")
    if [ -n "$tag" ]; then
        printf '%s\n' "${tag%%-*}"
    fi
}

replace_from_line() {
    local dockerfile="$1"
    local line_number="$2"
    local image="$3"
    local tmp_file

    tmp_file=$(mktemp)
    awk -v line_number="$line_number" -v image="$image" '
        BEGIN { from_count = 0 }
        /^FROM / {
            from_count++
            if (from_count == line_number) {
                line = $0
                sub(/^FROM [^ ]+/, "FROM " image, line)
                print line
                next
            }
        }
        { print }
    ' "$dockerfile" > "$tmp_file"
    mv "$tmp_file" "$dockerfile"
}

update_dockerfile_base_images() {
    local builder_image="$1"
    local runtime_image="$2"

    [ -f Dockerfile ] || return 0
    replace_from_line Dockerfile 1 "$builder_image"
    if [ -n "$runtime_image" ]; then
        replace_from_line Dockerfile 2 "$runtime_image"
    fi
}

prepare_base_image_policy() {
    local current_major
    local configured_major
    local latest_tag
    local target_tag
    local runtime_target_tag

    reset_base_image_state
    workspace_events_file="$(pwd)/.update-workspace-events"
    clear_workspace_events

    [ -f gradle.properties ] || return 0

    base_image_repository=$(property_value gradle.properties dockerBaseImageRepository)
    base_image_variant=$(property_value gradle.properties dockerBaseImageVariant)
    configured_major=$(property_value gradle.properties dockerBaseImageMajor)
    base_image_runtime_variant=$(property_value gradle.properties dockerRuntimeBaseImageVariant)

    if [ -z "$base_image_repository" ] || [ -z "$base_image_variant" ] || [ -z "$configured_major" ]; then
        return 0
    fi

    base_image_policy_active=1
    base_image_current_param=$(property_value gradle.properties dockerBaseImageParam)
    base_image_current_runtime_param=$(property_value gradle.properties dockerRuntimeBaseImageParam)
    current_major=$(image_major_from_ref "$base_image_current_param")

    base_image_gradle_backup=$(mktemp)
    cp gradle.properties "$base_image_gradle_backup"

    if [ -f Dockerfile ]; then
        base_image_dockerfile_backup=$(mktemp)
        cp Dockerfile "$base_image_dockerfile_backup"
    fi

    latest_tag=$(resolve_latest_tag "$base_image_repository" "$base_image_variant")
    if [ -z "$latest_tag" ]; then
        echo "Failed to resolve a matching base image tag for ${base_image_repository} (${base_image_variant})" >&2
        exit 1
    fi

    base_image_latest_major="${latest_tag%%-*}"

    if [ "$configured_major" = "latest" ]; then
        base_image_follow_latest=1
        base_image_target_major="$base_image_latest_major"
        target_tag="$latest_tag"
    else
        base_image_target_major="$configured_major"
        target_tag=$(resolve_tag_for_major "$base_image_repository" "$base_image_variant" "$base_image_target_major")
        if [ -z "$target_tag" ]; then
            echo "Failed to resolve ${base_image_repository}:${base_image_target_major}-${base_image_variant}" >&2
            exit 1
        fi
        if [ -n "$base_image_latest_major" ] && [ "$base_image_latest_major" -gt "$base_image_target_major" ]; then
            append_workspace_event "Java image pinned: staying on major ${base_image_target_major} while ${base_image_latest_major} is available."
        fi
    fi

    base_image_candidate_tag="$target_tag"
    base_image_candidate_param=$(resolve_image_reference "$base_image_repository" "$target_tag")
    set_property_value gradle.properties dockerBaseImageParam "$base_image_candidate_param"

    if [ -n "$base_image_runtime_variant" ]; then
        runtime_target_tag=$(resolve_tag_for_major "$base_image_repository" "$base_image_runtime_variant" "$base_image_target_major")
        if [ -z "$runtime_target_tag" ]; then
            echo "Failed to resolve ${base_image_repository}:${base_image_target_major}-${base_image_runtime_variant}" >&2
            exit 1
        fi
        base_image_candidate_runtime_tag="$runtime_target_tag"
        base_image_candidate_runtime_param=$(resolve_image_reference "$base_image_repository" "$runtime_target_tag")
        set_property_value gradle.properties dockerRuntimeBaseImageParam "$base_image_candidate_runtime_param"
        update_dockerfile_base_images "$base_image_candidate_param" "$base_image_candidate_runtime_param"
    fi

    if [ "$base_image_follow_latest" -eq 1 ] && [ -n "$current_major" ] && [ "$base_image_target_major" -gt "$current_major" ]; then
        local fallback_tag
        base_image_fallback_allowed=1
        fallback_tag=$(resolve_tag_for_major "$base_image_repository" "$base_image_variant" "$current_major")
        if [ -z "$fallback_tag" ]; then
            echo "Failed to resolve fallback image ${base_image_repository}:${current_major}-${base_image_variant}" >&2
            exit 1
        fi
        base_image_fallback_tag="$fallback_tag"
        base_image_fallback_param=$(resolve_image_reference "$base_image_repository" "$fallback_tag")

        if [ -n "$base_image_runtime_variant" ]; then
            local fallback_runtime_tag
            fallback_runtime_tag=$(resolve_tag_for_major "$base_image_repository" "$base_image_runtime_variant" "$current_major")
            if [ -z "$fallback_runtime_tag" ]; then
                echo "Failed to resolve fallback image ${base_image_repository}:${current_major}-${base_image_runtime_variant}" >&2
                exit 1
            fi
            base_image_fallback_runtime_tag="$fallback_runtime_tag"
            base_image_fallback_runtime_param=$(resolve_image_reference "$base_image_repository" "$fallback_runtime_tag")
        fi
    fi
}

restore_base_image_files() {
    if [ -n "$base_image_gradle_backup" ] && [ -f "$base_image_gradle_backup" ]; then
        cp "$base_image_gradle_backup" gradle.properties
    fi
    if [ -n "$base_image_dockerfile_backup" ] && [ -f "$base_image_dockerfile_backup" ]; then
        cp "$base_image_dockerfile_backup" Dockerfile
    fi
}

apply_base_image_fallback() {
    [ "$base_image_fallback_allowed" -eq 1 ] || return 1

    set_property_value gradle.properties dockerBaseImageParam "$base_image_fallback_param"
    if [ -n "$base_image_fallback_runtime_param" ]; then
        set_property_value gradle.properties dockerRuntimeBaseImageParam "$base_image_fallback_runtime_param"
        update_dockerfile_base_images "$base_image_fallback_param" "$base_image_fallback_runtime_param"
    fi

    append_workspace_event "Java image fallback: ${base_image_candidate_tag} failed build; kept ${base_image_fallback_tag}."
}

collect_module_summary() {
    if [ -x ./gradlew ]; then
        WORKSPACE_UPDATE_EVENTS_FILE="$workspace_events_file" ./gradlew -q updateSummary 2>/dev/null | sanitize_gradle_output || true
    fi
}

case "$command_name" in
    update)
        ensure_workspace_requirements update
        summary_file=$(mktemp)
        for module in $modules; do
            local_pre_pull_head=""
            local_post_pull_head=""
            build_reason=""
            print_header "Updating" "$module"
            cd_module "$module"
            git add -A && (git diff --quiet HEAD || git commit -am "WIP") || true
            local_pre_pull_head=$(repo_head)
            just pull
            local_post_pull_head=$(repo_head)
            prepare_base_image_policy
            just update-all
            if build_reason=$(update_build_reason "$local_pre_pull_head" "$local_post_pull_head"); then
                echo "Running standalone build for $module; $build_reason."
                if just build; then
                    :
                elif apply_base_image_fallback; then
                    just build
                else
                    restore_base_image_files
                    exit 1
                fi
            else
                echo "Skipping standalone build for $module; no pulled commits or repo changes."
            fi
            module_summary=$(collect_module_summary)
            if printf '%s\n' "$module_summary" | grep -q '[^[:space:]]'; then
                echo "$module" >> "$summary_file"
                while IFS= read -r line; do
                    [ -n "$line" ] || continue
                    printf '  %s\n' "$line" >> "$summary_file"
                done <<< "$module_summary"
            else
                echo "$module: No dependencies were updated." >> "$summary_file"
            fi
            clear_workspace_events
            reset_base_image_state
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
        if [ "$command_name" = "build" ]; then
            summary_file=$(mktemp)
        fi
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
                    module_summary=$(collect_module_summary)
                    if printf '%s\n' "$module_summary" | grep -q '[^[:space:]]'; then
                        echo "$module" >> "$summary_file"
                        while IFS= read -r line; do
                            [ -n "$line" ] || continue
                            printf '  %s\n' "$line" >> "$summary_file"
                        done <<< "$module_summary"
                    fi
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
            build)
                echo "╔══════════════════════════════════════════════════════════════════════════════"
                echo "║ BUILD SUMMARY"
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
                    echo "║  No build-triggered dependency changes detected."
                    echo "║"
                fi
                echo "╚══════════════════════════════════════════════════════════════════════════════"
                echo ""
                echo "✓ All modules built successfully!"
                ;;
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
    install)
        ensure_workspace_requirements install
        for module in $modules; do
            if [ -d "$start_dir/$module/.git" ]; then
                print_header "Skipping clone for" "$module"
                echo "✓ $module already exists"
                continue
            fi

            print_header "Cloning" "$module"
            cd "$start_dir"
            git clone "git@github.com:sollecitom/$module.git"
            echo "✓ $module cloned"
        done

        bash "$start_dir/scripts/workspace.sh" build "workspace $modules"

        echo ""
        echo "✓ All modules installed successfully!"
        ;;
    reinstall)
        for module in $modules; do
            if [ -d "$start_dir/$module" ]; then
                print_header "Removing" "$module"
                rm -rf "$start_dir/$module"
                echo "✓ $module removed"
            fi
        done

        bash "$start_dir/scripts/workspace.sh" install "$modules"

        echo ""
        echo "✓ All modules reinstalled successfully!"
        ;;
    *)
        echo "Unknown command: $command_name" >&2
        exit 1
        ;;
esac
