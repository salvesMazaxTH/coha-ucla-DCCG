import { renderCard } from "./CardRenderer.js";

export function renderBoard(board, containerId, options = {}) {
  const boardEl = document.getElementById(containerId);
  if (!boardEl) return;

  const { onSlotClick, selectedSlot = null } = options;
  const slots = 6;

  boardEl.innerHTML = "";

  for (let slotIndex = 0; slotIndex < slots; slotIndex += 1) {
    const slotEl = document.createElement("div");
    slotEl.className = "board-slot";
    slotEl.dataset.slot = String(slotIndex);

    if (selectedSlot === slotIndex) {
      slotEl.classList.add("ring-2", "ring-neon", "shadow-neon-soft");
    }

    const creature = board[slotIndex];
    if (creature) {
      const card = renderCard(creature);
      card.classList.add("card-board");
      slotEl.appendChild(card);
    }

    if (typeof onSlotClick === "function") {
      slotEl.addEventListener("click", () => onSlotClick(slotIndex));
    }

    boardEl.appendChild(slotEl);
  }
}
