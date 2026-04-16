# Workspace Analysis Summary

## Context

This is a personal workspace. All libraries and projects are developed, built, and tested locally by a single developer. There are no external consumers or CI/CD pipelines publishing releases. Changes are made locally and everything is rebuilt and re-tested together.

This context means some common concerns (e.g., SNAPSHOT versioning, BOM modules, compatibility matrices) are not applicable here.

## Project Ratings

| Project | Build | Code | Tests | Docs | Freshness | Modularity | Overall |
|---------|-------|------|-------|------|-----------|------------|---------|
| element-service-example | A | A | A | A- | A | A+ | **A** |
| modulith-example | A | A | B+ | A- | A | A+ | **A-** |
| swissknife | A | A | B+ | A | A | A+ | **A** |
| pillar | A | A | B+ | A- | A | A | **A-** |
| backend-skeleton | A+ | N/A | B | A | A | A | **B+** |
| examples | A | B | A- | B+ | A | B | **B** |
| gradle-plugins | A | B+ | F | B+ | A | A | **B** |
| acme-schema-catalogue | A | B | F | C | A | A | **B-** |
| tools | A | B+ | F | C | A | A | **C+** |
| facts | A | N/A | D | A- | A | B+ | **C+** |

## Cross-Cutting Strengths
- All projects on Gradle 9.4.1 and Kotlin 2.3.20 (latest)
- Consistent build conventions across the workspace
- Strong DDD and hexagonal architecture patterns
- Modern Kotlin usage (value classes, sealed hierarchies, coroutines, context parameters)
- Clean module separation with no circular dependencies

## Cross-Cutting Weaknesses

| Issue | Affected Projects | Impact |
|-------|-------------------|--------|
| Documentation gaps | tools | Onboarding difficulty for future-self and AI agents (swissknife, pillar, and gradle-plugins now documented with KDoc, READMEs, and CONTEXT.md) |
| Zero tests | gradle-plugins, acme-schema-catalogue, tools | Silent regressions (swissknife and pillar test gaps addressed) |
| No distributed tracing | modulith-example, element-service-example | Observability gap |

## gradle-plugins: Proper Plugins (Done)

Gradle-plugins now registers proper plugin IDs via `gradlePlugin { plugins { } }` blocks. The `com.github.ben-manes.versions` dependency was removed — `nl.littlerobots.version-catalog-update` (1.1.0) handles version resolution standalone, with `VersionSelectors.PREFER_STABLE` as the default.

### Registered Plugin IDs

| Plugin ID | Implementation Class |
|-----------|---------------------|
| `sollecitom.dependency-update-conventions` | `DependencyUpdateConvention` |
| `sollecitom.minimum-dependency-version-conventions` | `MinimumDependencyVersionConventions` |
| `sollecitom.test-conventions` | `TestTaskConventions` |
| `sollecitom.aggregate-test-metrics-conventions` | `AggregateTestMetricsConventions` |
| `sollecitom.maven-publish-conventions` | `MavenPublishConvention` |
| `sollecitom.jib-docker-build-conventions` | `JibDockerBuildConvention` |
| `sollecitom.container-based-service-test-conventions` | `ContainerBasedServiceTestConvention` |
| `sollecitom.kotlin-conventions` | `KotlinTaskConventions` |

### Current state
- Plugin IDs are registered, including composite `sollecitom.kotlin-library-conventions`
- Normal repos now consume `gradle-plugins` by explicit published version from `mavenLocal()` rather than `includeBuild("../gradle-plugins")`
- Internal producer repos publish explicit non-`SNAPSHOT` versions, and the workspace uses an internal-only updater plus normal `versionCatalogUpdate` for the full path
- All `allprojects`/`subprojects` blocks removed — each submodule declares its own `plugins { id("sollecitom.kotlin-library-conventions") }`
- Configuration cache enabled across all projects, with known third-party limitations still present for `versionCatalogUpdate`

## Documentation (Done)

- **Swissknife**: CONTEXT.md + ~94 module READMEs + KDoc across ~210 source files
- **Pillar**: CONTEXT.md + 36 module READMEs + KDoc across ~65 source files (domain model documented)
- **Gradle-plugins**: KDoc across all 16 convention plugin and utility files
- **Workspace root**: CONTEXT.md added

### Remaining
- Add CONTEXT.md to tools and other smaller projects
- Document architecture decision records (ADRs) for non-obvious choices (why Avro for some schemas, JSON for others; why Pulsar over NATS; why hexagonal)

## `update-workspace` Java Version Handling

The `update-workspace` command now manages workspace prerequisites centrally and upgrades only the targeted Temurin package through Homebrew rather than doing a general Homebrew update.

Current behavior:

1. Ensure `just`, `jq`, and Temurin are installed from the workspace layer.
2. Upgrade only the `temurin` cask, with Homebrew auto-update and cleanup noise suppressed.
3. Keep machine-level JDK mutation out of individual repos.
4. Leave toolchain source changes explicit rather than silently rewriting repo code during a workspace update.

## Test Container Version Drift

Test container image versions in swissknife are hardcoded constants that can drift from the library versions in `libs.versions.toml`. The affected constants are:

| Container | Constant location | Version catalog key |
|-----------|-------------------|---------------------|
| Pulsar | `pulsar/test/utils/.../PulsarContainerExtensions.kt` → `DEFAULT_PULSAR_DOCKER_IMAGE_VERSION` | `pulsar` |
| Keycloak | `keycloak/container/.../Keycloak.kt` → `defaultImageVersion` | `keycloak` |
| Postgres | `sql/postgres/container/.../PostgresContainer.kt` → `defaultImageVersion` | `postgres` (JDBC driver, not server — use major version) |

After running `versionCatalogUpdate`, these constants need manual updating to match. Options to automate:

1. **Build-time generation** — a Gradle task writes library versions from the catalog into a `container-versions.properties` resource file, read at runtime. Eliminates drift entirely but adds build complexity.
2. **Lint check** — a script or Gradle task that compares `libs.versions.toml` entries against the hardcoded constants and fails/warns on mismatch. Simpler, catches drift at build time.
3. **Manual** (current) — update the 3 constants when `versionCatalogUpdate` bumps Pulsar, Keycloak, or Postgres.

## Configuration Cache (Done)

Enabled across all 11 projects (`org.gradle.configuration-cache=true`). Palantir Git Version 5.0.0 and Jib 3.5.3 are both compatible — the original blockers were outdated.

**Jib caveat**: `jibDockerBuild` tasks fail at runtime with configuration cache because Jib serializes `Project`. In modulith-example and element-service-example, `just build` splits into two Gradle invocations — `build` with config cache, then `jibDockerBuild`/`containerBasedServiceTest` with `--no-configuration-cache`.

## Security Scanning (Done)

Docker image vulnerability scanning via Trivy integrated into element-service-example and modulith-example:
- `sollecitom.security-scan-conventions` plugin creates `securityScan` task
- Trivy runs as a container via Testcontainers — no host installation needed
- `assertThatImage(name).hasNoUnacceptableVulnerabilities()` assertion
- CVE-2025-24970 (netty-handler) fixed via minimum version enforcement
- Base image switched from Alpine to Ubuntu Noble for faster security patches
- Container versions centralized in `swissknife/container-versions.properties` with `just update-container-versions`

## Container Image Update Reporting

- Shared Docker base image changes are reported from repo-owned files such as `gradle.properties` and `Dockerfile`
- Repo-local container image automation can emit extra summary lines back to the workspace runner through an event-file contract
- `swissknife` is currently the only repo using that repo-local image-update path
- `pillar` uses `eclipse-temurin:25-jre-noble` as its explicit external base image but does not define its own concrete external test container image versions

## Prioritized TODO List

### Bugs (from swissknife & pillar report)

1. ~~**pillar: Unsafe email parsing**~~ — **Fixed**: uses `EmailAddress` value class
2. **swissknife: Null assertion operators** in Topic.Namespace.parse() and Trie — `!!` can NPE
3. **pillar: Missing domain validation** — User (blank names), Access (empty roles), Token (expiry ordering), Authentication ACR values

### Improvements

4. **Add tests to gradle-plugins** — every project depends on it, breakage is silent
5. **Add schema validation to acme-schema-catalogue** — catch invalid schemas at build time
6. **pillar: Add integration tests for `web/api/utils`** — security-sensitive module with no tests
7. **pillar: Fix dependency direction** — `acme/business/domain` imports from conventions (should be reverse)
8. **pillar: Resolve Tenant/Customer/Organization confusion** — define clear multi-tenancy model
9. **Complete the modulith-example** — finish CQRS queries and OpenTelemetry tracing
10. **Extract repeated patterns** — null-assert, type-cast, serde templates into shared utilities
