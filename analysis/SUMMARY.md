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
- All consumers use `pluginManagement { includeBuild("../gradle-plugins") }` — no `buildSrc` or `publishToMavenLocal` needed
- All `allprojects`/`subprojects` blocks removed — each submodule declares its own `plugins { id("sollecitom.kotlin-library-conventions") }`
- All inter-project dependencies use `includeBuild` (swissknife, pillar, acme-schema-catalogue)
- Configuration cache enabled across all projects

## Documentation (Done)

- **Swissknife**: CONTEXT.md + ~94 module READMEs + KDoc across ~210 source files
- **Pillar**: CONTEXT.md + 36 module READMEs + KDoc across ~65 source files (domain model documented)
- **Gradle-plugins**: KDoc across all 16 convention plugin and utility files
- **Workspace root**: CONTEXT.md added

### Remaining
- Add CONTEXT.md to tools and other smaller projects
- Document architecture decision records (ADRs) for non-obvious choices (why Avro for some schemas, JSON for others; why Pulsar over NATS; why hexagonal)

## `update-workspace` Java Version Handling

The `update-workspace` command (in the root justfile) should attempt to upgrade to the latest available Java version, but avoid getting stuck in a loop when the toolchain isn't available yet. Proposed behavior:

1. **Before updating projects**, check if a newer Temurin JDK is available (e.g., via `brew info --cask temurin`).
2. **If a newer version is available**, attempt the upgrade. If it succeeds, update `JAVA_HOME`, the toolchain version in `gradle-plugins` (`Plugins.kt` and `KotlinTaskConventions.kt`), and the `build-logic` conventions in `backend-skeleton`.
3. **If the upgrade fails** (e.g., Gradle or Kotlin don't support the new JVM target yet), log `info "No compatible Java version available"` and continue with the current version.
4. **To avoid retrying on every run**, record the Gradle and Kotlin versions at the time the Java upgrade was last attempted in a marker file (e.g., `.java-upgrade-marker`). Skip the Java upgrade check until either the Gradle or Kotlin version changes.

This prevents the cycle where `update-workspace` upgrades Java, builds fail because the toolchain target isn't supported, and the next run tries again.

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

## Prioritized TODO List

### Bugs (from swissknife & pillar report)

1. **pillar: Unsafe email parsing** in `AcmeJwtScheme.kt:72` — ~~uses `single()` on split~~ **Fixed**: now uses `EmailAddress` value class for validation
2. **swissknife: Null assertion operators** in Topic.Namespace.parse() and Trie — `!!` can NPE
4. **pillar: Missing domain validation** — User (blank names), Access (empty roles), Token (expiry ordering), Authentication ACR values

### Improvements

5. **Add tests to gradle-plugins** — every project depends on it, breakage is silent
6. **Add schema validation to acme-schema-catalogue** — catch invalid schemas at build time
7. **pillar: Add integration tests for `web/api/utils`** — security-sensitive module with no tests
8. **pillar: Fix dependency direction** — `acme/business/domain` imports from conventions (should be reverse)
9. **pillar: Resolve Tenant/Customer/Organization confusion** — define clear multi-tenancy model
10. **Complete the modulith-example** — finish CQRS queries and OpenTelemetry tracing
11. **Extract repeated patterns** — null-assert, type-cast, serde templates into shared utilities
