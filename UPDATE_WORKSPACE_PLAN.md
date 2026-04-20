# Update Workspace Plan

## Goal

Make `just refresh-workspace` cheap when nothing meaningful changed by relying primarily on reproducible outputs and Gradle-native incrementality, not workspace-level repo skipping logic.

## Accepted Decisions

1. Make library and image outputs reproducible so identical inputs yield identical artifacts.
2. Keep image builds and image-based tests in local and normal workflows, but only rerun them when the image inputs actually changed.
3. Keep local and CI semantics aligned. No split behavior.
4. Do not introduce a separate lighter workspace-only build path.
5. Keep summary generation in Gradle, not shell.
6. Make `update-gradle` a true no-op when the wrapper version did not change, and only print the checksum when it changed.
7. Re-enable the Gradle daemon for local development, but only after the higher-value build correctness and incrementality work.
8. Ignore CI-specific daemon policy for now.
9. Investigate and fix configuration-cache discards in the normal build path.
10. Refactor the shared Jib convention to improve configuration-cache compatibility.
11. Do not remove image/test/scan verification from local update flows.
12. Do not add a changed-only repo selection mode.
13. Do not wrap `versionCatalogUpdate` in extra caching logic. Let actual build inputs and outputs determine downstream work.
14. Filter known-noisy unresolved aliases from `versionCatalogUpdate` output, but keep unresolved external dependencies visible.
15. Skip a repo's standalone `just build` during the workspace refresh flow when `pull` and `update-all` produced no meaningful new inputs for that repo.
16. Normal repos should consume published dependencies by explicit version, not `includeBuild(...)` and not `SNAPSHOT` selectors.
17. A separate aggregator repo may use `includeBuild(...)` across the workspace for cross-repo development and refactoring.
18. Upstream repos should publish a new patch version only when their reproducible outputs actually changed.
19. All repos should expose `mavenLocal()` for both plugin/buildscript resolution and normal dependency resolution so locally published internal versions are visible everywhere, including to the dependency update plugin during workspace updates.
20. Maven-local cleanup should be limited to workspace artifacts only; each repo should expose a `just cleanup` command, and the workspace should expose a delegating cleanup command. The trigger point for automatic cleanup remains an open design question.
21. Keep the current newer Kotlin version across repos for now, even though `gradle-plugins` emits the known `kotlin-dsl` compatibility warning. Treat that warning as accepted noise rather than a migration driver.
22. Machine-level development prerequisites should be managed from the workspace layer, not from individual repos.
23. Repo-local container image update events should appear in the workspace update summary when a repo owns its own image-version automation.

## Proposed Design

### 1. Reproducible Outputs First

The primary optimization target is not a hand-maintained workspace dependency graph. It is making sure that unchanged inputs produce identical outputs, and that downstream work is triggered by actual changed inputs and artifacts.

Implementation direction:

- Audit library outputs so identical source, dependency, toolchain, and build configuration inputs yield byte-identical artifacts.
- Remove Javadoc timestamps from generated documentation archives.
- Audit service image outputs so identical inputs yield identical images.
- Remove dynamic or time-based output differences where possible.
- Ensure publishing does not happen merely because the command ran; it should only matter if the produced artifact changed.
- Use reproducibility as the gate for version bumping:
- if published outputs are unchanged, do not publish a new version
- if published outputs changed, publish a new patch version

Evidence already gathered:

- Two successive `swissknife` builds produced matching hashes for `306` built artifacts.
- That gives us a concrete proof point that at least the current `swissknife` JAR outputs are reproducible across repeated builds.

Why this matches your requirement:

- If `swissknife` rebuilds with unchanged relevant inputs, it should produce the same JARs.
- If the JARs are unchanged, downstream builds should not need to rerun meaningful work.
- This keeps Gradle and artifact identity as the source of truth, rather than a coarse workspace file graph.

### 1.1 Published Boundaries for Normal Repos

Normal repos should stop using composite-build substitution for cross-repo consumption.

Implementation direction:

- Remove `includeBuild(...)` from the normal repos over time:
  - start with `gradle-plugins`
  - then `swissknife`
  - then `pillar`
  - then the consuming repos
- Replace moving `SNAPSHOT` selectors with explicit published versions.
- Ensure every repo includes `mavenLocal()` in both:
  - plugin/buildscript resolution
  - normal dependency resolution
- Ensure freshly published local versions are therefore visible both to normal builds and to the dependency update plugin.
- Let `versionCatalogUpdate` discover newer local patch versions and rewrite catalogs accordingly.

Current status:

- `gradle-plugins` bootstrap publish-state logic now lives in `gradle-plugins/buildSrc`, so bootstrap-only dependencies such as `semver4j` are managed through the shared version catalog instead of a hidden root-script `buildscript` classpath.
- Normal repos now declare `sollecitomGradlePluginsVersion=1.0.0`, include `mavenLocal()` in both plugin/buildscript and normal dependency resolution, and no longer use `includeBuild("../gradle-plugins")`.
- End-to-end producer/consumer verification is still pending on a local machine because this runner cannot complete `:base:validatePlugins` due a Gradle worker socket restriction.

Expected result:

- normal repos behave like isolated published consumers
- workspace updates become easier to reason about
- downstream rebuild decisions can be based on actual published version movement instead of composite-build source coupling

### 1.2 Separate Aggregator Repo

Keep local composite-build development, but move it out of the normal repos into a dedicated aggregator repository.

Implementation direction:

- Create a separate repo whose job is to:
  - `includeBuild(...)` all relevant workspace repos
  - provide a single composite-build view for search/replace and cross-repo development
- Treat that repo as a development/integration convenience, not the canonical release-like verification path.
- Treat the aggregator as a workbench/view only:
  - make edits there if convenient
  - commit and push in the real underlying repos
  - run normal verification and push flows from the workspace repo
  - then refresh the aggregator repo state afterwards

Expected result:

- normal repo and workspace builds stay cleaner and more isolated
- cross-repo development remains convenient when explicitly needed

### 1.3 Maven Local Cleanup

Using explicit locally published versions will gradually grow the local Maven repository under `~/.m2/repository`.

Chosen direction:

- each repo exposes a `just cleanup` command for its own workspace-published artifacts
- the workspace exposes a cleanup command that delegates to the cleanup command of each repo

Open question:

- should cleanup run automatically anywhere, or remain an explicit maintenance step?
  - publish flow
  - workspace update flow
  - explicit cleanup command only

Constraints already agreed:

- cleanup must only touch workspace-owned artifacts
- cleanup policy should preserve a small rollback window instead of deleting everything
- ordinary `build` should not silently mutate caches unless we explicitly choose that later

### 2. Image Builds and Image-Based Tests

Keep them in the normal build flow, but make them genuinely incremental.

Implementation direction:

- Audit the input surface for:
  - `jibDockerBuild`
  - `containerBasedServiceTest`
  - `securityScan`
- Ensure image content only changes when image inputs change:
  - app jars/classes/resources
  - Docker base image parameter
  - Jib settings
  - container metadata actually baked into the image
- Preserve `reproducibleBuild = true` everywhere for Jib-backed services.
- Pin Docker base images by digest instead of tag alone.
- Support an explicit per-repo base-image policy so repos can either:
  - follow the newest supported major automatically, or
  - stay pinned to a specific major such as `25`
- Remove any dynamic timestamps or mutable labels from image configuration.
- Ensure container-based tests depend on image identity/content, not just task execution.
- Ensure `securityScan` and `containerBasedServiceTest` are up-to-date when:
  - test sources did not change
  - the scanned/tested image did not change
  - relevant runtime configuration did not change

Expected result:

- If service code or image inputs did not change, image build and image-based verification should not rerun meaningful work.
- If service code changed, the image is rebuilt and corresponding tests/scans rerun.

### 2.1 Base Image Upgrade Policy

Base images need both reproducibility and controlled upgrades.

Implementation direction:

- Replace plain tag-only values such as `eclipse-temurin:25-jre-noble` with digest-pinned references such as:
  - `eclipse-temurin:25-jre-noble@sha256:...`
- Add explicit policy inputs per repo so the updater can decide whether to:
  - follow the newest matching major automatically, or
  - remain pinned to a specific major such as `25`
- Keep the resolved image reference that Jib consumes separate from the policy decision that produced it.

Recommended policy model:

- `dockerBaseImageRepository=eclipse-temurin`
- `dockerBaseImageVariant=jre-noble`
- `dockerBaseImageMajor=latest` or `25`
- `dockerBaseImageParam=eclipse-temurin:25-jre-noble@sha256:...`

Update behavior:

- If a repo is configured with `latest`, the updater should resolve the newest matching major and write the corresponding `tag@digest`.
- If a repo is configured with a pinned major such as `25`, the updater should only refresh the digest within that major line.
- The updater should treat digest changes within the same tag as a base-image refresh, not a semantic version bump.

Failure handling:

- When a repo follows `latest`, attempt the newest matching major first.
- Run the repo's normal update/build flow.
- If that build fails, fall back for that run to the previous working major and its latest digest.
- Do not automatically persist that fallback policy in v1; require an explicit pin if the repo should stay on the older major.

Expected result:

- Base-image updates remain reproducible.
- Repos can advance automatically to newer Java majors by default.
- A failing major upgrade has a controlled fallback path without forcing every repo to move in lockstep.

### 3. Gradle Daemon

Re-enable daemon use for local development across repos.

Implementation direction:

- Remove or override `org.gradle.daemon=false` in local repo `gradle.properties`.
- Keep one local behavior everywhere.

Expected result:

- Lower startup/configuration cost across repeated `./gradlew` invocations during `refresh-workspace`.

## Configuration Cache Work

### 4. Fix Discarded Configuration Cache Entries

Investigate why normal `build` runs still report discarded configuration cache entries.

Implementation direction:

- Run representative builds with `--configuration-cache --configuration-cache-problems=warn`.
- Triage problems by plugin/task/convention class.
- Fix highest-frequency issues first in shared plugins, since they affect the whole workspace.

Target areas already identified:

- custom convention plugins in `gradle-plugins`
- image/container-related tasks
- task configuration using eager reads or late mutation
- third-party task limitations, especially `versionCatalogUpdate`
- Kotlin DSL / Kotlin plugin version mismatch in `gradle-plugins`

Important distinction:

- `versionCatalogUpdate` currently reports a real third-party configuration-cache incompatibility:
  - `Task.project` is accessed at execution time by `VersionCatalogUpdateTask`
- This means configuration-cache reuse for the dependency-update invocation itself may remain limited unless that plugin changes.
- That should not block the broader optimization work, because the larger payoff is avoiding unnecessary rebuild, image build, scan, and test work after `update-all` when nothing actually changed.

Additional cleanup target:

- `gradle-plugins` currently emits warnings about using `kotlin-dsl` together with an explicitly requested Kotlin plugin version newer than Gradle's embedded Kotlin.
- This is likely not the root cause of the `versionCatalogUpdate` cache issue, but it is still a build hygiene and cache-stability problem worth fixing.

Expected result:

- repeated no-change builds spend much less time reconfiguring the build graph.

### 5. Refactor Jib Convention

The current shared Jib convention uses `afterEvaluate`, which is a likely source of poor configuration-cache behavior.

Relevant file:

- [JibDockerBuildConvention.kt](/Users/msollecito/workspace/gradle-plugins/components/base/src/main/kotlin/sollecitom/plugins/conventions/task/jib/JibDockerBuildConvention.kt)

Implementation direction:

- Replace `afterEvaluate` configuration with lazy property wiring as far as Jib allows.
- Avoid imperative late mutation of task/plugin state.
- Re-check whether a separate `--no-configuration-cache` invocation is still necessary after the refactor.

Expected result:

- better configuration-cache compatibility
- lower cost for service image builds

## Update Flow Improvements

### 6. Wrapper Update Should Be a Real No-Op

Current desired behavior:

- If `./gradlew wrapper --gradle-version latest --distribution-type all` leaves `distributionUrl` unchanged, do not:
  - fetch a new checksum
  - rewrite `distributionSha256Sum`
  - print `Updated wrapper checksum: ...`
- Only print wrapper checksum updates when the checksum value actually changed from the current local one.

Expected result:

- less noise
- less unnecessary network work
- fewer false-positive file changes

### 7. Skip Standalone Build When Update Produced No Meaningful Changes

`versionCatalogUpdate` itself may still require a full Gradle configuration pass. The cheaper win is to avoid the follow-on standalone `just build` invocation when the update flow produced no meaningful changes for that repo.

Implementation direction:

- In `scripts/workspace.sh`, capture per-repo state before `just pull`:
  - current `HEAD`
  - current upstream ref when available
  - current working tree status
- After `just pull` and `just update-all`, detect whether the current update run introduced any meaningful repo-local changes:
  - local `HEAD` changed because upstream changes were pulled
  - update-relevant files changed, such as:
    - `gradle/libs.versions.toml`
    - `gradle.properties`
    - `gradle/wrapper/gradle-wrapper.properties`
    - `Dockerfile`
    - `container-versions.properties`
    - other repo-specific dependency/version inputs where needed
  - any net worktree diff remains from the update flow
- If none of those conditions are true, skip that repo's standalone `just build` and move to the next repo.
- Base the decision on the delta produced by the current workspace run, not on absolute repo cleanliness, so unrelated pre-existing local edits do not force or block a build by mistake.

Why this is safe:

- If nothing meaningful changed in that repo, there is nothing new to validate in its standalone build.
- In the target architecture, downstream repos consume published versions, so this optimization only removes redundant standalone verification work after no-op update runs.

Expected result:

- fewer second-stage Gradle invocations after no-op dependency update runs
- less repeated included-build configuration, especially for `gradle-plugins`
- materially faster no-change `refresh-workspace` runs

### 8. Use Real Build Inputs and Outputs, Not Workspace Heuristics

Do not try to replace Gradle’s incremental model with a large workspace dependency graph.

Implementation direction:

- Rely on reproducible artifacts and Gradle task inputs/outputs as the primary source of truth.
- Allow downstream builds to determine whether their tasks are actually out of date from consumed artifacts and declared inputs.
- Keep workspace scripting focused on orchestration and reporting, not on attempting to reimplement cross-repo dependency resolution.

This is the practical interpretation of your choice for item 13.

## Logging and Output

### 9. Keep Gradle Summary, But Fix Empty-Case Reporting

The current summary should always emit, per repo:

- a list of concrete upgrade lines, or
- `repo-name: No dependencies were updated.`

This was partially fixed already, but needs end-to-end verification after the latest workspace script changes.

### 10. Filter Known Noisy `versionCatalogUpdate` Warnings

Known-noisy unresolved aliases:

- internal snapshot modules such as `sollecitom.gradle-plugins:*`

Why these are noisy:

- they are workspace-internal snapshot coordinates, not normal externally versioned artifacts
- `versionCatalogUpdate` tries to resolve them like published dependencies
- that resolution may fail even though the workspace build is correct

Why the rest should still be logged:

- unresolved external dependencies can indicate a real problem:
  - missing repository
  - broken coordinate
  - catalog alias that cannot be evaluated for upgrade checks
  - dependency update tool unable to inspect a version you may actually care about
- hiding those would risk masking real maintenance issues

Implementation direction:

- post-process `versionCatalogUpdate` output
- suppress or collapse only known internal snapshot aliases
- keep all unresolved external coordinates visible

## Clarification on the Rejected Shell Summary Option

You said no to replacing `updateSummary` with shell summarization.

What that option would have meant:

- remove the per-repo `./gradlew -q updateSummary` call from the workspace loop
- generate the same summary directly from git diffs and text parsing in the workspace script
- benefit: fewer Gradle startups
- downside: duplicate logic outside the shared Gradle plugin

Since you rejected it, the plan keeps the shared Gradle summary task and focuses on reducing rebuilds and fixing configuration/cache inefficiencies instead.

## Execution Checklist

1. **Workspace Flow**
1.1 [x] Capture per-repo before/after update state in `scripts/workspace.sh` so the workspace runner can tell whether the current run introduced any meaningful changes.
Progress:
`scripts/workspace.sh` now captures each repo's pre-pull and post-pull `HEAD`, then inspects the resulting worktree state after `update-all` before deciding whether a standalone `just build` is required.
1.2 [x] Define the exact set of update-relevant files and conditions that should force a standalone repo build after `pull` and `update-all`.
Progress:
The workspace runner now treats these paths as update-relevant inputs: `gradle/libs.versions.toml`, `gradle.properties`, `gradle/wrapper/gradle-wrapper.properties`, `container-versions.properties`, and `Dockerfile`. A standalone build is forced when pulled commits changed `HEAD`, when any of those update-relevant files changed, or conservatively when any other net repo worktree diff remains after `update-all`.
1.3 [x] Skip a repo's standalone `just build` when the current update run produced no pulled commits, no meaningful dependency or base-image changes, and no net worktree diff for that repo.
Progress:
The workspace refresh flow now skips the extra standalone build in that no-op case and prints whether it is running or skipping the build for each repo.
1.4 [x] Add a separate internal-only workspace update path alongside the full external-plus-internal update path.
Progress:
Shared Gradle task `updateInternalCatalogVersions` now updates internal version refs from `mavenLocal()` using configurable internal group prefixes, every repo exposes `update-internal-dependencies`, and repo `build` commands now run the internal-only updater before build/publish. Workspace `just refresh-local-workspace` is the internal-only high-level flow, while `just refresh-workspace` runs the full pull + update + build + publish + cleanup flow.
1.5 [x] Centralize machine-level workspace requirements and JDK management at the workspace root.
Progress:
Workspace commands now ensure `just`, `jq`, and Temurin through a workspace-level script. Repo-local JDK update scripts were removed from `gradle-plugins` and `backend-skeleton`, and `backend-skeleton` no longer mutates the machine JDK during `update-all`.
1.6 [ ] Prove the first-install/bootstrap path on a clean machine.

2. **Publishing And Internal Versions**
2.1 [x] Add `mavenLocal()` to every repo for both plugin/buildscript resolution and normal dependency resolution, and verify the dependency update plugin sees locally published internal versions through the same setup.
Progress:
All normal repos now declare `mavenLocal()` in `pluginManagement.repositories` and `dependencyResolutionManagement.repositories`. End-to-end verification is now complete: after publishing `gradle-plugins` `1.0.4` locally, the workspace refresh flow updated downstream repos from `sollecitom-gradle-plugins = 1.0.3` to `1.0.4` through the normal dependency update flow.
2.2 [x] Introduce explicit non-`SNAPSHOT` internal versions for publishable repos and define the patch-bump workflow used when outputs actually changed.
Progress:
`gradle-plugins`, `acme-schema-catalogue`, `swissknife`, and `pillar` now publish explicit non-`SNAPSHOT` versions, and all normal repos consume those libraries by explicit version from `mavenLocal()`.
2.3 [x] Create a `publish-if-changed` flow that compares reproducible published outputs to the previous published hash and only then publishes a new patch version.
Progress:
`gradle-plugins`, `acme-schema-catalogue`, `swissknife`, and `pillar` now use `scripts/publish-if-changed.sh` plus shared publication-state logic, and end-to-end local verification is now considered complete.
2.4 [x] Verify that `versionCatalogUpdate` can detect newer locally published versions from `mavenLocal()` and rewrite the catalogs correctly.
Progress:
Confirmed end to end: after publishing `gradle-plugins` `1.0.4` locally, downstream repos rewrote `sollecitom-gradle-plugins = 1.0.3` to `1.0.4` through the normal update flow. Confirmed limitation remains: if the declared version is missing locally, the plugin falls into its `invalid/exceeded` path and only warns. The internal-only updater covers that bootstrap gap.
2.5 [x] Implement per-repo `just cleanup` commands for workspace-owned Maven-local artifacts, preserving a small rollback window.
Progress:
Every repo now exposes `just cleanup`, backed by the shared `scripts/cleanup-maven-local.sh` helper. Each repo sets its own retention policy through the recipe arguments (`--keep` and `--max-age-days`), with publishable libraries currently keeping a larger rollback window than consumer repos.
2.6 [x] Add a workspace-level cleanup entry point that delegates to each repo’s cleanup command.
Progress:
The root workspace now exposes cleanup through `just execute cleanup`, and `scripts/workspace.sh` has a dedicated `cleanup` command that runs `just cleanup` across the workspace modules.
2.7 [x] Decide whether Maven-local cleanup remains explicit or becomes part of another workflow later.
Progress:
Cleanup now has both forms:
- explicit via `just cleanup` and `just execute cleanup`
- integrated at the end of `just refresh-workspace` and `just refresh-local-workspace`
Workspace commands are now single-purpose underneath, with explicit composition at the top:
- `just execute pull update build publish cleanup` for an exact ordered pipeline
- `just refresh-workspace` for pull + update + build + publish + cleanup
- `just refresh-local-workspace` for build + publish + cleanup

3. **Reproducibility**
3.1 [x] Audit published library artifacts, manifests, and archive settings so unchanged inputs produce byte-identical outputs.
Progress:
Published library reproducibility has now been verified sufficiently for this checklist item. Shared conventions already removed Javadoc timestamp noise, and the remaining audit result is accepted as complete.
3.2 [ ] Audit service image outputs so unchanged image inputs produce identical images.
3.3 [x] Verify end-to-end that unchanged service repos do not rebuild images or rerun image-based tests/scans.
Progress:
The latest no-op workspace refresh run skipped the standalone `just build` for `modulith-example` and `element-service-example`, so their Jib image build, container-based tests, and security scan did not rerun.
3.4 [x] Verify end-to-end that unchanged upstream library outputs do not trigger meaningful downstream rebuild work.
Progress:
The latest no-op workspace refresh run skipped the standalone `just build` for downstream consumer repos after internal/external update tasks completed without net repo changes, confirming unchanged upstream outputs no longer force meaningful downstream rebuild work.

4. **Base Images And Service Verification**
4.1 [x] Define and implement a shared base-image policy model that supports `latest` major tracking and explicit pinned majors per repo.
Progress:
`element-service-example`, `modulith-example`, and `backend-skeleton` now declare repository, variant, and major policy fields in `gradle.properties`. The successful workspace run confirmed the `latest` policy advanced the service repos from Java 25 to Java 26.
4.2 [x] Update workspace image-upgrade tooling to rewrite `dockerBaseImageParam` as a digest-pinned `tag@digest` reference based on that policy.
Progress:
`scripts/workspace.sh` now resolves Docker Hub tags to the active target platform digest and rewrites `dockerBaseImageParam`, plus `dockerRuntimeBaseImageParam` where present. `backend-skeleton` also has its `Dockerfile` base images kept in sync with the resolved digest-pinned values.
4.3 [x] Add guarded major-upgrade fallback behavior so repos following `latest` can fall back to the previous working major when the update build fails.
Progress:
The workspace updater now retries a failed `latest` Java major attempt on the previously working major for repos with declared base-image policy.
4.4 [x] Surface base-image refreshes, major upgrades, pinned-major skips, and fallback events clearly in the workspace summary.
Progress:
The shared Gradle `updateSummary` task now renders image tag changes more cleanly, treats digest-only changes as refreshes, and can include workspace-provided pinned-major or fallback events. The successful workspace run confirmed the major-upgrade summary output for `modulith-example` and `element-service-example`.
4.4.1 [x] Surface repo-local container-version updater changes in the workspace summary where such updater scripts exist.
Progress:
`scripts/workspace.sh` now passes a workspace event file into repo-local `just update-all` runs, and `swissknife/scripts/update-container-versions.sh` appends concrete image update lines such as `keycloak: 26.6.0 → 26.6.1` when it changes repo-owned container versions.
4.4.2 [x] Confirm which repos actually need repo-local container-version summary plumbing.
Progress:
Only `swissknife` currently has dedicated repo-local container version automation (`container-versions.properties` plus `scripts/update-container-versions.sh`). Other repos with Docker image usage are already covered by the shared summary path through `gradle.properties` and, where applicable, `Dockerfile` changes. `pillar` uses an external Docker base image (`eclipse-temurin:25-jre-noble`) and Testcontainers abstractions, but does not define its own concrete external container image versions.
4.5 [x] Refactor the shared Jib convention away from `afterEvaluate` and other late mutation patterns.
Progress:
`JibDockerBuildConvention` no longer relies on project-wide `afterEvaluate`. Provider-capable Jib fields are now configured immediately, and only the remaining Jib API fields that still require eager setters are synchronized at Jib task execution time.
4.6 [ ] Re-evaluate whether service image builds can run with configuration cache after the Jib convention refactor.
Progress:
Functional verification succeeded after the convention refactor, but configuration-cache verification still fails in consumer repos because Jib's own `BuildDockerTask` serializes `Project` state and accesses `Task.project` at execution time. That leaves this item blocked by the third-party Jib task implementation rather than by the shared workspace convention.
4.7 [ ] Audit `jibDockerBuild` inputs to ensure image content changes only when actual image inputs change.
4.8 [ ] Audit `containerBasedServiceTest` task inputs and dependencies so unchanged image/test inputs do not trigger reruns.
4.9 [ ] Audit `securityScan` task inputs and dependencies so unchanged image/scan inputs do not trigger reruns.

5. **Configuration Cache And Build Logic**
5.1 [ ] Capture representative `build` runs that currently discard configuration-cache entries and group the problems by root cause.
5.2 [ ] Fix the highest-value configuration-cache issues in shared Gradle conventions before touching individual service repos.
5.3 [ ] Separate third-party configuration-cache limitations from first-party ones, and treat `versionCatalogUpdate` as an expected exception unless a compatible upgrade path exists.
Progress:
Two concrete third-party limitations are now confirmed:
- `versionCatalogUpdate` still discards configuration cache because `VersionCatalogUpdateTask` accesses `Task.project` at execution time
- Jib `BuildDockerTask` still discards configuration cache because it serializes `Project` and accesses `Task.project` at execution time
5.4 [ ] Align `gradle-plugins` Kotlin usage with Gradle's `kotlin-dsl` expectations so the included build stops emitting unsupported Kotlin plugin version warnings.
Current decision:
Keep the current newer Kotlin version for now and accept the warning. Do not prioritize this item unless it starts causing functional problems rather than cosmetic noise.

6. **Performance**
6.1 [ ] Verify end-to-end that a no-change `just refresh-workspace` run is materially faster while still relying on Gradle-native incrementality.
6.2 [ ] Re-enable the Gradle daemon for local runs across all workspace repos.

7. **Cross-Repo Development**
7.1 [x] Remove `includeBuild(...)` from the normal repos in rollout order, starting with `gradle-plugins`.
Progress:
Normal repos no longer use composite-build overrides for `gradle-plugins`, `acme-schema-catalogue`, `swissknife`, or `pillar`; they now consume published explicit versions.
7.2 [ ] Create a separate aggregator repo that uses `includeBuild(...)` across the workspace for cross-repo development.

## Immediate Follow-Ups

1. **Verified Recently**
1.1 [x] Run the workspace refresh flow end to end and confirm the new full flow.
Result:
Commits and pulls happen first, internal and external updates run, and standalone repo builds are now skipped when no meaningful repo change remains.
1.2 [x] Verify the new `BUILD SUMMARY` and `UPDATE SUMMARY` output includes internal version bumps from `updateInternalCatalogVersions`.
Result:
The workspace summary now stays concise, suppresses generic `changed:` lines, and no longer dumps long Docker `FROM ...@sha256 ... AS ...` details when equivalent image refresh lines are already present.
1.3 [x] Verify the tracked `sollecitom-gradle-plugins = 1.0.3` bootstrap can update itself cleanly on the next internal publish of `gradle-plugins`.
Result:
Confirmed by the `gradle-plugins` `1.0.4` publish and the subsequent successful workspace update ripple.
1.4 [x] Decide whether the workspace repo should permanently track the root `justfile` and `UPDATE_WORKSPACE_PLAN.md`.
Result:
Yes. They are now part of the operational workspace surface and should remain tracked.
1.5 [x] Confirm which repos besides `swissknife` need extra summary wiring for external container image updates.
Result:
None at the moment. `swissknife` is the only repo with repo-local container image version automation. Service repos already surface Docker base image changes through the shared Gradle summary, and `pillar` only declares `dockerBaseImageParam=eclipse-temurin:25-jre-noble` plus generic Testcontainers abstractions.

2. **Next**
2.1 [ ] Prove the first-install/bootstrap path on a clean machine.
2.2 [x] Add Maven-local cleanup commands:
   - per-repo `just cleanup`
   - workspace `just execute cleanup`
   - preserve a small rollback window
2.3 [ ] Decide whether repo-local update scripts should share a tiny helper convention for emitting workspace summary events, or continue using a simple environment-file contract.

## Success Criteria

- `just refresh-workspace` is fast when no relevant dependency files changed anywhere.
- If a core repo like `swissknife` rebuilds with unchanged relevant inputs, it produces the same artifacts.
- If upstream artifacts are unchanged, downstream repos do not do meaningful rebuild work.
- Service images are rebuilt and retested only when service/image inputs changed.
- Wrapper updates do not print checksum updates when nothing changed.
- Locally published newer internal versions are discoverable from `mavenLocal()` by the dependency update flow.
- All repos resolve both plugins and normal dependencies through `mavenLocal()` as part of the local workspace flow.
- Repeated no-change runs reuse configuration and task state much more effectively than today.
