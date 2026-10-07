class_name StateView
extends RefCounted
## What a given seat is allowed to know about a GameState: the opponent's hand and
## both decks are reduced to uid-only placeholders (card_id ""), everything else is public.

const HIDDEN := ""

static func _mask(cards: Array) -> Array:
	var out: Array = []
	for c in cards:
		out.append({"uid": c["uid"], "card_id": HIDDEN})
	return out

## JSON-safe snapshot for `seat`.
static func snapshot(g: GameState, seat: int) -> Dictionary:
	var players: Array = []
	for i in 2:
		var pl: Dictionary = g.players[i].duplicate(true)
		pl["deck"] = _mask(pl["deck"])
		if i != seat:
			pl["hand"] = _mask(pl["hand"])
		players.append(pl)
	return {
		"players": players,
		"active": g.active,
		"turn": g.turn,
		"phase": g.phase,
		"winner": g.winner,
		"decider": g.decider(),
		"attackers": g.attackers.duplicate(true),
		"pending_search": g.pending_search.duplicate(true),
	}

## Events are already public information (a draw carries only a uid, plays show the card
## being played, searches are revealed); kept as a hook so leaks can be closed in one place.
static func filter_events(events: Array, _seat: int) -> Array:
	return events
