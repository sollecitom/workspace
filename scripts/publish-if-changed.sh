#!/usr/bin/env bash
# Publishes the current repo to Maven Local, but only when its published artifacts actually differ from the
# state recorded in publication-state.properties. Run from the root of the repo being published.
#
# Usage: publish-if-changed.sh [--with-configuration-cache]
#
#   --with-configuration-cache  keep Gradle's configuration cache enabled for publishToMavenLocal.
#                               Off by default: most repos here have publication tasks that are not
#                               configuration-cache compatible. gradle-plugins opts in.
set -euo pipefail

use_configuration_cache=false
case "${1:-}" in
    --with-configuration-cache) use_configuration_cache=true ;;
    "") ;;
    *) echo "Unknown option '$1' (supported: --with-configuration-cache)" >&2; exit 2 ;;
esac

props_file="gradle.properties"
state_file="build/publication-state/publication-state.properties"
tracked_state_file="publication-state.properties"
original_version=$(grep '^currentVersion=' "$props_file" | cut -d= -f2-)
project_group=$(grep '^projectGroup=' "$props_file" | cut -d= -f2-)

restore_original_version() {
    if [ -n "${original_version:-}" ] && grep -q '^currentVersion=' "$props_file"; then
        sed -i '' "s/^currentVersion=.*/currentVersion=${original_version}/" "$props_file"
    fi
}

write_tracked_state() {
    local temp_file
    local maven_root
    local artifact_lines
    local artifact_count
    temp_file=$(mktemp "${tracked_state_file}.tmp.XXXXXX")
    maven_root="${HOME}/.m2/repository/$(printf '%s' "$project_group" | tr '.' '/')"
    artifact_lines=$(
        find . -path './build/libs/*' -prune -o -path '*/build/libs/*.jar' -type f -print | sort | while read -r build_jar; do
            local_file_name=$(basename "$build_jar")

            if [[ "$local_file_name" == *-"${target_version}.jar" ]]; then
                artifact_id=${local_file_name%"-${target_version}.jar"}
                classifier=""
            elif [[ "$local_file_name" == *-"${target_version}"-*.jar ]]; then
                artifact_id=${local_file_name%%-"${target_version}"-*}
                classifier=${local_file_name#"$artifact_id-$target_version-"}
                classifier=${classifier%.jar}
            else
                continue
            fi

            published_jar="${maven_root}/${artifact_id}/${target_version}/${local_file_name}"
            [ -f "$published_jar" ] || continue

            if [ -n "$classifier" ]; then
                identity="${project_group}:${artifact_id}:${classifier}@jar"
            else
                identity="${project_group}:${artifact_id}@jar"
            fi

            sha256=$(shasum -a 256 "$published_jar" | awk '{print $1}')
            printf '%s|%s\n' "$identity" "$sha256"

            # The POM and the Gradle module metadata are where dependency versions live. A dependency-only
            # upgrade leaves the bytecode untouched, so recording jars alone makes the next run report
            # "unchanged" and skip the republish, stranding consumers on the previously published versions.
            # Recorded once per module, against the main artifact rather than each classifier.
            if [ -z "$classifier" ]; then
                for extension in pom module; do
                    published_metadata="${maven_root}/${artifact_id}/${target_version}/${artifact_id}-${target_version}.${extension}"
                    [ -f "$published_metadata" ] || continue
                    metadata_sha256=$(shasum -a 256 "$published_metadata" | awk '{print $1}')
                    printf '%s|%s\n' "${project_group}:${artifact_id}@${extension}" "$metadata_sha256"
                done
            fi
        done | sort -u
    )
    artifact_count=$(printf '%s\n' "$artifact_lines" | sed '/^$/d' | wc -l | tr -d ' ')
    {
        echo "publishedVersion=${target_version}"
        echo "artifactCount=${artifact_count}"
        index=0
        while IFS='|' read -r identity sha256; do
            [ -n "${identity:-}" ] || continue
            index=$((index + 1))
            echo "artifact.${index}.identity=${identity}"
            echo "artifact.${index}.sha256=${sha256}"
        done <<< "$artifact_lines"
    } > "$temp_file"
    mv "$temp_file" "$tracked_state_file"
}

./gradlew writePublicationState

status=$(grep '^status=' "$state_file" | cut -d= -f2-)
target_version=$(grep '^targetVersion=' "$state_file" | cut -d= -f2-)

if [ "$status" = "UNCHANGED" ]; then
    echo "Artifacts match the tracked published state. Skipping publish."
    exit 0
fi

if [ "$target_version" != "$original_version" ]; then
    sed -i '' "s/^currentVersion=.*/currentVersion=${target_version}/" "$props_file"
fi

cleanup() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        restore_original_version
    fi
    exit "$exit_code"
}
trap cleanup EXIT

if [ "$use_configuration_cache" = true ]; then
    ./gradlew publishToMavenLocal
else
    ./gradlew --no-configuration-cache publishToMavenLocal
fi

write_tracked_state
trap - EXIT
echo "Published version ${target_version}"
