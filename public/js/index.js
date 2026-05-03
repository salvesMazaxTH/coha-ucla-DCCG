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

socket.on("connect", () => {
  console.log("Connected:", socket.id);
  const deckCode = localStorage.getItem("selectedDeckCode");
  if (deckCode) {
    socket.emit(ClientEvents.SUBMIT_DECK, { deckCode });
  }
});

function renderState(state) {
  gameState = state;

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

  renderBoard(gameState.players.p1.board, "player-board");
  renderBoard(gameState.players.p2.board, "opponent-board");

  renderHand(gameState.players.p1.hand, "player-hand");
}

socket.on(ServerEvents.GAME_STATE, (state) => {
  renderState(state);
});

socket.on(ServerEvents.MATCH_FOUND, ({ gameId, playerId }) => {
  console.log("Match found", { gameId, playerId });
});

socket.on(ServerEvents.GAME_EVENTS, (events) => {
  console.log("Ordered events", events);
});

socket.on(ServerEvents.SERVER_ERROR, (payload) => {
  console.error("Server action error", payload);
});

socket.on(ServerEvents.DECK_REJECTED, (error) => {
  console.error("Deck rejected by server", error);
  const link = document.getElementById("deckbuilder-link");
  if (link) {
    link.classList.remove("hidden");
  }
});

document.getElementById("end-turn-btn")?.addEventListener("click", () => {
  socket.emit(ClientEvents.END_TURN);
});
