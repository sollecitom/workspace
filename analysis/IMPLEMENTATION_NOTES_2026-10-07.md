# Implementation of the bug-hunt decisions — notes to discuss

## To discuss
- facts 8.2: TicTacToeMatch getters became suspend functions (honest API, also fixed a check-then-act race across separate replays). Alternative: live StateFlow projection, or revert to runBlocking. Owner to confirm.

- 12.90 (coroutine-native HTTP bindings) skipped: http4k's HttpHandler, Filter and routing are synchronous, so a suspend handler can only run behind a blocking bridge. Truly coroutine-native means replacing http4k routing and filters (pillar gateway, logging, context, OpenAPI filters) with a suspend-native stack (Ktor, or a home-grown suspend router on a virtual-thread dispatcher). Same for readiness (http4k ReadinessCheck is synchronous; it got the 5s timeout only). Architecture decision for the owner.

## Worth mentioning
- swissknife 9.2: hand-written monotonic UUIDv7 generator (uses the injected random and clock), with tests.
- swissknife 9.6: truncating division changed an existing expectation (30.22/2.67: 11.32 → 11.31).
- swissknife 9.4: Id.fromString no longer infers ULID/UUID; typed form `ulid:…`, `ksuid:…`, `uuidv7:…`, `uuid:…`, `string:…`.
- swissknife 9.40: ciphertext format changed (owner bound as associated data); fine given no data.
- swissknife: a consumer's name/subscriptionName throw until start().
- swissknife: JSON-metaschema tests need the JVM proxy settings in this sandboxed environment (JAVA_TOOL_OPTIONS https.proxyHost=localhost, proxyPort=10054); not a code issue.
- lattice depends on swissknife but uses none of the changed APIs (grep); only its version bumps.
- quality-scorer: usage errors are a dedicated InvalidInputException (b5452b6); Main exits 2 only for those.
- facts and quality-scorer catalogs bumped by `just build` (facts swissknife 1.0.26 → 1.0.46), confirmed by owner.
