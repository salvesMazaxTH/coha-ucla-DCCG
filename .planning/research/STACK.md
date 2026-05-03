# Technology Stack (2026) - UCLA Card Game Continuation

Context: brownfield continuation of an existing browser multiplayer card game using Node.js + Express + Socket.IO + vanilla JS, with heavy reuse of architecture principles from GAME_ARCHITECTURE_v6_2 (server-authoritative state, shared domain model, event-driven effects/hooks, deterministic action/event envelopes).

## Recommended Runtime and Frameworks

- Runtime: Node.js 22 LTS (production baseline), Node.js 24 (optional for local/dev only until full compatibility validation).
- Server HTTP/API: Express 5.2.x (ESM-compatible, modernized routing/error behavior, minimal disruption from current structure).
- Realtime transport: Socket.IO 4.8.x (keep as authoritative multiplayer transport and event contract layer).
- Client app layer: Vanilla JS + ES Modules (keep current rendering and state mapping architecture; no frontend framework migration in this milestone).
- Shared game logic: Continue isomorphic modules under shared/ for canonical rules, DTO/event envelope shapes, effect pipeline primitives.
- Styling: Keep existing CSS/Tailwind usage as-is for now; postpone Tailwind v4 migration.

## Keep As-Is

- Server-authoritative gameplay model and validation ownership in backend.
- Shared core model strategy (Entity/GameState/Player/effects primitives in shared/) to avoid rule drift.
- Event-driven effect architecture (EffectBus/hook-style dispatch) and queued deterministic resolution semantics.
- Socket event envelope approach for sequencing actions/logs/state sync.
- Vanilla JS modular renderers (Board/Card/Hand/Hero) and no forced SPA framework rewrite.
- Current Socket.IO major version (4.8.x) unless a known bug requires patch bump.

## Add Next (prioritized)

1. Runtime and package guardrails

- Add engines in package.json: node >=22 <25, npm >=10.
- Add .nvmrc (or Volta config) to standardize local/runtime alignment.
- Why now: reduces environment drift and hard-to-repro networking/state bugs.

2. Shared schema validation at trust boundaries

- Add Zod 4.x for socket payload schemas (join/match/start/play/end-turn/state sync/deck submit).
- Validate all client->server events and normalize server->client envelopes.
- Why now: protects server-authoritative model and avoids malformed payload edge cases.

3. Logging and diagnostics

- Add pino 9.x (server logs) with request/game correlation IDs.
- Add pino-pretty for local development readability.
- Why now: faster debugging of turn-resolution and multiplayer race reports.

4. Test harness for critical game rules

- Add Vitest 2.x for unit/integration tests on DeckValidator, ActionStack, EffectBus, and socket contract adapters.
- Add socket.io-client test helpers to simulate two-player flow in-process.
- Why now: deck/cohesion rules and turn contracts are regression-prone.

5. Lint/format quality floor (minimal)

- Add ESLint 9.x with flat config and a very small rule set focused on correctness (no stylistic churn).
- Optionally add Prettier only if team agrees to codemod/format pass boundaries.
- Why now: catches accidental logic hazards without architecture churn.

6. Optional hardening after above is stable

- Add rate-limiter-flexible (or equivalent) on high-risk socket events (join/spam/end-turn abuse).
- Add tiny metrics endpoint (Prometheus format or lightweight counters) for match health visibility.

## Avoid for now

- Full frontend framework migration (React/Vue/Svelte) during rules/domain stabilization.
- TypeScript full-rewrite across server/shared/client in the same milestone.
- Event sourcing/CQRS or microservices decomposition before core rules are complete.
- Redis/pub-sub horizontal scaling before proving single-instance correctness and reconnect semantics.
- Tailwind v4 migration while UI is not the bottleneck and current CSS/Tailwind hybrid is functioning.
- Database-first redesign before deck/rules/socket contracts are stable (in-memory first is acceptable now).

## Version suggestions and rationale

| Area              | Suggested version                    | Why this version now                                                                         |
| ----------------- | ------------------------------------ | -------------------------------------------------------------------------------------------- |
| Node.js runtime   | 22 LTS baseline                      | Best stability/ops posture for production in 2026 with broad package support.                |
| Express           | 5.2.x                                | Current stable line; low migration cost from existing Express usage, modern semantics.       |
| Socket.IO         | 4.8.x                                | Already current in project and registry; avoid unnecessary transport-layer churn.            |
| Tailwind CSS      | Stay 3.3.x now; evaluate 4.2.x later | v4 exists, but migration is lower priority than gameplay correctness and contract hardening. |
| Schema validation | Zod 4.x                              | Mature runtime validation for socket/event payload contracts and shared DTOs.                |
| Testing           | Vitest 2.x                           | Fast ESM-native test runner suitable for shared logic and socket simulation tests.           |
| Logging           | pino 9.x                             | High-performance structured logging with minimal operational overhead.                       |
| Linting           | ESLint 9.x                           | Flat config and modern parser ecosystem; enables incremental quality gates.                  |

## Confidence table (High/Med/Low)

| Recommendation area                                    | Confidence | Basis                                                                                       |
| ------------------------------------------------------ | ---------- | ------------------------------------------------------------------------------------------- |
| Keep Node + Express + Socket.IO + vanilla architecture | High       | Strong fit with existing codebase and PROJECT constraints; minimizes rewrite risk.          |
| Node 22 LTS as production baseline                     | Med        | Industry practice and compatibility posture; exact org infra constraints still unknown.     |
| Express 5.2.x upgrade path                             | High       | Current npm stable and close conceptual fit to existing server structure.                   |
| Keep Socket.IO at 4.8.x                                | High       | npm shows current stable as 4.8.3; already used in repo.                                    |
| Add Zod for event/deck payload validation              | High       | Directly addresses server-authoritative trust boundary risk with low integration cost.      |
| Add Vitest for shared rules and socket contracts       | High       | Strong compatibility with ESM and brownfield incremental test adoption.                     |
| Postpone Tailwind v4 migration                         | Med        | Pragmatic sequencing choice; should be revisited when UI velocity becomes priority.         |
| Avoid TS full rewrite now                              | Med        | Common brownfield risk tradeoff; may change if team commits to phased typed migration plan. |

Sources used for version grounding (2026-05-03):

- npm registry checks: express (5.2.1), socket.io (4.8.3), tailwindcss (4.2.4)
- Workspace files analyzed: .planning/PROJECT.md, GAME_ARCHITECTURE_v6_2 (current).md, package.json, README.md
