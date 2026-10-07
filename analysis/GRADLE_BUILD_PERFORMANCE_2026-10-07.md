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
| Test JVMs run with `-XX:TieredStopAtLevel=1 -XX:+UseSerialGC` (JvmConfiguration.testArgs) | tests-only, two runs each: pillar 16.8→14.0 s, swissknife ~40→~37 s, element ~50→~47.5 s | gradle-plugins a7f1bc8 |
| element service tests start Postgres (and run migrations) concurrently with Pulsar | ProcessBasedServiceTests 24.5→22.4 s; same spec drives ContainerBasedServiceTests | element 6bc3827 |

Intermediate measurement: the first `build-workspace` after the fork change reran every test in the workspace
(plugin classpath changed) and took 305 s, against 646 s for the baseline run that reran tests only in the repos with
code changes.

## Final numbers

| Scenario | Before | After |
|---|---|---|
| Tests only (`test --rerun`), swissknife / pillar / element | 73 / 37 / 84 s | ~37 / 14 / 47.5 s (≈95 s less whenever those suites rerun) |
| `build-workspace` rerunning every test after a plugin change | — (baseline run reran tests only where code changed: 646 s) | 305 s |
| Final `build-workspace` (green; mix of reruns and cache hits) | — | 295 s |
| `build-workspace`, nothing changed, first run after publishes | 214 s | 150 s |
| `build-workspace`, nothing changed, steady state | 80 s | 77 s (25 s with proposal 1) |

The baseline 646 s and the later runs are not the same workload (different sets of tasks reran), so the per-suite A/B
numbers above are the reliable comparison.

## Measured but not changed

- `--max-workers` 11 / 22 / 128 (configured): within noise once tests use one fork per task.
- Kotlin daemon vs in-process compilation (swissknife `clean build -x test`): warm Kotlin daemon 26.8 s vs in-process
  30.9 s (cold daemon 37.6 s). ~4 s per full compile, only when the daemon is warm; see proposals.
- Pulsar standalone itself is ready in ~4.7 s (admin endpoint); the remaining ~6–10 s per Pulsar test class is
  Testcontainers/Ryuk startup, topic setup and the tests. No real sleeps on hot paths: the only real-time delay found
  in tests is a 1 s `delay` in modulith's SendPaymentCommandEndpointHttpTestSpecification (others run on virtual time).
- `update-internal-catalog-versions.sh`: 0.06 s. Publication-state check regenerates POM/module metadata every time
  (Gradle never treats those as up to date): ~2–6 s per publishable repo.
- No-change `jibDockerBuild`: always reruns (Jib declares no outputs): ~5–6 s wall per service repo.

## Proposals needing the owner

1. **Turn the Gradle daemon on** (`org.gradle.daemon=false` in every repo since the first commit, no recorded reason).
   No-change `build-workspace`: 80 s → 25 s (33 s on the first run, including daemon start). In full builds it removes
   ~2–3 s of JVM/Gradle boot from each of the ~21 invocations and keeps the in-process Kotlin compiler warm.
   Risk seen during this dive: a daemon started earlier from a sandboxed process was reused by a later build and its
   child processes could not exec `docker` (Jib failed). Daemons are shared by any compatible build on the machine, so
   sandboxed agent builds and terminal builds would share daemons. Mitigations: keep it off for agents
   (`--no-daemon`), or run `./gradlew --stop` when switching environments. Memory: one 4 GB daemon per compatible JVM
   config (lattice's `-Djava.net.preferIPv4Stack` makes it a second one), idle-expiring after 3 h.
2. **Testcontainers reuse for Pulsar/Postgres in local builds** (`withReuse(true)` plus
   `testcontainers.reuse.enable=true` in `~/.testcontainers.properties`): 7 Pulsar starts per full workspace build
   would become 1, saving ~5–8 s on each critical path that starts one (examples, modulith ×2, element ×2, swissknife):
   roughly 20–30 s wall per full `build-workspace`. Trade-off: reused containers outlive the build (not reaped by
   Ryuk), state persists between runs (tests already use random topic names), and container config must be identical
   to match. Would live in swissknife's pulsar/postgres test-utils.
3. **[TRIED AND REVERTED, gradle-plugins 799a780 reverted by 3ef2b2f: ~3.5 s per service repo, not worth the complexity]** **Skip `jibDockerBuild` when the image fingerprint is unchanged and the image is present** (declare the fingerprint
   as input and an up-to-date check that the image exists): ~5–6 s per service repo per no-change build (~10–12 s per
   `build-workspace`). Needs care with `cleanup-docker-images.sh` and pruned images.
4. **Duplicate Pulsar coverage**: examples' `PulsarMessagingTests` implements swissknife's `MessagingTestSpecification`
   (the wrapper-types round trip that swissknife's own `PulsarMessagingTests` already runs), plus two Avro/converter
   tests of its own. Its container start is the whole examples test time (~11–12 s). Options: keep (examples document
   usage), or drop the spec implementation from examples and keep only its two Avro tests (saves no container start,
   since those two still need Pulsar) — so the saving is small; recommendation: keep.
5. **Kotlin compile daemon** (`kotlin.compiler.execution.strategy=daemon`): ~4 s per full repo compile when warm; only
   worth it together with (1) or if the Kotlin daemon is allowed to stay alive between builds.
6. **Within-JVM JUnit parallelism** (`junit.jupiter.execution.parallel.enabled`): not tried; many tests capture stdout
   (`withCapturedStandardOutput`) or share static state, so it would risk flakiness for a few seconds.
7. modulith's 1 s real `delay` in the send-payment contract test could be shortened (cosmetic, ~1 s).

## Follow-up: C1 flag removed, JUnit parallel classes (2026-10-07)

- Removed `-XX:TieredStopAtLevel=1` from test JVMs (gradle-plugins 0272c0e; `-XX:+UseSerialGC` kept): C1-only could hide data races the production C2 compiler exposes.
- JUnit Jupiter parallel execution enabled once in `TestTaskConventions` (gradle-plugins 5477c62): test classes run concurrently, methods of a class stay on one thread.
  - Methods-concurrent was also tried: green 3/3 in every repo, but no faster than classes-only, and most test classes use `@TestInstance(PER_CLASS)` with shared fields — so classes-only.
- Concurrency failures found: one, a REAL BUG. Avro schema catalogue objects initialised `all`/`nestedContainers` eagerly from other catalogues' lazies, so two threads touching two catalogues first could deadlock on JVM class initialisation (seen in element; same pattern in pillar, modulith, examples). Fixed by making `all`/`nestedContainers` getters (no cross-object work during object init) and dropping the redundant empty `nestedContainers` overrides: pillar 1.0.36, element a022112, modulith ab31658, examples a80d80c. Production services can hit this too: the first concurrent messages/requests touching different serdes.
- No test-only global-mutation failures surfaced in 3 reruns per suite (every repo, lattice included), so no test rewrites or `@Isolated` were needed.

Tests-only (`test --rerun`, warm, serial without C1 flag → classes-concurrent, median of 3):

| Suite | Serial | Parallel classes |
|---|---|---|
| swissknife | 46s | 31s |
| pillar | 15s | 10s |
| element | 46s | 40s |
| modulith | — | 21s |
| examples | — | 10–11s |

Full `just build-workspace`: 315s (green, all container tests and scans), vs 295s before (that run had C1-only JVMs and more cache hits; 377s for the run before this follow-up).

## Follow-up: Jib skip (reverted) and the modulith delay (done)

- Jib (gradle-plugins 799a780, published 1.0.46): every Jib image gets a `sollecitom.image.fingerprint` label with the `writeJibImageFingerprint` output (all Jib tasks depend on that task); `jibDockerBuild` has an `onlyIf` that runs `docker image inspect` on the image and every tag, and skips only when all exist with the same label. Works with the `--no-configuration-cache` Jib invocation.
  - Verified on element and modulith: no-change `just build` → `jibDockerBuild SKIPPED`, container tests and scans UP-TO-DATE against the existing image; a source change → rebuild; deleting the image → rebuild (only that image).
  - Saving: element no-change `just build` 15.0s → 11.5s (two images); modulith similar for one image. No-change `build-workspace` 77s → 71s. Smaller than the ~5–6s per repo estimated: Jib's exploded, reproducible layers are already cheap once cached.
  - Note: any upstream bump changes the runtime classpath, so the fingerprint changes and Jib rebuilds, as it should.
  - Reverted (gradle-plugins 3ef2b2f) at the owner's request: ~3.5 s per service repo isn't worth the extra convention complexity.
- modulith contract test (1d91815): "handling delayed processing results" completes the deferred result once the application is invoked, instead of `delay(1.seconds)`; no real sleep left.
- Full `build-workspace` after these changes: 302s green; no-change `build-workspace`: 71s.

