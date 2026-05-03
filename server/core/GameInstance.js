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
    this.gameOver = null;
    this.gameOverAnnounced = false;
  }

  assertGameIsActive() {
    if (this.gameOver) {
      throw new Error("Game is already over");
    }
  }

  async flushStack() {
    while (this.state.stack.isProcessing || this.state.stack.queue.length > 0) {
      await new Promise((resolve) => setTimeout(resolve, 0));
    }
  }

  async startMatch() {
    this.state.turnCount = 1;

    this.state.stack.push(() => {
      const context = this.getContext();
      const p1 = this.state.players.p1;
      const p2 = this.state.players.p2;

      for (let i = 0; i < 6; i += 1) {
        p1.drawCard(context);
        p2.drawCard(context);
      }

      p1.refillMana(this.state.turnCount);
      p1.board.forEach((creature) => {
        creature.hasAttackedThisTurn = false;
      });

      p2.board.forEach((creature) => {
        creature.hasAttackedThisTurn = false;
      });

      this.state.activePlayerId = "p1";
    });

    this.getContext().visualEvents.push({
      type: "TURN_STARTED",
      playerId: "p1",
      turnCount: this.state.turnCount,
    });

    await this.flushStack();
  }

  // Ciclo de Turno estilo Hearthstone
  startTurn(playerId, options = {}) {
    this.assertGameIsActive();

    const { advanceTurn = true } = options;
    const player = this.state.players[playerId];
    this.state.activePlayerId = playerId;
    if (advanceTurn) {
      this.state.turnCount += 1;
    }

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
    this.assertGameIsActive();

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
    this.assertGameIsActive();

    if (this.state.activePlayerId !== playerId) {
      throw new Error("Not your turn");
    }

    const nextPlayerId = playerId === "p1" ? "p2" : "p1";
    this.startTurn(nextPlayerId, { advanceTurn: true });
  }

  attack(attackerId, defenderId) {
    this.assertGameIsActive();

    const attackerEntity = this.state.findEntity(attackerId);
    if (!attackerEntity) {
      throw new Error("Attacker not found");
    }
    if (this.state.activePlayerId !== attackerEntity.ownerId) {
      throw new Error("Not your turn");
    }

    this.state.stack.push(() => {
      const gameState = this.state;
      const context = this.getContext();

      const attacker = gameState.findEntity(attackerId);
      const target = gameState.findEntity(defenderId);
      if (!attacker || !target) {
        throw new Error("Invalid attack target");
      }

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

  resolveGameOverByHealth() {
    if (this.gameOver) return this.gameOver;

    const p1 = this.state.players.p1;
    const p2 = this.state.players.p2;

    const p1Dead = p1.hp <= 0;
    const p2Dead = p2.hp <= 0;

    if (!p1Dead && !p2Dead) {
      return null;
    }

    if (p1Dead && p2Dead) {
      this.gameOver = {
        reason: "double_ko",
        winnerId: null,
        loserId: null,
      };
      return this.gameOver;
    }

    this.gameOver = p1Dead
      ? { reason: "hero_defeated", winnerId: "p2", loserId: "p1" }
      : { reason: "hero_defeated", winnerId: "p1", loserId: "p2" };

    return this.gameOver;
  }

  surrender(playerId) {
    this.assertGameIsActive();

    const winnerId = playerId === "p1" ? "p2" : "p1";
    this.gameOver = {
      reason: "surrender",
      winnerId,
      loserId: playerId,
      surrenderedBy: playerId,
    };

    this.getContext().visualEvents.push({
      type: "GAME_OVER",
      reason: "surrender",
      winnerId,
      loserId: playerId,
    });

    return this.gameOver;
  }

  getGameOver() {
    return this.gameOver;
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
