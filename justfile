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

@publish-workspace:
    bash ./scripts/workspace.sh publish '{{workspace_and_modules}}' '{{publishable}}'

@cleanup-workspace:
    bash ./scripts/workspace.sh cleanup '{{workspace_and_modules}}'

@refresh-workspace:
    just execute pull update build publish cleanup

@refresh-local-workspace:
    just execute build publish cleanup

@execute +steps:
    bash ./scripts/workspace.sh execute '{{workspace_and_modules}}' '{{publishable}}' {{steps}}

@workflow-workspace +steps:
    just execute {{steps}}

@install-workspace:
    bash ./scripts/workspace.sh install '{{all_modules}}'

@reinstall-workspace:
    bash ./scripts/workspace.sh reinstall '{{all_modules}}'
