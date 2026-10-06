# Bug hunt checklist — open items

Items still open after the 2026-10-06 redo. Full write-ups (file:line, scenario, suggested fix) are in
[`analysis/BUG_HUNT_2026-10-04.md`](analysis/BUG_HUNT_2026-10-04.md). Severity: **H** high, **M** medium, **L** low.
We go through them one at a time; an item is ticked when decided (and fixed if needed). This file stays until the owner
confirms we are done.


## 1. Workspace root (scripts, justfile, docs, policy)

- [x] 1.16 **L** `policy/license-policy.yml` aliases `MIT-0`→`0BSD` and `Public Domain`→`CC0-1.0` (different licenses) — needs decision: real; which licenses to allow is a policy choice — decided 2026-10-06: dropped the MIT-0 and bare Public Domain aliases

## 3. gradle-plugins

- [x] 3.3 **M** Jib `user`/`imageFormat` hardcoded; KDoc says reproducible default is false (it's true) — KDoc corrected; needs decision: honouring user/imageFormat needs afterEvaluate (Jib API is eager) or dropping the two settings — decided 2026-10-06: removed the ignored user/imageFormat settings (always nobody/OCI)
- [x] 3.8 **L** Placeholder `maven.pkg.github.com/acme/*` repo added whenever GitHub env vars are set — needs decision: real; whether the placeholder repo should exist at all — decided 2026-10-06: GitHub Packages repository commented out (no GitHub build today)
- [x] 3.10 **L** `UpdateInternalCatalogVersionsTask` registered but never used, and diverges from the script — needs decision: real; delete (drops public `internalGroups` extension) or align with the script — decided 2026-10-06: deleted the unused task and its internalGroups setting

## 4. acme-schema-catalogue

- [x] 4.1 **H** `AccountEvent.avsc` declares record `AccountPlanEvent` — needs decision: rename to AccountEvent (+ alias) is backward- but not forward-compatible, so a FORWARD/FULL registry would reject it (a fix was tried and reverted) — decided 2026-10-06: rename the record to AccountEvent (to do)
- [x] 4.2 **H** `EntityEvent.json` unsatisfiable (broken `allOf` ref, conflicting `additionalProperties`, wrong refs) — needs decision: real; Event.json has additionalProperties:false, so composition needs restructuring; unused — decided 2026-10-06: delete EntityEvent.json (to do)
- [x] 4.5 **M** `AuthenticatedAccess.json` requires `is-test`; Avro twin has no `is_test` — needs decision: real; add `is_test` to Avro (pillar serde change) or drop from JSON required — decided 2026-10-06: add is_test to AuthenticatedAccess.avsc and pillar serde (to do)
- [x] 4.6 **L** `EncryptionMetadata` union omits XTS — needs decision: real; adding XTS needs a pillar change, or delete the XTS schema — decided 2026-10-06: add XTS to the EncryptionMetadata union (to do)
- [x] 4.7 **L** `ServiceAccount.json` flattened vs Avro internal/external union — needs decision: real; modelling choice — decided 2026-10-06: leave them different: the JSON form only exists for a JavaScript client that cannot use Avro
- [x] 4.8 **L** `CurrencyAmount.json` `units` integer ≥ 0 vs Avro string (negatives) — needs decision: real; modelling choice — decided 2026-10-06: no negatives; units as a big integer (Avro: bytes decimal, precision 100, scale 0, as BigInteger, serde rejects negatives; JSON: string ^[0-9]+$, JS-safe) (to do)
- [x] 4.10 **L** `Unit.json` only allows the placeholder `"<unit>"` — needs decision: real; fill the enum or delete — decided 2026-10-06: by design (pillar serialises Kotlin Unit as "<unit>")
- [x] 4.11 **L** `PaginationArguments.json` `limit` has no minimum — needs decision: real; minimum 0 or 1 is a product call — decided 2026-10-06: minimum 1 (to do)
- [x] 4.12 **L** `envelope_type` free string, not tied to the union branch — needs decision: real; modelling choice — decided 2026-10-06: keep the envelope records (Avro cannot nest unions) but drop envelope_type: the union branch identifies the case, serdes dispatch on the branch record name; per-union type enums and the swissknife enum-type envelope helpers go (to do)

## 5. tools

- [ ] 5.2 **H** package-migrator text/path replacement has no identifier/segment boundaries — needs decision: real; whole-name matching changes the template-cloning use case and text/path matching must agree
- [ ] 5.3 **M** package-migrator targets the working directory; README stale — needs decision: real; CLI design
- [ ] 5.5 **M** package-migrator moves excluded directories but doesn't rewrite them — uncertain: real, suggested filter insufficient; how narrow the excluded-folder rule should be is a design choice
- [ ] 5.9 **L** license-audit self-check tests paths production never uses — needs decision: real; test strategy (new self-checks do cover the real path)

## 6. quality-scorer

- [ ] 6.1 **H** `--project` not validated: empty/missing project scores 0.65 — non-directory `--project` now exits 2; needs decision: an empty directory still scores 0.65 (usage error vs score 0)
- [ ] 6.2 **M** Missing/unparsable `--coverage` silently scores 0 — needs decision: real; fail vs warn is grading policy
- [ ] 6.5 **L** `productionFunctions` includes helpers in test sources — needs decision: real; scoring semantics
- [ ] 6.6 **L** Walk includes `build/`/`.gradle/`; `isTestPath` misses `testFixtures`/`integrationTest` — needs decision: real; scoring semantics
- [ ] 6.8 **L** `SourceLocation` dead — needs decision: real; removing a field from Finding is a contract change

## 7. examples

- [ ] 7.5 **L** `cardAuthWasProcessed` dead — needs decision: real; part of a factory set, deletion is taste
- [ ] 7.6 **L** Money fields as `double` in test schemas — needs decision: real; modelling

## 8. facts (unwired)

- [ ] 8.1 **L** `waitForTurn` matches historical events (replay flow) — real; facts is unwired — report only
- [ ] 8.2 **L** `runBlocking` in projection getter called from suspend code — real; facts is unwired — report only
- [ ] 8.3 **L** Vacuous `assertThat(true).isTrue()`; stale `.gitmodules` — real; facts is unwired — report only

## 9. swissknife

- [ ] 9.2 **M** `UniqueIdFactory` internal/external ignore the injected clock/random — needs decision: real; honour the injected clock/random or drop the parameters
- [ ] 9.4 **M** `Id.fromString` doesn't round-trip type or text — needs decision: real; round-trip semantics of Id.fromString
- [ ] 9.6 **M** `CurrencyAmount` division rounds, multiplication truncates — needs decision: finding partly wrong — an existing test asserts division rounds; rounding policy is a choice
- [ ] 9.7 **M** Logged random seed can't reproduce; seeded `secureRandom` used for JWT keys — needs decision: real; seed / secureRandom design
- [ ] 9.9 **L** `EmailAddress` validation too loose; test factory emits trailing dot — test factory trailing dot fixed; needs decision: how strict validation should be
- [ ] 9.10 **L** `EphemeralPort`/`RequestedPort` implement `Comparable<Int>`; "ephemeral" range wrong — needs decision: real; renaming/re-typing public types
- [ ] 9.15 **L** `requiredBits` wrong for powers of two and 0 — uncertain: semantics undefined and unused; only 0 → Int.MIN_VALUE is wrong under every reading
- [ ] 9.17 **M** Invalid toggle value from a header makes context logging throw — needs decision: real; reject at gateway, lenient EnumToggle, or tolerate in logLevel
- [ ] 9.21 **L** `Trace.isParent` means "is root" — needs decision: real; public rename
- [x] 9.22 **H** `configurationPropertiesUnderRoot` returns null values (Pulsar overrides dropped in both services) — needs decision: real but mis-described — http4k normalises keys (lowercase, `.`/`_`→`-`), so the result is an empty map and camelCase Pulsar names can't be recovered; needs an explicit key list or raw source — decided 2026-10-06: helper matches keys in any spelling against known names and fails on unknown keys; Pulsar names kept in swissknife `PulsarClientSettings`, checked against the Pulsar version by a build-time test
- [ ] 9.25 **L** Blake3 `*_BITES` constants are bytes; unused `zero-allocation-hashing` dependency — unused dependency removed; needs decision: renaming public `*_BITES` constants
- [ ] 9.26 **L** `ResourceLoader` fails for jar resources and names with `:` — colon names fixed (test); needs decision: jar resources have no Path
- [ ] 9.27 **L** `update-container-versions.sh` picks most recently updated tag, not highest — needs decision: real; tag-selection policy
- [ ] 9.29 **L** `correlation-logging-test-utils` published with no source — needs decision: real; per-module test-utils is a convention — remove or fill
- [ ] 9.33 **L** Signature verification trusts the algorithm name from the signature — needs decision: real; signature metadata design
- [ ] 9.34 **L** Signature metadata `keyHash` is the private key's hash — needs decision: real; signature metadata design
- [ ] 9.35 **L** XTS doesn't reject equal data/tweak keys — needs decision: IEEE 1619-2007 (which the code implements) uses equal keys in vector 1; rejecting them chooses the 2018/FIPS rule
- [ ] 9.38 **M** `protectValue(iv = …)` accepts caller IVs (GCM nonce reuse) — needs decision: real; API change
- [ ] 9.39 **M** Protected value `name`/`owner` not bound as AAD — needs decision: real; changes ciphertext format
- [ ] 9.40 **M** `access(context)` ignores the context; README claims access control — needs decision: real; access-control design
- [ ] 9.47 **L** `JWT.isValidAtTime` ignores `nbf` — needs decision: KDoc defines it as not-expired and pillar relies on that; add nbf (contract change), rename, or fix KDoc
- [ ] 9.53 **L** Stale `.trivyignore` check uses severity-filtered scan — needs decision: real; scan-all vs reword
- [x] 9.55 **H** Custom Liquibase lock: check-then-act race lets two pods migrate — needs decision: real; lock-service redesign — decided 2026-10-06: replaced by a Postgres session advisory lock (`PostgresAdvisoryLockService`), Testcontainers tests
- [x] 9.56 **M** Lock liveness uses zone-less `backend_start` strings; SQL interpolation — needs decision: real; lock-service redesign — gone with 9.55 (no session strings, no interpolated SQL)
- [ ] 9.57 **M** `bindValueOrNull` binds every null as VARCHAR — needs decision: real; null-typing API
- [ ] 9.59 **L** `PostgresContainer` `rootUser = true` connects as nonexistent `root` — needs decision: real; remove parameter (API) or no-op
- [ ] 9.62 **L** `LiquibaseDatabaseMigrator` lazy connection: wrong dispatcher, `stop()` connects, second run fails — needs decision: real; lifecycle redesign
- [ ] 9.63 **L** `SqlEntityFilter` count and page from different snapshots — needs decision: real; isolation choice
- [ ] 9.64 **L** No tests for lock service, pagination, binding helpers — first sql tests added (binding, parsing, readiness); lock tests added with 9.55; pagination tests wait on 9.63
- [ ] 9.77 **L** Response validation throws for `PURGE`/`QUERY` — needs decision: finding wrong about requests (they throw too); PURGE/QUERY aren't OpenAPI methods — throw vs report
- [ ] 9.81 **L** `LowercasePathNameRule` flags template variables — needs decision: style choice for template variables
- [ ] 9.82 **L** `DisallowReservedCharactersInParameterNameRule` misnamed — needs decision: real; public rename
- [ ] 9.85 **L** `OpenApiReader.parseContent` doesn't resolve refs — needs decision: no base location for string content
- [ ] 9.86 **L** `LocationBasedOpenApiProvider` re-parses on every access, leaks stream — stream closed; needs decision: caching would share one mutable OpenAPI object
- [ ] 9.87 **L** `DowngradingOpenApiDefinitionReader` dead and broken — needs decision: real; delete vs fix
- [ ] 9.88 **L** OpenAPI rules mostly untested; double-slash test URL — double-slash URL fixed; tests added for every changed rule; full per-rule coverage is coverage work
- [ ] 9.92 **L** `mainHttpApi` unused context parameters — needs decision: real; signature change
- [ ] 9.93 **L** `InvocationContextFilter` only holds keys — needs decision: real; rename
- [ ] 9.95 **L** `LocalHttpDrivingAdapterTestSpecification.meterRegistry` new per access — needs decision: interface can't hold per-instance state; abstract breaks consumers
- [ ] 9.101 **L** Toggle lens rejects values containing `=` — needs decision: `{id}={value}` format ambiguous either way
- [ ] 9.102 **L** Readiness `runBlocking` has no timeout — needs decision: real; timeout value
- [x] 9.103 **H** Pulsar `AvroReader` ignores the writer schema version (schema evolution broken) — uncertain: real, but AvroSchema.clone() shares one reader across per-topic clones, so delegating would mix writer schemas across topics of a multi-topic consumer; needs per-clone readers (design) — fixed 2026-10-06: public-API Pulsar schema decodes with the writer schema version (container test)
- [ ] 9.104 **H** Pulsar consumers forced to Failover — needs decision: real; consumers rely on Failover ordering
- [ ] 9.105 **M** Partition-change listener loses events; `runBlocking` on Pulsar thread — needs decision: real; replay/buffer and drop-vs-backpressure
- [ ] 9.107 **M** `setAutoTopicCreation` called twice with wrong enum format — needs decision: visible in code; broker behaviour needs a running broker
- [ ] 9.111 **L** Blocking Pulsar subscribe/create/close in suspend functions; `stop()` connects — needs decision: real; async API redesign
- [x] 9.113 **L** `MultiVersionGenericAvroReader` would mutate the shared schema once 9.103 is fixed — latent until 9.103 — fixed with 9.103: no shared mutable reader (clone() builds a fresh schema)
- [ ] 9.116 **M** `MessagingTestSpecification` unimplemented; no Pulsar tests — needs decision: test build-out
- [ ] 9.117 **L** `produceAndAwaitSuccessor` drops non-matching messages — needs decision: real; nacking loops in tests
- [ ] 9.119 **L** `toOutboundMessage(value, parent)` creates a sibling — needs decision: semantics
- [ ] 9.120 **L** Namespace-less topics don't round-trip — needs decision: topic model
- [ ] 9.122 **M** NATS no flush after subscribe — needs decision: real; flush timeout/failure policy — applied 2026-10-06 to fix a flaky test: flush with a 10s timeout after subscribing, failure propagates; **confirm**
- [ ] 9.128 **L** JSON `getInt`/`getLong` narrow silently — needs decision: real; null vs throw for fractions/overflow
- [ ] 9.131 **L** JSON checker rules only inspect top level — needs decision: stricter rules, nested path reporting
- [ ] 9.133 **M** MDC in `InheritableThreadLocal` leaks into pool threads — needs decision: MDC propagation semantics
- [ ] 9.135 **L** Logger level prefix matching per character, not per package segment — needs decision: `.` vs `.`/`$` boundary
- [ ] 9.136 **L** JSON log formatter drops null `message`; schema property names disagree — needs decision: empty string vs schema relaxation; renaming changes validation
- [ ] 9.137 **L** Logging level overrides not trimmed/uppercased; replace defaults instead of merging — needs decision: merge vs replace
- [ ] 9.139 **M** OpenTelemetry module registers global, per-span export, never shut down — needs decision: lifecycle design

## 10. pillar

- [ ] 10.9 **L** `MessagingEventProcessor` logs payloads at INFO — needs decision: real; log policy
- [ ] 10.18 **L** OpenAPI rule tests never exercise JSON example rules — JSON request/response example tests added; exampleSchemaComplianceRule still untested (needs $ref fixtures)
- [ ] 10.19 **L** `JvmGcMetrics`/`JvmHeapPressureMetrics` never closed — needs decision: real; API for binder lifecycle
- [ ] 10.26 **M** JSON locale serdes lack the `no_NO_NY` special case — needs decision: real; changes the JSON wire format
- [ ] 10.27 **M** Leaf JSON serdes have no schema-compliance tests — compliance tests added for 5 leaf serdes; actor leaves fail AcmeJsonSchemaRules (needs catalogue or rule change)

## 11. modulith-example

- [x] 11.1 **H** Production payment module wired to an always-success stub — needs decision: real; response contract — left to the owner (2026-10-06): building the processor and the NATS outcome round trip is his to do later
- [x] 11.2 **H** No check that the caller owns the source account — needs decision: real; authorisation — decided 2026-10-06: the account-event-processor checks ownership when handling the command and publishes a rejection; recorded as a README requirement and a TODO on the unimplemented handler (built with 11.8)
- [x] 11.3 **M** Fresh event id per request and publish-before-wait: retries double-apply — needs decision: real; idempotency — left to the owner with 11.1 (same piece of work)
- [x] 11.6 **L** Payment module test asserts status only — needs decision: real; right expectation depends on 11.1 — left to the owner with 11.1 (same piece of work)
- [x] 11.8 **H** account-event-processor handlers all TODO (unwired); README says Done — needs decision: real; README section left as is — left to the owner with 11.1 (same piece of work)
- [x] 11.10 **M** No positive-amount check on payments/deposits — needs decision: real; domain rule — left to the owner with 11.1 (same piece of work)
- [x] 11.11 **L** `AccountEvent.avsc` wrong record name (see 4.1) — needs decision: see 4.1 — decided 2026-10-06: with 4.1 (to do)
- [ ] 11.12 **L** Publisher log says "compliance plan event" and leaks amounts — log text fixed; needs decision: logging full events at INFO
- [ ] 11.16 **L** Random node name; `INSTANCE_*` env vars never read — needs decision: real; instance identity
- [ ] 11.18 **L** Registry auth lookup result discarded — needs decision: real; delete or wire Docker auth
- [x] 11.19 **L** Partitioned topic only pre-created in tests — needs decision: real; provisioning — left to the owner with 11.1 (same piece of work)

## 12. element-service-example

- [ ] 12.3 **M** Chart image repositories/tags don't match the images the build produces — needs decision: real; registry/tags
- [ ] 12.4 **M** No startupProbe; liveness budget shorter than startup — needs decision: real; probe budget
- [ ] 12.5 **M** Trivy scans only the service image, not the migrator — needs decision: real; scan scope
- [x] 12.9 **M** Pulsar config overrides dropped (see 9.22 — blocked on 9.22 (needs decision); no change needed in this repo once fixed upstream — fixed with 9.22
- [ ] 12.10 **M** Random instance id; `INSTANCE_NODE_NAME` never read — needs decision: real; instance identity
- [ ] 12.11 **M** R2DBC without a connection pool — needs decision: real; pool choice
- [ ] 12.12 **L** `stop()` doesn't close clients; first failure skips the rest — needs decision: real; stop-failure policy, and nothing to close until 12.11
- [ ] 12.13 **L** Health server starts before the main server — needs decision: real
- [ ] 12.14 **L** `default-configuration.yml` never loaded — needs decision: real; delete or load
- [ ] 12.16 **M** Migrations use `DROP TABLE` (data loss on upgrade) — needs decision: real; applied changesets must not be edited
- [ ] 12.17 **M** `Standard.equals` compares only reference and publication (hides serde bugs, collapses sets) — needs decision: real; equality semantics
- [ ] 12.18 **L** Requirement `Standard`/`Clause` `compareTo` inconsistent with `equals` — needs decision: real
- [ ] 12.20 **L** `Market`/SDO accept any name; Avro enums are closed — needs decision: real
- [ ] 12.31 **L** Uncommitted `.trivyignore` change (also modulith) pending a security-scan run — untouched as instructed
- [x] 12.34 **H** Re-storing requirements resets applicability decisions — needs decision: real; applicability semantics after re-analysis — decided 2026-10-06 (revised): re-storing keeps the decision of every requirement still present (by id); new ones start undecided, removed ones go; repository-spec test
- [ ] 12.37 **M** `limit` 0/negative/unbounded — uncertain: real; max limit and validation location are choices
- [ ] 12.38 **M** Plan upsert has no version guard — needs decision: real; versioning scheme
- [ ] 12.46 **H** CSV fields never quoted/escaped (formula injection, corrupt rows) — RFC-4180 quoting/escaping fixed (new CSVRow, tests); needs decision: spreadsheet formula prefixing alters data
- [ ] 12.47 **M** Missing plan treated as entitled — needs decision: real; not-found semantics
- [ ] 12.48 **M** Writes before publish not transactional — needs decision: real; transaction boundary
- [ ] 12.49 **L** CSV dates depend on JVM locale — needs decision: real; date format
- [ ] 12.50 **L** CSV has no BOM — needs decision: real; BOM
- [x] 12.55 **L** Repository spec missing re-store/empty/null-edition cases — empty-set and null-edition cases added; re-store-keeps-applicability depends on 12.34 — re-store-keeps-decisions case added with 12.34
- [ ] 12.57 **L** "Nonexistent plan" test uses a stub that always returns a plan — misleading name fixed; a real missing-plan test depends on 12.47
- [x] 12.60 **H** Ingestion only checks "authenticated" (no role/customer check) — needs decision: real; authorisation — decided 2026-10-06: the gateway restricts event endpoints to allowed machine clients (GATEWAY.md); services trust them
- [x] 12.63 **M** No idempotency on ingestion — needs decision: real; idempotency — skipped 2026-10-06 (example): documented in element IMPROVEMENTS.md (issue + improvement 9, idempotency-keyed rotating table)
- [ ] 12.64 **L** Always 200, even on `ApplicationResult.Error` — needs decision: real; status for a currently unreachable Error
- [x] 12.66 **H** Notifier serde writes fields its schema forbids; untested — needs decision: real; unclear whether the serde shape or the flat email-contract schema is intended — decided 2026-10-06: schemas now describe the nested plan the serde sends; schema-compliance test over the notification event (fails on the old schema)
- [ ] 12.67 **M** Lifecycle notifications lose the parent message id — needs decision: real; notifier interface change
- [ ] 12.71 **M** Round-trip tests can't detect dropped optional fields (see 12.17) — needs decision: see 12.17
- [ ] 12.72 **M** Body not schema-validated; no size limit (gzip bomb) — proposed close: body size limits are the gateway's job (awaiting confirmation)
- [ ] 12.73 **L** Contract tests happy path only — needs decision: an Error contract case would lock in 12.64
- [x] 12.77 **H** Upsert overwrites newer state (redelivery regresses plans) — needs decision: real; ordering guard design — skipped with 12.63 (stale re-posts are the remaining case; documented)
- [ ] 12.79 **M** `limit` not validated — needs decision: real; limit bounds
- [ ] 12.83 **L** Null customer becomes `'null'` — null customer now binds SQL NULL (no `'null'` literal); needs decision: reject with 403 instead of empty 200
- [ ] 12.87 **L** `ApplicableRequirementsOutputsAvailable` not handled — uncertain: nothing produces the event yet
- [ ] 12.89 **L** Full results logged at INFO — needs decision: log policy
- [ ] 12.90 **L** `toAuthenticated` runs handlers in `runBlocking` — needs decision: shared pillar API

## New (from the redo and the 2026-10-06 review)

- [ ] N.1 **L** package-migrator: migrating `a.b` → `a.b.v2` still fails in the directory phase (moves a directory into itself)
- [ ] N.2 **H** Pulsar 5: swissknife now uses only public Pulsar APIs (works on 4.2.4 and 5.0.0), but 5.0.0 is blocked by slog 0.10.0 (picks Log4j2 when log4j-api is present, then needs log4j-core; our services carry log4j-to-slf4j for Yauaa). Client pinned at 4.2.4. **Agreed next (when the owner is back):** drop the unused `web-client-info-analyzer` dependency from swissknife `web-api-utils`, move pillar's gateway stub (`GatewayHttpFilter`, `GatewayInvocationContextFilter`, `GATEWAY.md`) and its Yauaa dependency into its own pillar module, confirm `log4j-api` is gone from the services, then retry Pulsar 5; first run `build-workspace` (last changes unverified)
- [ ] N.4 **H** Evolving topics with new event types (decided 2026-10-06, to do): (1) swissknife namespace compatibility default `BACKWARD_TRANSITIVE` (FULL_TRANSITIVE rejects new union branches); (2) lint rule: a topic's value schema reaches its events through a union; (3) pillar's processor checks the event-type header before decoding and acks unhandled types without deserialising them (handlers declare the types they handle), tested with an undecodable payload of an unhandled type
- [ ] N.3 **L** Readability leftovers: one failure-injection style in the two `CompliancePlanEventProcessingTests`; Pulsar client closing style in the outputs-manager module spec; package-migrator relative-path helper
