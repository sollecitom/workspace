# Events Framework — Discussion

Working doc for designing an event-driven, CQRS, event-sourced backend framework.

Starting from scratch. `lattice` and `facts` are prior attempts in this workspace — reference material
at most, nothing carried over by default.

---

## Goal

A highly opinionated framework for backend systems. Developers declare facts and handlers; the
framework supplies the API surface, routing, journaling, request-reply, and the read side. Everything
works by default; everything has an escape hatch.

Company-agnostic. Depends on swissknife only, never pillar.

---

## Decided

| # | Decision |
|---|---|
| D1 | Versioning is **major only** in the path. Compatible evolution within a major is resolved by schema, not by a new endpoint. |
| D2 | **No codegen.** Routes, OpenAPI, and schemas are derived at runtime from registrations — nothing generated into source. |
| D3 | **Aggregates only consume events and only produce events.** Uniform log. |
| D4 | **Commands always become events** (`CommandReceived`) before an aggregate sees them. No exceptions. |
| D5 | Three validation tiers: **structural** (schema) → **permissions** (+ integrity) → **invariant** (aggregate state). |
| D6 | Commands rejected at structural / permissions / integrity **never reach the log**. Only invariant rejection is journaled — the `CommandReceived` is already there by then. |
| D7 | `/events` is roughly symmetric with `/commands`. It ingests facts that happened **outside** the system. Validation is structural + permissions only — an event is a fact and cannot be rejected on invariants. |
| D8 | Request-reply must be **race-free**: a reply published before the caller subscribes must never be lost. |
| D9 | Read side is **full lifecycle** — declare, build, track position, rebuild, version — with escape hatches. |
| D10 | **Kafka support must be real**, not theatre. Proven by the same conformance suite as Pulsar, in CI. |

---

## Core model

```
Fact
├── Event                     ← the only thing aggregates consume or produce
└── Instruction
    ├── Command               ← always wrapped as CommandReceived : Event
    └── Query<ANSWER>         ← never becomes an event (see below)
```

**Recommendation on queries — make the exception the rule: queries never become events.**

You flagged read-model-crossing queries as an exception and wondered if queries are exceptions in
general. I'd go further and say they always are, for two reasons:

1. A query is not a fact. Journaling it is a category error.
2. Read volume typically dwarfs write volume. Journaling reads into permanent tiered storage makes the
   log's economics attacker- and traffic-controllable, for zero audit value.

If a query genuinely needs strongly-consistent aggregate state, route it **to the actor's mailbox**
without journaling it — sequential processing without durability. That preserves the consistency
benefit and keeps the log clean. Normal path stays: query → read model.

This keeps D3 intact (aggregates still only consume events) while making the rule uniform rather than
case-by-case.

---

## HTTP surface

```
POST /commands/<name>/v<major>
POST /queries/<name>/v<major>
POST /events/<name>/v<major>
```

Routes and OpenAPI are **derived at runtime** from handler registrations (D2). swissknife already has
`openapi/builder`, `openapi/provider`, and `openapi/validation/http4k` for this.

Per-major deprecation: majors coexist, older ones carry a sunset header and are separately observable.

### Validation, concretely

| Tier | Question | Where | Journaled? |
|---|---|---|---|
| Structural | Parses against the schema? | Endpoint | No — 400 |
| Permissions / integrity | Caller allowed, for this key? Payload self-consistent? | Edge (JWT claims + routing key) | No — 403/422 |
| Invariant | Does current aggregate state permit it? | Aggregate | Yes — `CommandReceived` already written |

Events skip tier 3 by definition (D7). Events carry **provenance** so downstream can distinguish
"we observed this" from "an external party asserted this".

---

## Request-reply

One mechanism, three delivery styles:

- **sync** — wait inline
- **poll** — fetch later
- **push** — subscribe

Mode is a **per-request client preference** (`Prefer: respond-async` / `respond-sync`), not a separate
endpoint. The aggregate never knows which was chosen; it just publishes the outcome.

### The race-free invariant (D8)

> Every submission produces a **durable outcome record, addressable by correlation id, readable for a
> bounded TTL**. No delivery mode can lose it.

Two mechanisms, layered:

1. **Subscribe-before-publish** for the sync path — the endpoint subscribes to the reply subject before
   submitting. Removes the race entirely when the waiter is the submitter.
2. **Durable outcome store** as the universal backstop (NATS KV / JetStream, TTL'd). Late or
   disconnected subscribers follow *subscribe, then read the store* — if it wasn't there, the
   subscription catches it. This is what makes poll and push safe, and covers reconnects.

**A sync timeout is never a `504`.** The command is still in flight. Return `202` + correlation id +
`Location` of the outcome resource. "I stopped waiting" and "it failed" are different facts.

The outcome carries the **log position** of the result event — this is what makes read-your-own-writes
possible on the read side.

---

## Ports and adapters

Every port gets a **test specification**; every adapter must pass it. This is the existing workspace
pattern (`swissknife/**/test/specification`) and it is what makes "bring your own adapter" verifiable
rather than aspirational.

### Broker port — four operations only

1. Append a fact to a partitioned log under a partition key
2. Consume one partition sequentially, at-least-once, manual ack
3. Store and resume from a position
4. Durable retention

Everything else is implementation configuration.

**What must stay out of the port for D10 to hold** — Pulsar has these, Kafka does not, and smuggling
any of them in makes Kafka support fake:

- **Delayed delivery / message-level scheduling** → build a timer service on top, don't push it down
- **Per-message TTL** → framework-level expiry
- **Broker-side dedup** → idempotency is a framework concern
- **Key_Shared subscriptions** → the port says *partition*, not *key-shared*; both brokers give
  per-partition ordering, which is all that's needed

Tiered / infinite retention exists in both (Pulsar native, Kafka KIP-405) but with different ops
stories — that's config, not port.

**Build the Pulsar and Kafka adapters in the same phase.** A port with one implementation is not a
port, and retrofitting the second one always bends the first.

---

## Read side

Full lifecycle (D9):

- declare a projection: source events, initial state, apply, storage
- durable position tracking per projection
- rebuild from zero (new projection, or a bug fix) while the old version keeps serving
- versioned projections with atomic cutover
- lag / backpressure observability
- **read-your-own-writes**: query may specify "at least this log position", using the position returned
  in the command outcome
- escape hatches: raw store access, custom apply, opt out of framework storage entirely

---

## Open — needs a decision

**Q1 — serialization, and it's the blocker.** Three things get called "codegen" and D2 doesn't say which
you're rejecting:

| Option | Source of truth | Cost | Multi-language |
|---|---|---|---|
| (a) Status quo — `.avsc` resources + hand-written `GenericRecord` serde | Schema | Boilerplate per fact type; typing relationships live in Kotlin anyway | Authors *and* consumers |
| (b) kotlinx.serialization + Avro derivation | Kotlin type | Compiler plugin, no source emitted | Consumers only (publish derived schemas to a registry) |
| (c) `.avsc` → generated Kotlin classes | Schema | Generated source you read and maintain | Authors and consumers |

(c) is clearly out. (a) is what swissknife does today. Given "not fussed about multi-language" and the
typesafety goal, **I'd pick (b)** — single source of truth, no hand-written serde, sealed hierarchies
and value classes work naturally, and you can still publish derived schemas so other languages can
*consume*. What you give up is other languages *authoring* facts.

Worth deciding first: it determines how much boilerplate every fact type costs forever.

**Q2** — Idempotency: where does dedup live? Aggregate state, framework-level processed-id set, or
transport?

**Q3** — Event upcasting. Avro reader/writer resolution handles compatible evolution; it does not
handle "we restructured this event and there are years of the old shape in the log". Design early or
inherit the pain.

**Q4** — How much invocation context (tenant, actor, trace) is framework-owned vs application-owned?
swissknife's `correlation/*` already models this and it needs to flow HTTP → log → aggregate →
projection.

---

## Phasing

| Phase | Content | Proves |
|---|---|---|
| 0 | Resolve Q1. Repo skeleton. | — |
| 1 | Core model, in-memory everything, contract test spec. No broker, no HTTP. | D3, D4, D5, uniform log |
| 2 | HTTP surface derived from registrations + OpenAPI. Tiers 1–2 at the edge. | D1, D2, D6, D7 |
| 3 | Request-reply: durable outcome store, three modes. In-memory store, then NATS KV. | D8 |
| 4 | Broker port + conformance suite + **Pulsar and Kafka together**. | D10 |
| 5 | Read side: projections, positions, rebuild, versioning, read-your-writes. | D9 |
| 6 | Upcasting, idempotency hardening, observability. | Q2, Q3 |

Testing is a headline feature, not a phase: in-memory everything, deterministic time and ids,
`given(events) / when(command) / then(events)`.
