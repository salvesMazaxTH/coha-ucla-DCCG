export const ClientEvents = Object.freeze({
  SUBMIT_DECK: "deck:submit",
  PLAY_CARD: "action:playCard",
  END_TURN: "action:endTurn",
});

export const ServerEvents = Object.freeze({
  DECK_ACCEPTED: "deck:accepted",
  DECK_REJECTED: "deck:rejected",
  MATCH_FOUND: "match:found",
  GAME_STATE: "game:state",
  GAME_EVENTS: "game:events",
  SERVER_ERROR: "server:error",
});

export const ErrorCode = Object.freeze({
  INVALID_PAYLOAD: "INVALID_PAYLOAD",
  INVALID_DECK: "INVALID_DECK",
  INVALID_ACTION: "INVALID_ACTION",
});
