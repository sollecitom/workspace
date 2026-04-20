#!/usr/bin/env bash
set -euo pipefail

command_name="${1:?missing command}"
modules="${2:-}"
publishable_modules="${3:-}"
start_dir="$(pwd)"
summary_file=""
workspace_events_file=""
max_parallel_consumers="${WORKSPACE_MAX_PARALLEL_CONSUMERS:-2}"
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

run_cleanup_pass() {
    local modules_to_clean="$1"

    for module in $modules_to_clean; do
        run_module_cleanup "$module"
    done
}

commit_wip_if_needed() {
    git add -A && (git diff --quiet HEAD || git commit -am "WIP") || true
}

append_module_summary() {
    local target_file="$1"
    local module="$2"
    local module_summary="$3"
    local empty_message="$4"

    if printf '%s\n' "$module_summary" | grep -q '[^[:space:]]'; then
        echo "$module" >> "$target_file"
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            printf '  %s\n' "$line" >> "$target_file"
        done <<< "$module_summary"
    else
        echo "$module: $empty_message" >> "$target_file"
    fi
}

print_summary_box() {
    local title="$1"
    local empty_message="$2"

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════"
    echo "║ $title"
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
        echo "║  $empty_message"
        echo "║"
    fi
    echo "╚══════════════════════════════════════════════════════════════════════════════"
    echo ""
}

module_is_publishable() {
    [[ " $publishable_modules " =~ " $1 " ]]
}

reset_summary_file() {
    if [ -n "$summary_file" ] && [ -f "$summary_file" ]; then
        rm -f "$summary_file"
    fi
    summary_file=$(mktemp)
}

run_module_pull() {
    local module="$1"
    print_header "Pulling" "$module"
    cd_module "$module"
    commit_wip_if_needed
    just pull
    echo "✓ $module pulled successfully"
}

run_module_update() {
    local module="$1"
    local keep_state="${2:-0}"

    print_header "Updating" "$module"
    cd_module "$module"
    prepare_base_image_policy
    WORKSPACE_UPDATE_EVENTS_FILE="$workspace_events_file" just update-all
    if [ -n "$summary_file" ]; then
        module_summary=$(collect_module_summary)
        append_module_summary "$summary_file" "$module" "$module_summary" "No dependencies were updated."
    fi
    if [ "$keep_state" -eq 0 ]; then
        clear_workspace_events
        reset_base_image_state
    fi
    echo "✓ $module updated successfully"
}

run_module_update_internal() {
    local module="$1"

    print_header "Updating internal dependencies for" "$module"
    cd_module "$module"
    WORKSPACE_UPDATE_EVENTS_FILE="$workspace_events_file" just update-internal-dependencies
    if [ -n "$summary_file" ]; then
        module_summary=$(collect_module_summary)
        append_module_summary "$summary_file" "$module" "$module_summary" "No internal dependency updates were applied."
    fi
    echo "✓ $module internal dependencies updated successfully"
}

run_module_build() {
    local module="$1"
    local keep_state="${2:-0}"

    print_header "Building" "$module"
    cd_module "$module"
    if just build; then
        :
    elif apply_base_image_fallback; then
        just build
    else
        restore_base_image_files
        exit 1
    fi
    if [ -n "$summary_file" ]; then
        module_summary=$(collect_module_summary)
        append_module_summary "$summary_file" "$module" "$module_summary" "No build-triggered dependency changes detected."
    fi
    if [ "$keep_state" -eq 0 ]; then
        clear_workspace_events
        reset_base_image_state
    fi
    echo "✓ $module built successfully"
}

run_module_rebuild() {
    local module="$1"
    print_header "Rebuilding" "$module"
    cd_module "$module"
    just rebuild
    echo "✓ $module rebuilt successfully"
}

run_module_publish() {
    local module="$1"
    print_header "Publishing" "$module"
    cd_module "$module"
    if just --summary 2>/dev/null | tr ' ' '\n' | grep -Fxq publish; then
        just publish
        echo "✓ $module published successfully"
    else
        echo "Skipping publish for $module; no publish recipe."
    fi
}

run_module_push() {
    local module="$1"
    print_header "Pushing" "$module"
    cd_module "$module"
    just push
    echo "✓ $module pushed successfully"
}

run_module_cleanup() {
    local module="$1"
    print_header "Cleaning" "$module"
    cd_module "$module"
    just cleanup
    echo "✓ $module cleaned successfully"
}

consumer_modules_from_list() {
    local consumer_modules=""
    local module

    for module in $modules; do
        if [ "$module" = "workspace" ]; then
            continue
        fi
        if ! module_is_publishable "$module"; then
            consumer_modules="${consumer_modules} ${module}"
        fi
    done

    printf '%s\n' "$consumer_modules"
}

consumer_modules_supporting_recipe() {
    local recipe="$1"
    local consumer_modules=""
    local module

    for module in $modules; do
        if [ "$module" = "workspace" ]; then
            continue
        fi
        if module_is_publishable "$module"; then
            continue
        fi
        cd_module "$module"
        if just --summary 2>/dev/null | tr ' ' '\n' | grep -Fxq "$recipe"; then
            consumer_modules="${consumer_modules} ${module}"
        fi
    done

    cd "$start_dir"

    printf '%s\n' "$consumer_modules"
}

wait_for_parallel_slot() {
    while [ "$(jobs -pr | wc -l | tr -d ' ')" -ge "$max_parallel_consumers" ]; do
        sleep 0.2
    done
}

run_parallel_consumer_builds() {
    local consumer_modules="$1"
    local results_dir
    local failure=0
    local module

    [ -n "${consumer_modules// }" ] || return 0

    results_dir=$(mktemp -d)
    echo "Running independent consumer builds in parallel (max ${max_parallel_consumers})..."

    for module in $consumer_modules; do
        wait_for_parallel_slot
        (
            cd_module "$module"
            if just build >"$results_dir/${module}.log" 2>&1; then
                collect_module_summary >"$results_dir/${module}.summary" || true
                printf '0' > "$results_dir/${module}.exit"
            else
                printf '%s' "$?" > "$results_dir/${module}.exit"
            fi
        ) &
    done

    wait || true

    for module in $consumer_modules; do
        module_exit="$(cat "$results_dir/${module}.exit" 2>/dev/null || printf '1')"
        if [ "$module_exit" -ne 0 ]; then
            print_header "Build failed for" "$module"
            cat "$results_dir/${module}.log"
            failure=1
            continue
        fi

        if [ -n "$summary_file" ]; then
            module_summary="$(cat "$results_dir/${module}.summary" 2>/dev/null || true)"
            append_module_summary "$summary_file" "$module" "$module_summary" "No build-triggered dependency changes detected."
        fi
        echo "✓ $module built successfully"
    done

    rm -rf "$results_dir"

    if [ "$failure" -ne 0 ]; then
        exit 1
    fi
}

run_parallel_consumer_rebuilds() {
    local consumer_modules="$1"
    local results_dir
    local failure=0
    local module

    [ -n "${consumer_modules// }" ] || return 0

    results_dir=$(mktemp -d)
    echo "Running independent consumer rebuilds in parallel (max ${max_parallel_consumers})..."

    for module in $consumer_modules; do
        wait_for_parallel_slot
        (
            cd_module "$module"
            if just rebuild >"$results_dir/${module}.log" 2>&1; then
                printf '0' > "$results_dir/${module}.exit"
            else
                printf '%s' "$?" > "$results_dir/${module}.exit"
            fi
        ) &
    done

    wait || true

    for module in $consumer_modules; do
        module_exit="$(cat "$results_dir/${module}.exit" 2>/dev/null || printf '1')"
        if [ "$module_exit" -ne 0 ]; then
            print_header "Rebuild failed for" "$module"
            cat "$results_dir/${module}.log"
            failure=1
            continue
        fi

        echo "✓ $module rebuilt successfully"
    done

    rm -rf "$results_dir"

    if [ "$failure" -ne 0 ]; then
        exit 1
    fi
}

run_parallel_consumer_modules() {
    local consumer_modules="$1"
    local module_function="$2"
    local phase_name="$3"
    local success_verb="$4"
    local phase_label
    local results_dir
    local failure=0
    local module

    [ -n "${consumer_modules// }" ] || return 0

    phase_label=$(printf '%s' "$phase_name" | tr '[:upper:]' '[:lower:]')
    results_dir=$(mktemp -d)
    echo "Running independent consumer ${phase_label} in parallel (max ${max_parallel_consumers})..."

    for module in $consumer_modules; do
        wait_for_parallel_slot
        (
            if "$module_function" "$module" >"$results_dir/${module}.log" 2>&1; then
                printf '0' > "$results_dir/${module}.exit"
            else
                printf '%s' "$?" > "$results_dir/${module}.exit"
            fi
        ) &
    done

    wait || true

    for module in $consumer_modules; do
        module_exit="$(cat "$results_dir/${module}.exit" 2>/dev/null || printf '1')"
        if [ "$module_exit" -ne 0 ]; then
            print_header "${phase_name} failed for" "$module"
            cat "$results_dir/${module}.log"
            failure=1
            continue
        fi

        echo "✓ $module ${success_verb} successfully"
    done

    rm -rf "$results_dir"

    if [ "$failure" -ne 0 ]; then
        exit 1
    fi
}

run_step_pull() {
    local module
    local consumer_modules

    for module in $modules; do
        if [ "$module" = "workspace" ] || module_is_publishable "$module"; then
            run_module_pull "$module"
        fi
    done

    consumer_modules="$(consumer_modules_from_list)"
    run_parallel_consumer_modules "$consumer_modules" run_module_pull "Pull" "pulled"

    echo ""
    echo "✓ All modules pulled successfully!"
}

run_step_update() {
    local module
    reset_summary_file
    for module in $modules; do
        run_module_update "$module"
    done
    print_summary_box "UPDATE SUMMARY" "No upgrade-related changes detected."
    echo "✓ All modules updated successfully!"
}

run_step_update_internal() {
    local module

    reset_summary_file
    for module in $modules; do
        run_module_update_internal "$module"
    done
    print_summary_box "INTERNAL UPDATE SUMMARY" "No internal dependency changes detected."
    echo "✓ All modules updated internal dependencies successfully!"
}

run_step_build() {
    local module
    local consumer_modules

    reset_summary_file

    for module in $modules; do
        if [ "$module" = "workspace" ] || module_is_publishable "$module"; then
            run_module_build "$module"
        fi
    done

    consumer_modules="$(consumer_modules_from_list)"
    run_parallel_consumer_builds "$consumer_modules"

    print_summary_box "BUILD SUMMARY" "No build-triggered dependency changes detected."
    echo "✓ All modules built successfully!"
}

run_step_rebuild() {
    local module
    local consumer_modules

    for module in $modules; do
        if [ "$module" = "workspace" ] || module_is_publishable "$module"; then
            run_module_rebuild "$module"
        fi
    done

    consumer_modules="$(consumer_modules_from_list)"
    run_parallel_consumer_rebuilds "$consumer_modules"

    echo "✓ All modules rebuilt successfully!"
}

run_step_publish() {
    local module
    local consumer_modules

    for module in $modules; do
        if [ "$module" = "workspace" ] || module_is_publishable "$module"; then
            run_module_publish "$module"
        fi
    done

    consumer_modules="$(consumer_modules_supporting_recipe publish)"
    run_parallel_consumer_modules "$consumer_modules" run_module_publish "Publish" "published"

    echo ""
    echo "✓ All module publish steps completed successfully!"
}

run_step_cleanup() {
    local module
    local cleanup_modules

    for module in $modules; do
        if [ "$module" = "workspace" ] || module_is_publishable "$module"; then
            run_module_cleanup "$module"
        fi
    done

    cleanup_modules="$(consumer_modules_from_list)"
    run_parallel_consumer_modules "$cleanup_modules" run_module_cleanup "Cleanup" "cleaned"

    echo ""
    echo "✓ All modules cleaned successfully!"
}

run_step_push() {
    local module
    for module in $modules; do
        run_module_push "$module"
    done
    echo ""
    echo "✓ All modules pushed successfully!"
}

execute_requires_workspace_requirements() {
    local step
    for step in "$@"; do
        case "$step" in
            pull|update|update-internal|build|publish|rebuild|reset)
                return 0
                ;;
        esac
    done
    return 1
}

run_execute_pipeline() {
    shift 3
    local steps=("$@")
    local step

    if execute_requires_workspace_requirements "${steps[@]}"; then
        ensure_workspace_requirements update
    fi

    for step in "${steps[@]}"; do
        case "$step" in
            pull)
                run_step_pull
                ;;
            update)
                run_step_update
                ;;
            update-internal)
                run_step_update_internal
                ;;
            build)
                run_step_build
                ;;
            rebuild)
                run_step_rebuild
                ;;
            publish)
                run_step_publish
                ;;
            push)
                run_step_push
                ;;
            cleanup)
                run_step_cleanup
                ;;
            *)
                echo "Unsupported workspace pipeline step: $step" >&2
                exit 1
                ;;
        esac
    done
}

case "$command_name" in
    update)
        ensure_workspace_requirements update
        run_step_update
        ;;
    update-internal)
        ensure_workspace_requirements update
        run_step_update_internal
        ;;
    pull|reset|push|rebuild|build|cleanup|publish)
        if [ "$command_name" = "cleanup" ]; then
            run_step_cleanup
            exit 0
        fi
        if [ "$command_name" = "pull" ]; then
            run_step_pull
            exit 0
        fi
        if [ "$command_name" = "build" ]; then
            run_step_build
            exit 0
        fi
        if [ "$command_name" = "rebuild" ]; then
            run_step_rebuild
            exit 0
        fi
        if [ "$command_name" = "publish" ]; then
            run_step_publish
            exit 0
        fi
        if [ "$command_name" = "push" ]; then
            run_step_push
            exit 0
        fi
        for module in $modules; do
            case "$command_name" in
                reset) print_header "Resetting" "$module" ;;
            esac
            cd_module "$module"
            case "$command_name" in
                reset)
                    git clean -fdx && git reset --hard
                    just build
                    ;;
            esac
            echo "✓ $module ${command_name}ed successfully"
        done
        echo ""
        case "$command_name" in
            reset) echo "✓ All modules reset successfully!" ;;
        esac
        ;;
    execute)
        run_execute_pipeline "$@"
        echo ""
        echo "✓ Workspace pipeline completed successfully!"
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
