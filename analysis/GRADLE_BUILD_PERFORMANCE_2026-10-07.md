# Gradle build performance deep dive (2026-10-07)

Machine: 11 CPUs, 36 GB RAM, Docker Desktop (11 CPUs, 23 GB). Gradle 9.8.0 everywhere (facts 9.7.1). All builds ran with
`JAVA_TOOL_OPTIONS` pointing the JVM at the sandbox proxy (needed for network access here); it adds a "Picked up
JAVA_TOOL_OPTIONS" line to every JVM and slightly slows network-bound steps (dependency/base-image checks), nothing else.

## Baseline

| Scenario | Wall | Notes |
|---|---|---|
| `just build-workspace` after code changes (partial reruns) | 646 s | user 1687 s; ~553 s inside Gradle, ~90 s scripts/JVM startup |
| `just build-workspace`, nothing changed, first run after publishes | 214 s | config cache misses (`currentVersion` changed by last publish; git HEAD changed for services) |
| `just build-workspace`, nothing changed, steady state | 80 s | 21 Gradle invocations, each a fresh JVM (`org.gradle.daemon=false`) |
| swissknife `clean build --rerun-tasks` | 122 s | compile-only (`-x test`) is 27–31 s → tests are ~90 s of it |

## Hotspots (ranked)

1. **Test JVM fan-out**: `maxParallelForks = 2 × CPUs` (22) per test task. ~100 test tasks per repo each forking up
   to 22 JVMs oversubscribes 11 cores; JVM startup and class loading dominate. Tests-only wall (`test --rerun`):

   | Repo | 22 forks | 4 forks | 2 forks | 1 fork |
   |---|---|---|---|---|
   | swissknife | 73 s | — | 47 s | 40 s |
   | pillar | 37 s | — | — | 17 s |
   | element | 84 s | — | — | 50 s |

   (compile + tests in swissknife: 100 s → 81 s with 4 forks → 69 s with 1 fork.) `--max-workers` 11/22/128 made no
   significant difference (±5 s noise).
2. **No Gradle daemon**: every one of the ~21 invocations per `build-workspace` boots a fresh JVM and cold Gradle.
3. **Container tests**: 7 Pulsar container starts per full workspace build (swissknife ×2, examples, modulith
   in-process, modulith containerised, element process-based, element container-based), each test class ~11–16 s,
   mostly broker startup; plus Postgres ×5, NATS ×1, Trivy ×3.
4. **Kotlin compilation**: largest single tasks (openapi-checking-checker 14–26 s, cryptography 9–23 s, correlation
   core 9–21 s); `kotlin.compiler.execution.strategy=in-process`.

## Changes

| Change | Before → after | Commit |
|---|---|---|
| Tests run in one JVM per test task (Gradle default) instead of 2×CPU forks (TestTaskConventions, BackendSkeletonKotlinJvmConventions) | tests-only: swissknife 73→40 s, pillar 37→17 s, element 84→50 s | gradle-plugins 44d34c3 |

## Proposals needing the owner
