/**
 * index.js
 *
 * Frontend game logic for Arena dos Campeões
 *
 * This file will contain:
 * - Socket.io connection handling
 * - Game state management
 * - UI event listeners
 * - Card interactions
 * - Board management
 *
 * TODO: Implement game logic
 */

console.log(
  "Game frontend initialized - waiting for game logic implementation",
);

// Socket.io connection placeholder
// const socket = io();

// Game state placeholder
// const gameState = {};

// Event listeners to be implemented
// document.getElementById('end-turn-btn')?.addEventListener('click', () => {});
// document.getElementById('undo-actions-btn')?.addEventListener('click', () => {});
// document.getElementById('surrender-btn')?.addEventListener('click', () => {});

import { renderBoard } from "./render/BoardRenderer.js";
import { renderHand } from "./render/HandRenderer.js";
import { renderHero } from "./render/HeroRenderer.js";
import { ClientEvents, ServerEvents } from "/shared/contracts/SocketEvents.js";

const socket = io();

let gameState = null;
let selectedBoardSlot = 0;
let selectedAttackerId = null;
let localPlayerId = null;
let gameOverPayload = null;

function setGameControlsEnabled(enabled) {
  const endTurnBtn = document.getElementById("end-turn-btn");
  const surrenderBtn = document.getElementById("surrender-btn");

  if (endTurnBtn) endTurnBtn.disabled = !enabled;
  if (surrenderBtn) surrenderBtn.disabled = !enabled;
}

function normalizeReason(reason) {
  if (reason === "surrender") return "Rendicao";
  if (reason === "hero_defeated") return "Heroi derrotado";
  if (reason === "double_ko") return "Empate por nocaute duplo";
  return "Partida encerrada";
}

function showGameOverOverlay(payload) {
  const overlay = document.getElementById("gameover-overlay");
  const title = document.getElementById("gameover-title");
  const subtitle = document.getElementById("gameover-subtitle");

  if (!overlay || !title || !subtitle) return;

  const result = payload?.result || "draw";
  if (result === "victory") {
    title.textContent = "Vitoria";
    title.className = "text-3xl font-extrabold text-emerald-300";
  } else if (result === "defeat") {
    title.textContent = "Derrota";
    title.className = "text-3xl font-extrabold text-rose-300";
  } else {
    title.textContent = "Empate";
    title.className = "text-3xl font-extrabold text-amber-300";
  }

  subtitle.textContent = `${normalizeReason(payload?.reason)}.`;
  overlay.classList.remove("hidden");
}

function showStatus(message, tone = "info") {
  const statusEl = document.getElementById("game-status");
  if (!statusEl) return;

  const toneClass =
    {
      info: "text-white/80",
      ok: "text-emerald-300",
      warn: "text-amber-300",
      error: "text-rose-300",
    }[tone] || "text-white/80";

  statusEl.className = `text-xs font-semibold tracking-wide ${toneClass}`;
  statusEl.textContent = message;
}

socket.on("connect", () => {
  console.log("Connected:", socket.id);
  const deckCode = localStorage.getItem("selectedDeckCode");
  if (deckCode) {
    socket.emit(ClientEvents.SUBMIT_DECK, { deckCode });
    showStatus("Deck enviado. Aguardando oponente...", "info");
  } else {
    showStatus("Selecione um deck no Deckbuilder para entrar na fila.", "warn");
  }
});

function renderState(state) {
  if (gameOverPayload) return;

  gameState = state;

  const attackerStillAlive = state.players.p1.board.some(
    (creature) => creature.id === selectedAttackerId,
  );
  if (!attackerStillAlive) {
    selectedAttackerId = null;
  }

  renderHero(gameState.players.p1, "player-hero", {
    deckId: "player-deck",
    graveyardId: "player-graveyard",
    iconClass: "bx bx-user",
    iconColorClass: "text-neon/50",
  });

  renderHero(gameState.players.p2, "opponent-hero", {
    deckId: "opponent-deck",
    graveyardId: "opponent-graveyard",
    iconClass: "bx bx-bot",
    iconColorClass: "text-neon/40",
  });

  renderBoard(gameState.players.p1.board, "player-board", {
    selectedSlot: selectedBoardSlot,
    onSlotClick: (slotIndex) => {
      selectedBoardSlot = slotIndex;
      const ownCreature = gameState.players.p1.board[slotIndex];
      if (ownCreature) {
        selectedAttackerId = ownCreature.id;
        showStatus(
          `Atacante selecionado: ${ownCreature.name}. Escolha um alvo.`,
          "info",
        );
      } else {
        selectedAttackerId = null;
      }
      renderState(gameState);
    },
  });
  renderBoard(gameState.players.p2.board, "opponent-board", {
    onSlotClick: (slotIndex) => {
      const targetCreature = gameState.players.p2.board[slotIndex];
      if (!targetCreature || !selectedAttackerId) return;
      socket.emit(ClientEvents.ATTACK, {
        attackerId: selectedAttackerId,
        defenderId: targetCreature.id,
      });
      showStatus("Ataque enviado ao servidor.", "info");
    },
  });

  renderHand(gameState.players.p1.hand || [], "player-hand", {
    onCardClick: (handIndex) => {
      if (gameState.activePlayerId !== "p1") {
        showStatus("Nao e seu turno para jogar carta.", "warn");
        return;
      }
      socket.emit(ClientEvents.PLAY_CARD, {
        cardIndex: handIndex,
        slot: selectedBoardSlot,
      });
    },
  });

  const turnLabel = document.getElementById("turn-display");
  if (turnLabel) {
    turnLabel.textContent = `TURNO ${state.turnCount}`;
  }

  showStatus(
    state.activePlayerId === "p1"
      ? "Seu turno. Clique numa carta da mao para jogar."
      : "Turno do oponente.",
    "info",
  );

  const opponentHero = document.querySelector("#opponent-hero .hero-container");
  if (opponentHero) {
    opponentHero.onclick = () => {
      if (!selectedAttackerId) return;
      socket.emit(ClientEvents.ATTACK, {
        attackerId: selectedAttackerId,
        defenderId: "p2",
      });
      showStatus("Ataque ao heroi enviado ao servidor.", "info");
    };
  }
}

socket.on(ServerEvents.GAME_STATE, (state) => {
  renderState(state);
});

socket.on(ServerEvents.DECK_ACCEPTED, () => {
  showStatus("Deck aceito pelo servidor. Entrando na fila...", "ok");
});

socket.on(ServerEvents.MATCH_FOUND, ({ gameId, playerId }) => {
  console.log("Match found", { gameId, playerId });
  localPlayerId = playerId;
  gameOverPayload = null;
  setGameControlsEnabled(true);
  showStatus(`Partida encontrada (${gameId}). Voce e ${playerId}.`, "ok");
});

socket.on(ServerEvents.GAME_OVER, (payload) => {
  gameOverPayload = payload;
  setGameControlsEnabled(false);
  showStatus("Partida encerrada.", "warn");
  showGameOverOverlay(payload);
});

socket.on(ServerEvents.GAME_EVENTS, (events) => {
  console.log("Ordered events", events);
});

socket.on(ServerEvents.SERVER_ERROR, (payload) => {
  console.error("Server action error", payload);
  showStatus(payload?.message || "Erro de acao no servidor.", "error");
});

socket.on(ServerEvents.DECK_REJECTED, (error) => {
  console.error("Deck rejected by server", error);
  showStatus(`Deck rejeitado: ${error?.message || "erro"}`, "error");
  const link = document.getElementById("deckbuilder-link");
  if (link) {
    link.classList.remove("hidden");
  }
});

document.getElementById("end-turn-btn")?.addEventListener("click", () => {
  if (gameOverPayload) return;
  socket.emit(ClientEvents.END_TURN);
});

document.getElementById("surrender-btn")?.addEventListener("click", () => {
  if (gameOverPayload) return;
  if (!localPlayerId) {
    showStatus("Voce ainda nao esta em partida.", "warn");
    return;
  }

  socket.emit(ClientEvents.SURRENDER);
  showStatus("Rendicao enviada ao servidor.", "warn");
});

document
  .getElementById("gameover-deckbuilder-btn")
  ?.addEventListener("click", () => {
    window.location.href = "/deckbuilder.html";
  });

document
  .getElementById("gameover-requeue-btn")
  ?.addEventListener("click", () => {
    window.location.reload();
  });
