# INTEGRATIONS

## Network Integration

- WebSocket-like realtime layer via Socket.IO.
- Server initializes Socket.IO in `server/server.js`.
- Client connects using global `io()` in `public/js/index.js`.

## Socket Event Surface (Current)

- Outbound from server:
  - `gameState` (initial snapshot)
  - `gameStateUpdate` (from `server/network/SocketHandler.js`)
  - `error` (deck/action failures)
- Inbound to server:
  - `joinGame` (deck code handshake)
  - `action:playCard` (play action)
  - `endTurnClicked` (client emits, server handler not implemented yet)

## Data Contracts

- Deck code transport:
  - Encoded on client/server via `shared/utils/DeckCoder.js`.
  - Decoded and validated in `server/network/SocketHandler.js` + `server/core/DeckValidator.js`.
- Game state snapshot:
  - Produced by `GameInstance.getSnapshotFor()` and `GameState.serialize(viewerId)`.

## HTTP Integration

- Static hosting only (Express static middleware) from `public/` in `server/server.js`.
- No REST API endpoints currently exposed.

## External Services

- No external DB, cache, queue, auth provider, webhook, or cloud service integration detected.
- No telemetry/monitoring integration (Sentry, Datadog, OpenTelemetry) detected.

## Browser Libraries (CDN)

- Socket.IO client loaded in `public/index.html`.
- Optional debug tooling references in README (Eruda), but production intent is unclear.

## Security Integration Status

- No authentication/session identity layer on sockets yet.
- No signed deck payload or anti-tamper checksum for deck codes.
- CORS permissive (`*`) should be tightened before deployment.

## Integration Gaps to Address

- Implement full matchmaking path referenced in `handleMatchmaking(...)` from `server/network/SocketHandler.js`.
- Align client event names with server (`endTurnClicked` vs expected server handler names).
- Add handshake identity and room management before real multiplayer sessions.
