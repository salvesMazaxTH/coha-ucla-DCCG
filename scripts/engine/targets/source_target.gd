class_name SourceTarget
extends TargetSelector
## Targets taken from the trigger itself: self (the unit whose effect it is), opposed_unit
## (the other unit in a combat trigger) and none (the effect runs once with target 0).

const NAMES := ["self", "opposed_unit", "none"]

func resolve(context: EffectContext, _effect: Effect) -> Array:
	match name:
		"self":
			if context.game.find_unit(context.self_uid) != null:
				return [context.self_uid]
		"opposed_unit":
			if context.game.find_unit(context.other_uid) != null:
				return [context.other_uid]
		"none":
			return [0]
	return []
