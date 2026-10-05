# Bug hunt checklist

Working list for the 2026-10-04 bug hunt across every repo except lattice, numbered `section.point` in dependency
order. Full write-ups (file:line, failure scenario, suggested fix) are in
[`analysis/BUG_HUNT_2026-10-04.md`](analysis/BUG_HUNT_2026-10-04.md). Severity: **C** critical, **H** high, **M** medium,
**L** low. `[x]` means resolved (fixed, or a deliberate no-change decision), with the outcome noted. Update this file
whenever an item is decided.

## Status after the overnight pass (2026-10-05)

- Every item was re-verified against the code; items that were real, certain and free of trade-offs were fixed, with a
  test that fails without the fix wherever the logic was non-trivial. Open items carry the reason they were left
  (`needs decision: …` = real but involves a choice; `uncertain: …` = couldn't be fixed safely without one).
- `just build-workspace` passed end to end; producers published gradle-plugins 1.0.33, acme-schema-catalogue 1.0.7,
  swissknife 1.0.36, pillar 1.0.18, lattice 1.0.9 (lattice only received the mechanical version bumps), and every
  consumer built against them.
- Committed locally in each repo, not pushed. Pre-existing uncommitted changes were included in those commits:
  `.trivyignore` in modulith-example and element-service-example, and aggregator's untracked files.
- Corrections to the original reports discovered while fixing: 4.9, 4.15, 9.58, 9.67, 10.32 are not bugs; 9.22 is real
  but mis-described (empty map, not nulls); 9.6 and 9.47 are contract questions rather than defects.

## 1. Workspace root (scripts, justfile, docs, policy)

- [x] 1.1 **H** Docker image cleanup kept arbitrary images (`.Created` is 1970 for Jib), and `\t` in the inspect format was literal, so every cleanup deleted all tags — fixed: rank by `LastTagTime`, real tab, keep-guard, warn on failed `rm`
- [x] 1.2 **H** Gradle lock retry dead under `set -e` for update/update-internal/publish — fixed
- [x] 1.3 **H** CycloneDX aggregate tasks didn't declare per-project outputs as inputs, so the license audit read stale snapshots — fixed (option 1) and documented in README/CONTEXT
- [x] 1.4 **M** Every flow upgraded Homebrew packages (JDK included) — fixed: only `update`/`install` upgrade, others `check`; added time-bounded Homebrew holds (`policy/version-holds.txt`)
- [x] 1.5 **M** Base-image fallback not shown in the update summary — fixed
- [x] 1.6 **M** Base image pinned to the arm64-only digest — fixed: pin the multi-platform index digest
- [x] 1.7 **M** `reinstall-workspace` deletes repos without checking for unpushed work — declined
- [x] 1.8 **L** License-audit runner staleness — finding was wrong for workspace flows; `run-license-audit.sh` simplified to always `installDist`
- [x] 1.9 **L** Test summary garbled by CR; OSC `ESC \` not stripped — fixed
- [x] 1.10 **L** Lock retry `pkill`s every Gradle daemon — no change (needed: the journal lock is shared across Gradle versions)
- [x] 1.11 **L** Dead code in `workspace.sh` (unreachable standalone commands incl. destructive `reset`, unused helpers, unused `publishable` arg, stale resumability comment) — removed
- [x] 1.12 **L** Dockerfile `FROM` only updated with a runtime variant — the whole unused Dockerfile/runtime-variant branch removed
- [x] 1.13 **L** Maven-local cleanup never pruned gradle-plugins plugin markers — fixed: `--plugin-markers sollecitom`
- [x] 1.14 **L** A manual bump to `2.0.0` published `2.0.1` — fixed in both gates (`PublicationHashGate`, buildSrc `PublicationStateSupport`), `nextPatchVersion` renamed `nextVersion`; first gate tests added (gradle-plugins now has JUnit/AssertK test setup)
- [x] 1.15 **L** Docs: `CONTEXT.md` claims service-repo builds are skipped during `update` (not implemented); README "Allowed steps" omits `license-audit`/`license-audit-compact`; `CONTEXT.md` says `~/workspace`; CONTEXT blames Kotlin compiler daemons for locks (all repos compile in-process) — fixed: CONTEXT (repo layout, Kotlin-daemon claim, nonexistent service-build skipping), README allowed steps + Docker cleanup wording
- [ ] 1.16 **L** `policy/license-policy.yml` aliases `MIT-0`→`0BSD` and `Public Domain`→`CC0-1.0` (different licenses) — needs decision: real; which licenses to allow is a policy choice

## 2. aggregator

- [x] 2.1 **M** `settings.gradle.kts` requires `../backend-skeleton` (doesn't exist), so every command fails; `quality-scorer` missing — fixed: removed backend-skeleton, added quality-scorer (settings, README, CONTEXT); not built

## 3. gradle-plugins

- [x] 3.1 **H** Minimum-dependency-version convention pins the minimum exactly, silently downgrading newer versions — fixed: pins only when the requested version is below the minimum (or unparsable); 6 tests
- [x] 3.2 **H** Jib `.convention(settings.x).convention(default)` drops user settings from the image fingerprint, so container tests/scan don't rerun on config changes — fixed: `convention(settings.x.orElse(default))` for all 9 fingerprint inputs
- [ ] 3.3 **M** Jib `user`/`imageFormat` hardcoded; KDoc says reproducible default is false (it's true) — KDoc corrected; needs decision: honouring user/imageFormat needs afterEvaluate (Jib API is eager) or dropping the two settings
- [x] 3.4 **M** `DependencyUpdateConvention` reads `versionSelector` at apply time (user value ignored; latent) — fixed: selector read lazily
- [x] 3.5 **M** `UpdateSummaryTask` uses `project.projectDir` at execution time (configuration cache; failure hidden by `|| true`) — fixed: project directory captured at configuration (plugin task and root build copy); verified with configuration-cache=fail
- [x] 3.6 **L** Test report dirs keyed by project name only (tasks overwrite each other) — fixed: report dirs keyed by task name too (test task paths unchanged)
- [x] 3.7 **L** `MavenPublishConvention` `doLast` reads `project` (why publish needs `--no-configuration-cache`) — fixed: coordinates captured at configuration
- [ ] 3.8 **L** Placeholder `maven.pkg.github.com/acme/*` repo added whenever GitHub env vars are set — needs decision: real; whether the placeholder repo should exist at all
- [x] 3.9 **L** Duplicate `<name>-maven` publication alongside `pluginMaven` — fixed: manual publication removed; publication state uses pluginMaven (hashes unchanged)
- [ ] 3.10 **L** `UpdateInternalCatalogVersionsTask` registered but never used, and diverges from the script — needs decision: real; delete (drops public `internalGroups` extension) or align with the script
- [x] 3.11 **L** README/IMPROVEMENTS stale; wrapper-change suppression and dead `extractGradleVersion` — fixed: README/IMPROVEMENTS facts; wrapper changes now summarised via the previously dead `extractGradleVersion`

## 4. acme-schema-catalogue

- [ ] 4.1 **H** `AccountEvent.avsc` declares record `AccountPlanEvent` — needs decision: rename to AccountEvent (+ alias) is backward- but not forward-compatible, so a FORWARD/FULL registry would reject it (a fix was tried and reverted)
- [ ] 4.2 **H** `EntityEvent.json` unsatisfiable (broken `allOf` ref, conflicting `additionalProperties`, wrong refs) — needs decision: real; Event.json has additionalProperties:false, so composition needs restructuring; unused
- [x] 4.3 **M** Nullable unions lack `"default": null` (blocks FULL_TRANSITIVE evolution) — fixed: `default: null` on all 30 nullable fields (all null-first); all schemas parse
- [ ] 4.4 **M** Growable enums lack `default` — needs decision: real (13 enums); default symbol per enum is a product choice
- [ ] 4.5 **M** `AuthenticatedAccess.json` requires `is-test`; Avro twin has no `is_test` — needs decision: real; add `is_test` to Avro (pillar serde change) or drop from JSON required
- [ ] 4.6 **L** `EncryptionMetadata` union omits XTS — needs decision: real; adding XTS needs a pillar change, or delete the XTS schema
- [ ] 4.7 **L** `ServiceAccount.json` flattened vs Avro internal/external union — needs decision: real; modelling choice
- [ ] 4.8 **L** `CurrencyAmount.json` `units` integer ≥ 0 vs Avro string (negatives) — needs decision: real; modelling choice
- [x] 4.9 **L** `DecimalToggleValue` is a `double` — not a bug: matches the domain (`DecimalToggleValue.value: Double`); only the name says decimal
- [ ] 4.10 **L** `Unit.json` only allows the placeholder `"<unit>"` — needs decision: real; fill the enum or delete
- [ ] 4.11 **L** `PaginationArguments.json` `limit` has no minimum — needs decision: real; minimum 0 or 1 is a product call
- [ ] 4.12 **L** `envelope_type` free string, not tied to the union branch — needs decision: real; modelling choice
- [x] 4.13 **L** README/IMPROVEMENTS stale — fixed: README (title, Java 25, recipes), IMPROVEMENTS (Gradle, schema counts)
- [x] 4.14 **L** `.gitignore` fused line `*.pidjava_pid*.hprof` — fixed in every repo except lattice (left untouched)
- [x] 4.15 **L** `scripts/update-gradle.sh` dead checksum comparisons (same file in tools, quality-scorer, examples) — not a bug: the comparisons make the script report checksum updates only when the wrapper changed

## 5. tools

- [x] 5.1 **C** package-migrator matches/replaces the package path in the absolute path (can move files outside the project) — fixed: paths judged/rewritten relative to the root (excluded-folder check too); verified on /tmp trees
- [ ] 5.2 **H** package-migrator text/path replacement has no identifier/segment boundaries — needs decision: real; whole-name matching changes the template-cloning use case and text/path matching must agree
- [ ] 5.3 **M** package-migrator targets the working directory; README stale — needs decision: real; CLI design
- [x] 5.4 **M** package-migrator mutates the tree while lazily walking it — fixed: walk materialised before mutating; verified on /tmp (old code recursed endlessly)
- [ ] 5.5 **M** package-migrator moves excluded directories but doesn't rewrite them — uncertain: real, suggested filter insufficient; how narrow the excluded-folder rule should be is a design choice
- [x] 5.6 **H** license-audit cache skip ignores waiver expiry (expired waiver keeps passing) — fixed: active waivers in the cache fingerprint; self-check
- [x] 5.7 **M** license-audit policy changes reuse cached raw licenses / overrides — fixed: overrides checked before cache, override results never reused; self-check
- [x] 5.8 **M** license-audit caches transient POM fetch failures as UNKNOWN — fixed: cached missing/parent-missing re-resolved; self-check
- [ ] 5.9 **L** license-audit self-check tests paths production never uses — needs decision: real; test strategy (new self-checks do cover the real path)
- [x] 5.10 **L** license-audit crashes on an unquoted YAML waiver date (`expires: 2026-01-01` parses as a Date) — fixed: java.util.Date accepted; self-check fails without the fix (DateTimeParseException), passes with it

## 6. quality-scorer

- [ ] 6.1 **H** `--project` not validated: empty/missing project scores 0.65 — non-directory `--project` now exits 2; needs decision: an empty directory still scores 0.65 (usage error vs score 0)
- [ ] 6.2 **M** Missing/unparsable `--coverage` silently scores 0 — needs decision: real; fail vs warn is grading policy
- [x] 6.3 **M** `TEST_ANNOTATION` matches `@BeforeTest`/`@AfterTest` — fixed: excludes @BeforeTest/@AfterTest; test
- [x] 6.4 **M** `kotlin-compiler-embeddable` declared but unused (fat JAR bloat) — fixed: dependency removed (fat JAR 65.6 MB → 3.5 MB)
- [ ] 6.5 **L** `productionFunctions` includes helpers in test sources — needs decision: real; scoring semantics
- [ ] 6.6 **L** Walk includes `build/`/`.gradle/`; `isTestPath` misses `testFixtures`/`integrationTest` — needs decision: real; scoring semantics
- [x] 6.7 **L** JSON output doesn't escape all control characters — fixed: all control chars escaped; test
- [ ] 6.8 **L** `SourceLocation` dead — needs decision: real; removing a field from Finding is a contract change

## 7. examples

- [x] 7.1 **H** `Transaction.equals` compares id only, so serde round-trip tests can't catch field corruption — fixed: equals compares all fields; no serde bugs surfaced; tests now catch swapped fields
- [x] 7.2 **M** D&D modifier uses truncating division — fixed: floorDiv; test
- [x] 7.3 **L** `KClass` identity comparison (`!==`) — fixed: `!=`
- [x] 7.4 **L** IMPROVEMENTS stale — fixed: IMPROVEMENTS facts
- [ ] 7.5 **L** `cardAuthWasProcessed` dead — needs decision: real; part of a factory set, deletion is taste
- [ ] 7.6 **L** Money fields as `double` in test schemas — needs decision: real; modelling

## 8. facts (unwired)

- [ ] 8.1 **L** `waitForTurn` matches historical events (replay flow) — real; facts is unwired — report only
- [ ] 8.2 **L** `runBlocking` in projection getter called from suspend code — real; facts is unwired — report only
- [ ] 8.3 **L** Vacuous `assertThat(true).isTrue()`; stale `.gitmodules` — real; facts is unwired — report only

## 9. swissknife

Core, kotlin-extensions, ddd, correlation, configuration, hashing, resource
- [x] 9.1 **H** KSUID factories freeze the clock at construction — fixed: clock read per id; 2 tests
- [ ] 9.2 **M** `UniqueIdFactory` internal/external ignore the injected clock/random — needs decision: real; honour the injected clock/random or drop the parameters
- [x] 9.3 **M** `UUIDv7(String/ByteArray)` doesn't check the version — fixed: non-v7 UUIDs rejected at construction; test
- [ ] 9.4 **M** `Id.fromString` doesn't round-trip type or text — needs decision: real; round-trip semantics of Id.fromString
- [x] 9.5 **M** `Version.compareTo` compares strings (`10.0.0 < 9.0.0`) — fixed: Semantic compares numerically; tests
- [ ] 9.6 **M** `CurrencyAmount` division rounds, multiplication truncates — needs decision: finding partly wrong — an existing test asserts division rounds; rounding policy is a choice
- [ ] 9.7 **M** Logged random seed can't reproduce; seeded `secureRandom` used for JWT keys — needs decision: real; seed / secureRandom design
- [x] 9.8 **L** `Number.dollars/euros/pounds` go through `toDouble()` — fixed: exact conversion for BigDecimal/BigInteger/integers/Float; tests
- [ ] 9.9 **L** `EmailAddress` validation too loose; test factory emits trailing dot — test factory trailing dot fixed; needs decision: how strict validation should be
- [ ] 9.10 **L** `EphemeralPort`/`RequestedPort` implement `Comparable<Int>`; "ephemeral" range wrong — needs decision: real; renaming/re-typing public types
- [ ] 9.11 **H** `Flow.chunk` emits one shared mutable list (`[[], []]`), stacks handlers, emits from another coroutine — fixed: chunks emitted as copies, per-collect state (2 tests); needs decision: timed flush from a child coroutine needs a channelFlow rewrite (buffering/backpressure, empty-chunk semantics)
- [x] 9.12 **M** `awaitAny` doesn't cancel the rest when one fails — fixed: remaining deferreds cancelled in finally; test
- [x] 9.13 **L** `ListExtensions` cyclic sequence shares its index across iterators — fixed: index per iteration; empty list → empty sequence; tests
- [x] 9.14 **L** `pow` goes through `Double` — fixed: exact integer pow, throws on overflow (negative exponents now throw instead of returning 0; no callers); tests
- [ ] 9.15 **L** `requiredBits` wrong for powers of two and 0 — uncertain: semantics undefined and unused; only 0 → Int.MIN_VALUE is wrong under every reading
- [x] 9.16 **M** `Happening.Type.parse` splits on every `--v` — fixed: split at last `--v`; test
- [ ] 9.17 **M** Invalid toggle value from a header makes context logging throw — needs decision: real; reject at gateway, lenient EnumToggle, or tolerate in logLevel
- [x] 9.18 **M** `Toggles.withToggle` doesn't replace an existing value — fixed: replaces existing value; test
- [x] 9.19 **M** `ActorTestFactory` impersonation arguments swapped — fixed: arguments un-swapped; test
- [x] 9.20 **L** `customerOrNull`/`tenantOrNull` let a specified target override the actor (see 10.2) — by design: the specified target is set by the gateway (decided 2026-10-05)
- [ ] 9.21 **L** `Trace.isParent` means "is root" — needs decision: real; public rename
- [ ] 9.22 **H** `configurationPropertiesUnderRoot` returns null values (Pulsar overrides dropped in both services) — needs decision: real but mis-described — http4k normalises keys (lowercase, `.`/`_`→`-`), so the result is an empty map and camelCase Pulsar names can't be recovered; needs an explicit key list or raw source
- [x] 9.23 **H** Blake3 `invoke(bytes, offset, length)` ignores the range and writes at the input offset — fixed: hashes the requested range, writes output from 0; known-answer test
- [x] 9.24 **M** Blake3 debug `println` on every hash — fixed: println removed
- [ ] 9.25 **L** Blake3 `*_BITES` constants are bytes; unused `zero-allocation-hashing` dependency — unused dependency removed; needs decision: renaming public `*_BITES` constants
- [ ] 9.26 **L** `ResourceLoader` fails for jar resources and names with `:` — colon names fixed (test); needs decision: jar resources have no Path
- [ ] 9.27 **L** `update-container-versions.sh` picks most recently updated tag, not highest — needs decision: real; tag-selection policy
- [x] 9.28 **L** CONTEXT/IMPROVEMENTS stale — fixed: CONTEXT/IMPROVEMENTS facts
- [ ] 9.29 **L** `correlation-logging-test-utils` published with no source — needs decision: real; per-module test-utils is a convention — remove or fill

Cryptography, protected-value, jwt, keycloak, security scan
- [x] 9.30 **H** `AESKeyAdapter.toString()` prints the raw key (also via `SymmetricKeyWithEncapsulation`) — fixed: prints algorithm/format/hash only; spec test
- [x] 9.31 **L** `SigningPrivateKey.sign` has an uninferable type parameter — fixed: unused type parameter removed
- [x] 9.32 **L** Injected `SecureRandom` ignored for signing and AES keygen — fixed: injected SecureRandom used; tests
- [ ] 9.33 **L** Signature verification trusts the algorithm name from the signature — needs decision: real; signature metadata design
- [ ] 9.34 **L** Signature metadata `keyHash` is the private key's hash — needs decision: real; signature metadata design
- [ ] 9.35 **L** XTS doesn't reject equal data/tweak keys — needs decision: IEEE 1619-2007 (which the code implements) uses equal keys in vector 1; rejecting them chooses the 2018/FIPS rule
- [x] 9.36 **L** No IEEE 1619 vectors for non-aligned XTS lengths — fixed: IEEE vectors 15–18 added (implementation passes)
- [x] 9.37 **L** Cryptography READMEs say CTR — fixed: READMEs say GCM/XTS
- [ ] 9.38 **M** `protectValue(iv = …)` accepts caller IVs (GCM nonce reuse) — needs decision: real; API change
- [ ] 9.39 **M** Protected value `name`/`owner` not bound as AAD — needs decision: real; changes ciphertext format
- [ ] 9.40 **M** `access(context)` ignores the context; README claims access control — needs decision: real; access-control design
- [x] 9.41 **L** Vacuous `ByteArray` vs `String` assertion in AES protected-value test — fixed: compares content against bytes
- [x] 9.42 **L** Protected-value README says AES-CTR — fixed: README + CONTEXT say GCM
- [x] 9.43 **M** `JoseJwtAdapter` NPEs on absent `iat`/`iss`/`jti`/`sub` — fixed: claims read lazily with clear errors; 2 tests
- [x] 9.44 **M** `newJKSJwtProcessor` takes no configuration (no `exp` required, no alg allow-list) — deferred: JWT validation policy belongs to the unfinished gateway; tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [x] 9.45 **L** JWT audience validation always skipped — deferred: JWT validation policy belongs to the unfinished gateway; tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [x] 9.46 **L** Audience processor doesn't require encryption — deferred: JWT validation policy belongs to the unfinished gateway; tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [ ] 9.47 **L** `JWT.isValidAtTime` ignores `nbf` — needs decision: KDoc defines it as not-expired and pillar relies on that; add nbf (contract change), rename, or fix KDoc
- [x] 9.48 **L** JWT tests are happy-path only — fixed: 4 negative tests (all pass)
- [x] 9.49 **M** Keycloak `adminClient` ignores its `password` argument — fixed: passes `password`
- [x] 9.50 **L** Keycloak `customize()` applied before defaults — fixed: customize applied last; test
- [x] 9.51 **L** Disabled Keycloak example test can't pass if re-enabled — fixed: verified by running it once against Keycloak 26.8.0; still @Disabled
- [x] 9.52 **M** Trivy scanner `return@repeat` retries non-retryable failures — fixed: for/break, reports real attempts; Docker test
- [ ] 9.53 **L** Stale `.trivyignore` check uses severity-filtered scan — needs decision: real; scan-all vs reword
- [x] 9.54 **L** Security-scan README names a nonexistent API — fixed: README API name, stale KDoc claim removed

SQL
- [ ] 9.55 **H** Custom Liquibase lock: check-then-act race lets two pods migrate — needs decision: real; lock-service redesign
- [ ] 9.56 **M** Lock liveness uses zone-less `backend_start` strings; SQL interpolation — needs decision: real; lock-service redesign
- [ ] 9.57 **M** `bindValueOrNull` binds every null as VARCHAR — needs decision: real; null-typing API
- [x] 9.58 **L** Indexed `bindNullable` uses primitive classes — not a bug: reified T::class.java is the boxed class; test added proving it
- [ ] 9.59 **L** `PostgresContainer` `rootUser = true` connects as nonexistent `root` — needs decision: real; remove parameter (API) or no-op
- [x] 9.60 **L** `PostgresReadinessCheck` swallows `CancellationException` — fixed: ensureActive in catch; test
- [x] 9.61 **L** `booleanValue` casts to `Byte` — fixed: Boolean columns returned directly; test
- [ ] 9.62 **L** `LiquibaseDatabaseMigrator` lazy connection: wrong dispatcher, `stop()` connects, second run fails — needs decision: real; lifecycle redesign
- [ ] 9.63 **L** `SqlEntityFilter` count and page from different snapshots — needs decision: real; isolation choice
- [ ] 9.64 **L** No tests for lock service, pagination, binding helpers — first sql tests added (binding, parsing, readiness); lock/pagination tests wait on 9.55/9.56/9.63

OpenAPI, web, http4k, lens, readiness
- [x] 9.65 **H** Response body validator only matches the exact status (passes anything under `default`/`4XX`) — fixed: exact → NXX → default (also fixes the response-header validator); tests
- [x] 9.66 **H** Response schema chosen by the caller's accept header; only exact `application/json` counts — fixed: media type from response Content-Type, `+json` counts as JSON; tests
- [x] 9.67 **H** Empty response body only flagged when the schema came from a `$ref` — not a bug: atlassian already reports `validation.response.body.missing` and it isn't filtered
- [x] 9.68 **M** Checker ignores path-item-level parameters — fixed: path-level parameters merged (additive parameter); test
- [ ] 9.69 **M** `ExamplesSchemaComplianceRule` demands a `$ref` for inline schemas — uncertain: scalar examples need scalar support in json-utils first
- [ ] 9.70 **M** `ExamplesSchemaComplianceRule.toJson` always builds a `JSONObject` — arrays fixed (test); scalars still unsupported (see 9.69)
- [x] 9.71 **M** `Response.MissingRequiredHeader` extends `Request` — fixed: extends Response
- [x] 9.72 **M** Unknown query params reported as unknown headers (test locks it in) — fixed: new `UnknownQueryParam` error (additive); locked-in test corrected
- [x] 9.73 **M** `inHeader()/inQuery()` filter by subclass and operation level only — fixed: matched on `in`, path-level included; tests
- [x] 9.74 **M** `compliesWithOpenApiForRequest` uses Content-Type as accept and force-unwraps it — fixed: first Accept type, fallback JSON, no `!!`
- [x] 9.75 **L** Malformed response JSON throws out of `validate`; default charset — fixed: UTF-8, malformed JSON reported; test
- [x] 9.76 **L** N unknown headers produce N identical errors — fixed: one error per report; test
- [ ] 9.77 **L** Response validation throws for `PURGE`/`QUERY` — needs decision: finding wrong about requests (they throw too); PURGE/QUERY aren't OpenAPI methods — throw vs report
- [x] 9.78 **L** `MandatoryVersioningPathPrefixRule` regex unanchored, single digit — fixed: anchored multi-digit regex; tests
- [x] 9.79 **L** `MandatoryRequestBodyContentMediaTypesRule` NPE on null content — fixed: violation instead of NPE; test
- [x] 9.80 **L** `ExampleInfo` NPE for `externalValue` examples — fixed: externalValue examples skipped; test
- [ ] 9.81 **L** `LowercasePathNameRule` flags template variables — needs decision: style choice for template variables
- [ ] 9.82 **L** `DisallowReservedCharactersInParameterNameRule` misnamed — needs decision: real; public rename
- [x] 9.83 **L** `MandatoryOperationFieldsRule.isNotCompliant` dead — fixed: dead code deleted
- [x] 9.84 **L** `OpenApiParser.parse(URL)` fails for `jar:` URLs — fixed: `parse(url.toString())`; test (relative external refs inside a jar still unsupported by swagger-parser)
- [ ] 9.85 **L** `OpenApiReader.parseContent` doesn't resolve refs — needs decision: no base location for string content
- [ ] 9.86 **L** `LocationBasedOpenApiProvider` re-parses on every access, leaks stream — stream closed; needs decision: caching would share one mutable OpenAPI object
- [ ] 9.87 **L** `DowngradingOpenApiDefinitionReader` dead and broken — needs decision: real; delete vs fix
- [ ] 9.88 **L** OpenAPI rules mostly untested; double-slash test URL — double-slash URL fixed; tests added for every changed rule; full per-rule coverage is coverage work
- [x] 9.89 **M** `CatchAndLogErrorsRequestFilter` logs full request (tokens, PII) at ERROR — fixed (decided 2026-10-05): logs only method, path (no query) and the exception; test proves token, cookie, body and query values are absent (fails with the old logging)
- [x] 9.90 **M** `OpenApiEndpoint` unsynchronised map keyed by client directives — fixed: map removed, replies with plain supported type
- [ ] 9.91 **L** `PrometheusMetrics` echoes `*/*`; empty Accept → 500 — wildcard/empty Accept fixed (tests); unsupported specific types still echoed
- [ ] 9.92 **L** `mainHttpApi` unused context parameters — needs decision: real; signature change
- [ ] 9.93 **L** `InvocationContextFilter` only holds keys — needs decision: real; rename
- [x] 9.94 **L** `lenses.first()` on empty list — fixed: clear require
- [ ] 9.95 **L** `LocalHttpDrivingAdapterTestSpecification.meterRegistry` new per access — needs decision: interface can't hold per-instance state; abstract breaks consumers
- [x] 9.96 **L** `OpenApiHttpEndpointTestSpecification` dead helpers; body never checked — fixed: dead helpers deleted, non-empty body check
- [x] 9.97 **L** Prometheus "returns response body" test can't fail — fixed: asserts non-empty body
- [x] 9.98 **M** `HttpHeaders.UserAgent` returns the `location` header — fixed: `user-agent`; test
- [x] 9.99 **L** `suspendCoroutine` not cancellable in HTTP client extension — fixed: cancellable, late response closed; test
- [x] 9.100 **L** `ExampleTests` doesn't stop the server in `finally` — fixed: `use {}`
- [ ] 9.101 **L** Toggle lens rejects values containing `=` — needs decision: `{id}={value}` format ambiguous either way
- [ ] 9.102 **L** Readiness `runBlocking` has no timeout — needs decision: real; timeout value

Messaging, Pulsar, NATS, Avro, JSON, logging, OpenTelemetry, test utils
- [ ] 9.103 **H** Pulsar `AvroReader` ignores the writer schema version (schema evolution broken) — uncertain: real, but AvroSchema.clone() shares one reader across per-topic clones, so delegating would mix writer schemas across topics of a multi-topic consumer; needs per-clone readers (design)
- [ ] 9.104 **H** Pulsar consumers forced to Failover — needs decision: real; consumers rely on Failover ordering
- [ ] 9.105 **M** Partition-change listener loses events; `runBlocking` on Pulsar thread — needs decision: real; replay/buffer and drop-vs-backpressure
- [x] 9.106 **M** `removeFromLast("-partition")` mangles topic names — fixed: `TopicName.get(...).partitionedTopicName`
- [ ] 9.107 **M** `setAutoTopicCreation` called twice with wrong enum format — needs decision: visible in code; broker behaviour needs a running broker
- [x] 9.108 **M** `withBrokerEnv(map)` omits `PULSAR_PREFIX_` — fixed: map overload delegates to the prefixing one
- [x] 9.109 **L** Protocol property filter drops user `PROTOCOL*` properties — fixed: filter on `PROTOCOL-` (serialised names unchanged)
- [x] 9.110 **L** Null message key NPE — fixed: null key → "" (interface unchanged)
- [ ] 9.111 **L** Blocking Pulsar subscribe/create/close in suspend functions; `stop()` connects — needs decision: real; async API redesign
- [x] 9.112 **L** `PulsarReadinessCheck` swallows `CancellationException` — fixed: ensureActive in catch
- [ ] 9.113 **L** `MultiVersionGenericAvroReader` would mutate the shared schema once 9.103 is fixed — latent until 9.103
- [x] 9.114 **M** `Topic.parse` truncates names containing `_` and similar — fixed: `matches()` with Pulsar's NamedEntity characters; 3 tests
- [ ] 9.115 **M** `EventTypeUtils` `!!` makes a message without type a poison message — needs decision: real; ack-and-skip vs nack
- [ ] 9.116 **M** `MessagingTestSpecification` unimplemented; no Pulsar tests — needs decision: test build-out
- [ ] 9.117 **L** `produceAndAwaitSuccessor` drops non-matching messages — needs decision: real; nacking loops in tests
- [x] 9.118 **L** `additionalProperties` not `open` — fixed: `protected open`
- [ ] 9.119 **L** `toOutboundMessage(value, parent)` creates a sibling — needs decision: semantics
- [ ] 9.120 **L** Namespace-less topics don't round-trip — needs decision: topic model
- [x] 9.121 **M** NATS consumer subscribes per collector and leaks — fixed: subscribe once, lazily; test (failed 3/3 before, passes 3/3)
- [ ] 9.122 **M** NATS no flush after subscribe — needs decision: real; flush timeout/failure policy
- [x] 9.123 **L** NATS container `customize` ignored — fixed: customize applied
- [x] 9.124 **M** Avro `setRecords` fails on nullable arrays — fixed: union ARRAY branch; test
- [x] 9.125 **M** Avro `getBigInteger`/`getBigDecimal` fail on `Utf8` — fixed: handles Utf8 after binary round trip; tests
- [x] 9.126 **L** `LocalResourcesAvroSchemaRepository` accumulates ClassGraph paths — fixed: new ClassGraph per call; test
- [x] 9.127 **L** Avro schema checker rules NPE on namespace-less / non-record schemas — fixed: null-safe namespace rules, non-record compliant; 3 tests
- [ ] 9.128 **L** JSON `getInt`/`getLong` narrow silently — needs decision: real; null vs throw for fractions/overflow
- [x] 9.129 **L** `JsonSchema` uses `as` where `as?` was meant — fixed: `as?`; test
- [x] 9.130 **L** JSON schema cache not thread-safe — fixed: ConcurrentHashMap
- [ ] 9.131 **L** JSON checker rules only inspect top level — needs decision: stricter rules, nested path reporting
- [x] 9.132 **H** SLF4J adapter drops the throwable in `log("msg {}", arg, ex)` — fixed: throwable passed for every overload, formatting still lazy; 4 tests
- [ ] 9.133 **M** MDC in `InheritableThreadLocal` leaks into pool threads — needs decision: MDC propagation semantics
- [x] 9.134 **L** `DefaultLoggerFactory.alreadyConfigured` never set; vars not volatile — fixed: dead check removed, vars @Volatile
- [ ] 9.135 **L** Logger level prefix matching per character, not per package segment — needs decision: `.` vs `.`/`$` boundary
- [ ] 9.136 **L** JSON log formatter drops null `message`; schema property names disagree — needs decision: empty string vs schema relaxation; renaming changes validation
- [ ] 9.137 **L** Logging level overrides not trimmed/uppercased; replace defaults instead of merging — needs decision: merge vs replace
- [x] 9.138 **L** Logging tests leave system properties set — fixed: properties cleared after each test
- [ ] 9.139 **M** OpenTelemetry module registers global, per-span export, never shut down — needs decision: lifecycle design
- [x] 9.140 **M** `withCapturedStandardOutput(ERR)` captures stdout and leaves `System.out` broken — fixed: sets the chosen stream; tests
- [x] 9.141 **M** `processAsCompositeEvent` `runCatching` turns `CancellationException` into a nack (affects modulith and element) — fixed: CancellationException rethrown; test

## 10. pillar

- [x] 10.1 **C** Gateway doesn't strip a client-sent invocation-context header; duplicate headers joined and the client's wins (forged identity) — fixed: client-sent context header removed before the gateway adds its own; parsing filter rejects duplicates (400) instead of joining; 4 tests
- [x] 10.2 **H** Gateway trusts target-customer/tenant, is-test and toggle headers from clients — by design (decided 2026-10-05): the gateway sets target-customer/tenant/is-test/toggle headers, not end clients; the edge must not forward client-supplied copies
- [x] 10.3 **M** JWT audience never validated — deferred: GatewayInvocationContextFilter is an unfinished stub (2026-10-05); tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [x] 10.4 **M** Issuer-by-domain always uses `""`; verified-JWT cache keyed by token only — deferred: gateway filter is an unfinished stub; tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [x] 10.5 **M** Every user gets `Example.tenant`; every customer `isTest=false` — deferred: gateway filter is an unfinished stub; tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [x] 10.6 **L** All gateway failures become 400 with the raw exception message — deferred: gateway filter is an unfinished stub; tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [x] 10.7 **L** Invocation-context header compared case-sensitively — fixed with 10.1: header name case-insensitive; test
- [x] 10.8 **H** `MessagingEventProcessor` dies for good on the first exception — fixed: exceptions become Failure (log + nack), CancellationException rethrown; test
- [ ] 10.9 **L** `MessagingEventProcessor` logs payloads at INFO — needs decision: real; log policy
- [x] 10.10 **M** `aud` as array rejected — deferred: JWT claim parsing for the unfinished gateway; tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [x] 10.11 **L** `User.fullName` missing space; tests assert the wrong value — fixed: spaces between names; tests corrected to literals
- [x] 10.12 **L** Required JWT claims stricter than Keycloak emits — deferred: JWT claim parsing for the unfinished gateway; tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [x] 10.13 **L** Organisation from email domain wrong for subdomains/case — deferred: JWT claim parsing for the unfinished gateway; tracked in `pillar/modules/web/api/utils/GATEWAY.md`
- [x] 10.14 **L** `otherNames` gets the whole name when `given_name` isn't a prefix — fixed: otherNames only when name = given + … + family; 4 tests
- [x] 10.15 **L** Acme `locale` falls back to `Example.defaultLocale` — fixed: Acme.defaultLocale (both UK, no behaviour change)
- [x] 10.16 **L** Cookie rule tests use `ParameterLocation.path` — fixed: cookie location
- [x] 10.17 **L** `AcmeOpenApiRules` version regex rejects `/v10` — fixed: `v[1-9][0-9]*`; tests
- [ ] 10.18 **L** OpenAPI rule tests never exercise JSON example rules — JSON request/response example tests added; exampleSchemaComplianceRule still untested (needs $ref fixtures)
- [ ] 10.19 **L** `JvmGcMetrics`/`JvmHeapPressureMetrics` never closed — needs decision: real; API for binder lifecycle
- [x] 10.20 **L** `AcmeHttpApiDefinitionTests` assertions can't fail — fixed: literal header-name assertions
- [x] 10.21 **L** CONTEXT/IMPROVEMENTS/READMEs stale (includeBuild, SNAPSHOT, CTR) — fixed: CONTEXT/IMPROVEMENTS/READMEs (GCM); stale `TODO this should be forked!` removed (already forked)
- [x] 10.22 **L** `scripts/update-gradle.sh` `sed -i ''` is BSD-only (also element) — fixed: portable `sed -i.bak` in every repo's update-gradle.sh except lattice; verified with GNU sed in a container
- [x] 10.23 **L** `jwt-parsing-tests` publishes an empty jar — fixed: no longer published
- [x] 10.24 **H** Three JSON serdes use leading-slash schema paths (never load) — fixed: leading slashes removed; tests
- [x] 10.25 **H** `UnitJsonSerde` points at a nonexistent schema — fixed: correct schema path; test
- [ ] 10.26 **M** JSON locale serdes lack the `no_NO_NY` special case — needs decision: real; changes the JSON wire format
- [ ] 10.27 **M** Leaf JSON serdes have no schema-compliance tests — compliance tests added for 5 leaf serdes; actor leaves fail AcmeJsonSchemaRules (needs catalogue or rule change)
- [x] 10.28 **L** `MonthAndYearJsonSerde` untested — fixed: tests
- [x] 10.29 **L** `EventReference`/`HappeningType` JSON serdes never exercised — fixed: tests
- [x] 10.30 **M** `AccessAvroSchemas.all` omits two schemas — fixed; test
- [x] 10.31 **L** `IdentityAvroSchemas.all` omits `idType` — fixed; test
- [x] 10.32 **L** `InvocationContextAvroSchemas.nestedContainers` empty — not a bug: nestedContainers are sub-namespaces by contract (SchemaContainerTestSpecification), not dependencies
- [x] 10.33 **L** `EventCompositeAvroSerde` untested (and `Composite.equals` hides data loss) — fixed: test checks data and metadata separately
- [x] 10.34 **L** Serde test generators never produce null/empty cases — fixed: null/empty/target-customer cases added (Avro and JSON)

## 11. modulith-example

- [ ] 11.1 **H** Production payment module wired to an always-success stub — needs decision: real; response contract
- [ ] 11.2 **H** No check that the caller owns the source account — needs decision: real; authorisation
- [ ] 11.3 **M** Fresh event id per request and publish-before-wait: retries double-apply — needs decision: real; idempotency
- [x] 11.4 **L** Stub subscriber scope never cancelled; deferred never completed on failure — fixed: failure fails the Deferred; scope cancelled on module stop; test
- [x] 11.5 **L** `$arguments` logged before declaration (send-payment and deposit endpoints) — fixed: arguments parsed before logging (both endpoints)
- [ ] 11.6 **L** Payment module test asserts status only — needs decision: real; right expectation depends on 11.1
- [x] 11.7 **H** Deposit endpoint: any authenticated actor; client-supplied event metadata published as-is — by design: event endpoint with a trusted client (decided 2026-10-05)
- [ ] 11.8 **H** account-event-processor handlers all TODO (unwired); README says Done — needs decision: real; README section left as is
- [x] 11.9 **H** `OutboundPayment.inbound()` swaps the accounts (no callers yet) — fixed: accounts un-swapped; literal test
- [ ] 11.10 **M** No positive-amount check on payments/deposits — needs decision: real; domain rule
- [ ] 11.11 **L** `AccountEvent.avsc` wrong record name (see 4.1) — needs decision: see 4.1
- [ ] 11.12 **L** Publisher log says "compliance plan event" and leaks amounts — log text fixed; needs decision: logging full events at INFO
- [x] 11.13 **L** "inbound-payment" serde test builds an `OutboundPayment` — fixed: builds InboundPayment
- [x] 11.14 **L** Account-number test factory never produces 9 — fixed: `nextInt(0, 10)`
- [x] 11.15 **M** `InProcessServiceTests.afterAll` never stops the service — fixed: service stopped in afterAll
- [ ] 11.16 **L** Random node name; `INSTANCE_*` env vars never read — needs decision: real; instance identity
- [x] 11.17 **L** `stop()` doesn't close the `PulsarClient` — fixed: PulsarClient closed after the health adapter stops
- [ ] 11.18 **L** Registry auth lookup result discarded — needs decision: real; delete or wire Docker auth
- [ ] 11.19 **L** Partitioned topic only pre-created in tests — needs decision: real; provisioning
- [x] 11.20 **L** README describes nonexistent SDKs — fixed: SDKs under To Do
- [x] 11.21 **L** IMPROVEMENTS stale — fixed: IMPROVEMENTS facts
- [x] 11.22 **L** `api.yaml` send-payment example named "DepositEvent" — fixed: example renamed SendPayment

## 12. element-service-example

Infra, service, shared
- [x] 12.1 **C** Migrator `-XX:+ZGenerational` is fatal on JDK 26 (init container never starts) — fixed: flags removed; verified on Temurin 26
- [x] 12.2 **C** Helm `deployment.yaml:63` `{ { … } }` renders a map (install fails) — fixed: `{{ … | default "json" | quote }}`
- [ ] 12.3 **M** Chart image repositories/tags don't match the images the build produces — needs decision: real; registry/tags
- [ ] 12.4 **M** No startupProbe; liveness budget shorter than startup — needs decision: real; probe budget
- [ ] 12.5 **M** Trivy scans only the service image, not the migrator — needs decision: real; scan scope
- [x] 12.6 **L** Dead env var `MODULES_HTTP_EVENT_BRIDGE_USER_SERVICE_ADDRESS` — fixed: removed
- [x] 12.7 **L** Probe ports hardcoded to 8081 — fixed: named `health` port from values, probes use it
- [x] 12.8 **L** Migrator egd passed as program arg; `HeapDumpPath` literal `<pid>` — fixed: egd arg removed (ignored), HeapDumpPath → /tmp directory
- [ ] 12.9 **M** Pulsar config overrides dropped (see 9.22 — blocked on 9.22 (needs decision); no change needed in this repo once fixed upstream
- [ ] 12.10 **M** Random instance id; `INSTANCE_NODE_NAME` never read — needs decision: real; instance identity
- [ ] 12.11 **M** R2DBC without a connection pool — needs decision: real; pool choice
- [ ] 12.12 **L** `stop()` doesn't close clients; first failure skips the rest — needs decision: real; stop-failure policy, and nothing to close until 12.11
- [ ] 12.13 **L** Health server starts before the main server — needs decision: real
- [ ] 12.14 **L** `default-configuration.yml` never loaded — needs decision: real; delete or load
- [x] 12.15 **M** No index on `Compliance_Plan_Output_Standards` — fixed: new changeset 1_5 creates `(customer_id, compliance_plan_id, pk)` index (plain CREATE INDEX like existing ones)
- [ ] 12.16 **M** Migrations use `DROP TABLE` (data loss on upgrade) — needs decision: real; applied changesets must not be edited
- [ ] 12.17 **M** `Standard.equals` compares only reference and publication (hides serde bugs, collapses sets) — needs decision: real; equality semantics
- [ ] 12.18 **L** Requirement `Standard`/`Clause` `compareTo` inconsistent with `equals` — needs decision: real
- [x] 12.19 **L** `Submission.shortName` is null — fixed: returns "510(k)" (unused)
- [ ] 12.20 **L** `Market`/SDO accept any name; Avro enums are closed — needs decision: real
- [x] 12.21 **L** `OrganizationAvroSchemas`/`DeviceAvroSchemas` `.all` wrong — fixed
- [x] 12.22 **L** Migrator `writeRaw` bypasses Jackson bookkeeping — fixed: `writeRawValue`
- [x] 12.23 **L** Test factories use `Random.Default` — fixed: seeded random
- [x] 12.24 **L** `EntitlementAvroSerdeTests` missing a case — fixed: case added
- [x] 12.25 **L** Container test registry auth discarded — fixed: no-op auth helper deleted
- [x] 12.26 **L** Container Postgres URL has no database name — fixed: database name in URL
- [x] 12.27 **L** `ProcessBasedServiceTests.afterAll` never stops the service — fixed: service stopped first
- [x] 12.28 **M** README documents `PULSAR_BROKER_URI` (key is `PULSAR_BROKER_URL`) — fixed: `PULSAR_BROKER_URL`
- [x] 12.29 **L** README: ports "optional", OCI registry default wrong — fixed: ports mandatory, OCI registry/project path documented
- [x] 12.30 **L** IMPROVEMENTS stale — fixed: Gradle, module count, SNAPSHOT claim
- [ ] 12.31 **L** Uncommitted `.trivyignore` change (also modulith) pending a security-scan run — untouched as instructed

compliance-plan-outputs-manager
- [x] 12.32 **C** SQL injection via `origin.standard`/`origin.clause` — fixed: bound parameters; Testcontainers test (apostrophe works, injection returns nothing)
- [x] 12.33 **H** Null `edition` stored but unreadable (500 for that plan) — fixed: nullable edition read with getStringOrNull (DB + HTTP), `edition` no longer required in 4 schemas; tests
- [ ] 12.34 **H** Re-storing requirements resets applicability decisions — needs decision: real; applicability semantics after re-analysis
- [x] 12.35 **H** Empty standards/requirements: unbound insert after committed delete (poison message) — fixed: stop after delete on empty set; test
- [x] 12.36 **M** Delete + insert not in a transaction — fixed: delete+insert in a transaction; test (failing insert leaves rows intact)
- [ ] 12.37 **M** `limit` 0/negative/unbounded — uncertain: real; max limit and validation location are choices
- [ ] 12.38 **M** Plan upsert has no version guard — needs decision: real; versioning scheme
- [x] 12.39 **L** Remote `FileContent` reads `LENGTH` never written — fixed: length written; round-trip test
- [x] 12.40 **H** Confirm-applicability serde lacks `MissingCompliancePlanEntitlement` (500) — fixed: serde + Result.json; serde/contract tests
- [x] 12.41 **M** List `Result.json` omits the entitlement error — fixed: entitlement error in both list Result.json; tests
- [x] 12.42 **M** `selector` required by the serde, optional in the schema — fixed: selector optional, defaults to ALL; test
- [x] 12.43 **L** Origin `type` required by the serde, not the schema — fixed: `type` required in schemas (matches serde)
- [x] 12.44 **L** `$arguments` logged before declaration — fixed: arguments parsed before logging (5 endpoints)
- [x] 12.45 **H** CSV Conditionality column prints the summary — fixed: conditionality summary; literal test
- [ ] 12.46 **H** CSV fields never quoted/escaped (formula injection, corrupt rows) — RFC-4180 quoting/escaping fixed (new CSVRow, tests); needs decision: spreadsheet formula prefixing alters data
- [ ] 12.47 **M** Missing plan treated as entitled — needs decision: real; not-found semantics
- [ ] 12.48 **M** Writes before publish not transactional — needs decision: real; transaction boundary
- [ ] 12.49 **L** CSV dates depend on JVM locale — needs decision: real; date format
- [ ] 12.50 **L** CSV has no BOM — needs decision: real; BOM
- [x] 12.51 **L** Cancellation becomes a nack (see 9.141) — fixed upstream in swissknife (9.141)
- [x] 12.52 **M** Event processing tests exercise a stub — fixed: tests run the real Application with recording publisher
- [x] 12.53 **M** No CSV generator tests — fixed: CSV generator tests added
- [x] 12.54 **L** Verification-method filter test can't fail — fixed: subset + exact assertion
- [ ] 12.55 **L** Repository spec missing re-store/empty/null-edition cases — empty-set and null-edition cases added; re-store-keeps-applicability depends on 12.34
- [x] 12.56 **L** Contract tests never exercise the entitlement error — fixed: entitlement-error cases in serde/contract tests
- [ ] 12.57 **L** "Nonexistent plan" test uses a stub that always returns a plan — misleading name fixed; a real missing-plan test depends on 12.47
- [x] 12.58 **L** Module spec connectors never stopped — fixed: stopped/closed in finally

http-event-bridge
- [x] 12.59 **H** Client-supplied event metadata (identity, id, timestamp) published as-is — by design (decided 2026-10-05): event endpoints ingest events from trusted clients (e.g. Stripe), so body metadata is trusted
- [ ] 12.60 **H** Ingestion only checks "authenticated" (no role/customer check) — needs decision: real; authorisation
- [x] 12.61 **M** Shutdown stops the connector before the processor — fixed: processor → connector → publisher
- [x] 12.62 **M** Cancellation becomes a failure (see 9.141) — fixed upstream in swissknife (9.141)
- [ ] 12.63 **M** No idempotency on ingestion — needs decision: real; idempotency
- [ ] 12.64 **L** Always 200, even on `ApplicationResult.Error` — needs decision: real; status for a currently unreachable Error
- [x] 12.65 **L** `$arguments` logged before declaration — fixed: arguments parsed before logging
- [ ] 12.66 **H** Notifier serde writes fields its schema forbids; untested — needs decision: real; unclear whether the serde shape or the flat email-contract schema is intended
- [ ] 12.67 **M** Lifecycle notifications lose the parent message id — needs decision: real; notifier interface change
- [x] 12.68 **L** Notifier schema `$ref`s point at another module — fixed: notifier `$ref`s point at notifier copies; test
- [x] 12.69 **M** `Publication.edition` nullable but required in serde/schema — fixed: nullable edition (serde + schema); test
- [x] 12.70 **M** `RequirementStandard.edition` same — fixed: nullable edition (serde + schema); test
- [ ] 12.71 **M** Round-trip tests can't detect dropped optional fields (see 12.17) — needs decision: see 12.17
- [ ] 12.72 **M** Body not schema-validated; no size limit (gzip bomb) — proposed close: body size limits are the gateway's job (awaiting confirmation)
- [ ] 12.73 **L** Contract tests happy path only — needs decision: an Error contract case would lock in 12.64
- [x] 12.74 **L** Module spec `first {}` without timeout; consumers not closed — fixed: client closed per test (closes consumers); the no-timeout half was not a bug (10s withTimeout already)

compliance-plans-viewer
- [x] 12.75 **C** SQL injection via continuation token / customer id / states — fixed: customer/states/token bound (`= ANY(:STATES)`, token parsed to Long, non-numeric rejected before SQL → generic 500); 2 Testcontainers tests
- [x] 12.76 **H** Tenant taken from a client header (see 10.2) — by design: services trust the gateway-set context (decided 2026-10-05)
- [ ] 12.77 **H** Upsert overwrites newer state (redelivery regresses plans) — needs decision: real; ordering guard design
- [x] 12.78 **H** In-memory sort after `LIMIT` duplicates rows across pages — fixed (decided 2026-10-05): sorting and keyset pagination in SQL on `(state_order, pk)`; new `state_order` column (migration 1_6, backfilled) with `(customer_id, state_order, pk)` and `(customer_id, pk)` indexes; continuation token is `stateOrder:pk`; test pages through mixed states in both directions and unsorted (fails on the old code)
- [ ] 12.79 **M** `limit` not validated — needs decision: real; limit bounds
- [x] 12.80 **M** Empty `selected-states` → `IN ()` SQL error — fixed by the ANY binding: empty selection → empty page; test
- [x] 12.81 **M** Upsert never updates device fields — fixed: upsert updates device fields; test
- [x] 12.82 **L** Extra empty page; count/page from different queries — fixed with 12.78: fetches limit+1 to decide whether there is a next page (no trailing empty page)
- [ ] 12.83 **L** Null customer becomes `'null'` — null customer now binds SQL NULL (no `'null'` literal); needs decision: reject with 403 instead of empty 200
- [x] 12.84 **L** `upsertAll(emptyList())` throws — fixed: early return; test
- [x] 12.85 **L** `DocumentModule` writes the wrong format fields — fixed: format fields and error message; test
- [x] 12.86 **H** `ApplicableRequirementsReady.type` is `REQUIREMENTS_READY` — fixed: `APPLICABLE_REQUIREMENTS_READY`; test. Existing rows written before the fix would need a backfill
- [ ] 12.87 **L** `ApplicableRequirementsOutputsAvailable` not handled — uncertain: nothing produces the event yet
- [x] 12.88 **L** Cancellation becomes a nack (see 9.141) — fixed upstream in swissknife (9.141)
- [ ] 12.89 **L** Full results logged at INFO — needs decision: log policy
- [ ] 12.90 **L** `toAuthenticated` runs handlers in `runBlocking` — needs decision: shared pillar API
- [x] 12.91 **M** Repository spec state assertions can't fail — fixed: real assertions (existing filter tests still pass)
- [x] 12.92 **M** Event processing tests exercise a stub — fixed: real Application with recording writer
- [x] 12.93 **M** Viewer application tests filter inside the stub — fixed: stub returns page as-is, records arguments
- [x] 12.94 **L** Contract stub ignores arguments — fixed: stub captures arguments, test asserts them
- [x] 12.95 **L** Sorted pagination test doesn't check pages are disjoint — fixed with 12.78: the new paging test asserts every plan appears exactly once, in order
