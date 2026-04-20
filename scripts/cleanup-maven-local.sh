#!/usr/bin/env bash
set -euo pipefail

repo_root="."
keep_versions=""
max_age_days=""
maven_local="${HOME}/.m2/repository"

usage() {
    cat <<'EOF'
Usage: cleanup-maven-local.sh --keep <count> --max-age-days <days> [--repo-root <path>] [--maven-local <path>]
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo-root)
            repo_root="${2:?missing value for --repo-root}"
            shift 2
            ;;
        --keep)
            keep_versions="${2:?missing value for --keep}"
            shift 2
            ;;
        --max-age-days)
            max_age_days="${2:?missing value for --max-age-days}"
            shift 2
            ;;
        --maven-local)
            maven_local="${2:?missing value for --maven-local}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [ -z "$keep_versions" ] || [ -z "$max_age_days" ]; then
    usage >&2
    exit 1
fi

property_value() {
    local file="$1"
    local key="$2"
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, "", $0); print $0; exit }' "$file"
}

directory_mtime_epoch() {
    local path="$1"
    if stat -f %m "$path" >/dev/null 2>&1; then
        stat -f %m "$path"
    else
        stat -c %Y "$path"
    fi
}

repo_gradle_properties="${repo_root}/gradle.properties"
if [ ! -f "$repo_gradle_properties" ]; then
    echo "No gradle.properties found under ${repo_root}; skipping Maven-local cleanup."
    exit 0
fi

project_group="$(property_value "$repo_gradle_properties" projectGroup)"
current_version="$(property_value "$repo_gradle_properties" currentVersion)"

if [ -z "$project_group" ]; then
    echo "No projectGroup declared in ${repo_gradle_properties}; skipping Maven-local cleanup."
    exit 0
fi

group_path="${project_group//./\/}"
artifacts_root="${maven_local}/${group_path}"

if [ ! -d "$artifacts_root" ]; then
    echo "No Maven-local artifact root exists at ${artifacts_root}; nothing to clean for ${project_group}."
    exit 0
fi

current_epoch="$(date +%s)"
cutoff_epoch=$(( current_epoch - (max_age_days * 86400) ))
removed_count=0

while IFS= read -r -d '' artifact_dir; do
    mapfile -t version_entries < <(
        find "$artifact_dir" -mindepth 1 -maxdepth 1 -type d -print \
            | awk -F/ '{ print $NF "\t" $0 }' \
            | sort -t $'\t' -k1,1Vr
    )

    if [ "${#version_entries[@]}" -eq 0 ]; then
        continue
    fi

    rank=0
    for entry in "${version_entries[@]}"; do
        version="${entry%%$'\t'*}"
        version_dir="${entry#*$'\t'}"
        rank=$((rank + 1))

        if [ -n "$current_version" ] && [ "$version" = "$current_version" ]; then
            continue
        fi

        if [ "$rank" -le "$keep_versions" ]; then
            continue
        fi

        version_mtime="$(directory_mtime_epoch "$version_dir")"
        if [ "$version_mtime" -ge "$cutoff_epoch" ]; then
            continue
        fi

        rm -rf "$version_dir"
        removed_count=$((removed_count + 1))
    done
done < <(find "$artifacts_root" -mindepth 1 -maxdepth 1 -type d -print0)

if [ "$removed_count" -eq 0 ]; then
    echo "No Maven-local cleanup needed for ${project_group} under ${artifacts_root} (keep ${keep_versions}, max age ${max_age_days}d)."
else
    echo "Removed ${removed_count} old Maven-local version directories for ${project_group} under ${artifacts_root} (keep ${keep_versions}, max age ${max_age_days}d)."
fi
