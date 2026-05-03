/**
 * CombatEngine.js
 * Gerencia a lógica de quem pode bater em quem.
 */

import { Player } from "../shared/core/Player.js";

export class CombatEngine {
  /**
   * @param {Creature} attacker - Quem está atacando
   * @param {Entity} target - Alvo (Creature ou Player)
   * @param {Creature[]} enemyBoard - Array de criaturas no campo inimigo
   * @param {GameState} gameState - Estado atual do tabuleiro
   */
  static validateAttack(attacker, target, enemyBoard, gameState) {
    // 1. Checagem de Ataque Anterior
    if (attacker.hasAttackedThisTurn) {
      return { valid: false, reason: "Esta unidade não pode atacar agora." };
    }

    const justSummoned = attacker.summonedTurn === gameState.turnCount;

    if (justSummoned) {
      if (attacker.keywords.has("turbo")) {
        // pode atacar tudo
      } else if (attacker.keywords.has("haste")) {
        if (target instanceof Player) {
          return { valid: false, reason: "Haste cannot attack hero this turn" };
        }
      } else {
        return { valid: false, reason: "Summoning sickness" };
      }
    }

    // 2. Lógica de TAUNT (Provocar)
    const tauntCreatures = enemyBoard.filter(
      (c) => c.alive && c.keywords.has("taunt"),
    );

    if (tauntCreatures.length > 0) {
      // Se existe Taunt, o alvo PRECISA ter Taunt
      const targetHasTaunt = target.keywords && target.keywords.has("taunt");

      if (!targetHasTaunt) {
        return {
          valid: false,
          reason:
            "Você deve atacar as criaturas com Provocar (Taunt) primeiro.",
        };
      }
    }

    return { valid: true };
  }
}
