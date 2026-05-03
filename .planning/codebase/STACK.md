# STACK

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
  - `public/js/render/BoardRenderer.js`
  - `public/js/render/HandRenderer.js`
  - `public/js/render/HeroRenderer.js`
  - `public/js/render/CardRenderer.js`
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
