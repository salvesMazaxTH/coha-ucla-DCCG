import { DeckCoder } from "/shared/utils/DeckCoder.js";

const TARGET_SIZE = 48;

const cardListEl = document.getElementById("card-list");
const deckEntriesEl = document.getElementById("deck-entries");
const deckSizeEl = document.getElementById("deck-size");
const precheckEl = document.getElementById("precheck");
const deckCodeEl = document.getElementById("deck-code");

let cards = [];
const deck = new Map();

function getCopyLimit(card) {
  if (card.type === "Champion") return 2;
  if (card.rarity === "Legendary") return 3;
  return 4;
}

function deckArrayFromMap() {
  const out = [];
  for (const [id, count] of deck.entries()) {
    for (let i = 0; i < count; i += 1) {
      out.push(id);
    }
  }
  return out;
}

function sharesEssence(cardA, cardB) {
  if (!cardA.essences?.length || !cardB.essences?.length) return false;
  return cardA.essences.some((essence) => cardB.essences.includes(essence));
}

function runPrecheck() {
  const allCards = deckArrayFromMap()
    .map((id) => cards.find((c) => c.id === id))
    .filter(Boolean);

  const sizeOk = allCards.length === TARGET_SIZE;
  const limitViolations = [];
  for (const [id, count] of deck.entries()) {
    const card = cards.find((item) => item.id === id);
    if (!card) continue;
    const limit = getCopyLimit(card);
    if (count > limit) {
      limitViolations.push(`${card.name}: ${count}/${limit}`);
    }
  }

  const nonNeutral = allCards.filter((card) => card.essences?.length > 0);
  const cohesionViolations = nonNeutral
    .filter(
      (card, idx) =>
        !nonNeutral.some(
          (other, otherIdx) => otherIdx !== idx && sharesEssence(card, other),
        ),
    )
    .map((card) => card.name);

  const messages = [];
  messages.push(
    sizeOk ? "Tamanho: OK" : `Tamanho: ${allCards.length}/${TARGET_SIZE}`,
  );
  messages.push(
    limitViolations.length
      ? `Copias: erro (${limitViolations.join(", ")})`
      : "Copias: OK",
  );
  messages.push(
    cohesionViolations.length
      ? `Coesao: erro (${cohesionViolations.join(", ")})`
      : "Coesao: OK",
  );

  precheckEl.innerHTML = messages.map((msg) => `<p>${msg}</p>`).join("");
  deckSizeEl.textContent = `${allCards.length} / ${TARGET_SIZE} cartas`;
}

function renderDeck() {
  const entries = [...deck.entries()]
    .map(([id, count]) => {
      const card = cards.find((item) => item.id === id);
      if (!card) return null;
      return { card, count };
    })
    .filter(Boolean)
    .sort(
      (a, b) => b.count - a.count || a.card.name.localeCompare(b.card.name),
    );

  deckEntriesEl.innerHTML = "";
  for (const entry of entries) {
    const li = document.createElement("li");
    li.className =
      "rounded-lg border border-white/15 px-3 py-2 bg-black/20 flex items-center justify-between";
    li.innerHTML = `<span>${entry.card.name}</span><span class="text-mint font-semibold">x${entry.count}</span>`;
    deckEntriesEl.appendChild(li);
  }

  runPrecheck();
}

function addCard(card) {
  const currentDeckSize = deckArrayFromMap().length;
  if (currentDeckSize >= TARGET_SIZE) return;

  const current = deck.get(card.id) || 0;
  const limit = getCopyLimit(card);
  if (current >= limit) return;
  deck.set(card.id, current + 1);
  renderDeck();
}

function removeCard(card) {
  const current = deck.get(card.id) || 0;
  if (current <= 1) {
    deck.delete(card.id);
  } else {
    deck.set(card.id, current - 1);
  }
  renderDeck();
}

function renderCatalog() {
  cardListEl.innerHTML = "";
  cards.forEach((card) => {
    const wrapper = document.createElement("article");
    wrapper.className = "rounded-xl border border-white/15 bg-black/25 p-3";
    wrapper.innerHTML = `
      <p class="text-xs text-mist">${card.type} - ${card.rarity}</p>
      <h3 class="font-bold">${card.name}</h3>
      <p class="text-xs text-mist mt-1">Essencias: ${card.essences.length ? card.essences.join(", ") : "neutra"}</p>
      <div class="mt-3 flex gap-2">
        <button class="add px-3 py-1 rounded bg-mint/20 border border-mint/50 hover:bg-mint/30">+1</button>
        <button class="remove px-3 py-1 rounded bg-ember/20 border border-ember/50 hover:bg-ember/30">-1</button>
      </div>
    `;

    wrapper
      .querySelector(".add")
      .addEventListener("click", () => addCard(card));
    wrapper
      .querySelector(".remove")
      .addEventListener("click", () => removeCard(card));
    cardListEl.appendChild(wrapper);
  });
}

async function loadCards() {
  const response = await fetch("/api/cards");
  const payload = await response.json();
  cards = payload.cards || [];
  renderCatalog();
  renderDeck();
}

document.getElementById("clear-deck")?.addEventListener("click", () => {
  deck.clear();
  renderDeck();
});

document.getElementById("generate-code")?.addEventListener("click", () => {
  deckCodeEl.value = DeckCoder.encode(deckArrayFromMap());
});

document.getElementById("import-code")?.addEventListener("click", () => {
  const decoded = DeckCoder.decode(deckCodeEl.value.trim());
  if (!decoded) return;

  deck.clear();
  decoded.forEach((id) => {
    const card = cards.find((item) => item.id === id);
    if (!card) return;
    deck.set(id, (deck.get(id) || 0) + 1);
  });
  renderDeck();
});

document
  .getElementById("validate-backend")
  ?.addEventListener("click", async () => {
    const deckCode =
      deckCodeEl.value.trim() || DeckCoder.encode(deckArrayFromMap());
    deckCodeEl.value = deckCode;

    const response = await fetch("/api/decks/validate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ deckCode }),
    });

    const payload = await response.json();
    if (response.ok) {
      precheckEl.innerHTML = `<p class="text-emerald-300">Backend: deck valido.</p>`;
      return;
    }

    precheckEl.innerHTML = `<p class="text-rose-300">Backend rejeitou (${payload.error?.rule || "unknown"}): ${payload.error?.message || "erro"}</p>`;
  });

document.getElementById("save-and-play")?.addEventListener("click", () => {
  const code = deckCodeEl.value.trim() || DeckCoder.encode(deckArrayFromMap());
  deckCodeEl.value = code;
  localStorage.setItem("selectedDeckCode", code);
  window.location.href = "/index.html";
});

loadCards();
