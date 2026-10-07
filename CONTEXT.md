# Workspace Context

## Overview

Personal multi-project Kotlin/JVM workspace. Each project is its own git repo in a subdirectory of this workspace repo (ignored by its `.gitignore`), managed together via a root `justfile`.

Normal repos now consume internal libraries and conventions by explicit published version from `mavenLocal()`. Composite `includeBuild(...)` is not used.

Container image handling currently has two paths:

- shared Docker base image updates flow through repo `gradle.properties`
- repo-local container version automation is currently only present in `swissknife` via `container-versions.properties` and `scripts/update-container-versions.sh`

## Dependency Graph

```
gradle-plugins          (published build conventions)
       ↓
acme-schema-catalogue   (published Avro/JSON schemas)
       ↓
swissknife              (published general-purpose libraries)
       ↓
pillar                  (published domain-specific libraries)
lattice                 (published event-driven framework; depends on swissknife only)
       ↓
tools / examples / modulith-example / element-service-example / quality-scorer
```

`facts` is still on disk but **unwired** from the workspace flows — an abandoned exploration, superseded
by `lattice`.

Published internal versions are discovered locally through `mavenLocal()`. Workspace flows now distinguish between:

- `just build-workspace`: build, publish
- `just pull-workspace`: pull, build, publish, cleanup
- `just update-workspace`: update, build, publish, license audit, cleanup
- all three accept `--no-cache`, which swaps `build` for `rebuild`
- `just execute ...`: explicit workspace pipelines such as `just execute pull update build publish cleanup`

Workflow invariants:

- `just execute ...` is the source of truth for composed workspace flows
- workspace flows run sequentially in dependency order across all repos
- each repo still executes its own requested steps in order
- internal-only flows use `update-internal`; full flows use `update`

## Build System

- **Gradle** with Kotlin DSL and version catalogs (`gradle/libs.versions.toml`)
- **Kotlin**, **Temurin JDK** on the machine, **JUnit 5 + AssertK**
- **Configuration cache** enabled across all projects
- **`just`** for task automation — all recipes use kebab-case
- Machine prerequisites are upgraded only by `install-workspace` / `update-workspace` (or `just ensure-workspace-requirements`); every other flow runs the `check` mode of `scripts/ensure-workspace-requirements.sh`. Homebrew versions can be skipped until a date via `policy/version-holds.txt` (format documented in the file and in README.md).
- Workspace prerequisites are managed centrally from the root workspace scripts:
  - `just`, `jq`, Temurin via Homebrew
  - `git`, `curl`, Docker with `buildx`

### Key Commands

| Command | Description |
|---------|-------------|
| `just build` | Build a single project |
| `just build-workspace` | The inner loop: build, publish |
| `just pull-workspace` | Pull, build, publish, cleanup |
| `just update-workspace` | Update external versions, build, publish, license audit, cleanup |
| `just execute ...` | Compose workspace steps explicitly, for example `just execute pull update build publish cleanup` |
| `just publish` | Publish internal producer outputs to `mavenLocal()` when changed |
| `just update-all` | Repo-local internal update + external version update + wrapper update |
| `just update-java-workspace` | Targeted machine-level Temurin update from the workspace root |

Current workspace pipeline execution:
- workspace flows run sequentially in dependency order across all repos
- within any single repo, requested steps still run sequentially

### Build performance: ideas to revisit

- **Gradle daemon** (off today, see Gradle Lock / Daemon Issues): measured 2026-10-07, a no-change `build` drops from ~80s to ~25s with it on, and every invocation saves 2–3s. Risk seen: a daemon started from a sandboxed process gets reused by a later build and can't reach Docker (Jib fails).
- **Kotlin compile daemon**: ~4s per full swissknife compile; only worth it together with the Gradle daemon.

## Build Troubleshooting

### Gradle Lock / Daemon Issues

When running multiple Gradle builds in sequence (for example, `just execute build publish`), stale daemons or lock files can cause failures like:
```
Timeout waiting to lock journal cache (.gradle/caches/journal-1)
```

**Fix**: Kill all Gradle processes before retrying:
```bash
pkill -f "GradleDaemon" 2>/dev/null; pkill -f "gradle" 2>/dev/null; sleep 3
```

All workspace repos use `org.gradle.daemon=false` and `kotlin.compiler.execution.strategy=in-process` to avoid daemon accumulation.

### Sandbox / Network Restrictions

In sandboxed environments (e.g., Meta OnDemand), network access may be blocked. Symptoms:
- `Operation not permitted` on socket connections
- `validatePlugins` task fails (needs worker daemon sockets)
- Maven Central / Gradle Plugin Portal unreachable

**Fix**: Skip network-dependent tasks (`-x validatePlugins`) or use `--offline` if all dependencies are cached.

### Jib and Configuration Cache

Jib is incompatible with configuration cache at runtime (`jibDockerBuild` serializes `Project`). In modulith-example and element-service-example, `just build` splits into two Gradle invocations — `build` with config cache, then `jibDockerBuild`/`containerBasedServiceTest` with `--no-configuration-cache`.

## gradle-plugins

Conventions are registered as proper Gradle plugins with IDs:

| Plugin ID | What it does |
|-----------|-------------|
| `sollecitom.dependency-update-conventions` | Version catalog updates via littlerobots (PREFER_STABLE) |
| `sollecitom.minimum-dependency-version-conventions` | Enforce minimum versions for vulnerable dependencies |
| `sollecitom.test-conventions` | JUnit 5, parallel execution, test reporting |
| `sollecitom.aggregate-test-metrics-conventions` | Aggregate test metrics across subprojects |
| `sollecitom.maven-publish-conventions` | Maven publication setup |
| `sollecitom.jib-docker-build-conventions` | Jib Docker image build |
| `sollecitom.container-based-service-test-conventions` | Container-based service tests |
| `sollecitom.security-scan-conventions` | Docker image vulnerability scanning via Trivy |
| `sollecitom.kotlin-conventions` | Kotlin compiler options (JVM target, context parameters, progressive) |
| `sollecitom.kotlin-library-conventions` | Composite: kotlin-jvm + java-library + idea + test + minimum-dependency-version + repositories + Java toolchain |

Submodules apply `plugins { id("sollecitom.kotlin-library-conventions") }`. No `buildSrc` or `allprojects` — each module is self-contained.

## Security Scanning

Docker images built by Jib are scanned for vulnerabilities using Trivy (via Testcontainers). The `securityScan` task runs after `jibDockerBuild` in element-service-example and modulith-example.

- Trivy version and container image versions are managed in `swissknife/container-versions.properties`
- Update with `just update-container-versions` in swissknife
- Suppress accepted CVEs in `.trivyignore` per project
- Base Docker images are now digest-pinned through repo `gradle.properties` policy fields and refreshed by `just execute update` or `just update-workspace`
- Repo-local container image updates can contribute extra per-repo summary lines through the workspace event-file contract; today only `swissknife` uses that path

## License Audit

`just license-audit` (and `license-audit-compact` in `update-workspace`) checks every external dependency against `policy/license-policy.yml`. The full mechanics, including both caching layers and the known per-project gap, are in README.md under *License Audit*. The rules that matter when changing it:

- The dependency list comes from `scripts/cyclonedx-init.gradle`: per-project `licenseDependencySnapshot` tasks merged by a root `aggregateLicenseDependencySnapshot` (and `cyclonedxDirectBom` → `cyclonedxBom` for SBOMs).
- Caching is two-layered. The audit tool fingerprints the repo's build files before invoking Gradle, then Gradle's up-to-date checks skip unchanged snapshot tasks.
- Invariant: **any task that reads another task's output must declare that output as an input.** The aggregates once declared only root build files, so a subproject dependency change left the aggregate `UP-TO-DATE` and the audit silently skipped the new dependency.
- Force a re-check with `FORCE_LICENSE_AUDIT=1 just license-audit`, or delete the repo's `build/reports/license-audit/` to bypass both layers.

## Architecture Patterns

- **DDD / Hexagonal Architecture** throughout
- **CQRS + Event Sourcing** in modulith-example, element-service-example, lattice
- **Apache Pulsar** for event streaming, **PostgreSQL** for persistence, **NATS** for sync request-reply
- **http4k** for HTTP

## Active Project: Lattice

An event-driven, CQRS, event-sourced framework. Restarted from scratch; the earlier SDK/framework/
connector exploration was removed.

Currently a `usage-example` and `company-stubs` pair — the design is being driven outside-in from
developer-facing tests, and the framework will be extracted once the usage has a shape. Design
decisions and open questions live in [`lattice/events-framework.md`](lattice/events-framework.md).
