# ARCHITECTURE

## Current Architecture Pattern

- Pattern: lightweight layered architecture with server-authoritative simulation.
- Layers:
  - Transport/entry: `server/server.js`, `server/network/SocketHandler.js`
  - Domain/game orchestration: `server/core/GameInstance.js`
  - Combat engine: `engine/CombatEngine.js`, `engine/CombatResolver.js`
  - Shared model/effects: `shared/core/*`, `shared/effects/*`, `shared/utils/*`
  - UI rendering: `public/js/index.js`, `public/js/render/*`

## Runtime Data Flow

1. Client connects via Socket.IO (`public/js/index.js`).
2. Server emits initial state from `GameInstance.getSnapshotFor(playerId)`.
3. Client action events are sent to server (`action:playCard`, etc.).
4. Server validates and mutates canonical state through `GameInstance` and `ActionStack`.
5. Server emits update payloads and visual events queue to clients.
6. Client renderers redraw board/hand/hero from snapshots.

## Core Domain Abstractions

- `Entity` is base primitive for combat participants.
- `Player` extends `Entity` and owns deck/hand/board resources.
- `Creature` extends `Entity` and models in-board units.
- `GameState` is aggregate root for players/entities/turn metadata.
- `ActionStack` provides ordered effect execution and chain processing.

## Combat/Effector Design

- Validation separated from resolution:
  - `CombatEngine.validateAttack(...)` for legality checks.
  - `CombatResolver.resolve(...)` for damage exchange + death queueing.
- Event bus strategy:
  - `EffectBus.emit(...)` dispatches effect hooks over alive entities.
  - Hooks can react to `beforeDamage`/`afterDamage` and card triggers.

## What Aligns with RPG Architecture

- Server-authoritative state and intent-based client actions.
- Pipeline/event-hook style combat extensibility.
- Domain delegation and clear separations for state, effects, and transport.

## Structural Gaps

- No explicit match/session aggregate (equivalent to RPG `GameMatch`) yet.
- Partial event naming mismatches between frontend and backend.
- Deckbuilding and validation rules are not aligned with desired card-game requirements.

## Suggested Build Order

1. Solidify canonical data model for card types/elements/rarity/deck rules.
2. Refactor deck validation and deck code contract into authoritative shared schema.
3. Add dedicated match/session lifecycle module (rooms, players, turn handshake).
4. Implement deckbuilder page and client-side pre-validation.
5. Expand server checks and integration tests for authoritative validation.
