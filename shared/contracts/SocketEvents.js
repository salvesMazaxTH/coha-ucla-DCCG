export const ClientEvents = Object.freeze({
  SUBMIT_DECK: "deck:submit",
  PLAY_CARD: "action:playCard",
  ATTACK: "action:attack",
  END_TURN: "action:endTurn",
  SURRENDER: "action:surrender",
});

export const ServerEvents = Object.freeze({
  DECK_ACCEPTED: "deck:accepted",
  DECK_REJECTED: "deck:rejected",
  MATCH_FOUND: "match:found",
  GAME_STATE: "game:state",
  GAME_EVENTS: "game:events",
  GAME_OVER: "game:over",
  SERVER_ERROR: "server:error",
});

export const ErrorCode = Object.freeze({
  INVALID_PAYLOAD: "INVALID_PAYLOAD",
  INVALID_DECK: "INVALID_DECK",
  INVALID_ACTION: "INVALID_ACTION",
});
