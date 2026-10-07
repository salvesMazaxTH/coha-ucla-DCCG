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
	var search: Dictionary = g.pending_search.duplicate(true)
	if search.get("look", false) and int(search["player"]) != seat:
		search["cards"] = _mask(search["cards"]) # a look at the deck top is private
	return {
		"players": players,
		"active": g.active,
		"turn": g.turn,
		"phase": g.phase,
		"winner": g.winner,
		"decider": g.decider(),
		"attackers": g.attackers.duplicate(true),
		"blocks": g.blocks.duplicate(true),
		"pending_search": search,
		"stack": g.stack.duplicate(true),
		"priority": g.priority,
		"window": g.window,
	}

## Events are public information (a draw carries only a uid, plays show the card being
## played, searches are revealed) except a private look at the deck top, masked for the
## other seat; only the card taken from it is shown (search_take).
static func filter_events(events: Array, seat: int) -> Array:
	var out: Array = []
	for e in events:
		if e.get("type", "") == "look_top" and int(e["player"]) != seat:
			var m: Dictionary = e.duplicate(true)
			m["cards"] = _mask(m["cards"])
			out.append(m)
		else:
			out.append(e)
	return out
