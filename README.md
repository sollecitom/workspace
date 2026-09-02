# Workspace

A way to manage multiple projects in a centralised way.

## Requirements

Bootstrap requirements:

1. [Homebrew](https://brew.sh/)
2. [Just](https://github.com/casey/just) command runner

Workspace-managed requirements checked during `just install-workspace` and `just update-workspace`:

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

The inner loop. Builds every repo in dependency order and publishes producers whose artifacts changed:

- updates internal dependency versions from `mavenLocal()`
- builds every repo
- publishes internal producers only when their artifacts changed

Deliberately does not pull or clean, to keep the loop short.

### Pull And Build Everything

`just pull-workspace`

Everything `build-workspace` does, plus:

- commits local repo changes as `WIP` before `pull` when needed
- pulls every repo in dependency order
- runs each repo's cleanup policy at the end

### Update Everything

`just update-workspace`

The maintenance pass. Everything `build-workspace` does, plus:

- updates external dependency versions, container images, and Gradle wrappers
- runs compact license audits for each repo
- runs each repo's cleanup policy at the end

### Forcing A Clean Rebuild

All three accept `--no-cache`, which swaps the normal `build` for a `rebuild`
(`clean --rerun-tasks --refresh-dependencies`), bypassing Gradle's caches:

`just build-workspace --no-cache`

Use it for a clean-room verification pass, not for the daily loop: it discards every
up-to-date check, so it rebuilds and re-tests everything regardless of what changed.

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

Named workspace commands such as `build-workspace` and `update-workspace` are thin wrappers around `execute`.

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
- `update-workspace` automatically runs `license-audit-compact`
- `build-workspace` and `pull-workspace` do not run license audit

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

Cleanup is repo-local, but the workspace flows run it automatically.

Current behavior:

- `build-workspace` does not clean, to keep the inner loop short
- `pull-workspace` cleans
- `update-workspace` cleans

A full workspace cleanup takes about 20 seconds.

Each repo decides its own retention policy for:

- Maven-local artifacts under `~/.m2/repository`
- local Docker images, where applicable

Current retention policy:

- library-style repos keep the current version, the newest `5` version directories, and only delete older Maven-local versions once they are also older than `30` days
- service/consumer repos keep the current version, the newest `2` version directories, and only delete older Maven-local versions once they are also older than `14` days
- Docker images use a count-only policy and keep the newest `2` image ids by creation time for each configured image repository

In other words, Maven-local cleanup currently uses a mixed count-and-age rule, while Docker cleanup uses count only.
