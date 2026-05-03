import { ActionStack } from "./ActionStack.js";

export class GameState {
  constructor(player1, player2) {
    this.players = {
      p1: player1,
      p2: player2,
    };

    this.entities = new Map(); // Mapa de todas as entidades (Heroes, Creatures, etc.) por ID

    this.activePlayerId = "p1";
    this.turnCount = 1;

    this.stack = new ActionStack();

    // registrar jogadores como entidades
    this.registerEntity(player1);
    this.registerEntity(player2);
  }

  // Retorna o estado serializado para enviar via Socket
  serialize(viewerId) {
    return {
      players: {
        p1: this.players.p1.serialize(viewerId),
        p2: this.players.p2.serialize(viewerId),
      },
      activePlayerId: this.activePlayerId,
      turnCount: this.turnCount,
    };
  }

  registerEntity(entity) {
    if (!entity || !entity.id) {
      throw new Error("Entity must have an id");
    }

    this.entities.set(entity.id, entity);
  }

  removeEntity(entityOrId) {
    const id = typeof entityOrId === "string" ? entityOrId : entityOrId.id;

    this.entities.delete(id);
  }

  hasEntity(id) {
    return this.entities.has(id);
  }

  // Helper para buscar qualquer entidade (Hero ou Creature) por ID
  findEntity(id) {
    return this.entities.get(id) || null;
  }

  getPlayer(playerId) {
    return this.players[playerId];
  }

  getOpponent(playerId) {
    return playerId === "p1" ? this.players.p2 : this.players.p1;
  }
}
