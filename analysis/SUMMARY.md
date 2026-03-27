# Workspace Analysis Summary

## Context

This is a personal workspace. All libraries and projects are developed, built, and tested locally by a single developer. There are no external consumers or CI/CD pipelines publishing releases. Changes are made locally and everything is rebuilt and re-tested together.

This context means some common concerns (e.g., SNAPSHOT versioning, BOM modules, compatibility matrices) are not applicable here.

## Project Ratings

| Project | Build | Code | Tests | Docs | Freshness | Modularity | Overall |
|---------|-------|------|-------|------|-----------|------------|---------|
| element-service-example | A | A | A | A- | A | A+ | **A** |
| modulith-example | A | A | B+ | A- | A | A+ | **A-** |
| swissknife | A | A | B- | D+ | A | A+ | **B+** |
| pillar | A | A | A- | D | A | A | **B+** |
| backend-skeleton | A+ | N/A | B | A | A | A | **B+** |
| examples | A | B | A- | B+ | A | B | **B** |
| gradle-plugins | A | B+ | F | C+ | A | A | **B-** |
| acme-schema-catalogue | A | B | F | C | A | A | **B-** |
| tools | A | B+ | F | C | A | A | **C+** |
| facts | A | N/A | D | A- | A | B+ | **C+** |

## Cross-Cutting Strengths
- All projects on Gradle 9.4.0 and Kotlin 2.3.10 (latest)
- Consistent build conventions across the workspace
- Strong DDD and hexagonal architecture patterns
- Modern Kotlin usage (value classes, sealed hierarchies, coroutines, context parameters)
- Clean module separation with no circular dependencies

## Cross-Cutting Weaknesses

| Issue | Affected Projects | Impact |
|-------|-------------------|--------|
| Documentation gaps | swissknife, pillar, gradle-plugins, tools | Onboarding difficulty for future-self and AI agents |
| Zero tests | gradle-plugins, acme-schema-catalogue, tools | Silent regressions |
| Configuration cache disabled | All except backend-skeleton | Slower builds on every rebuild |
| No distributed tracing | modulith-example, element-service-example | Observability gap |
| gradle-plugins consumers still use `apply<Class>()` | All legacy consumers | Consumers could migrate to `plugins { id("sollecitom.xyz") }` and `includeBuild` for faster iteration |

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
- Plugin IDs are registered and published to mavenLocal
- Backward compatible — existing `apply<ClassName>()` usage still works
- Consumers can incrementally migrate to `plugins { id("sollecitom.xyz") }` and `includeBuild`

### Remaining steps
- Migrate consumers from `apply<Class>()` to `plugins { id("sollecitom.xyz") }`
- Switch consumers from `buildscript { classpath }` to `includeBuild` for live source changes without `publishToMavenLocal`
- Enable configuration cache in consumer projects once migrated

## Documentation Gaps

Documentation matters even in a personal workspace for two reasons:

1. **Future-self** — modules like swissknife (98 modules, 3-line README) and pillar (36 modules, 2-line README) will become harder to navigate as they grow. Domain concepts (Tenant, Customer, Actor, Facts) need explanation.

2. **AI agent context** — AI coding assistants (Claude, Copilot, etc.) operate far more effectively when projects provide clear context: what a module does, why it exists, what patterns it follows, and what constraints apply. Without this, agents must reverse-engineer intent from code, which is slow and error-prone.

### Recommended actions

- Add a `CLAUDE.md` or `CONTEXT.md` to each project root explaining purpose, architecture, key patterns, and constraints
- Add module-level READMEs to swissknife and pillar (even one-liners per module help agents navigate)
- Document the Acme domain model (what is a Tenant, Customer, Actor?) — this is domain knowledge that can't be inferred from code
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

## Top 5 High-Impact Improvements

1. **Enable configuration cache** — you rebuild constantly; this saves real time. gradle-plugins now has proper plugin IDs; next step is migrating consumers to `plugins { id() }` + `includeBuild`
2. **Add tests to gradle-plugins** — every project depends on it, breakage is silent
3. **Add schema validation to acme-schema-catalogue** — catch invalid schemas at build time instead of at runtime
4. **Improve documentation for AI agent context** — add CONTEXT.md / CLAUDE.md files and module READMEs to swissknife and pillar
5. **Complete the modulith-example** — finish CQRS queries and OpenTelemetry tracing to make it a complete reference architecture
