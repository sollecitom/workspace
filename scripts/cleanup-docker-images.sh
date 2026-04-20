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

image_listing="$(docker image ls --no-trunc --format '{{.Repository}}\t{{.Tag}}\t{{.ID}}')"

cleanup_repository() {
    local repository="$1"
    local refs_file
    local unique_ids_file
    local dated_ids_file
    local kept_ids_file
    local tags_to_remove_file
    local remove_count="0"
    local inspect_ids
    local image_ref
    local image_id

    refs_file=$(mktemp)
    unique_ids_file=$(mktemp)
    dated_ids_file=$(mktemp)
    kept_ids_file=$(mktemp)
    tags_to_remove_file=$(mktemp)

    printf '%s\n' "$image_listing" \
        | awk -F'\t' -v repository="$repository" '$1 == repository && $2 != "<none>" { print $0 }' > "$refs_file"

    if [ ! -s "$refs_file" ]; then
        rm -f "$refs_file" "$unique_ids_file" "$dated_ids_file" "$kept_ids_file" "$tags_to_remove_file"
        echo "No local Docker tags matched ${repository}; nothing to clean."
        return 0
    fi

    awk -F'\t' '{ print $3 }' "$refs_file" | awk '!seen[$0]++' > "$unique_ids_file"

    inspect_ids="$(tr '\n' ' ' < "$unique_ids_file" | sed 's/[[:space:]]*$//')"
    if [ -n "$inspect_ids" ]; then
        # Docker returns one formatted line per inspected image; using --no-trunc
        # keeps ids stable between `docker image ls` and `docker image inspect`.
        docker image inspect $inspect_ids --format '{{.Id}}\t{{.Created}}' \
            | awk -F'\t' '{ print $2 "\t" $1 }' > "$dated_ids_file"
    fi

    sort -r "$dated_ids_file" | awk -F'\t' -v keep="$keep_images" 'NR <= keep { print $2 }' > "$kept_ids_file"

    while IFS=$'\t' read -r _repo tag image_id; do
        [ -n "$tag" ] || continue
        if ! grep -Fxq "$image_id" "$kept_ids_file"; then
            printf '%s:%s\n' "$repository" "$tag" >> "$tags_to_remove_file"
        fi
    done < "$refs_file"

    remove_count="$(awk 'NF { count++ } END { print count + 0 }' "$tags_to_remove_file")"

    if [ "$remove_count" -eq 0 ]; then
        rm -f "$refs_file" "$unique_ids_file" "$dated_ids_file" "$kept_ids_file" "$tags_to_remove_file"
        echo "No Docker cleanup needed for ${repository} (keeping latest ${keep_images} image ids by creation time)."
        return 0
    fi

    while IFS= read -r image_ref; do
        [ -n "$image_ref" ] || continue
        docker image rm "$image_ref" >/dev/null
    done < "$tags_to_remove_file"

    rm -f "$refs_file" "$unique_ids_file" "$dated_ids_file" "$kept_ids_file" "$tags_to_remove_file"
    echo "Removed ${remove_count} old Docker tags for ${repository} (kept latest ${keep_images} image ids by creation time)."
}

for repository in "${image_repositories[@]}"; do
    cleanup_repository "$repository"
done
