# Roadmap: UCLA Card Game Continuation

## Overview

This roadmap delivers a server-authoritative multiplayer card game by reusing proven RPG architecture patterns (shared contracts, action pipeline, event bus, state authority) where they fit, while explicitly adapting or removing RPG-specific mechanics that are not suitable for card-game rules. Delivery order prioritizes canonical rules and validation correctness first, then user deckbuilding flow, then deterministic multiplayer sync, and finally full verification hardening.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

- [x] **Phase 1: Card Domain and Shared Contracts** - Canonical card model and cross-runtime contracts are established from RPG-inspired foundations.
- [x] **Phase 2: Authoritative Deck Validation** - Backend enforces all deck legality rules with structured errors and trust boundaries.
- [x] **Phase 3: Deckbuilder UX and Revalidation Loop** - Dedicated deckbuilding experience integrates with backend revalidation without client authority.
- [x] **Phase 4: Deterministic Match Flow and Sync** - Multiplayer match lifecycle runs through deterministic server pipeline and ordered state sync.
- [x] **Phase 5: Verification and Protocol Hardening** - Automated tests lock deck rules, deck code contracts, and socket flow reliability.

## Phase Mapping Table

| Phase                                    | Goal                                                                               | Requirements                                                                    |
| ---------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 1 - Card Domain and Shared Contracts     | Canonical card schema and protocol contracts adapted from RPG architecture         | CARD-01, CARD-02, CARD-03, CARD-04, CARD-05, ARCH-02, ARCH-04                   |
| 2 - Authoritative Deck Validation        | Server validates all deck legality and network intents before state mutation       | DECK-01, DECK-02, DECK-03, DECK-04, DECK-05, DECK-06, DECK-07, ARCH-01, ARCH-05 |
| 3 - Deckbuilder UX and Revalidation Loop | Players can build/import/export decks in dedicated UI with backend truth preserved | DBLD-01, DBLD-02, DBLD-03, DBLD-04, DBLD-05                                     |
| 4 - Deterministic Match Flow and Sync    | Validated decks power deterministic multiplayer join/start/turn/state-sync loop    | ARCH-03, SYNC-01, SYNC-02, SYNC-03                                              |
| 5 - Verification and Protocol Hardening  | Critical deck and socket contracts are proven by automated regression tests        | QUAL-01, QUAL-02, QUAL-03                                                       |

## Phase Details

### Phase 1: Card Domain and Shared Contracts

**Goal**: Users interact with a canonical card domain (types, rarity, essence, neutrality) and stable shared contracts that reuse RPG architectural patterns only where meaningful.
**Depends on**: Nothing (first phase)
**Requirements**: CARD-01, CARD-02, CARD-03, CARD-04, CARD-05, ARCH-02, ARCH-04
**Success Criteria** (what must be TRUE):

1. Card definitions consistently expose Unit, Spell, and Champion in shared runtime contracts used by both client and server.
2. Champion cards inherit Unit behavior while preserving distinct, data-driven power characteristics.
3. Rarity and essence metadata (including neutral cards with zero essence) are represented canonically and interpreted the same way on both sides.
4. RPG mechanisms that do not fit card-game semantics are absent or explicitly adapted in the shared model and contracts.
   **Plans**: TBD

### Phase 2: Authoritative Deck Validation

**Goal**: The backend is the sole authority for deck legality and rejects invalid payload intents before any game-state mutation.
**Depends on**: Phase 1
**Requirements**: DECK-01, DECK-02, DECK-03, DECK-04, DECK-05, DECK-06, DECK-07, ARCH-01, ARCH-05
**Success Criteria** (what must be TRUE):

1. Any submitted deck not containing exactly 48 cards is rejected server-side.
2. Copy limits for Champion, Legendary, and other Unit cards are enforced server-side regardless of client behavior.
3. Essence cohesion is validated so every non-neutral card shares at least one essence with another card, while neutral cards do not break validity.
4. Invalid deck or intent submissions return structured, rule-specific errors without mutating authoritative game state.
   **Plans**: TBD

### Phase 3: Deckbuilder UX and Revalidation Loop

**Goal**: Players can reliably construct decks in a dedicated deckbuilder UI while backend revalidation remains the final authority.
**Depends on**: Phase 2
**Requirements**: DBLD-01, DBLD-02, DBLD-03, DBLD-04, DBLD-05
**Success Criteria** (what must be TRUE):

1. Players can access a dedicated deckbuilding page independent of the in-match screen.
2. During deck construction, users receive immediate prevention/feedback for basic size, copy-limit, and format mistakes.
3. Deck export/import produces valid deck codes that can be transmitted to backend validation endpoints.
4. If backend rejects a submitted deck code, the player sees clear and actionable rejection feedback in the deckbuilder flow.
   **Plans**: TBD
   **UI hint**: yes

### Phase 4: Deterministic Match Flow and Sync

**Goal**: Two players can start and progress through a multiplayer match using validated decks and deterministic, ordered server events.
**Depends on**: Phase 3
**Requirements**: ARCH-03, SYNC-01, SYNC-02, SYNC-03
**Success Criteria** (what must be TRUE):

1. Two players can join/start a match only after server deck validation succeeds.
2. Turn actions are accepted only when legal under server rules and are rejected before illegal state mutation.
3. Clients receive ordered server events/snapshots that keep both views synchronized and deterministic during play.
4. Action/effect resolution follows an RPG-inspired pipeline/event-bus approach adapted for card-game combat semantics.
   **Plans**: TBD

### Phase 5: Verification and Protocol Hardening

**Goal**: Critical rule and protocol behavior is continuously verifiable through automated tests that guard against regressions.
**Depends on**: Phase 4
**Requirements**: QUAL-01, QUAL-02, QUAL-03
**Success Criteria** (what must be TRUE):

1. Automated tests detect regressions in authoritative deck legality (size, copies, cohesion).
2. Deck code encode/decode contract tests consistently validate valid and invalid scenarios.
3. Socket integration tests validate the main flow from deck submission through join/start/match progression events.
   **Plans**: TBD

## Progress

| Phase                                   | Plans Complete | Status   | Completed  |
| --------------------------------------- | -------------- | -------- | ---------- |
| 1. Card Domain and Shared Contracts     | 1/1            | Complete | 2026-05-03 |
| 2. Authoritative Deck Validation        | 1/1            | Complete | 2026-05-03 |
| 3. Deckbuilder UX and Revalidation Loop | 1/1            | Complete | 2026-05-03 |
| 4. Deterministic Match Flow and Sync    | 1/1            | Complete | 2026-05-03 |
| 5. Verification and Protocol Hardening  | 1/1            | Complete | 2026-05-03 |
