import { renderCard } from "./CardRenderer.js";

export function renderHand(hand, containerId, options = {}) {
  const handEl = document.getElementById(containerId);
  if (!handEl) return;

  const { onCardClick } = options;

  handEl.innerHTML = "";

  hand.forEach((card, index) => {
    const cardEl = renderCard(card);
    cardEl.classList.add("card-hand");
    cardEl.classList.add("hand-card", `hand-card-${Math.min(index, 4)}`);
    cardEl.dataset.handIndex = String(index);

    if (typeof onCardClick === "function") {
      cardEl.addEventListener("click", () => onCardClick(index));
    }

    handEl.appendChild(cardEl);
  });
}
