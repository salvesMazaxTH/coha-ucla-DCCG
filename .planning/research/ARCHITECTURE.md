# Architecture Patterns

**Domain:** Server-authoritative multiplayer card game
**Researched:** 2026-05-03

## Recommended Architecture

Reuse the RPG architectural principles, not the RPG combat formulas.

Keep these RPG patterns as the backbone:

- Server-authoritative state and action validation
- Shared domain contracts in shared/
- Event-driven effect processing
- Deterministic client rendering from structured envelopes
- Orchestration classes that keep server entrypoints thin

Adaptation thesis for this repository:

- Use GameInstance as the match aggregate root (equivalent role to RPG GameMatch facade)
- Keep GameState as canonical state container and action stack host
- Evolve EffectBus into a scoped, phased hook dispatcher
- Move from direct imperative action side-effects to a staged ActionResolver pipeline

Do not import RPG-only complexity such as elemental multipliers, deep damage modes, or finishing pipelines unless a card explicitly requires them.

## Component Boundaries

### Server Match Layer

| Component                         | Responsibility                                                                                            | Communicates With                                                                           |
| --------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| server/network/SocketHandler.js   | Receives intents, authenticates player/game ownership, validates payload shape, emits snapshots/envelopes | server/core/GameRegistry.js, server/core/GameInstance.js, shared/contracts/NetworkEvents.js |
| server/core/GameRegistry.js (new) | Holds active games, matchmaking queues, lifecycle (create, join, cleanup)                                 | server/core/GameInstance.js, SocketHandler                                                  |
| server/core/GameInstance.js       | Match aggregate root. Owns turn lifecycle, play sequencing, and calls resolver pipelines                  | shared/core/GameState.js, server/core/ActionResolver.js, server/core/TurnManager.js         |

### Shared Domain Layer

| Component                           | Responsibility                                                                                | Communicates With                                                        |
| ----------------------------------- | --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| shared/core/GameState.js            | Canonical mutable state (players, entities, turn metadata, stack) and serialization snapshots | shared/core/Player.js, shared/core/Entity.js, shared/core/ActionStack.js |
| shared/core/CommandIntent.js (new)  | Canonical intent DTOs: PlayCardIntent, AttackIntent, EndTurnIntent                            | SocketHandler, ActionResolver                                            |
| shared/core/EventsEnvelope.js (new) | Deterministic render envelope contract (typed event arrays + state snapshots)                 | ActionResolver, client renderers                                         |
| shared/effects/EffectBus.js         | Hook/event dispatcher over alive entities and status effects                                  | ActionResolver, status/keyword handlers                                  |

### Rules and Resolution Layer

| Component                           | Responsibility                                                                      | Communicates With                                     |
| ----------------------------------- | ----------------------------------------------------------------------------------- | ----------------------------------------------------- |
| server/core/ActionResolver.js (new) | Executes intents in ordered stages (validate, preHooks, apply, postHooks, finalize) | CombatEngine, CombatResolver, EffectBus, GameState    |
| engine/CombatEngine.js              | Pure validation rules for legal attacks/targets                                     | ActionResolver, GameState                             |
| engine/CombatResolver.js            | Damage exchange and death queue orchestration                                       | ActionResolver, EffectBus, GameState                  |
| server/core/DeckValidator.js        | Authoritative deck legality checks and deck rule profile                            | shared/data/cardDB.js, shared/core/DeckRules.js (new) |

### Client Rendering Layer

| Component                        | Responsibility                                    | Communicates With                                       |
| -------------------------------- | ------------------------------------------------- | ------------------------------------------------------- |
| public/js/index.js               | Socket wiring and state handoff to render modules | HandRenderer, BoardRenderer, HeroRenderer, CardRenderer |
| public/js/render/\*              | Visual projection only; no game authority         | server envelopes and snapshots                          |
| public/js/state/EntityViewMap.js | Stable entity-to-view identity mapping            | Render modules                                          |

Boundary rule: no authoritative rules in client renderers. Client can pre-validate UX hints, but backend revalidates everything.

## Data Flow and Authority Boundaries

### Authoritative Flow

1. Client emits intent: joinGame, action:playCard, action:attack, action:endTurn.
2. SocketHandler authenticates socket ownership, validates payload schema, and routes to GameInstance.
3. GameInstance delegates to ActionResolver.
4. ActionResolver runs stage pipeline and mutates GameState through controlled methods.
5. EffectBus emits hooks at deterministic phases.
6. Resolver returns typed EventsEnvelope plus per-player filtered snapshots.
7. SocketHandler emits envelope and snapshots to room.
8. Client renderers consume envelope in order and repaint.

### Authority Matrix

| Concern                                | Client                  | Server                                    |
| -------------------------------------- | ----------------------- | ----------------------------------------- |
| Deck legality                          | Optional UX pre-check   | Authoritative check in DeckValidator      |
| Card ownership and hand index validity | Never trusted           | Authoritative in GameState/ActionResolver |
| Combat targeting rules                 | Optional highlight only | Authoritative in CombatEngine             |
| Damage and deaths                      | Never trusted           | Authoritative in CombatResolver           |
| Trigger hooks and statuses             | Render only             | Authoritative in EffectBus                |
| Turn progression                       | Visual indicator only   | Authoritative in GameInstance/TurnManager |

## Event Pipeline Adaptation (RPG to Card Game)

RPG pattern to keep: numbered, explicit stages with context accumulation and typed outputs.

Card game adaptation:

- Replace DamageEvent-centric pipeline with Action-centric pipeline.
- Keep per-action context object with visual registries, but action type drives stages.

### Proposed Pipeline

ActionResolver.resolve(intent, context)

- Stage 01: validateIntent
  - ownership, turn rights, mana, zone legality, target existence
- Stage 02: collectPreHooks
  - beforeAction, beforeDamage, beforeSummon, beforeDeath, beforeDraw
- Stage 03: applyCoreAction
  - play card, summon, attack exchange, cast spell
- Stage 04: resolveDeathsAndLeaves
  - queue deterministic deaths, lastBreath, remove entities, graveyard moves
- Stage 05: collectPostHooks
  - afterAction, afterDamage, onDeath, onSummon, onCardPlayed
- Stage 06: flushScheduledEffects
  - delayed effects created by hooks (end of action or end of turn)
- Stage 07: buildEnvelope
  - typed events + filtered snapshots + compact action summary

### Context Shape to Adopt

context contains:

- gameId, turn, actingPlayerId, actionId
- visual: playEvents, damageEvents, deathEvents, statusEvents, resourceEvents, drawEvents, summonEvents, logEvents
- registries: registerDamage, registerDeath, registerStatus, registerResourceChange, registerDraw, registerSummon
- queue helpers: schedule(effect), enqueueFollowUp(intent)

This mirrors the RPG context accumulator pattern while staying card-domain-first.

## Build Order Implications

1. Stabilize authority contracts first

- Introduce intent schema validation and a strict event envelope contract.
- Add GameRegistry to decouple matchmaking and per-game lifecycle from socket handlers.

2. Introduce ActionResolver pipeline before adding new card mechanics

- Migrate existing playCard and attack paths to staged resolution.
- Keep behavior equivalent during migration.

3. Expand EffectBus hook vocabulary after pipeline landing

- Add phase-specific hooks and scoped listeners.
- Migrate ad hoc cardTriggers invocations into hook-based dispatch.

4. Update deck system in parallel but behind stable interfaces

- Replace hardcoded 30/3 limits with rules profile supporting 48 cards and rarity caps.
- Keep single authoritative validator entrypoint.

5. Only then add complex mechanics

- Introduce advanced keywords/statuses once deterministic action pipeline and envelope are verified.

Reason for this order: architecture-first migration minimizes regressions and avoids freezing rules into socket handlers.

## Specific Modules and Files to Introduce

### Server

- server/core/GameRegistry.js
  - createGame, joinWaitingGame, getGame, removeGame, cleanupIdleGames
- server/core/TurnManager.js
  - beginTurn, endTurn, passPriority, drawStep, refillStep
- server/core/ActionResolver.js
  - staged action pipeline described above
- server/core/IntentValidator.js
  - payload schema + ownership/turn checks before resolver
- server/core/EnvelopeBuilder.js
  - deterministic envelope and per-player filtered snapshot builder

### Shared

- shared/contracts/NetworkEvents.js
  - single source of truth for socket event names and payload contracts
- shared/core/CommandIntent.js
  - intent constructors and runtime guards
- shared/core/EventsEnvelope.js
  - envelope types and helper factories
- shared/core/DeckRules.js
  - deck-size, rarity-cap, and essence-cohesion rule profile
- shared/effects/HookNames.js
  - canonical hook string enum to avoid drift

### Client

- public/js/network/EventRouter.js
  - maps envelope event groups to render handlers in deterministic order
- public/js/render/EventQueueRenderer.js
  - serially processes envelope event groups, replacing ad hoc queue usage
- public/js/deckbuilder/DeckRulesAdapter.js
  - mirrors UX-level checks from shared deck rules without granting authority

## Explicit Removals and Adaptations

### Remove from card-game core

- RPG damageMode matrix (standard, piercing, absolute) as a global mandatory abstraction.
- RPG elemental affinity formula as default combat rule.
- RPG finishing pipeline semantics as engine-level primitive.
- RPG-specific switch/reserve architecture assumptions.

### Adapt selectively

- Keep only a minimal damageType axis when a card explicitly needs typed mitigation.
- Keep hook scope concept, but use card zones and owners as primary scope dimensions.
- Keep context.schedule, but schedule by card game timing windows (endOfAction, endOfTurn, startOfTurn).
- Keep deterministic envelope sequencing, but event groups should be card-centric (draw, summon, deathrattle, discover, etc.).

### Current brownfield fixes required now

- server/core/DeckValidator.js currently encodes 30-card and max-3-copy legacy values; replace with DeckRules profile.
- server/network/SocketHandler.js currently has inline matchmaking and action side-effects; extract to GameRegistry and ActionResolver.
- shared/effects/EffectBus.js currently mixes keyword/status/card trigger checks in one loop; split listener discovery from hook execution for testability.
- server/core/GameInstance.js currently pushes imperative closures directly to ActionStack; route through ActionResolver stages and envelope builder.

## Anti-Patterns to Avoid

### Anti-Pattern: Rules in Socket Handlers

What: Validation and mutation implemented directly in socket event handlers.
Why bad: Hard to test, duplicates logic, high regression risk.
Instead: Socket handlers only parse, authenticate, route to resolver/services.

### Anti-Pattern: Client-Dependent Legality

What: Assuming client-side pre-validation guarantees legality.
Why bad: Cheating and desync risk.
Instead: All legality checks on server, client is hint-only.

### Anti-Pattern: One giant effect switch

What: Central resolver with huge switch/case for every card effect.
Why bad: Coupling explosion and brittle merges.
Instead: Hook-driven composition with card-local effect modules and shared hook names.

## Scalability Considerations

| Concern         | At 100 users                         | At 10K users                                 | At 1M users                                    |
| --------------- | ------------------------------------ | -------------------------------------------- | ---------------------------------------------- |
| Match lifecycle | In-memory GameRegistry               | Sharded game workers per process             | Distributed coordinator + sticky sessions      |
| Event ordering  | Single process ordering              | Per-game single-threaded execution guarantee | Partition by gameId with ordered stream        |
| Snapshot size   | Full snapshot each action acceptable | Delta snapshots preferred                    | Delta plus compression and event replay        |
| Validation cost | Simple sync checks                   | Cache card metadata and compiled validators  | Rule engine precompilation and profile caching |

## Source Anchors Used

- Existing brownfield modules: GameInstance, GameState, EffectBus, SocketHandler, CombatEngine, CombatResolver, DeckValidator.
- RPG architecture source of patterns: GAME_ARCHITECTURE_v6_2 (current).md (sections on GameMatch facade, TurnResolver, context/event envelopes, hooks, deterministic animation queue, and explicit warning on domain-specific subsystems).

## Final Recommendation

Proceed with an architecture migration that preserves the RPG structural advantages (server authority, staged resolver, context accumulators, deterministic envelopes) while explicitly dropping RPG combat-domain abstractions not required for this card game. The highest-leverage move is introducing ActionResolver plus EnvelopeBuilder, then converging all action paths through that pipeline.
