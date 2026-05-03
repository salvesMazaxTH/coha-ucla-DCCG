/**
 * EffectBus.js
 * Gerencia a propagação de eventos para todas as entidades ativas.
 */
export class EffectBus {
  static emit(eventName, payload, gameState) {
    const results = [];

    // Coleta todos os interessados: Jogadores + Criaturas no Board
    const listeners = [
      gameState.players.p1,
      gameState.players.p2,
      ...gameState.players.p1.board,
      ...gameState.players.p2.board,
    ].filter((e) => e && e.alive);

    for (const entity of listeners) {
      // 1. Verificar Keywords (Passivas nativas)
      if (entity.keywords && entity.keywords.has(eventName)) {
        // Lógica específica para keywords que reagem a eventos
      }

      // 2. Verificar Status Effects (Buffs/Debuffs/DoTs)
      if (entity.statusEffects) {
        for (const effect of entity.statusEffects) {
          if (effect.hooks && typeof effect.hooks[eventName] === "function") {
            const res = effect.hooks[eventName]({
              ...payload,
              self: entity,
              effect: effect,
              gameState,
            });
            if (res) results.push(res);
          }
        }
      }

      // 3. Verificar Triggers de Carta (onEnterBoard, lastBreath)
      if (
        entity.cardTriggers &&
        typeof entity.cardTriggers[eventName] === "function"
      ) {
        entity.cardTriggers[eventName]({ ...payload, self: entity, gameState });
      }
    }

    return results;
  }
}
