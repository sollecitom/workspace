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

Builds every repo in dependency order. This is the internal-only path:

- updates internal dependency versions from `mavenLocal()`
- builds every repo
- publishes internal producers only when their artifacts changed

### Install Everything

`just install-workspace`

Clones every missing repo, then runs `just build-workspace`.

### Reinstall Everything

`just reinstall-workspace`

Deletes every repo, reclones them all, then runs `just install-workspace`.

### Check Requirements

`just check-workspace-requirements`

Verifies the required local CLI tools are available.

### Update Machine JDK

`just update-java-workspace`

Runs the targeted Temurin JDK update for the machine without triggering a general Homebrew auto-update.

### Pull/Push Everything

`just pull-workspace` (or push)

### Update Dependencies and Rebuild/Publish Everything

`just update-workspace`

This is the full path:

- commits and pulls first
- updates internal versions
- updates external versions
- builds every repo
- republishes internal producers only when their artifacts changed
