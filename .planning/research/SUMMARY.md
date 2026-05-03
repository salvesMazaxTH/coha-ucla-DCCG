# Project Research Summary

**Project:** UCLA Card Game Continuation  
**Domain:** Server-authoritative multiplayer card game (brownfield continuation)  
**Researched:** 2026-05-03  
**Confidence:** HIGH

## Executive Summary

This project is a continuation of an existing online card game where correctness and competitive integrity matter more than rapid feature sprawl. The strongest shared conclusion across research is to keep the current architecture direction: Node.js + Express + Socket.IO, server-authoritative rules, shared domain contracts, and deterministic event-driven resolution. The fastest path to a stable v1 is not a rewrite; it is contract hardening, deterministic action processing, and deck legality correctness.

The recommended approach is architecture-first stabilization, then feature expansion. Concretely: standardize runtime and protocol contracts, centralize deck and card schemas, migrate imperative action paths into a staged ActionResolver pipeline, and enforce schema validation at all socket trust boundaries. This ordering aligns with the highest-impact dependencies and prevents logic from being trapped inside transport handlers or client UX paths.

The top risk is drift: drift between deckbuilder and validator rules, drift between client/server socket contracts, and drift in effect ordering under mutation-heavy turns. Mitigation is explicit and testable: shared schema and protocol modules, versioned deck code rules, deterministic timeline stages with queued side effects, and integration tests that exercise real two-player socket flows.

## Key Findings

### Recommended Stack Direction

Keep the current platform and harden it incrementally instead of changing technology layers in the same milestone.

**Core technologies:**

- Node.js 22 LTS: production runtime baseline for stability and package compatibility.
- Express 5.2.x: low-risk modernization of server routing/error behavior with minimal structural churn.
- Socket.IO 4.8.x: authoritative real-time transport and event contract channel already aligned with current code.
- Vanilla JS + ES Modules (client): preserve existing render modules and avoid framework migration during rules stabilization.
- Shared domain modules under shared/: single source for game rules, intents, envelopes, and deck rule profiles.
- Zod 4.x: runtime schema validation for inbound/outbound socket payloads.
- Vitest 2.x + socket.io-client tests: deterministic coverage for deck validation, action pipeline, and multiplayer contracts.
- Pino 9.x: structured logs with correlation IDs for match-level diagnostics.

### Table-Stakes Features for v1

These are mandatory for a credible v1 and should be treated as launch blockers if incomplete.

- Quick match flow: queue, pair, start, reconnect timeout handling.
- Server-authoritative lifecycle: join, mulligan/start, turns, action legality, finalization.
- Canonical card model: Unit/Spell/Champion, rarity, essence, cost, effect metadata.
- Deck loop: build/import/export deck code and always revalidate server-side.
- Deck legality enforcement: 48 cards, copy caps by card type/rarity, essence cohesion rule.
- Deterministic turn protocol: clear action windows and legal move validation.
- Core board loop: draw, resource update, play card, attack/resolve, end turn.
- Sync reliability: event envelopes plus periodic canonical snapshot reconciliation.
- Resolution depth: trigger/effect pipeline with deterministic ordering and bounded recursion.
- Match completion: concede, disconnect recovery/finalization, decisive win state.
- Operational observability: structured combat/action trace for replay-lite debugging.

### Architecture Guardrails

1. Preserve strict authority boundaries.

- Client provides intent and UX hints only.
- Server owns legality, state mutation, combat outcomes, and turn progression.

2. Enforce shared contracts for protocol and rules.

- Centralize event names/payload schemas in shared contracts.
- Centralize deck/card rules in shared schema consumed by validator and deckbuilder adapter.

3. Route all actions through a staged resolver pipeline.

- validateIntent -> preHooks -> applyCoreAction -> resolveDeaths -> postHooks -> flushScheduled -> buildEnvelope.
- No direct gameplay mutations inside socket handlers.

4. Keep deterministic event processing.

- Snapshot listeners before dispatch.
- Queue side effects to explicit commit points.
- Apply stable tie-breakers (turn order + stable entity IDs).

5. Keep client rendering projection-only.

- Render from ordered envelopes/snapshots.
- Never encode authoritative rules in render modules.

6. Defer high-churn architecture changes.

- No full frontend framework migration.
- No full TypeScript rewrite.
- No distributed scaling decomposition before single-instance correctness.

### Highest-Risk Pitfalls and Mitigations

1. Rule drift between product deck rules and backend validator.

- Mitigation: shared DeckRules profile, versioned rulesets in deck code/server responses, property-based legality tests.

2. Client/server socket contract drift.

- Mitigation: shared protocol constants + schemas, runtime validation, protocol version handshake, socket round-trip integration tests.

3. Non-deterministic effect and combat ordering.

- Mitigation: explicit timeline stages, queued side effects, stable ordering keys, determinism harness (same seed/state repeated).

4. Deck code fragility and ambiguous decode failures.

- Mitigation: deck code v2 with version prefix and checksum, structured decode error categories, parser fuzz tests.

5. Shared module runtime assumptions (browser vs Node).

- Mitigation: environment-safe utility adapters, dual-runtime CI tests for shared modules on join/combat/deck paths.

## Suggested Phase Ordering

### Phase 1: Contracts and Rule Canonicalization

**Rationale:** Everything else depends on stable rules and protocol contracts.  
**Delivers:** shared protocol map, schema validation boundaries, canonical card/deck schema, DeckRules profile, validator parity baseline.  
**Features covered:** canonical card model, server deck legality, basic join/start event correctness.  
**Pitfalls addressed:** rule drift, contract drift.

### Phase 2: Deterministic Match Core

**Rationale:** v1 credibility depends on fair and repeatable match outcomes.  
**Delivers:** ActionResolver staged pipeline, TurnManager hardening, EffectBus scoped hooks, deterministic envelope builder, reconnect/concede state machine cleanup.  
**Features covered:** deterministic turn protocol, core board loop, resolution pipeline, match finalization.  
**Pitfalls addressed:** non-deterministic ordering, placeholder flow leakage.

### Phase 3: Client Integration and UX Integrity

**Rationale:** Once backend truth is stable, align the client to that truth for reliable player experience.  
**Delivers:** EventRouter/EventQueueRenderer integration, action gating from legal moves, snapshot reconciliation, clearer error/feedback/log UX.  
**Features covered:** reliable sync, clear action feedback, reconnect recovery visibility.  
**Pitfalls addressed:** ghost UI states, hidden contract mismatch symptoms.

### Phase 4: Verification and Hardening

**Rationale:** Stabilization must be proven under test and abuse-like inputs before scale or content expansion.  
**Delivers:** unit + integration + socket E2E suites, determinism replay checks, deck parser fuzzing, telemetry dashboards for rejection and event anomalies.  
**Features covered:** operational observability, regression resistance for v1 rules.  
**Pitfalls addressed:** decode fragility, undetected protocol drift, regression churn.

### Phase 5: Post-v1 Expansion

**Rationale:** Add differentiators only after contracts and determinism are trusted.  
**Delivers:** spectator/replay, ranked progression, draft/arena experiments, broader card pool increments.  
**Features covered:** competitive and retention differentiators.  
**Pitfalls addressed:** premature complexity and content explosion before tooling maturity.

### Phase Ordering Rationale

- Contract-first prevents downstream rework across server, client, and tests.
- Determinism before feature breadth protects fairness and debuggability.
- Client UX tuning after backend hardening avoids masking authority/ordering defects.
- Test and telemetry hardening before expansion protects release quality under new mechanics.

### Research Flags

Phases likely needing deeper research during planning:

- Phase 2 (Deterministic Match Core): resolver staging migration details and hook ordering semantics need targeted design validation.
- Phase 4 (Verification and Hardening): determinism harness and replay-fidelity strategy may require deeper tooling research.
- Phase 5 (Post-v1 Expansion): ranked/MMR and replay/spectator architecture choices need product and infra research.

Phases with standard patterns (can usually skip dedicated research-phase):

- Phase 1 (Contracts and Rule Canonicalization): established schema/contract hardening patterns.
- Phase 3 (Client Integration and UX Integrity): conventional event-driven client reconciliation patterns once contracts are stable.

## Confidence Assessment

| Area         | Confidence | Notes                                                                                                                  |
| ------------ | ---------- | ---------------------------------------------------------------------------------------------------------------------- |
| Stack        | HIGH       | Recommendations align with current codebase and stable 2026 package lines; low migration risk.                         |
| Features     | HIGH       | Strong agreement on v1 table stakes and dependency chain for card game integrity.                                      |
| Architecture | HIGH       | Clear reusable backbone from existing server-authoritative/event-driven structure with explicit adaptation boundaries. |
| Pitfalls     | HIGH       | Risks are concrete, observed in current brownfield context, and mapped to testable mitigations.                        |

**Overall confidence:** HIGH

### Gaps to Address

- Product/business priority gaps for monetization and long-term progression sequencing; resolve during roadmap scoping.
- Capacity assumptions for infra scaling beyond early user cohorts; validate with load targets before distributed architecture work.
- Final protocol compatibility policy (strict vs grace-period support windows) needs explicit release governance.

## Sources

### Primary

- .planning/research/STACK.md
- .planning/research/FEATURES.md
- .planning/research/ARCHITECTURE.md
- .planning/research/PITFALLS.md
- .planning/PROJECT.md

### Secondary

- GAME_ARCHITECTURE_v6_2 (current).md (referenced by research outputs)

---

Research completed: 2026-05-03  
Ready for roadmap: yes
