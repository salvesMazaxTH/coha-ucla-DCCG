class_name MillEffect
extends Effect
## "mill": the top `amount` cards of a deck go to its owner's graveyard. Milling your OWN deck never
## causes fatigue (the next draw from the empty deck is what hurts). "who": "enemy" mills the
## opponent's deck instead of the controller's (Metálica); if it has fewer cards than `amount`
## (or none), the missing cards turn into ONE Fadiga for them, so mill keeps working after the deck runs out.
## "mill_pick" does the same on the own deck, then offers one of those cards to the hand.

var amount := 1
var mills_enemy := false

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))
	mills_enemy = String(data.get("who", "self")) == "enemy"

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var deck_owner: int = game.opponent(context.controller) if mills_enemy else context.controller
	var player: Dictionary = game.players[deck_owner]
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
		game._emit({"type": "mill", "player": deck_owner, "cards": milled_ids})
	if mills_enemy and milled_ids.size() < amount:
		game.suffer_fatigue(deck_owner)

func opens_choice() -> bool:
	return action == "mill_pick"

func open_choice(context: EffectContext) -> void:
	context.game._begin_grave_pick(context.controller, context.milled_cards, context.self_uid)
