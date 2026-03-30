# Swissknife & Pillar: Comprehensive Analysis Report

## Overview

| | Swissknife | Pillar |
|---|---|---|
| Purpose | General-purpose Kotlin libraries | Domain-specific / company-specific libraries |
| Modules | ~90 | ~36 |
| Modules without tests | 6 (7%) | 12 (33%) |
| Critical issues | 6 | 2 |

---

## 1. Bugs and Correctness Issues

### Swissknife

#### HIGH — Unsafe type casts without guards

Multiple locations with unchecked casts that will throw ClassCastException on wrong input:

| File | Line | Cast |
|------|------|------|
| `openapi/validation/http4k/validator/.../ResponseJsonBodyValidator.kt` | 28 | `rawResponse as ResponseWithHeadersAdapter` |
| `json/utils/.../JsonExtensions.kt` | 35 | `get(index) as JSONObject` |
| `json/utils/.../JsonExtensions.kt` | 59, 62 | `it as String`, `it as Int` |
| `avro/serialization/utils/.../AvroGenericRecordExtensions.kt` | 17-47 | 10+ unchecked casts suppressed with `@Suppress("UNCHECKED_CAST")` |

#### HIGH — Null assertion failures

| File | Line | Issue |
|------|------|-------|
| `logger/core/.../Trie.kt` | 50, 66, 105 | `node[element]!!` and `node!!.containsKey(element)` — unsafe in concurrent access from logger |
| `messaging/domain/.../Topic.kt` | 31 | `.namespace!!` NPE if parse fails — converts exception to NPE |
| `avro/serialization/utils/.../AvroGenericRecordExtensions.kt` | 75 | `getRecordListOrNull(key)?.map(...)!!` — NPE instead of graceful handling |

#### MEDIUM — TODO indicating incomplete feature

**File**: `openapi/validation/http4k/validator/.../ResponseJsonBodyValidator.kt:56`

`// TODO this removes 'const' from the schema for some reason - fix it when you have time`

---

### Pillar

#### LOW — Hardcoded Example.tenant and Customer.isTest in GatewayInvocationContextFilter

**File**: `web/api/utils/.../GatewayInvocationContextFilter.kt`

This filter is **early WIP and unused**. Known issues (hardcoded `Example.tenant`, `Customer.isTest=false`, missing tenant resolver) are expected for unfinished code and not actionable until the filter is completed.

#### ~~HIGH — Unsafe email parsing in JWT~~ **Fixed**

Now uses `EmailAddress` value class from swissknife which validates email format (must contain `@`, must have `.` after `@`). Organization name extracted via `substringAfter`/`substringBeforeLast` instead of `split().single()`.

#### MEDIUM — Missing validation in User.fullName

**File**: `jwt/domain/.../User.kt:5`

```kotlin
val fullName: String = "$firstName${...} $lastName"
```

If `firstName` or `lastName` are empty strings, produces malformed output with leading/trailing spaces. No `require(isNotBlank())` validation.

#### MEDIUM — Unsafe null assertions in filter

**File**: `web/api/utils/.../GatewayInfoContextParsingFilter.kt:27, 49`

- Line 27: `attempt.exceptionOrNull()!!.asResponse()` — NPE if no exception present
- Line 49: `it.second!!` assumes header value is never null

---

## 2. Test Coverage Gaps

### Swissknife — 6 modules still without tests

Tests were added to 14 previously untested modules. Remaining untested:

| Module | Reason |
|--------|--------|
| `openapi/provider` | Infrastructure-dependent (classpath/file I/O) |
| `opentelemetry/core` | Pure interface, no testable logic |
| `pulsar/utils` | Requires running Pulsar broker |
| `nats/client` | Requires running NATS server |
| `serialization/domain` | Pure interfaces only |
| `test/utils` | Test infrastructure itself |

### Pillar — 12 modules still without tests

Tests were added to 5 previously untested modules. Remaining untested:

| Module | Reason |
|--------|--------|
| `web/api/utils` | **CRITICAL** — tightly coupled to http4k, needs integration test setup |
| `correlation/logging/utils` | Thin wrapper, minimal logic |
| `messaging/domain` | Requires coroutine Flow/Message infrastructure |
| `acme/conventions` | Pure interfaces only |
| `messaging/avro` | Simple delegation, no logic |
| `messaging/json` | Simple delegation, no logic |
| `messaging/pulsar/avro` | Requires Pulsar |
| `messaging/pulsar/json` | Requires Pulsar |
| `protected-value/domain` | Just a typealias |
| `prometheus/micrometer/registry` | Requires server infrastructure |
| `jwt/test/utils` | Test infrastructure |
| `messaging/test/utils` | Test infrastructure |
| `service/container-based/test` | Test infrastructure |

---

## 3. API Design Concerns

### Inconsistent factory patterns (swissknife)

Multiple "companion object" factory methods with no consistent naming:
- Sometimes `of()`, sometimes `parse()`, sometimes constructor overloads
- No shared convention across modules

### Missing sealed hierarchies

| Location | Issue |
|----------|-------|
| `swissknife: messaging/domain/Topic.kt` | Protocol variants (Persistent, NonPersistent) should be sealed |
| `pillar: jwt/domain/Authentication.kt` | Allows unchecked extensions; JWT spec only supports specific ACR values |
| `pillar: jwt/domain/Access.kt` | No invariant that at least one role set is non-empty |

### Missing validation in domain types (pillar)

| Type | Missing |
|------|---------|
| `Token` | No validation that `expiresAt > issuedAt` when both present |
| `Access` | Allows empty role sets: `Access(emptySet(), emptySet(), emptySet())` |
| `User` | No validation for blank firstName/lastName |

### Leaky abstractions (pillar)

- `GatewayInvocationContextFilter` depends on `Example.tenant` from business domain — early WIP, not yet actionable
- `acme/business/domain` imports from `messaging/conventions` and `http/api/conventions` — inverted dependency (conventions should depend on domain, not vice versa)

### Inconsistent naming (pillar)

Mixed use of `authorization` vs `authentication`:
- JWT domain uses `Authentication` for authc
- GatewayInvocationContextFilter uses `AuthorizationPrincipal` for roles (authz)
- Swissknife uses `Access` as umbrella term
- No glossary defines these terms

---

## 4. Domain Model Concerns (Pillar)

### Tenant vs Customer vs Organization confusion

| Concept | Module | Definition | Issue |
|---------|--------|-----------|-------|
| `Tenant` | swissknife | Multi-tenant isolation unit | Used in Example but never configured from JWT |
| `Customer` | swissknife | Business customer entity | Hardcoded `isTest=false` |
| `Organization` | pillar/jwt/domain | Org from JWT claims | Different from Tenant, extracted from email domain |
| `User` | pillar/jwt/domain | End user identity | Has `organization` but no reference to `Tenant` |

### Missing access control hierarchy

Should be: Tenant → Customer → User → Session → Token

Actual: Token → Session → User → Organization (JWT) vs Tenant (separate, hardcoded)

Breaks multi-tenancy: all authenticated users see `Example.tenant` regardless of JWT org.

### Incomplete Actor abstraction

`GatewayInvocationContextFilter:127` has TODO "add support for service accounts, user locale, other actor types" but Actor is defined in swissknife — pillar can't extend it without modifying swissknife.

---

## 5. Code Duplication

### Swissknife

| Pattern | Occurrences | Modules |
|---------|-------------|---------|
| `getOrNull() ?: fail()` null-assertion pattern | 20+ | json/utils, avro/serialization, jwt |
| `?.let { it as Type }` cast-and-check | 20+ | across many modules |
| Extension methods for different wrapper types with same shape | 10+ | core, json, avro |

### Pillar

| Pattern | Occurrences | Modules |
|---------|-------------|---------|
| JWT field extraction `getRequired*(); return DomainClass(...)` | 8+ | jwt/domain/AcmeJwtScheme.kt |
| Serde template (get required fields → optional fields → put) | 5+ | json/serialization/* |
| Role validation logic | 2 | AcmeJwtScheme.kt, AcmeRoles.kt |

---

## 6. Deprecated/Outdated Patterns

### runBlocking in HTTP handler (pillar)

**File**: `web/api/utils/.../InvocationContextLoggingFilter.kt:19`

`runBlocking { withCoroutineLoggingContext(...) }` blocks the HTTP thread, defeating the purpose of async context. Should use async-compatible logging or convert filter to suspending.

### Guava cache usage (pillar)

**File**: `web/api/utils/.../GatewayInvocationContextFilter.kt:3-4`

Uses Guava `CacheBuilder` for key caching. Could be replaced with Kotlin-native `ConcurrentHashMap` or coroutine-aware caching, removing the Guava dependency.

### Mutable state in Flow extension (swissknife)

**File**: `kotlin/extensions/.../FlowChunkingExtensions.kt:24`

`private var original = this@chunkUntilPrivate` — mutable state in a Flow object is problematic for re-entrancy.

---

## 7. Configuration Issues

### No module READMEs

- Swissknife: 0 out of ~90 modules have READMEs
- Pillar: 0 out of ~36 modules have READMEs
- Root READMEs are 1-3 lines each

### Outstanding TODOs

| Project | Count | Critical |
|---------|-------|----------|
| Swissknife | 17 files | ResponseJsonBodyValidator schema issue |
| Pillar | 10+ | Example.tenant, customer lookup, nested containers, Actor types, SupervisorJob |

### SNAPSHOT dependency lock-in

All internal dependencies are `1.0.0-SNAPSHOT`. Two builds on different days may resolve different JARs. No reproducibility guarantee.

---

## 8. Priority Fix List

### Immediate (bugs in production-path code)

| # | Project | Issue | File |
|---|---------|-------|------|
| ~~1~~ | ~~pillar~~ | ~~Unsafe email parsing~~ | **Fixed** — uses `EmailAddress` value class |

### Short-term (correctness and safety)

| # | Project | Issue |
|---|---------|-------|
| 7 | swissknife | Add null guards to unsafe type casts in JsonExtensions and AvroGenericRecordExtensions |
| 8 | swissknife | Guard `!!` operators in Topic.Namespace.parse() and Trie |
| 9 | pillar | Add validation to User (blank names), Access (empty roles), Token (expiry ordering) |
| 10 | pillar | Add validation to Authentication ACR values |

### Medium-term (test coverage)

| # | Project | Issue |
|---|---------|-------|
| 11 | pillar | Add integration tests for `web/api/utils` — most critical untested module, requires http4k test setup |

### Long-term (design)

| # | Project | Issue |
|---|---------|-------|
| 15 | pillar | Resolve Tenant/Customer/Organization confusion — define clear multi-tenancy model |
| 16 | pillar | Fix dependency direction: conventions should depend on business domain, not vice versa |
| 18 | both | Add module-level READMEs for at least the top 20 most-used modules |
| 19 | both | Extract repeated patterns (null-assert, type-cast, serde template) into shared utilities |
