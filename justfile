#!/usr/bin/env just --justfile

set quiet

# Project modules (order matters: dependencies first)
publishable := "gradle-plugins acme-schema-catalogue swissknife pillar lattice"
non_publishable := "tools examples backend-skeleton modulith-example element-service-example quality-scorer"
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

# Workspace operations
# Workflow invariants:
# - `execute` is the source of truth for composed workspace flows.
# - Workspace flows run sequentially in dependency order across all repos.
# - Within any repo, requested steps still execute in order.
# - There is no resume state: Gradle's own up-to-date checks make unchanged repos near-free,
#   so a re-run after a failure simply repeats the cheap work and continues.
# - `--no-cache` means "ignore Gradle's caches": it swaps `build` for `rebuild`
#   (`clean --rerun-tasks --refresh-dependencies`). It is a clean-room verification, not the daily loop.

# The daily loop: build every repo and publish the producers whose artifacts changed.
# Deliberately no `pull` and no `cleanup`, to keep the inner loop as short as possible.
@build-workspace flag="":
    {{ if flag == "" { "just execute build publish" } else if flag == "--no-cache" { "just execute rebuild publish" } else { error("Unknown flag '" + flag + "' (supported: --no-cache)") } }}

# Same as build-workspace, but pulls each repo first and prunes afterwards.
@pull-workspace flag="":
    {{ if flag == "" { "just execute pull build publish cleanup" } else if flag == "--no-cache" { "just execute pull rebuild publish cleanup" } else { error("Unknown flag '" + flag + "' (supported: --no-cache)") } }}

# The maintenance pass: also update external dependency versions and audit licenses.
# Security scanning is part of `build`/`rebuild` in the repos that produce container images.
@update-workspace flag="":
    {{ if flag == "" { "just execute update build publish license-audit-compact cleanup" } else if flag == "--no-cache" { "just execute update rebuild publish license-audit-compact cleanup" } else { error("Unknown flag '" + flag + "' (supported: --no-cache)") } }}

@execute +steps:
    bash ./scripts/workspace.sh execute '{{workspace_and_modules}}' '{{publishable}}' {{steps}}

@install-workspace:
    bash ./scripts/workspace.sh install '{{all_modules}}'

@reinstall-workspace:
    bash ./scripts/workspace.sh reinstall '{{all_modules}}'
