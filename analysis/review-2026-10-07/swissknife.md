# Review findings: swissknife (to verify and fix)

1. H [OWNER: DON'T TOUCH — discuss first] CoreDataGeneratorProvider.kt:21,24,27 — production ids (ULID, KSUID, UUIDv4/v7, external) derive from `random`, seeded with a value logged at INFO → ids predictable from logs. Fix: ids from `secureRandom` (unseeded in production, seeded only when a seed is configured).
2. M DowngradingOpenApiDefinitionReader.kt:33,38 — versionLine regex YAML-only; JSON 3.1 silently not downgraded. Read version from the model; handle JSON; test.
3. M JsonSchema.kt:40,45 — nested objects without properties skipped by objectSchemas; select by object type; test.
4. M GenericRecordRoundTrip.kt:7 — writes with record.schema, reads with `schema` as writer+reader. Drop the parameter (serializeAndDeserialize()) or write with schema too.
5. L-M PulsarMessageConsumer name/subscriptionName throw before start (plausible; no caller found).
6. L LiquibaseDatabaseMigrator.kt:65-66 — JDBC connection leaks if findCorrectDatabaseImplementation throws.
7. L AvroRecordBuilderImpl.decimalBytesOrNull — unknown field → bare NPE; multi-branch union → single() throws.
8. L more than decided: EmailAddress empty labels; parseContent resolves refs by default; LogEntry.json changed instead of formatter (check 9.136 wording).
9. L stop() races create without the mutex (consumer/producer); seeded secureRandom == random stream.
10. Style: new KDoc added (strip all except decision-mandated 9.10, 9.26, 9.85, 9.117): TopicEventUnionRule, getRecordFromUnion, setRecordInUnion x2, configureNamespace, autoTopicCreation, toTypedString/fromTypedString, Toggles.standard, requireAcceptedBy, Toggle.accepts, testWithInvocationLoggingContext, VerifyingPublicKey.verify, JWT.isNotExpiredAt, getLongOrNull/getIntOrNull, JsonSchema.objectSchemas, LongestPrefixMatchLoggingLevelEnabler, minimumLoggingLevelOverridesFromEnvironment, LowercasePathNameRule, OpenApiDefinitionReader.downgrading, OpenTelemetryModule.stop (re-declared only for KDoc), AccessHook, loggingAccessHook, accessible(...), createUser, selectPage, TypedNull, plus operator, defaultReadinessTimeout, InvocationContextKeys.
11. Naming: setRecordInUnion/getRecordFromUnion are envelope accessors → setEnvelope / getEnvelope.
12. Inside-out: AvroRecordBuilderImpl.kt:63; IdStringFormTests.kt:42; UUIDTests.kt:141; Toggle.kt:9; ToggleValueLensTests.kt:40.
13. Duplicate decimal schema lookup → one Schema.decimalFieldOrNull(name).
14. Three shapes of nested JSON violations → one Violation(path: List<String>).
15. EnvelopeTests.kt:29 roundTripped never serialises.
16. Leftover `topic.namespace.let {}`; duplicate PulsarAdmin.ensureTopicExists (x3).
17. DatabaseClient.close() in the wrong file (→ WithSqlConnectivity.kt).
18. StandardLoggingConfiguration trims twice.
19. Failure-test style: XtsAesTests.kt:40, ResourceLoaderTest.kt:75 → failedThrowing; AesProtectedValueTests.kt:92 failedThrowing<Exception> too broad.
20. AesProtectedValueTests access-hook test doesn't prove "before decryption".
21. Missing tests: map(deserializer); malformed override require; getIntArrayOrNull strictness; decimal getter on non-decimal bytes; OpenTelemetryModule.stop; MDC child-thread non-inheritance.
22. PooledR2dbcClientTests in sql-postgres-utils (needs a driver) — fine, maybe note.
