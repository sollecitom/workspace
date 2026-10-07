# Build improvements to revisit

Ideas measured or designed but not implemented. Numbers are from 2026-10-07 (11-core laptop).

## Gradle daemon

Off in every repo (`org.gradle.daemon=false`) to avoid daemon accumulation across sequential workspace builds (see CONTEXT.md, Gradle Lock / Daemon Issues).

- Gain: a no-change `build` drops from ~80s to ~25s; every Gradle invocation saves 2–3s (a `build-workspace` runs ~21).
- Risk seen: a daemon started from a sandboxed process is reused by a later build and can't reach Docker, so Jib fails.

## Kotlin compile daemon

Compilation is `in-process` today. A Kotlin daemon saves ~4s per full swissknife compile, but only pays off together with the Gradle daemon.

## One container per build, stopped with the build

Today every container-backed test class starts its own Pulsar (and Postgres in element): ~7 Pulsar starts per full workspace build, ~5s each.

How:
- A Gradle shared build service (`BuildService` + `AutoCloseable`) in gradle-plugins starts the container lazily, the first time a test task that needs it runs, and stops it in `close()`.
- Gradle closes build services when the build finishes, including on failure or cancellation, so nothing outlives the build. No Testcontainers reuse mode.
- Test tasks declare `usesService(...)` and get the container's address through system properties. Test specs read the address when it's present and fall back to starting their own container otherwise, so IDE runs keep working.
- Scope is one repo build: each repo in `build-workspace` gets its own instance.

Costs:
- Tests must not assume a fresh broker or database: unique topic names (most already do) and isolated database schemas or data per test class.
- Containers become shared state between test JVMs of the same build, so failures can cross tests.

Expected gain: ~20–30s per full workspace build.

## Rejected

- **Skip `jibDockerBuild` when the image is unchanged** (fingerprint label on the image + `onlyIf` with `docker image inspect`): tried 2026-10-07, saved ~3.5s per service repo on a no-change build (no-change `build-workspace` 77s → 71s). Not worth the extra convention complexity; reverted (gradle-plugins 4021000).
