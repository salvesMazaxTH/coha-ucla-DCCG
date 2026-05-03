import { GameState } from "../../shared/core/GameState.js";
import { CombatEngine } from "../../engine/CombatEngine.js";
import { CombatResolver } from "../../engine/CombatResolver.js";

export class GameInstance {
  constructor(id, p1Data, p2Data) {
    this.id = id;
    this.state = new GameState(p1Data.player, p2Data.player);
    this.visualQueue = []; // Acumula eventos para enviar ao front
    this.eventSequence = 0;
    this.state.activePlayerId = "p1";
  }

  async flushStack() {
    while (this.state.stack.isProcessing || this.state.stack.queue.length > 0) {
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
  }

  async startMatch() {
    this.startTurn("p1");
    await this.flushStack();
  }

  // Ciclo de Turno estilo Hearthstone
  startTurn(playerId) {
    const player = this.state.players[playerId];
    this.state.activePlayerId = playerId;
    this.state.turnCount += 1;

    this.state.stack.push(() => {
      player.refillMana(this.state.turnCount);
      player.drawCard(this.getContext());

      // Retira o status de ataque das criaturas
      player.board.forEach((creature) => {
        creature.hasAttackedThisTurn = false;
      });
    });

    this.getContext().visualEvents.push({
      type: "TURN_STARTED",
      playerId,
      turnCount: this.state.turnCount,
    });
  }

  // Ação de Jogar Carta
  playCard(playerId, cardHandIndex, boardSlotIndex) {
    if (this.state.activePlayerId !== playerId)
      throw new Error("Not your turn");

    const player = this.state.players[playerId];
    const card = player.hand[cardHandIndex];
    if (!card) throw new Error("Card index out of range");
    if (card.type === "Spell")
      throw new Error("Spell play is not implemented yet");

    if (player.mana < card.cost) throw new Error("Mana insuficiente");
    if (player.board.length >= 6) throw new Error("Campo cheio");

    this.state.stack.push(() => {
      player.mana -= card.cost;
      player.hand.splice(cardHandIndex, 1);

      // Transforma a carta em uma Creature no board
      const creature = card.toCreature(playerId);
      player.board.push(creature);
      this.state.registerEntity(creature);

      this.getContext().visualEvents.push({
        type: "playCard",
        playerId,
        cardId: card.id,
        boardSlotIndex,
      });

      // Gatilho de Entrada (OnEnterBoard)
      if (
        typeof creature.hasEffect === "function" &&
        creature.hasEffect("onEnterBoard")
      ) {
        creature.trigger("onEnterBoard", this.getContext());
      }
    });
  }

  endTurn(playerId) {
    if (this.state.activePlayerId !== playerId) {
      throw new Error("Not your turn");
    }

    const nextPlayerId = playerId === "p1" ? "p2" : "p1";
    this.startTurn(nextPlayerId);
  }

  attack(attackerId, defenderId) {
    this.state.stack.push(() => {
      const gameState = this.state;
      const context = this.getContext();

      const attacker = gameState.findEntity(attackerId);
      const target = gameState.findEntity(defenderId);

      const enemyBoard = gameState.players[target.ownerId || target.id].board;

      // Validação final via CombatEngine
      const validation = CombatEngine.validateAttack(
        attacker,
        target,
        enemyBoard,
        gameState,
      );

      if (!validation.valid) throw new Error(validation.reason);

      CombatResolver.resolve(attacker, target, context);

      attacker.hasAttackedThisTurn = true;
    });
  }

  getContext() {
    return {
      visualEvents: this.visualQueue,
      state: this.state,
    };
  }

  drainVisualEvents() {
    const events = this.visualQueue.map((event) => ({
      ...event,
      sequence: ++this.eventSequence,
      gameId: this.id,
    }));
    this.visualQueue = [];
    return events;
  }

  // Envia o estado filtrado para cada jogador (Fog of War)
  getSnapshotFor(playerId) {
    return this.state.serialize(playerId);
  }
}
