# Workspace

A way to manage multiple projects in a centralised way.

## Requirements

Bootstrap requirements:

1. [Homebrew](https://brew.sh/)
2. [Just](https://github.com/casey/just) command runner

Workspace-managed requirements checked during `just install-workspace` and `just refresh-workspace`:

1. `jq`
2. Temurin JDK via Homebrew
3. `git`
4. `curl`
5. Docker with `buildx`

Notes:

- Workspace install/update uses targeted Homebrew operations only. It does not run a general Homebrew upgrade.
- `just` and `jq` are installed if missing, and upgraded if already present.
- Only Temurin is actively upgraded, via `brew upgrade --cask temurin` with `HOMEBREW_NO_AUTO_UPDATE=1`.
- `just` is still a bootstrap prerequisite because you need it to run the workspace commands in the first place.

## Commands

### Build Everything

`just build-workspace`

Builds every repo in dependency order without touching external dependencies:

- updates internal dependency versions from `mavenLocal()`
- builds every repo
- publishes internal producers only when their artifacts changed

If you also want cleanup at the end, use `just refresh-local-workspace`.

### Refresh Everything

`just refresh-workspace`

This is the full workspace flow:

- commits local repo changes as `WIP` before `pull` when needed
- pulls every repo in dependency order
- updates external and internal dependency versions
- builds every repo
- publishes internal producers only when their artifacts changed
- runs compact license audits for each repo
- runs each repo's cleanup policy

This command is resumable. If it fails mid-run, rerun the same command to continue from the first unfinished repo.

### Refresh Local Only

`just refresh-local-workspace`

Runs the local-only refresh flow:

- updates internal dependency versions from `mavenLocal()`
- builds every repo
- publishes internal producers only when their artifacts changed
- runs each repo's cleanup policy

Use this when you want the full local publish/build/cleanup cycle without pulling or updating external dependencies.

### Force Rebuild Everything

`just refresh-rebuild-workspace`

Runs the full refresh flow, but forces rebuilds instead of normal builds:

- commits and pulls first
- updates internal and external dependency versions
- forces full repo rebuilds
- republishes internal producers only when their artifacts changed
- runs compact license audits for each repo
- runs each repo's cleanup policy

This is the most useful command when you want a full clean-ish verification pass across the workspace.

### Force Rebuild Local Only

`just rebuild-workspace`

Runs the internal-only rebuild path:

- commits and pulls first
- updates internal versions
- forces full repo rebuilds
- republishes internal producers only when their artifacts changed

Unlike `refresh-rebuild-workspace`, this does not run cleanup at the end.

### Install Everything

`just install-workspace`

Clones every missing repo, then runs `just build-workspace`.

### Reinstall Everything

`just reinstall-workspace`

Deletes every repo, reclones them all, then runs `just install-workspace`.

### Pull/Push Everything

`just execute pull` (or use repo-local `just pull`)

For workspace-git-only push of the root repo metadata:

`just push`

### Compose A Flow

`just execute <step>...`

Examples:

- `just execute pull update build publish cleanup`
- `just execute update-internal build publish`
- `just execute pull update rebuild publish cleanup`

Allowed steps:

- `pull`
- `update`
- `update-internal`
- `build`
- `rebuild`
- `publish`
- `push`
- `cleanup`

Rules:

- steps run sequentially in the order you provide
- each repo completes its full requested mini-pipeline before the next repo starts
- duplicate steps are rejected
- invalid step order is rejected
- use either `build` or `rebuild`, not both

Named workspace commands such as `build-workspace` and `refresh-workspace` are thin wrappers around `execute`.

### License Audit

Workspace-level commands:

- `just license-audit`
- `just license-audit-compact`

Repo-local commands, from inside any repo that exposes them:

- `just license-audit`
- `just license-audit-compact`

Behavior:

- `license-audit` is the extended report, including grouped findings and explanatory notes
- `license-audit-compact` prints only the compact finding set intended for workspace flows
- both commands fail on `DENY`
- both commands also fail on `UNKNOWN`
- `refresh-workspace` and `refresh-rebuild-workspace` automatically run `license-audit-compact`
- `build-workspace` does not run license audit

### Reset Resume State

`just reset-workspace-state`

Removes all saved resumable workspace state.

You can also reset a single flow:

`just reset-workspace-state refresh-workspace`

Supported flow names currently include:

- `build-workspace`
- `refresh-workspace`
- `refresh-local-workspace`
- `refresh-rebuild-workspace`
- `rebuild-workspace`

`just reset-workspace-state all` is equivalent to the default.

### Check Requirements

`just check-workspace-requirements`

Verifies the required local CLI tools are available.

### Ensure Requirements

`just ensure-workspace-requirements`

Installs or upgrades the workspace-managed machine prerequisites.

### Update Machine JDK

`just update-java-workspace`

Runs the targeted Temurin JDK update for the machine without triggering a general Homebrew auto-update.

## Cleanup

Cleanup is repo-local, but the refresh flows run it automatically.

Current behavior:

- `build-workspace` does not clean
- `rebuild-workspace` does not clean
- `refresh-workspace` cleans
- `refresh-local-workspace` cleans
- `refresh-rebuild-workspace` cleans

Each repo decides its own retention policy for:

- Maven-local artifacts under `~/.m2/repository`
- local Docker images, where applicable

Current retention policy:

- library-style repos keep the current version, the newest `5` version directories, and only delete older Maven-local versions once they are also older than `30` days
- service/consumer repos keep the current version, the newest `2` version directories, and only delete older Maven-local versions once they are also older than `14` days
- Docker images use a count-only policy and keep the newest `2` image ids by creation time for each configured image repository

In other words, Maven-local cleanup currently uses a mixed count-and-age rule, while Docker cleanup uses count only.

## Resumability

These named workspace flows are resumable:

- `build-workspace`
- `refresh-workspace`
- `refresh-local-workspace`
- `refresh-rebuild-workspace`
- `rebuild-workspace`

Resume behavior:

- successful repos are marked complete
- rerunning the same command resumes from the first unfinished repo
- failed steps are retried; successful repos are skipped
- stale saved state older than one hour is discarded automatically
- use `just reset-workspace-state` if you want to force a full restart from scratch
