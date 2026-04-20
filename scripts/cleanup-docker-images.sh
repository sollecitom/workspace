#!/usr/bin/env bash
set -euo pipefail

keep_images=""
image_repositories=()

usage() {
    cat <<'EOF'
Usage: cleanup-docker-images.sh --keep <count> <image-repository>...
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --keep)
            keep_images="${2:?missing value for --keep}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            image_repositories+=("$1")
            shift
            ;;
    esac
done

if [ -z "$keep_images" ] || [ "${#image_repositories[@]}" -eq 0 ]; then
    usage >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is not installed; skipping Docker image cleanup."
    exit 0
fi

if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not available; skipping Docker image cleanup."
    exit 0
fi

image_listing="$(docker image ls --format '{{.Repository}}\t{{.Tag}}\t{{.ID}}')"

cleanup_repository() {
    local repository="$1"
    local -a entries=()
    local -a tags_to_remove=()
    local -A seen_ids=()
    local -A kept_ids=()
    local kept_count=0
    local entry=""
    local tag=""
    local image_id=""

    mapfile -t entries < <(printf '%s\n' "$image_listing" | awk -F'\t' -v repository="$repository" '$1 == repository && $2 != "<none>" { print $2 "\t" $3 }')

    if [ "${#entries[@]}" -eq 0 ]; then
        echo "No Docker images found for ${repository}."
        return 0
    fi

    for entry in "${entries[@]}"; do
        tag="${entry%%$'\t'*}"
        image_id="${entry#*$'\t'}"

        if [ -z "${seen_ids[$image_id]+x}" ]; then
            seen_ids[$image_id]=1
            if [ "$kept_count" -lt "$keep_images" ]; then
                kept_ids[$image_id]=1
                kept_count=$((kept_count + 1))
            fi
        fi

        if [ -z "${kept_ids[$image_id]+x}" ]; then
            tags_to_remove+=("${repository}:${tag}")
        fi
    done

    if [ "${#tags_to_remove[@]}" -eq 0 ]; then
        echo "No Docker image cleanup needed for ${repository} (keep ${keep_images} image ids)."
        return 0
    fi

    printf '%s\0' "${tags_to_remove[@]}" | xargs -0 docker image rm >/dev/null
    echo "Removed ${#tags_to_remove[@]} old Docker tags for ${repository} (keep ${keep_images} image ids)."
}

for repository in "${image_repositories[@]}"; do
    cleanup_repository "$repository"
done
