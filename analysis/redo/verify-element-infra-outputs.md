# Verification: element-service-example (infra, shared, service, migrator, chart, docs, compliance-plan-outputs-manager)

Refs: base `8c9debd`, snapshot `bug-hunt-snapshot-2026-10-05` (`057a915`, commits `9681c43` and `057a915`). Out of scope: `content/modules/http-event-bridge`, `content/modules/compliance-plans-viewer`, and the owner's `.trivyignore` change.

Method: read the base code with `git show 8c9debd:<path>` and the snapshot diff, traced into swissknife (`selectPage`, `WithSqlConnectivity.inTransaction` / `withConnection`, the messaging test utils) and ran the migrator JVM flags on local Temurin 26.0.1. I didn't run any builds. Aggregated Gradle test results at `element-service-example/build/test-results/test/` (timestamp 2026-10-05T13:45Z, after the snapshot commits) show these suites green: `PostgresCompliancePlanOutputsRepositoryTests` 24/24, which includes every new repository test; application tests (CSV ×2, event processing 2, ApplicationTests 6); the contract tests, including the new entitlement cases; `ProcessBasedServiceTests` 17/17; and the shared Avro suites. Container-based tests last ran on 2026-10-03, so nothing tested the 12.25/12.26 changes.

---

### 12.1 — Migrator `-XX:+ZGenerational` fatal on JDK 26
- Defect in base: REAL. `content/migrator/postgres/starter/build.gradle.kts:37,42` passes `-XX:+UnlockExperimentalVMOptions` and `-XX:+ZGenerational`. The base image is `eclipse-temurin:26-jre-noble` (`gradle.properties:19`). On Temurin 26.0.1 I got `Unrecognized VM option 'ZGenerational'` / `Could not create the Java Virtual Machine`. The remaining snapshot flags (`UseZGC`, `AlwaysPreTouch`, `UseNUMA`, `HeapDumpPath=/tmp`, `MaxRAMPercentage`) start fine.
- Fix: CORRECT. Removes both flags and nothing else. The service image already used plain `-XX:+UseZGC`, so the two images now match.
- Principles: none
- Importance: 5. The init container can't start, so no pod ever comes up. Caveat: only the Helm chart uses the migrator image, and no recipe deploys the chart.
- Confidence: 5. Reproduced locally.
- Recommendation: REDO AS IS

### 12.2 — Helm `{ { … } }` renders a map
- Defect in base: REAL. `content/chart/templates/deployment.yaml:63` is `value: { { .Values.log.format | default "json" } }`. With the spaces, Go templates don't see an action, so YAML gets a flow mapping where the env value should be a string. The Deployment is invalid.
- Fix: CORRECT. `value: {{ .Values.log.format | default "json" | quote }}`.
- Principles: none
- Importance: 5. `helm install` fails. Same caveat as 12.1: nothing renders or deploys the chart.
- Confidence: 4. Follows from YAML/Go template semantics; no `helm` on this machine to render it.
- Recommendation: REDO AS IS

### 12.6 — Dead env var `MODULES_HTTP_EVENT_BRIDGE_USER_SERVICE_ADDRESS`
- Defect in base: REAL. `deployment.yaml:60-61`. Grepping base for `USER_SERVICE_ADDRESS|userServiceAddress` finds only the chart.
- Fix: CORRECT. Two lines removed.
- Principles: none
- Importance: 1. Dead config.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.7 — Probe ports hard-coded to 8081
- Defect in base: REAL. `values.yaml:93,102` say `port: 8081`, while `HEALTH_PORT` comes from `.Values.service.healthPort` (`deployment.yaml:55`, value 8081 at `values.yaml:61`). Changing `healthPort` silently breaks the probes.
- Fix: CORRECT. Adds a container port named `health` (`containerPort: {{ .Values.service.healthPort }}`) and points both probes at `port: health`. Named httpGet ports are valid in Kubernetes, and `health` fits the 15-character name limit.
- Principles: none
- Importance: 2
- Confidence: 5
- Recommendation: REDO AS IS

### 12.8 — Migrator egd as program arg; `HeapDumpPath` literal `<pid>`
- Defect in base: REAL. `build.gradle.kts:33-35` passes `-Djava.security.egd=...` through `args`, which the starter's `main` receives and ignores. `:39` sets `HeapDumpPath=$tmpVolume/java_pid<pid>.hprof`, and HotSpot doesn't expand `<pid>`.
- Fix: CORRECT. The finding suggested moving egd to `jvmFlags`; the fix drops it instead. That matches the service image, which has no egd, and it's irrelevant on modern JDKs. `HeapDumpPath=/tmp` (a directory) makes HotSpot write `java_pid<real pid>.hprof` there, which also matches the service image.
- Principles: none
- Importance: 1
- Confidence: 5
- Recommendation: REDO AS IS

### 12.15 — No index on `Compliance_Plan_Output_Standards`
- Defect in base: REAL. `1_3_1_recreate_compliance_plan_reports_table.sql` creates the table without an index. Delete and paging filter on `(customer_id, compliance_plan_id)` and order by `pk`. The requirements table already has the equivalent `cp_out_req_*` indexes.
- Fix: CORRECT. New changeset `1_5_0_create_sorted_index_on_compliance_plan_output_standards_table.sql` adds `CREATE INDEX IF NOT EXISTS cp_out_std_sorted_idx ON Compliance_Plan_Output_Standards (customer_id, compliance_plan_id, pk ASC)`, plus a changelog include. The style matches `1_4_1`.
- Principles: none. Principle 1 would also allow putting the index straight into `1_3_1`; either way works.
- Importance: 2. Performance only.
- Confidence: 5
- Recommendation: REDO AS IS. Optionally fold the statement into `1_3_1` instead of adding a changeset, since editing applied changesets is allowed.

### 12.19 — `Submission.shortName` is null
- Defect in base: REAL. `Standard.kt:92` has `override val shortName = null`, while the companion defines `"510(k)"`. Nothing reads `shortName` (grep finds no readers).
- Fix: CORRECT. `override val shortName: Name get() = Companion.shortName`, the same pattern as `EssentialPrinciple` / `NotifiedBodyOperationsGroup`.
- Principles: none
- Importance: 1. Dead today.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.21 — `OrganizationAvroSchemas` / `DeviceAvroSchemas` `.all` wrong
- Defect in base: REAL. `OrganizationAvroSchemas.kt:12` lists `standardsDevelopingOrganizationCode` twice and omits `standardsDevelopingOrganization`. `DeviceAvroSchemas.kt:14` omits `wholeDeviceCode`.
- Fix: CORRECT. Each schema is now listed once.
- Principles: none
- Importance: 1. Catalogue completeness; no runtime path found that depends on it.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.22 — Migrator `writeRaw` bypasses Jackson bookkeeping
- Defect in base: REAL (latent). `content/migrator/postgres/domain/src/main/kotlin/Serialization.kt:11` calls `writeRaw(...)`. That works only at the JSON root; nested use would emit invalid JSON.
- Fix: CORRECT. Changed to `writeRawValue(...)`, a one-word change.
- Principles: none
- Importance: 2. Latent.
- Confidence: 4
- Recommendation: REDO AS IS

### 12.23 — Test factories use `Random.Default`
- Defect in base: REAL. `StandardTestFactory.kt:36` and `standard/StandardTestFactories.kt:33` call `setOf(...).random()`. The injected generator can be reproduced through the `randomSeed` environment key (swissknife `CoreDataGeneratorProvider`); `Random.Default` can't.
- Fix: INCOMPLETE but correct. Both now call `.random(random.random)`. Other unseeded calls remain in the same module's tests: `ApplicationTests.kt:81,98,127,140` and `ConfirmRequirementApplicabilityEndpointHttpTestSpecification.kt:60,117` (`setOf(true, false, null).random()`).
- Principles: none
- Importance: 1
- Confidence: 5
- Recommendation: REDO MODIFIED: apply the same `.random(random.random)` to the remaining unseeded calls listed above, or keep the two-file change as is.

### 12.24 — `EntitlementAvroSerdeTests` missing a case
- Defect in base: REAL. `EntitlementAvroSerdeTests.kt:16-17` covers only `Standards` and `Requirements`.
- Fix: CORRECT. Adds `"applicable-requirements-access" to CompliancePlan.Entitlement.ApplicableRequirements`.
- Principles: none
- Importance: 1
- Confidence: 5
- Recommendation: REDO AS IS

### 12.25 — Container test registry auth discarded
- Defect in base: REAL. `ElementExampleContainer.kt:67-72`: `withRegistryAuthentication` calls `RegistryAuthLocator.lookupAuthConfig(...)`, throws the result away and returns `this`. `CI_REGISTRY_USER` / `CI_REGISTRY_PASSWORD` were never applied.
- Fix: CORRECT. Deletes the no-op helper, `registryCredentials()` and the unused imports. Registry auth still works through the Docker config, as before.
- Principles: none
- Importance: 1. Dead code that pretended to configure auth.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.26 — Container Postgres URL has no database name
- Defect in base: REAL. `ElementExampleContainer.kt:38` builds `postgres://alias:5432` with no database. It works only because Testcontainers' default user and database are both `test`.
- Fix: CORRECT. Appends `/${postgres.databaseName}`.
- Principles: none
- Importance: 1
- Confidence: 4. Not re-run: container tests last ran on 2026-10-03.
- Recommendation: REDO AS IS

### 12.27 — `ProcessBasedServiceTests.afterAll` never stops the service
- Defect in base: REAL. `ProcessBasedServiceTests.kt:72-73`: `afterAll() = specificationAfterAll()` stops Pulsar and Postgres but never the `Service`.
- Fix: CORRECT. Calls `service.stopBlocking()` first, then `specificationAfterAll()`. The 17/17 suite passes on the snapshot.
- Principles: none
- Importance: 2
- Confidence: 5
- Recommendation: REDO AS IS

### 12.28 — README `PULSAR_BROKER_URI`
- Defect in base: REAL. `README.md:81` documents `PULSAR_BROKER_URI`; the key is `pulsar.broker.url` (`ServiceProperties.kt`), i.e. `PULSAR_BROKER_URL`. The chart uses `PULSAR_BROKER_URL`.
- Fix: CORRECT. One-word change.
- Principles: none
- Importance: 2. Following the README gives a missing-required-key startup failure.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.29 — README ports "optional"; wrong OCI registry default
- Defect in base: REAL. `README.md:10-11,17-18` call the ports optional. swissknife `PortLensExtensions.kt:11,16` defines both as `requiredWithSameMetaAs(...)`, and the yml defaults are never loaded (12.14). `README.md:44` says `ghcr.io/sollecitom`, but the code has `DEFAULT_IMAGE_REGISTRY = "ghcr.io"` and `DEFAULT_PROJECT_PATH = "sollecitom"`.
- Fix: CORRECT. Ports become "Mandatory", with "when set to `0`, random port". `OCI_IMAGE_REGISTRY` defaults to `ghcr.io` and the new `OCI_PROJECT_PATH` entry defaults to `sollecitom`.
- Principles: none
- Importance: 2. If 12.14 ends up loading the yml defaults, revisit "Mandatory".
- Confidence: 5
- Recommendation: REDO AS IS

### 12.30 — IMPROVEMENTS stale
- Defect in base: REAL. Base claims Gradle 9.4.0, but the wrapper is `gradle-9.8.0-all.zip`. It claims 39 modules, but `settings.gradle.kts` has 58 `content(...)` lines. It claims "SNAPSHOT dependencies throughout", but `libs.versions.toml` has no SNAPSHOT.
- Fix: CORRECT. Changes 9.8.0 and 58 (twice) and deletes the SNAPSHOT bullet.
- Principles: none
- Importance: 1
- Confidence: 5
- Recommendation: REDO AS IS

### 12.32 — SQL injection via `origin.standard` / `origin.clause`
- Defect in base: REAL. `RequirementsOperations.kt:148-149` builds `AND STANDARD = '${origins.standard.value}' AND CLAUSE = '${origins.clause.value}'`, and `:113` feeds that string to `selectPage`. swissknife `selectPage` runs it in both the COUNT query and the single-line page query. A payload like `x' OR 1=1 --` comments out the keyset, `ORDER BY` and `LIMIT` and returns every row. An apostrophe in a real standard name gives a syntax error (500).
- Fix: CORRECT and minimal. The clause becomes `AND STANDARD = :STANDARD_FILTER [AND CLAUSE = :CLAUSE_FILTER]`. A new private `whereBindings()` produces the matching pairs, appended to the `selectPage` bindings, so both queries get them. The parameter names don't collide with `RequirementsFilter`'s keyset bindings (`:STANDARD`, `:CLAUSE`, `:PK`). The verification-method `IN (...)` interpolation remains, but its values come from a closed enum (`sqlName`), so it's safe. No behaviour change beyond binding.
- New test `fetch the requirements with a standard and clause containing SQL syntax`: the apostrophe lookup returns exactly the match, and the injection returns nothing. On base it would fail on both counts (syntax error, and all rows). Green on the snapshot.
- Principles: none. Principle 3 (trusted gateway context) doesn't cover request-body filter values.
- Importance: 5. An authenticated caller can read other customers' data.
- Confidence: 5. Clear trace plus a test that passes now and would fail on base.
- Recommendation: REDO AS IS

### 12.33 — Null `edition` stored but unreadable
- Defect in base: REAL. The DB serdes write with `put(EDITION, value.edition?.value)`, which drops the key when null. They read with `getRequiredString` (`serde/requirement/RequirementStandard.kt:33`) and `getString` (`serde/standard/publication/PublicationJsonSerde.kt:30`), which throw. The HTTP serdes have the same pair. Null editions are reachable: the Avro serdes read `edition` with `getStringOrNull`.
- Fix: CORRECT. Four reads change to `getStringOrNull(...)?.let(::Name)` (DB ×2, HTTP ×2), and `edition` is removed from `required` in four schemas (DB `RequirementStandard.json` and `Publication.json`, HTTP `RequirementStandard.json` and `Publication.json`). `PublicationTestFactories` now takes `edition: Name?` so tests can build null editions.
- Tests: a repository round-trip without an edition, plus `success-without-edition` cases in the two list `ResultJsonSerializationTests`. All fail on base and are green on the snapshot.
- Side note: the DB `Publication.json` edit has no effect. The DB `PublicationJsonSerde.SCHEMA_LOCATION` points at `compliance-plan-outputs-manager/db/standard/testing/Publication.json`, which doesn't exist (see Observations). It's harmless and keeps the schema consistent.
- Principles: none
- Importance: 4. Any plan with a null edition returns 500 on lists and reports.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.35 — Empty set: unbound insert after committed delete
- Defect in base: REAL. `StandardsOperations.kt:72-90` and `RequirementsOperations.kt:86-108` always build and execute the INSERT. With an empty set nothing is bound and r2dbc throws, after the DELETE has already been auto-committed. Under principle 2 the message is never acked and consumption stops behind it.
- Fix: CORRECT. `if (… .isEmpty()) return@withConnection` right after the delete, inside the transaction from 12.36. An empty set therefore means "replace with nothing", which is the right meaning.
- Test: `replacing the standards and requirements with empty sets` would fail on base and is green on the snapshot.
- Principles: none (consistent with 2)
- Importance: 4. A plan with zero standards or requirements blocks the subscription.
- Confidence: 4. The base failure is inferred from r2dbc behaviour; the test passing now confirms the fix.
- Recommendation: REDO AS IS (together with 12.36)

### 12.36 — Delete + insert not in a transaction
- Defect in base: REAL. Both store methods were `= withConnection { … }` with no transaction, even though the class implements `WithSqlConnectivity.Transactional` (it has `transactionManager`).
- Fix: CORRECT. Each body is wrapped in `inTransaction { withConnection { … } }`. `inTransaction` is `TransactionalOperator.executeAndAwait`, and `withConnection` is `DatabaseClient.inConnection{ mono{} }.awaitSingle()`. The Reactor context carries the transaction into `inConnection`, so the delete and the inserts share the transactional connection. The test proves it.
- Behaviour beyond the finding: only that readers now see the old rows until commit instead of an empty gap. That's the intended effect. The return type stays `Unit`, and the expression body became a block only to hold the wrapper.
- Test `failing to replace the requirements keeps the previous ones` uses a 101-character clause against `VARCHAR(100)`. On base the delete commits and the test fails; on the snapshot it passes. Minor: this puts a Postgres column width into a supposedly generic repository spec, but the spec has only the Postgres implementation.
- Principles: none
- Importance: 3. A partial failure leaves a plan with no outputs; under principle 2 redelivery eventually repairs it.
- Confidence: 5. The test is green and the trace is clear.
- Recommendation: REDO AS IS

### 12.39 — Remote `FileContent` reads `LENGTH` that is never written
- Defect in base: REAL (latent). `FileContentModule.kt:35-43`: the remote branch never writes `length`, and `:58` reads `node.get(LENGTH).intValue()`, which throws a NullPointerException. Only inline reports are produced today.
- Fix: CORRECT. One line, `writeNumberField(Fields.LENGTH, value.length)`. The round-trip test `storing and retrieving a remote standards report` fails on base and is green now.
- Principles: none
- Importance: 2. Latent.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.40 — Confirm-applicability serde lacks `MissingCompliancePlanEntitlement`
- Defect in base: REAL. `ApplicationImplementation.kt:97` returns `MissingCompliancePlanEntitlement`. `confirm_requirement_applicability/serde/ApplicationResultJsonSerde.kt` handles only `Successful` and `ConditionalRequirementNotFound`, and everything else hits `else -> error(...)` (500). `Result.json` has no such variant either.
- Fix: CORRECT. Adds a serialize branch, a deserialize branch, the `missing-compliance-plan-entitlement` constant (same literal as the existing list and report serdes) and a `$ref` in `Result.json` to the existing `MissingCompliancePlanEntitlementError.json`. Serde and contract cases were added.
- Principles: none
- Importance: 4. Confirming without the entitlement returns 500 instead of the domain error.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.41 — List `Result.json` omits the entitlement error
- Defect in base: REAL. The `get_requirements_list` and `get_standards_list` `Result.json` `oneOf`s lack the entitlement variant, which their `ResultJsonSerde`s (`:40,46,57`) do emit.
- Fix: CORRECT. Adds the `$ref` to both. The new contract cases (`compliesWithOpenApiForRequest`) would fail on base.
- Principles: none
- Importance: 3. Breaks the published contract.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.42 — `selector` required by the serde, optional in the schema
- Defect in base: REAL. `get_requirements_list/Arguments.json` requires only `compliance-plan-id` and `pagination`, but `ArgumentsJsonSerde.kt:31` reads `selector` with `getValue`. `Arguments` already defaults `selector = ALL`.
- Fix: CORRECT. `getValueOrNull(...) ?: RequirementsOutputSelector.ALL`. The test removes `selector` and asserts `ALL`; it would fail on base.
- Principles: none
- Importance: 3. A schema-valid request gets a 400.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.43 — Origin `type` required by the serde, not the schema
- Defect in base: REAL. `get_requirements_list/Standard.json` requires only `standard`, and `StandardAndClause.json` only `standard` and `clause`. The serde requires `type`.
- Fix: CORRECT. Adds `"type"` to both `required` lists. It also makes the `oneOf` discriminate properly.
- Principles: none
- Importance: 2
- Confidence: 5
- Recommendation: REDO AS IS

### 12.44 — `$arguments` logged before declaration
- Defect in base: REAL. In the five endpoints the `logger.info { "... $arguments" }` line comes before `val arguments = arguments(request)`, so it logs the companion's lens.
- Fix: CORRECT. The log line moves after the parse, in all five; nothing else changes.
- Principles: none
- Importance: 1
- Confidence: 5
- Recommendation: REDO AS IS

### 12.45 — CSV Conditionality column prints the summary
- Defect in base: REAL. `CSVRequirementsReportGenerator.kt:44` is `conditionality is SummarizedConditionality -> summary.value`, the requirement's summary (`Requirement.kt:30`). It should read `SummarizedConditionality.summary`.
- Fix: CORRECT. Binds `val conditionality = conditionality` for the smart cast, then uses `conditionality.summary.value`.
- Test: `CSVRequirementsReportGeneratorTests` expects `Only when powered` and fails on base. The expectation isn't fully literal, though (see 12.53).
- Principles: 4 (literal expectations), in the test only.
- Importance: 4. Every requirements report has a wrong column.
- Confidence: 5
- Recommendation: REDO AS IS for the main code. Write the test per the 12.53 modification.

### 12.46 — CSV fields never quoted or escaped (partly fixed)
- Defect in base: REAL. Both generators join with `", "` and never quote, and the multi-value fields use `joinToString`'s default `", "`. Commas, quotes and newlines corrupt rows, and the headers get leading spaces.
- Fix: CORRECT for the part implemented. New `CSVRow.kt` adds `internal fun csvRow(vararg fields: Any)`: join on `,`, quote a field only if it contains `,`, `"`, CR or LF, and double embedded quotes. That's RFC 4180, apart from using LF row endings instead of CRLF, which is acceptable. Headers and rows both go through it.
- Behaviour changes, all requested by the finding: the separator is now `,`, header spaces are gone, and multi-value cells are quoted instead of switched to `;`. Formula-prefixing was deliberately left out (needs a decision).
- Minimality: about 5 lines, and no CSV library exists in the dependency catalogue, so hand-rolling is fine.
- Principles: none
- Importance: 4. Every report with multiple publishers or reasons is corrupt today (the test factories create 1–2 publishers).
- Confidence: 5
- Recommendation: REDO AS IS for the quoting. Formula prefixing stays an owner decision.

### 12.51 — Cancellation becomes a nack (upstream)
- Defect in base: REAL, but upstream (swissknife `processAsCompositeEvent`, item 9.141).
- Fix: N/A in this repo. The only element change is the `sollecitom-swissknife` 1.0.35 → 1.0.37 bump in `libs.versions.toml`, along with pillar, gradle-plugins and the catalogue.
- Principles: depends on how 9.141 is redone against principle 2.
- Importance: 2 for this repo
- Confidence: 4
- Recommendation: DROP as an element item. Track it under swissknife 9.141; bump versions after the upstream redo.

### 12.52 — Event processing tests exercise a stub
- Defect in base: REAL. `CompliancePlanEventProcessingTests.kt:69-87` builds the downstream events in a hand-written lambda and never calls `ApplicationImplementation`.
- Fix: CORRECT. The test now builds `Application.create(repository, CSVStandardsReportGenerator(), CSVRequirementsReportGenerator(), recordingPublisher)`, using a repository that overrides the store methods on top of `stubbedCompliancePlanOutputsRepository()`. Assertions now check the published event types, `descendFrom` and `originateFrom`, all of which exist in swissknife since the first commit, so no new API is needed. The old `descendAndOriginateFrom` compared the full parent context, which only fit the stub. The failure case now throws from `storeCompliancePlan` and asserts that nothing was published.
- Behaviour beyond the finding: none in production code. The test still doesn't assert what was stored (the store stubs return `Unit`), which would be a cheap addition.
- Principles: CONFLICT with 2, carried over from base. The failure test still asserts `wasAcknowledgedAsFailed()` / `wasNotAcknowledgedSuccessfully()`, i.e. that the message was nacked. That matches current pillar behaviour but not "never nack".
- Importance: 3. Before the rewrite the test couldn't catch any regression.
- Confidence: 5. Green on the snapshot.
- Recommendation: REDO MODIFIED: keep the rewrite. Change the failure assertion to "not acknowledged and not nacked" once the processing semantics are redone per principle 2; until then this test pins the current nack. Optionally record and assert the stored standards and requirements.

### 12.53 — No CSV generator tests
- Defect in base: REAL. There were no generator tests, and the module spec only checks the CSV is non-empty.
- Fix: INCOMPLETE. Adds `CSVStandardsReportGeneratorTests` and `CSVRequirementsReportGeneratorTests`, one row each, with quoting and the conditionality column. Problems:
  - (a) The expected strings interpolate `${publicationDate.displayName()}`. That mirrors the implementation and the JVM locale (12.49) instead of being literal, and `testImplementation(libs.swissknife.kotlin.extensions)` was added just for it.
  - (b) There's no case for the inapplicable-requirement filtering or for `includeConditionalityForConfirmedApplicableRequirements`, which the finding named.
- Principles: 4 (literal expectations), because of (a).
- Importance: 3
- Confidence: 5
- Recommendation: REDO MODIFIED: use a literal date string. Decide 12.49 first, e.g. ISO `2020-01`, or fix the locale. Drop the extra `kotlin.extensions` test dependency. Add one test for filtering a confirmed-inapplicable conditional requirement.

### 12.54 — Verification-method filter test can't fail
- Defect in base: REAL. The test selects all four methods and asserts `containsAtLeastAllElementsIn(requirements)`, which a filter that returns everything still passes.
- Fix: CORRECT. It now selects `{MEASUREMENT, TEST}` and asserts `containsSameElementsAs(setOf(measurement, test))`, and the unused import is removed.
- Principles: none
- Importance: 3
- Confidence: 5
- Recommendation: REDO AS IS

### 12.55 — Repository spec missing re-store / empty / null-edition cases (partly fixed)
- Defect in base: REAL.
- Fix: CORRECT for the part implemented. The empty-set case (12.35) and the null-edition case (12.33) were added, plus the shared `PublicationTestFactories` `edition: Name?` parameter. The re-store-keeps-applicability case is deferred to 12.34.
- Principles: none
- Importance: 3
- Confidence: 5
- Recommendation: REDO AS IS, together with 12.33 and 12.35.

### 12.56 — Contract tests never exercise the entitlement error
- Defect in base: REAL. The contract tests have no entitlement case, and the list stubs are typed `ApplicationResult.Successful<…>`, so they couldn't return one.
- Fix: CORRECT. Adds an entitlement test to the confirm, requirements-list and standards-list specs, and widens the two list stub types to `ApplicationResult<…>`, which is needed for those tests. Entitlement cases were also added to the three `ResultJsonSerializationTests`. These test changes don't alter behaviour beyond the finding. The report endpoints weren't touched; their serde already handled entitlement.
- Principles: none
- Importance: 3. They catch 12.40 and 12.41.
- Confidence: 5
- Recommendation: REDO AS IS

### 12.57 — "Nonexistent plan" test uses a stub that always returns a plan (partly fixed)
- Defect in base: REAL. `ApplicationTests.kt:57-68` uses `nonexistentPlanId`, but the default stub returns a plan.
- Fix: rename only (`nonexistentPlanId` → `compliancePlanId`); the real missing-plan test waits on 12.47.
- Principles: none
- Importance: 1
- Confidence: 5
- Recommendation: REDO AS IS. It's trivial and removes a misleading name.

### 12.58 — Module spec connectors never stopped
- Defect in base: REAL. `CompliancePlanOutputsManagerModuleTestSpecification.kt:82,106` calls `pulsar.client().messages(...).apply { start() }` and never stops or closes it.
- Fix: CORRECT. Keeps `client` in a local, wraps the body in `try { … } finally { messages.stop(); client.close() }`, and reindents. Closing the client goes slightly beyond the finding but is right, since `pulsar.client()` makes a new client per call. Process-based suite is 17/17.
- Principles: none
- Importance: 2
- Confidence: 4
- Recommendation: REDO AS IS

### scripts/update-gradle.sh — `sed -i ''` BSD-only
- Defect in base: REAL. `scripts/update-gradle.sh:23` uses `sed -i '' 's/…/'`. GNU sed takes `''` as the script and fails after the wrapper was already rewritten (`set -euo pipefail`).
- Fix: CORRECT. `sed -i.bak … && rm "${props_file}.bak"`, which works with both BSD and GNU sed. Strictly the two commands are separate lines; with `set -e` that behaves the same.
- Principles: none
- Importance: 2. Only matters on Linux or CI; the owner uses macOS.
- Confidence: 5
- Recommendation: REDO AS IS

---

## Unattributed changes

None in scope beyond what's excluded. Every file in the base..snapshot diff outside the two excluded modules maps to an item above, with these notes:
- `gradle/libs.versions.toml`: internal version bumps (gradle-plugins 1.0.33, swissknife 1.0.37, pillar 1.0.19, acme-schema-catalogue 1.0.7). These are mechanical and excluded, but 12.51 (and possibly other upstream-dependent behaviour) relies on them, so re-bump only after the upstream redo.
- `content/migrator/.../1_6_order_compliance_plans_by_state/1_6_0_add_state_order_column.sql` and its changelog include belong to viewer item 12.78, which the other verifier covers. It sits in the migrator directory but isn't my scope. It also drops `customer_id_state_type_index`.
- `PublicationTestFactories.kt` (`edition: Name?`) supports 12.33 and 12.55.
- `application/tests/build.gradle.kts` (`testImplementation(libs.swissknife.kotlin.extensions)`) exists only to support the non-literal date in the 12.53 tests. Drop it under the 12.53 modification.

## Observations (pre-existing, not scored, not fixed)
- Many DB serdes in `compliance-plan-outputs-manager/adapters/driven/repository/postgres/.../serde/standard/**` point their `SCHEMA_LOCATION` at paths that don't exist, e.g. `compliance-plan-outputs-manager/db/standard/testing/Publication.json` and `requirement/standard/testing/ApplicabilityReason.json`. Several others point at `example/http-event-bridge/...`. The actual files live under `compliance-plan-output-viewer/db/...`. Lazy `schema` is never touched on the DB path, so nothing fails today, but `.schema` would throw. Possibly the same class of bug as the pillar `UnitJsonSerde` finding.
- `GetCompliancePlanRequirementsQueryEndpoint` logs the request twice (`logger.info` and `logger.log`). Not introduced by the fix.
