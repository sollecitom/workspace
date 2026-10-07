# Implementation of the bug-hunt decisions — notes to discuss

## To discuss
- facts 8.2: TicTacToeMatch getters became suspend functions (honest API, also fixed a check-then-act race across separate replays). Alternative: live StateFlow projection, or revert to runBlocking. Owner to confirm.

- Gateway: JWT.isValidAtTime now also checks nbf (9.47), and the gateway stub's isNotExpired() uses it, so the gateway now rejects tokens before nbf. GATEWAY.md asks for this, but it's a behaviour change in the untouched stub (alternative: switch the stub to isNotExpiredAt).
- N.4(3): handledTypes is an explicit set per processor factory call (ProcessEvent lives in swissknife, so it isn't declared on the handler). Unhandled types are acked silently, with no log (each component decides its logging). A message with no event-type property halts in the retry loop and logs.
- Composition style (left to right): applied to code written or touched in this round. A workspace-wide sweep of existing inside-out calls? Owner to decide.

- examples 7.6: money is Avro bytes decimal with scale 2, not 0: these amounts have cents (9.95, price per share); scale 0 would mean renaming fields to minor units. Keep scale 2, or switch to integral minor units?
- modulith never wires accountEventProcessor into the service (only the deposit and payment endpoints are modules). Left alone (related to skipped 11.1).
- examples' PulsarMessagingTests now overlap swissknife's own PulsarMessagingTests (9.116). Keep both, or trim examples?
- Tests that fetch the JSON Schema metaschema over the network (swissknife openapi-checking, pillar JSON) fail without network access (here: they need the sandbox proxy). Bundle the metaschema as a resource to make them hermetic?
- Page size maximum: element picked 100; the structure pass puts `maximum: 100` in acme's PaginationArguments (one source; no configuration value needed since the bound lives in the schema). Confirm 100 for all Acme APIs.
- element 12.83: the 403 for a missing customer has an empty body.
- element dispatch is now a map from event type to handler, and handledTypes is its keys (no drift). A type missing from the map can no longer reach a handler; if it somehow did, it throws and the processor retries in place (halts), consistent with D1.
- swissknife keeps createR2dbcClient() unpooled (used by tests) next to the new createPooledR2dbcClient(); production uses the pooled one. Keep both, or make pooled the only one?
- Undecodable payloads: default reaction is exitProcess(1) (on a separate thread, after one ERROR log, consumption stopped, never acked). It's a library default in pillar; services can pass their own onUndecodableMessage. OK as the default, or should the service own it explicitly (no default)?
- "Handled" event types are matched by NAME: an unknown version of a handled name is not acked; it reaches the handler, whose type lookup fails, so it retries in place and halts loudly. Confirm.
- swissknife id predictability (review finding): untouched, awaiting your call (options given).

## Worth mentioning
- element: every to-do done; 2-container test and both image scans green. 12.38 verified (plan events keyed by plan id, Failover subscription): no version guard needed.
- element: the viewer now stores plan and customer ids as typed strings (consequence of 9.4).
- element 12.48: plan, report and outputs written in one transaction via new storeStandardsOutputs/storeRequirementsOutputs repository methods, with a Postgres test that a failed write stores nothing.
- Structure pass (tier-0): element's helpers moved upstream (body schema validation in swissknife's body lens, R2DBC pooling in createR2dbcClient, toCustomerScoped in pillar), duplications reduced; see the final report.
- N.2 solved: Pulsar 5.0.0 works. The hang was swissknife's Slf4jMDCAdapter.put rejecting null: slog 0.10.0 (via Pulsar 5) restores absent MDC keys with null on Pulsar I/O threads. Fixed in swissknife 1.0.50.
- modulith: in-process, 2-container and security-scan tests all green; the .trivyignore change was already committed (9c7ce73) and the scan passes.
- modulith's security-scan test classpath prints SLF4J 1.x "StaticLoggerBinder" warnings (an old slf4j-api 1.x from a scan dependency); harmless.
- 12.90: decided, no change. A single runBlocking bridge, as close to the http4k handler as possible.
- swissknife 7eb8a13 (1.0.48): the Avro builder and getters encode BigInteger/BigDecimal as decimal bytes when the field is a bytes decimal (else string as before). Pillar's CurrencyAmount serde now uses it (c49dfaa) instead of hand-building a GenericData.Record.
- pillar 4.5: Avro AuthenticatedAccess writes is_test; on read it's ignored (like JSON), because the domain derives it from the actor.
- pillar 9.40: no pillar main code builds accessible protected values; swissknife's ProtectedValue.loggingAccessHook() is the standard hook.
- pillar 12.72: GATEWAY.md already listed body size limits; body schema validation is per service (pillar has no shared body parsing).
- swissknife 9.2: hand-written monotonic UUIDv7 generator (uses the injected random and clock), with tests.
- swissknife 9.6: truncating division changed an existing expectation (30.22/2.67: 11.32 → 11.31).
- swissknife 9.4: Id.fromString no longer infers ULID/UUID; typed form `ulid:…`, `ksuid:…`, `uuidv7:…`, `uuid:…`, `string:…`.
- swissknife 9.40: ciphertext format changed (owner bound as associated data); fine given no data.
- swissknife: a consumer's name/subscriptionName throw until start().
- swissknife: JSON-metaschema tests need the JVM proxy settings in this sandboxed environment (JAVA_TOOL_OPTIONS https.proxyHost=localhost, proxyPort=10054); not a code issue.
- lattice depends on swissknife but uses none of the changed APIs (grep); only its version bumps.
- quality-scorer: usage errors are a dedicated InvalidInputException (b5452b6); Main exits 2 only for those.
- facts and quality-scorer catalogs bumped by `just build` (facts swissknife 1.0.26 → 1.0.46), confirmed by owner.
- tools N.1/N.3 (6630667, b7b39b1): migrating into a subpackage works (two-step move through a temporary package); emptied source directories are deleted up to the source-set root; a single-segment source package is rewritten as a name or a path by context (a single segment right after a separator and followed by a dot, like `/a.properties`, reads as a path — inherently ambiguous).
- Structure pass: acme 1.0.11 (PaginationArguments maximum 100); swissknife 1.0.51/1.0.52: JSON body lenses validate against schema-aware serdes (400 on mismatch; modulith gets it automatically), createPooledR2dbcClient + DatabaseClient.close(), ImageSecurityScanTestSpecification (scan tests are one-liners); pillar 1.0.29: toCustomerScoped next to toAuthenticated; element: local helpers and BoundedPaginationArguments.json deleted, probe initial delays removed (startupProbe gates them), known Market/SDO codes in one private enum, N.3 test tidy-ups.

## Decisions from the 2026-10-07 discussion (to do unless noted)
- Undecodable default: keep ERROR + exit, but template it: one reusable fatal-error mechanism ("log ERROR loudly, stop, exit non-zero") that any situation needing this behaviour can use, not specific to the event processor (to do).
- Gateway nbf rejection: keep.
- examples money: keep scale 2.
- Page-size maximum 100 in acme PaginationArguments for every Acme API: confirmed.
- R2DBC: owner leans to keeping both; if unpooled is never needed, pooled only — pending my answer.
- JSON metaschema: bundle as a resource so tests are hermetic (to do).
- Pulsar tests are heavy: measure build time and optimise; very thorough deep dive on Gradle build performance across the workspace (to do).
- Randomness (revises 9.7): production (no seed configured) uses an unseeded SecureRandom for both random and secureRandom, nothing logged; tests (seed configured) seed everything, so id generation stays reproducible in tests, with the test-only warning. Reproducing prod issues = replaying the recorded inputs with a configured seed (to do).
- Handled event types match by NAME (business logic, not versioning): confirmed; already implemented in pillar.
- R2DBC: keep both createR2dbcClient (unpooled) and createPooledR2dbcClient.
- Left-to-right composition: sweep every repo (lattice excluded: no lattice code edits) (to do).
- facts 8.2: revert the TicTacToeMatch suspend getters back to the previous shape (runBlocking projection); keep 8.1 and 8.3 (done: facts 3e70250).
- modulith account event processor wiring: leave for 11.1.
- Email empty-label check: keep. parseContent resolving refs by default: keep.
- element: repositories take the customer passed by toCustomerScoped instead of re-reading the invocation context (it's redundant) (to do).
- element viewer: store the customer id type alongside its value (filter by value, return the typed id the event carried) (to do).
- Pending: handled-by-name semantics (explained), composition sweep (unanswered), examples/swissknife Pulsar test overlap (folded into the build-performance dive).
