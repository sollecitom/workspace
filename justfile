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

# Workspace operations
@update-workspace:
    bash ./scripts/workspace.sh update '{{workspace_and_modules}}'

@pull-workspace:
    bash ./scripts/workspace.sh pull '{{workspace_and_modules}}'

@reset-workspace:
    bash ./scripts/workspace.sh reset '{{workspace_and_modules}}'

@push-workspace:
    bash ./scripts/workspace.sh push '{{workspace_and_modules}}'

@build-and-publish-workspace:
    bash ./scripts/workspace.sh build-and-publish '{{workspace_and_modules}}' '{{publishable}}'

@rebuild-workspace:
    bash ./scripts/workspace.sh rebuild '{{workspace_and_modules}}'

@build-workspace:
    bash ./scripts/workspace.sh build '{{workspace_and_modules}}'

@reinstall-workspace:
    bash ./scripts/workspace.sh reinstall '{{all_modules}}'
