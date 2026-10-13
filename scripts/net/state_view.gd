class_name StateView
extends RefCounted
## What a given seat is allowed to know about a GameState: the opponent's hand and
## both decks and the opponent's banished cards are reduced to uid-only placeholders (card_id ""), everything else is public.

const HIDDEN := ""

const CARD_ZONES := ["deck", "hand", "board", "relics", "graveyard", "banished"]

## Hides which cards these are: keeps only the uid. Accepts Card objects or card dicts.
static func _mask(cards: Array) -> Array:
	var out: Array = []
	for card in cards:
		var card_uid: int = card.uid if card is Card else card["uid"]
		out.append({"uid": card_uid, "card_id": HIDDEN})
	return out

## Turns a zone's Card objects into the plain dicts sent over the network.
static func _zone_to_dicts(cards: Array) -> Array:
	var out: Array = []
	for card: Card in cards:
		out.append(card.to_dict())
	return out

## JSON-safe snapshot for `seat`.
static func snapshot(g: GameState, seat: int) -> Dictionary:
	var players: Array = []
	for i in 2:
		var source: Dictionary = g.players[i]
		# copy everything except the card zones (Card objects can't be deep-copied into JSON)
		var player: Dictionary = {}
		for key in source:
			if key not in CARD_ZONES:
				player[key] = source[key].duplicate(true) if source[key] is Dictionary or source[key] is Array else source[key]
		for zone in CARD_ZONES:
			player[zone] = _zone_to_dicts(source[zone])
		player["deck"] = _mask(player["deck"])
		if i != seat:
			player["banished"] = _mask(player["banished"]) # cards banished from the hand stay private
			player["hand"] = _mask(player["hand"])
		players.append(player)
	var search: Dictionary = g.pending_search.duplicate(true)
	if (search.get("look", false) or search.get("discard_hand", false)) and int(search["player"]) != seat:
		search["cards"] = _mask(search["cards"]) # a look at the deck top, or a pick from a hand, is private
	return {
		"players": players,
		"active": g.active,
		"turn": g.turn,
		"first": g.first,
		"phase": g.phase,
		"winner": g.winner,
		"decider": g.decider(),
		"pending_search": search,
		"pending_enter": g.pending_enter.duplicate(true),
		"pending_tap": g.pending_tap.duplicate(),
		"stack": g.stack.duplicate(true),
		"priority": g.priority,
		"window": g.window,
		"summon_window": g.summon_window,
		"stack_passed": g.stack_passed,
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
