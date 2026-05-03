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
  const matchmakingQueue = [];
  const games = new Map();
  const socketContext = new Map();

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

  function buildPlayer(socketId, seat, deckIds) {
    const deck = deckIds.map((id) => new Card(cardDB[id]));
    return new Player(seat, `Player-${socketId.slice(0, 4)}`, deck);
  }

  async function startMatch(p1Entry, p2Entry) {
    const gameId = `game-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    const game = new GameInstance(
      gameId,
      { player: buildPlayer(p1Entry.socket.id, "p1", p1Entry.deckIds) },
      { player: buildPlayer(p2Entry.socket.id, "p2", p2Entry.deckIds) },
    );
    games.set(gameId, game);

    p1Entry.socket.join(gameId);
    p2Entry.socket.join(gameId);

    socketContext.set(p1Entry.socket.id, { gameId, playerId: "p1" });
    socketContext.set(p2Entry.socket.id, { gameId, playerId: "p2" });

    p1Entry.socket.emit(ServerEvents.MATCH_FOUND, { gameId, playerId: "p1" });
    p2Entry.socket.emit(ServerEvents.MATCH_FOUND, { gameId, playerId: "p2" });

    await game.startMatch();
    emitStateAndMaybeGameOver(gameId);
  }

  io.on("connection", (socket) => {
    socket.on(ClientEvents.SUBMIT_DECK, async ({ deckCode }) => {
      const decoded = DeckCoder.decode(deckCode);
      const validation = DeckValidator.validateDetailed(decoded);

      if (!validation.valid) {
        socket.emit(ServerEvents.DECK_REJECTED, validation.error);
        return;
      }

      socket.emit(ServerEvents.DECK_ACCEPTED, { valid: true });

      const entry = { socket, deckIds: decoded };
      matchmakingQueue.push(entry);

      if (matchmakingQueue.length >= 2) {
        const p1 = matchmakingQueue.shift();
        const p2 = matchmakingQueue.shift();
        await startMatch(p1, p2);
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
      socketContext.delete(socket.id);
      const queueIndex = matchmakingQueue.findIndex(
        (entry) => entry.socket.id === socket.id,
      );
      if (queueIndex >= 0) {
        matchmakingQueue.splice(queueIndex, 1);
      }
    });
  });
}
