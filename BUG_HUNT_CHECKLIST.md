# Bug hunt checklist — open items

Items still open after the 2026-10-06 redo. Full write-ups (file:line, scenario, suggested fix) are in
[`analysis/BUG_HUNT_2026-10-04.md`](analysis/BUG_HUNT_2026-10-04.md). Severity: **H** high, **M** medium, **L** low.
We go through them one at a time; an item is ticked when decided (and fixed if needed). This file stays until the owner
confirms we are done.

## Where we are (saved 2026-10-06, before a laptop restart)

**How we work through this list** (owner's rules): one repo at a time, up to 10 items per batch; items numbered 1, 2, 3…
(no checklist ids in the presentation); short options numbered 1, 2, 3 with a recommendation; when the owner decides,
*record* the decision here and mark it "(to do)" — the actual changes are made later, all together, then
`build-workspace` + commit.

**Done so far:** workspace, gradle-plugins, acme, tools, quality-scorer, examples, facts, swissknife, pillar, modulith, element.

**Next:** review finished (N.2 and N.4 already decided). Implementation in progress 2026-10-07 (see analysis/IMPLEMENTATION_NOTES_2026-10-07.md).

**Then the actual work:** implement every "(to do)" decision, then `just build-workspace` until green, commit.

**Open technical thread — N.2 Pulsar 5:** swissknife is on Pulsar 5.0.0 with only public APIs; the Yauaa/log4j path is
gone from the services (web-api-utils no longer depends on the client-info analyser; pillar's gateway stub moved to
module `web-api-gateway`). The last `build-workspace` passed gradle-plugins, acme, swissknife, pillar, lattice and tools,
then **examples' Pulsar tests hung until the 2-minute default timeout** (send/receive with Avro, wrapper types, message
converter), with no broker errors. Suspects: ack receipts (now enabled), consumers' `startPaused(true)`, or how Pulsar
5's client drives our public-API `Schema`. Investigate; if it's a Pulsar 5 behaviour change, pin back to 4.2.4 (the
public-API code works there) and tell the owner. element and modulith haven't been built against these changes yet.


## 1. Workspace root (scripts, justfile, docs, policy)

- [x] 1.16 **L** `policy/license-policy.yml` aliases `MIT-0`→`0BSD` and `Public Domain`→`CC0-1.0` (different licenses) — needs decision: real; which licenses to allow is a policy choice — decided 2026-10-06: dropped the MIT-0 and bare Public Domain aliases

## 3. gradle-plugins

- [x] 3.3 **M** Jib `user`/`imageFormat` hardcoded; KDoc says reproducible default is false (it's true) — KDoc corrected; needs decision: honouring user/imageFormat needs afterEvaluate (Jib API is eager) or dropping the two settings — decided 2026-10-06: removed the ignored user/imageFormat settings (always nobody/OCI)
- [x] 3.8 **L** Placeholder `maven.pkg.github.com/acme/*` repo added whenever GitHub env vars are set — needs decision: real; whether the placeholder repo should exist at all — decided 2026-10-06: GitHub Packages repository commented out (no GitHub build today)
- [x] 3.10 **L** `UpdateInternalCatalogVersionsTask` registered but never used, and diverges from the script — needs decision: real; delete (drops public `internalGroups` extension) or align with the script — decided 2026-10-06: deleted the unused task and its internalGroups setting

## 4. acme-schema-catalogue

- [x] 4.1 **H** `AccountEvent.avsc` declares record `AccountPlanEvent` — needs decision: rename to AccountEvent (+ alias) is backward- but not forward-compatible, so a FORWARD/FULL registry would reject it (a fix was tried and reverted) — decided 2026-10-06: rename the record to AccountEvent (done: acme 4e74575)
- [x] 4.2 **H** `EntityEvent.json` unsatisfiable (broken `allOf` ref, conflicting `additionalProperties`, wrong refs) — needs decision: real; Event.json has additionalProperties:false, so composition needs restructuring; unused — decided 2026-10-06: delete EntityEvent.json (done: acme 4e74575)
- [x] 4.5 **M** `AuthenticatedAccess.json` requires `is-test`; Avro twin has no `is_test` — needs decision: real; add `is_test` to Avro (pillar serde change) or drop from JSON required — decided 2026-10-06: add is_test to AuthenticatedAccess.avsc and pillar serde (acme 4e74575; pillar done pillar ce6582c..c49dfaa, 1.0.28; services done: modulith 93a3682, element 20a3775)
- [x] 4.6 **L** `EncryptionMetadata` union omits XTS — needs decision: real; adding XTS needs a pillar change, or delete the XTS schema — decided 2026-10-06: add XTS to the EncryptionMetadata union (done: acme 4e74575)
- [x] 4.7 **L** `ServiceAccount.json` flattened vs Avro internal/external union — needs decision: real; modelling choice — decided 2026-10-06: leave them different: the JSON form only exists for a JavaScript client that cannot use Avro
- [x] 4.8 **L** `CurrencyAmount.json` `units` integer ≥ 0 vs Avro string (negatives) — needs decision: real; modelling choice — decided 2026-10-06: no negatives; units as a big integer (Avro: bytes decimal, precision 100, scale 0, as BigInteger, serde rejects negatives; JSON: string ^[0-9]+$, JS-safe) (done: acme 4e74575)
- [x] 4.10 **L** `Unit.json` only allows the placeholder `"<unit>"` — needs decision: real; fill the enum or delete — decided 2026-10-06: by design (pillar serialises Kotlin Unit as "<unit>")
- [x] 4.11 **L** `PaginationArguments.json` `limit` has no minimum — needs decision: real; minimum 0 or 1 is a product call — decided 2026-10-06: minimum 1 (done: acme 4e74575)
- [x] 4.12 **L** `envelope_type` free string, not tied to the union branch — needs decision: real; modelling choice — decided 2026-10-06: keep the envelope records (Avro cannot nest unions) but drop envelope_type: the union branch identifies the case, serdes dispatch on the branch record name; per-union type enums and the swissknife enum-type envelope helpers go (acme 4e74575; pillar done pillar ce6582c..c49dfaa, 1.0.28; services done: modulith 93a3682, element 20a3775)

## 5. tools

- [x] 5.2 **H** package-migrator text/path replacement has no identifier/segment boundaries — needs decision: real; whole-name matching changes the template-cloning use case and text/path matching must agree — decided 2026-10-06: match whole package segments only, the same for text and paths (done: tools 51117ae)
- [x] 5.3 **M** package-migrator targets the working directory; README stale — needs decision: real; CLI design — decided 2026-10-06: add --project <dir> (default: working directory) and fix the README (done: tools 51117ae)
- [x] 5.5 **M** package-migrator moves excluded directories but doesn't rewrite them — uncertain: real, suggested filter insufficient; how narrow the excluded-folder rule should be is a design choice — decided 2026-10-06: never move excluded directories (build, .git, .kotlin, gradle; also add .gradle and .idea) (done: tools 51117ae)
- [x] 5.9 **L** license-audit self-check tests paths production never uses — needs decision: real; test strategy (new self-checks do cover the real path) — decided 2026-10-06: closed: the JUnit tests cover the real path

## 6. quality-scorer

- [x] 6.1 **H** `--project` not validated: empty/missing project scores 0.65 — non-directory `--project` now exits 2; needs decision: an empty directory still scores 0.65 (usage error vs score 0) — decided 2026-10-06 (paused stub, recommendations): no Kotlin files is a usage error (exit 2) (done: quality-scorer 8e7f774)
- [x] 6.2 **M** Missing/unparsable `--coverage` silently scores 0 — needs decision: real; fail vs warn is grading policy — decided 2026-10-06 (paused stub, recommendations): fail clearly when a given coverage path cannot be read (done: quality-scorer 8e7f774)
- [x] 6.5 **L** `productionFunctions` includes helpers in test sources — needs decision: real; scoring semantics — decided 2026-10-06 (paused stub, recommendations): count only functions in main source sets (done: quality-scorer 8e7f774)
- [x] 6.6 **L** Walk includes `build/`/`.gradle/`; `isTestPath` misses `testFixtures`/`integrationTest` — needs decision: real; scoring semantics — decided 2026-10-06 (paused stub, recommendations): skip build directories; any src/*test* is test code (done: quality-scorer 8e7f774)
- [x] 6.8 **L** `SourceLocation` dead — needs decision: real; removing a field from Finding is a contract change — decided 2026-10-06 (paused stub, recommendations): leave SourceLocation (owner, 2026-10-06)

## 7. examples

- [x] 7.5 **L** `cardAuthWasProcessed` dead — needs decision: real; part of a factory set, deletion is taste — decided 2026-10-06: leave it
- [x] 7.6 **L** Money fields as `double` in test schemas — needs decision: real; modelling — decided 2026-10-06: switch money to the Avro decimal form chosen for acme (bytes, logical type decimal) (done: examples 56ca8f2, 245b039; scale 2 not 0 because the amounts have cents — discuss)

## 8. facts (unwired)

- [x] 8.1 **L** `waitForTurn` matches historical events (replay flow) — real; facts is unwired — report only — decided 2026-10-06: fix anyway (done: facts c7e977c)
- [x] 8.2 **L** `runBlocking` in projection getter called from suspend code — real; facts is unwired — report only — decided 2026-10-06: fix anyway (done: facts c7e977c)
- [x] 8.3 **L** Vacuous `assertThat(true).isTrue()`; stale `.gitmodules` — real; facts is unwired — report only — decided 2026-10-06: fix anyway (done: facts c7e977c)

## 9. swissknife

- [x] 9.2 **M** `UniqueIdFactory` internal/external ignore the injected clock/random — needs decision: real; honour the injected clock/random or drop the parameters — decided 2026-10-06: honour the injected clock and random for UUIDv7 (internal/external): ULID/KSUID already do since 9.1, the UUID adapter takes neither (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.4 **M** `Id.fromString` doesn't round-trip type or text — needs decision: real; round-trip semantics of Id.fromString — decided 2026-10-06: fromString always returns a StringId (exact text); add a typed string form "<type>:<value>" (e.g. ulid:01ARZ…) with toTypedString/fromTypedString for round-trips where the type matters (element stores plan ids that way) (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.6 **M** `CurrencyAmount` division rounds, multiplication truncates — needs decision: finding partly wrong — an existing test asserts division rounds; rounding policy is a choice — decided 2026-10-06: truncate in both division and multiplication (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.7 **M** Logged random seed can't reproduce; seeded `secureRandom` used for JWT keys — needs decision: real; seed / secureRandom design — decided 2026-10-06: draw the logged seed from a separate source so it reproduces the run; seeding secureRandom stays possible when a seed is explicitly configured (tests), with a startup warning (done: swissknife 9740ee9..0c1bdb8, 1.0.47) — REVISED 2026-10-07: drop the logged production seed; production uses an unseeded SecureRandom for random and secureRandom (ids unpredictable); a configured seed (tests) seeds everything, so ids are reproducible in tests (to do)
- [x] 9.9 **L** `EmailAddress` validation too loose; test factory emits trailing dot — test factory trailing dot fixed; needs decision: how strict validation should be — decided 2026-10-06: easy tightening only: exactly one @, non-empty local part, domain containing a dot, no whitespace (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.10 **L** `EphemeralPort`/`RequestedPort` implement `Comparable<Int>`; "ephemeral" range wrong — needs decision: real; renaming/re-typing public types — decided 2026-10-06: Comparable with their own type, correct the ephemeral range doc (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.15 **L** `requiredBits` wrong for powers of two and 0 — uncertain: semantics undefined and unused; only 0 → Int.MIN_VALUE is wrong under every reading — decided 2026-10-06: fix requiredBits(0) (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.17 **M** Invalid toggle value from a header makes context logging throw — needs decision: real; reject at gateway, lenient EnumToggle, or tolerate in logLevel — decided 2026-10-06: reject invalid toggle values when the header is parsed (400) (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.21 **L** `Trace.isParent` means "is root" — needs decision: real; public rename — decided 2026-10-06: rename isParent to isRoot (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.22 **H** `configurationPropertiesUnderRoot` returns null values (Pulsar overrides dropped in both services) — needs decision: real but mis-described — http4k normalises keys (lowercase, `.`/`_`→`-`), so the result is an empty map and camelCase Pulsar names can't be recovered; needs an explicit key list or raw source — decided 2026-10-06: helper matches keys in any spelling against known names and fails on unknown keys; Pulsar names kept in swissknife `PulsarClientSettings`, checked against the Pulsar version by a build-time test
- [x] 9.25 **L** Blake3 `*_BITES` constants are bytes; unused `zero-allocation-hashing` dependency — unused dependency removed; needs decision: renaming public `*_BITES` constants — decided 2026-10-06: rename *_BITES to *_BYTES (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.26 **L** `ResourceLoader` fails for jar resources and names with `:` — colon names fixed (test); needs decision: jar resources have no Path — decided 2026-10-06: document it and offer a stream-based API for jar resources (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.27 **L** `update-container-versions.sh` picks most recently updated tag, not highest — needs decision: real; tag-selection policy — decided 2026-10-06: pick the highest version (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.29 **L** `correlation-logging-test-utils` published with no source — needs decision: real; per-module test-utils is a convention — remove or fill — decided 2026-10-06: fill correlation-logging-test-utils with the obvious helpers (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.33 **L** Signature verification trusts the algorithm name from the signature — needs decision: real; signature metadata design — decided 2026-10-06: fix the algorithm per key; reject signatures naming another one (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.34 **L** Signature metadata `keyHash` is the private key's hash — needs decision: real; signature metadata design — decided 2026-10-06: signature metadata uses the public-key hash; encryption metadata unchanged (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.35 **L** XTS doesn't reject equal data/tweak keys — needs decision: IEEE 1619-2007 (which the code implements) uses equal keys in vector 1; rejecting them chooses the 2018/FIPS rule — decided 2026-10-06: reject equal data and tweak keys (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.38 **M** `protectValue(iv = …)` accepts caller IVs (GCM nonce reuse) — needs decision: real; API change — decided 2026-10-06: remove the caller-chosen IV parameter, always generate it (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.39 **M** Protected value `name`/`owner` not bound as AAD — needs decision: real; changes ciphertext format — decided 2026-10-06: bind the owner (not the name) as associated data (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.40 **M** `access(context)` ignores the context; README claims access control — needs decision: real; access-control design — decided 2026-10-06: access takes a required closure called before decrypting, with the access context and the value (name, owner, metadata): it records who accessed what and when, and may refuse by throwing; test factories pass a default that logs timestamp, field name, owner and accessor; pillar provides the standard audit-log hook (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.47 **L** `JWT.isValidAtTime` ignores `nbf` — needs decision: KDoc defines it as not-expired and pillar relies on that; add nbf (contract change), rename, or fix KDoc — decided 2026-10-06: isValidAtTime also checks nbf, and add isNotExpiredAt (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.53 **L** Stale `.trivyignore` check uses severity-filtered scan — needs decision: real; scan-all vs reword — decided 2026-10-06: run the stale-ignore check at all severities (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.55 **H** Custom Liquibase lock: check-then-act race lets two pods migrate — needs decision: real; lock-service redesign — decided 2026-10-06: replaced by a Postgres session advisory lock (`PostgresAdvisoryLockService`), Testcontainers tests
- [x] 9.56 **M** Lock liveness uses zone-less `backend_start` strings; SQL interpolation — needs decision: real; lock-service redesign — gone with 9.55 (no session strings, no interpolated SQL)
- [x] 9.57 **M** `bindValueOrNull` binds every null as VARCHAR — needs decision: real; null-typing API — decided 2026-10-06: bindValueOrNull takes the column type for nulls (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.59 **L** `PostgresContainer` `rootUser = true` connects as nonexistent `root` — needs decision: real; remove parameter (API) or no-op — decided 2026-10-06: remove rootUser; add container.createUser(name, password) creating a restricted login (connect, read/write data, no DDL) for tests that need a non-superuser (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.62 **L** `LiquibaseDatabaseMigrator` lazy connection: wrong dispatcher, `stop()` connects, second run fails — needs decision: real; lifecycle redesign — decided 2026-10-06: fix the lifecycle: connect in start on an I/O dispatcher, close only if open, allow reuse (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.63 **L** `SqlEntityFilter` count and page from different snapshots — needs decision: real; isolation choice — decided 2026-10-06: read count and page in one read-only repeatable-read transaction (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.64 **L** No tests for lock service, pagination, binding helpers — first sql tests added (binding, parsing, readiness); lock tests added with 9.55; pagination tests wait on 9.63 — decided 2026-10-06: pagination tests with 9.63 (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.77 **L** Response validation throws for `PURGE`/`QUERY` — needs decision: finding wrong about requests (they throw too); PURGE/QUERY aren't OpenAPI methods — throw vs report — decided 2026-10-06: closed: PURGE/QUERY are not OpenAPI methods
- [x] 9.81 **L** `LowercasePathNameRule` flags template variables — needs decision: style choice for template variables — decided 2026-10-06: ignore path template variables (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.82 **L** `DisallowReservedCharactersInParameterNameRule` misnamed — needs decision: real; public rename — decided 2026-10-06: rename to DisallowReservedCharactersInParameterValuesRule (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.85 **L** `OpenApiReader.parseContent` doesn't resolve refs — needs decision: no base location for string content — decided 2026-10-06: document it and add an optional base-location parameter, with a test proving relative refs resolve (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.86 **L** `LocationBasedOpenApiProvider` re-parses on every access, leaks stream — stream closed; needs decision: caching would share one mutable OpenAPI object — decided 2026-10-06: leave it (no repeated reads today)
- [x] 9.87 **L** `DowngradingOpenApiDefinitionReader` dead and broken — needs decision: real; delete vs fix — decided 2026-10-06: fix it, with tests (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.88 **L** OpenAPI rules mostly untested; double-slash test URL — double-slash URL fixed; tests added for every changed rule; full per-rule coverage is coverage work — decided 2026-10-06: add a test per OpenAPI rule (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.92 **L** `mainHttpApi` unused context parameters — needs decision: real; signature change — decided 2026-10-06: leave the context parameters
- [x] 9.93 **L** `InvocationContextFilter` only holds keys — needs decision: real; rename — decided 2026-10-06: rename InvocationContextFilter to InvocationContextKeys (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.95 **L** `LocalHttpDrivingAdapterTestSpecification.meterRegistry` new per access — needs decision: interface can't hold per-instance state; abstract breaks consumers — decided 2026-10-06: leave it
- [x] 9.101 **L** Toggle lens rejects values containing `=` — needs decision: `{id}={value}` format ambiguous either way — decided 2026-10-06: split the toggle header on the first = (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.102 **L** Readiness `runBlocking` has no timeout — needs decision: real; timeout value — decided 2026-10-06: add a readiness timeout (e.g. 5s) reporting not ready (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.103 **H** Pulsar `AvroReader` ignores the writer schema version (schema evolution broken) — uncertain: real, but AvroSchema.clone() shares one reader across per-topic clones, so delegating would mix writer schemas across topics of a multi-topic consumer; needs per-clone readers (design) — fixed 2026-10-06: public-API Pulsar schema decodes with the writer schema version (container test)
- [x] 9.104 **H** Pulsar consumers forced to Failover — needs decision: real; consumers rely on Failover ordering — decided 2026-10-06: split the factory: plain consumer respects the subscription type; a separate partition-assignment-aware one forces Failover (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.105 **M** Partition-change listener loses events; `runBlocking` on Pulsar thread — needs decision: real; replay/buffer and drop-vs-backpressure — decided 2026-10-06: leave it
- [x] 9.107 **M** `setAutoTopicCreation` called twice with wrong enum format — needs decision: visible in code; broker behaviour needs a running broker — decided 2026-10-06: call setAutoTopicCreation once with the intended topic type, verified by a container test (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.111 **L** Blocking Pulsar subscribe/create/close in suspend functions; `stop()` connects — needs decision: real; async API redesign — decided 2026-10-06: switch to the async Pulsar API, close only what was opened (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.113 **L** `MultiVersionGenericAvroReader` would mutate the shared schema once 9.103 is fixed — latent until 9.103 — fixed with 9.103: no shared mutable reader (clone() builds a fresh schema)
- [x] 9.116 **M** `MessagingTestSpecification` unimplemented; no Pulsar tests — needs decision: test build-out — decided 2026-10-06: implement MessagingTestSpecification against a Pulsar container (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.117 **L** `produceAndAwaitSuccessor` drops non-matching messages — needs decision: real; nacking loops in tests — decided 2026-10-06: keep the behaviour, rename to produceAndSkipToSuccessor with a KDoc line about skipped messages (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.119 **L** `toOutboundMessage(value, parent)` creates a sibling — needs decision: semantics — decided 2026-10-06: delete the sibling overload toOutboundMessage(value, parentMessage) (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.120 **L** Namespace-less topics don't round-trip — needs decision: topic model — decided 2026-10-06: default to public/default explicitly (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.122 **M** NATS no flush after subscribe — needs decision: real; flush timeout/failure policy — applied 2026-10-06 to fix a flaky test: flush with a 10s timeout after subscribing, failure propagates; **confirm** — confirmed 2026-10-06: keep the flush; the timeout comes from configuration as a Kotlin Duration, default 10s (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.128 **L** JSON `getInt`/`getLong` narrow silently — needs decision: real; null vs throw for fractions/overflow — decided 2026-10-06: throw on overflow or fractions (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.131 **L** JSON checker rules only inspect top level — needs decision: stricter rules, nested path reporting — decided 2026-10-06: check nested properties, reporting the path (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.133 **M** MDC in `InheritableThreadLocal` leaks into pool threads — needs decision: MDC propagation semantics — decided 2026-10-06: plain ThreadLocal for the MDC (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.135 **L** Logger level prefix matching per character, not per package segment — needs decision: `.` vs `.`/`$` boundary — decided 2026-10-06: match whole package segments (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.136 **L** JSON log formatter drops null `message`; schema property names disagree — needs decision: empty string vs schema relaxation; renaming changes validation — decided 2026-10-06: write an empty string for a null message and align property names with the schema (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.137 **L** Logging level overrides not trimmed/uppercased; replace defaults instead of merging — needs decision: merge vs replace — decided 2026-10-06: trim, upper-case and merge with the defaults, configuration winning (done: swissknife 9740ee9..0c1bdb8, 1.0.47)
- [x] 9.139 **M** OpenTelemetry module registers global, per-span export, never shut down — needs decision: lifecycle design — decided 2026-10-06: add stop() that flushes and shuts down the SDK, called from the services stop (done: swissknife 9740ee9..0c1bdb8, 1.0.47)

## 10. pillar

- [x] 10.9 **L** `MessagingEventProcessor` logs payloads at INFO — needs decision: real; log policy — decided 2026-10-07: remove the generic received/processed/ignored INFO logging from MessagingEventProcessor; each consumer, processor or producer decides what to log and when. Keep the error log on failure and retry, so failures aren't silent (done: pillar ce6582c..c49dfaa, 1.0.28)
- [x] 10.18 **L** OpenAPI rule tests never exercise JSON example rules — JSON request/response example tests added; exampleSchemaComplianceRule still untested (needs $ref fixtures) — decided 2026-10-07: closed: swissknife now tests the examples rule directly
- [x] 10.19 **L** `JvmGcMetrics`/`JvmHeapPressureMetrics` never closed — needs decision: real; API for binder lifecycle — decided 2026-10-07: close the GC and heap-pressure binders when the meter registry stops (done: pillar ce6582c..c49dfaa, 1.0.28)
- [x] 10.26 **M** JSON locale serdes lack the `no_NO_NY` special case — needs decision: real; changes the JSON wire format — decided 2026-10-07: add the no_NO_NY special case to the JSON locale serdes, with a test (done: pillar ce6582c..c49dfaa, 1.0.28)
- [x] 10.27 **M** Leaf JSON serdes have no schema-compliance tests — compliance tests added for 5 leaf serdes; actor leaves fail AcmeJsonSchemaRules (needs catalogue or rule change) — decided 2026-10-07: fix the catalogue's actor schemas to satisfy the rules, then add the compliance tests (acme 4e74575; pillar done pillar ce6582c..c49dfaa, 1.0.28; services done: modulith 93a3682, element 20a3775)

## 11. modulith-example

- [x] 11.1 **H** Production payment module wired to an always-success stub — needs decision: real; response contract — left to the owner (2026-10-06): building the processor and the NATS outcome round trip is his to do later
- [x] 11.2 **H** No check that the caller owns the source account — needs decision: real; authorisation — decided 2026-10-06: the account-event-processor checks ownership when handling the command and publishes a rejection; recorded as a README requirement and a TODO on the unimplemented handler (built with 11.8)
- [x] 11.3 **M** Fresh event id per request and publish-before-wait: retries double-apply — needs decision: real; idempotency — left to the owner with 11.1 (same piece of work)
- [x] 11.6 **L** Payment module test asserts status only — needs decision: real; right expectation depends on 11.1 — left to the owner with 11.1 (same piece of work)
- [x] 11.8 **H** account-event-processor handlers all TODO (unwired); README says Done — needs decision: real; README section left as is — left to the owner with 11.1 (same piece of work)
- [x] 11.10 **M** No positive-amount check on payments/deposits — needs decision: real; domain rule — left to the owner with 11.1 (same piece of work)
- [x] 11.11 **L** `AccountEvent.avsc` wrong record name (see 4.1) — needs decision: see 4.1 — decided 2026-10-06: with 4.1 (done: acme 4e74575, modulith 93a3682)
- [x] 11.12 **L** Publisher log says "compliance plan event" and leaks amounts — log text fixed; needs decision: logging full events at INFO — decided 2026-10-07: closed: the publisher's own logging is its choice; keep it at INFO
- [x] 11.16 **L** Random node name; `INSTANCE_*` env vars never read — needs decision: real; instance identity — decided 2026-10-07: build ServiceInfo from INSTANCE_NODE_NAME (the charts aren't used, leave them). The 2-container Docker test must keep distinct names per container: the container factory already defaults to a random name per call, so verify it still passes (done: modulith 93a3682..596c960; 2-container test green)
- [x] 11.18 **L** Registry auth lookup result discarded — needs decision: real; delete or wire Docker auth — decided 2026-10-07: delete the lookup; registry login comes from the Docker config (done: modulith 93a3682)
- [x] 11.19 **L** Partitioned topic only pre-created in tests — needs decision: real; provisioning — left to the owner with 11.1 (same piece of work)

## 12. element-service-example

- [x] 12.3 **M** Chart image repositories/tags don't match the images the build produces — needs decision: real; registry/tags — decided 2026-10-07: closed: the charts aren't used
- [x] 12.4 **M** No startupProbe; liveness budget shorter than startup — needs decision: real; probe budget — decided 2026-10-07: add a startupProbe on /liveness with a budget of at least 60s (done: element 20a3775..7d21ad1)
- [x] 12.5 **M** Trivy scans only the service image, not the migrator — needs decision: real; scan scope — decided 2026-10-07: Trivy also scans the migrator image (done: element 20a3775..7d21ad1)
- [x] 12.9 **M** Pulsar config overrides dropped (see 9.22 — blocked on 9.22 (needs decision); no change needed in this repo once fixed upstream — fixed with 9.22
- [x] 12.10 **M** Random instance id; `INSTANCE_NODE_NAME` never read — needs decision: real; instance identity — decided 2026-10-07: same as 11.16: build ServiceInfo from INSTANCE_NODE_NAME, keeping the 2-container Docker test working (done: element 20a3775..7d21ad1). The registry-auth lookup in element's container test follows 11.18: delete it (done: element 20a3775..7d21ad1)
- [x] 12.11 **M** R2DBC without a connection pool — needs decision: real; pool choice — decided 2026-10-07: use r2dbc:pool:postgresql:// via r2dbc-pool (done: element 20a3775..7d21ad1)
- [x] 12.12 **L** `stop()` doesn't close clients; first failure skips the rest — needs decision: real; stop-failure policy, and nothing to close until 12.11 — decided 2026-10-07: stop modules in reverse order with runCatching, then close the Pulsar and R2DBC clients in finally (done: element 20a3775..7d21ad1)
- [x] 12.13 **L** Health server starts before the main server — needs decision: real — decided 2026-10-07: start the main HTTP server before the health server, in element and modulith (same order there) (done: element 20a3775..7d21ad1)
- [x] 12.14 **L** `default-configuration.yml` never loaded — needs decision: real; delete or load — decided 2026-10-07: delete default-configuration.yml: its port 0 defaults would mean random ports, and its instance.* keys are stale (done: element 20a3775..7d21ad1)
- [x] 12.16 **M** Migrations use `DROP TABLE` (data loss on upgrade) — needs decision: real; applied changesets must not be edited — decided 2026-10-07: closed: no data yet, migrations can change freely
- [x] 12.17 **M** `Standard.equals` compares only reference and publication (hides serde bugs, collapses sets) — needs decision: real; equality semantics — decided 2026-10-07: keep Standard equality on reference and publication; round-trip tests compare all fields (done: element 20a3775..7d21ad1)
- [x] 12.18 **L** Requirement `Standard`/`Clause` `compareTo` inconsistent with `equals` — needs decision: real — decided 2026-10-07: extend Standard/Clause compareTo to every field equals uses (done: element 20a3775..7d21ad1)
- [x] 12.20 **L** `Market`/SDO accept any name; Avro enums are closed — needs decision: real — decided 2026-10-07: validate Market and SDO names in init against the known codes (done: element 20a3775..7d21ad1)
- [x] 12.31 **L** Uncommitted `.trivyignore` change (also modulith) pending a security-scan run — untouched as instructed — decided 2026-10-07: run the security scan during implementation; commit the .trivyignore change (element and modulith) if it passes (done: element 20a3775..7d21ad1)
- [x] 12.34 **H** Re-storing requirements resets applicability decisions — needs decision: real; applicability semantics after re-analysis — decided 2026-10-06 (revised): re-storing keeps the decision of every requirement still present (by id); new ones start undecided, removed ones go; repository-spec test
- [x] 12.37 **M** `limit` 0/negative/unbounded — uncertain: real; max limit and validation location are choices — decided 2026-10-07: reject limit outside 1..MAX (MAX from configuration) as a protocol error: enforce it in the request schema so validation returns 400 (done: element 20a3775..7d21ad1)
- [x] 12.38 **M** Plan upsert has no version guard — needs decision: real; versioning scheme — decided 2026-10-07: closed if in-place retry keeps per-key order: verify the plan events are keyed by plan id during implementation (done: element 20a3775..7d21ad1)
- [x] 12.46 **H** CSV fields never quoted/escaped (formula injection, corrupt rows) — RFC-4180 quoting/escaping fixed (new CSVRow, tests); needs decision: spreadsheet formula prefixing alters data — decided 2026-10-07: prefix cells starting with =, +, - or @ with ' (OWASP) (done: element 20a3775..7d21ad1)
- [x] 12.47 **M** Missing plan treated as entitled — needs decision: real; not-found semantics — decided 2026-10-07: error statuses are only for protocol errors; an existing path that finds no record returns 200 with an explicit not-found result, not an empty page or header-only CSV. Applies everywhere (done: element 20a3775..7d21ad1)
- [x] 12.48 **M** Writes before publish not transactional — needs decision: real; transaction boundary — decided 2026-10-07: write plan, report and outputs in one transaction (done: element 20a3775..7d21ad1)
- [x] 12.49 **L** CSV dates depend on JVM locale — needs decision: real; date format — decided 2026-10-07: CSV dates as ISO yyyy-MM (done: element 20a3775..7d21ad1)
- [x] 12.50 **L** CSV has no BOM — needs decision: real; BOM — decided 2026-10-07: add a UTF-8 BOM to the CSVs (done: element 20a3775..7d21ad1)
- [x] 12.55 **L** Repository spec missing re-store/empty/null-edition cases — empty-set and null-edition cases added; re-store-keeps-applicability depends on 12.34 — re-store-keeps-decisions case added with 12.34
- [x] 12.57 **L** "Nonexistent plan" test uses a stub that always returns a plan — misleading name fixed; a real missing-plan test depends on 12.47 — decided 2026-10-07: add a real missing-plan test expecting the 200 not-found result (done: element 20a3775..7d21ad1)
- [x] 12.60 **H** Ingestion only checks "authenticated" (no role/customer check) — needs decision: real; authorisation — decided 2026-10-06: the gateway restricts event endpoints to allowed machine clients (GATEWAY.md); services trust them
- [x] 12.63 **M** No idempotency on ingestion — needs decision: real; idempotency — skipped 2026-10-06 (example): documented in element IMPROVEMENTS.md (issue + improvement 9, idempotency-keyed rotating table)
- [x] 12.64 **L** Always 200, even on `ApplicationResult.Error` — needs decision: real; status for a currently unreachable Error — decided 2026-10-07: closed: 200 for business outcomes matches the protocol-errors-only rule (12.47)
- [x] 12.66 **H** Notifier serde writes fields its schema forbids; untested — needs decision: real; unclear whether the serde shape or the flat email-contract schema is intended — decided 2026-10-06: schemas now describe the nested plan the serde sends; schema-compliance test over the notification event (fails on the old schema)
- [x] 12.67 **M** Lifecycle notifications lose the parent message id — needs decision: real; notifier interface change — decided 2026-10-07: pass the parent message id through the notifier interface (done: element 20a3775..7d21ad1)
- [x] 12.71 **M** Round-trip tests can't detect dropped optional fields (see 12.17) — needs decision: see 12.17 — decided 2026-10-07: covered by 12.17: round-trip tests compare all fields (done: element 20a3775..7d21ad1)
- [x] 12.72 **M** Body not schema-validated; no size limit (gzip bomb) — proposed close: body size limits are the gateway's job (awaiting confirmation) — decided 2026-10-07: validate request bodies against the schema (400 on failure); body size limits are the gateway's job: add them to pillar's GATEWAY.md job list (done: element 20a3775..7d21ad1)
- [x] 12.73 **L** Contract tests happy path only — needs decision: an Error contract case would lock in 12.64 — decided 2026-10-07: no contract case: cover not-found locally with an application test (returns the not-found result) and a result serde test (wire form and schema compliance) (done: element 20a3775..7d21ad1)
- [x] 12.77 **H** Upsert overwrites newer state (redelivery regresses plans) — needs decision: real; ordering guard design — skipped with 12.63 (stale re-posts are the remaining case; documented)
- [x] 12.79 **M** `limit` not validated — needs decision: real; limit bounds — decided 2026-10-07: covered by 12.37 (done: element 20a3775..7d21ad1)
- [x] 12.83 **L** Null customer becomes `'null'` — null customer now binds SQL NULL (no `'null'` literal); needs decision: reject with 403 instead of empty 200 — decided 2026-10-07: no customer returns 403 (authorisation is a protocol error) (done: element 20a3775..7d21ad1)
- [x] 12.87 **L** `ApplicableRequirementsOutputsAvailable` not handled — uncertain: nothing produces the event yet — decided 2026-10-07: closed: covered by N.4 (unhandled types acked without decoding)
- [x] 12.89 **L** Full results logged at INFO — needs decision: log policy — decided 2026-10-07: closed: each component decides its logging (see 10.9); keep it
- [x] 12.90 **L** `toAuthenticated` runs handlers in `runBlocking` — needs decision: shared pillar API — decided 2026-10-07: always coroutine-native HTTP bindings on top of virtual-thread executors, everywhere (pillar, swissknife, all services); verified 2026-10-07: both servers (swissknife HttpApi, LocalWebService) run on http4k JettyLoom (virtual threads), and every request is bridged with runBlocking(MDCContext()) in swissknife SuspendingHttpHandler.asBlockingHandler and in pillar RoutingExtensions (toAuthenticated, toUnauthenticated, withContext); Http4kServiceReadinessUtils also runBlocks. Replace these bridges — decided 2026-10-07 (revised): http4k is synchronous; keep a single runBlocking bridge as high as possible, close to the http4k handler. No change now.

## New (from the redo and the 2026-10-06 review)

- [x] N.1 **L** package-migrator: migrating `a.b` → `a.b.v2` still fails in the directory phase (moves a directory into itself) — decided 2026-10-06: move through a temporary location, with a test (done: tools 6630667, b7b39b1; also fixed emptied source directories left behind and the single-segment package name/path clash)
- [x] N.2 **H** Pulsar 5 — done 2026-10-07: running on Pulsar 5.0.0. Root cause of the hang: slog 0.10.0 (via Pulsar 5) restores absent MDC keys with null, and swissknife Slf4jMDCAdapter.put rejected null, crashing Pulsar I/O threads. Fixed in swissknife 1.0.50 (null removes the key, with tests); examples and modulith Pulsar tests green
- [x] N.4 **H** Evolving topics with new event types (decided 2026-10-06; done: (1)(2) swissknife 5573aef.., (3) pillar ce6582c.., services adapted): (1) swissknife namespace compatibility default `BACKWARD_TRANSITIVE` (FULL_TRANSITIVE rejects new union branches); (2) lint rule: a topic's value schema reaches its events through a union; (3) pillar's processor checks the event-type header before decoding and acks unhandled types without deserialising them (handlers declare the types they handle), tested with an undecodable payload of an unhandled type
- [x] N.3 **L** Readability leftovers: one failure-injection style in the two `CompliancePlanEventProcessingTests`; Pulsar client closing style in the outputs-manager module spec; package-migrator relative-path helper — decided 2026-10-06: tidy all three (done: tools 6630667; element e7bd610)
