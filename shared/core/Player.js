import { Entity } from "./Entity.js";

export class Player extends Entity {
  constructor(id, name, deck) {
    super(id, name, 25); // HP inicial configurável

    this.mana = 1;
    this.maxMana = 1;
    
    this.hand = [];
    this.deck = deck; // Array de Card instances
    this.graveyard = [];
    this.board = []; // Creature instances em campo
  }

  serialize(viewerId) {
    const isOwner = viewerId === this.id;

    return {
      ...super.serialize(),

      mana: this.mana,
      maxMana: this.maxMana,

      board: this.board.map((c) => c.serialize()),

      hand: isOwner ? this.hand.map((c) => c.serialize()) : undefined,

      handSize: this.hand.length,

      deckSize: this.deck.length,
      graveyardSize: this.graveyard.length,
    };
  }

  drawCard(context) {
    if (this.deck.length === 0) return;
    const card = this.deck.pop();
    this.hand.push(card);

    context.visualEvents.push({
      type: "DRAW_CARD",
      playerId: this.id,
      card: card.serialize(),
    });
  }

  refillMana(turnCount) {
    this.maxMana = Math.min(turnCount, 10);
    this.mana = this.maxMana;
  }
}
