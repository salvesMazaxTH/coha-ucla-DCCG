import { registerEntityView } from "../state/EntityViewMap.js";

const CARD_PLACEHOLDER_ART = "/assets/cards/card-placeholder.svg";

export function renderCard(entity) {
  const el = document.createElement("div");
  el.className = "card";

  el.dataset.entityId = entity.id;

  el.innerHTML = `
    <div class="card-cost">${entity.cost}</div>
    <div class="card-art">
      <img src="${entity.art || CARD_PLACEHOLDER_ART}" alt="${entity.name || "Card"}">
    </div>
    <div class="card-attack">${entity.attack ?? 0}</div>
    <div class="card-hp">${entity.hp}</div>
    <div class="card-name">${entity.name || entity.id}</div>
  `;

  registerEntityView(entity.id, el);

  return el;
}
