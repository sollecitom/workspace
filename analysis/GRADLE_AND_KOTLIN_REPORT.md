# Gradle & Kotlin Usage Report

An in-depth analysis of how Gradle and Kotlin are used across the workspace, compared against modern best practices (Gradle 9.x, Kotlin 2.3.x, 2025/2026 conventions).

## Executive Summary

The workspace is on latest-or-near-latest versions of Gradle (9.4.1), Kotlin (2.3.20), and JDK (25). Configuration cache and build cache are enabled. Convention plugins are registered with proper IDs and all inter-project dependencies use `includeBuild`. These are strong foundations.

However, 10 of 11 projects follow a **legacy build pattern** (buildSrc + `allprojects`/`subprojects` + `afterEvaluate` + imperative configuration) that predates the **precompiled script plugin** pattern already proven in backend-skeleton. This legacy pattern causes unnecessary configuration overhead, blocks further Gradle optimizations, and makes the build harder to reason about.

---

## 1. Build Structure: buildSrc vs build-logic

### Current State

| Pattern | Projects |
|---------|----------|
| `buildSrc` + imperative `apply<Plugin>()` | All except backend-skeleton (10 projects) |
| `build-logic` + precompiled script plugins | backend-skeleton only |

### The Problem with buildSrc

The legacy projects use `buildSrc` in a non-standard way:

1. **buildSrc as a classpath bridge, not as convention plugins**. Each project's `buildSrc/build.gradle.kts` pulls in `gradle-plugins` jars via `buildscript { classpath }`, then the root `build.gradle.kts` imperatively applies conventions using `apply(plugin = "...")`. This is a workaround from before gradle-plugins had proper plugin IDs.

2. **buildSrc is rebuilt on every settings change**. Any change to `buildSrc/settings.gradle.kts` (which now has `includeBuild`) invalidates the entire buildSrc compilation. This is a known Gradle limitation — buildSrc is compiled before the main build, so changes cascade.

3. **No convention logic lives in buildSrc**. The buildSrc directories contain zero convention plugins — they're purely classpath shims. All actual convention logic lives in gradle-plugins.

### Best Practice: Precompiled Script Plugins in build-logic

Backend-skeleton demonstrates the modern approach:

```
settings.gradle.kts:
  pluginManagement { includeBuild("build-logic") }

build-logic/src/main/kotlin/sollecitom.kotlin-jvm-conventions.gradle.kts
  → applied via: plugins { id("sollecitom.kotlin-jvm-conventions") }
```

Benefits:
- **No buildSrc at all** — eliminates the buildSrc rebuild penalty
- **Declarative `plugins { }` block** — type-safe, IDE-friendly, cacheable
- **Self-contained** — each project carries its conventions (or shares via `includeBuild`)
- **Configuration cache friendly** — no `afterEvaluate`, no imperative `apply`

### Recommendation

The legacy projects don't need their own `build-logic` — they share gradle-plugins. The improvement would be:
1. Remove `buildSrc` from all legacy projects
2. Add `pluginManagement { includeBuild("../gradle-plugins") }` to each project's `settings.gradle.kts`
3. Move from `apply(plugin = "...")` in the build script to `plugins { id("sollecitom.xyz") }` in subproject build scripts
4. This requires converting the `allprojects { }` pattern first (see section 2)

---

## 2. allprojects/subprojects: Cross-Project Configuration

### Current State

All legacy projects use `allprojects { }` and nested `subprojects { }` blocks to configure every module from the root `build.gradle.kts`. This is a **Gradle anti-pattern** that has been discouraged since Gradle 7.

```kotlin
// Current pattern (every legacy project)
allprojects {
    apply(plugin = "sollecitom.kotlin-conventions")
    apply(plugin = "sollecitom.test-conventions")
    // ...
    subprojects {
        apply {
            plugin("org.jetbrains.kotlin.jvm")
            plugin<JavaLibraryPlugin>()
        }
    }
}
```

### Why This Is a Problem

1. **Couples all modules to the root project**. Every module is configured identically regardless of its purpose. A test utilities module gets the same configuration as a domain model module.

2. **Breaks project isolation**. Gradle's project isolation feature (planned to become the default) requires that projects don't configure each other. `allprojects`/`subprojects` violates this by definition.

3. **Blocks `configure on demand`**. Despite `org.gradle.configureondemand=true` being set everywhere, it has **no effect** when `allprojects { }` is used, because Gradle must evaluate the root project (which configures all projects) to determine the task graph.

4. **Configuration cache stores redundant state**. Each subproject's configuration is a copy of the root's `allprojects` block, serialized separately.

### Best Practice: Convention Plugins per Module

Backend-skeleton's approach — each module applies its own plugins:

```kotlin
// modules/my-feature/domain/build.gradle.kts
plugins {
    id("sollecitom.kotlin-jvm-conventions")
}

dependencies {
    // only what this module needs
}
```

No root-level cross-project configuration. Each module is self-describing.

### Recommendation

1. Create a composite convention plugin (e.g., `sollecitom.library-conventions`) that bundles kotlin-conventions + test-conventions + maven-publish-conventions + minimum-dependency-version-conventions
2. Apply it in each subproject's `build.gradle.kts` via `plugins { id("sollecitom.library-conventions") }`
3. Remove `allprojects { }` and `subprojects { }` from all root build scripts
4. Move repository configuration into the convention plugin

---

## 3. afterEvaluate Usage

### Current State

5 of 8 convention plugins in gradle-plugins use `afterEvaluate`:

| Convention | Uses afterEvaluate |
|------------|:-:|
| DependencyUpdateConvention | Yes |
| MinimumDependencyVersionConventions | Yes |
| MavenPublishConvention | Yes |
| JibDockerBuildConvention | Yes |
| ContainerBasedServiceTestConvention | Yes |
| TestTaskConventions | No |
| AggregateTestMetricsConventions | No |
| KotlinTaskConventions | No |

### Why This Is a Problem

`afterEvaluate` is a **Gradle anti-pattern** since Gradle 6:

1. **Non-deterministic ordering**. Multiple `afterEvaluate` blocks execute in registration order, not dependency order. If plugin A depends on configuration from plugin B, and both use `afterEvaluate`, the result depends on which was applied first.

2. **Configuration cache incompatibility**. `afterEvaluate` closures capture mutable project state. While Gradle currently handles this, future Gradle versions are tightening restrictions.

3. **Breaks lazy configuration**. Gradle's provider/property API (`Property<T>`, `Provider<T>`) is designed to defer resolution until task execution. `afterEvaluate` eagerly resolves values at configuration time, defeating the purpose of lazy evaluation.

### Best Practice: Lazy Configuration with Providers

Instead of:
```kotlin
afterEvaluate {
    tasks.withType<DependencyUpdatesTask> {
        checkConstraints = extension.check.constraints.getOrElse(true)
    }
}
```

Use:
```kotlin
tasks.withType<DependencyUpdatesTask>().configureEach {
    checkConstraints = extension.check.constraints.getOrElse(true)
}
```

Convention plugin extensions should use `Property<T>` (they already do), and task configuration should use `.configureEach { }` (lazy) instead of `.all { }` (eager) or `afterEvaluate`.

### Recommendation

Audit each convention plugin and remove `afterEvaluate` in favor of lazy task configuration. The simplified DependencyUpdateConvention we created earlier already demonstrates this partially.

---

## 4. gradle.properties Issues

### Invalid Property Format

All legacy projects have lines starting with `-D`:

```properties
-Dkotlin.compiler.execution.strategy=in-process
-Dkotlin.incremental=false
```

These are **not valid `gradle.properties` entries**. The `-D` prefix is for JVM system properties passed on the command line, not for properties files. In `gradle.properties`, Gradle silently ignores invalid keys. These settings are likely **not taking effect**.

The correct format is:
```properties
kotlin.compiler.execution.strategy=in-process
kotlin.incremental=false
```

### Kotlin Incremental Compilation Disabled

All projects set `kotlin.incremental=false`. This means every Kotlin compilation recompiles all sources from scratch. For large projects like swissknife (98 modules), this significantly increases build time.

Kotlin incremental compilation has been stable since Kotlin 1.7. Unless there's a specific reproducibility issue, it should be enabled:
```properties
kotlin.incremental=true
```

### Kotlin In-Process Compilation

All projects set `kotlin.compiler.execution.strategy=in-process`. This runs the Kotlin compiler inside the Gradle JVM rather than in a separate daemon. Trade-offs:

| | In-Process | Daemon (default) |
|---|---|---|
| Startup time | No startup cost | ~1-2s per new daemon |
| Memory | Shares Gradle's heap | Separate heap |
| Stability | Compiler crash = Gradle crash | Compiler crash is isolated |
| Build cache | Works | Works |

For a single-developer workspace with `org.gradle.daemon=false`, in-process makes sense (no daemon to reuse). But since the `-D` prefix makes this setting likely not take effect, the actual strategy is probably the default (daemon).

### Wrong projectGroup in facts

`facts/gradle.properties` has:
```properties
projectGroup=sollecitom.element-service-example
```
This should be `sollecitom.facts`.

### Recommendation

1. Remove `-D` prefix from all properties — use `kotlin.compiler.execution.strategy=in-process` and `kotlin.incremental=false`
2. Consider enabling `kotlin.incremental=true` for faster rebuilds
3. Fix facts' `projectGroup`

---

## 5. Version Catalog Usage

### Current State

All projects use `gradle/libs.versions.toml` — this is best practice. However:

1. **No bundles defined**. Version catalogs support `[bundles]` for grouping commonly-used dependencies (e.g., `junit = ["junit-jupiter-api", "junit-jupiter-params", "assertk"]`). No project uses bundles.

2. **Duplicate Kotlin version declarations**. Every project declares `kotlin = "2.3.20"` in its own catalog AND gets Kotlin via the gradle-plugins classpath. With `includeBuild`, the version from gradle-plugins' `KotlinTaskConventions` (which sets `JvmTarget.JVM_25`) is authoritative. The per-project Kotlin version in the catalog is used for the `kotlin-jvm` plugin in buildSrc — a second, potentially conflicting, version source.

3. **No version catalog sharing**. Each project maintains its own `libs.versions.toml`. Common dependencies (JUnit, AssertK, kotlinx-coroutines) are duplicated across catalogs with potentially different versions. A shared catalog or a BOM would reduce drift.

### Recommendation

1. Add `[bundles]` for common dependency groups (testing, serialization, etc.)
2. Consider a shared version catalog published from swissknife or a dedicated project
3. Remove redundant Kotlin version from catalogs where it's only used by buildSrc (would be resolved by eliminating buildSrc)

---

## 6. Kotlin Language Usage

### Strengths

- **Modern Kotlin features**: context parameters, value classes (25 files), sealed hierarchies (35 files), coroutines (54 files)
- **Progressive mode** enabled — catches upcoming deprecations early
- **`-Xjsr305=strict`** — proper nullability from Java interop
- **JVM 25 target** — latest available

### Observations

1. **Context parameters are experimental** (`-Xcontext-parameters`). Used in 5+ files in pillar. This is a good bet — context parameters are on the Kotlin roadmap for stabilization — but it's worth tracking when they become stable to remove the opt-in.

2. **`companion object` is heavily used** (199 files). In many cases, these serve as factory functions or constants. For factories, top-level functions or `operator fun invoke` on the companion are idiomatic. Not a problem per se, but worth noting.

3. **No explicit API mode**. Backend-skeleton's CONTEXT.md explicitly rejects `-Xexplicit-api`. This is a reasonable choice for a personal workspace — explicit API mode is primarily valuable for published libraries with external consumers.

4. **`@OptIn(ExperimentalTime::class)`** is still globally applied via compiler args. `kotlin.time` has been stable since Kotlin 1.9. This opt-in can be removed.

---

## 7. Testing Configuration

### Current State

- JUnit 5 (Jupiter) + AssertK — modern and appropriate
- Parallel test execution (2x CPU cores locally, 1 fork in CI)
- Test reports centralized under `build/test-results/`
- `TestMetricsBuildService` aggregates test counts across modules

### Observations

1. **No test fixtures**. Gradle's `java-test-fixtures` plugin allows sharing test utilities between modules without publishing them as a separate module. The workspace instead creates explicit `*-test-utils` modules (e.g., `swissknife:core-test-utils`). Both approaches work, but test fixtures reduce module count.

2. **No JUnit `@Nested` or `@DisplayName`** conventions visible. Not a problem, but Kotlin's backtick-quoted test names (`` `should do something` ``) are more idiomatic than Java-style `testShouldDoSomething`.

3. **Test containers versions are hardcoded** (noted in SUMMARY.md). The version catalog has the library versions, but the container image versions are string constants in Kotlin source.

---

## 8. Dependency Management

### Current State

- Internal dependencies resolved via `includeBuild` — excellent
- External dependencies from mavenCentral
- Internal group `sollecitom.*` routed to mavenLocal (fallback)
- Minimum dependency version enforcement for known CVEs (commons-compress)

### Observations

1. **No dependency locking**. Gradle supports dependency locking (`dependencyLocking { lockAllConfigurations() }`) to ensure reproducible builds. Without it, SNAPSHOT dependencies or version ranges can resolve differently across machines. Not critical for a single-developer workspace, but would matter if CI is added.

2. **`api` vs `implementation` separation is good** in swissknife and pillar. Library modules properly expose `api` dependencies that are part of their public API and keep internal ones as `implementation`.

3. **No dependency constraints or platforms for alignment**. When multiple modules depend on different versions of the same library (e.g., Jackson), Gradle's `platform()` or `constraints { }` can enforce consistent versions. Currently, the `MinimumDependencyVersionConventions` convention handles this partially via `resolutionStrategy`, but a Gradle platform would be more standard.

---

## 9. Gradle Wrapper

### Current State

- All projects on Gradle 9.4.1 — latest
- Distribution type: `all` (includes sources — good for IDE support)
- **No `distributionSha256Sum`** in any project

### Recommendation

Add `distributionSha256Sum` to `gradle-wrapper.properties` for supply-chain security. This ensures the Gradle distribution hasn't been tampered with:

```properties
distributionSha256Sum=<hash>
```

The `just update-gradle` recipe could automatically fetch and set this.

---

## 10. Configuration on Demand

### Current State

All projects set `org.gradle.configureondemand=true`.

### The Problem

Configuration on demand is **effectively broken** when combined with `allprojects { }` or `subprojects { }` (see section 2). Gradle must evaluate the root project to apply cross-project configuration, which means all projects get configured regardless.

Configuration on demand also has known issues with `includeBuild` — Gradle may skip configuring included builds that are needed for dependency substitution.

### Recommendation

Either:
1. Remove `org.gradle.configureondemand=true` (it's not helping and may cause subtle issues with `includeBuild`)
2. Or migrate away from `allprojects { }` first, then configuration on demand will actually work

---

## 11. Summary: backend-skeleton vs Legacy Projects

Backend-skeleton represents the target state. Here's how it compares:

| Aspect | backend-skeleton | Legacy projects (10) |
|--------|:---:|:---:|
| Build conventions | `build-logic/` precompiled script plugins | `buildSrc` classpath shim |
| Plugin application | `plugins { id("...") }` in each module | `allprojects { apply(...) }` in root |
| Cross-project config | None (each module self-contained) | `allprojects { }` + `subprojects { }` |
| `afterEvaluate` | Not used | Used by 5 conventions |
| `buildSrc` | None | Present (empty — only classpath) |
| Configuration on demand | Works | Broken (due to `allprojects`) |
| `kotlin.incremental` | Not set (default: true) | ~~Explicitly false~~ Fixed: now true |
| Property format | Correct | ~~Invalid `-D` prefix~~ Fixed |

---

## Priority Improvements

Ordered by recommended execution sequence:

| # | Improvement | Effort | Status |
|---|-------------|--------|--------|
| ~~1~~ | ~~Fix `-D` prefix in `gradle.properties`~~ | ~~Trivial~~ | **Done** |
| ~~2~~ | ~~Fix facts `projectGroup`~~ | ~~Trivial~~ | **Done** |
| ~~3~~ | ~~Remove `kotlin.time.ExperimentalTime` opt-in~~ | ~~Trivial~~ | **Done** |
| ~~4~~ | ~~Enable `kotlin.incremental=true`~~ | ~~Trivial~~ | **Done** |
| ~~5~~ | ~~Remove `org.gradle.configureondemand=true`~~ | ~~Low~~ | **Done** |
| ~~6~~ | ~~Remove `afterEvaluate` from convention plugins~~ | ~~Medium~~ | **Done** (4 of 5 removed; Jib kept with comment — Jib's API uses plain Strings, not Gradle Properties) |
| ~~7~~ | ~~Add Gradle wrapper SHA-256 checksum~~ | ~~Low~~ | **Done** |
| 8 | Add `[bundles]` to version catalogs | Low | |
| 9 | Replace `allprojects`/`subprojects` with per-module `plugins { }` blocks | High | |
| 10 | Eliminate `buildSrc` — use `pluginManagement { includeBuild }` | Medium | |

Notes on remaining items:
- **#8** is independent and can be done any time — reduces dependency boilerplate in submodule build files
- **#9** is the big structural change — each submodule declares its own plugins, enabling project isolation and proper configure-on-demand
- **#10** falls out naturally from #9 — once submodules declare their own plugins, `buildSrc` is no longer needed as a classpath bridge
