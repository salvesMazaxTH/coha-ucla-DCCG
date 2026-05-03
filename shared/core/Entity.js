import { CombatResolver } from "../../engine/CombatResolver.js";

export class Entity {
  constructor(id, name, baseHp) {
    this.id = id;
    this.name = name;

    this.baseHp = baseHp;
    this.maxHp = baseHp;
    this.hp = baseHp;

    this.statusEffects = [];
    this.alive = true;
  }

  serialize() {
    return {
      id: this.id,
      name: this.name,
      hp: this.hp,
      maxHp: this.maxHp,
      alive: this.alive,
    };
  }

  takeDamage(amount, context) {
    if (!this.alive) return 0;

    this.hp -= amount;

    if (this.hp <= 0) {
      this.hp = 0;
    }

    context.visualEvents.push({
      type: "DAMAGE",
      targetId: this.id,
      amount: amount,
      hpAfter: this.hp,
    });

    // DeathResolver processes all deaths after the full combat exchange completes, so we don't call die() here.
    return amount;
  }

  heal(amount, context) {
    if (!this.alive) return;

    this.hp = Math.min(this.hp + amount, this.maxHp);

    context.visualEvents.push({
      type: "HEAL",
      targetId: this.id,
      amount,
      hpAfter: this.hp,
    });
  }

  // Called by the attacker to deal damage to a target entity.
  dealDamage(amount, target, context) {
    CombatResolver.applyDamage(this, target, amount, context);
  }

  // Marks the entity as dead and emits a generic DEATH event.
  // For creatures, prefer DeathResolver which handles board removal and graveyard.
  die(context) {
    this.alive = false;
    context.visualEvents.push({
      type: "DEATH",
      targetId: this.id,
    });
  }
}
