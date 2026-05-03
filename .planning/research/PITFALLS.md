# Domain Pitfalls

**Domain:** Brownfield online card game with server-authoritative architecture and event-driven combat/effects
**Researched:** 2026-05-03
**Overall confidence:** HIGH for project-specific findings, MEDIUM for generalized domain patterns

## Critical Pitfalls

### Pitfall 1: Rule Drift Between Product Spec and Deck Validator

**What goes wrong:** Deck rules implemented on the server no longer match the active game design, causing legal decks to be rejected or illegal decks to be accepted.
**Why it happens:** Deck constraints are hardcoded in one place and evolve slower than product rules (for example, legacy max size/copies versus new rarity- and card-type-based caps).
**Consequences:** Matchmaking failures, competitive integrity issues, and emergency hotfixes that destabilize onboarding.
**Warning signs:**

- Frequent player reports of "valid in deckbuilder, invalid on join".
- Deck validation constants differ from current project requirements.
- Hotfixes in deck rules without corresponding tests.
  **Prevention strategy:**
- Define one canonical deck-rules schema in shared domain code and make server validator consume it.
- Version the deck rules and include ruleset version in deck codes and server responses.
- Add contract tests for deck size, copy caps by card type/rarity, and essence-cohesion rules.
  **Detection:**
- CI job that compares deckbuilder acceptance matrix vs server acceptance matrix.
- Telemetry on deck rejection reasons with top-card and top-rule breakdown.
  **Suggested phase mapping:**
- Phase 1: Canonical schema + validator refactor.
- Phase 2: Deckbuilder parity checks and error UX.
- Phase 3: Regression and property-based tests for deck legality.

### Pitfall 2: Client/Server Contract Drift on Socket Events and Payload Shapes

**What goes wrong:** Client emits one event name/payload while server listens for another, or server emits payload keys the client no longer reads.
**Why it happens:** Brownfield incremental edits across separate files without shared typed contracts and without protocol compatibility gates.
**Consequences:** Silent no-op actions, stuck turns, ghost UI state, and hard-to-reproduce multiplayer desync symptoms.
**Warning signs:**

- Event names with near-duplicates (for example, one side uses end turn names that differ by wording).
- Manual payload assembly in multiple places without shared DTO helpers.
- Frontend placeholders/test code paths mixed with production listeners.
  **Prevention strategy:**
- Centralize protocol constants (event names + payload schemas) in shared code consumed by both client and server.
- Validate inbound and outbound payloads at runtime (schema validation).
- Introduce protocol version handshake at connect/join and reject incompatible clients early.
  **Detection:**
- Integration tests that spin real socket client/server and assert round-trip for each critical event.
- Runtime metric: unknown events, schema failures, and dropped actions.
  **Suggested phase mapping:**
- Phase 1: Shared protocol map and naming normalization.
- Phase 2: Runtime schema validation and compatibility handshake.
- Phase 4: E2E network contract tests in CI.

### Pitfall 3: Non-Deterministic Event Ordering in Combat and Effects

**What goes wrong:** Effects trigger in inconsistent order across turns or environments, producing different outcomes for similar board states.
**Why it happens:** Event bus listeners iterate mutable board/entity collections while effects may mutate state mid-iteration; ordering guarantees are implicit instead of explicit.
**Consequences:** Competitive fairness risks, replay/debug mismatch, and cascading bugs in death triggers, retaliation, and on-damage hooks.
**Warning signs:**

- Bug reports like "same setup, different result".
- Effect handlers that mutate board/status immediately during beforeDamage/afterDamage loops.
- Event processing that depends on object iteration order or incidental array order.
  **Prevention strategy:**
- Adopt explicit event timeline stages: intent -> pre-hooks -> resolution -> post-hooks -> death queue -> cleanup.
- Snapshot listeners before dispatch and queue side effects for deterministic commit points.
- Enforce deterministic tie-breakers (turn index, priority, stable entity id ordering).
  **Detection:**
- Determinism test harness: run same seed/state N times and diff outputs.
- Structured combat trace logs with sequence numbers and stage markers.
  **Suggested phase mapping:**
- Phase 2: Formalize event timeline and queue semantics.
- Phase 3: Determinism tests and seed-based replay.
- Phase 5: Performance tuning that preserves deterministic ordering.

## Moderate Pitfalls

### Pitfall 4: Deck Code Format Fragility and Ambiguous Decode Failures

**What goes wrong:** Deck code decoding accepts malformed segments or fails ambiguously, leading to null/partial decks that downstream logic mishandles.
**Why it happens:** Minimal encoding format without checksum/version/schema and weak parse validation.
**Consequences:** Join errors, false invalid deck responses, and exploit surface via crafted payloads.
**Warning signs:**

- Deck decode returns null without reason classification.
- Parsing accepts non-integer counts, empty ids, or malformed separators.
- No checksum or signature to detect tampering/corruption.
  **Prevention strategy:**
- Add deck code version prefix, strict parser, and checksum.
- Return structured decode errors (malformed, unsupported version, overflow, unknown card).
- Limit deck payload size and sanitize before decode.
  **Detection:**
- Fuzz tests for deck code parser.
- Monitoring of decode failure categories and top offending patterns.
  **Suggested phase mapping:**
- Phase 1: Deck code v2 spec.
- Phase 2: Parser hardening + structured errors.
- Phase 4: Fuzzing and abuse-case tests.

### Pitfall 5: Shared Module Runtime Assumptions (Browser vs Node)

**What goes wrong:** Shared utilities rely on globals available in one runtime but not the other, breaking server paths under load or deployment changes.
**Why it happens:** Isomorphic folders hide environment-specific dependencies (for example base64 APIs).
**Consequences:** Production-only crashes during join/validation, hard to reproduce locally.
**Warning signs:**

- Shared utility works in browser tests but fails in server execution paths.
- Conditional polyfills sprinkled across call sites.
  **Prevention strategy:**
- Encapsulate runtime differences inside utility adapters and test both runtimes.
- Add explicit environment contract tests for shared modules used by join/combat path.
  **Detection:**
- CI matrix running shared tests in Node and browser-like environment.
  **Suggested phase mapping:**
- Phase 1: Runtime compatibility audit for shared modules.
- Phase 3: Dual-runtime test suite enforcement.

## Minor Pitfalls

### Pitfall 6: Placeholder Client Flows Leaking Into Production Paths

**What goes wrong:** Test rendering and mock flows execute in live sessions, masking real network failures or creating false-positive UI confidence.
**Why it happens:** Brownfield frontend evolves from placeholders without strict feature flags.
**Consequences:** QA misses integration defects until multiplayer tests.
**Warning signs:**

- Test board rendering on socket connect regardless of server game state.
- TODO placeholders adjacent to production listeners.
  **Prevention strategy:**
- Gate all test scaffolding behind explicit dev flags.
- Fail fast in production mode when required server events are missing.
  **Detection:**
- Production build lint/check that disallows test scaffolding imports/calls.
  **Suggested phase mapping:**
- Phase 2: Frontend cleanup and environment flags.
- Phase 4: Build-time guardrails and smoke tests.

## Phase-Specific Warnings

| Phase Topic                | Likely Pitfall                                 | Mitigation                                                  |
| -------------------------- | ---------------------------------------------- | ----------------------------------------------------------- |
| Canonical card/deck schema | Divergent source of truth for deck legality    | Shared schema package consumed by validator and deckbuilder |
| Network contract hardening | Event-name mismatch and payload drift          | Shared protocol constants + runtime schema validation       |
| Combat/effect refactor     | Hook order regression while adding features    | Timeline stages + deterministic side-effect queue           |
| Deck code evolution        | Legacy codes break silently                    | Versioned decoder with compatibility policy and telemetry   |
| Test expansion             | Good unit coverage but no real socket coverage | Integration/E2E socket contract suite in CI                 |

## Recommended Mitigation Sequence (Roadmap Input)

1. Stabilize contracts first: deck rules schema + socket protocol map.
2. Make correctness observable: structured errors, rejection telemetry, ordered combat traces.
3. Lock deterministic behavior: queue-based event timeline and replay/determinism tests.
4. Harden interfaces: deck code v2 and runtime-safe shared utilities.
5. Scale confidence: integration and fuzz testing before feature expansion.

## Sources

- Internal project requirements and active constraints from project planning docs.
- Current architecture baseline and server-authoritative/event-driven principles from architecture documentation.
- Current implementation behavior in deck validation, deck coding/decoding, socket handlers, combat resolver, effect bus, and client entry flow.
