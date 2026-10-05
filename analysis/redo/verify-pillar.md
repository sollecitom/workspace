# pillar — independent verification of bug-hunt fixes

Refs: base `78de257`, snapshot `bug-hunt-snapshot-2026-10-05` (commits `39a29a1`, `bb46a8d`). Everything was read-only: I read the code with `git show`/`git diff`, checked http4k 6.61 bytecode (`HeadersKt.headerValues`/`removeHeader` compare names with `equals(ignoreCase = true)`), and read swissknife and the consumers. I built or ran nothing. "Test fails without fix" claims come from tracing the code. The checklist header says `just build-workspace` passed on the snapshot, so the added tests are taken to compile and pass.

The checklist marks 10.2–10.6, 10.10, 10.12 and 10.13 as deferred or by-design, and the diff confirms none of them changed code. Their coverage in GATEWAY.md is checked under that entry. 10.32 ("not a bug") also has no change. Its reasoning holds: `InvocationContextAvroSchemas` has namespace `acme.common.correlation.context`, so its sibling containers would fail `SchemaContainerTestSpecification`'s nested-namespace check.

---

### 10.1 — Gateway doesn't strip a client-sent invocation-context header; duplicates joined
- Defect in base: REAL. `GatewayInvocationContextFilter.kt:82` (`next(request.withoutAuthorization().withInvocationContext(invocationContext))`) appends the gateway's header and keeps the client's. `GatewayInfoContextParsingFilter.kt:49-51` joins duplicates with `","` and passes the result to `JSONObject`, which parses the first (client) object. There are two parts here:
  - The strip half is in the gateway stub (principle 3).
  - The join half is in `GatewayInfoContextParsingFilter`, which every service runs: `HttpApiExtensions.kt:13` → `StandardHttpFilter.kt:41` → `parseInvocationContextFromGatewayHeader`. Consumers reach it through `EndpointHttpDrivingAdapter` in both examples. Behind a correct gateway, duplicates never happen, so the join is dead and nonsensical code rather than an exploitable path.
- Fix: CORRECT, with part of it in the stub.
  - Stub: `withoutInvocationContext()` = `removeHeader(headerNames.correlation.invocationContext)`. It is case-insensitive in http4k.
  - Parser: `headerValues(...)`, `check(size <= 1)` (→ 400 through `asResponse`), then `singleOrNull().takeUnless { it.isNullOrBlank() }`. Same blank handling as base.
  - Also removes the owner's `// TODO this should be forked!`. That is justified: line 26 already calls `.forked()`.
  - Adds 2 testImplementation deps (`swissknife.core.test.utils`, `swissknife.correlation.core.test.utils`), which the tests need.
  - Tests (`GatewayInvocationContextFilterTests`):
    - "replaced by the one built by the gateway" fails on base: the forged Authenticated context wins and there are 2 header values.
    - "multiple … rejected" fails on base: 200, not 400.
    - "parsed regardless of case" fails on base: no context, so `key.mandatory` throws. It belongs to 10.7.
    - "replaced regardless of case" passes on base, because the case-sensitive parser ignores the client header. It only guards the combination of the stub strip and 10.7.
  - Style is OK (PER_CLASS, backticks, AssertK). The tests capture with `var … ; !!`.
- Principles: #3. The strip touches the unfinished stub, and the owner may prefer to leave it untouched.
- Importance: 2. Stub hardening is 1. Replacing a nonsensical join with a reject on the service path is 2.
- Confidence: 5. Code trace plus the http4k bytecode.
- Recommendation: REDO MODIFIED:
  - Keep the `GatewayInfoContextParsingFilter.rawInvocationContextValue` change (reject duplicates, case-insensitive), the stale-TODO removal, and the two parser tests ("multiple invocation context headers are rejected", "parsed regardless of the header name case").
  - Put those tests in a file named `GatewayInfoContextParsingFilterTests`.
  - Drop `withoutInvocationContext()` in the stub and the two gateway-chain tests, unless the owner wants the one-liner. In that case keep it with only the first gateway test.
  - Update the GATEWAY.md "(done)" row to match.

### 10.7 — Invocation-context header compared case-sensitively
- Defect in base: REAL. `GatewayInfoContextParsingFilter.kt:49` `headers.filter { it.first == headerNames.invocationContext }`. Header names are case-insensitive (RFC 9110), and http4k's lenses and `headerValues` ignore case. This is the service-side parser, not the stub.
- Fix: CORRECT. `headerValues(name)` is case-insensitive (bytecode: `StringsKt.equals(…, true)`). It is the same line as 10.1's parser change. The test fails on base.
- Principles: none. It is not the stub: every service behind the gateway uses this parser.
- Importance: 2. It only bites if a hop sends mixed-case names over HTTP/1.1. A pillar-built client sends lowercase, and HTTP/2 always does.
- Confidence: 5.
- Recommendation: REDO AS IS, together with the parser half of 10.1.

### 10.8 — `MessagingEventProcessor` dies for good on the first exception
- Defect in base: PARTLY. `MessagingEventProcessor.kt:25-44` → `ReceivedMessage.kt:26-32`: an exception from `processEvent` escapes `onEach`/`collect` in a `launch` on `CoroutineScope(SupervisorJob())` (lines 61, 84) with no handler. It is printed by the default uncaught handler, not the app logger. The message is neither acked nor nacked, and processing stops. Under principle 2, stopping is correct. The real defects are:
  - it is silent;
  - the processor's failure is isolated from the service (SupervisorJob), so the service looks healthy;
  - the Pulsar consumer stays open, so the unacked message is not redelivered until a restart.
- Fix: INCORRECT. `runCatching { processEvent(message) }.getOrElse { if (it is CancellationException) throw it else it.asProcessingFailure() }` routes thrown errors into the `Failure` branch, which calls `message.acknowledgeAsFailed()`. In Pulsar that is `consumer.negativeAcknowledge` (swissknife `PulsarReceivedMessage.kt:29`), and processing continues with the next message. That is nack plus skip-ahead. The new test asserts `wasAcknowledgedAsFailed()` for both messages, which enshrines the nack. A throwing `acknowledge()` still escapes.
- Principles: #2. It directly contradicts principle 2: it nacks and skips ahead.
- Importance: 4. Used path: modulith `AccountEventProcessorModule.kt:25`; element `HttpEventBridge.kt:34`, `CompliancePlanOutputsManager.kt:42`, `CompliancePlansViewer.kt:35`.
- Confidence: 5.
- Recommendation: DROP. Replace it with the principle-2 behaviour described under "Message processing finding". Thrown errors and `Failure` should both log at ERROR and stop the processor without acking or nacking.

### 10.11 — `User.fullName` missing space; tests assert the wrong value
- Defect in base: REAL. `User.kt:7` `"$firstName${otherNames…joinToString(" ") ?: ""} $lastName"` gives `"JohnWilliam Doe"`. `UserTests.kt:30,38` asserted that output. It feeds the `name` claim in `asClaims` (`AcmeJwtScheme.kt:161,213`).
- Fix: CORRECT. `(listOf(firstName) + otherNames + lastName).joinToString(" ")`, and the tests are corrected to literals. The new `AcmeJwtSchemeTests` test "the full name claim separates every name with a space" fails on base.
- Principles: none. It is in the JWT module of the unfinished gateway, where the owner deferred sibling items 10.10/10.12/10.13. It is cheap and self-contained.
- Importance: 2. Wrong output, but there are no consumers outside pillar: no `pillar.jwt` use in either example.
- Confidence: 5.
- Recommendation: REDO AS IS. It must go together with 10.14. With 10.14 alone, round-trips of users with other names break, because base only round-tripped by accident (`"JohnWilliam Doe".removePrefix("John")` → `"William Doe"`).

### 10.14 — `otherNames` gets the whole name when `given_name` isn't a prefix
- Defect in base: REAL. `AcmeJwtScheme.kt:86` `fullName.removePrefix(firstName).removeSuffix(lastName)…`: given `Johnny`, name `John Doe` gives `["John"]`; given `Jo` gives `["hn"]`.
- Fix: CORRECT. `takeIf { startsWith("$firstName ") && endsWith(" $lastName") }?.removePrefix(firstName)?.removeSuffix(lastName)?.split(" ")?.filterNot(isBlank) ?: emptyList()`.
  - Edge cases check out (`"John Doe"` → `[]`, `"Doe Doe"` → `[]`).
  - Don't swap to `removeSurrounding("$f ", " $l")`: it returns the input unchanged for `"John Doe"`.
  - Of the 4 new tests, 3 fail on base (Johnny, Jo, Smith). "Parsed from the full name" passes on base and serves as a regression guard.
- Principles: none (same stub caveat as 10.11).
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS, with 10.11.

### 10.15 — Acme `locale` falls back to `Example.defaultLocale`
- Defect in base: REAL but behaviour-neutral. `Acme.kt:6` imports `Example.defaultLocale`; line 28 `?: defaultLocale`. Both are `Locale.UK`.
- Fix: CORRECT. Removes the import and uses `Acme.defaultLocale`. No test, which is fine for a trivial line.
- Principles: none.
- Importance: 1. No behaviour change. It removes coupling to `Example`.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.16 — Cookie rule tests use `ParameterLocation.path`
- Defect in base: REAL. `StandardOpenApiRulesTests.kt` `inner class Cookies … parameterLocation = ParameterLocation.path`, so the cookie alphabet (`AcmeOpenApiRules.kt:30,39`) was never tested.
- Fix: CORRECT. One token: `ParameterLocation.cookie`.
- Principles: none.
- Importance: 3. A test that could not catch regressions.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.17 — `AcmeOpenApiRules` version regex rejects `/v10`
- Defect in base: REAL. `AcmeOpenApiRules.kt:34` `Regex("v[1-9]+\$")`, used with `matchEntire` (swissknife `WhitelistedAlphabetPathNameRule.kt:18`). `v10` fails because `0` is not in `[1-9]`.
- Fix: CORRECT. `Regex("v[1-9][0-9]*")`; dropping `$` is harmless with `matchEntire`. The trailing and leading `v10` tests fail on base. The `v01` rejection test passes on base and serves as a guard.
- Principles: none.
- Importance: 2. Wrong, but only from version 10 on.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.18 (partly fixed) — OpenAPI rule tests never exercise JSON example rules
- Defect in base: REAL. `util/OpenApiTestSpecification.kt:39` uses only `text/plain`, so `mandatoryRequestBodyExampleRule` (JSON only) and the JSON branch of `mandatoryResponseBodyExampleRule` were never hit.
- Fix: INCOMPLETE, as the checklist says. Adds `JsonExamples` with request and response cases that assert the exact violation type and media types. They fail if `application/json` is removed from `mediaTypesFor…MustHaveAnExample` or the rule is dropped from the set. `exampleSchemaComplianceRule` is still untested.
- Principles: none.
- Importance: 2. Coverage of pillar's rule configuration.
- Confidence: 5.
- Recommendation: REDO AS IS. The schema-compliance case can be added later.

### 10.20 — `AcmeHttpApiDefinitionTests` assertions can't fail
- Defect in base: REAL. The tests asserted `isNotNull()` on non-nullable `HttpApiDefinition.companyWide` and `.headerNames`.
- Fix: CORRECT. Asserts literal header names. Verified against swissknife `CompanySpecificHttpHeaderNames.kt:11-22`. The tests are renamed to precise names.
- Principles: none.
- Importance: 3. Tests that could not catch regressions.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.21 — CONTEXT/IMPROVEMENTS/READMEs stale
- Defect in base: REAL.
  - `settings.gradle.kts` has `mavenLocal()` (lines 5, 13) and no `includeBuild`, and pillar has its own `gradle/libs.versions.toml`.
  - Known Issue #5 is stale (`GatewayInfoContextParsingFilter.kt:26` forks).
  - The version is not SNAPSHOT.
  - `ProtectedString.kt:7` is `EncryptionMode.GCM.Metadata`, and the encryption avro module has GCM/XTS/Metadata serdes and no CTR.
- Fix: CORRECT. Docs only.
  - The test count is updated to 123, which is accurate for the snapshot (base had 116, not the claimed 107). If some tests aren't redone, recount.
  - Removing the owner's stale code TODO (`// TODO this should be forked!`) is justified.
  - The renumbered IMPROVEMENTS list drops "Move to semantic versioning".
- Principles: none.
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.22 — `scripts/update-gradle.sh` `sed -i ''` is BSD-only
- Defect in base: REAL. Line 23 `sed -i '' 's/…/'`: GNU sed treats `''` as the script and the expression as a file, which fails under `set -euo pipefail`.
- Fix: CORRECT. `sed -i.bak … && rm "${props_file}.bak"` works on both BSD and GNU sed.
- Principles: none.
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.23 — `jwt-parsing-tests` publishes an empty jar
- Defect in base: REAL. `modules/jwt/parsing/tests` contains only `src/test`, but `build.gradle.kts:3` applies `maven-publish-conventions`. `publication-state.properties` lists artifacts 96-100 for it.
- Fix: CORRECT. Drops the plugin; the snapshot's publication-state no longer lists it. No consumer references it (grep of both examples' `.kts`/`.toml`).
- Principles: none.
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.24 — Three JSON serdes use leading-slash schema paths
- Defect in base: REAL. `EventContextJsonSerde.kt:15`, `EventReferenceJsonSerde.kt:18`, `HappeningTypeJsonSerde.kt:14` use `"/json/schemas/…"`. `jsonSchemaAt` → `ClassLoader.getResource` never resolves a leading `/`. The resources exist without the slash in acme-schema-catalogue `json/common`. Any read of `.schema` throws. No production code reads these schemas today: serialize/deserialize don't, only `JsonSerdeTestSpecification` does.
- Fix: CORRECT. Three one-character changes. The new `EventContextJsonSerializationTests`, `EventReferenceJsonSerializationTests` and `HappeningTypeJsonSerializationTests` read the schema and fail on base.
- Principles: none.
- Importance: 3. Broken published API, latent because nothing reads it yet.
- Confidence: 5. The original report reproduced it against the jar; the resource layout is confirmed.
- Recommendation: REDO AS IS.

### 10.25 — `UnitJsonSerde` points at a nonexistent schema
- Defect in base: REAL. `UnitJsonSerde.kt:11` `"example/http-event-bridge/result/Unit.json"`. The catalogue ships `json/schemas/acme/common/unit/Unit.json`.
- Fix: CORRECT. The path is corrected. The new `UnitJsonSerializationTests` fails on base. It is the first test in `json/serialization/core`; the base `build.gradle.kts` already declares the test deps.
- Principles: none.
- Importance: 3. Latent; no consumer uses `Unit.jsonSerde`.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.27 (partly fixed) — Leaf JSON serdes have no schema-compliance tests
- Defect in base: REAL. `AcmeJsonSerdeTestSpecification` only covers serdes that have a test class.
- Fix: INCOMPLETE, as the checklist says. The tests added are those for MonthAndYear, Unit, EventContext, EventReference and HappeningType (10.24/10.25/10.28/10.29). The actor leaves are still untested and would fail `AcmeJsonSchemaRules`; that needs a catalogue or rule decision.
- Principles: none.
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS. This adds no work beyond 10.24/10.25/10.28/10.29.

### 10.28 — `MonthAndYearJsonSerde` untested
- Defect in base: REAL. No test file under `json/serialization/core/src/test` existed.
- Fix: CORRECT. `MonthAndYearJsonSerializationTests` adds 3 literal cases (round trip plus Acme schema compliance).
- Principles: none.
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.29 — `EventReference`/`HappeningType` JSON serdes never exercised
- Defect in base: REAL. `EventMetadataJsonSerdeTest.kt:17-23` only had null parent and originating references.
- Fix: CORRECT. Adds a case with both references populated, plus the dedicated test classes listed under 10.24.
- Principles: none.
- Importance: 3. This gap is what hid 10.24.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.30 — `AccessAvroSchemas.all` omits two schemas
- Defect in base: REAL. `AccessAvroSchemas.kt:23` `sequenceOf(unauthenticatedAccess)`, while `authenticatedAccess` and `access` are declared at lines 18-19.
- Fix: CORRECT. All three are in the same namespace, so the `SchemaContainerTestSpecification` namespace test still holds. The new literal-name test fails on base.
- Principles: none.
- Importance: 2. Nothing consumes `all`/`schemasAndDependencies` outside swissknife's definition.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.31 — `IdentityAvroSchemas.all` omits `idType`
- Defect in base: REAL. `IdentityAvroSchemas.kt:15` `sequenceOf(id)`.
- Fix: CORRECT. `sequenceOf(idType, id)`. The test fails on base.
- Principles: none.
- Importance: 1.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.33 — `EventCompositeAvroSerde` untested
- Defect in base: REAL (coverage gap). `EventCompositeAvroSerde.kt` had no test, and `Event.Composite.equals` compares only id and type.
- Fix: CORRECT. The new test round-trips and asserts `data` (a literal) and `metadata` separately. `WithEventAvroSerdeSupport.kt` is still untested; that is minor.
- Principles: none.
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.34 — Serde test generators never produce null/empty cases
- Defect in base: REAL. There were no cases for `UserAccount.locale = null`, `Origin.ipAddress = null`, `specifiedTargetCustomer`, or empty `AccessScope`/`Toggles`.
- Fix: CORRECT. Adds those cases to the Avro and JSON test classes. The factories and `copy` exist: `Origin` and `UserAccount` are data classes, and `Customer.create(isTest)` and `specifiedTargetCustomer` exist in swissknife test utils. These cases are independent of the catalogue's nullable-default changes, since round-tripping null works either way.
- Principles: none.
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS.

### .gitignore — split merged line
- Defect in base: REAL. `.gitignore:40` `*.pidjava_pid*.hprof` (a missing newline) meant neither `*.pid` nor `java_pid*.hprof` was ignored.
- Fix: CORRECT. Split into two lines.
- Principles: none.
- Importance: 1.
- Confidence: 5.
- Recommendation: REDO AS IS.

### GATEWAY.md + README link
- Defect in base: n/a. New doc, written with the owner. It tracks 10.2–10.6, 10.10 and 10.12.
- Fix: CORRECT overall, with four inaccuracies:
  - Accurate parts:
    - The Position section matches the code: `StandardHttpFilter` → `parseInvocationContextFromGatewayHeader`.
    - Responsibilities match principle 3: the gateway sets target customer/tenant, is-test and toggles, and authenticated event clients are trusted.
    - Gap rows checked against base and accurate: audience skipped (swissknife `JwtProcessorFactory.kt:20` `setSkipDefaultAudienceValidation`); `aud` read with `getRequiredString` (`AcmeJwtScheme.kt:130`); `issuerForDomain(request.uri.authority)` (`GatewayInvocationContextFilter.kt:89,189`); cache keyed by token (lines 78, 105); `Example.tenant` and `isTest = false` (lines 141-142, 157); caller-supplied headers (lines 93-96, 165-185); 400 with raw message (line 194); acr/allowed-origins/session_state (`AcmeJwtScheme.kt:105-109,116,132`); no machine-client auth, route-level authorisation or body limits.
  - The README link sentence is accurate.
  - Inaccuracies:
    1. **"JWT `nbf` | `JWT.isValidAtTime` ignores it"** is technically true (swissknife `JWT.kt:27` checks only `exp`) but not a real gap. jose4j's `JwtConsumer` rejects a not-yet-valid `nbf` on first verification, and `isValidAtTime` is only used to re-check cached tokens, which were already past `nbf`. Confidence 4 (jose4j default `NumericDateValidator`).
    2. **"Error logging | method and path only (done)"** is not true of pillar. It relies on the swissknife snapshot change to `CatchAndLogErrorsRequestFilter` (`it.toMessage()` → `method + uri.path`). Even in the snapshot, `GatewayHttpFilter.kt:29` still logs the full `request.uri` (query string included) plus the lens failure text.
    3. **"Client-supplied invocation-context header | stripped; duplicates rejected (done)"** is only true while 10.1 is redone in full.
    4. **10.13** (organisation from email domain) is marked "tracked in GATEWAY.md" in the checklist, but it has no row.
- Principles: none. It is docs only, and it is consistent with #2/#3.
- Importance: 2. Docs accuracy.
- Confidence: 4.
- Recommendation: REDO MODIFIED:
  - Drop or reword the `nbf` row, e.g. "re-check of cached tokens uses `exp` only (initial verification checks `nbf`)".
  - Make the error-logging row match what is actually redone in swissknife and pillar, or mark it as a gap until `GatewayHttpFilter`'s lens-failure log uses the path only.
  - Make the strip/duplicates row match the 10.1 decision (with the recommended 10.1: "duplicates rejected by services; stub does not strip").
  - Add a "Claims | organisation name derived from the email domain (wrong for subdomains and case)" row for 10.13.

---

## Message processing finding

### MP-1 — `MessagingEventProcessor` nacks on `Failure` and keeps consuming (base)
- Evidence (base `78de257`):
  - `modules/messaging/domain/src/main/kotlin/sollecitom/libs/pillar/messaging/domain/event/processing/MessagingEventProcessor.kt:39-42`:
    ```kotlin
    is Failure -> {
        logger.warn(error = result.error) { "Failed to process message …" }
        message.acknowledgeAsFailed()
    }
    ```
  - Then the `onEach`/`collect` loop (`ReceivedMessage.kt:27-32`) moves on to the next message.
  - `acknowledgeAsFailed` is `consumer.negativeAcknowledge(delegate)` (swissknife `PulsarReceivedMessage.kt:29`). Pulsar redelivers it after `negativeAckRedeliveryDelay` while later messages are processed and acked, so it skips ahead and processes out of order.
  - No dead-letter policy is configured anywhere (grep for `deadLetter` in swissknife, pillar and the examples), so the nacked message is retried indefinitely, out of order.
  - Every consumer handler returns `Failure` for any exception via swissknife `processAsCompositeEvent` (modulith `account-event-processor` `Application.kt:40-60`; element `compliance-plans-viewer` and `http-event-bridge` `ApplicationImplementation.kt`). So this branch is the live failure path for all four processors: modulith `AccountEventProcessorModule.kt:25`; element `HttpEventBridge.kt:34`, `CompliancePlanOutputsManager.kt:42`, `CompliancePlansViewer.kt:35`.
  - The base test `MessagingEventProcessorTests.kt:53-64` ("failing to process an event") asserts both messages are `wasAcknowledgedAsFailed()`. That encodes the nack-and-continue behaviour.
  - Thrown exceptions (10.8) take a different path. Base stops, without ack or nack, which is the principle-2 outcome, but silently (SupervisorJob, no handler, so no app log) and without closing the consumer. With a Failover subscription and no `ackTimeout`, the still-connected consumer keeps the partition, so the unacked message is not redelivered until restart.
  - The snapshot's 10.8 change makes thrown exceptions nack and continue too, so it widens the violation.
- Principle-2-compliant behaviour:
  - `Success`/`NoOp` → `acknowledge()` (unchanged).
  - `Failure`, or any non-cancellation exception from `processEvent`/`acknowledge`:
    - log at ERROR with the message id and cause;
    - do not ack and do not nack;
    - stop processing: end the collection by throwing out of `onEach`, or cancel the processing job.
  - Make the stop visible and make redelivery happen, either:
    - let the failure propagate to the service lifecycle instead of being swallowed by a private `SupervisorJob` (e.g. a caller-supplied scope or a failure callback that stops the service / fails health); or
    - close the consumer on stop, so Pulsar hands the unacked message to the next (Failover) consumer or to the restarted one.
  - Cross-repo cleanup that principle 1 allows:
    - Remove `ReceivedMessage.acknowledgeAsFailed` and its implementations and spy plumbing from swissknife (see `verify-swissknife-messaging.md` A1–A3).
    - Rewrite `MessagingEventProcessorTests` "failing to process an event": the first message is neither acked nor nacked, the second is never processed, and the processor reports that it stopped.
    - `processAndWaitUntilAllAcked` cannot be used for failure cases (it would hang). Add a helper that waits for processor termination.
- Importance: 4. Wrong behaviour (out-of-order processing of account and compliance events) on every used event-processing path. It is not 5 only because there is no data to preserve (principle 1).
- Confidence: 5. Direct code trace across pillar, swissknife and both consumers.

---

## Unattributed changes

Excluded as mechanical: `gradle.properties` (`currentVersion` 1.0.17 → 1.0.19), `publication-state.properties`, and `gradle/libs.versions.toml` internal versions (swissknife 1.0.35 → 1.0.37, acme-schema-catalogue 1.0.6 → 1.0.7, gradle-plugins 1.0.32 → 1.0.33).

Every other hunk in `78de257..bug-hunt-snapshot-2026-10-05` maps to an item above. No unrelated code changes were found. Three things to watch when redoing:
- **Owner TODO removed:** `GatewayInfoContextParsingFilter.kt:44` `// TODO this should be forked!`, filed under 10.21. The removal is justified because the value is already forked at line 26.
- **Cross-repo coupling:** the version bumps make the pillar snapshot depend on the swissknife and catalogue snapshot changes.
  - None of the pillar fixes above needs them (`asProcessingFailure` already exists in base swissknife, and all JSON schema resources exist in the base catalogue).
  - GATEWAY.md's "Error logging (done)" row is true only with the swissknife `CatchAndLogErrorsRequestFilter` change.
- **Test-only build deps** in `modules/web/api/utils/build.gradle.kts` (`swissknife.core.test.utils`, `swissknife.correlation.core.test.utils`) belong to the 10.1/10.7 tests and are needed only if those tests are redone.
