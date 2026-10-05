# swissknife core / kotlin-extensions / ddd / correlation / hashing / resource / docs: independent verification

Refs: base `3f1d24b`, snapshot `bug-hunt-snapshot-2026-10-05` (commits `2208ca2`, `92ee316`). Everything was read-only: I read the code with `git show`/`git diff`/`git grep` and grepped the sibling repos. I built and ran nothing. "Test fails without fix" claims come from tracing the code, not from running the tests.

Not scored because they have no code change in the snapshot: 9.2, 9.4, 9.6, 9.7, 9.10, 9.15, 9.17, 9.20 (decided by design), 9.21, 9.22, 9.27 and 9.29. None of their files (`UniqueIdFactoryAdapter`, `IdFactoryExtensions`, `CurrencyAmountExtensions`, `CoreDataGeneratorProvider`, `EphemeralPort`/`RequestedPort`, `BytesExtensions`, `EnumToggle`, `InvocationContext`, `Trace`, `EnvironmentExtensions`, `update-container-versions.sh`, the `correlation-logging-test-utils` build file) appears in the diff.

Production usage found by grep across pillar, modulith-example, element-service-example, lattice, examples, tools and quality-scorer:
- No production code anywhere uses `Flow.chunk*`, `awaitAny`, `circularSequence`, `Int/Long.pow`, the range form of Blake3, or KSUID generation. pillar uses KSUID only in serde tests.
- Services use `withToggle` only in contract tests.

---

### 9.1 — KSUID factories freeze the clock at construction
- Defect in base: REAL. `MonotonicKsuidFactoryAdapter.kt:14` and `SubSecondPrecisionKsuidFactoryAdapter.kt:14` pass `clock.now()::toJavaInstant`. That is a bound reference, so `clock.now()` runs once, when the factory is constructed. The ULID adapter (`MonotonicUlidFactoryAdapter.kt:14`) correctly calls `clock.now()` inside a lambda.
- Fix: CORRECT and minimal. Both adapters now pass `{ clock.now().toJavaInstant() }`, an internal change with no API impact. The two new tests use a mutable `Clock` that moves forward one hour after the first id. On base they would fail: monotonic keeps the first second and bumps the payload, and sub-second keeps the frozen instant. The tests follow the style rules, with literal instants.
- Principles: none.
- Importance: 3. The timestamps are certainly wrong for any long-lived factory, but nothing in production generates KSUIDs today; the default `newId` uses UUIDv7.
- Confidence: 5. Kotlin bound-reference semantics are unambiguous.
- Recommendation: REDO AS IS.

### 9.3 — `UUIDv7(String/ByteArray)` doesn't check the version
- Defect in base: REAL. `UUIDv7.kt:32,34`: `invoke(String)` and `invoke(ByteArray)` wrap any `Uuid`. Only `parseOrNull` (line 37) checks `version == 7`. The unchecked path is reachable from pillar `IdJsonSerde.kt:39` and `IdAvroSerde.kt:32` (`TYPE_UUIDV7 -> UUIDv7(stringValue)`).
- Fix: CORRECT and minimal. An `init { require(delegate.version == 7) }` uses the existing file-private `version` extension. Every internal construction site (`UuidV7FactoryAdapter` `generateV7`/`generateV7NonMonotonicAt`, `parseOrNull`) produces v7, so nothing regresses. The new test uses a literal v4 string and expects `IllegalArgumentException`; on base the call succeeds, so the test fails.
- Principles: none.
- Importance: 3. Corrupt or mistyped input is accepted and later yields a nonsense `timestamp`. It is only reachable through deserialization of a mislabelled id.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.5 — `Version.compareTo` compares strings
- Defect in base: REAL. `Version.kt:10` is `override fun compareTo(other: Version) = value.compareTo(other.value)`, which compares the `Name` strings, so `"10.0.0" < "9.0.0"`.
- Fix: CORRECT and minimal. `Semantic` overrides `compareTo` with `compareValuesBy(major, minor, patch)` when the other side is `Semantic`, and falls back to `super.compareTo` otherwise. Mixed `Semantic`/`Simple` comparisons stay string-based in both directions, so they remain symmetric. The new `VersionTests` would fail on base for all three assertions.
- Principles: none.
- Importance: 3. The only user, `DowngradingOpenApiDefinitionReader` (`version > Semantic(3,0,0)`), compares single-digit OpenAPI versions, where the string order happens to be right. The bug is latent but certain once a component reaches 10.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.8 — `Number.dollars/euros/pounds` go through `toDouble()`
- Defect in base: REAL. `Dollars.kt:18`, `Euros.kt:18`, `Pounds.kt:18`: `Dollars(toDouble().toBigDecimal())`.
  - `0.1f` widens to `0.10000000149…`, and `toUnits` (`SpecificCurrencyAmountTemplate.kt:48`, `toBigIntegerExact`) then throws.
  - BigDecimals with more than 15–16 significant digits are silently rounded.
- Fix: CORRECT. An `internal fun Number.toDecimal()` in `KnowCurrencyStaticExtensions.kt` passes BigDecimal through, converts BigInteger and the integral types exactly, uses `toString()` for Float, and falls back to Double (Kotlin's `Double.toBigDecimal` already goes via `toString`). The two tests use literal units and would fail on base: one throws, the other gets `…456800`.
- Principles: none.
- Importance: 2. These are convenience constructors used only in tests (pillar serde tests use `23.18.dollars` and similar, which work either way).
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.9 (partial) — Test factory email has a trailing dot
- Defect in base: REAL. `EmailAddressTestFactories.kt:10` builds `"${prefix}@${domain}."` with a default domain of `xxxx.com`, which gives `x@xxxx.com.`.
- Fix: CORRECT. The trailing `.` is dropped and nothing else changes. No test was added, which is fine for a one-character data fix. The validation strictness question is left open, as noted.
- Principles: none.
- Importance: 2. The bad test data only "works" because `EmailAddress` validation is loose; it would break as soon as validation is tightened.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.11 (partial) — `Flow.chunk` emits one shared mutable list and stacks handlers
- Defect in base: REAL.
  - `FlowChunkingExtensions.kt:35-36`: `collector.emit(chunk); chunk.clear()` emits the same list every time, so `flowOf(1,2,3,4).chunk(2).toList()` is `[[], []]`.
  - Lines 28 and 45: `private var original` is reassigned on every `collect`. A second collection therefore also runs the first collection's `onCompletion { flush() }`, which emits into the first collector's destination list.
- Fix: CORRECT for those two defects. It emits `chunk.toList()` and makes `original` a local `val` inside `collect`. Each test independently catches its defect:
  - The first test fails on aliasing.
  - The second test, with only the copy fix applied, would still fail because the stacked handler appends an extra `[]` to `firstChunks`.

  Not addressed, and correctly left for a decision: the timed flush still emits from the `async` ticker coroutine and races on `chunk`, and empty chunks are still emitted on empty upstream and idle ticks.
- Principles: none.
- Importance: 3. Broken for any collector that keeps the chunk, but nothing uses it today.
- Confidence: 5.
- Recommendation: REDO AS IS, and leave the timed-flush rewrite (`channelFlow`) as a separate decision. Since there are no callers, deleting the timed variants is also an option.

### 9.12 — `awaitAny` doesn't cancel the rest when one fails
- Defect in base: REAL. `DeferredExtensions.kt:13-21`: the cancellation runs in `.also { … cancelAndJoin() }` after `select`. When a deferred completes exceptionally, `onAwait` throws, the `.also` is skipped, and the other deferreds keep running.
- Fix: CORRECT. The body is wrapped in `try { select … } finally { filter { isActive }.onEach { cancel() }.joinAll() }`.
  - Recursion is safe: the inner call's `finally` cancels the remaining deferreds, and the outer one is then a no-op.
  - If the caller itself is cancelled, `cancel()` still runs before `joinAll` throws.

  The test (a failing deferred plus `awaitCancellation()`) would fail on base because `pending.isCancelled` stays false. Minor test hygiene issue: the test's `CoroutineScope(SupervisorJob())` is never cancelled.
- Principles: none.
- Importance: 3. The function contradicts its own KDoc; it is latent because nothing calls it.
- Confidence: 4. Clear trace; not executed.
- Recommendation: REDO AS IS.

### 9.13 — `circularSequence` shares its index across iterators
- Defect in base: REAL. `ListExtensions.kt:6` declares `var index = 0` outside `sequence {}`, so every iterator shares it. On an empty list, `get(0)` throws `IndexOutOfBoundsException`.
- Fix: CORRECT and minimal. The index moves inside the block, and an empty list returns `return@sequence`, giving an empty sequence. Both tests would fail on base: the second iteration gives `[c, a]`, and the empty case throws. The KDoc still says "infinite sequence", which is now false for an empty list; that is negligible.
- Principles: none.
- Importance: 2. Unused helper.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.14 — `pow` goes through `Double`
- Defect in base: REAL. `NumberExtensions.kt:5,7`: `toDouble().pow(exponent).toInt()/toLong()`. `3L.pow(39)` is inexact (above 2^53), and `Int.pow` saturates at `Int.MAX_VALUE` instead of failing.
- Fix: CORRECT but heavier than needed. It hand-rolls exponentiation by squaring with `multiplyExact`, and makes `Int.pow` use `Math.toIntExact(toLong().pow(e))`. I checked the edge cases: there is no spurious overflow on the final squaring, and `(-2)^63` fits. Negative exponents now throw, where base returned the truncated double: 0 for most bases, but `1` and `-1` gave valid results. No callers exist. The tests would fail on base: the first is off by 11, the second saturates instead of throwing.
- Principles: none, apart from minimal code.
- Importance: 2. Unused helper.
- Confidence: 5.
- Recommendation: REDO MODIFIED. Use the stdlib one-liners `fun Long.pow(exponent: Int): Long = toBigInteger().pow(exponent).longValueExact()` and `fun Int.pow(exponent: Int): Int = toBigInteger().pow(exponent).intValueExact()`. `BigInteger.pow` already throws `ArithmeticException` on a negative exponent, and `*ValueExact` throws on overflow. Keep both tests as they are.

### 9.16 — `Happening.Type.parse` splits on every `--v`
- Defect in base: REAL. `Happening.kt:22-24`: `split("--v")` followed by `check(parts.size == 2)`. `Type(Name("user--verified"), 1).stringValue` is `user--verified--v1`, which splits into 3 parts, so `check` throws.
- Fix: CORRECT. It splits at `lastIndexOf("--v")`, which is always right because the version suffix is digits only. It also extracts a `private const val VERSION_SEPARATOR`, a tiny refactor used in both `stringValue` and `parse` that is acceptable. For inputs with no separator or a non-numeric version, the error behaviour is unchanged. The test (`user--verified--v1`, literal `Name` and `IntVersion`) fails on base.
- Principles: none.
- Importance: 3. `parse` is on the event-type deserialization path in pillar. Names containing `--v` are unlikely but valid.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.18 — `Toggles.withToggle` doesn't replace an existing value
- Defect in base: REAL. `Toggles.kt:28,30`: `copy(values = values + toggle(value))`. A different value is a different set element, so both are kept. `byId` (`associateBy`) then picks whichever comes last, and serialized forms carry both.
- Fix: CORRECT and minimal. Both overloads route through a `private fun Toggles.withValue(...)` that filters out the same id before adding. The `Toggles(values)` constructor can still be given duplicates directly, which is out of scope. The test, which uses a literal `EnumToggleValue(StringId("invocation-visibility"), "DEFAULT")` with `containsOnly`, fails on base. It lives in `correlation/core/test/utils/src/test`, which matches the convention because `correlation/core/domain` has no test source set.
- Principles: none.
- Importance: 3. The behaviour is wrong as soon as anything overrides a toggle, for example a gateway default followed by a header value. Current users (contract tests) set each toggle only once.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.19 — `ActorTestFactory` impersonation arguments swapped
- Defect in base: REAL. `ActorTestFactory.kt:44,47`: `ImpersonatingActor(impersonator = impersonating, impersonated = impersonator, …)`, while `ImpersonatingActor.account` is `impersonated`.
- Fix: CORRECT and minimal; the arguments are un-swapped in both factories. The new test covers only `Actor.impersonating`, not `ImpersonatingActor.create`. It would fail on base. The only callers use the defaults (pillar `ActorAvroSerdeTests`), so they are unaffected.
- Principles: none.
- Importance: 2. It is a test utility; it only misleads tests that pass explicit accounts.
- Confidence: 5.
- Recommendation: REDO AS IS. Optionally add the same assertion for `ImpersonatingActor.create`.

### 9.23 — Blake3 `invoke(bytes, offset, length)` ignores the range
- Defect in base: REAL. `Blake3.kt:24` calls `blake3(bytes, hashBytesLength, offset, hashBytesLength, key)`, so `length` is dropped. Line 33 `hasher.update(bytes)` hashes the whole array. Line 36 `doFinalize(hash, offset, hashBytesLength)` writes at the input offset, which throws `IndexOutOfBounds` for any `offset > 0`.
- Fix: CORRECT. It calls `update(bytes, offset, length)` and `doFinalize(hash)`, and drops the private function's default parameters. The known-answer test hashes the well-known digest embedded at offset 2 and expects the published hash. It fails on base, which hashes the whole array and then throws on the output offset.
- Principles: none.
- Importance: 3. The public `HashFunction` contract is broken for ranges, but the only caller (`CryptographicKeyAdapter.hash`) hashes whole arrays, where base behaved correctly.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.24 — Blake3 debug `println`
- Defect in base: REAL. `Blake3.kt:34`: `println("HashBytesLength: …")` runs on every hash, including every `CryptographicKeyAdapter.hash`.
- Fix: CORRECT; the line is deleted. No test, which is appropriate.
- Principles: none.
- Importance: 3. A library writes raw lines to stdout, mixed into services' JSON stdout logs.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.25 (partial) — Unused `zero-allocation-hashing` dependency
- Defect in base: REAL. `hashing/utils/build.gradle.kts:8` has `implementation(libs.zero.allocation.hashing)`, and `git grep openhft|LongHashFunction` at base finds nothing in any module.
- Fix: CORRECT. The dependency is removed from the module, and the version and library entries are removed from `gradle/libs.versions.toml`; nothing else references them. The `*_BITES` rename is correctly left for a decision.
- Principles: none.
- Importance: 1. It is a dead dependency.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.26 (partial) — `ResourceLoader` fails for names with `:`
- Defect in base: REAL. `ResourceLoader.kt:21-25`: `URI.create("db:x.sql").toURL()` throws `MalformedURLException` ("unknown protocol"). Only `IllegalArgumentException` is caught, so the classpath fallback never runs.
- Fix: CORRECT and minimal. A second `catch (MalformedURLException)` falls back to `Resources.getResource`. The test expects Guava's literal "resource db:FileThatDoesNotExist.sql not found." message, which proves the fallback ran; on base the error would be a `MalformedURLException`. Side effect: a mistyped real URL scheme now reports "resource not found" instead of "unknown protocol", which is acceptable. The jar-resource `Path` case is correctly left for a decision.
- Principles: none.
- Importance: 2. Edge case; no known resource names contain a colon.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.28 — CONTEXT/IMPROVEMENTS stale
- Defect in base: REAL. At base:
  - the catalog has `kotlin = "2.4.20"`;
  - the wrapper is `gradle-9.8.0`;
  - `settings.gradle.kts` `pluginManagement` resolves plugins from mavenLocal and the plugin portal (no `includeBuild`);
  - `currentVersion=1.0.35`;
  - `just publish` is `publish-if-changed.sh` and `update-dependencies` is `versionCatalogUpdate`;
  - `org.gradle.configuration-cache=true`;
  - consumers pin `sollecitom-swissknife = "1.0.x"`.
- Fix: CORRECT. Every edited statement now matches the code. The CONTEXT `AES-CTR → AES-GCM` line belongs to 9.42, not this item. Left stale but harmless: the Palantir git-version plugin is still applied in `build.gradle.kts` although it no longer drives the version, and the CONTEXT line now says so correctly.
- Principles: none.
- Importance: 2. Docs accuracy.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.141 — `processAsCompositeEvent` turns `CancellationException` into a failure
- Defect in base: PARTLY.
  - `CompositeEventProcessingUtils.kt:8`: `runCatching { action(...) }.map { Success }.getOrElse(Throwable::asProcessingFailure)` does catch `CancellationException` (and `Error`).
  - In pillar base (`MessagingEventProcessor.kt:39-42`, ref `78de257`), `Failure` leads to `logger.warn` followed by `message.acknowledgeAsFailed()`.
  - The claimed nack mostly does not happen, though. On `stop()` → `cancelAndJoin()`, `acknowledgeAsFailed` is `withContext(Dispatchers.VirtualThreads) { negativeAcknowledge }` (`PulsarReceivedMessage.kt:29`), and `withContext` calls `ensureActive()` first, so it throws in the cancelled coroutine before nacking.
  - The real effect is a spurious WARN on shutdown and one extra trip through the failure branch.
  - A `TimeoutCancellationException` from a `withTimeout` inside the action would also become `Failure`, which is a real but separate nuance.
- Fix: CORRECT for the narrow claim. The `getOrElse` now rethrows `CancellationException` and maps everything else to `Failure`. The test (an action that throws `CancellationException`, with `runCatching` asserting `isFailure().isInstanceOf(CancellationException)`) fails on base, where `Failure` is returned normally.
- Principles: CONFLICT with principle 2, though not caused by this fix.
  - Under "on failure stop processing, never nack", `processAsCompositeEvent` converting every other exception into `Failure` is exactly what feeds pillar's `Failure → acknowledgeAsFailed()` (nack-and-continue) branch.
  - The pillar snapshot makes this worse: it adds the same `runCatching … asProcessingFailure()` around `processEvent` in `MessagingEventProcessor`, so every exception is nacked and processing continues. That assumption is wrong; it belongs to the pillar verifier, but the redo has to be coordinated.
  - If exceptions are not caught at all, cancellation propagates naturally, and the 9.141 special case becomes unnecessary.
- Importance: 2 as filed (a spurious warning on shutdown). The underlying design conflict (exceptions becoming nacks) matters more and is a principle-2 issue across swissknife and pillar.
- Confidence: 4. Clear trace of `withContext` cancellation and the pillar branch; not executed.
- Recommendation: REDO MODIFIED.
  - Drop the `runCatching` from `processAsCompositeEvent` entirely: `action(this, value.data, value); return EventProcessingResult.Success`. Exceptions, including `CancellationException`, then propagate and processing stops with the message unacked.
  - Coordinate with pillar so that `MessagingEventProcessor` neither nacks nor catches. On `Failure` it should stop processing rather than call `acknowledgeAsFailed()`, and the snapshot's `runCatching` there must not be redone.
  - Replace the test with one that asserts a thrown `IllegalStateException("boom")` propagates out of `processAsCompositeEvent`, using a literal message.
  - Whether `EventProcessingResult.Failure`, `asProcessingFailure` and `ReceivedMessage.acknowledgeAsFailed` should stay in the general-purpose contract (principle 4) is the owner's call, but no default path should produce a nack.

---

## Unattributed changes

Scope: base..snapshot diff for core, kotlin, ddd, correlation, serialization, pagination, resource, configuration, hashing, messaging-domain `CompositeEventProcessingUtils`, and root docs/build files.

- No truly unattributed functional change in scope. `modules/serialization`, `modules/pagination` and `modules/configuration` are untouched.
- Attributed to items outside this list, all in the root files:
  - `.gitignore`: the fused `*.pidjava_pid*.hprof` line is split into two (4.14).
  - `scripts/update-gradle.sh`: `sed -i ''` becomes `sed -i.bak … && rm` (10.22).
  - `CONTEXT.md`: the `protected-value` row now says AES-GCM (9.42).
- Incidental edits inside scored fixes. All are acceptable, and none changes behaviour beyond the item:
  - `Happening.kt` adds the `VERSION_SEPARATOR` constant (9.16).
  - `FlowChunkingExtensions.kt` removes the `private var original` field (9.11).
  - `Blake3.kt` removes the private function's default parameters (9.23).
  - `ListExtensions.kt` KDoc "infinite" is now slightly inaccurate (9.13).
- Mechanical: `gradle.properties` `currentVersion` 1.0.35 → 1.0.37, `sollecitom-gradle-plugins` 1.0.32 → 1.0.33, and `publication-state.properties` hashes and version. Note that the checklist says swissknife 1.0.36 was published, but the snapshot is at 1.0.37 and pillar's catalog pins 1.0.37.
- Out of my scope but present in the same commits, attributed to other sections' items: avro serialization utils (`AvroGenericRecordExtensions`, `AvroRecordBuilderImpl`), messaging-domain `Topic`/`TenantAgnosticTopic` (9.114 and related), and `EventMessageConverterTemplate`.
