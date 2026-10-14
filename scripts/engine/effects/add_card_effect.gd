class_name AddCardEffect
extends Effect
## "add_card": creates a brand new copy of card `card` for the controller (use it with target "none").
##   "card": the card id (e.g. "bola_de_neve").
##   "to": "deck_top" (default, the next draw) or "hand".
## A Bola de Neve created while its owner is at Grande level is born Grande (GameState._move does it).

var card_id := ""
var destination := "deck_top"

func _read_parameters(data: Dictionary) -> void:
	card_id = String(data.get("card", ""))
	destination = String(data.get("to", "deck_top"))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var player: Dictionary = game.players[context.controller]
	var created := Card.new(game._uid(), card_id, context.controller)
	if destination == "hand":
		player["hand"].append(created)
		game._move(created, "hand")
	else:
		player["deck"].append(created) # draws pop the back, so the back is the top
		game._move(created, "deck")
	game._emit({"type": "card_created", "player": context.controller, "uid": created.uid, "card_id": created.card_id, "to": destination})
