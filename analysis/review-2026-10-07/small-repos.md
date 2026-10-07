# Review findings: acme, modulith, examples, tools, quality-scorer, facts (to verify and fix)

1. M tools StaticPackageMigration.kt:119/:104 — lookbehind allows a leading `.`; `x.a.b.c` gets rewritten when migrating `a.b.c`. Fix: name lookbehind `(?<![\w$.])`; paths only match at a source-set root. Test x.a.b.c unchanged.
2. M modulith account-event-processor Application.kt:26/:34 — hand-written handledTypes + when with else → warn+NoOp (skips a message on drift, violates halt-on-bugs). Fix: element's map pattern (handlers.keys / getValue).
3. L tools StaticPackageMigration.kt:112-119 — single-segment package rewrites any standalone word (`this is a test`). Fix: only package contexts (package/import, or followed by `.`).
4. L examples Transaction.kt — domain accepts any BigDecimal scale; builder setScale(2): 23.8 round-trips as 23.80 (not equal), ≥3 decimals throw. Fix: normalise/reject scale in domain.
5. L quality-scorer GraderIntegrationTests.kt:73/:80 — use failedThrowing<InvalidInputException>().
6. L quality-scorer KoverCoverageParser.kt:16 — unreadable existing file throws AccessDeniedException (exit 1). Wrap IOException → InvalidInputException; add unparsable-report test.
7. L quality-scorer KotlinModel.kt:67-73 — duplicate main-source filtering; extract mainSourceFiles.
8. L quality-scorer — diff extended KDoc in Main.kt, KotlinProjectLoader.kt, KotlinModel.kt; strip the added KDoc.
9. L modulith Service.kt:110 / element Service.kt:128 — serviceInstanceInfo duplicated; move to pillar (ServiceInfo from environment).
10. L acme CurrencyAmount.json units — pattern unbounded vs Avro precision 100: `^[0-9]{1,100}$`.
11. L facts settings.gradle.kts:65 — in-memory tests module now empty; KotlinClientApiTestSpecification empty and unused. Delete both.
12. L tools Directory.kt:26 — deleteIfExists() unused now. Delete.
13. L tools StaticPackageMigration.kt:102 — excluded-folder check applies to segments inside source sets (package x.gradle.y skipped). Only check segments before src/.
14. L examples Transaction.kt:30 — `pricePerShare * quantity.toBigDecimal()`; TransactionTestStubs.kt:37 — rename maximumInMinorUnits → untilInMinorUnits.

## Status
- Fixed: 1, 3, 12, 13 (tools a3b3052); 5, 6, 7, 8 (quality-scorer b4fb5b9); 11 (facts 2ace5b6); 10 (acme bc1b0f2, 1.0.12).
- Fixed: 2, 9 (modulith 279c365, via pillar EventHandler.byType and swissknife ServiceInfo.fromEnvironment); 4, 14 (examples 585d6a3; money normalised to scale 2, lossy values throw).
