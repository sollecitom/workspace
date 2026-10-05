# Verification — swissknife messaging, pulsar, nats, avro, json, compliance-checker, logger, logging, opentelemetry, test, scripts

Refs: base `3f1d24b` → snapshot `bug-hunt-snapshot-2026-10-05`. All base evidence comes from `git show 3f1d24b:<path>`. I ran no builds or tests. "Test fails without fix" claims come from tracing the code by hand against the base, plus `javap` on jars in the Gradle cache.

Items in scope that were marked fixed: 9.106, 9.108, 9.109, 9.110, 9.112, 9.114, 9.118, 9.121, 9.123, 9.124, 9.125, 9.126, 9.127, 9.129, 9.130, 9.132, 9.134, 9.138, 9.140, plus the `scripts/update-gradle.sh` change (checklist 10.22). No open `[ ]` item in 9.103–9.140 says it was partly fixed. 9.141 is outside the numeric range, but it sits directly on the acknowledgement path, so it is assessed under "Message acknowledgement findings" (A4).

---

### 9.106 — `removeFromLast("-partition")` mangles topic names
- Defect in base: REAL. `modules/pulsar/messaging/adapter/.../protocol/PulsarReceivedMessage.kt:31` has `private fun String.withoutPartitionId(): String = removeFromLast(PARTITION_TOPIC_PREFIX)` with `PARTITION_TOPIC_PREFIX = "-partition"` (line 35). `removeFromLast` (kotlin/extensions `StringExtensions.kt:32-35`) cuts from the last `-partition` to the end of the string. So `persistent://t/ns/user-partitioning` becomes `persistent://t/ns/user`, and a namespace containing `-partition` truncates everything after it. The result feeds `Topic.parse` for the message ID, which is used in lineage.
- Fix: CORRECT. The fix uses `TopicName.get(this).partitionedTopicName`. That only strips a real `-partition-<n>` suffix and otherwise returns the name unchanged. `org.apache.pulsar.common.naming.TopicName` is present, not relocated, in `pulsar-client-admin-4.2.4.jar`, which reaches the adapter through `pulsarUtils`' `api(libs.pulsar.client.admin)`. The diff is minimal (the unused import and companion were removed). No test was added: the module has no tests and needs a broker or a mocked `Message`.
- Principles: none.
- Importance: 2. Only topic, tenant or namespace names containing `-partition` outside the suffix are affected. No downstream topic does this (`account-events`, `compliance-plan-events`, `compliance-plans-lifecycle-json`).
- Confidence: 4. Clear trace; Pulsar's `TopicName` semantics are well known.
- Recommendation: REDO AS IS.

### 9.108 — `withBrokerEnv(map)` omits `PULSAR_PREFIX_`
- Defect in base: REAL. In `modules/pulsar/test/utils/.../PulsarContainerExtensions.kt`, line 30 (`withEnv("PULSAR_PREFIX_$propertyName", …)`) adds the prefix, but line 34 in the map overload calls `container.withEnv(propertyName, propertyValue)`, so map entries never reach the broker config.
- Fix: CORRECT. The map overload now folds with `container.withBrokerEnv(propertyName, propertyValue)`. It is a one-token change.
- Principles: none.
- Importance: 2. This is a test utility, and no consumer repo calls `withBrokerEnv`.
- Confidence: 5. Visible in the code.
- Recommendation: REDO AS IS.

### 9.109 — Protocol property filter drops user `PROTOCOL*` properties
- Defect in base: REAL. `protocol/ProtocolProperties.kt:5,7` filters with `!it.startsWith("PROTOCOL")`, while `contextualize` (line 9) writes `PROTOCOL-<key>`. A user property such as `PROTOCOL_VERSION` or `PROTOCOLS` is silently removed from `ReceivedMessage.properties`.
- Fix: CORRECT. The constant becomes `"PROTOCOL-"` and `contextualize` becomes `"$PROTOCOL_PROPERTY_PREFIX$propertyKey"`. The serialised names (`PROTOCOL-MESSAGE-CONTEXT-…`, see `MessageContextPropertiesSerde.kt:7-8`) are unchanged, so there is no wire change.
- Principles: none.
- Importance: 2. Edge case, and no in-repo property uses that prefix.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.110 — Null message key NPE
- Defect in base: REAL. `PulsarReceivedMessage.kt:20` has `override val key: String get() = delegate.key`. Pulsar's `Message.getKey()` returns null when no partition key was set, and Kotlin's platform-type null check throws an NPE on access. This matters downstream: pillar's `MessagingEventProcessor.kt:29` logs `message.key` at INFO for every received message, so a keyless message from any external producer crashes the processor.
- Fix: CORRECT but a compromise. `delegate.key ?: ""` keeps `Message.key: String`. It does conflate "no key" with "empty key". Principle 1 would allow making `key` nullable across repos instead, but that change is wider (OutboundMessage, converters' `key(event)`, pillar, examples).
- Principles: none. Note that under principle 2 a crash on such a message is not data loss, only a stuck consumer.
- Importance: 3. A keyless message stops the processor on a used path, though all in-repo producers set keys.
- Confidence: 5.
- Recommendation: REDO AS IS. If the owner prefers a precise contract, make `key: String?` across repos instead.

### 9.112 — `PulsarReadinessCheck` swallows `CancellationException`
- Defect in base: REAL. `pulsar/utils/.../readiness/PulsarReadinessCheck.kt:25` catches `Exception`, which includes `CancellationException`, and returns `ReadinessCheckResult.Failed`.
- Fix: CORRECT. `currentCoroutineContext().ensureActive()` was added as the first statement in the catch, so cancellation propagates only when the calling coroutine itself is cancelled. This is consistent with the identical change to `PostgresReadinessCheck` (sql module, another verifier).
- Principles: none. The base already had `// This is fine` comments at lines 36/38; the fix added none.
- Importance: 2. Robustness: with `withTimeout`, the outer scope still throws, so the visible effect is small.
- Confidence: 4.
- Recommendation: REDO AS IS.

### 9.114 — `Topic.parse` truncates names containing `_` and similar
- Defect in base: REAL. `messaging/domain/.../topic/Topic.kt:57-59` uses the groups `[a-zA-Z0-9.\-]+`, and line 67 uses `matcher.find()`. So `persistent://t/ns/my_topic` silently parses as name `my`, and trailing garbage is accepted. `TenantAgnosticTopic.kt:23-24,32` has the same problem, and also excludes `.`.
- Fix: CORRECT. The groups become `[\w.=:\-]+`, which is Pulsar's NamedEntity alphabet `[-=:.\w]`, and the code uses `matches()`. There are three tests:
  - The all-underscores `Topic` test throws on base, because there is no match at all.
  - The trailing-`?` test passes parsing on base (because of `find()`), so it fails on base as intended.
  - The `TenantAgnosticTopic` underscore test parses as `my` on base, so it fails on base.
- Principles: none. The tests follow the existing nested-class style, with backtick names and literal expectations.
- Importance: 3. A latent silent-corruption bug in IDs and lineage. No consumer topic uses `_`, `=` or `:` today.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.118 — `additionalProperties` not `open`
- Defect in base: REAL. In `EventMessageConverterTemplate.kt:21`, `protected fun additionalProperties(event)` is final with an `emptyMap()` body, so the hook used at line 14 can never be overridden. It is dead.
- Fix: CORRECT. The fix is `protected open fun`.
- Principles: none. It is an extension point (contract), not added behaviour.
- Importance: 2. No subclass in any repo needs it today.
- Confidence: 5.
- Recommendation: REDO AS IS. The alternative is to delete the hook, if the owner sees no need for it.

### 9.121 — NATS consumer subscribes per collector and leaks
- Defect in base: REAL. `nats/client/.../NatsConsumerAdapter.kt:21-30`: every `messages` collection runs `onSubscription`, which creates a new `Dispatcher` and subscribes all subjects again, all emitting into the same `MutableSharedFlow`. Nothing ever unsubscribes, so the Nth collection receives each message N times.
- Fix: CORRECT. The dispatcher and subscriptions are now created once via `by lazy`, and `onSubscription { dispatcher }` forces it. The semantics are otherwise unchanged: messages that arrive while nobody collects are dropped, as in base, because there is no replay. The test (two `first()` rounds, then `take(2)` expecting `["first","second"]`) would get `["first","first"]` on base, with three dispatchers.
- Principles: none. The test uses a backtick name and literal expectations.
- Importance: 3. modulith-example's `shared/nats/adapter` depends on `swissknife.nats.client` but has no Kotlin sources using it, so this is latent.
- Confidence: 4. Clear trace; the checklist reports 3/3 failures before the fix.
- Recommendation: REDO AS IS.

### 9.123 — NATS container `customize` ignored
- Defect in base: REAL. In `nats/test/utils/.../NatsContainerExtensions.kt:12,14`, the `customize` parameter is never applied.
- Fix: CORRECT. `.apply(customize)` is added before `.build()` in both functions.
- Principles: none.
- Importance: 2. Test utility, no consumer usage.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.124 — Avro `setRecords` fails on nullable arrays
- Defect in base: REAL. `avro/serialization/utils/.../AvroRecordBuilderImpl.kt:77-78` builds `GenericData.Array(fieldSchema, value)` with the raw field schema. For `["null", array]` that throws `AvroRuntimeException: Not an array schema`.
- Fix: CORRECT. A private `Schema.arraySchema()` unwraps a UNION to its ARRAY branch, mirroring the existing `getEnumFieldSchema` pattern at lines 86-95. The test `setting records on a nullable array field` throws on base. The test also sets unrelated `amount`/`count` fields; that is harmless noise.
- Principles: none.
- Importance: 3. Latent: no consumer calls `setRecords` on a nullable field today.
- Confidence: 5.
- Recommendation: REDO AS IS. Optionally drop the irrelevant `amount`/`count` setters from that test.

### 9.125 — Avro `getBigInteger`/`getBigDecimal` fail on `Utf8`
- Defect in base: REAL. `AvroGenericRecordExtensions.kt:22,28` cast with `it as BigInteger` / `it as BigDecimal`. `set(BigDecimal)` on a `string` field is written via `SpecificDatumWriter` (`AvroSerializationUtils.writeAsBytes`, which supports stringable types) and read back by `SpecificDatumReader` as `Utf8`, so the getter throws `ClassCastException`.
- Fix: CORRECT. The code becomes `it as? BigX ?: BigX(it.asString())`, reusing the existing `AvroStringUtils.asString()`. The round-trip test fails on base. The not-serialised test passes on base and guards the fast path.
- Principles: none.
- Importance: 3. Latent: pillar's `CryptographicKeyMetadataAvroSerde.kt:9` only imports `getBigInteger` and doesn't use it.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.126 — `LocalResourcesAvroSchemaRepository` accumulates ClassGraph paths
- Defect in base: REAL. `LocalResourcesAvroSchemaRepository.kt:10,24`: a single lazy `ClassGraph` gets `acceptPaths(...)` added on every call. `acceptPaths` mutates the scan spec, so later searches return schemas from earlier namespaces too.
- Fix: CORRECT. A new `ClassGraph()` is created per call. There is no performance regression, because base already ran `scan()` per call. The analysis also suggested `acceptPathsNonRecursive` (nested namespaces are still included); the fix didn't do that, which is reasonable because it is a semantics decision. The test (search `alpha`, then `beta`, expect exactly `beta.Two`) fails on base, and it adds two test `.avsc` resources.
- Principles: none.
- Importance: 2. Only reached via `AvroSchemaCatalogueTemplate`; no consumer calls `findAllInNamespace` twice.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.127 — Avro schema checker rules NPE on namespace-less / non-record schemas
- Defect in base: REAL.
  - `MandatoryNamespacePrefixRule.kt:11` and `WhitelistedAlphabetNamespaceNameRule.kt:11` pass `target.namespace` (null for a namespace-less record) into `check(namespace: String)`, which throws an NPE.
  - `WhitelistedAlphabetFieldNameRule.kt:11` calls `target.fields`, which throws `Not a record` for an enum.
- Fix: CORRECT.
  - `namespace.orEmpty()`: the prefix rule reports a violation with `""`, and the alphabet rule is compliant.
  - The field-name rule returns `Compliant()` for non-RECORD schemas.
  - Three tests; all fail on base.
  - A primitive top-level schema would still throw `Not a named type` from `getNamespace()`, but such schemas are not realistic inputs.
- Principles: none.
- Importance: 2. Robustness of compliance rules; no consumer repo uses these rules.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.129 — `JsonSchema` uses `as` where `as?` was meant
- Defect in base: REAL. `json/utils/.../JsonSchema.kt:26` has `value as CompositeSchema? ?: return@lazy emptySet()`. A boolean subschema (`true` becomes jsonsKema `TrueSchema`) throws `ClassCastException` instead of returning no properties.
- Fix: CORRECT. The fix is `value as? CompositeSchema`. The test `{"properties":{"anything":true}}` fails on base.
- Principles: none.
- Importance: 2. Pillar's JSON schema rules walk `properties`, so a schema with a `true` property schema would crash them. That is plausible but uncommon.
- Confidence: 4. I relied on jsonsKema mapping boolean schemas to `TrueSchema`/`FalseSchema`, consistent with `JsonSchema.kt:31`; I didn't execute it.
- Recommendation: REDO AS IS.

### 9.130 — JSON schema cache not thread-safe
- Defect in base: REAL, latent. `JsonSchemaUtils.kt:37` uses `mutableMapOf()` (a LinkedHashMap) with `computeIfAbsent` inside a JVM-global `schemaClient`.
- Fix: CORRECT. The map becomes a `ConcurrentHashMap`. The mapping function (`delegate.get`) doesn't touch the cache, so CHM's recursive-update guard is not an issue. No test, which is reasonable.
- Principles: none.
- Importance: 2. Only bites with concurrent schema loading, such as parallel tests or lazy serdes on several threads.
- Confidence: 3. The race is real; I didn't confirm that it occurs in practice.
- Recommendation: REDO AS IS.

### 9.132 — SLF4J adapter drops the throwable in `log("msg {}", arg, ex)`
- Defect in base: REAL. In `logger/slf4j/adapter/.../Slf4jLoggerAdapter.kt`, the `(format, arg)`, `(format, arg1, arg2)` and vararg overloads of all five levels (lines 17-19, 30-32, 43-45, 56-58, 69-71) call `logger.x { format(...) }`, and `format` (line 79) keeps only `FormattingTuple.message`. The throwable SLF4J extracts from the trailing argument is discarded, so Pulsar, Jetty and Netty error logs lose their stack traces.
- Fix: CORRECT.
  - Each overload passes `throwableIn(args)` = `MessageFormatter.getThrowableCandidate(args)`, which is public static in slf4j-api 2.0.20 (checked with `javap`). The message stays lazy.
  - The marker overloads delegate to these overloads, so they are covered too.
  - The message text matches SLF4J semantics: the trailing throwable is excluded from substitution, so `warn("Failed for {}", ex)` gives `"Failed for {}"`, which the test asserts.
  - The first three of the four tests fail on base, because the error is null. The fourth guards the no-throwable case.
  - The tests use a recording `Logger`, PER_CLASS, backtick names and literal expectations.
- Principles: none.
- Importance: 4. Every service that routes SLF4J through swissknife loses exception details from third-party libraries.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.134 — `DefaultLoggerFactory.alreadyConfigured` never set; vars not volatile
- Defect in base: REAL. `logger/core/.../DefaultLoggerFactory.kt:13,19`: `alreadyConfigured` is never set to true, so `check(!alreadyConfigured)` is dead. The interface KDoc says "Supports runtime reconfiguration", and `StandardLoggingTests` reconfigure `JvmLoggerFactory` repeatedly. The three configuration `var`s are written by `configure` and read from any thread.
- Fix: CORRECT. The dead flag and check are removed, and `@Volatile` is added on the three vars.
- Principles: none.
- Importance: 1. The dead check is cosmetic; `@Volatile` is marginal robustness, since configuration happens at startup.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 9.138 — Logging tests leave system properties set
- Defect in base: REAL. In `logging/standard/configuration/src/test/.../StandardLoggingTests.kt`, line 35 sets `LOGGING_FORMAT=json` and line 49 sets `CUSTOM_LOG_FORMAT_PROPERTY_NAME`, and neither is cleared. If test 2 runs before test 3, test 3 passes even if the custom property name were ignored, because `LOGGING_FORMAT` is still set.
- Fix: CORRECT. `@AfterEach` clears both properties, and `customPropertyName` moved to a class val.
- Principles: minor naming nit: `fun afterEach()` is not a precise name; something like `clearLoggingSystemProperties` would be.
- Importance: 3. As written, the test can't catch a regression.
- Confidence: 5.
- Recommendation: REDO MODIFIED: same change, but rename `afterEach` to a precise name such as `clearLoggingSystemProperties`.

### 9.140 — `withCapturedStandardOutput(ERR)` captures stdout and leaves `System.out` broken
- Defect in base: REAL. `test/utils/.../StandardOutputUtils.kt:12` always calls `System.setOut(printStream)`. The `finally` block (line 20) restores only `standardPrintStream`, so with `ERR`, stdout stays redirected to a closed capture stream for the rest of the JVM, and stderr is not captured.
- Fix: CORRECT. The fix is `standardPrintStream.set(printStream)`. Two of the three tests (capture ERR; `System.out` untouched afterwards) fail on base. The third guards OUT.
- Principles: none.
- Importance: 3. Latent: no repo uses `ERR` today, but the first use would break all later stdout in the JVM.
- Confidence: 5.
- Recommendation: REDO AS IS.

### 10.22 (swissknife part) — `scripts/update-gradle.sh` `sed -i ''` is BSD-only
- Defect in base: REAL. `scripts/update-gradle.sh:23` has `sed -i '' 's/…/'`. GNU sed takes `''` as the script and the expression as a filename, so it fails. Because of `set -e`, the script then aborts after `./gradlew wrapper` has already rewritten the wrapper.
- Fix: CORRECT. The fix is `sed -i.bak … "$props_file"` followed by `rm "${props_file}.bak"`, which is portable across BSD and GNU sed.
- Principles: none.
- Importance: 2. The owner runs on macOS, and this repo has no CI directory; it only matters on Linux.
- Confidence: 5.
- Recommendation: REDO AS IS.

---

## Message acknowledgement findings

Principle 2: acknowledge only on success; never nack, dead-letter or skip ahead; on failure, stop processing and let Pulsar redeliver unacked messages.

Context for all items below: swissknife's Pulsar consumers default to `Failover`, `Durable`, `Earliest` (`DefaultPulsarConsumerCustomization.kt:10-14`), and `PulsarPartitionChangeAwareMessageConsumer.kt:18` forces `Failover`. No `ackTimeout`, `deadLetterPolicy` or `negativeAckRedeliveryDelay` is configured anywhere in swissknife. Acks are individual (`acknowledgeAsync`, `PulsarReceivedMessage.kt:28`), not cumulative.

### A1 — `ReceivedMessage.acknowledgeAsFailed` contract
- Base: `modules/messaging/domain/.../message/ReceivedMessage.kt:32` declares `suspend fun acknowledgeAsFailed()`.
- What it does: it is the generic "nack" hook. Its only production caller is pillar's `MessagingEventProcessor.kt:43`, which calls it on `EventProcessingResult.Failure` and then continues with the next message.
- Principle-2-compliant behaviour: there should be no nack in the contract. Remove `acknowledgeAsFailed` from `ReceivedMessage` and all implementations (A2, A3). The consumer that sees a failure must stop instead (A9). Principle 1 allows this cross-repo change; pillar's processor and its `MessagingEventProcessorTests.kt:58` (which asserts that a Failure ends up "acked") must be updated in the same change.
- Importance: 4. The contract is what enables nack-and-continue on a used path, through pillar into modulith-example and element-service-example.
- Confidence: 5.

### A2 — `PulsarReceivedMessage.acknowledgeAsFailed` → `negativeAcknowledge`
- Base: `modules/pulsar/messaging/adapter/.../protocol/PulsarReceivedMessage.kt:29` has `withContext(Dispatchers.VirtualThreads) { consumer.negativeAcknowledge(delegate) }`.
- What it does: Pulsar redelivers the message after `negativeAckRedeliveryDelay` (default 1 minute). Meanwhile the consumer keeps receiving and acking later messages, so the failed message is skipped and later processed out of order. That is exactly the "skip ahead" pattern principle 2 forbids.
- Principle-2-compliant behaviour: delete the override, together with A1.
- Importance: 4.
- Confidence: 5.

### A3 — `ReceivedMessageSpy` nack plumbing
- Base: `modules/messaging/test/utils/.../message/ReceivedMessageSpy.kt`:
  - line 22: constructor param `acknowledgeAsFailed`
  - lines 60-61: the override
  - lines 69, 72, 75: the `acknowledgeAsFailed = {}` parameters of `inMemorySpy` and both `asReceivedMessageSpy` overloads
- What it does: test support for the nack path.
- Principle-2-compliant behaviour: remove it, together with A1. Grep the consumer repos' tests for `acknowledgeAsFailed =` named arguments when doing so.
- Importance: 2. Test code, but it must go with A1 or nothing compiles.
- Confidence: 5.

### A4 — `processAsCompositeEvent` turns every exception into `EventProcessingResult.Failure` (includes 9.141)
- Base: `modules/messaging/domain/.../event/processing/CompositeEventProcessingUtils.kt:8` has `runCatching { action(...) }.map { Success }.getOrElse(Throwable::asProcessingFailure)`.
- What it does: it swallows every throwable, including `CancellationException` (item 9.141), and hands back a `Failure`, which pillar then nacks (A1/A2). It is used by every event handler in modulith-example (`account-event-processor` `Application.kt:40-60`) and element-service-example (three modules).
- Snapshot change (9.141): it rethrows `CancellationException` and still converts every other error to `Failure`. Under principle 2 this fixes the wrong thing: a real processing error still becomes a nack-and-continue.
- Principle-2-compliant behaviour: drop the `runCatching` entirely, so exceptions (cancellation included) propagate and stop processing:

  ```kotlin
  inline fun … processAsCompositeEvent(action: …): EventProcessingResult { action(this, value.data, value); return EventProcessingResult.Success }
  ```

  The snapshot's cancellation test would still pass. Add one test that a non-cancellation exception propagates.
- Importance: 4.
- Confidence: 5.
- Recommendation for 9.141: REDO MODIFIED. Remove the `runCatching` wrapper instead of special-casing `CancellationException`.

### A5 — `EventProcessingResult.Failure` / `asProcessingFailure`
- Base: `modules/messaging/domain/.../event/processing/EventProcessingResult.kt:7,12`.
- What it does: it is a result value that represents "failed but handled". Its existence invites the consumer to handle it and move on, which is what pillar does.
- Principle-2-compliant behaviour: with A4, swissknife no longer produces `Failure`. Either remove `Failure` and `asProcessingFailure`, so a failure can only be an exception and therefore always stops processing, or keep it with the documented rule that a consumer receiving it must stop without acking. Removal is simpler and leaves no wrong usage possible, and principle 1 allows it. Also check `EventProcessingResultTests.kt` in swissknife and pillar's processor.
- Importance: 3.
- Confidence: 4.

### A6 — `onlyWithTypeIn` acks and skips messages of other types
- Base: `modules/messaging/domain/.../event/utils/EventTypeUtils.kt:28-37` acknowledges any message whose type isn't in the set and filters it out.
- What it does: it treats "not for this processor" as successfully handled.
- Principle-2 view: compliant, if "irrelevant type" counts as success. It is not a failure being skipped. The owner should confirm. Separately, lines 32 and 34 log the same "Skipped message…" text before and after the ack; that is cosmetic, and the second line was presumably meant to say "Acknowledged".
- Importance: 2.
- Confidence: 4.

### A7 — `eventType()` `!!` on a missing type property (open item 9.115)
- Base: `EventTypeUtils.kt:17` has `properties[propertyNames.forEvents.type]!!`.
- What it does: a message without the type property throws an NPE inside the flow, which stops processing without acking.
- Principle-2 view: the current behaviour (stop, rely on redelivery) is compliant. The checklist's proposed fixes for 9.115 ("ack-and-skip" or "nack") both conflict with principle 2 and must not be applied. The only acceptable change is a descriptive error, e.g. `?: error("Message '${id}' has no '${propertyNames.forEvents.type}' property")`, instead of a bare NPE.
- Importance: 2.
- Confidence: 5.

### A8 — `produceAndAwaitSuccessor` drops non-matching messages unacked (open item 9.117)
- Base: `modules/messaging/domain/.../message/Messages.kt:49` has `values.first { it.hasType(successorType) && it.wasCausedBy(event) }.apply { acknowledge() }`. It is used in element-service-example's `CompliancePlanOutputsManagerModuleTestSpecification.kt:90,121`.
- What it does: it consumes non-matching messages without acking them. With Failover and no ackTimeout, they are only redelivered when the consumer reconnects.
- Principle-2 view: not acking is compliant. The checklist's proposed fix for 9.117 ("nack the non-matching messages") conflicts with principle 2 and must not be applied. If the owner wants this cleaner, filter by subscription or topic instead, or document that the helper consumes the stream up to the successor.
- Importance: 2. Test helper.
- Confidence: 4.

### A9 — "Stop on failure" doesn't release the consumer, so redelivery never happens while the process lives
- Base:
  - `modules/messaging/domain/.../message/consumer/MessageConsumer.kt:24-30`: the `messages` flow loops over `receive()`.
  - `ReceivedMessage.kt:48-55`: `processWithForkedContext` does `scope.launch { onEach { action }.collect() }`.
  - `PulsarMessageConsumer.kt:27`: `stop()` is the only thing that closes the consumer.
- What it does: when an action throws, the launched job fails and collection stops, but nothing closes the Pulsar consumer. Under Failover the partition stays assigned to this still-connected consumer, so unacked messages are neither redelivered to the standby consumer nor replayed until the process restarts or `stop()` is called. Pillar's processor uses `SupervisorJob`, so the failure is also isolated from the service's lifecycle.
- Principle-2-compliant behaviour: "stop processing" has to mean "release the subscription". On a processing exception, close the consumer, for example in a `finally`/`onCompletion` of the processing job, or propagate the failure so the service shuts down or fails liveness and restarts. Redelivery then happens naturally. This is a design gap rather than a one-line bug. It needs an owner decision on where the stop belongs: swissknife's processing helper or pillar's `EventProcessor`.
- Importance: 3.
- Confidence: 3. This is standard Pulsar Failover behaviour; I didn't reproduce it.

### A10 — Consumer defaults: keep them, and treat 9.104's proposal with care
- Base: `DefaultPulsarConsumerCustomization.kt:8-15` and `PulsarPartitionChangeAwareMessageConsumer.kt:18`.
- What it does: no ack timeout, no DLQ and no nack delay are configured, which is compliant: an ack timeout would cause redelivery while the consumer continues, equivalent to a nack. Failover gives one active consumer per partition, so "stop on failure" really halts that partition.
- Principle-2 view: the open item 9.104 proposes dropping the forced `Failover` so callers can choose `Shared`/`Key_Shared`. With `Shared`, other consumers keep acking later messages while a failed one sits unacked, which is effectively skipping ahead. If 9.104 is ever done, it should keep `Failover` as the default and treat `Shared` as an explicit opt-out that is incompatible with principle 2. Also, don't add `ackTimeout` or `deadLetterPolicy` defaults.
- Importance: 2. Currently compliant; this is guidance.
- Confidence: 4.

### A11 — NATS consumer has no acknowledgement semantics
- Base: `nats/client/.../NatsConsumerAdapter.kt:18-30` uses core NATS (at-most-once). Messages are emitted into a `MutableSharedFlow` with no replay, so anything that arrives while nobody is collecting is dropped.
- Principle-2 view: not applicable, because there is no redelivery to rely on. If NATS is ever used for processing that must survive failures, it would need JetStream with explicit acks. Nothing uses it today.
- Importance: 1.
- Confidence: 4.

---

## Unattributed changes

In-scope modules (messaging, pulsar, nats, avro, json, compliance-checker, logger, logging, opentelemetry, test, scripts): **none**. Every hunk of `git diff 3f1d24b bug-hunt-snapshot-2026-10-05` in these paths maps to a checklist item:

| Item | Changed files |
|---|---|
| 9.106, 9.110 | `PulsarReceivedMessage` |
| 9.108 | `PulsarContainerExtensions` |
| 9.109 | `ProtocolProperties` |
| 9.112 | `PulsarReadinessCheck` |
| 9.114 | `Topic`, `TenantAgnosticTopic` and their tests; the widened `TenantAgnosticTopic` namespace group now also accepts `.`, consistent with `Topic` |
| 9.118 | `EventMessageConverterTemplate` |
| 9.141 | `CompositeEventProcessingUtils` and its test |
| 9.121, 9.123 | NATS |
| 9.124–9.127 | Avro |
| 9.129–9.130 | JSON |
| 9.132, 9.134 | Logger |
| 9.138 | Logging |
| 9.140 | Test utils |
| 10.22 | `scripts/update-gradle.sh` |

compliance-checker and opentelemetry are unchanged.

Out of scope, noted for whoever covers the repo root: `gradle.properties` (`currentVersion` 1.0.35 → 1.0.37), `gradle/libs.versions.toml` (the `zero-allocation-hashing` removal belongs to hashing; `sollecitom-gradle-plugins` 1.0.32 → 1.0.33), `publication-state.properties` (mechanical), and `.gitignore` (splits the malformed `*.pidjava_pid*.hprof` line into `*.pid` and `java_pid*.hprof`).
