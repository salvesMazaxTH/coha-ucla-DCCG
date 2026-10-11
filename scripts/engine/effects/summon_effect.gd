class_name SummonEffect
extends Effect
## "summon": {"card": <id|"self">, "overrides": {atk, hp, keywords, effects, text...}}.
## "self" is the unit whose Ao Morrer is resolving. Overrides stick to the new instance.

var card_id := "self"
var overrides: Dictionary = {}

func _read_parameters(data: Dictionary) -> void:
	card_id = String(data.get("card", "self"))
	overrides = data.get("overrides", {})

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var summoned_id := card_id
	if summoned_id == "self":
		if context.dying_card == null:
			return
		summoned_id = context.dying_card.card_id
	if not game.has_free_slot(context.controller):
		return
	game._summon(context.controller, Card.new(game._uid(), summoned_id, context.controller), false, 0, overrides)
