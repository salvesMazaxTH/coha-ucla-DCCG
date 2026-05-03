<!-- GSD:project-start source:PROJECT.md -->
## Project

**UCLA Card Game Continuation**

Continuidade de um card game multiplayer server-authoritative, evoluindo de um prototipo incompleto para uma base de producao modular e escalavel. O objetivo e reutilizar ao maximo os padroes arquiteturais do RPG turn-based documentado em `GAME_ARCHITECTURE_v6_2 (current).md`, adaptando o que fizer sentido para mecanicas de cartas. O produto final inclui fluxo de deckbuilding dedicado no client e validacao completa de deck no backend.

**Core Value:** A regra de deck e a resolucao de jogo devem ser corretas e server-authoritative, com arquitetura modular que permita expandir cartas/efeitos sem retrabalho estrutural.

### Constraints

- **Architecture**: Reutilizar ao maximo arquitetura do RPG (pipeline/eventos/delegacao) — consistencia e escalabilidade
- **Authority**: Backend valida tudo e define estado canonico — integridade competitiva
- **Compatibility**: Aproveitar estrutura existente sem quebrar o fluxo atual de renderizacao — evolucao incremental
- **Scope**: Priorizar regras de deck e fluxo deckbuilder antes de features cosmeticas — reduzir risco funcional
- **Quality**: Evitar duplicacao de logica entre client e server — mesma semantica com responsabilidades separadas
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Snapshot
- Project type: Node.js multiplayer card game prototype with shared domain modules.
- Runtime model: server-side authoritative simulation with browser client rendering.
- Language standard: JavaScript ES Modules (`"type": "module"` in `package.json`).
## Core Runtime
- Node.js runtime for backend entrypoint: `server/server.js`.
- HTTP framework: `express` ^4.22.1.
- Realtime transport: `socket.io` ^4.8.3.
- Build step: none required for runtime (plain ESM scripts).
## Frontend Stack
- Plain HTML/CSS/JS in `public/index.html` and `public/js/*`.
- Rendering strategy: manual DOM renderers in:
- Styling: Tailwind config exists in `tailwind.config.js`, plus custom CSS at `public/css/card-styles.css`.
## Shared Domain Layer
- Shared game model in `shared/core/*` (`Entity`, `Creature`, `Player`, `GameState`, `ActionStack`).
- Shared effects in `shared/effects/*` (`EffectBus`, keyword/status registries).
- Shared utility for deck serialization in `shared/utils/DeckCoder.js`.
## Dependency Footprint
- Runtime deps are intentionally small (`express`, `socket.io`).
- Dev deps currently include only `tailwindcss`.
- No TypeScript, ORM, test framework, linting, formatter, or migration tooling configured yet.
## Scripts
- `npm start` -> `node server/server.js`
- `npm run dev` -> `node --watch server/server.js`
## Config and Environment
- Port is read from `process.env.PORT` with fallback 3000 in `server/server.js`.
- CORS for Socket.IO is open (`origin: "*"`), suitable for prototype only.
## Technical Notes
- Current architecture already matches a server-authoritative approach from the RPG architecture doc.
- Combat domain logic is split between `engine/*` and `shared/*`, which is good for future module extraction.
- No package lock enforcement strategy beyond npm defaults (`package-lock.json` present).
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

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
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## Current Architecture Pattern
- Pattern: lightweight layered architecture with server-authoritative simulation.
- Layers:
## Runtime Data Flow
## Core Domain Abstractions
- `Entity` is base primitive for combat participants.
- `Player` extends `Entity` and owns deck/hand/board resources.
- `Creature` extends `Entity` and models in-board units.
- `GameState` is aggregate root for players/entities/turn metadata.
- `ActionStack` provides ordered effect execution and chain processing.
## Combat/Effector Design
- Validation separated from resolution:
- Event bus strategy:
## What Aligns with RPG Architecture
- Server-authoritative state and intent-based client actions.
- Pipeline/event-hook style combat extensibility.
- Domain delegation and clear separations for state, effects, and transport.
## Structural Gaps
- No explicit match/session aggregate (equivalent to RPG `GameMatch`) yet.
- Partial event naming mismatches between frontend and backend.
- Deckbuilding and validation rules are not aligned with desired card-game requirements.
## Suggested Build Order
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
