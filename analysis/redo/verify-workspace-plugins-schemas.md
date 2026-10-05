# Verification: workspace root, aggregator, gradle-plugins, acme-schema-catalogue (+ 4.14 / 10.22 cross-repo)

Refs: workspace bb5fdff, gradle-plugins 349b791, acme-schema-catalogue a225e68, aggregator 2b7ab94, lattice 21fcf68, each compared with `bug-hunt-snapshot-2026-10-05`. All four sub-repos had HEAD equal to the snapshot and clean working trees when checked. Base `workspace.sh` line numbers below come from `git show bb5fdff:scripts/workspace.sh`.

### 1.1 — Docker image cleanup ranked by `.Created` with a literal `\t`
- Defect in base: REAL. `cleanup-docker-images.sh:80` used `docker image inspect ... --format '{{.Id}}\t{{.Created}}'`. `docker inspect` templates don't expand `\t`, so the line has no tab. `awk -F'\t'` then gives an empty `$2`, every "kept id" is garbage, and every tag gets removed. Even with a real tab, ranking would be arbitrary: base `JibDockerBuildConvention` has `defaultReproducibleBuild = true`, which sets `creationTime = EPOCH`, so every image is created in 1970. Also `docker image rm` under `set -e` (line 105) aborts the whole pipeline on the first failure.
- Fix: CORRECT. Uses `{{"\t"}}` and `.Metadata.LastTagTime`, adds a keep-guard that skips the repo when no kept id is a real id, and warns instead of aborting on a failed `rm` (with a correct recount). Remaining risk, not a regression: if `LastTagTime` is the zero value (e.g. containerd image store, or pulled-only images), ties fall back to id order and the guard doesn't catch it. Jib `dockerBuild` loads via `docker load`, which sets the tag time.
- Principles: none
- Importance: 4 — every cleanup run deleted the wrong tags, including the current `latest`.
- Confidence: 4 — clear trace from code. The `\t` non-expansion in `docker inspect` is well known but I didn't run it.
- Recommendation: REDO AS IS

### 1.2 — Gradle lock retry dead under `set -e`
- Defect in base: REAL. `workspace.sh:220-221` runs `run_command_with_live_logging ...; exit_code="$?"`. Callers at `:680` (update), `:697` (update-internal) and `:758` (publish) are bare statements, so `errexit` is live and a non-zero return exits before the `grep` at `:223`. Only the `if`-wrapped callers at `:711`/`:737` reached the retry.
- Fix: CORRECT. `... && exit_code=0 || exit_code=$?` at both call sites. It is minimal and doesn't change behaviour for the `if` callers.
- Principles: none
- Importance: 3 — the retry silently didn't exist for three flows. Failure is loud, not corrupting.
- Confidence: 5 — standard bash `errexit` semantics, traced.
- Recommendation: REDO AS IS

### 1.3 — CycloneDX aggregates didn't declare per-project outputs as inputs
- Defect in base: REAL. In `cyclonedx-init.gradle:307-313` and `:352-358`, the aggregates declare only `taskInputFilesFor(workspaceRoot)`, which is root files plus the root project's own `build.gradle(.kts)` (`:42-82`), plus a `dependsOn`. A subproject dependency change re-runs that subproject's snapshot while the aggregate stays UP-TO-DATE. The tool's layer-1 hash (`LicenseAudit.kt:188-192`) does trigger Gradle, so the audit reads a stale aggregate.
- Fix: CORRECT. Two `inputs.files(allprojects.collect { direct...OutputFileFor(it) })` lines, consistent with the existing `dependsOn`. README/CONTEXT text is accurate: I checked the hashed file list and `FORCE_LICENSE_AUDIT` against `LicenseAudit.kt`. The two docs largely duplicate each other, which is cosmetic.
- Principles: none
- Importance: 4 — the license audit could silently skip new dependencies.
- Confidence: 5 — Gradle up-to-date semantics are clear from the declarations.
- Recommendation: REDO AS IS

### 1.4 — Every flow upgraded Homebrew packages (JDK included)
- Defect in base: REAL. `run_execute_pipeline` (base `:1071-1073`) calls `ensure_workspace_requirements update` for any of pull/build/publish/…. `ensure-workspace-requirements.sh` `install|update` then runs `brew upgrade just/jq` and `brew upgrade --cask temurin`. So `build-workspace` could switch the JDK major. Standalone `license-audit` also used `update` (base `:1103,1107`).
- Fix: CORRECT. `update` mode runs only when the pipeline has `update`; other flows use `check`, and standalone `license-audit` uses `check`. The time-bounded holds file (`policy/version-holds.txt`, `is_held`, `candidate_version`) is a new feature beyond the defect, agreed interactively. Its logic is sound:
  - Malformed lines `exit 1`. This works because the loop reads from process substitution, not a pipe.
  - Prefix match on `[.,_-]`, inclusive `until`, expired holds reported.
  - Minor edge: when `jq` is missing, `candidate_version` yields an empty version and the upgrade proceeds. Harmless.
- Principles: none (holds go slightly past "minimal behaviour", but the owner agreed to them)
- Importance: 4 — the daily loop could change the machine JDK and break builds.
- Confidence: 5 — traced.
- Recommendation: REDO AS IS. If you want the smallest diff, the `check`/`update` split alone fixes the defect and the holds can be a separate decision.

### 1.5 — Base-image fallback missing from the update summary
- Defect in base: REAL. The update summary is collected in `run_module_update` (`:681-683`) before `build`. `apply_base_image_fallback` (`:516-526`) only appends to the events file during build, when `summary_file=""` (`run_module_pipeline` build branch), so the fallback never reaches UPDATE SUMMARY.
- Fix: CORRECT. The message is appended as an indented line to `pipeline_update_summary_file`. That module's block is always the last one written, because steps run per module in order. Minimal.
- Principles: none
- Importance: 3 — the summary claims a Java image bump that was rolled back.
- Confidence: 4 — clear trace.
- Recommendation: REDO AS IS

### 1.6 — Base image pinned to a single-platform digest
- Defect in base: REAL. `resolve_image_digest` (`:313-333`) picks the `linux/arm64` manifest on Apple Silicon (amd64 otherwise) and pins it in `gradle.properties`. The error text at `:342` always said "linux/amd64".
- Fix: CORRECT. `docker buildx imagetools inspect --format '{{.Manifest.Digest}}'` returns the index digest. Jib already selects the platform through `from.platforms` (`JibDockerBuildConvention.configureForOperatingSystem`). The error message is updated.
- Principles: none
- Importance: 2 — only bites builds on another architecture; there is no CI and the machine is macOS only.
- Confidence: 4 — template semantics from memory; not run.
- Recommendation: REDO AS IS

### 1.8 — License-audit runner staleness
- Defect in base: NOT REAL for workspace flows, as the checklist says. Base `ensure_license_audit_runner` (`:781-795`) runs `installDist` once per `workspace.sh` process, because `license_audit_runner_ready` starts at 0. `run-license-audit.sh` is only used by `tools/justfile`. Its staleness check (src/main `*.kt`, build file, settings, catalog) was nearly complete for a single-module app.
- Fix: CORRECT (simplification). It always runs `installDist`, which Gradle makes near-free when nothing changed. This deletes 30 lines; the cost is one Gradle invocation per `tools` audit.
- Principles: none
- Importance: 1 — tidy-up, no real defect.
- Confidence: 5
- Recommendation: REDO AS IS (optional; low value)

### 1.9 — Test summary garbled by CR; OSC `ESC \` not stripped
- Defect in base: REAL. `sanitize_gradle_output` (`:79-84`): inside single quotes, the Perl pattern `\e\\\\` means ESC followed by two literal backslashes, so ST-terminated OSC sequences were never stripped. The `tr -d` set `\000-\010\013\014\016-\037\177` keeps `\r` (015), and `script` emits CRLF.
- Fix: CORRECT. Non-greedy `[^\a]*?(?:\a|\e\\)` (also stops one OSC swallowing the next), and `tr -d '\000-\010\013-\037\177'` now removes CR.
- Principles: none
- Importance: 2 — cosmetic output corruption in the summary.
- Confidence: 4 — regex semantics traced. The CRLF from `script` was observed by the original reporter, not by me.
- Recommendation: REDO AS IS

### 1.11 — Dead code in `workspace.sh`
- Defect in base: REAL. `count_modules`, `module_is_publishable`, `reset_summary_file` and all `run_step_*` (except license audit) are unreachable: the justfile only calls `execute`, `license-audit(-compact)`, `install` and `reinstall`. The destructive standalone `reset` (`git clean -fdx`) was reachable only by invoking the script directly. `reset` was listed in `execute_requires_workspace_requirements` but isn't a step. The "Resumability" comment contradicted the justfile.
- Fix: CORRECT. Pure removal. The `publishable` argument was dropped consistently from the justfile (3 recipes) and `shift 3` became `shift 2`. I grepped the snapshot for every removed symbol: zero references left.
- Principles: none
- Importance: 1 — dead code, plus the removal of a latent destructive command.
- Confidence: 5
- Recommendation: REDO AS IS

### 1.12 — Dockerfile / runtime-variant branch
- Defect in base: REAL but latent. `FROM` lines were only rewritten when `dockerRuntimeBaseImageVariant` was set (`:471-481`, `:520-523`). No repo has a Dockerfile or that property.
- Fix: INCOMPLETE (minor). It removes the whole runtime-variant/Dockerfile branch, all of its state variables and the backup/restore. The removal itself is clean. Leftovers:
  - `CONTEXT.md:11` still says base image updates flow through "`gradle.properties` and, where present, `Dockerfile`".
  - The edit leaves a double blank line in `prepare_base_image_policy`.
  - `UpdateSummaryTask` (plugin and root copy) still summarises `Dockerfile` and `dockerRuntimeBaseImage*`, which is now dead.
- Principles: none (deleting is in line with YAGNI)
- Importance: 1 — dead path.
- Confidence: 5
- Recommendation: REDO MODIFIED: same deletion, plus remove "and, where present, `Dockerfile`" from `CONTEXT.md:11`, and drop the stray blank line. Optionally also delete the Dockerfile/`dockerRuntimeBaseImage*` handling in both `UpdateSummaryTask` copies.

### 1.13 — Maven-local cleanup never pruned plugin markers
- Defect in base: REAL. `cleanup-maven-local.sh:91-135` only walks `~/.m2/repository/<projectGroup>` (`sollecitom/gradle-plugins`). Markers live at `sollecitom/<plugin>/sollecitom.<plugin>.gradle.plugin/<ver>`; `~/.m2/repository/sollecitom/` currently holds 13 such plugin dirs.
- Fix: CORRECT. The opt-in `--plugin-markers sollecitom` (only gradle-plugins' `justfile` passes it) adds `find <ns> -mindepth 2 -maxdepth 2 -name 'sollecitom.*.gradle.plugin'` to the artifact list. The same rank / `current_version` / age rules apply, and counts are now computed in the loop. The `-name` filter excludes other repos' groups under `sollecitom/`.
- Principles: none
- Importance: 1 — disk hygiene.
- Confidence: 5
- Recommendation: REDO AS IS

### 1.14 — A manual bump to `2.0.0` published `2.0.1`
- Defect in base: REAL. `PublicationHashGate.nextPatchVersion` (plugin `:186-193`, buildSrc copy) returned `max(current, published).nextPatch()`, so `2.0.0` became `2.0.1`.
- Fix: CORRECT. `nextVersion` returns `currentVersion` when it is stable semver and greater than the published version. Otherwise the old behaviour is unchanged. Applied to both copies; `private` became `internal` for the test.
  - The new `PublicationHashGateTests` (4 tests, AssertK, backticks, `PER_CLASS`, literal values) would fail without the fix (`2.0.0` → `2.0.1`).
  - The JUnit/AssertK test setup in `components/base/build.gradle.kts` and the catalog is minimal. Test reports show 4/4 passed.
- Principles: none
- Importance: 2 — only on a rare manual major/minor bump.
- Confidence: 5
- Recommendation: REDO AS IS

### 1.15 — Docs: CONTEXT/README inaccuracies
- Defect in base: REAL.
  - Base CONTEXT `:103` described skipping service builds during `update`, which nothing implements.
  - CONTEXT `:5` said `~/workspace`.
  - CONTEXT blamed Kotlin daemons, but every justfile repo has `kotlin.compiler.execution.strategy=in-process` and `org.gradle.daemon=false` (aggregator has neither, but it isn't a workspace module).
  - README "Allowed steps" omitted `license-audit(-compact)`, which `run_module_pipeline` supports.
- Fix: CORRECT. Each new statement checks out against the code.
- Principles: none
- Importance: 2
- Confidence: 5
- Recommendation: REDO AS IS

### 2.1 — aggregator requires nonexistent `../backend-skeleton`
- Defect in base: REAL. The snapshot `settings.gradle.kts` runs `require(repoDir.isDirectory)` for each entry, and `backend-skeleton/` doesn't exist in the workspace, so including it fails settings evaluation. `quality-scorer` exists with a `settings.gradle.kts`. Caveat: at 2b7ab94 only `.gitignore` was tracked, so I can't see the exact pre-session text of `settings.gradle.kts`/README/CONTEXT. The fix can only be inferred from the report (`settings.gradle.kts:29,37-39`).
- Fix: CORRECT as far as can be seen. The list now matches the 11 existing sibling repos, each with a `settings.gradle.kts`. Two issues: it was never built, and the session committed all of the owner's untracked aggregator work (11 files) in the same commit as the fix. That second part is outside the item.
- Principles: none (but committing the owner's untracked WIP was not asked for)
- Importance: 2 — aggregator isn't part of any workspace flow ("a future separate aggregator repo"). It is broken, but unused.
- Confidence: 4 for the defect. 2 for the exact extent of the edit, since there is no base text.
- Recommendation: REDO MODIFIED: make only the `workspaceBuilds` edit (remove `backend-skeleton`, add `quality-scorer`) and the matching README/CONTEXT lines in the working tree. Leave committing the untracked files to the owner. Run `./gradlew help` in aggregator once to confirm.

### 3.1 — Minimum-dependency-version convention pins the minimum exactly
- Defect in base: REAL, on a used path. In `MinimumDependencyVersionConventions.kt:18-21`, `if (matches(requested)) useVersion(minimum)` has no version comparison. `KotlinLibraryConventions` applies it to every repo with defaults such as `io.netty:* 4.2.18.Final` and jackson `2.22.3`. A catalog upgrade to netty 4.2.19 was rewritten on every edge to 4.2.18, a silent downgrade.
- Fix: CORRECT.
  - `isViolatedBy` = matches and the requested version is not ≥ the minimum. Unparsable or null versions count as violated, which keeps the old pinning for ranges and versionless edges.
  - Because `eachDependency` is per edge, low transitive edges are raised and conflict resolution still picks the higher direct version.
  - `BackendSkeletonKotlinJvmConventions` (plugin `kotlin-jvm-conventions`, applied by no repo) was aligned.
  - 6 tests with literal versions, all passing, including the `4.2.9.Final` < `4.2.18.Final` < `4.2.19.Final` ordering. "Above the minimum does not violate" would catch a regression back to `matches`. The wiring in the convention itself isn't tested.
- Principles: none
- Importance: 4 — resolved versions silently differed from the catalog in every repo.
- Confidence: 5
- Recommendation: REDO AS IS

### 3.2 — Jib fingerprint `.convention(settings.x).convention(default)`
- Defect in base: REAL. In base `JibDockerBuildConvention.kt:46-54`, a second `convention()` call replaces the first, so the fingerprint task always saw the defaults for 9 inputs. Changing `jvmFlags`/`environment`/etc. didn't change the fingerprint.
- Fix: CORRECT. `convention(settings.x.orElse(default))` for all 9. `user`/`imageFormat` now enter the fingerprint even though Jib ignores them (3.3). That can only cause extra re-runs, never missed ones.
- Principles: none
- Importance: 3 — container tests and the scan could be skipped after an image configuration change.
- Confidence: 5
- Recommendation: REDO AS IS

### 3.3 — Jib `user`/`imageFormat` hardcoded; KDoc says the reproducible default is false (partial)
- Defect in base: REAL. `defaultReproducibleBuild = true` while the KDoc said false, and `user = Extension.defaultUser` / `setFormat(Extension.defaultImageFormat)` are hardcoded.
- Fix: CORRECT for what was done. Only the two KDoc lines were changed; the hardcoding is left as `needs decision`.
- Principles: none
- Importance: 2 — docs accuracy.
- Confidence: 5
- Recommendation: REDO AS IS (KDoc only)

### 3.4 — `DependencyUpdateConvention` read `versionSelector` at apply time
- Defect in base: REAL but latent. `versionSelector(extension.versionSelector.getOrElse(PREFER_STABLE))` runs at apply time, before the consumer's script. No repo sets the property.
- Fix: CORRECT. VCU's own `versionSelector { }` extension wraps a lambda that reads the provider at select time. I checked the VCU 1.1.1 jar: `VersionCatalogUpdateTask` is `notCompatibleWithConfigurationCache`, so capturing the lambda and provider is safe.
- Principles: none (makes a public contract honest)
- Importance: 2 — latent.
- Confidence: 4
- Recommendation: REDO AS IS

### 3.5 — `UpdateSummaryTask` used `project.projectDir` at execution time
- Defect in base: REAL. `project.projectDir` was called inside `summarize*`/`gitOrNull` in the plugin copy (`:61,94,188`) and the root copy. That is a configuration-cache problem, and lattice runs with the default `problems=fail`. `workspace.sh:530-532` hid the failure with `2>/dev/null || true`.
- Fix: CORRECT. A `private val projectDirectory: File = project.projectDir` field, captured at construction and serialisable by the configuration cache, in both copies. Minimal.
- Principles: none
- Importance: 3 — lattice's update summary was silently empty.
- Confidence: 4
- Recommendation: REDO AS IS

### 3.6 — Test report dirs keyed by project name only
- Defect in base: REAL. `TestTaskConventions.kt:38-41` uses `test-results/test/<project>` for every `Test` task, including `securityScan` (a `Test` registered in the same project) and `containerBasedServiceTest`. That means overlapping outputs and overwritten reports.
- Fix: CORRECT. `${this@configureEach.name}` replaces the hardcoded `test`, so the path for the `test` task is unchanged. I found nothing that reads these paths. The unused `BackendSkeletonKotlinJvmConventions` was aligned too.
- Principles: none
- Importance: 2
- Confidence: 4
- Recommendation: REDO AS IS

### 3.7 — `MavenPublishConvention` `doLast` read `project`
- Defect in base: REAL. `MavenPublishConvention.kt:53` called `println("Published ${project.group}...")` inside `doLast`, which is a configuration-cache problem.
- Fix: CORRECT. Coordinates are captured in the configure block, the same pattern as root `build.gradle.kts`. `publish-if-changed.sh` still forces `--no-configuration-cache`; not changed, which is fine.
- Principles: none
- Importance: 2
- Confidence: 5
- Recommendation: REDO AS IS

### 3.9 — Duplicate `<name>-maven` publication alongside `pluginMaven`
- Defect in base: REAL. Base root `build.gradle.kts:59-67` created a second `MavenPublication` with the same GAV as the `java-gradle-plugin` `pluginMaven`.
- Fix: CORRECT. The manual publication is removed and `PublicationStateSupport.publicationName` now returns `"pluginMaven"`. GAV is unchanged (`allprojects { group = projectGroup; version = currentVersion }`). 1.0.33 was published and consumed. The `publication-state.properties` hash changes are expected from the code and version change.
- Principles: none
- Importance: 1 — duplicate work and warnings.
- Confidence: 4
- Recommendation: REDO AS IS

### 3.11 — README/IMPROVEMENTS stale; wrapper changes suppressed in root `UpdateSummaryTask`
- Defect in base: REAL. The README cited `updateGradle`/`updateDependencies` and an `includeBuild`/`classpath` usage that no longer applies. IMPROVEMENTS claimed no plugin IDs, CC disabled and Gradle 9.4.0. In root `build.gradle.kts:164`, the `gradle-wrapper.properties` branch returned `null` for every key, so `extractGradleVersion` (`:221`) was dead.
- Fix: CORRECT. The new README usage matches swissknife's actual `settings.gradle.kts`, catalog and `plugins` block. Root summary now mirrors the plugin copy (`distributionUrl` → "Gradle: a → b"). IMPROVEMENTS LOC counts are approximate (cosmetic).
- Principles: none
- Importance: 2
- Confidence: 4
- Recommendation: REDO AS IS

### 4.3 — Nullable unions lack `"default": null`
- Defect in base: REAL as stated (30 of 31 `["null", X]` fields had no default), but it only matters for registry schema evolution.
- Fix: CORRECT and complete. I scanned every `.avsc`: 31 nullable fields, all null-first, all with `default: null`. No other changes.
- Principles: CONFLICT in rationale with principle 1. The motivation is FULL_TRANSITIVE evolution compatibility, which the owner explicitly doesn't need. Tests start fresh Pulsar instances, so no registry history exists. The edit itself is harmless; the one small side benefit is that `GenericRecordBuilder` can leave such fields unset.
- Importance: 1
- Confidence: 5
- Recommendation: DROP: the defect is premised on compatibility guarantees the owner doesn't want. Keeping it is harmless if preferred.

### 4.13 — acme README/IMPROVEMENTS stale
- Defect in base: REAL. The README said "Playground", Java 23, `updateGradle`/`updateDependencies`/`publishLibraries`. IMPROVEMENTS had Gradle 9.4.0 and 77/79 schemas.
- Fix: CORRECT. The justfile has `update-gradle`/`update-dependencies`/`publish`, the JVM target is `JVM_25`, and counts match the files: 63/10/50/59, 182 total.
- Principles: none
- Importance: 2
- Confidence: 5
- Recommendation: REDO AS IS

### 4.14 — `.gitignore` fused `*.pidjava_pid*.hprof` (checked in every listed repo)
- Defect in base: REAL in gradle-plugins (`.gitignore:41`) and acme-schema-catalogue (`:40`). Elsewhere:
  - workspace root `.gitignore` has no such line.
  - aggregator's `.gitignore` has no pid/hprof lines.
  - lattice has `java_pid*.hprof` on its own line (`:10`) and no `*.pid`, so it isn't fused there.
- Fix: CORRECT. Split into `*.pid` and `java_pid*.hprof` in gradle-plugins and acme. This matters a little because the `push` recipes do `git add -A`.
- Principles: none
- Importance: 2
- Confidence: 5
- Recommendation: REDO AS IS

### 10.22 — `sed -i ''` BSD-only in `scripts/update-gradle.sh` (checked in every listed repo)
- Defect in base: REAL only on GNU sed. The workspace is macOS-only: Homebrew bootstrap, `/usr/libexec/java_home`, and no `.github/workflows` in any repo. Per repo:
  - gradle-plugins and acme: fixed.
  - lattice: still `sed -i ''` (left untouched, as intended).
  - aggregator: has no script.
  - workspace root: has no `update-gradle.sh`, but `scripts/publish-if-changed.sh:27,105` still uses `sed -i ''`. So the "portability" isn't consistent even within the session.
- Fix: CORRECT but INCOMPLETE for its own goal: `sed -i.bak … ; rm "${props_file}.bak"`.
- Principles: none
- Importance: 1 — no Linux execution path exists.
- Confidence: 5
- Recommendation: DROP: no Linux user or CI, and the change is inconsistent with the remaining `sed -i ''` uses. If portability is ever wanted, do it everywhere at once, including `publish-if-changed.sh` and lattice.

## Unattributed changes

- workspace root: none beyond the checklist items. `BUG_HUNT_CHECKLIST.md` and `analysis/BUG_HUNT_2026-10-04.md` are session artifacts. Every hunk in CONTEXT.md, README.md, justfile, `policy/` and `scripts/` maps to 1.1, 1.3, 1.4, 1.5, 1.6, 1.8, 1.9, 1.11, 1.12, 1.13 or 1.15. The only cosmetic leftover is the double blank line in `prepare_base_image_policy` (1.12).
- gradle-plugins: none. `import java.io.File` in root `build.gradle.kts` belongs to 3.5. The catalog test libraries and the `components/base` test setup belong to 1.14/3.1. The justfile belongs to 1.13. Mechanical-only: `gradle.properties` `currentVersion` 1.0.32→1.0.33 and `publication-state.properties` (version and hashes).
- acme-schema-catalogue: none. Mechanical-only: `currentVersion` 1.0.6→1.0.7, `sollecitom-gradle-plugins` 1.0.32→1.0.33, and `publication-state.properties`.
- aggregator: the whole commit 35d8d0b adds 11 files that were untracked owner work: CONTEXT, LICENSE, README, `build.gradle.kts`, `gradle.properties`, wrapper, `gradlew(.bat)`, justfile, `settings.gradle.kts`. Only the `settings.gradle.kts`/README/CONTEXT edits for 2.1 are attributable. The rest is owner content committed without being asked, and its pre-session text can't be diffed.
- lattice: purely mechanical. `currentVersion`/`publishedVersion` 1.0.8→1.0.10, `sollecitom-gradle-plugins` 1.0.32→1.0.33, `sollecitom-swissknife` 1.0.35→1.0.37, plus artifact hashes. These came in two commits: 7cf658b at 2026-10-05 00:11 ("Bump internal dependency versions") and f722aa4. Note that the checklist's "lattice 1.0.9 / swissknife 1.0.36" understates what was published: there were two publish rounds.
