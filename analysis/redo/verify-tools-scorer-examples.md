# Independent verification: tools, quality-scorer, examples, facts (sections 5–8)

Refs checked: tools f01f824..ea1379e, quality-scorer 72f5823..b415dc7, examples fb10e63..ea7c232, facts 9e58128..eaa8881 (all equal to `bug-hunt-snapshot-2026-10-05` and to `analysis/redo/patches/<repo>.patch`).

How I checked:
- package-migrator: ran the compiled snapshot classes (`tools/modules/package-migrator/domain/build/classes`, built 2026-10-05 00:05, contain the `relativize` calls) through a throwaway Java driver on `/tmp` trees. I also ran a faithful Java copy of the base algorithm.
- SnakeYAML 2.7 behaviour: checked in jshell.
- Everything else: traced by reading the code.
- No workspace builds were run.

Items in scope: 5.1, 5.4, 5.6, 5.7, 5.8, 5.10, 6.1 (partly fixed), 6.3, 6.4, 6.7, 7.1, 7.2, 7.3, 7.4. Section 8 has no fixes.

---

### 5.1 — package-migrator matches/rewrites the package path inside the absolute path
- Defect in base: REAL. In `StaticPackageMigration.kt` (f01f824):
  - Line 70: `isWithinPackage` is `pathString.contains(...)` on the absolute path.
  - Line 48: `movePackage` does `pathString.replaceFirst(...)` on the absolute path.
  - Line 66: `isWithinFolder` splits the absolute path, so a root under a folder named `build` or `gradle` excludes every file.
  - Demonstrated with root `/tmp/x/com/example-svc` and `com.example → org.foo`. The base algorithm moved both `other/B.kt` (not in the package) and `com/example/A.kt` to `/tmp/x/org/foo-svc/...`, which is outside the project.
- Fix: CORRECT.
  - All three checks now work on `root.relativize(this)`, and the new path is resolved against the root.
  - Ran the snapshot classes on the same tree: only `A.kt` moved, to `<root>/src/main/kotlin/org/foo/A.kt`, with its package rewritten. `B.kt` was untouched.
  - The change is minimal with no unrelated edits. Segment boundaries are deliberately not addressed (that is 5.2).
  - No test was added; tools has no test source set anywhere.
- Principles: minor. The non-trivial logic has no JUnit test (only manual /tmp verification).
- Importance: 4. It destroys the tree by moving files outside the project. The trigger (a root path that contains the package path) is uncommon, and the tool is run by hand.
- Confidence: 5. Demonstrated on base and snapshot.
- Recommendation: REDO AS IS. Optionally add a JUnit/AssertK temp-dir test (root path containing the package path) if a test setup is added to tools.

### 5.4 — package-migrator mutates the tree while lazily walking it
- Defect in base: REAL.
  - `Directory.kt:19` is `Files.walk(path).asSequence()`: a lazy stream that is never closed.
  - `StaticPackageMigration.kt:17-24` moves files while iterating it.
  - Demonstrated with the base algorithm: `a.b → a.b.v2` on a directory of 3000 files recursed without end. After about 28k moves, paths looked like `a/b/v2/v2/v2/.../X383.kt`. Small directories (8 files) did not recurse on APFS because readdir buffers them.
- Fix: INCOMPLETE.
  - `Files.walk(path).use { it.toList() }.asSequence()` is correct. It also fixes the stream leak.
  - With the snapshot classes on the same 3000-file tree, every file was moved once and rewritten once (0 files containing `v2.v2`).
  - **However, the finding's own scenario still fails.** The directory phase then calls `movePackage` on the non-empty `a/b/v2` and tries to move it into `a/b/v2/v2`, which throws `FileSystemException: Invalid argument`. I demonstrated this with the snapshot classes on both the 1-file and the 3000-file trees. The files end up correct, but the run crashes.
  - The base code has the same directory-phase crash. This is a separate, pre-existing defect that the agent's "/tmp verification" missed.
- Principles: none. No test (same as 5.1).
- Importance: 4. `a.b → a.b.v2` (target contains source) is a plausible migration. Base corrupts files without end; snapshot crashes after correct file moves.
- Confidence: 5. Demonstrated.
- Recommendation: REDO AS IS for the one-liner, and open a new item. The directory phase (`directoriesWithinPackage` plus moving non-empty directories) must skip directories that are, or contain, the target package path. This ties in with 5.5 (how the directory phase treats excluded folders).

### 5.6 — license-audit cache skip ignores waiver expiry
- Defect in base: REAL.
  - `LicenseAudit.kt:108-120`: `policyFingerprint` hashes only file contents (policy yml, the audit source, the repo waiver file).
  - Expired waivers are dropped in `loadWaivers` (line 427) only after the fingerprint has been computed.
  - With unchanged files, line 119 returns `cachedState.findings`, which were computed with the waiver applied. The audit prints "Ignoring expired waiver…" and still exits 0.
  - Components reused on the non-skip path (line 256) keep the waived finding the same way.
- Fix: CORRECT.
  - Waivers are loaded before the fingerprint, and `computePolicyFingerprint` hashes the file fingerprint together with `activeWaivers.joinToString()` (`Waiver` is a data class, so its `toString` is stable).
  - When a waiver expires, the active set changes, so `policyFingerprintChanged` becomes true and every coordinate is re-evaluated without the waiver.
  - A `today: LocalDate = LocalDate.now()` constructor parameter was added so the expiry check can be tested. Production callers are unaffected.
  - Self-check `checkExpiredWaiverIsNotServedFromCache` runs twice: today = 2026-01-01 expects 0, then 2026-01-02 expects 1. Without the fingerprint change the second run takes the skip path and returns 0, so the check would fail.
- Principles: tension with rule 3.
  - The new checks extend the module's existing `main()` + `check()` self-check (wired into `check` via the `selfCheck` task). They are not JUnit/AssertK tests with backtick names.
  - They are consistent with the module, but not with the owner's test style. 5.9, the self-check strategy, is still undecided.
- Importance: 3. A wrong pass on a used path (`build-workspace` runs `license-audit-compact`), but no `license-waivers.yml` exists in any repo today, so it is latent.
- Confidence: 5. Clear trace, and the self-check logic is sound.
- Recommendation: REDO MODIFIED. Same production change. Express the scenario as a JUnit/AssertK test, unless the owner decides (5.9) to keep the self-check harness, in which case keep the check as is.

### 5.7 — license-audit policy changes reuse cached raw licenses / overrides
- Defect in base: REAL.
  - `LicenseAudit.kt:272`: when the policy changed, `cachedComponent` is passed in.
  - Lines 303-308 then reuse `cachedComponent.rawLicenses` and never reach `packageOverrideFor` (line 310).
  - So an override added to `policy/license-policy.yml` is ignored for already-cached coordinates. A removed override keeps applying through the cached `"policy-override"` raw license.
  - Overrides are actively used: `package_overrides` exists in the policy for jib and docker-java.
- Fix: CORRECT.
  - `packageOverrideFor` is checked first.
  - The cached component is reused only when the policy changed and its source is neither `policy-override` nor retriable.
  - Includes a refactor: the `POLICY_OVERRIDE_RESOLUTION_SOURCE` constant.
  - Self-check `checkPackageOverrideChangesApplyToCachedComponents`: MIT expects 0, then adding a GPL override expects 1, then removing it expects 0. In base the second run reuses the cached MIT and returns 0, so the check fails without the fix.
  - No network is used: the POM is pre-seeded under `.workspace-run-state/license-audit/poms`, the path `fetchPom` checks first.
- Principles: the same self-check vs JUnit tension as 5.6.
- Importance: 4. The plausible workflow is editing the policy to fix a failing audit; in base it keeps failing (or keeps passing) until `--force`.
- Confidence: 5.
- Recommendation: REDO MODIFIED. Same production change; test form as for 5.6.

### 5.8 — license-audit caches transient POM fetch failures as UNKNOWN
- Defect in base: REAL.
  - The resolver is designed to retry `missing`/`parent-missing` (line 986).
  - But the repo-level skip (lines 113-120) returns cached findings first.
  - On the non-skip path, coordinates with unchanged configurations are reused as-is (lines 251-260).
  - So a one-off fetch failure stays UNKNOWN (exit 1) until `--force`.
- Fix: CORRECT.
  - The skip path also requires that no cached component has a retriable source.
  - Retriable coordinates are added to `changedCoordinates`.
  - Retriable cached components are never reused.
  - The resolver's inline `setOf("missing","parent-missing")` now uses the shared `retriableResolutionSources` (a pure refactor).
  - Side effect: a permanently missing POM now re-runs the evaluation on every audit, re-using the snapshot but re-trying curl against 3 repos at up to 15 s each. That matches the resolver's existing retry intent, and such a coordinate fails the audit anyway unless waived. Acceptable.
  - Self-check `checkMissingPomResolutionIsRetriedOnCachedRuns`: it edits `state.json` to mark the component `missing` and expects 0. In base the skip path returns the cached UNKNOWN (exit 1), so the check would fail.
  - The check only exercises the repo-level path; the retry itself is satisfied by the resolver cache. That is enough for the defect.
- Principles: the same self-check vs JUnit tension.
- Importance: 3. A loud but sticky false failure on a used path; `--force` works around it.
- Confidence: 5.
- Recommendation: REDO MODIFIED. Same production change; test form as for 5.6.

### 5.10 — license-audit crashes on an unquoted YAML waiver date
- Defect in base: REAL.
  - `LicenseAudit.kt:425` is `LocalDate.parse(waiverMap["expires"]?.toString())`.
  - Verified in jshell with snakeyaml 2.7: `expires: 2026-01-01` loads as `java.util.Date` ("Thu Jan 01 00:00:00 GMT 2026"), and `LocalDate.parse` of that string throws `DateTimeParseException`.
- Fix: CORRECT.
  - A `when` maps `java.util.Date` to a UTC `LocalDate`. SnakeYAML parses date-only values as UTC midnight, so the result is 2026-01-01 (verified); anything else goes through `LocalDate.parse`.
  - Self-check `checkUnquotedWaiverDateIsAccepted` would throw without the fix.
  - Style nit: fully-qualified `java.util.Date` and `java.time.ZoneOffset.UTC` inline instead of imports.
- Principles: the same self-check vs JUnit tension.
- Importance: 2. A clear crash rather than a wrong answer, and no waiver files exist today.
- Confidence: 5. Demonstrated.
- Recommendation: REDO AS IS (move the qualified names into imports). Test form as for 5.6.

### 6.1 — `--project` not validated (partly fixed: non-directory exits 2)
- Defect in base: REAL.
  - `Main.kt:13-18` passes `File(project)` straight to `Grader`.
  - `KotlinProjectLoader.kt:11` walks zero files.
  - `FunctionLengthRule` and `PublicApiKDocRule` return `Score.perfect` on empty input; coverage and assertion-density return 0.
  - With weights 0.50/0.175/0.175/0.15, the reward is 0.65.
- Fix (partial): CORRECT.
  - A non-directory `--project` now prints an error and exits 2, matching the KDoc's "2 on a usage error".
  - Minimal, no test (`main` calls `exitProcess`).
  - An empty directory still scores 0.65. That remains open as a needs-decision item.
- Principles: none.
- Importance: 4. A grader reward for nothing on a path typo, the most likely misuse.
- Confidence: 5.
- Recommendation: REDO AS IS for the non-directory check. Leave the empty-directory policy to the owner's decision.

### 6.3 — `TEST_ANNOTATION` matches `@BeforeTest`/`@AfterTest`
- Defect in base: REAL. `HeuristicKotlinAnalyzer.kt:193` is `@\w*Test\b`, used at lines 45 and 76 to set `isTest`. kotlin.test `@BeforeTest`/`@AfterTest` functions therefore count as tests with no assertions, which lowers assertion density.
- Fix: CORRECT.
  - Regex changed to `@(?!BeforeTest\b|AfterTest\b)\w*Test\b`. This denylist is narrower than the report's allowlist suggestion, and it keeps custom `@…Test` annotations working.
  - The new backtick test covers both detection paths: the annotation above the function and on the same line. It expects literally `containsExactlyInAnyOrder("parameterised")`.
  - Without the fix, `setUp`/`tearDown` would also be included, so the test fails.
  - Style is consistent (JUnit, AssertK, PER_CLASS).
- Principles: none.
- Importance: 3. Wrong scores for kotlin.test-style projects only.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 6.4 — `kotlin-compiler-embeddable` declared but unused
- Defect in base: REAL. `content/kotlin/analysis/build.gradle.kts:7` declares it, and `git grep` finds no use of any compiler/PSI API. The analyzer KDoc says "no Kotlin compiler / PSI dependency". The `fatJar` bundles the whole runtime classpath.
- Fix: CORRECT. The dependency and its catalog entry are removed. The swappable `KotlinSourceAnalyzer` contract is untouched, so a future PSI analyzer can re-add it. The claimed size drop (65.6 MB to 3.5 MB) was not re-measured.
- Principles: none. YAGNI on a dependency, not a contract.
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 6.7 — JSON output doesn't escape all control characters
- Defect in base: REAL. `QualityReportJson.kt:24-35` escapes only `\\ " \n \r \t`. Any other character below 0x20 is emitted raw, which is invalid JSON.
- Fix: CORRECT.
  - `else -> if (c < ' ') append("\\u%04x".format(c.code)) else append(c)`. Hex formatting does not depend on locale.
  - The new test feeds real U+0001 and U+001F and expects the literal raw-string text `"message": "a\u0001b\u001fc"`. It fails without the fix.
  - Style compliant.
- Principles: none.
- Importance: 2. Finding messages are built from source names and paths, so control characters are unlikely.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 7.1 — `Transaction.equals` compares id only
- Defect in base: REAL.
  - `Transaction.kt:41-46` (test fixture) compares class and `id` only.
  - `AvroSerdeTestSpecification` asserts `isEqualTo(value)` (swissknife test utils, line 33), and `PulsarMessagingTests` uses `matches`. So a serde that drops or swaps `amount`, `tag`, `cardNumber`, `quantity`, `assetId` or `pricePerShare` would pass.
- Fix: CORRECT.
  - `equals` now compares a `fields` list per sealed branch.
  - `hashCode` stays id-based, which is still consistent.
  - `cardNumber` is a `ProtectedValueData`, which has value equality (bytes, name, owner, metadata), so round-trips compare meaningfully. The checklist says the suite passed afterwards; I could not re-check that (no test-result XML present).
  - No new test is needed: the existing round-trip tests become able to catch field corruption.
  - Naming nit: `fields` is vague (e.g. `equalityFields`).
- Principles: rule 3 naming nit only.
- Importance: 3. Tests that could not catch regressions.
- Confidence: 4.
- Recommendation: REDO AS IS (optionally rename `fields`).

### 7.2 — D&D modifier uses truncating division
- Defect in base: REAL. `RolePlayingGamesTests.kt:223` is `(this - 10) / 2`. A score of 9 gives 0 instead of -1. The real rule is floor((score - 10) / 2).
- Fix: CORRECT.
  - `(this - 10).floorDiv(2)`.
  - The new test uses strength 9, DC 13 and a roll of 13. Truncation gives modifier 0, so 13 >= 13 succeeds and the test fails; floor gives 12, a failure, so it passes.
  - Literal expectation, backtick name, no comment.
- Principles: none.
- Importance: 2. Kata logic inside test sources.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 7.3 — `KClass` identity comparison
- Defect in base: REAL but latent.
  - `EventFrameworkExampleTests.kt:88` is `stream.eventClass !== eventClass`.
  - Without kotlin-reflect, `EVENT::class` yields a fresh `ClassReference` per evaluation (line 57 builds a new one for each reference). Identity would then fail for the same class. `ClassReference.equals` compares the Java class.
  - The tests pass today: either the same stream is never re-fetched through a new reference, or kotlin-reflect caches.
- Fix: CORRECT. `!=`, one character.
- Principles: none.
- Importance: 1.
- Confidence: 4.
- Recommendation: REDO AS IS.

### 7.4 — IMPROVEMENTS.md stale
- Defect in base: PARTLY.
  - False claims: SNAPSHOT dependencies (pinned versions), configuration cache disabled (`gradle.properties` has `org.gradle.configuration-cache=true`), no Pulsar end-to-end tests (`PulsarMessagingTests` uses `newPulsarContainer`), and Gradle 9.4.0 (the wrapper is 9.8.0).
  - But the report's "23 test files" claim was wrong: base has exactly 23 `.kt` files under `src/test` and 0 under `src/main`.
- Fix: CORRECT. Gradle changed to 9.8.0, the three false issues and the Testcontainers improvement removed, items renumbered. "23 test files" is correctly left alone.
- Principles: none.
- Importance: 2. Docs accuracy.
- Confidence: 5.
- Recommendation: REDO AS IS.

---

## Unattributed changes

All diffs in base..snapshot for tools, quality-scorer, examples and facts are accounted for. The only changes not explained by sections 5–8 belong to other checklist items:

- **4.14 `.gitignore` fused line** (`*.pidjava_pid*.hprof` split into `*.pid` and `java_pid*.hprof`): tools, examples, facts. quality-scorer's base already had the two lines split, so it is unchanged. Correct.
- **10.22 `scripts/update-gradle.sh`** (`sed -i ''` replaced by `sed -i.bak …` plus `rm "${props_file}.bak"`): tools, quality-scorer, examples, facts. Portable and correct under `set -e`.
- **`gradle/libs.versions.toml` version bumps:** mechanical.
  - tools and quality-scorer: gradle-plugins 1.0.32 → 1.0.33, swissknife 1.0.35 → 1.0.37.
  - examples: the same two bumps, plus pillar 1.0.17 → 1.0.19.
  - facts: no bump.
  - The second commit in each repo only moved swissknife 1.0.36 → 1.0.37 (and pillar 1.0.18 → 1.0.19 in examples). The checklist status still says swissknife 1.0.36 and pillar 1.0.18 were published, so that text is out of date.
- **quality-scorer catalog:** removal of the `kotlin-compiler-embeddable` entry, which belongs to 6.4.

No other edits.

## Summary

| Item | Defect | Fix | Imp | Conf | Recommendation |
|---|---|---|---|---|---|
| 5.1 | REAL | CORRECT | 4 | 5 | REDO AS IS |
| 5.4 | REAL | INCOMPLETE | 4 | 5 | REDO AS IS + new item (directory-phase crash when the target contains the source) |
| 5.6 | REAL | CORRECT | 3 | 5 | REDO MODIFIED (test form) |
| 5.7 | REAL | CORRECT | 4 | 5 | REDO MODIFIED (test form) |
| 5.8 | REAL | CORRECT | 3 | 5 | REDO MODIFIED (test form) |
| 5.10 | REAL | CORRECT | 2 | 5 | REDO AS IS (imports nit) |
| 6.1 (partial) | REAL | CORRECT | 4 | 5 | REDO AS IS |
| 6.3 | REAL | CORRECT | 3 | 5 | REDO AS IS |
| 6.4 | REAL | CORRECT | 2 | 5 | REDO AS IS |
| 6.7 | REAL | CORRECT | 2 | 5 | REDO AS IS |
| 7.1 | REAL | CORRECT | 3 | 4 | REDO AS IS |
| 7.2 | REAL | CORRECT | 2 | 5 | REDO AS IS |
| 7.3 | REAL (latent) | CORRECT | 1 | 4 | REDO AS IS |
| 7.4 | PARTLY | CORRECT | 2 | 5 | REDO AS IS |
