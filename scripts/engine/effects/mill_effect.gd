class_name MillEffect
extends Effect
## "mill": the top `amount` cards of the controller's deck go to the graveyard (no fatigue
## when the deck runs out). "mill_pick" does the same, then offers one of those cards to the hand.

var amount := 1

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var player: Dictionary = game.players[context.controller]
	var milled_ids: Array = []
	context.milled_cards = []
	for i in amount:
		if player["deck"].is_empty():
			break
		var card: Card = player["deck"].pop_back()
		player["graveyard"].append(card)
		game._move(card, "graveyard")
		context.milled_cards.append(card)
		milled_ids.append(card.card_id)
	if not milled_ids.is_empty():
		game._emit({"type": "mill", "player": context.controller, "cards": milled_ids})

func opens_choice() -> bool:
	return action == "mill_pick"

func open_choice(context: EffectContext) -> void:
	context.game._begin_grave_pick(context.controller, context.milled_cards, context.self_uid)
