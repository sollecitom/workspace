# Verification: swissknife cryptography, protected-value, jwt, keycloak, security, sql (9.30–9.64) and `.gitignore`

Refs: base `3f1d24b`, snapshot `bug-hunt-snapshot-2026-10-05` (= `92ee316`, current HEAD). Read-only checks only. Nothing was built or run. "Would the test fail at base" was worked out by reading the code.

Scope: the items marked fixed, 9.58 (marked not-a-bug, but a test was added), 9.64 (partly addressed), and the `.gitignore` split (attributed to 4.14). 9.44–9.46 are deferred and change nothing in swissknife, so they are not scored here.

### 9.30 — `AESKeyAdapter.toString()` leaks the raw key
- Defect in base: REAL — `AESKeyAdapter.kt:50` `toString() = "JavaAESKeyAdapter(encoded=${encoded.contentToString()}, keySpec=${keySpec})"`. `SymmetricKeyWithEncapsulation.kt:23` embeds `key=$key`, so it leaks through that class too. The other key adapters are data classes that wrap JCA/BC keys, and those do not print private bytes. AES was the only leak.
- Fix: CORRECT — now `"AESKeyAdapter(algorithm=$algorithm, format=$format, hash=$hash)"`. The hash is a Blake3-256 fingerprint, which is already used as key metadata in ciphertexts, so printing it is not a leak. A spec test in `CryptographyTestSpecification` checks both `toString`s against `contentToString()` and the hex form. It would fail at base. The change is minimal and nothing else changed with it.
- Principles: none
- Importance: 4 — a secret key gets written to logs whenever a key or a key-with-encapsulation is logged. No logging call site exists today.
- Confidence: 5 — the code shows it directly.
- Recommendation: REDO AS IS

### 9.31 — `SigningPrivateKey.sign(String)` has a type parameter that can't be inferred
- Defect in base: REAL — `SigningPrivateKey.kt:11` `fun <OPTIONS> SigningPrivateKey.sign(input: String, ...)`. `OPTIONS` is never used, so any call fails with "not enough information to infer". There are no callers in swissknife, pillar, the two examples or lattice.
- Fix: CORRECT — `<OPTIONS>` removed. One token. No test, and none is needed.
- Principles: none
- Importance: 2 — a public helper that can't be used. Nobody calls it.
- Confidence: 5
- Recommendation: REDO AS IS

### 9.32 — The injected `SecureRandom` is ignored for signing and AES key generation
- Defect in base: REAL — `BouncyCastleUtils.kt:27` `sig.initSign(privateKey, SecureRandom())`, and `:46` `keyGenerator.init(length)` with no random source. Every other BC call in the file already receives `random`.
- Fix: CORRECT — `random` is added to `sign` and `generateSecretKey` and passed in from `JavaSigningKeyAdapter` and `AESKeyAdapter.Factory`. The public `BouncyCastleUtils` signatures changed, but nothing downstream calls these two functions. Two tests use a constant-random `SecureRandom` and expect equal AES keys and equal ML-DSA signatures. Both would fail at base. All callers of `bouncyCastle(random)` outside swissknife are tests in pillar that use a seeded `secureRandom`. Their keys and signatures become deterministic, which is harmless. Note the link to 9.7 (seeded random): a production caller passing a seeded random would now get predictable AES keys. Today no production caller passes one.
- Principles: none
- Importance: 2 — production uses the default `SecureRandom()` either way. Only determinism and RNG-policy control are affected.
- Confidence: 5
- Recommendation: REDO AS IS

### 9.36 — No IEEE 1619 vectors for XTS lengths that aren't whole blocks
- Defect in base: REAL (test gap) — base `XtsAesTests` checks vectors 1, 2 and 10 (all block-aligned). Ciphertext stealing is only round-trip tested (`CiphertextStealing`), so a stealing implementation that is consistent with itself but non-standard would pass.
- Fix: CORRECT — one test with IEEE 1619-2007 vectors 15–18 (key `fffefd…f0`/`bfbebd…b0`, data unit `0x123456789a`, which `tweakOf` encodes little-endian). The expected ciphertexts match the published vectors as far as I recall them. The snapshot reports the test passing, so it adds coverage, not a fix. The style is fine: literal expectations and no comments.
- Principles: none
- Importance: 3 — a test that could not catch regressions in ciphertext stealing.
- Confidence: 4 — vectors checked against memory of the standard, not executed.
- Recommendation: REDO AS IS

### 9.37 — Cryptography READMEs say CTR
- Defect in base: REAL — `cryptography/domain/README.md:3` "(CTR with metadata)" and `bouncy-castle/README.md:3` "CTR-mode". The code only has `EncryptionMode.GCM` and `EncryptionMode.XTS`. There is no CTR anywhere in base code.
- Fix: CORRECT — both now say GCM/XTS. Docs only.
- Principles: none
- Importance: 2 — the docs are wrong.
- Confidence: 5
- Recommendation: REDO AS IS

### 9.41 — Vacuous `ByteArray` vs `String` assertion in `AesProtectedValueTests`
- Defect in base: REAL — `AesProtectedValueTests.kt:38` `assertThat(protectedValue.value).isNotEqualTo(originalValue)` compares a `ByteArray` with a `String`, so it can never fail.
- Fix: CORRECT but redundant — now `isNotEqualTo(originalValue.toByteArray())`. assertk 0.28.1 has `Assert<ByteArray>.isNotEqualTo(ByteArray)` (checked in the jar), so the comparison is by content. Line 40, `assertThat(String(protectedValue.value)).isNotEqualTo(originalValue)`, already asserts exactly the same thing.
- Principles: none
- Importance: 1 — a dead assertion that sits next to an equivalent live one.
- Confidence: 5
- Recommendation: REDO MODIFIED: delete line 38 instead, since line 40 already covers it. Keeping the snapshot version is also fine.

### 9.42 — Protected-value README and CONTEXT say AES-CTR
- Defect in base: REAL — `protected-value/factory/aes/README.md:3` "AES-CTR-256" and `CONTEXT.md:36` "AES-CTR". The implementation is `GcmAes256ProtectedValueFactory` (`aes256WithGCM`).
- Fix: CORRECT — both say AES-256-GCM / AES-GCM.
- Principles: none
- Importance: 2
- Confidence: 5
- Recommendation: REDO AS IS

### 9.43 — `JoseJwtAdapter` throws NPE when `iat`/`iss`/`jti`/`sub` are absent
- Defect in base: REAL — `JoseJwtAdapter.kt:14,16` evaluate `issuerId` and `issuedAt` eagerly from nullable jose4j getters, so construction throws an NPE. That hits `readWithoutVerifying` for any token without `iss` or `iat`, and `readAndVerify` with `requireIssuedAt = false`, a supported `newJwtProcessorConfiguration` option. `id`/`subject` (`:11-12`) throw an NPE only when read.
- Fix: CORRECT (minimal) — all four are now lazy getters using `checkNotNull(...) { "The JWT has no 'x' claim" }`. Construction no longer fails, and reading a missing claim throws `IllegalStateException` with a clear message. Both new tests would fail at base: `readWithoutVerifying` without iss/sub/jti/iat, and `readAndVerify` with `requireIssuedAt=false`. Downstream, pillar only reads `claimsAsJson` and `isValidAtTime`, so there are no regressions.
- Principles: possibly 5. RFC 7519 makes `iss`/`sub`/`jti`/`iat` optional, and the interface already types `expirationTime`/`notBeforeTime` as nullable. A general-purpose `JWT` contract would type these four as nullable too. Keeping them non-null and throwing on read is the "minimal behaviour" option. This is not gateway policy (principle 3), only parsing robustness.
- Importance: 3 — a latent crash on a non-default path. No consumer uses `readWithoutVerifying` or `requireIssuedAt=false` today.
- Confidence: 5 — traced. The original finder also confirmed in jshell that the getters return null.
- Recommendation: REDO MODIFIED: make `id`, `subject`, `issuerId` and `issuedAt` nullable in `jwt/domain/JWT.kt`, mapped with `?.let`. No consumer outside swissknife reads them. Keep both tests and assert `isNull()` for the missing claims. The snapshot's `checkNotNull` approach is an acceptable fallback if the owner prefers non-null types.

### 9.48 — JWT tests only cover happy paths
- Defect in base: REAL (test gap) — base `JwtExampleTests` has no negative cases.
- Fix: CORRECT, INCOMPLETE against the finding — 4 negative tests: expired token, wrong key with the same issuer id, wrong issuer, tampered payload. All expect `InvalidJwtException`. They pass at base, as expected for a coverage gap. The finding's "wrong audience" and "alg outside the allow-list" cases are not covered, which fits with audience/alg policy being deferred to the gateway (9.44–9.46). Style is fine.
- Principles: none. The tests pin jose4j verification and add no policy.
- Importance: 2 — protects against regressions in verification wiring. Risk is low today.
- Confidence: 5
- Recommendation: REDO AS IS

### 9.49 — Keycloak `adminClient` ignores its `password` argument
- Defect in base: REAL — `KeycloakContainerExtensions.kt:20` `.password(adminPassword)` while the function takes `password: String = adminPassword`.
- Fix: CORRECT — `.password(password)`. No test, and there are no callers anywhere. `customize()` also runs first in `adminClient`, but every value it could set there is an explicit parameter, so that is not a bug.
- Principles: none
- Importance: 3 — logging in as any non-admin user always fails. It is test infrastructure and currently unused.
- Confidence: 5
- Recommendation: REDO AS IS

### 9.50 — Keycloak `newContainer` applies `customize()` before the defaults
- Defect in base: REAL — `Keycloak.kt:21` `KeycloakContainer(imageName).customize()`, followed by `withAdminUsername`/`withAdminPassword`/`withStartupAttempts`/`withStartupTimeout`/`withRamPercentage`. Anything set in `customize` for those is overwritten.
- Fix: CORRECT — `customize()` is now applied last. The new `KeycloakContainerConfigurationTests` builds a container without starting it and checks the customised admin username and password. It would fail at base and doesn't need Docker, because the container is never started. The only consumer, the disabled example test, calls `newContainer()` with no customisation.
- Principles: none
- Importance: 2 — each overwritten setting already has an explicit parameter, so this only bites people who use `customize` for them.
- Confidence: 4 — the test is assumed to run without a Docker daemon (the testcontainers constructor is lazy). Not executed.
- Recommendation: REDO AS IS

### 9.51 — The disabled Keycloak example test can't pass if re-enabled
- Defect in base: REAL — `KeycloakExampleTests.kt:82` `delay(timeout)` equals the test timeout. `:134-143`: the client is created without `clientId` and then fetched with `clients().get(representation.clientId)`, but that call needs the internal id. `:90`: `authzClient` passes `client.id` (the UUID) as the OAuth client id.
- Fix: CORRECT — sets `clientId = name`, uses `findByClientId(name).single()`, `get(representation.id)` (also in `clients()`), adds `Client.clientId`, passes `client.clientId` to `AuthzClient`, and removes `delay`. Test code only, still `@Disabled`. The checklist says it was run once against Keycloak 26.8.0; that run can't be verified here.
- Principles: none. Note that `delay(timeout)` may have been deliberate, to keep the container up for manual poking during exploration (the `@Disabled` TODO talks about the exploratory phase). The owner should confirm before removing it.
- Importance: 1 — a disabled exploratory test.
- Confidence: 3 — the code trace is clear. The claim that it passes end to end is unverified.
- Recommendation: REDO AS IS (keep `delay` only if the owner uses it for manual exploration)

### 9.52 — Trivy scanner `return@repeat` retries failures that aren't worth retrying
- Defect in base: REAL — `TrivyImageScanner.kt:74-93`: `return@repeat` inside `repeat(maximumAttempts)` acts as `continue`. A missing image (`isWorthRetrying == false`) is re-run `maximumAttempts` times without the delay, and the failure always reports `maximumAttempts` attempts.
- Fix: CORRECT for the loop. It is now `for (attemptIndex in 0 until maximumAttempts)` with `break`, and `attempts` is tracked and reported accurately. Minimal.
  The new test is questionable. `a scan of a missing image fails after a single attempt` runs Trivy in Docker against a nonexistent image. That needs Docker, pulls the Trivy image, and has Trivy initialise its vulnerability DB over the network before it fails on the image. That DB download is exactly the flaky step (`unexpected EOF`) that `isWorthRetrying` retries. When it flakes, the run gets retried and the "after 1 attempt(s)" assertion fails. Every other test in that class is a pure unit test. It would fail at base ("after 3 attempt(s)").
- Principles: none
- Importance: 2 — security-scan tooling. The bug only adds wasted retries and a misleading attempt count. It doesn't cause a false pass.
- Confidence: 5 for the defect and fix. 3 for the flakiness concern.
- Recommendation: REDO MODIFIED: apply the `for`/`break` fix and drop the Docker/network test. If coverage is wanted, pull the retry loop out into a function that takes the attempt as a lambda and unit-test that.

### 9.54 — Security-scan README names a nonexistent API, plus a "stale" KDoc claim
- Defect in base: PARTLY.
  - README part: REAL. `security/scan/README.md:3` cites `assertDockerImageHasNoVulnerabilities()`, which doesn't exist. The API is `assertThatImage(...).hasNoUnacceptableVulnerabilities()` (`DockerImageSecurityAssertions.kt:8,31`).
  - KDoc part: NOT REAL. The finding said nothing in the workspace sets `securityScan.trivyIgnoreFile`. It is set: `gradle-plugins/components/base/src/main/kotlin/sollecitom/plugins/conventions/task/security/scan/SecurityScanConvention.kt:122-123` adds `-DsecurityScan.trivyIgnoreFile=…` to the `securityScan` test task's JVM args. That file is untouched by the overnight gradle-plugins patch.
- Fix: INCORRECT (half). The README fix is right. Removing "(set by the Gradle `securityScan` convention)" from the `hasNoUnacceptableVulnerabilities` KDoc deletes a true statement and makes the docs worse.
- Principles: none
- Importance: 2 — docs accuracy.
- Confidence: 5 — the gradle-plugins source shows it directly.
- Recommendation: REDO MODIFIED: apply the README change only. Leave the KDoc in `DockerImageSecurityAssertions.kt` as it was in base.

### 9.58 — Indexed `bindNullable` uses primitive classes
- Defect in base: NOT REAL — `StatementUtils.kt:13` `bindNull(index, T::class.java)` with a `reified T`. A reified type argument is substituted as its boxed class, so `T::class.java` is `java.lang.Integer` for `Int` and so on. The named variant's `javaObjectType` is equivalent here.
- Fix: no code change. Only `StatementUtilsTests` was added, asserting boxed classes for both variants. It passes at base by construction and pins compiler behaviour. Adding `testImplementation(projects.testUtils)` to `sql/reactive/utils/build.gradle.kts` is needed for assertk/JUnit and is shared with 9.61.
- Principles: none
- Importance: 1
- Confidence: 4 — known Kotlin reified semantics. Not executed here; the snapshot reports the test passing.
- Recommendation: DROP: it isn't a bug, and the test only pins compiler behaviour. Keeping it as a cheap guard is harmless if the owner wants sql test scaffolding.

### 9.60 — `PostgresReadinessCheck` swallows `CancellationException`
- Defect in base: REAL — `PostgresReadinessCheck.kt:27` `catch (error: Exception)` around a suspending `awaitOne()`. If the check is cancelled it returns `ReadinessCheckResult.Failed` instead of propagating the cancellation. `checkReadiness` (`ReadinessAware.kt:15`) does no wrapping of its own.
- Fix: CORRECT — `currentCoroutineContext().ensureActive()` as the first line of the catch, so an outer cancellation is rethrown and any other exception still maps to `Failed`. The test uses a `ConnectionFactory` that returns `Mono.never()`, launches the check `UNDISPATCHED`, then calls `cancelAndJoin`, and asserts the result is still null. It would fail at base (`Failed` would be assigned). Adding `testImplementation(projects.testUtils)` is required for `test {}`. The same fix was applied to `PulsarReadinessCheck` under 9.112, which is consistent.
- Principles: none
- Importance: 2 — structured-concurrency correctness. In practice it reports a spurious `Failed` during shutdown or timeout.
- Confidence: 5
- Recommendation: REDO AS IS

### 9.61 — `booleanValue` casts to `Byte`
- Defect in base: REAL — `RowParsingUtils.kt:9` `cast<Byte>(columnName).toInt() != 0`. r2dbc-postgresql returns `Boolean` for `bool`, so this always throws `ClassCastException`. It has no callers anywhere.
- Fix: CORRECT but over-built — it now uses `when (val value = get(columnName)) { is Boolean -> value; else -> (value as Byte).toInt() != 0 }`. The `Byte` branch keeps a code path that nothing in this Postgres-only workspace produces, and it throws an NPE/TypeCast error on null. Of the two tests, the Boolean one would fail at base; the Byte one pins the speculative branch.
- Principles: 5 (minimal behaviour). The byte fallback is speculative.
- Importance: 2 — the helper is broken today but unused.
- Confidence: 5
- Recommendation: REDO MODIFIED: `fun Readable.booleanValue(columnName: String): Boolean = getValue(columnName)`, which lets the driver convert. Keep only the Boolean test.

### 9.64 — No tests for the lock service, pagination or binding helpers
- Defect in base: REAL — the only sql test at base is `sql/domain/.../SqlConnectionOptionsTests.kt`.
- Fix: INCOMPLETE (correctly left open) — the only tests added are the ones from 9.58, 9.60 and 9.61. There are still no tests for the custom Liquibase lock (9.55/9.56), pagination (9.63) or null typing (9.57), which are the important ones. Nothing else changed under this item.
- Principles: none
- Importance: 3 — the high-risk lock code has no tests.
- Confidence: 5
- Recommendation: DROP as a standalone redo item. Its tests belong with 9.60/9.61 (and 9.58 if kept), and the rest waits on the lock and pagination decisions.

### 4.14 (swissknife) — `.gitignore` fused line
- Defect in base: REAL — `.gitignore` has the single line `*.pidjava_pid*.hprof` (confirmed with `od -c`), so neither `*.pid` nor `java_pid*.hprof` is ignored. This matters because `gradle.properties` sets `-XX:+HeapDumpOnOutOfMemoryError`, so a heap dump would show up as an untracked, possibly multi-GB file.
- Fix: CORRECT — split into `*.pid` and `java_pid*.hprof`.
- Principles: none
- Importance: 2
- Confidence: 5
- Recommendation: REDO AS IS

## Unattributed changes

Every change in the base..snapshot diff for cryptography, protected-value, jwt, keycloak, security and sql traces back to an item above:
- cryptography: 9.30, 9.31, 9.32, 9.36, 9.37
- protected-value: 9.41, 9.42
- jwt: 9.43, 9.48
- keycloak: 9.49, 9.50, 9.51
- security: 9.52, 9.54
- sql: 9.58, 9.60, 9.61, 9.64, plus the two `testImplementation(projects.testUtils)` build lines needed by the new tests

The only crypto-related `CONTEXT.md` change is line 36, AES-CTR → AES-GCM (9.42). The other `CONTEXT.md`/`IMPROVEMENTS.md` edits (Gradle/Kotlin versions, how convention plugins are resolved, versioning text) belong to 9.28 and are out of this scope. Version-catalog changes are a `zero-allocation-hashing` removal (9.25, hashing) and a gradle-plugins version bump. `publication-state.properties` changes are mechanical.

Two side observations:
- The `PulsarReadinessCheck` change is attributed to 9.112 and is outside this scope. It is consistent with 9.60.
- 9.54's KDoc edit is attributed, but it rests on a wrong finding (see above).
