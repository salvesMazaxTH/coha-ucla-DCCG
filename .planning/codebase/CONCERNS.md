# CONCERNS

## Critical Concerns

- Deck constraints are currently incorrect for target game rules:
  - `server/core/DeckValidator.js` enforces 30 cards and max 3 copies.
  - Target spec requires 48 cards and nuanced copy limits by type/rarity.
- Essence cohesion rule is missing entirely in backend validation.
- Server-authoritative principle is incomplete while deckbuilder and deck schema are undefined.

## Functional Gaps

- `public/js/index.js` still has TODO/test scaffolding and partial mock rendering.
- `server/network/SocketHandler.js` references `handleMatchmaking(...)` without visible implementation.
- Socket event mismatch indicates unfinished turn flow wiring.

## Architecture Gaps vs RPG Baseline

- No explicit match/session boundary object equivalent to RPG `GameMatch` orchestration.
- Event pipeline abstraction exists but is still shallow compared with RPG structured combat pipeline.
- Missing robust context/event envelope standards for consistent client playback.

## Data Integrity Risks

- `DeckCoder` decode returns `null` on error, but socket path may not guard all null/shape cases.
- Card model in `public/data/cardDB.js` is prototype-level and does not encode full rarity/type semantics.
- `shared/effects/Keywords.js` is empty, indicating unfinished keyword registry source-of-truth.

## Security and Production Readiness

- Open CORS (`*`) for Socket.IO.
- No auth, no rate limit, and no anti-spam/anti-cheat validations.
- No persistence strategy (all state in-memory).

## Maintainability Risks

- README indicates frontend logic is incomplete while code has partial implementation drift.
- Mixed naming and mixed language comments increase onboarding friction.
- No tests means regressions likely during rapid feature expansion.

## Recommended Immediate Mitigations

1. Stabilize shared schema for card/deck metadata and validation constants.
2. Implement authoritative backend deck validation from full rules before feature expansion.
3. Add tests around deck validation and socket action flow.
4. Align client/server event contracts through shared constants.
5. Introduce session/match manager module to structure multiplayer lifecycle.
