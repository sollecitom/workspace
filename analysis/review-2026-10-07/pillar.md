# Review findings: pillar (to verify and fix)

1. H [OWNER 2026-10-07: an undecodable payload must crash hard and loud and stop the whole pipeline — ERROR log with message identity and cause, stop consuming, fail the service visibly; no retry, no silent death, no DLQ. Processing failures keep retry-in-place.] MessagingEventProcessor.kt:49/:45 — retry catch logs `${message.value}`; Pulsar value decodes lazily → second decode failure thrown inside catch → processing coroutine dies silently (no retry, no ack, no log). Fix: log id, key, raw event-type property only; test handled-type message throwing from value → retried, never acked.
2. M :56 — `eventType() in handledTypes` matches name+version: foo--v2 acked silently by a foo--v1 consumer. Fix (choice): "handled" by name; unknown versions of a handled name go to the handler/retry path (halt).
3. M handledTypes and processEvent separate params, drift-prone; N.4 decided handlers declare types → pillar EventHandler { handledTypes; process } taken by the factories.
4. M EventProcessingTestUtils.kt:15 default handledTypes from decoded values; inMemorySpy has no event-type header → hangs. Move the header-setting factory (EVENT.asMessage()) to messaging-test-utils; helper uses it.
5. M tests: no test for missing event-type header halting; none for finding 1.
6. M no_NO_NY special case duplicated (LocaleLanguageTags in json correlation root package vs LocaleAvroSerde); one shared locale helper in a core module.
7. M filter factories are extensions on swissknife's InvocationContextKeys object → top-level functions or pillar InvocationContextFilters (gateway stub: mechanical call-site update only).
8. M toCustomerScoped doesn't pass the customer; 403 empty body vs sibling apiError JSON. Pass non-null Customer to the action; error body with ErrorCode.
9. L branch-name string constants duplicate .avsc names → match on schema names (X.avroSchema.name).
10. L double blank lines where type() removed (Access, Account, Actor, ServiceAccount, Authentication, ToggleValue serdes).
11. L new/extended KDoc: AcmeTopicValueSchemaRules.kt:8, LocaleLanguageTags.kt:9,12, PrometheusMicrometerRegistryConventions.kt:16, RoutingExtensions.kt:33; extended CurrencyAmountAvroSerde.kt:19, CurrencyAmountJsonSerde.kt:16, MessagingEventProcessor.kt:77-80,95,112,129.
12. L CurrencyAmountAvroSerdeTests.kt:36 inside-out, duplicated field lookup, assert message.
13. L CurrencyAmountJsonSerializationTests: cases don't prove the regex; assert messages.
14. L deprecated Locale(...) + suppress → Locale.of.
15. L new processor test without backgroundScope; UndecodableMessage → test-utils.
16. L AcmeTopicValueSchemaRules tests in AcmeAvroSchemaRulesTests → own class.
17. L tests: InvocationContext.specifiedLocale no_NO_NY path; customer-scoped with specifiedTargetCustomer.
18. L factory overloads parameter order inconsistent; require(handledTypes.isNotEmpty()).
19. L CurrencyAmountJsonSerde read check `^[0-9]+$` → align with acme `^[0-9]{1,100}$` (acme 1.0.12).
