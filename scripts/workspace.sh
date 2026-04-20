#!/usr/bin/env bash
set -euo pipefail

command_name="${1:?missing command}"
modules="${2:-}"
publishable_modules="${3:-}"
start_dir="$(pwd)"
summary_file=""
pipeline_update_summary_file=""
pipeline_internal_update_summary_file=""
workspace_events_file=""
pipeline_state_dir="$start_dir/.workspace-run-state"
pipeline_state_file=""
pipeline_state_schema_version="1"
pipeline_flow_name=""
pipeline_started_at=""
pipeline_steps_signature=""
pipeline_modules_signature=""
completed_repos_csv=""
pipeline_runner_pid="$$"
pipeline_runner_command=""
pipeline_is_resuming=0
pipeline_update_summary_state_file=""
pipeline_internal_update_summary_state_file=""
resume_ttl_seconds=3600
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
base_image_update_skip_reason=""

cleanup() {
    cd "$start_dir"
    if [ -n "$summary_file" ] \
        && [ "$summary_file" != "${pipeline_update_summary_state_file:-}" ] \
        && [ "$summary_file" != "${pipeline_internal_update_summary_state_file:-}" ]; then
        rm -f "$summary_file"
    fi
    if [ -n "$pipeline_update_summary_file" ] \
        && [ "$pipeline_update_summary_file" != "${pipeline_update_summary_state_file:-}" ]; then
        rm -f "$pipeline_update_summary_file"
    fi
    if [ -n "$pipeline_internal_update_summary_file" ] \
        && [ "$pipeline_internal_update_summary_file" != "${pipeline_internal_update_summary_state_file:-}" ]; then
        rm -f "$pipeline_internal_update_summary_file"
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

display_workspace_path() {
    local path="$1"

    case "$path" in
        "$start_dir"/*)
            printf './%s\n' "${path#"$start_dir"/}"
            ;;
        *)
            printf '%s\n' "$path"
            ;;
    esac
}

print_resume_hint_on_failure() {
    local exit_code="$1"

    if [ "$command_name" = "execute" ] && [ "$exit_code" -ne 0 ] && [ -n "$pipeline_state_file" ] && [ -f "$pipeline_state_file" ]; then
        echo ""
        echo "Workspace pipeline failed."
        echo "Run the same command again to resume ${pipeline_flow_name:-the unfinished flow}."
        echo "Resume state kept at $(display_workspace_path "$pipeline_state_file")."
    fi
}

on_exit() {
    local exit_code="$?"
    print_resume_hint_on_failure "$exit_code"
    cleanup
    exit "$exit_code"
}

trap on_exit EXIT

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
    base_image_update_skip_reason=""
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

# Resumability is scoped to a named workspace flow (or to an `execute` step
# signature when no explicit flow name is supplied). A repo is considered
# complete only after all requested steps for that repo have succeeded.
sanitize_flow_name() {
    printf '%s' "$1" | tr '[:space:]/:' '-' | tr -cd '[:alnum:]-_.'
}

count_modules() {
    local count=0
    local module_name

    for module_name in $modules; do
        count=$((count + 1))
    done

    printf '%s\n' "$count"
}

count_completed_repos() {
    if [ -z "$completed_repos_csv" ]; then
        printf '0\n'
        return 0
    fi

    awk -F',' 'NF { print NF }' <<< "$completed_repos_csv"
}

process_command_for_pid() {
    local pid="${1:-}"
    ps -p "$pid" -o command= 2>/dev/null || true
}

pipeline_runner_pid_is_active() {
    local pid="${1:-}"
    local expected_command="${2:-}"
    local actual_command

    [ -n "$pid" ] || return 1
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1

    if [ "$pid" = "$pipeline_runner_pid" ]; then
        return 0
    fi

    kill -0 "$pid" >/dev/null 2>&1 || return 1

    if [ -z "$expected_command" ]; then
        return 0
    fi

    actual_command="$(process_command_for_pid "$pid")"
    [ -n "$actual_command" ] || return 1
    [ "$actual_command" = "$expected_command" ]
}

pipeline_repo_is_completed() {
    local repo="$1"
    case ",$completed_repos_csv," in
        *,"$repo",*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

mark_pipeline_repo_completed() {
    local repo="$1"
    if pipeline_repo_is_completed "$repo"; then
        return 0
    fi

    if [ -n "$completed_repos_csv" ]; then
        completed_repos_csv="${completed_repos_csv},${repo}"
    else
        completed_repos_csv="$repo"
    fi
}

write_pipeline_state() {
    local status="$1"
    local current_repo="${2:-}"
    local current_step="${3:-}"
    local now
    local temp_state_file

    [ -n "$pipeline_state_file" ] || return 0

    now=$(date +%s)
    mkdir -p "$pipeline_state_dir"
    temp_state_file=$(mktemp "${pipeline_state_file}.tmp.XXXXXX")

    {
        printf 'STATE_FLOW_NAME=%q\n' "$pipeline_flow_name"
        printf 'STATE_SCHEMA_VERSION=%q\n' "$pipeline_state_schema_version"
        printf 'STATE_MODULES_SIGNATURE=%q\n' "$pipeline_modules_signature"
        printf 'STATE_STEPS_SIGNATURE=%q\n' "$pipeline_steps_signature"
        printf 'STATE_STATUS=%q\n' "$status"
        printf 'STATE_STARTED_AT=%q\n' "$pipeline_started_at"
        printf 'STATE_UPDATED_AT=%q\n' "$now"
        printf 'STATE_RUNNER_PID=%q\n' "$pipeline_runner_pid"
        printf 'STATE_RUNNER_COMMAND=%q\n' "$pipeline_runner_command"
        printf 'STATE_CURRENT_REPO=%q\n' "$current_repo"
        printf 'STATE_CURRENT_STEP=%q\n' "$current_step"
        printf 'STATE_COMPLETED_REPOS=%q\n' "$completed_repos_csv"
    } > "$temp_state_file"

    mv "$temp_state_file" "$pipeline_state_file"
}

remove_pipeline_state() {
    if [ -n "$pipeline_state_file" ]; then
        rm -f "$pipeline_state_file"
    fi
    if [ -n "$pipeline_update_summary_state_file" ]; then
        rm -f "$pipeline_update_summary_state_file"
    fi
    if [ -n "$pipeline_internal_update_summary_state_file" ]; then
        rm -f "$pipeline_internal_update_summary_state_file"
    fi
    pipeline_state_file=""
    pipeline_flow_name=""
    pipeline_started_at=""
    pipeline_steps_signature=""
    pipeline_modules_signature=""
    completed_repos_csv=""
    pipeline_is_resuming=0
    pipeline_update_summary_state_file=""
    pipeline_internal_update_summary_state_file=""
}

prepare_pipeline_state() {
    local steps=("$@")
    local configured_flow_name="${WORKSPACE_FLOW_NAME:-}"
    local now
    local state_age
    local total_modules
    local completed_modules
    local remaining_modules

    pipeline_steps_signature="${steps[*]}"
    pipeline_modules_signature="$modules"
    pipeline_is_resuming=0
    pipeline_runner_command="$(process_command_for_pid "$pipeline_runner_pid")"
    if [ -z "$pipeline_runner_command" ]; then
        pipeline_runner_command="scripts/workspace.sh ${command_name}"
    fi

    if [ -n "$configured_flow_name" ]; then
        pipeline_flow_name="$configured_flow_name"
    else
        pipeline_flow_name="$(sanitize_flow_name "execute-${pipeline_steps_signature}")"
    fi

    pipeline_state_file="${pipeline_state_dir}/${pipeline_flow_name}.state"
    pipeline_update_summary_state_file="${pipeline_state_dir}/${pipeline_flow_name}.update-summary"
    pipeline_internal_update_summary_state_file="${pipeline_state_dir}/${pipeline_flow_name}.internal-update-summary"
    completed_repos_csv=""

    if [ -f "$pipeline_state_file" ]; then
        STATE_FLOW_NAME=""
        STATE_SCHEMA_VERSION=""
        STATE_MODULES_SIGNATURE=""
        STATE_STEPS_SIGNATURE=""
        STATE_STATUS=""
        STATE_STARTED_AT=""
        STATE_UPDATED_AT=""
        STATE_RUNNER_PID=""
        STATE_RUNNER_COMMAND=""
        STATE_CURRENT_REPO=""
        STATE_CURRENT_STEP=""
        STATE_COMPLETED_REPOS=""
        # shellcheck disable=SC1090
        . "$pipeline_state_file"

        now=$(date +%s)
        state_age=$(( now - ${STATE_UPDATED_AT:-0} ))

        if [ "${STATE_SCHEMA_VERSION:-}" != "$pipeline_state_schema_version" ]; then
            echo "Discarding incompatible workspace run state for ${pipeline_flow_name} (schema version changed)."
            rm -f "$pipeline_state_file"
            rm -f "$pipeline_update_summary_state_file" "$pipeline_internal_update_summary_state_file"
        elif [ "${STATE_FLOW_NAME:-}" = "$pipeline_flow_name" ] \
            && [ "${STATE_MODULES_SIGNATURE:-}" = "$pipeline_modules_signature" ] \
            && [ "${STATE_STEPS_SIGNATURE:-}" = "$pipeline_steps_signature" ] \
            && [ "${STATE_STATUS:-}" = "running" ] \
            && pipeline_runner_pid_is_active "${STATE_RUNNER_PID:-}" "${STATE_RUNNER_COMMAND:-}"; then
            echo "Another ${pipeline_flow_name} run is still active (PID ${STATE_RUNNER_PID}); refusing to start a second one." >&2
            exit 1
        elif [ "${STATE_STATUS:-}" = "running" ] && [ "$state_age" -gt "$resume_ttl_seconds" ]; then
            echo "Discarding stale workspace run state for ${pipeline_flow_name} (older than 1 hour with no active runner)."
            rm -f "$pipeline_state_file"
            rm -f "$pipeline_update_summary_state_file" "$pipeline_internal_update_summary_state_file"
        elif [ "${STATE_FLOW_NAME:-}" = "$pipeline_flow_name" ] \
            && [ "${STATE_MODULES_SIGNATURE:-}" = "$pipeline_modules_signature" ] \
            && [ "${STATE_STEPS_SIGNATURE:-}" = "$pipeline_steps_signature" ] \
            && [ "${STATE_STATUS:-}" = "running" ]; then
            pipeline_started_at="${STATE_STARTED_AT:-$now}"
            completed_repos_csv="${STATE_COMPLETED_REPOS:-}"
            pipeline_is_resuming=1
            total_modules=$(count_modules)
            completed_modules=$(count_completed_repos)
            remaining_modules=$(( total_modules - completed_modules ))
            echo "Resuming ${pipeline_flow_name} from ${STATE_CURRENT_REPO:-the first pending repo} at step ${STATE_CURRENT_STEP:-the first pending step} (${completed_modules}/${total_modules} repos complete, ${remaining_modules} remaining)."
            return 0
        else
            echo "Discarding incompatible workspace run state for ${pipeline_flow_name}."
            rm -f "$pipeline_state_file"
            rm -f "$pipeline_update_summary_state_file" "$pipeline_internal_update_summary_state_file"
        fi
    fi

    pipeline_started_at="$(date +%s)"
    write_pipeline_state running "" ""
}

stop_local_gradle_processes() {
    if [ -x ./gradlew ]; then
        ./gradlew --stop >/dev/null 2>&1 || true
    fi
    pkill -f 'GradleDaemon' >/dev/null 2>&1 || true
}

base_image_updates_supported() {
    if ! command -v curl >/dev/null 2>&1; then
        base_image_update_skip_reason="curl is not installed"
        return 1
    fi

    if ! command -v jq >/dev/null 2>&1; then
        base_image_update_skip_reason="jq is not installed"
        return 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        base_image_update_skip_reason="Docker is not installed"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        base_image_update_skip_reason="Docker daemon is not available"
        return 1
    fi

    if ! docker buildx version >/dev/null 2>&1; then
        base_image_update_skip_reason="docker buildx is not available"
        return 1
    fi

    return 0
}

run_just_recipe_with_gradle_lock_retry() {
    local recipe="$1"
    local log_file
    local exit_code

    log_file=$(mktemp)

    set +e
    just "$recipe" >"$log_file" 2>&1
    exit_code="$?"
    set -e

    if [ "$exit_code" -ne 0 ] && grep -q 'Timeout waiting to lock journal cache' "$log_file"; then
        cat "$log_file"
        echo "Gradle cache lock detected while running '$recipe'; stopping daemons and retrying once..."
        stop_local_gradle_processes

        set +e
        just "$recipe" >"$log_file" 2>&1
        exit_code="$?"
        set -e
    fi

    cat "$log_file"
    rm -f "$log_file"

    return "$exit_code"
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

    if ! base_image_updates_supported; then
        append_workspace_event "Java image update skipped: ${base_image_update_skip_reason}."
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

commit_wip_if_needed() {
    local module="${1:-this repo}"

    if [ -z "$(git status --porcelain)" ]; then
        return 0
    fi

    echo "Creating WIP commit in ${module} to preserve local changes before pull."
    git add -A
    git commit -am "WIP"
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
    commit_wip_if_needed "$module"
    just pull
    echo "✓ $module pulled successfully"
}

run_module_update() {
    local module="$1"
    local keep_state="${2:-0}"

    print_header "Updating" "$module"
    cd_module "$module"
    prepare_base_image_policy
    WORKSPACE_UPDATE_EVENTS_FILE="$workspace_events_file" run_just_recipe_with_gradle_lock_retry update-all
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
    WORKSPACE_UPDATE_EVENTS_FILE="$workspace_events_file" run_just_recipe_with_gradle_lock_retry update-internal-dependencies
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
    if run_just_recipe_with_gradle_lock_retry build; then
        :
    elif apply_base_image_fallback; then
        run_just_recipe_with_gradle_lock_retry build
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
    local keep_state="${2:-0}"

    print_header "Rebuilding" "$module"
    cd_module "$module"
    if run_just_recipe_with_gradle_lock_retry rebuild; then
        :
    elif apply_base_image_fallback; then
        run_just_recipe_with_gradle_lock_retry rebuild
    else
        restore_base_image_files
        exit 1
    fi
    if [ "$keep_state" -eq 0 ]; then
        clear_workspace_events
        reset_base_image_state
    fi
    echo "✓ $module rebuilt successfully"
}

run_module_publish() {
    local module="$1"
    print_header "Publishing" "$module"
    cd_module "$module"
    if just --summary 2>/dev/null | tr ' ' '\n' | grep -Fxq publish; then
        run_just_recipe_with_gradle_lock_retry publish
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

run_step_pull() {
    local module
    for module in $modules; do
        run_module_pull "$module"
    done
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

    reset_summary_file

    for module in $modules; do
        run_module_build "$module"
    done

    print_summary_box "BUILD SUMMARY" "No build-triggered dependency changes detected."
    echo "✓ All modules built successfully!"
}

run_step_rebuild() {
    local module

    for module in $modules; do
        run_module_rebuild "$module"
    done

    echo "✓ All modules rebuilt successfully!"
}

run_step_publish() {
    local module

    for module in $modules; do
        run_module_publish "$module"
    done

    echo ""
    echo "✓ All module publish steps completed successfully!"
}

run_step_cleanup() {
    local module

    for module in $modules; do
        run_module_cleanup "$module"
    done

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

validate_execute_steps() {
    local previous_rank=0
    local step
    local step_rank
    local seen_steps=""

    if [ "$#" -eq 0 ]; then
        echo "No pipeline steps were provided." >&2
        exit 1
    fi

    for step in "$@"; do
        case "$step" in
            pull) step_rank=10 ;;
            update|update-internal) step_rank=20 ;;
            build|rebuild) step_rank=30 ;;
            publish|push) step_rank=40 ;;
            cleanup) step_rank=50 ;;
            *)
                echo "Unsupported workspace pipeline step: $step" >&2
                exit 1
                ;;
        esac

        case " $seen_steps " in
            *" $step "*)
                echo "Duplicate workspace pipeline step: $step" >&2
                exit 1
                ;;
        esac
        seen_steps="${seen_steps} ${step}"

        if [ "$step_rank" -lt "$previous_rank" ]; then
            echo "Invalid workspace pipeline order: '$step' cannot come after a later-stage step." >&2
            exit 1
        fi

        if { [ "$step" = "build" ] && [[ " $seen_steps " == *" rebuild "* ]]; } \
            || { [ "$step" = "rebuild" ] && [[ " $seen_steps " == *" build "* ]]; }; then
            echo "Use either 'build' or 'rebuild' in a workspace pipeline, not both." >&2
            exit 1
        fi

        previous_rank="$step_rank"
    done
}

pipeline_includes_step() {
    local expected_step="$1"
    shift
    local step

    for step in "$@"; do
        if [ "$step" = "$expected_step" ]; then
            return 0
        fi
    done

    return 1
}

run_module_pipeline() {
    local module="$1"
    shift
    local steps=("$@")
    local step
    local has_pending_base_image_state=0

    for step in "${steps[@]}"; do
        write_pipeline_state running "$module" "$step"
        case "$step" in
            pull)
                summary_file=""
                run_module_pull "$module"
                ;;
            update)
                has_pending_base_image_state=1
                summary_file="$pipeline_update_summary_file"
                run_module_update "$module" 1
                ;;
            update-internal)
                summary_file="$pipeline_internal_update_summary_file"
                run_module_update_internal "$module"
                ;;
            build)
                summary_file=""
                if [ "$has_pending_base_image_state" -eq 1 ]; then
                    run_module_build "$module" 1
                else
                    run_module_build "$module"
                fi
                ;;
            rebuild)
                summary_file=""
                if [ "$has_pending_base_image_state" -eq 1 ]; then
                    run_module_rebuild "$module" 1
                else
                    run_module_rebuild "$module"
                fi
                ;;
            publish)
                summary_file=""
                run_module_publish "$module"
                ;;
            push)
                summary_file=""
                run_module_push "$module"
                ;;
            cleanup)
                summary_file=""
                if [ "$has_pending_base_image_state" -eq 1 ]; then
                    clear_workspace_events
                    reset_base_image_state
                    has_pending_base_image_state=0
                fi
                run_module_cleanup "$module"
                ;;
            *)
                echo "Unsupported workspace pipeline step: $step" >&2
                exit 1
                ;;
        esac
    done

    if [ "$has_pending_base_image_state" -eq 1 ]; then
        clear_workspace_events
        reset_base_image_state
    fi
}

run_execute_pipeline() {
    shift 3
    local steps=("$@")
    local module
    local original_summary_file="$summary_file"

    validate_execute_steps "${steps[@]}"

    if execute_requires_workspace_requirements "${steps[@]}"; then
        ensure_workspace_requirements update
    fi

    prepare_pipeline_state "${steps[@]}"

    pipeline_update_summary_file=""
    pipeline_internal_update_summary_file=""
    if pipeline_includes_step update "${steps[@]}"; then
        pipeline_update_summary_file="$pipeline_update_summary_state_file"
        mkdir -p "$pipeline_state_dir"
        if [ "$pipeline_is_resuming" -eq 0 ] || [ ! -f "$pipeline_update_summary_file" ]; then
            : > "$pipeline_update_summary_file"
        fi
    fi
    if pipeline_includes_step update-internal "${steps[@]}"; then
        pipeline_internal_update_summary_file="$pipeline_internal_update_summary_state_file"
        mkdir -p "$pipeline_state_dir"
        if [ "$pipeline_is_resuming" -eq 0 ] || [ ! -f "$pipeline_internal_update_summary_file" ]; then
            : > "$pipeline_internal_update_summary_file"
        fi
    fi

    for module in $modules; do
        if pipeline_repo_is_completed "$module"; then
            echo "Skipping $module; already completed in previous ${pipeline_flow_name} run."
            continue
        fi

        run_module_pipeline "$module" "${steps[@]}"
        mark_pipeline_repo_completed "$module"
        write_pipeline_state running "" ""
    done

    if [ -n "$pipeline_update_summary_file" ]; then
        summary_file="$pipeline_update_summary_file"
        print_summary_box "UPDATE SUMMARY" "No upgrade-related changes detected."
    fi
    if [ -n "$pipeline_internal_update_summary_file" ]; then
        summary_file="$pipeline_internal_update_summary_file"
        print_summary_box "INTERNAL UPDATE SUMMARY" "No internal dependency changes detected."
    fi

    summary_file="$original_summary_file"
    remove_pipeline_state
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
    install)
        module=""
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

        (
            cd "$start_dir"
            just build-workspace
        )

        echo ""
        echo "✓ All modules installed successfully!"
        ;;
    reinstall)
        module=""
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
