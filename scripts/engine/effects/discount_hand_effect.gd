class_name DiscountHandEffect
extends Effect
## "discount_hand": every card in the controller's hand whose type is in "card_types" costs `amount` less
## while it stays in that hand (the same per-copy discount the Tecnomante gives). Repeating it stacks, so a
## card kept in hand for several turns keeps getting cheaper; leaving the hand clears it. Never below (0).
## Empty "card_types" = every card. Example: {"action": "discount_hand", "card_types": ["unit", "artifact"], "amount": 1}.

var amount := 1
var card_types: Array = []

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))
	card_types = data.get("card_types", [])

func apply(context: EffectContext, _target_uid: int) -> void:
	for card: Card in context.game.players[context.controller]["hand"]:
		var card_type := String(CardDB.card(card.card_id).get("type", ""))
		if card_types.is_empty() or card_types.has(card_type):
			card.discount += amount
