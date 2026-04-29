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

update-internal-dependencies:
    @:

cleanup:
    @:

@check-workspace-requirements:
    bash ./scripts/ensure-workspace-requirements.sh check

@ensure-workspace-requirements:
    bash ./scripts/ensure-workspace-requirements.sh install

@update-java-workspace:
    bash ./scripts/ensure-workspace-requirements.sh update-java

@license-audit:
    bash ./scripts/workspace.sh license-audit '{{workspace_and_modules}}' '{{publishable}}'

@license-audit-compact:
    bash ./scripts/workspace.sh license-audit-compact '{{workspace_and_modules}}' '{{publishable}}'

@license-audit-workspace:
    WORKSPACE_FLOW_NAME=license-audit-workspace just execute license-audit

# Workspace operations
# Workflow invariants:
# - `execute` is the source of truth for composed workspace flows.
# - Workspace flows run sequentially in dependency order across all repos.
# - Within any repo, requested steps still execute in order
#   (for example `pull -> update -> build -> publish -> cleanup`).
# - `build-workspace` and `refresh-local-workspace` are internal-only flows.
# - `refresh-workspace` is the full flow and includes external dependency updates.

@build-workspace:
    WORKSPACE_FLOW_NAME=build-workspace just execute update-internal build publish

@refresh-workspace:
    WORKSPACE_FLOW_NAME=refresh-workspace just execute pull update build publish license-audit-compact cleanup

@refresh-rebuild-workspace:
    WORKSPACE_FLOW_NAME=refresh-rebuild-workspace just execute pull update rebuild publish license-audit-compact cleanup

@rebuild-workspace:
    WORKSPACE_FLOW_NAME=rebuild-workspace just execute pull update-internal rebuild publish

@refresh-local-workspace:
    WORKSPACE_FLOW_NAME=refresh-local-workspace just execute update-internal build publish cleanup

@reset-workspace-state flow="all":
    bash ./scripts/reset-workspace-state.sh '{{flow}}'

@execute +steps:
    bash ./scripts/workspace.sh execute '{{workspace_and_modules}}' '{{publishable}}' {{steps}}

@install-workspace:
    bash ./scripts/workspace.sh install '{{all_modules}}'

@reinstall-workspace:
    bash ./scripts/workspace.sh reinstall '{{all_modules}}'
