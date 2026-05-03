import { DeckCoder } from "../../shared/utils/DeckCoder.js";
import { Card } from "../../shared/core/Card.js";
import { Player } from "../../shared/core/Player.js";
import {
  ClientEvents,
  ErrorCode,
  ServerEvents,
} from "../../shared/contracts/SocketEvents.js";
import { cardDB } from "../../public/data/cardDB.js";
import { DeckValidator } from "../core/DeckValidator.js";
import { GameInstance } from "../core/GameInstance.js";

export function setupSocketHandlers(io) {
  const waitingPlayers = [];
  const games = new Map();
  const pendingMatches = new Map();
  const socketContext = new Map();
  const playerProfiles = new Map();

  function getSocketById(socketId) {
    return io.sockets.sockets.get(socketId) || null;
  }

  function removeFromWaitingPlayers(socketId) {
    let index = waitingPlayers.indexOf(socketId);
    while (index !== -1) {
      waitingPlayers.splice(index, 1);
      index = waitingPlayers.indexOf(socketId);
    }
  }

  function enqueueWaitingPlayer(socketId) {
    removeFromWaitingPlayers(socketId);
    waitingPlayers.push(socketId);
  }

  function emitLobbyStatus() {
    const payload = {
      connectedPlayers: playerProfiles.size,
      queuedPlayers: waitingPlayers.length,
      minimumPlayers: 2,
    };

    for (const socketId of playerProfiles.keys()) {
      io.to(socketId).emit(ServerEvents.LOBBY_STATUS, payload);
    }
  }

  function createPendingMatch(p1SocketId, p2SocketId) {
    const p1Profile = playerProfiles.get(p1SocketId);
    const p2Profile = playerProfiles.get(p2SocketId);
    const p1Socket = getSocketById(p1SocketId);
    const p2Socket = getSocketById(p2SocketId);

    if (!p1Profile || !p2Profile || !p1Socket || !p2Socket) {
      return;
    }

    const pendingMatchId = `pending-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;

    pendingMatches.set(pendingMatchId, {
      id: pendingMatchId,
      players: {
        p1: {
          socketId: p1SocketId,
          username: p1Profile.username,
          deckIds: null,
        },
        p2: {
          socketId: p2SocketId,
          username: p2Profile.username,
          deckIds: null,
        },
      },
    });

    socketContext.set(p1SocketId, { pendingMatchId, playerId: "p1" });
    socketContext.set(p2SocketId, { pendingMatchId, playerId: "p2" });

    p1Socket.emit(ServerEvents.PAIR_READY, {
      pendingMatchId,
      playerId: "p1",
      opponentName: p2Profile.username,
    });

    p2Socket.emit(ServerEvents.PAIR_READY, {
      pendingMatchId,
      playerId: "p2",
      opponentName: p1Profile.username,
    });
  }

  function tryPairPlayers() {
    while (waitingPlayers.length >= 2) {
      const p1SocketId = waitingPlayers.shift();
      const p2SocketId = waitingPlayers.shift();

      if (!p1SocketId || !p2SocketId) {
        continue;
      }
      if (!playerProfiles.has(p1SocketId) || !playerProfiles.has(p2SocketId)) {
        continue;
      }
      if (!getSocketById(p1SocketId) || !getSocketById(p2SocketId)) {
        continue;
      }

      createPendingMatch(p1SocketId, p2SocketId);
    }

    emitLobbyStatus();
  }

  function buildGameOverPayload(game, playerId) {
    const gameOver = game.getGameOver();
    if (!gameOver) return null;

    let result = "draw";
    if (gameOver.winnerId === playerId) {
      result = "victory";
    } else if (gameOver.loserId === playerId) {
      result = "defeat";
    }

    return {
      ...gameOver,
      result,
      playerId,
      opponentId: playerId === "p1" ? "p2" : "p1",
      gameId: game.id,
    };
  }

  function emitGameOver(gameId) {
    const game = games.get(gameId);
    if (!game) return;
    if (!game.getGameOver()) return;
    if (game.gameOverAnnounced) return;

    for (const [socketId, ctx] of socketContext.entries()) {
      if (ctx.gameId !== gameId) continue;
      io.to(socketId).emit(
        ServerEvents.GAME_OVER,
        buildGameOverPayload(game, ctx.playerId),
      );
    }

    game.gameOverAnnounced = true;
  }

  function emitStateAndMaybeGameOver(gameId) {
    const game = games.get(gameId);
    if (!game) return;

    game.resolveGameOverByHealth();
    emitState(gameId);
    emitGameOver(gameId);
  }

  function emitState(gameId) {
    const game = games.get(gameId);
    if (!game) return;

    const snapshots = {
      p1: game.getSnapshotFor("p1"),
      p2: game.getSnapshotFor("p2"),
    };

    for (const [socketId, ctx] of socketContext.entries()) {
      if (ctx.gameId !== gameId) continue;
      const seat = ctx.playerId;
      io.to(socketId).emit(ServerEvents.GAME_STATE, snapshots[seat]);
    }

    const events = game.drainVisualEvents();
    if (events.length > 0) {
      io.to(gameId).emit(ServerEvents.GAME_EVENTS, events);
    }
  }

  function buildPlayer(seat, username, deckIds) {
    const deck = deckIds.map((id) => new Card(cardDB[id]));
    return new Player(seat, username, deck);
  }

  async function startMatchFromPending(pendingMatch) {
    const p1Entry = pendingMatch.players.p1;
    const p2Entry = pendingMatch.players.p2;
    const p1Socket = getSocketById(p1Entry.socketId);
    const p2Socket = getSocketById(p2Entry.socketId);
    if (!p1Socket || !p2Socket) {
      return;
    }

    const gameId = `game-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    const game = new GameInstance(
      gameId,
      {
        player: buildPlayer("p1", p1Entry.username, p1Entry.deckIds),
      },
      {
        player: buildPlayer("p2", p2Entry.username, p2Entry.deckIds),
      },
    );

    games.set(gameId, game);
    pendingMatches.delete(pendingMatch.id);

    p1Socket.join(gameId);
    p2Socket.join(gameId);

    socketContext.set(p1Entry.socketId, { gameId, playerId: "p1" });
    socketContext.set(p2Entry.socketId, { gameId, playerId: "p2" });

    p1Socket.emit(ServerEvents.MATCH_FOUND, {
      gameId,
      playerId: "p1",
      username: p1Entry.username,
      opponentName: p2Entry.username,
    });
    p2Socket.emit(ServerEvents.MATCH_FOUND, {
      gameId,
      playerId: "p2",
      username: p2Entry.username,
      opponentName: p1Entry.username,
    });

    await game.startMatch();
    emitStateAndMaybeGameOver(gameId);
  }

  io.on("connection", (socket) => {
    socket.emit(ServerEvents.LOBBY_STATUS, {
      connectedPlayers: playerProfiles.size,
      queuedPlayers: waitingPlayers.length,
      minimumPlayers: 2,
    });

    socket.on(ClientEvents.REGISTER_PLAYER, ({ username }) => {
      const normalized = typeof username === "string" ? username.trim() : "";
      if (!normalized) {
        socket.emit(ServerEvents.SERVER_ERROR, {
          code: ErrorCode.INVALID_PAYLOAD,
          message: "Username is required",
        });
        return;
      }

      const ctx = socketContext.get(socket.id);
      if (ctx?.gameId) {
        socket.emit(ServerEvents.SERVER_ERROR, {
          code: ErrorCode.INVALID_ACTION,
          message: "Cannot re-register while in a match",
        });
        return;
      }

      playerProfiles.set(socket.id, { username: normalized });
      if (!ctx?.pendingMatchId) {
        enqueueWaitingPlayer(socket.id);
      }

      emitLobbyStatus();
      tryPairPlayers();
    });

    socket.on(ClientEvents.SUBMIT_DECK, async ({ deckCode }) => {
      const ctx = socketContext.get(socket.id);
      if (!ctx?.pendingMatchId || !ctx?.playerId) {
        socket.emit(ServerEvents.SERVER_ERROR, {
          code: ErrorCode.INVALID_ACTION,
          message: "You must be paired before submitting a deck",
        });
        return;
      }

      const pendingMatch = pendingMatches.get(ctx.pendingMatchId);
      if (!pendingMatch) {
        socket.emit(ServerEvents.SERVER_ERROR, {
          code: ErrorCode.INVALID_ACTION,
          message: "Pairing expired. Rejoin queue.",
        });
        return;
      }

      const decoded = DeckCoder.decode(deckCode);
      const validation = DeckValidator.validateDetailed(decoded);

      if (!validation.valid) {
        socket.emit(ServerEvents.DECK_REJECTED, validation.error);
        return;
      }

      pendingMatch.players[ctx.playerId].deckIds = decoded;
      socket.emit(ServerEvents.DECK_ACCEPTED, {
        valid: true,
        waitingForOpponent: true,
      });

      if (pendingMatch.players.p1.deckIds && pendingMatch.players.p2.deckIds) {
        await startMatchFromPending(pendingMatch);
      }
    });

    socket.on(ClientEvents.PLAY_CARD, async ({ cardIndex, slot = 0 }) => {
      const ctx = socketContext.get(socket.id);
      if (!ctx) return;
      const game = games.get(ctx.gameId);
      if (!game) return;

      try {
        game.playCard(ctx.playerId, cardIndex, slot);
        await game.flushStack();
        emitStateAndMaybeGameOver(ctx.gameId);
      } catch (error) {
        socket.emit(ServerEvents.SERVER_ERROR, {
          code: ErrorCode.INVALID_ACTION,
          message: error.message,
        });
      }
    });

    socket.on(ClientEvents.END_TURN, async () => {
      const ctx = socketContext.get(socket.id);
      if (!ctx) return;
      const game = games.get(ctx.gameId);
      if (!game) return;

      try {
        game.endTurn(ctx.playerId);
        await game.flushStack();
        emitStateAndMaybeGameOver(ctx.gameId);
      } catch (error) {
        socket.emit(ServerEvents.SERVER_ERROR, {
          code: ErrorCode.INVALID_ACTION,
          message: error.message,
        });
      }
    });

    socket.on(ClientEvents.ATTACK, async ({ attackerId, defenderId }) => {
      const ctx = socketContext.get(socket.id);
      if (!ctx) return;
      const game = games.get(ctx.gameId);
      if (!game) return;

      try {
        const attacker = game.state.findEntity(attackerId);
        if (!attacker || attacker.ownerId !== ctx.playerId) {
          throw new Error("Invalid attacker");
        }

        game.attack(attackerId, defenderId);
        await game.flushStack();
        emitStateAndMaybeGameOver(ctx.gameId);
      } catch (error) {
        socket.emit(ServerEvents.SERVER_ERROR, {
          code: ErrorCode.INVALID_ACTION,
          message: error.message,
        });
      }
    });

    socket.on(ClientEvents.SURRENDER, () => {
      const ctx = socketContext.get(socket.id);
      if (!ctx) return;
      const game = games.get(ctx.gameId);
      if (!game) return;

      try {
        game.surrender(ctx.playerId);
        emitStateAndMaybeGameOver(ctx.gameId);
      } catch (error) {
        socket.emit(ServerEvents.SERVER_ERROR, {
          code: ErrorCode.INVALID_ACTION,
          message: error.message,
        });
      }
    });

    socket.on("disconnect", () => {
      const ctx = socketContext.get(socket.id);
      socketContext.delete(socket.id);
      playerProfiles.delete(socket.id);
      removeFromWaitingPlayers(socket.id);

      if (ctx?.pendingMatchId && pendingMatches.has(ctx.pendingMatchId)) {
        const pending = pendingMatches.get(ctx.pendingMatchId);
        pendingMatches.delete(ctx.pendingMatchId);

        const opponentSeat = ctx.playerId === "p1" ? "p2" : "p1";
        const opponentSocketId = pending.players[opponentSeat].socketId;

        if (
          playerProfiles.has(opponentSocketId) &&
          getSocketById(opponentSocketId)
        ) {
          socketContext.delete(opponentSocketId);
          enqueueWaitingPlayer(opponentSocketId);
          io.to(opponentSocketId).emit(ServerEvents.PAIR_CANCELLED, {
            reason: "opponent_disconnected",
          });
        }
      }

      tryPairPlayers();
      socketContext.delete(socket.id);
      emitLobbyStatus();
    });
  });
}
