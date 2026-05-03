# TESTING

## Current Testing Status

- No automated test framework configured in `package.json` scripts.
- No `tests/` directory or unit/integration test files detected.
- No CI pipeline config detected in repository root.

## Existing Validation Mechanisms

- Runtime checks are mostly inline guards in domain methods:
  - `server/core/DeckValidator.js`
  - `engine/CombatEngine.js`
  - `server/core/GameInstance.js`
- These checks are useful but currently unverified by automated suites.

## High-Risk Areas That Need Tests First

1. Deck authoritative validation rules:
   - exact size (48)
   - copy limits by type/rarity
   - essence cohesion rule (critical)
2. Deck code encode/decode roundtrip validity.
3. Socket action authorization and turn integrity.
4. Combat death ordering and event queue consistency.

## Recommended Test Stack

- Unit tests: Vitest or Jest (Vitest preferred for ESM simplicity).
- Integration tests: Socket.IO test harness with in-memory server.
- Optional contract tests: snapshot shape tests for `serialize()` outputs.

## Suggested Test Structure

- `tests/unit/shared/core/*.test.js`
- `tests/unit/server/core/*.test.js`
- `tests/integration/network/*.test.js`
- `tests/fixtures/decks/*.json`

## Immediate Smoke Test Backlog

- `DeckValidator.validate` with valid/invalid 48-card decks.
- `DeckCoder` decode error behavior on malformed payloads.
- `GameInstance.playCard` rejects insufficient mana/full board.
- `CombatResolver.collectDeaths` deterministic ordering by creature id.

## Quality Gate Recommendation

- Block phase completion without passing server-authoritative deck validation tests.
- Require at least one integration test for each new socket action event.
