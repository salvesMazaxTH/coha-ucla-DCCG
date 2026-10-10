class_name SourceTarget
extends TargetSelector
## Targets taken from the trigger itself: self (the unit whose effect it is, on the board), self_card
## (the same card wherever it is), opposed_unit
## (the other unit in a combat trigger) and none (the effect runs once with target 0).

const NAMES := ["self", "self_card", "opposed_unit", "none"]

func resolve(context: EffectContext, _effect: Effect) -> Array:
	match name:
		"self":
			if context.game.find_unit(context.self_uid) != null:
				return [context.self_uid]
		"self_card": # the card itself in any zone (deck, hand, graveyard...), for listeners that work off the board
			if context.game.find_card(context.self_uid) != null:
				return [context.self_uid]
		"opposed_unit":
			if context.game.find_unit(context.other_uid) != null:
				return [context.other_uid]
		"none":
			return [0]
	return []
