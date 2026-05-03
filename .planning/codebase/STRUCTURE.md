# STRUCTURE

## Top-Level Layout

- `engine/` - Combat rules and resolution primitives.
- `server/` - Runtime server and networking entry modules.
- `shared/` - Isomorphic domain model, effects, and utilities.
- `public/` - Browser assets, game UI scripts, and static resources.
- `README.md` - Project overview and current setup notes.
- `GAME_ARCHITECTURE_v6_2 (current).md` - Full RPG architecture reference used as baseline.

## Server-Side Key Paths

- `server/server.js` - Express + Socket.IO bootstrapping, static serving.
- `server/core/DeckValidator.js` - Deck validation logic (currently minimal, outdated constraints).
- `server/core/GameInstance.js` - Turn operations and action orchestration.
- `server/network/SocketHandler.js` - Socket event wiring and action handlers.

## Shared Domain Key Paths

- `shared/core/Entity.js` - Base entity HP/lifecycle methods.
- `shared/core/Creature.js` - Unit-specific combat data.
- `shared/core/Player.js` - Player resources and hand/deck state.
- `shared/core/GameState.js` - Aggregate game state and serialization.
- `shared/core/ActionStack.js` - Ordered execution queue.
- `shared/effects/EffectBus.js` - Global effect propagation.
- `shared/utils/DeckCoder.js` - Deck encode/decode helper.

## Frontend Key Paths

- `public/index.html` - Main page shell.
- `public/js/index.js` - Main client script and socket integration.
- `public/js/render/*` - Granular renderers for board/hand/cards/heroes.
- `public/data/cardDB.js` - Card definitions (currently very small sample set).

## Naming and Module Conventions

- ESM imports across all folders.
- Mixed comment language (Portuguese + English) across modules.
- Domain classes are PascalCase files; helper utilities are mixed naming.

## Immediate Directory Improvements

- Add `public/deckbuilder/` (or route-specific module split) for dedicated deckbuilding page.
- Add `shared/schema/` for canonical card/deck validation contracts.
- Add `server/match/` for lobby/session orchestration.
- Add `tests/` (unit + integration) to lock server-authoritative constraints.
