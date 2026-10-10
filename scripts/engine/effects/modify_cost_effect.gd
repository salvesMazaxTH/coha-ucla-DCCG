class_name ModifyCostEffect
extends Effect
## "modify_cost": changes the cost of the target card by `amount` (negative = cheaper) for the rest
## of the match, in whatever zone it is. Use target "self_card" so a card can cheapen itself.

var amount := 0

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	var card := context.game.find_card(target_uid)
	if card != null:
		card.cost_mod += amount
