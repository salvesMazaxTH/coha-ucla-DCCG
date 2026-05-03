/**
 * CombatResolver.js
 * Executa a troca de dano real entre duas entidades.
 *
 * Combat ordering guarantee:
 *
 * Normal combat:
 *   attacker damage
 *   → defender retaliation
 *   → death resolution
 *
 * Quick attack:
 *   attacker damage
 *   → defender retaliation only if still alive
 *   → death resolution
 *
 * Death resolution happens AFTER all damage is applied,
 * ensuring retaliation still occurs even if HP drops to 0.
 */

 import { EffectBus } from "../shared/effects/EffectBus.js";

export class CombatResolver {
  static resolve(attacker, defender, context) {
    const isAttackerQuick = attacker.keywords.has("quickAttack");
    const defenderCanRetaliate = defender.attack > 0;

    if (isAttackerQuick) {
      // Attacker strikes first
      attacker.dealDamage(attacker.attack, defender, context);

      if (defender.hp > 0 && defenderCanRetaliate) {
        defender.dealDamage(defender.attack, attacker, context);
      }

      if (defender.hp <= 0) {
        context.visualEvents.push({
          type: "QUICK_ATTACK_KILL",
          sourceId: attacker.id,
        });
      }
    } else {
      // Simulated simultaneous combat
      attacker.dealDamage(attacker.attack, defender, context);

      if (defenderCanRetaliate) {
        defender.dealDamage(defender.attack, attacker, context);
      }
    }

    // After both damages resolve
    CombatResolver.pushDeathsToStack(context.state, context);
  }

  static applyDamage(source, target, amount, context) {
    const payload = {
      source,
      target,
      amount,
      context,
    };

    EffectBus.emit("beforeDamage", payload, context.state);

    target.takeDamage(payload.amount, context);

    EffectBus.emit("afterDamage", payload, context.state);
  }

  /**
   * Finds all creatures that should die.
   */
  static collectDeaths(gameState) {
    const deaths = [];

    for (const player of Object.values(gameState.players)) {
      for (const creature of player.board) {
        if (creature.hp <= 0 && creature.alive) {
          deaths.push({ creature, owner: player });
        }
      }
    }

    // deterministic order
    deaths.sort((a, b) =>
      String(a.creature.id).localeCompare(String(b.creature.id)),
    );

    return deaths;
  }

  /**
   * Pushes death resolutions into the ActionStack.
   */
  static pushDeathsToStack(gameState, context) {
    const deaths = CombatResolver.collectDeaths(gameState);

    for (const { creature, owner } of deaths) {
      gameState.stack.push(() => {
        CombatResolver.resolveCreatureDeath(creature, owner, context);
      });
    }
  }

  /**
   * Resolves the death of a creature.
   */
  static resolveCreatureDeath(creature, owner, context) {
    // lastBreath triggers before removal
    if (
      typeof creature.hasEffect === "function" &&
      creature.hasEffect("lastBreath") &&
      typeof creature.trigger === "function"
    ) {
      creature.trigger("lastBreath", context);
    }

    creature.alive = false;

    // remove from board
    const index = owner.board.indexOf(creature);
    if (index !== -1) {
      owner.board.splice(index, 1);
    }

    // move to graveyard
    owner.graveyard.push(creature);
    context.state.removeEntity(creature);

    context.visualEvents.push({
      type: "CREATURE_DIED",
      creatureId: creature.id,
      ownerId: owner.id,
    });
  }
}
