# Workspace Context

## Overview

Personal multi-project Kotlin/JVM workspace. All projects are sibling git repos under `~/workspace`, managed together via a root `justfile`.

Normal repos now consume internal libraries and conventions by explicit published version from `mavenLocal()`. Composite `includeBuild(...)` is no longer the normal workspace path; a future separate aggregator repo may still use it for cross-repo development.

## Dependency Graph

```
gradle-plugins          (published build conventions)
       ↓
acme-schema-catalogue   (published Avro/JSON schemas)
       ↓
swissknife              (published general-purpose libraries)
       ↓
pillar                  (published domain-specific libraries)
       ↓
tools / examples / facts / lattice / backend-skeleton / modulith-example / element-service-example
```

Published internal versions are discovered locally through `mavenLocal()`. Workspace flows now distinguish between:

- `just build-workspace`: internal-only updates plus build/publish
- `just update-workspace`: pull, internal updates, external updates, then conditional standalone build only when the repo actually changed

## Build System

- **Gradle 9.4.1** with Kotlin DSL and version catalogs (`gradle/libs.versions.toml`)
- **Kotlin 2.3.20**, **Temurin JDK 26** on the machine, **JUnit 5 + AssertK**
- **Configuration cache** enabled across all projects
- **`just`** for task automation — all recipes use kebab-case
- Workspace prerequisites are managed centrally from the root workspace scripts:
  - `just`, `jq`, Temurin via Homebrew
  - `git`, `curl`, Docker with `buildx`

### Key Commands

| Command | Description |
|---------|-------------|
| `just build` | Build a single project |
| `just build-workspace` | Internal-only workspace update plus build/publish in dependency order |
| `just update-workspace` | Pull, update internal/external versions, then conditionally build changed repos |
| `just publish` | Publish internal producer outputs to `mavenLocal()` when changed |
| `just update-all` | Repo-local internal update + external version update + wrapper update |
| `just push-workspace` | Git push all projects |
| `just update-java-workspace` | Targeted machine-level Temurin update from the workspace root |

## Build Troubleshooting

### Gradle Lock / Daemon Issues

When running multiple Gradle builds in sequence (e.g., `build-workspace`), stale daemons or lock files can cause failures like:
```
Timeout waiting to lock journal cache (.gradle/caches/journal-1)
```

**Fix**: Kill all Gradle processes before retrying:
```bash
pkill -f "GradleDaemon" 2>/dev/null; pkill -f "gradle" 2>/dev/null; sleep 3
```

All projects use `org.gradle.daemon=false` to avoid daemon accumulation, but background Kotlin compiler daemons can still hold locks.

### Sandbox / Network Restrictions

In sandboxed environments (e.g., Meta OnDemand), network access may be blocked. Symptoms:
- `Operation not permitted` on socket connections
- `validatePlugins` task fails (needs worker daemon sockets)
- Maven Central / Gradle Plugin Portal unreachable

**Fix**: Skip network-dependent tasks (`-x validatePlugins`) or use `--offline` if all dependencies are cached.

### Jib and Configuration Cache

Jib 3.5.3 is incompatible with configuration cache at runtime (`jibDockerBuild` serializes `Project`). In modulith-example and element-service-example, `just build` splits into two Gradle invocations — `build` with config cache, then `jibDockerBuild`/`containerBasedServiceTest` with `--no-configuration-cache`.

During `just update-workspace`, those service repos now skip the standalone `just build` entirely when no pulled commits or update-relevant file changes were produced for the repo.

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
| `sollecitom.kotlin-conventions` | Kotlin compiler options (JVM 25, context parameters, progressive) |
| `sollecitom.kotlin-library-conventions` | Composite: kotlin-jvm + java-library + idea + test + minimum-dependency-version + repositories + Java toolchain |

Submodules apply `plugins { id("sollecitom.kotlin-library-conventions") }`. No `buildSrc` or `allprojects` — each module is self-contained.

`gradle-plugins` intentionally keeps Kotlin `2.3.20` for now, even though Gradle emits the known `kotlin-dsl` compatibility warning. That warning is currently accepted noise.

## Security Scanning

Docker images built by Jib are scanned for vulnerabilities using Trivy (via Testcontainers). The `securityScan` task runs after `jibDockerBuild` in element-service-example and modulith-example.

- Trivy version and container image versions are managed in `swissknife/container-versions.properties`
- Update with `just update-container-versions` in swissknife
- Suppress accepted CVEs in `.trivyignore` per project
- Base Docker images are now digest-pinned through repo `gradle.properties` policy fields and refreshed by `just update-workspace`

## Architecture Patterns

- **DDD / Hexagonal Architecture** throughout
- **CQRS + Event Sourcing** in modulith-example, element-service-example, lattice
- **Apache Pulsar** for event streaming, **PostgreSQL** for persistence, **NATS** for sync request-reply
- **http4k** for HTTP

## Active Project: Lattice

Event-driven framework with pure aggregate functions, triage topic pattern, and Pulsar backbone. SDK API defined, in-memory implementation passing basic tests.
