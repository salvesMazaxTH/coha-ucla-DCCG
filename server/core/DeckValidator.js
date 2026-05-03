import { cardDB } from "../../public/data/cardDB.js";

export const DECK_CONFIG = {
  EXACT_SIZE: 48,
  INITIAL_HAND: 5,
  COPY_LIMITS: {
    CHAMPION: 2,
    LEGENDARY: 3,
    DEFAULT: 4,
  },
};

function structuredError(rule, message, details = {}) {
  return {
    code: "INVALID_DECK",
    rule,
    message,
    details,
  };
}

function getCopyLimit(card) {
  if (card.type === "Champion") return DECK_CONFIG.COPY_LIMITS.CHAMPION;
  if (card.rarity === "Legendary") return DECK_CONFIG.COPY_LIMITS.LEGENDARY;
  return DECK_CONFIG.COPY_LIMITS.DEFAULT;
}

function sharesAnyEssence(cardA, cardB) {
  if (!cardA?.essences?.length || !cardB?.essences?.length) return false;
  return cardA.essences.some((essence) => cardB.essences.includes(essence));
}

function findCohesionViolations(cards) {
  const nonNeutral = cards.filter(
    (card) => Array.isArray(card.essences) && card.essences.length > 0,
  );
  return nonNeutral
    .filter((card, idx) => {
      return !nonNeutral.some(
        (other, otherIdx) => otherIdx !== idx && sharesAnyEssence(card, other),
      );
    })
    .map((card) => ({ id: card.id, essences: card.essences }));
}

export class DeckValidator {
  static validate(cardIds) {
    return this.validateDetailed(cardIds).valid;
  }

  static validateDetailed(cardIds) {
    if (!Array.isArray(cardIds)) {
      return {
        valid: false,
        error: structuredError(
          "format",
          "Deck payload must be an array of card IDs.",
        ),
      };
    }

    if (cardIds.length !== DECK_CONFIG.EXACT_SIZE) {
      return {
        valid: false,
        error: structuredError(
          "size",
          `Deck must contain exactly ${DECK_CONFIG.EXACT_SIZE} cards.`,
          {
            expected: DECK_CONFIG.EXACT_SIZE,
            actual: cardIds.length,
          },
        ),
      };
    }

    const counts = new Map();
    const unknown = [];

    for (const id of cardIds) {
      counts.set(id, (counts.get(id) || 0) + 1);
      if (!cardDB[id]) unknown.push(id);
    }

    if (unknown.length > 0) {
      return {
        valid: false,
        error: structuredError("format", "Deck contains unknown card IDs.", {
          unknownIds: [...new Set(unknown)],
        }),
      };
    }

    for (const [id, count] of counts.entries()) {
      const card = cardDB[id];
      const limit = getCopyLimit(card);
      if (count > limit) {
        return {
          valid: false,
          error: structuredError(
            "copies",
            "Deck exceeds copy limit for one or more cards.",
            {
              cardId: id,
              cardName: card.name,
              cardType: card.type,
              rarity: card.rarity,
              limit,
              actual: count,
            },
          ),
        };
      }
    }

    const cards = cardIds.map((id) => cardDB[id]);
    const cohesionViolations = findCohesionViolations(cards);
    if (cohesionViolations.length > 0) {
      return {
        valid: false,
        error: structuredError(
          "cohesion",
          "Every non-neutral card must share at least one essence with another card in the deck.",
          { violations: cohesionViolations },
        ),
      };
    }

    return {
      valid: true,
      error: null,
    };
  }
}
