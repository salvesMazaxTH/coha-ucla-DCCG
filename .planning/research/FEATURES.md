# Feature Landscape

**Domain:** Competitive online card game (brownfield continuation)
**Researched:** 2026-05-03
**Reference pattern:** `GAME_ARCHITECTURE_v6_2 (current).md` adapted to card game context

## Scope Alignment (What This Document Assumes)

- Keep **server-authoritative** state and validation as non-negotiable.
- Keep **event pipeline + modular domain boundaries** (shared core, effects bus, resolver layers).
- Adapt combat/turn concepts to card game semantics (cards, board, hand, mana/resources, deck rules).
- Exclude RPG-only systems when not needed (champion switch/reserve loops, RPG-specific damage formulas, ult meter semantics tied to champion kits).

## Table Stakes (v1 Card Game Loop)

Features players expect in a playable and fair competitive v1. Missing any of these makes the product feel incomplete.

| Feature                                                                              | Why Expected                                                | Complexity | Risk Notes                                                              |
| ------------------------------------------------------------------------------------ | ----------------------------------------------------------- | ---------- | ----------------------------------------------------------------------- |
| Accountless quick match lobby (join, queue, pair, reconnect timeout)                 | Baseline for online head-to-head play                       | Medium     | Match/session desync if reconnect ownership is weak                     |
| Server-authoritative match lifecycle (create game, mulligan/start, turns, end state) | Core integrity requirement for competitive games            | High       | Any client-authoritative branch creates exploit surface                 |
| Deterministic turn protocol (priority windows and legal action validation)           | Prevents disputes and race conditions                       | High       | Ambiguous timing causes "I clicked first" conflicts                     |
| Canonical card schema (Unit/Spell/Champion, rarity, essence, cost, effects)          | Required for deckbuilding, rules, rendering, and validation | Medium     | Schema drift between client/server leads to invalid games               |
| Deckbuilding + deck code import/export                                               | Mandatory user loop before play                             | Medium     | Invalid deck serialization/version mismatch blocks matchmaking          |
| Backend deck validation (48 cards, copy limits, essence cohesion rule)               | Competitive fairness and anti-cheat minimum                 | High       | Weak validation allows illegal decks in ranked-like flow                |
| Core board loop (draw, resource gain, play card, attack/resolve, end turn)           | Fundamental expected gameplay loop                          | High       | Missing phase guards can allow illegal sequencing                       |
| State sync snapshots + incremental events                                            | Reliable client rendering under latency                     | High       | Full-state spam impacts perf; events-only can drift without checkpoints |
| Combat/effect resolution pipeline (stacked effects, triggers, statuses)              | Expected depth and consistency in card interactions         | High       | Infinite loops/order bugs without strict event ordering and caps        |
| Basic UX integrity layer (action lock, timers, clear feedback/log)                   | Prevents confusion and accidental invalid actions           | Medium     | Poor UX appears as "bugs" even when rules are correct                   |
| Concede + disconnect handling + win condition finalization                           | Must finish matches cleanly                                 | Medium     | Orphaned games and ghost sessions if not finalized                      |
| Telemetry/debug trace for match replay-lite (server logs/events)                     | Needed for QA, balancing, and dispute diagnosis             | Medium     | Hard to debug effects without event traces                              |

## Differentiators (Later Milestones)

Valuable features that improve retention and depth after v1 stability.

| Feature                                                          | Value Proposition                                 | Complexity | Recommended Milestone Window                  |
| ---------------------------------------------------------------- | ------------------------------------------------- | ---------- | --------------------------------------------- |
| Spectator mode with delayed state feed                           | Community and content growth                      | Medium     | Post-v1 once sync is stable                   |
| Replay system from event log (deterministic re-sim)              | Learning, bug diagnosis, esports credibility      | High       | After event contracts are frozen              |
| Advanced draft/arena modes                                       | High replayability and monetization-friendly loop | High       | After base constructed mode is healthy        |
| Seasonal ranked ladder + MMR                                     | Competitive progression and retention             | High       | After anti-cheat and reconnect reliability    |
| In-client deck analytics (curve, essence balance, matchup hints) | Better onboarding and strategic depth             | Medium     | Early post-v1                                 |
| Keyword-rich card interactions (combo windows, reaction chains)  | Signature gameplay identity                       | High       | Expand gradually with guardrails              |
| Tournament brackets/private lobbies                              | Community events and creator ecosystem            | Medium     | Mid-term once lobbies are robust              |
| Cosmetic progression only (boards, card backs, VFX)              | Monetization without pay-to-win risk              | Medium     | Any time after core loop trust is established |

## Anti-Features (Do Not Build Now)

Features likely to slow delivery or destabilize the rules engine in the current continuation phase.

| Anti-Feature                                                            | Why Avoid Now                                                            | What To Do Instead                                          |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------ | ----------------------------------------------------------- |
| RPG-style champion reserve/switch system                                | Mismatch with primary card-game loop and adds unnecessary state branches | Keep board-slot/card-zone model only                        |
| Highly custom one-off card scripting per card without shared primitives | Creates unmaintainable effect code and bug explosion                     | Expand shared effect primitives and compose cards from them |
| Real-time action combat overlays                                        | Conflicts with deterministic turn/event model                            | Keep turn-based action windows and explicit priorities      |
| Full economy/shop/crafting before stable gameplay                       | Pulls focus from correctness and balance                                 | Ship gameplay-first with simple collection stubs            |
| Cross-region global matchmaking in first milestone                      | Infra complexity and fairness issues too early                           | Start single-region or limited-region queues                |
| Heavy client-side rule execution                                        | Increases cheat/desync risk                                              | Client predicts UX only, server confirms truth              |
| Over-designed animation pipeline before rules hardening                 | Visual debt can mask logic debt                                          | Keep concise deterministic animations tied to events        |
| Large content drop (hundreds of cards) before validation tooling        | Balance and QA become unmanageable                                       | Launch with constrained card pool and telemetry             |

## Feature Dependencies

```text
Canonical Card Schema
  -> Deck Builder UI
  -> Deck Code Encoder/Decoder
  -> Deck Validator (server)

Deck Validator (server)
  -> Match Join Eligibility
  -> Ranked/Competitive Queue Safety

Turn Protocol + Action Validation
  -> Effect Resolution Pipeline
  -> Combat Log and Replay Feeds

Effect Resolution Pipeline
  -> Stable Card Keyword System
  -> Advanced Differentiators (Draft, Replay, Spectator)

State Sync (snapshot + events)
  -> Reconnect Recovery
  -> Spectator Mode
  -> Replay Determinism

Telemetry/Event Trace
  -> Balance Iteration
  -> Dispute Debugging
  -> Replay Accuracy
```

## Risk and Complexity Notes (By Delivery Layer)

| Layer                                                                                        | Primary Risks                                     | Complexity | Mitigation                                                       |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------- | ---------- | ---------------------------------------------------------------- |
| Shared domain schema (`shared/core`, card DB)                                                | Type drift and implicit rule assumptions          | Medium     | Versioned schema contracts and validation tests                  |
| Validation layer (`server/core/DeckValidator.js`)                                            | Illegal decks passing edge cases                  | High       | Property-based tests + strict server revalidation                |
| Match orchestration (`server/core/GameInstance.js`, `server/network/SocketHandler.js`)       | Reconnect race conditions, stale socket ownership | High       | Session tokens, authoritative slot claims, timeout state machine |
| Resolution engine (`engine/CombatEngine.js`, `engine/CombatResolver.js`, `shared/effects/*`) | Trigger loops, non-deterministic ordering         | High       | Hard ordering rules, max recursion depth, event caps             |
| Client renderer (`public/js/render/*`)                                                       | Visual desync vs server truth                     | Medium     | Event IDs + periodic canonical snapshot reconciliation           |
| UX flow (`public/js/index.js`)                                                               | Invalid action affordances and player confusion   | Medium     | Action gating from server legal-move responses                   |

## Brownfield Continuation Priorities

1. Lock canonical card/deck contracts first (schema + validator + deck code).
2. Harden server-authoritative turn/action protocol before adding new card keywords.
3. Introduce replay/spectator only after event contracts and ordering are stable.
4. Expand content breadth (new cards/modes) only after validation and telemetry baselines are in place.

## Suggested v1 Acceptance Slice

1. Legal deck can be built/imported/exported and always revalidated on server join.
2. Two players can complete a full match with deterministic turn progression.
3. All card actions resolve through event pipeline with ordered logs.
4. Disconnect/reconnect and concede terminate or recover matches safely.
5. Server snapshot can fully reconstruct client board state at any turn boundary.

## Confidence Notes

- **High confidence:** server-authoritative loop, deck validation criticality, deterministic event ordering as table stakes.
- **Medium confidence:** milestone timing for replay/spectator/ranked (depends on team velocity and infra budget).
- **Low confidence:** monetization sequencing details (not enough product/business input yet).
