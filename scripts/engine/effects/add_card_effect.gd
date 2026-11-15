class_name AddCardEffect
extends Effect
## "add_card": creates a brand new copy of card `card` for the controller (use it with target "none").
##   "card": the card id (e.g. "bola_de_neve").
##   "to": "deck_top" (default, the next draw) or "hand".
##   "depth": only for "deck_top", the card lands at a random place among the top `depth` cards (default 1 = the very top).
## A Bola de Neve created while its owner is at Grande level is born Grande (GameState._move does it).

var card_id := ""
var destination := "deck_top"
var depth := 1

func _read_parameters(data: Dictionary) -> void:
	card_id = String(data.get("card", ""))
	destination = String(data.get("to", "deck_top"))
	depth = maxi(1, int(data.get("depth", 1)))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var player: Dictionary = game.players[context.controller]
	var created := Card.new(game._uid(), card_id, context.controller)
	if destination == "hand":
		player["hand"].append(created)
		game._move(created, "hand")
	else:
		# draws pop the back, so the back is the top; a card put k places down sits k before the end
		var places_down := 0
		if depth > 1:
			places_down = game.rng.randi_range(0, mini(depth, player["deck"].size() + 1) - 1)
		player["deck"].insert(player["deck"].size() - places_down, created)
		game._move(created, "deck")
	game.emit_event({"type": "card_created", "player": context.controller, "uid": created.uid, "card_id": created.card_id, "to": destination})
