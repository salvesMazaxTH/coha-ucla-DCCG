class_name ChosenTarget
extends TargetSelector
## Targets the player picks: enemy_unit, ally_unit, other_ally_unit, any_unit, any, enemy_stack, enemy_artifact.
## The pick is checked again on resolution (it may have died or left meanwhile).

const NAMES := ["enemy_unit", "ally_unit", "other_ally_unit", "any_unit", "any", "enemy_stack", "enemy_artifact"]

func needs_choice() -> bool:
	return true

func resolve(context: EffectContext, effect: Effect) -> Array:
	var pick := context.second_target if effect.uses_second_pick else context.chosen_target
	if context.game.valid_targets(context.controller, name, context.self_uid).has(pick):
		return [pick]
	return []
