# modulith-example — independent verification of bug-hunt fixes

Refs: base `898432a`, snapshot `bug-hunt-snapshot-2026-10-05` (= `73a9240`, which is HEAD; commits `9c7ce73` and `73a9240`). Everything was read-only: I read the code with `git show`/`git diff` and built or ran nothing. "Test fails without fix" claims come from tracing the code, not from running the tests.

Items with no code change in the snapshot (11.1, 11.2, 11.3, 11.6, 11.8, 11.10, 11.11, 11.16, 11.18, 11.19) are confirmed untouched by the diff. 11.7 ("by design") has no code change either: the deposit endpoint diff only moves the log line (11.5).

`.trivyignore` (owner work, not scored): the diff removes `CVE-2026-84782` and replaces the block with a "(none currently ...)" comment. This matches a CVE removal. Base commit `898432a` bumped `dockerBaseImageParam` to `eclipse-temurin:26-jre-noble@sha256:5077290942a2...` in `gradle.properties`, which fits "the noble base rebuilt".

---

### 11.4 — Stub subscriber: scope never cancelled; deferred never completed on failure
- Defect in base: REAL (latent). `StubbedSendPaymentProcessingResultSubscriber.kt:14-21` creates a `CompletableDeferred`, launches `async(UNDISPATCHED) { val result = awaitResult(); deferred.complete(result) }` in `CoroutineScope(SupervisorJob())` (line 12), and returns `deferred`. If `awaitResult` throws, the exception stays in the unobserved `async` Deferred, `deferred` never completes, and the endpoint waits the full 10s (`SendPaymentCommandEndpoint.kt:33,42`). The scope is never cancelled: `PaymentCommandEndpointModule.kt:41` `stop() = accountEventPublisher.stop()`. In production the lambda is `delay(2.seconds); ProcessedSuccessfully` (module lines 30-33), so the failure path can't happen today. The only real effect is up to 2s of leftover delay coroutines after stop. The class is marked `// TODO delete after the NATS round-trip will be implemented`.
- Fix: CORRECT, with minor overreach. `processingResult() = scope.async(start = UNDISPATCHED) { awaitResult() }` plus `fun stop() = scope.cancel()`. The module now calls `sendPaymentProcessingResultSubscriber.stop()` in `stop()`. To do that, it drops the `SendPaymentProcessingResultSubscriber` type annotation and import, so the module now depends on the concrete stub type. The new test (`StubbedSendPaymentProcessingResultSubscriberTests`) would fail on base: `isCompleted` is false because the CompletableDeferred never completes. It follows the style rules (backtick name, PER_CLASS, AssertK, literal message). `runTest` is available through `swissknife.test.utils` (api `kotlinx-coroutines-test`). Of the 4 new testImplementation deps, `swissknife.ddd.test.utils` and `swissknife.test.utils` are redundant because `sharedAccountDomainTestUtils` already exports both as `api`. The test covers only the failure path, not cancellation on stop.
- Principles: minor tension with #5 (general-purpose contracts). Lifecycle was added to the stub instead of the port, so the real NATS subscriber will hit the same problem.
- Importance: 2 — latent, and only on a stub that is meant to be deleted.
- Confidence: 4 — clear trace; not executed.
- Recommendation: REDO MODIFIED. Make `SendPaymentProcessingResultSubscriber` extend swissknife `Stoppable` (`core.domain` is already an `api` dep of the domain model). In the stub, use `override suspend fun stop() = scope.cancel()` with the `scope.async { awaitResult() }` body. Keep the module field typed by the interface. Keep the test. Add only `projects.sharedAccountDomainTestUtils` and `libs.swissknife.core.test.utils` as test deps.

### 11.5 — `$arguments` logged before declaration (both endpoints)
- Defect in base: REAL. `SendPaymentCommandEndpoint.kt:28-29` and `DepositEventEndpoint.kt:25-26` log `$arguments` one line before `val arguments = arguments(request)`. At that point the name resolves to the companion's `private val arguments = Body...toLens()` (lines 41 and 35), so every request logs the lens's `toString()`.
- Fix: CORRECT. It swaps the two lines in both files and makes no other change. One side effect: a request whose body fails the lens is no longer logged as "Received", because the lens throws first. The log line now prints the full arguments (account numbers and amounts) at INFO, which is the same open question as 11.12.
- Principles: none.
- Importance: 2 — the request log is useless on every request today.
- Confidence: 5 — Kotlin name resolution is unambiguous here.
- Recommendation: REDO AS IS.

### 11.9 — `OutboundPayment.inbound()` swaps the accounts
- Defect in base: REAL (latent, no callers). `AccountEventDataExtensions.kt:9` is `InboundPayment(targetAccount = sourceAccount, sourceAccount = targetAccount, amount = amount)`. `InboundPayment.relevantAccount = targetAccount` and `OutboundPayment.relevantAccount = sourceAccount`, so the inbound event for A→B would credit A and be keyed to A's partition. `git grep "inbound()"` finds no callers.
- Fix: CORRECT and minimal (one line). The new `AccountEventDataExtensionsTests` uses literal accounts and amount (`2500.pence`). It would fail on base because the accounts come out swapped. The module already had `testImplementation(libs.swissknife.test.utils)`, so no build change was needed. Style matches.
- Principles: none.
- Importance: 3 — latent money-routing bug that hits as soon as the account-event-processor uses it.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 11.12 (partial) — Publisher log text says "compliance plan event"
- Defect in base: REAL. `PulsarAccountEventPublisher.kt:32` says "Successfully produced compliance plan event ...", a copy-paste leftover. It also logs `Event: {$value}` at INFO.
- Fix: CORRECT for the text only ("account event"). The INFO logging of the full event is unchanged; that part still needs an owner decision.
- Principles: none.
- Importance: 1 — wrong wording.
- Confidence: 5.
- Recommendation: REDO AS IS (text only). Decide the INFO payload logging separately, together with 11.5.

### 11.13 — "inbound-payment" serde test builds an `OutboundPayment`
- Defect in base: REAL. `AccountEventAvroSerdeTests.kt:24` has `"inbound-payment" to OutboundPayment.create().asEvent()`, so `InboundPaymentAvroSerde` is never round-tripped. `InboundPayment.Companion.create` already exists (`AccountEventDataTestFactories.kt:29`).
- Fix: CORRECT. It uses `InboundPayment.create()` and adds the import. I checked `InboundPaymentAvroSerde` against `InboundPayment.avsc`: field names match, so the new case should pass.
- Principles: none.
- Importance: 3 — a test that could not catch regressions in the InboundPayment serde.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 11.14 — Account-number test factory never produces 9
- Defect in base: REAL. `InternalAccountNumberTestFactories.kt:8` uses `random.nextInt(0, 9)`. swissknife `RandomGenerator.nextInt(from, until) = random.nextInt(from, until)` has an exclusive upper bound.
- Fix: CORRECT (`nextInt(0, 10)`).
- Principles: none.
- Importance: 2 — test-data coverage gap.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 11.15 — `InProcessServiceTests.afterAll` never stops the service
- Defect in base: REAL. `InProcessServiceTests.kt:73-74` is `fun afterAll() = specificationAfterAll()`, while `beforeAll` calls `service.startBlocking()` (line 70). The service is never stopped, so the Jetty servers and Pulsar producers leak and the container is stopped underneath them.
- Fix: CORRECT. It calls `service.stopBlocking()` and then `specificationAfterAll()`, importing `stopBlocking` from swissknife `core.domain.lifecycle`. It also starts exercising `Service.stop()` (and so 11.17 and 11.4's module stop) in a test. Small caveat: if `stopBlocking()` throws, the container teardown is skipped. A try/finally would avoid that, but it isn't essential.
- Principles: none.
- Importance: 2 — test resource leak; it also means the shutdown path was never exercised.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 11.17 — `stop()` doesn't close the `PulsarClient`
- Defect in base: REAL. `Service.kt:74-84`: `stop()` stops the HTTP adapter, the modules and the health adapter, but never calls `pulsarClient.value.close()`. The client is created at line 49 and built at lines 98-101.
- Fix: CORRECT. It adds `pulsarClient.value.close()` after `healthHttpDrivingAdapter.stop()`, so producers are closed by the module stops first and the readiness check is gone before the client closes. The call blocks inside a suspend function, which is acceptable at shutdown. As in base, a throwing module stop still skips the close; that is pre-existing.
- Principles: none.
- Importance: 2 — thread and connection leak on in-process stop.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 11.20 — README describes nonexistent SDKs
- Defect in base: REAL. `README.md:91-101` says "There are also example SDKs in Kotlin" and describes the Account Holder and Deposits SDKs. `git ls-tree` finds no SDK path in the repo.
- Fix: CORRECT. It turns the section into "### To Do / The following example SDKs in Kotlin are planned." and demotes the two SDK headings to `####`. Docs only.
- Principles: none.
- Importance: 2 — docs accuracy.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 11.21 — IMPROVEMENTS.md stale
- Defect in base: REAL. `IMPROVEMENTS.md` says Gradle 9.4.0, but `gradle-wrapper.properties` has `gradle-9.8.0-all.zip`. It says 31 modules, but `settings.gradle.kts` has 47 `content(...)` entries. It says "SNAPSHOT dependencies throughout", but `libs.versions.toml` has 0 SNAPSHOT entries. It says 26 test files, but base has 27 `.kt` files under test paths (58 non-test, which matches the existing "58 production files").
- Fix: INCOMPLETE (self-referential). Gradle 9.8.0, 47 modules and dropping the SNAPSHOT line are correct. "29 test files" counts the two test files the session itself added (11.4 and 11.9). After a revert the number depends on which tests are redone: 27 + the number of new test files. "88+ dependency refs" was left as is; base has 75 library and 8 plugin aliases (83).
- Principles: none.
- Importance: 2 — docs accuracy.
- Confidence: 5 — counted with `git ls-tree`/`grep`.
- Recommendation: REDO MODIFIED. Apply the Gradle, module-count and SNAPSHOT edits. Recount test files after the redo (27 at base, +1 for each new test file kept), and fix or drop "88+ dependency refs".

### 11.22 — `api.yaml` send-payment example named "DepositEvent"
- Defect in base: REAL. `content/contracts/http/src/main/resources/api/api.yaml:80-81`: the `/commands/send-payment/v1` request example is keyed `DepositEvent` with summary "A deposit event.", copied from lines 42-43. No Kotlin code refers to the example key.
- Fix: CORRECT. It renames the key to `SendPayment` with summary "A send payment command."
- Principles: none.
- Importance: 1 — cosmetic in the API docs.
- Confidence: 5.
- Recommendation: REDO AS IS.

### .gitignore — `*.pidjava_pid*.hprof` split
- Defect in base: REAL. `.gitignore:40` is the concatenation `*.pidjava_pid*.hprof`, introduced in `1b70eb7` (2026-03-30). It matches neither `*.pid` files nor heap dumps, so heap dumps could be committed.
- Fix: CORRECT. It splits the line into `*.pid` and `java_pid*.hprof`. The same split exists in 10 other workspace repos (lattice has only `java_pid*.hprof`), so treat it as a workspace-wide decision.
- Principles: none.
- Importance: 2 — accidental commit of large or sensitive heap dumps.
- Confidence: 5.
- Recommendation: REDO AS IS, consistently across the workspace repos.

### scripts/update-gradle.sh — `sed -i ''` to `sed -i.bak` + `rm`
- Defect in base: PARTLY. `update-gradle.sh:23` `sed -i '' 's/...'` is BSD/macOS syntax. On GNU sed, `''` is taken as the script and the expression as a filename, so it errors and `set -e` aborts after the wrapper was already regenerated. The owner works on macOS (darwin), and the script is only called from the `justfile` (`update-gradle`, `update-all`), not from CI. So it is a portability issue, not a bug for this owner.
- Fix: CORRECT. `sed -i.bak ... && rm "${props_file}.bak"` works on both BSD and GNU sed. lattice still uses the old form.
- Principles: none.
- Importance: 1 — portability only; works today on the owner's machine.
- Confidence: 4 — known BSD/GNU sed difference; not executed.
- Recommendation: REDO AS IS only as a workspace-wide change, including lattice. Otherwise DROP; nothing breaks on macOS.

## Unattributed changes

No functional change in base..snapshot lacks an item. Leftovers, all small:
- `gradle/libs.versions.toml`: internal version bumps across both commits (gradle-plugins 1.0.32→1.0.33, swissknife 1.0.35→1.0.37, pillar 1.0.17→1.0.19, acme-schema-catalogue 1.0.6→1.0.7). Excluded as mechanical. None of the fixes needs them. The catalogue's `AccountEvent.avsc` still has record name `AccountPlanEvent` in the workspace, so the bump doesn't silently touch 11.11.
- `.trivyignore`: owner work, confirmed above.
- Newline-at-EOF additions in `payment-command-endpoint/adapters/driven/nats/build.gradle.kts` and `StubbedSendPaymentProcessingResultSubscriber.kt`; incidental to 11.4.
- `PaymentCommandEndpointModule.kt`: removed the `SendPaymentProcessingResultSubscriber` import and type annotation. Part of 11.4; see the recommendation there to keep the interface type.
- `README.md`: Account Holder SDK and Deposits SDK headings demoted from `###` to `####`. Part of 11.20.
- `IMPROVEMENTS.md`: test-file count includes the session's own new tests. See 11.21.
