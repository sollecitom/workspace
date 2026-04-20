#!/usr/bin/env just --justfile

set quiet

# Project modules (order matters: dependencies first)
publishable := "gradle-plugins acme-schema-catalogue swissknife pillar"
non_publishable := "tools examples facts backend-skeleton modulith-example element-service-example lattice"
all_modules := publishable + " " + non_publishable
workspace_and_modules := "workspace " + all_modules

# Git operations (workspace repo only — for the justfile, CONTEXT.md, analysis files)
push:
    git add -A && (git diff --quiet HEAD || git commit -am "WIP") && git pull --rebase origin main && git push origin main

pull:
    git pull --rebase origin main

build:
    @:

rebuild:
    @:

update-all:
    @:

cleanup:
    @:

@check-workspace-requirements:
    bash ./scripts/ensure-workspace-requirements.sh check

@ensure-workspace-requirements:
    bash ./scripts/ensure-workspace-requirements.sh install

@update-java-workspace:
    bash ./scripts/ensure-workspace-requirements.sh update-java

# Workspace operations
# Workflow invariants:
# - `execute` is the source of truth for composed workspace flows.
# - For any given pipeline, `workspace` and publishable/library repos must run sequentially.
# - Non-library/service repos may run in parallel, but each repo still executes the requested
#   steps in order within that repo (for example `pull -> update -> build -> publish -> cleanup`).
# - `build-workspace` and `refresh-local-workspace` are internal-only flows.
# - `refresh-workspace` is the full flow and includes external dependency updates.

@build-workspace:
    just execute update-internal build publish

@refresh-workspace:
    just execute pull update build publish cleanup

@refresh-rebuild-workspace:
    just execute pull update rebuild publish cleanup

@rebuild-workspace:
    just execute pull update-internal rebuild publish

@refresh-local-workspace:
    just execute update-internal build publish cleanup

@execute +steps:
    bash ./scripts/workspace.sh execute '{{workspace_and_modules}}' '{{publishable}}' {{steps}}

@install-workspace:
    bash ./scripts/workspace.sh install '{{all_modules}}'

@reinstall-workspace:
    bash ./scripts/workspace.sh reinstall '{{all_modules}}'
