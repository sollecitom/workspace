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
| D3 | **Aggregates only consume events and only produce events.** |
| D4 | **Commands always become events** (`CommandReceived`) before an aggregate sees them. No exceptions. |
| D5 | Three validation tiers: **structural** (schema) → **permissions** (+ integrity) → **invariant** (aggregate state). |
| D6 | Commands rejected at structural / permissions / integrity **never reach the log**. Only invariant rejection is journaled — the `CommandReceived` is already there by then. |
| D7 | `/events` is roughly symmetric with `/commands`. It ingests facts that happened **outside** the system. Validation is structural + permissions only — an event is a fact and cannot be rejected on invariants. |
| D8 | Request-reply must be **race-free**: a reply published before the caller subscribes must never be lost. |
| D9 | Read side is **full lifecycle** — declare, build, track position, rebuild, version — with escape hatches. |
| D10 | **Kafka support must be real**, not theatre. Proven by the same conformance suite as Pulsar, in CI. |
| D11 | **Queries are journaled**, on their own topics — see below. They are `Fact`s like everything else. |
| D12 | Journaling queries **replaces request logging**; it is not additional cost. |
| D13 | Audit is **at-least-once, never at-most-once**, and the mechanism must be able to prove it. |
| D14 | **Record what you can't derive, derive what you can.** |

---

## Core model

```
Fact
├── Event                     ← the only thing aggregates consume or produce
└── Instruction
    ├── Command               ← always wrapped as CommandReceived : Event
    └── Query<ANSWER>         ← wrapped as QueryReceived, but to its own topic
```

---

## Queries, audit, and why queries are journaled

This was the longest thread. Recording the reasoning because the conclusion is non-obvious and the
first two positions were both wrong.

### Rejected: "a query isn't a fact"

A definitional assertion, not an argument. `Query` is a `Fact` in the hierarchy already. The real
question was never the category, it was three separable ones:

1. Is `Query` a `Fact`? — yes, never in dispute
2. Is it routed through the same ordering machinery? — see below
3. Is it durably journaled? — **yes** (D11)

### Why journal: the comparison is journal-vs-log, not journal-vs-nothing

You need an access record anyway, for observability and for compliance. The alternative to journaling
is logging, and logging is a poor audit substrate:

- best-effort delivery — drops under backpressure, disk pressure, agent crash
- schema drifts silently
- frequently **sampled**, which is disqualifying for compliance
- separate retention, separate access control, separate query tool
- not replayable, no ordering guarantees, rarely tamper-evident

So journaling doesn't add a cost, it moves an existing one onto a better substrate.

### Payoff: one stream, many consumers

Once query submissions are events, these stop being separate subsystems and become consumers:

request logging · access audit (same stream, longer retention) · rate limiting and abuse detection ·
usage metering and billing · query analytics · cache warming and prefetch · replaying production read
traffic against a new version before cutover

This constrains the schema: a query event must carry actor, tenant, trace, timestamp, applied
position, outcome status, and latency.

### Separate topics, co-partitioned

Query topics are **separate** from command/event topics, with their own retention.

What that fixes:

| | |
|---|---|
| Retention conflict | Solved — per-topic retention. Queries weeks, events forever. |
| Replay filtering | Solved — the aggregate reads its event topic and *never sees* a query. No skip logic to get wrong in replay, rebuild, or upcasters. |
| Rebuild cost | Solved — projection rebuild no longer streams past 99% queries to find the events. |
| Partition contention | Largely solved. |
| Queueing latency | Solved — queries no longer sit behind commands. |

What it costs, and what follows:

- **Sequentiality with commands/events is lost.** Acceptable, but it makes the read-your-own-writes
  position token load-bearing rather than incidental — a query must be able to say "wait until applied
  position ≥ N", using the position returned in the command outcome. Explicit beats accidental; with
  shared topics RYOW worked by luck of ordering.
- **Co-partitioning is a correctness requirement, not an optimisation.** For an actor owning key K to
  serve a query about K, the query topic must use the same key and the same partition count as the
  event topic. The framework enforces this.
- **Contention moves into the actor's scheduler.** The actor merges two sources, so a query flood can
  still starve commands. The win is that the policy becomes a declared knob (fair-share,
  command-priority, separate budget) instead of whatever topic interleaving happened to give.

---

## Audit durability

### At-most-once vs at-least-once

Fire-and-forget is **at-most-once** — a crash loses the in-flight producer batch, which with batching
is thousands of records, not one. "Off the critical path" and "at-least-once" are incompatible as
stated. At-least-once requires durable retention before you can claim non-loss.

### The fix: overlap, don't weaken

Computing the answer and durably recording the query are independent. Run them concurrently:

```
     ├── compute answer ────────────┐
t0 ──┤                              ├── respond
     └── publish audit → ack ───────┘
```

Latency is `max(compute, publish)`, not `compute + publish`. For anything hitting a store or
projection (1–50ms), a batched ack of 1–3ms disappears under the compute.

**This also satisfies the strict requirement.** Waiting for the ack before releasing the response means
no disclosure without a durable record. So the strict behaviour *is* the default — no `syncAudit` knob
needed. One less thing.

### Where overlap doesn't save you

Queries answered from actor memory in microseconds — then `max()` ≈ the broker round-trip, and you've
added real latency to a nearly-free read. Two options, declared per query type:

- **Local durable buffer + crash-safe async shipper.** Read path waits on a local fsync (tens of µs);
  the shipper drains to the broker with retries and replays unshipped entries on restart.
  *Honest flag:* this is the transactional outbox, which the earlier recap doc explicitly rejected.
  That rejection was about domain events, where the log must be the system of record. This is a
  different trade — audit durability against read latency — but it is the same machinery, so it needs
  to be a conscious carve-out rather than a quiet reintroduction.
- **Accept at-most-once explicitly**, where the domain says audit is observability, not compliance.

### Consequences of actually having at-least-once

- **Duplicates.** Producer retries after a lost ack. Consumers dedupe on the query's
  `idempotencyKey`, which `Fact` already carries.
- **Gap detection is what makes the claim auditable.** "We record every read" is unverifiable without
  a way to detect loss. Per-producer monotonic sequence numbers plus an alert on gaps. This is part of
  the feature, not an ops afterthought — it is what an auditor will actually ask for.

---

## Recording the answer

Audit content splits by when it's known:

| Content | Known when |
|---|---|
| Who, what was asked, tenant, actor, trace, timestamp | At arrival |
| **Applied position** — which version of state will be read | **At start of processing** |
| Digest of what was returned, status, latency | After compute |

The middle row is the one that matters: the actor knows its applied position *before* it computes,
because its state is already at P when the query lands. So the intent record can state precisely which
version of the world is about to be read, without waiting for the read.

That makes the intent record self-sufficient — query + position is enough to **reconstruct** the answer
by replaying to P and re-running. Don't store what you can derive (D14). It also keeps the erasure
surface smaller, since answer payloads are the PII-dense part.

### Two records, mirroring commands

- **`QueryReceived`** — durable, published before disclosure, overlaps with compute. Contains
  everything above the line, plus the applied position.
- **`QueryAnswered`** — status, latency, result size. Published after; may be at-most-once, because
  losing it costs precision, not evidence.

Same shape as `CommandReceived` → outcome event, so it's uniform with the model rather than a special
case.

**Compliance failure mode is correct by construction:** crash after intent, before outcome, and the
auditor sees "X asked for Y at position P, outcome unknown" — the conservative reading is *assume
disclosed*. That's the direction you want an audit trail to fail in.

### When the answer must be recorded

Reconstruction requires deterministic re-execution. It isn't available when:

- the query is non-deterministic — sampling, "as of now", anything touching an external call
- the regime requires recording *disclosed content* rather than access (rare; some financial
  disclosure rules)
- replay-to-position is too expensive to be a practical audit lookup

Then it's serial and you pay `compute + publish`. Declared per query type.

### Erasure

Auditing reads creates a **right-to-erasure obligation on the audit stream itself** — query payloads
contain search terms and subject identifiers. Immutable log plus right to erasure is the classic hard
problem; the standard answer is crypto-shredding (encrypt per subject, delete the key).

swissknife already has `protected-value/domain`, `protected-value/factory/aes`, and `cryptography/*`.
Reuse, not new work — but it must be designed in from the start. Retrofitting erasure into an existing
journal is expensive.

### Cross-aggregate queries

No single routing key, so nothing to partition by. These go to read models, as always. The read-model
path exists regardless, which is why "journal everything through one pipeline" was never going to
deliver true uniformity anyway.

---

## HTTP surface

```
POST /commands/<name>/v<major>
POST /queries/<name>/v<major>
POST /events/<name>/v<major>
```

Routes and OpenAPI are **derived at runtime** from handler registrations (D2). swissknife already has
`openapi/builder`, `openapi/provider`, and `openapi/validation/http4k`.

Majors coexist; older ones carry a sunset header and are separately observable.

### Validation, concretely

| Tier | Question | Where | Journaled? |
|---|---|---|---|
| Structural | Parses against the schema? | Endpoint | No — 400 |
| Permissions / integrity | Caller allowed, for this key? Payload self-consistent? | Edge (JWT claims + routing key) | No — 403/422 |
| Invariant | Does current aggregate state permit it? | Aggregate | Yes — `CommandReceived` already written |

Events skip tier 3 by definition (D7), and carry **provenance** so downstream can distinguish "we
observed this" from "an external party asserted this".

---

## Request-reply

One mechanism, three delivery styles: **sync** (wait inline), **poll** (fetch later), **push**
(subscribe). Mode is a per-request client preference (`Prefer: respond-async` / `respond-sync`), not a
separate endpoint. The aggregate never knows which was chosen; it just publishes the outcome.

### The race-free invariant (D8)

> Every submission produces a **durable outcome record, addressable by correlation id, readable for a
> bounded TTL**. No delivery mode can lose it.

1. **Subscribe-before-publish** for the sync path — the endpoint subscribes before submitting. Removes
   the race entirely when the waiter is the submitter.
2. **Durable outcome store** as universal backstop (NATS KV / JetStream, TTL'd). Late or reconnecting
   subscribers follow *subscribe, then read the store*. This is what makes poll and push safe.

**A sync timeout is never a `504`.** The command is still in flight. Return `202` + correlation id +
`Location` of the outcome resource. "I stopped waiting" and "it failed" are different facts.

The outcome carries the **log position** of the result event — load-bearing for read-your-own-writes.

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

**What must stay out of the port for D10 to hold** — Pulsar has these, Kafka does not, and smuggling
any of them in makes Kafka support fake:

- **Delayed delivery / message-level scheduling** → build a timer service on top
- **Per-message TTL** → framework-level expiry
- **Broker-side dedup** → idempotency is a framework concern
- **Key_Shared subscriptions** → the port says *partition*, not *key-shared*; both brokers give
  per-partition ordering, which is all that's needed

Tiered / infinite retention exists in both (Pulsar native, Kafka KIP-405) with different ops stories —
config, not port.

**Build Pulsar and Kafka in the same phase.** A port with one implementation is not a port, and
retrofitting the second always bends the first.

---

## Read side

Full lifecycle (D9):

- declare a projection: source events, initial state, apply, storage
- durable position tracking per projection
- rebuild from zero while the old version keeps serving
- versioned projections with atomic cutover
- lag / backpressure observability
- **read-your-own-writes** via the position token — load-bearing now that query topics are separate
- escape hatches: raw store access, custom apply, opt out of framework storage entirely

---

## Open — needs a decision

**Q1 — serialization. Still the blocker.** Three things get called "codegen" and D2 doesn't say which
is rejected:

| Option | Source of truth | Cost | Multi-language |
|---|---|---|---|
| (a) Status quo — `.avsc` resources + hand-written `GenericRecord` serde | Schema | Boilerplate per fact type | Authors *and* consumers |
| (b) kotlinx.serialization + Avro derivation | Kotlin type | Compiler plugin, no source emitted | Consumers only |
| (c) `.avsc` → generated Kotlin classes | Schema | Generated source to read and maintain | Authors and consumers |

(c) is out. (a) is what swissknife does today. Given "not fussed about multi-language" plus the
typesafety goal, **(b)** — single source of truth, no hand-written serde, sealed hierarchies and value
classes work naturally, derived schemas still publishable so other languages can *consume*. What you
give up is other languages *authoring* facts.

Decide first: it sets the per-fact-type cost forever.

**Q2** — Idempotency: dedup in aggregate state, a framework-level processed-id set, or transport?

**Q3** — Event upcasting. Avro handles compatible evolution; it does not handle "we restructured this
event and there are years of the old shape in the log."

**Q4** — How much invocation context (tenant, actor, trace) is framework-owned vs application-owned?
swissknife's `correlation/*` models this already and it must flow HTTP → log → aggregate → projection.

**Q5** — Actor scheduling policy between the command/event stream and the query stream. Default
fair-share, or command-priority?

---

## Phasing

| Phase | Content | Proves |
|---|---|---|
| 0 | Resolve Q1. Repo skeleton. | — |
| 1 | Core model, in-memory everything, contract test spec. No broker, no HTTP. | D3, D4, D5, uniform log |
| 2 | HTTP surface derived from registrations + OpenAPI. Tiers 1–2 at the edge. | D1, D2, D6, D7 |
| 3 | Request-reply: durable outcome store, three modes. In-memory, then NATS KV. | D8 |
| 4 | Broker port + conformance suite + **Pulsar and Kafka together**. | D10 |
| 5 | Query topics, audit stream, overlap-publish, gap detection. | D11–D14 |
| 6 | Read side: projections, positions, rebuild, versioning, read-your-own-writes. | D9 |
| 7 | Upcasting, idempotency hardening, crypto-shredding, observability. | Q2, Q3 |

Testing is a headline feature, not a phase: in-memory everything, deterministic time and ids,
`given(events) / when(command) / then(events)`.
