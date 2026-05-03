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
let inMatch = false;
let lobbyRegistered = false;
let lobbyPaired = false;
let lobbyDeckAccepted = false;
let localUsername = "";

const lobbyOverlayEl = document.getElementById("lobby-overlay");
const lobbyUsernameStepEl = document.getElementById("lobby-step-username");
const lobbyWaitingStepEl = document.getElementById("lobby-step-waiting");
const lobbyDeckStepEl = document.getElementById("lobby-step-deck");
const lobbyMessageEl = document.getElementById("lobby-message");
const lobbyPlayerCountEl = document.getElementById("lobby-player-count");
const lobbyOpponentNameEl = document.getElementById("lobby-opponent-name");
const lobbyDeckFeedbackEl = document.getElementById("lobby-deck-feedback");
const lobbyUsernameInputEl = document.getElementById("lobby-username-input");
const lobbyDeckCodeEl = document.getElementById("lobby-deck-code");
const lobbyRegisterBtnEl = document.getElementById("lobby-register-btn");
const lobbySubmitDeckBtnEl = document.getElementById("lobby-submit-deck-btn");

function setLobbyStep(step) {
  if (!lobbyUsernameStepEl || !lobbyWaitingStepEl || !lobbyDeckStepEl) return;

  lobbyUsernameStepEl.classList.toggle("hidden", step !== "username");
  lobbyWaitingStepEl.classList.toggle("hidden", step !== "waiting");
  lobbyDeckStepEl.classList.toggle("hidden", step !== "deck");
}

function showLobbyOverlay(show) {
  if (!lobbyOverlayEl) return;
  lobbyOverlayEl.classList.toggle("hidden", !show);
}

function setLobbyMessage(text, tone = "info") {
  if (!lobbyMessageEl) return;

  const toneClass =
    {
      info: "text-white/80",
      ok: "text-emerald-300",
      warn: "text-amber-300",
      error: "text-rose-300",
    }[tone] || "text-white/80";

  lobbyMessageEl.className = `text-sm font-semibold ${toneClass}`;
  lobbyMessageEl.textContent = text;
}

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
  showLobbyOverlay(true);
  setLobbyStep("username");
  setLobbyMessage("Digite seu nome para entrar na fila.", "info");
  showStatus("Conectado. Aguardando entrada no lobby.", "info");
});

function renderState(state) {
  if (gameOverPayload || !inMatch) return;

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

socket.on(ServerEvents.LOBBY_STATUS, (payload) => {
  const connectedPlayers = payload?.connectedPlayers ?? 0;
  if (lobbyPlayerCountEl) {
    lobbyPlayerCountEl.textContent = String(connectedPlayers);
  }

  if (!lobbyRegistered) {
    setLobbyStep("username");
    return;
  }

  if (!lobbyPaired) {
    setLobbyStep("waiting");
    if (connectedPlayers < 2) {
      setLobbyMessage(
        "Aguardando pelo menos 2 jogadores conectados...",
        "warn",
      );
    } else {
      setLobbyMessage(
        "Jogadores suficientes. Aguardando pareamento...",
        "info",
      );
    }
  }
});

socket.on(ServerEvents.PAIR_READY, ({ playerId, opponentName }) => {
  lobbyPaired = true;
  lobbyDeckAccepted = false;
  localPlayerId = playerId;

  if (lobbyOpponentNameEl) {
    lobbyOpponentNameEl.textContent = opponentName || "Oponente";
  }

  if (lobbySubmitDeckBtnEl) {
    lobbySubmitDeckBtnEl.disabled = false;
  }
  if (lobbyDeckCodeEl) {
    lobbyDeckCodeEl.disabled = false;
    lobbyDeckCodeEl.value = "";
  }
  if (lobbyDeckFeedbackEl) {
    lobbyDeckFeedbackEl.textContent =
      "Cole um deck code valido para confirmar seu deck.";
    lobbyDeckFeedbackEl.className = "text-xs text-white/70";
  }

  setLobbyStep("deck");
  setLobbyMessage("Pareamento pronto. Falta confirmar os decks.", "ok");
});

socket.on(ServerEvents.PAIR_CANCELLED, () => {
  lobbyPaired = false;
  lobbyDeckAccepted = false;

  if (lobbyDeckFeedbackEl) {
    lobbyDeckFeedbackEl.textContent =
      "Pareamento cancelado. Voltando para a fila...";
    lobbyDeckFeedbackEl.className = "text-xs text-amber-300";
  }

  setLobbyStep("waiting");
  setLobbyMessage("Seu oponente desconectou. Reentrando na fila...", "warn");
});

socket.on(ServerEvents.DECK_ACCEPTED, () => {
  lobbyDeckAccepted = true;

  if (lobbySubmitDeckBtnEl) {
    lobbySubmitDeckBtnEl.disabled = true;
  }
  if (lobbyDeckCodeEl) {
    lobbyDeckCodeEl.disabled = true;
  }
  if (lobbyDeckFeedbackEl) {
    lobbyDeckFeedbackEl.textContent =
      "Deck aceito. Aguardando deck do oponente...";
    lobbyDeckFeedbackEl.className = "text-xs text-emerald-300";
  }

  setLobbyMessage("Deck confirmado. Aguardando inicio da partida...", "ok");
  showStatus("Deck confirmado no lobby.", "ok");
});

socket.on(ServerEvents.MATCH_FOUND, ({ gameId, playerId }) => {
  console.log("Match found", { gameId, playerId, localUsername });
  localPlayerId = playerId;
  gameOverPayload = null;
  inMatch = true;
  showLobbyOverlay(false);
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
  setLobbyMessage(payload?.message || "Erro no servidor.", "error");
  showStatus(payload?.message || "Erro de acao no servidor.", "error");
});

socket.on(ServerEvents.DECK_REJECTED, (error) => {
  console.error("Deck rejected by server", error);

  if (!inMatch && lobbyDeckFeedbackEl) {
    lobbyDeckFeedbackEl.textContent = `Deck invalido (${error?.rule || "unknown"}): ${error?.message || "erro"}`;
    lobbyDeckFeedbackEl.className = "text-xs text-rose-300";
    if (lobbySubmitDeckBtnEl) lobbySubmitDeckBtnEl.disabled = false;
    if (lobbyDeckCodeEl) lobbyDeckCodeEl.disabled = false;
  }

  showStatus(`Deck rejeitado: ${error?.message || "erro"}`, "error");
});

document.getElementById("end-turn-btn")?.addEventListener("click", () => {
  if (gameOverPayload || !inMatch) return;
  socket.emit(ClientEvents.END_TURN);
});

document.getElementById("surrender-btn")?.addEventListener("click", () => {
  if (gameOverPayload || !inMatch) return;
  if (!localPlayerId) {
    showStatus("Voce ainda nao esta em partida.", "warn");
    return;
  }

  socket.emit(ClientEvents.SURRENDER);
  showStatus("Rendicao enviada ao servidor.", "warn");
});

document.getElementById("gameover-lobby-btn")?.addEventListener("click", () => {
  window.location.reload();
});

document
  .getElementById("gameover-requeue-btn")
  ?.addEventListener("click", () => {
    window.location.reload();
  });

lobbyRegisterBtnEl?.addEventListener("click", () => {
  const username = lobbyUsernameInputEl?.value?.trim() || "";
  if (!username) {
    setLobbyMessage("Digite um nome de usuario valido.", "warn");
    return;
  }

  localUsername = username;
  lobbyRegistered = true;
  setLobbyStep("waiting");
  setLobbyMessage("Entrando na fila...", "info");
  socket.emit(ClientEvents.REGISTER_PLAYER, { username });
});

lobbyUsernameInputEl?.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    lobbyRegisterBtnEl?.click();
  }
});

lobbySubmitDeckBtnEl?.addEventListener("click", () => {
  if (!lobbyPaired) {
    setLobbyMessage(
      "Voce precisa estar pareado antes de confirmar o deck.",
      "warn",
    );
    return;
  }

  const deckCode = lobbyDeckCodeEl?.value?.trim() || "";
  if (!deckCode) {
    if (lobbyDeckFeedbackEl) {
      lobbyDeckFeedbackEl.textContent = "Cole um deck code antes de confirmar.";
      lobbyDeckFeedbackEl.className = "text-xs text-amber-300";
    }
    return;
  }

  if (lobbySubmitDeckBtnEl) lobbySubmitDeckBtnEl.disabled = true;
  socket.emit(ClientEvents.SUBMIT_DECK, { deckCode });
});

setGameControlsEnabled(false);
