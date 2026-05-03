import {
  //entityView,
  removeEntityView,
  registerEntityView,
  //getEntityView,
} from "../state/EntityViewMap.js";

function buildManaOrbs(mana = 0, maxMana = 0) {
  const slots = 10;
  const safeMana = Math.max(0, Math.min(Number(mana) || 0, slots));
  const safeMaxMana = Math.max(0, Math.min(Number(maxMana) || 0, slots));

  return Array.from({ length: slots }, (_, index) => {
    const isUnlocked = index < safeMaxMana;
    const isActive = index < safeMana;

    if (!isUnlocked) {
      return '<div class="mana-orb inactive"></div>';
    }

    return `<div class="mana-orb ${isActive ? "active" : "inactive"}"></div>`;
  }).join("");
}

export function renderHero(player, containerId, options = {}) {
  const heroRoot = document.getElementById(containerId);
  if (!heroRoot || !player) return;

  const {
    deckId,
    graveyardId,
    iconClass = "bx bx-user",
    iconColorClass = "text-neon/50",
    zoneCardClass = "zone-card",
    zoneCountClass = "zone-count",
  } = options;

  const deckSize = Number(player.deckSize ?? 0);
  const graveyardSize = Number(player.graveyardSize ?? 0);
  const hp = Number(player.hp ?? 0);
  const mana = Number(player.mana ?? 0);
  const maxMana = Number(player.maxMana ?? 0);

  removeEntityView(player.id);

  heroRoot.innerHTML = `
		<div class="hero-container" data-entity-id="${player.id}">
			<i class="${iconClass} text-2xl ${iconColorClass}"></i>
			<div class="hero-hp">${hp}</div>
			<div class="hero-mana">${buildManaOrbs(mana, maxMana)}</div>
		</div>
	`;

  const heroEl = heroRoot.querySelector(".hero-container");
  if (heroEl) {
    registerEntityView(player.id, heroEl);
  }

  if (deckId) {
    const deckEl = document.getElementById(deckId);
    if (deckEl) {
      const countEl = deckEl.querySelector(`.${zoneCountClass}`);
      if (countEl) countEl.textContent = String(deckSize);

      const cardEl = deckEl.querySelector(`.${zoneCardClass}`);
      if (cardEl) {
        cardEl.setAttribute("title", `Deck: ${deckSize}`);
      }
    }
  }

  if (graveyardId) {
    const graveyardEl = document.getElementById(graveyardId);
    if (graveyardEl) {
      const countEl = graveyardEl.querySelector(`.${zoneCountClass}`);
      if (countEl) countEl.textContent = String(graveyardSize);

      const cardEl = graveyardEl.querySelector(`.${zoneCardClass}`);
      if (cardEl) {
        cardEl.setAttribute("title", `Graveyard: ${graveyardSize}`);
      }
    }
  }
}
