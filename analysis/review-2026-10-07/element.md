# Review findings: element (to verify and fix)

1. H confirm_requirement_applicability ApplicationResultJsonSerde.kt:20 — CompliancePlanNotFound unmapped → 500 (regression; was 200). Add serde case, Result.json $ref, api.yaml example, serde test case, confirm call in the not-found application test.
2. H viewer tenant filter compares typed strings: writes customerId.toTypedString() from events, query binds context customer (gateway Id.fromString → string:<v>) → type mismatch → empty list. Bind/query customer_id by stringValue (as outputs-manager); repository-spec case with differing id types.
3. M chart never sets INSTANCE_NODE_NAME (now required): add env from metadata.name.
4. M transaction test: runCatching + isFailure isTrue → failedThrowing; also assert retrieveRequirements empty; add storeStandardsOutputs test.
5. L Service.kt:89-93 finally closes sequentially; one throw skips the rest — runCatching each.
6. L 12.67 test only isOriginating false → assert descendsFrom(triggering message id).
7. L StandardOrderingTests.kt:26 isNotEqualTo(0) → literal/containsExactly.
8. L StandardAssertions.kt:13 hand-maintained fields list → derive (e.g. data class componentN / reflection-free alternative) or a structural check.
9. L outputs-manager ApplicationImplementation.kt:58 dispatches on message.value.type (decodes) → message.eventType().
10. L CompliancePlanEventHandler typealias + map dispatch duplicated in 3 apps → one pillar helper (ties to pillar finding 3: EventHandler).
11. L PostgresCompliancePlanOutputsRepository.kt:39 RequirementsOperations gets its own transaction manager → pass transactionManager.
12. L standards report ResultJsonSerializationTests lacks CompliancePlanNotFound case.
13. L StandardsDevelopingOrganization.json accepts any string; add enum of known codes (like Market.json).
14. L outputs-manager: no 403 / page-size 400 contract tests.
15. L import churn on `lens.map` in seven endpoint files (revert churn).
16. L CSVRow.kt holds csvFile/asCsvDate → rename/split file; CompliancePlanNotFound in report.csv package used beyond CSV → move.
