import { Creature } from "./Creature.js";

export const CardType = Object.freeze({
  UNIT: "Unit",
  SPELL: "Spell",
  CHAMPION: "Champion",
});

export const CardRarity = Object.freeze({
  COMMON: "Common",
  EPIC: "Epic",
  LEGENDARY: "Legendary",
});

export const CardEssence = Object.freeze({
  OBSCURA: "obscura",
  IGNEA: "ignea",
  ELETRICA: "eletrica",
  SAGRADA: "sagrada",
  AQUATICA: "aquatica",
  GLACIAL: "glacial",
  TERRESTRE: "terrestre",
  AEREA: "aerea",
  CREPUSCULAR: "crepuscular",
});

const VALID_TYPES = new Set(Object.values(CardType));
const VALID_RARITIES = new Set(Object.values(CardRarity));
const VALID_ESSENCES = new Set(Object.values(CardEssence));

export function normalizeEssences(rawEssences) {
  const essences = Array.isArray(rawEssences) ? rawEssences : [];
  const unique = [...new Set(essences.filter(Boolean))];
  if (unique.length > 2) {
    throw new Error("Card cannot define more than 2 essences");
  }

  for (const essence of unique) {
    if (!VALID_ESSENCES.has(essence)) {
      throw new Error(`Invalid essence: ${essence}`);
    }
  }

  return unique;
}

export function isNeutralCard(cardData) {
  return normalizeEssences(cardData?.essences).length === 0;
}

export function validateCardData(cardData) {
  if (!cardData || !cardData.id || !cardData.name) {
    throw new Error("Card must define id and name");
  }

  if (!VALID_TYPES.has(cardData.type)) {
    throw new Error(`Invalid card type: ${cardData.type}`);
  }

  if (!VALID_RARITIES.has(cardData.rarity)) {
    throw new Error(`Invalid card rarity: ${cardData.rarity}`);
  }

  const essences = normalizeEssences(cardData.essences);

  if (
    (cardData.type === CardType.UNIT || cardData.type === CardType.CHAMPION) &&
    (typeof cardData.attack !== "number" || typeof cardData.hp !== "number")
  ) {
    throw new Error("Unit/Champion cards must define attack and hp");
  }

  return {
    ...cardData,
    essences,
    neutral: essences.length === 0,
  };
}

export class Card {
  constructor(cardData) {
    const canonical = validateCardData(cardData);

    this.id = canonical.id;
    this.name = canonical.name;
    this.type = canonical.type;
    this.rarity = canonical.rarity;
    this.essences = canonical.essences;
    this.neutral = canonical.neutral;
    this.cost = canonical.cost ?? 0;
    this.attack = canonical.attack ?? 0;
    this.hp = canonical.hp ?? 0;
    this.keywords = canonical.keywords ?? [];
    this.power = canonical.power ?? null;
  }

  toCreature(ownerId) {
    if (this.type !== CardType.UNIT && this.type !== CardType.CHAMPION) {
      throw new Error("Only Unit/Champion cards can be summoned as creatures");
    }

    return new Creature(
      {
        instanceId: `${this.id}-${Math.random().toString(36).slice(2, 9)}`,
        name: this.name,
        cost: this.cost,
        attack: this.attack,
        hp: this.hp,
        essences: this.essences,
        keywords: this.keywords,
      },
      ownerId,
    );
  }

  serialize() {
    return {
      id: this.id,
      name: this.name,
      type: this.type,
      rarity: this.rarity,
      essences: this.essences,
      neutral: this.neutral,
      cost: this.cost,
      attack: this.attack,
      hp: this.hp,
      keywords: this.keywords,
      power: this.power,
    };
  }
}
