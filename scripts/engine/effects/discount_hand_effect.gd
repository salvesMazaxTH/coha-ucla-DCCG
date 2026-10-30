class_name DiscountHandEffect
extends Effect
## "discount_hand": every card in the controller's hand whose type is in "card_types" costs `amount` less
## while it stays in that hand (the same per-copy discount the Tecnomante gives). Repeating it stacks, so a
## card kept in hand for several turns keeps getting cheaper; leaving the hand clears it. Never below (0).
## Empty "card_types" = every card. Example: {"action": "discount_hand", "card_types": ["unit", "artifact"], "amount": 1}.
## "card_filter" (optional) narrows it further with any CardFilter key, e.g. {"species": "elefante"}
## (Matriarca Pisa-Mansinho: only the Elefantes in hand get cheaper).

var amount := 1
var card_types: Array = []
var card_filter: Dictionary = {}

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))
	card_types = data.get("card_types", [])
	card_filter = data.get("card_filter", {})

func apply(context: EffectContext, _target_uid: int) -> void:
	for card: Card in context.game.players[context.controller]["hand"]:
		var card_data := CardDB.card(card.card_id)
		var type_matches := card_types.is_empty()
		for wanted_type in card_types:
			type_matches = type_matches or CardDB.has_type(card_data, String(wanted_type))
		var filter_matches := card_filter.is_empty() or CardFilter.matches(card.card_id, card_filter)
		if type_matches and filter_matches:
			card.discount += amount
