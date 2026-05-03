# CONVENTIONS

## Language and Style

- JavaScript ES Modules is the project-wide standard.
- Class-based domain modeling is used for major entities (`Entity`, `Player`, `Creature`, `GameState`).
- Comments are present and pragmatic, often explaining gameplay intent.

## Domain Conventions Observed

- Server owns canonical state and sends serialized snapshots.
- Client renderers do not compute authoritative outcomes.
- Effects are modeled as hooks reacting to named events via `EffectBus`.
- Action sequencing uses explicit queueing (`ActionStack`) to avoid ordering bugs.

## Serialization Conventions

- Core models expose `serialize(...)` methods for transport-safe snapshots.
- Viewer-dependent payload shaping already exists in `Player.serialize(viewerId)`.
- Entity registry uses IDs as canonical references in `GameState.entities`.

## Error Handling Patterns

- Domain validation errors are thrown in core methods (`playCard`, attack validation).
- Socket layer catches and emits user-facing `error` events in some paths.
- Queue executor logs and continues on action errors (`ActionStack.process`).

## Gaps in Conventions

- Inconsistent event naming between client and server (`endTurnClicked` not wired).
- `DeckCoder` relies on `atob`/`btoa`, which is browser-centric and brittle on Node without globals.
- Some modules are placeholders/empty (`shared/effects/Keywords.js`).

## Recommended Coding Standards to Adopt

- Define shared event constants (`shared/constants/events.js`) to avoid name drift.
- Define canonical enums for card type/rarity/essence and deck rule constants.
- Keep validation logic pure and side-effect free where possible.
- Normalize Portuguese/English naming for consistency over time.

## Documentation Conventions

- Keep architecture deltas in `.planning/codebase/*.md` and update after major refactors.
- Track rule changes (deck size, copy limits, essence constraints) in a single source of truth in shared schema.
