# Verification: element-service-example — http-event-bridge + compliance-plans-viewer (12.59–12.95)

Base `8c9debd` → snapshot `bug-hunt-snapshot-2026-10-05`. Read-only review. I ran no builds or tests: "test fails on base" claims below come from tracing the base code, not from running it.

Abbreviations:
- `Repo` = `content/modules/compliance-plans-viewer/adapters/driven/repository/postgres/src/main/kotlin/.../PostgresCompliancePlansRepository.kt`
- `Spec` = `.../repository/test/specification/.../CompliancePlansRepositoryTestSpecification.kt`
- `Bridge` = `content/modules/http-event-bridge/module/implementation/.../HttpEventBridge.kt`

Not covered (by design, no code change in the snapshot): 12.59 and 12.76. Both were closed under principle 3. There is nothing to redo.

---

### 12.61 — Shutdown stops the connector before the processor
- Defect in base: REAL. `Bridge:39-48` starts in the order publisher → connector → processor, but `stop()` calls `compliancePlanEvents.stop()` first, then `compliancePlanEventProcessor.stop()`. The processor is still consuming and acking through the connector at that point.
- Fix: CORRECT. It is a one-line swap to processor → connector → publisher, which matches `CompliancePlansViewer.stop()` (already correct). There is no test, and one would be impractical.
- Principles: none. Under principle 2, a failed ack only means a redelivery, so the impact is a duplicate notification at shutdown.
- Importance: 2. Robustness on shutdown (a possible duplicate lifecycle notification).
- Confidence: 4. Clear trace.
- Recommendation: REDO AS IS

### 12.62 — Cancellation becomes a failure (bridge)
- Defect in base: REAL. swissknife `processAsCompositeEvent` used `runCatching`, which swallowed `CancellationException`. There was no defect in element-service-example code itself.
- Fix: CORRECT. It is upstream only: swissknife `CompositeEventProcessingUtils.kt:9` now rethrows `CancellationException`. Nothing changed in this repo. The verdict belongs to 9.141.
- Principles: none. The fix moves toward principle 2: a cancelled message is no longer nacked, so it is redelivered.
- Importance: 2. Only matters during shutdown.
- Confidence: 4. I read the swissknife code.
- Recommendation: REDO AS IS (through 9.141; nothing to do here)

### 12.65 — `$arguments` logged before declaration
- Defect in base: REAL. In `CompliancePlanEventEndpoint.kt:25-26`, the log line comes before `val arguments = arguments(request)`, so `$arguments` resolves to the companion lens (`:33`).
- Fix: CORRECT. The two lines are swapped. Side effect: a body that fails to parse is no longer logged as "Received…". The log now contains the full event payload (see 12.89, log policy, still open).
- Principles: none.
- Importance: 1. The log content is wrong.
- Confidence: 5.
- Recommendation: REDO AS IS

### 12.68 — Notifier schema `$ref`s point at another module
- Defect in base: REAL. Base `notifier/plan/CompliancePlan.json:22,29,32,37`, `CompliancePlanEntityReference.json:6` and `subject/*.json` point to `/example/http-event-bridge/plan/...`. Those files exist only in the `driving/http/serialization/json` module, and email-notifier's `build.gradle.kts` does not depend on it.
- Fix: CORRECT. The refs are rewritten to `/notifier/plan/...` (every target exists in email-notifier). A new `CompliancePlanJsonSerdeTest` (AcmeJsonSerdeTestSpecification, so it checks schema compliance) should fail on base because the refs can't be resolved on that classpath. It follows the style rules (PER_CLASS, AssertK spec).
- Principles: none.
- Importance: 2. The schema doesn't hold up on its own; there's no runtime use today.
- Confidence: 4. The trace is clear, but I didn't run the test.
- Recommendation: REDO AS IS

### 12.69 — `Publication.edition` nullable but required in serde/schema
- Defect in base: REAL. `Publication.kt:24` `put(EDITION, null)` drops the key, `:30` `getString(EDITION)` throws, and `Publication.json` lists `edition` as required.
- Fix: CORRECT. It uses `getStringOrNull`, removes `edition` from the schema's `required`, and adds a `publication-without-edition` case. That case fails on base (deserialize throws, and the schema check fails too). The same fix was applied to the outputs-manager copies (outside this scope).
- Principles: none.
- Importance: 3. A standard without an edition can't be ingested (400), and the domain allows that.
- Confidence: 5.
- Recommendation: REDO AS IS

### 12.70 — `RequirementStandard.edition` same bug
- Defect in base: REAL. `RequirementStandard.kt:33` uses `getRequiredString(EDITION)`, and `RequirementStandard.json` requires `edition`.
- Fix: CORRECT. Same pattern as 12.69, plus a `standard-without-edition` case (the factory has an `edition: Name?` parameter).
- Principles: none.
- Importance: 3.
- Confidence: 5.
- Recommendation: REDO AS IS

### 12.74 — Module spec: `first {}` without timeout; consumers not closed
- Defect in base: PARTLY. The leak is REAL and worse than reported: every `pulsar.client()` call builds a new `PulsarClient` (swissknife `PulsarContainerExtensions.kt:39`), giving 2 per test, and none is ever closed. The "no timeout" half is NOT REAL: `testWithInvocationContext` defaults to `timeout = 10.seconds`.
- Fix: CORRECT. Each test runs inside a single `pulsar.client().use { client -> ... }`, so closing the client closes the consumers. The diff looks large only because of re-indentation; the assertions are unchanged.
- Principles: none.
- Importance: 2. Test hygiene.
- Confidence: 4.
- Recommendation: REDO AS IS

### 12.75 — SQL injection via continuation token / customer id / states
- Defect in base: REAL (critical for the token).
  - `Repo:48`: `AND pk > ${it.value}` pastes the client token into the SQL, so `"0 OR 1=1"` returns every customer's rows.
  - `Repo:44,48`: `customer_id = '$customerId'` is interpolated. Under principle 3 the customer comes from the trusted gateway, so this is mainly a correctness bug (a quote in an id), not an attack vector.
  - States are enum-derived and can't be injected.
- Fix: CORRECT.
  - The customer id and states are bound through Spring `DatabaseClient` named parameters. `Array<Int>` → `int4[]` with `= ANY(:STATE_ORDERS)`; Spring expands only `Collection`s, so the array is passed as one parameter.
  - The token is parsed (now `PagePosition`, see 12.78), so anything non-numeric throws `IllegalArgumentException` before any SQL runs.
  - `LIMIT` is still interpolated, but it's an `Int`, so it's safe.
  - Both new Testcontainers tests fail on base: the customer `attacker' OR '1'='1` returns the victim's plan, and the token `0 OR 1=1` raises nothing.
  - Concern: a bad token gives a generic 500, not the 400 the finding suggested. That's acceptable; see 12.79.
- Principles: none. A null customer now binds as SQL NULL via swissknife `bindValueOrNull`, which returns an empty page (see 12.83).
- Importance: 5. Cross-tenant read on a public endpoint.
- Confidence: 5. Clear SQL trace, and the tests target exactly this.
- Recommendation: REDO AS IS. Redo it together with 12.78, since it's the same function and the interactive change was built on top of it.

### 12.78 — In-memory sort after `LIMIT` duplicates rows across pages
- Defect in base: REAL. `Repo:49-57` does `ORDER BY pk LIMIT n`, then `.sortBy(sortOrder)` in memory. `:62` uses the token `records.last().primaryKey` *after* that sort, so the next `pk > token` page serves rows again or skips them. The old spec only checked ordering within a page.
- Fix: CORRECT, with test and edge caveats.
  - SQL:
    - unsorted: `ORDER BY pk ASC` with `pk > :PRIMARY_KEY`
    - ASC: `ORDER BY state_order ASC, pk ASC` with `(state_order, pk) > (:STATE_ORDER, :PRIMARY_KEY)`
    - DESC: `ORDER BY state_order DESC, pk DESC` with `(state_order, pk) < (...)`
    - The row comparisons are right for both directions, and the bindings match the placeholders for each branch.
  - Next page: it fetches `limit + 1` rows, then `take(limit)`. The token comes from the last row of the page, only when `records.size > limit`. That's correct, and it also removes the base `limit: 0` crash (`records.last()` on an empty list).
  - Token: `PagePosition` `"stateOrder:pk"`, parsed strictly (exactly 2 parts, int and long).
  - Migration `1_6_0`:
    - adds `state_order`, backfills it with a `CASE` (mapping matches `toDbStateOrder`), then sets it `NOT NULL`
    - drops `customer_id_state_type_index`; `state_type` is no longer read anywhere (checked)
    - adds `(customer_id, state_order, pk)`, which serves ASC and DESC through a backward scan, and `(customer_id, pk)` for unsorted
  - The upsert writes `state_order` (`$8`) and updates it on conflict.
  - The new spec test pages through 6 mixed-state plans in ASC, DESC and unsorted order and asserts the exact sequence. It fails on base by trace.
- Concerns:
  1. The test never puts a page boundary inside a group of equal states. With `pageSize = 2` and exactly 2 plans per state (SP, SP, SR, SR, RR, ARR), every boundary falls where the state changes. A wrong condition `state_order > :STATE_ORDER` (no pk tiebreak) would still pass. Use `pageSize = 3`, or an odd number of plans in one state.
  2. `LIMIT ${pagination.limit + 1}` overflows when `limit == Int.MAX_VALUE`, producing a negative LIMIT and a 500. Base accepted that value. Use `pagination.limit.toLong() + 1`.
  3. `state_type` is now written but never read, so the state is duplicated in `state_type`, `state_order` and `state_payload.type`. Optional: drop `state_type` (principle 1 allows it).
  4. The `api.yaml:44` example token is a ULID. It was stale before and is still stale; docs only.
  5. The count and the page are still two separate, non-transactional queries (the second half of 12.82).
- Principles: none. Principle 1 covers the token format change and the migration.
- Importance: 4. Sorting plus pagination returns duplicated or missing plans: wrong behaviour on a documented API feature.
- Confidence: 5.
- Recommendation: REDO MODIFIED. Keep the design as is. Change the paging test so one boundary falls inside a state group (`pageSize = 3`). Compute the limit as `pagination.limit.toLong() + 1`. Optionally drop the `state_type` column.

### 12.80 — Empty `selected-states` → `IN ()` SQL error
- Defect in base: REAL. `Repo:43,44,48`: an empty set joins to `state_type IN ()`, a syntax error and a 500. The schema has no `minItems`.
- Fix: CORRECT. It falls out of the `= ANY(:STATE_ORDERS)` binding: an empty array matches nothing and gives an empty page with count 0. The spec test `retrieving plans with an empty selection of states` fails on base.
- Principles: none.
- Importance: 3. A 500 on input the schema accepts.
- Confidence: 5.
- Recommendation: REDO AS IS (comes with 12.75)

### 12.81 — Upsert never updates device fields
- Defect in base: REAL. `Repo:115`: `DO UPDATE SET` doesn't include `device_id` or `device`.
- Fix: CORRECT. Both are added to the `SET`. The test `upserting a plan whose device changed` fails on base.
- Principles: none.
- Importance: 3. The view keeps serving an old device name.
- Confidence: 5.
- Recommendation: REDO AS IS

### 12.82 — Extra empty page; count and page from different queries
- Defect in base: REAL. `Repo:59-62`: when exactly `limit` rows are left, base still returns a token, and the following page is empty.
- Fix: CORRECT for the empty page (it's the `limit + 1` fetch from 12.78). The count/page consistency half is not addressed, which is fine as minimal behaviour. No test pins the exact-boundary case: the new paging test would also pass with a trailing empty page, because the empty page adds no items.
- Principles: none.
- Importance: 2.
- Confidence: 5.
- Recommendation: REDO AS IS. Optionally add a test with remaining == limit that asserts `hasNoNextPage()`.

### 12.83 — Null customer becomes `'null'` (open, partly addressed)
- Defect in base: REAL. `Repo:42,44`: `'$customerId'` with a null value becomes the literal `'null'`.
- Fix: PARTLY. As a by-product of 12.75, it now binds SQL NULL, so the visible behaviour is unchanged (an empty 200) but there's no literal. The 403 decision is still open.
- Principles: under principle 3, a context with no customer comes from the trusted gateway (for example a non-customer actor). Choosing between an empty page and a 403 is product policy.
- Importance: 1.
- Confidence: 5.
- Recommendation: REDO AS IS (comes with 12.75); the 403 decision stays open.

### 12.84 — `upsertAll(emptyList())` throws
- Defect in base: REAL. `Repo:101-110` executes a statement with placeholders and no bindings, which r2dbc-postgresql rejects. Only tests call `upsertAll`; the interface default (`forEach upsert`) already handles an empty list.
- Fix: CORRECT. `if (plans.isEmpty()) return@withConnection`, plus a spec test.
- Principles: none.
- Importance: 2. A contract method crashes on an edge input; there's no production caller.
- Confidence: 4. The r2dbc behaviour is known but I didn't run it.
- Recommendation: REDO AS IS

### 12.85 — `DocumentModule` writes the wrong format fields
- Defect in base: REAL. `DocumentModule.kt:30-32` writes `value.name.value` into all three format fields, so reading it back throws. `:77` prints the deserializer object.
- Fix: CORRECT. The fields and the error message are fixed. The round-trip test fails on base (`format_extension = "report"` throws). `InMemoryDocument` has a content-based `equals`, so the assertion is valid.
- Principles: none.
- Importance: 1. Dead code: nothing persists a `Document` through `dbObjectMapper`.
- Confidence: 5.
- Recommendation: REDO AS IS. It's cheap; deleting `DocumentModule` would also be valid.

### 12.86 — `ApplicableRequirementsReady.type` is `REQUIREMENTS_READY`
- Defect in base: REAL. `CompliancePlanState.kt:49`. In practice it's latent: `ApplicationImplementation` only ever builds `StandardsReady` and `RequirementsReady`, and `ApplicableRequirementsOutputsAvailable` maps to NoOp (12.87, open). No production path stores this state today.
- Fix: CORRECT. A one-word change. The spec test `retrieving plans selected by applicable requirements ready state` fails on base: the plan would get `state_order = 2` (or `state_type = 'requirements_ready'` in base) and not be selected. The HTTP serde dispatches on class, so it's unaffected.
- Principles: none. The checklist line "existing rows would need a backfill" doesn't apply under principle 1. Drop it.
- Importance: 3. Latent; it only matters once 12.87 is implemented.
- Confidence: 5.
- Recommendation: REDO AS IS

### 12.88 — Cancellation becomes a nack (viewer)
- Defect in base: REAL. It's in the shared swissknife API (same root cause as 12.62). In base, it turned an in-flight upsert into `Failure`, and the pillar processor then called `acknowledgeAsFailed()`, which is a nack.
- Fix: CORRECT. Upstream only (9.141); nothing changed in this repo.
- Principles: none. The fix removes a nack and so moves toward principle 2.
- Importance: 2.
- Confidence: 4.
- Recommendation: REDO AS IS (through 9.141)

### 12.91 — Repository spec state assertions can't fail
- Defect in base: REAL. `AssertionUtils.kt:16,23`: `assertk.assertThat(plan.state.type >= x)` creates an assertion on a Boolean and never checks it.
- Fix: CORRECT. It now calls `assertThat(plan.state.type).isGreaterThanOrEqualTo(...)` and `isLessThanOrEqualTo(...)`, using `Assert.assertThat` inside `given`. The existing filter tests still pass even with 12.86 unfixed, because `GreaterThan(STANDARDS_READY)` and `LessThan(STANDARDS_READY)` aren't affected by that bug. Nit: the DESCENDING branch of `areSortedByStateWithDirection` still uses a qualified `assertk.assertThat`. That's pre-existing and harmless.
- Principles: none.
- Importance: 3. Before the fix, these tests could never fail.
- Confidence: 5.
- Recommendation: REDO AS IS

### 12.92 — Event processing tests exercise a stub
- Defect in base: REAL. In `CompliancePlanEventProcessingTests.kt:53-58,90-94`, the "application" is a lambda, so the real projection is never run.
- Fix: CORRECT. It now uses `Application.create(reader = UnusedReader, writer = RecordingWriter())`. Fixed ids and device make the expectations literal, and the test asserts the exact projected viewer plans: `isRequirementsAnalysisAvailable` / `isApplicable…` come from the entitlements, and `reachedAt` is the event timestamp. Switching `MessagePropertyNames by AcmeMessagePropertyNames` to `by Example, WithDefaultLocale by Example` is needed because `Application.create(reader, writer)` takes both as context parameters. It's incidental, not unrelated.
- Principles: CONFLICT (inherited). The failure test still asserts `wasAcknowledgedAsFailed()`, i.e. a nack, through pillar's `processAndWaitUntilAllAcked`. That locks in nack-on-failure, which principle 2 forbids. Once the processor stops on failure, the helper would hang.
- Importance: 3. Before the fix, the projection had no test at all.
- Confidence: 5.
- Recommendation: REDO MODIFIED. Keep the success test as is. Rewrite the failure test to call `application.processCompliancePlanEvent(message)` directly and assert it returns `EventProcessingResult.Failure`. That is the application's contract; ack policy belongs in pillar's processor tests.

### 12.93 — Viewer application tests filter inside the stub
- Defect in base: REAL. `CompliancePlansViewerApplicationTests.kt`: `StubbedReader` filtered by `selector.states`, and the test filtered `result.page.items` again before comparing.
- Fix: CORRECT. The stub returns the page unchanged and records the arguments. The tests assert `result.page == stubbedPage` and the exact `GetCompliancePlans.Arguments`, which is a data class, as are its parts.
- Principles: none.
- Importance: 3.
- Confidence: 5.
- Recommendation: REDO AS IS

### 12.94 — Contract stub ignores arguments
- Defect in base: REAL. In `GetCompliancePlansQueryEndpointHttpTestSpecification.kt:60`, the stub was `{ _ -> page }`.
- Fix: CORRECT. The stub captures the arguments, and the test asserts `containsExactly(GetCompliancePlans.Arguments(selector, sortOrder, pagination))`, all data classes. A serde that drops or swaps a selector or the order would now fail.
- Principles: none.
- Importance: 3. Before the fix, argument deserialization was never checked end to end.
- Confidence: 5.
- Recommendation: REDO AS IS

### 12.95 — Sorted pagination test doesn't check pages are disjoint
- Defect in base: REAL. The `Spec` "pagination, filters, and sort order" test only checked filtering and ordering within each page.
- Fix: INCOMPLETE. It's covered by the 12.78 test (exact sequence over all pages, every plan once), but as noted in 12.78, no boundary falls inside a group of equal states, so the pk tiebreak isn't tested.
- Principles: none.
- Importance: 3.
- Confidence: 5.
- Recommendation: REDO MODIFIED. Same change as 12.78: `pageSize = 3`, or an odd number of plans in one state.

---

## 12.77 under principle 2

Conclusion: the reported mechanism (a nack, the processor keeps going, the older event is redelivered after a newer one) only exists because the current pillar processor breaks principle 2. Fix that processor and consumer-side reordering mostly disappears. Out-of-order or duplicate *older* events can still reach the upsert by two remaining routes, so 12.77 stays a real but lower-priority finding. The "ordering guard" should be a domain decision, not a reaction to nacks.

Evidence:
- Today's processor (pillar `MessagingEventProcessor.kt`) calls `message.acknowledgeAsFailed()` on `Failure`, which is `consumer.negativeAcknowledge` (swissknife `PulsarReceivedMessage.kt:29`), and then **continues** with the next message. This was the same before and after the session. So in today's code the 12.77 scenario is real: StandardsOutputsAvailable fails and is nacked, RequirementsOutputsAvailable is applied, then StandardsOutputsAvailable comes back and regresses the plan. This is the part that conflicts with principle 2. The fix belongs in the pillar processor (on failure: stop, no ack, no nack), not in the repository.
- Under principle 2, the consumer side is order-preserving per plan:
  - the subscription type is `Failover` (swissknife `defaultConsumerCustomization`), so there's one active consumer per partition
  - the message key is the plan id (`CompliancePlanEventMessageConverter.key`), so a plan always lands on the same partition
  - processing is sequential (`processWithForkedContext` → `onEach{}.collect()`)
  - when processing stops on a failure, Pulsar redelivers from the first unacked message, in order
- Remaining ways an older event can still be applied after a newer one:
  1. **Upstream order and duplicates.** Order on the topic is the order of HTTP ingestion. The bridge has no idempotency (12.63), so a client that retries a timed-out `standards-analysis-completed` after posting `requirements-analysis-completed` publishes the older event again. The outputs manager then emits StandardsOutputsAvailable *after* RequirementsOutputsAvailable, and the viewer regresses. Concurrent POSTs for the same plan behave the same way. Nothing in the messaging layer can prevent this.
  2. **Ack holes.** Pulsar acks are fire-and-forget by default: they're grouped and there's no ack receipt. If M1's ack is lost when a connection drops but M2 is acked afterwards, M1 is redelivered after M2 on reconnect or failover. This is rare.
- Cost of a guard now: with the new `state_order` column, a monotonic guard is one clause: `ON CONFLICT ... DO UPDATE SET ... WHERE Compliance_Plan.state_order <= EXCLUDED.state_order`. This is right only if plan state is monotonic in the domain, meaning a re-analysis never legitimately moves a plan back to StandardsReady. That's an owner decision.
- Side note: the redone 12.92 success test expects StandardsReady after RequirementsReady for the same plan *at the writer*. That's correct for the application layer. A repository guard wouldn't change it.

Score for 12.77 as reframed:
- Importance: 3. Latent once the processor follows principle 2; reachable through client retries or concurrent posts.
- Confidence: 4 for the reasoning about mechanisms; 3 for the ack-hole route.
- Recommendation: keep it open. First make the pillar processor follow principle 2 (outside this scope). Then decide whether states are monotonic; if they are, add the one-line `WHERE` guard and a spec test that upserts RequirementsReady then StandardsReady and expects RequirementsReady.

## Unattributed changes

Within http-event-bridge, compliance-plans-viewer and the viewer's migration, every change in base..snapshot maps to an item above. The only incidental change is the `MessagePropertyNames by Example, WithDefaultLocale by Example` switch in `CompliancePlanEventProcessingTests` (needed for 12.92).

Other changes in `content/migrator`, attributed to items outside this scope:
- `postgres/starter/build.gradle.kts` (removes `-XX:+ZGenerational`, `UnlockExperimentalVMOptions` and the egd arg; `HeapDumpPath` now points to a directory) → 12.1 and 12.8
- changelog include plus a new `1_5_0_create_sorted_index_on_compliance_plan_output_standards_table.sql` → 12.15
- `postgres/domain/src/main/kotlin/Serialization.kt` (`writeRaw` → `writeRawValue`) → 12.22

## Summary

22 items checked (12.59 and 12.76 are by design, with no code change):
- REDO AS IS: 19 (12.61, 12.62, 12.65, 12.68, 12.69, 12.70, 12.74, 12.75, 12.80, 12.81, 12.82, 12.83 (by-product of 12.75), 12.84, 12.85, 12.86, 12.88, 12.91, 12.93, 12.94)
- REDO MODIFIED: 3 (12.78, 12.92, 12.95)
- DROP: 0
- 12.77: keep open, reframed as described above.
