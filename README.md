# Workspace

A way to manage multiple projects in a centralised way.

## Requirements

1. [Just](https://github.com/casey/just) command runner.

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
