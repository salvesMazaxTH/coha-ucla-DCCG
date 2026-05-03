import { Entity } from "./Entity.js";

export class Creature extends Entity {
  constructor(cardData, ownerId) {
    super(cardData.instanceId, cardData.name, cardData.hp);

    this.baseAttack = cardData.attack; // Para referência em buffs/debuffs
    this.attack = cardData.attack;

    this.cost = cardData.cost;

    this.ownerId = ownerId;

    this.essences = cardData.essences || [];
    this.neutral = this.essences.length === 0;

    this.keywords = new Set(cardData.keywords || []); // Taunt, Haste, etc

    this.cardTriggers = {}; // onEnterBoard, lastBreath, etc

    this.summonedTurn = null;
    this.hasAttackedThisTurn = false;
  }

  serialize() {
    return {
      ...super.serialize(),
      attack: this.attack,
      cost: this.cost,
      essences: this.essences,
      neutral: this.neutral,
      keywords: [...this.keywords],
      summonedTurn: this.summonedTurn,
      hasAttackedThisTurn: this.hasAttackedThisTurn,
      ownerId: this.ownerId,
    };
  }
}
