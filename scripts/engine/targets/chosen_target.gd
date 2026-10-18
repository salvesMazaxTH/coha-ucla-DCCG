class_name ChosenTarget
extends TargetSelector
## Targets the player picks: enemy_unit, weak_enemy_unit (an enemy unit with Vida atual <= GameState.WEAK_UNIT_MAX_HP), ally_unit, other_ally_unit, ally_or_own_leader (an ally unit
## or your own Leader), any_unit, any, enemy_stack, enemy_artifact.
## The pick is checked again on resolution (it may have died or left meanwhile).

const NAMES := ["enemy_unit", "weak_enemy_unit", "ally_unit", "other_ally_unit", "ally_or_own_leader", "any_unit", "any", "enemy_stack", "enemy_artifact"]

func needs_choice() -> bool:
	return true

func resolve(context: EffectContext, effect: Effect) -> Array:
	var pick := context.second_target if effect.uses_second_pick else context.chosen_target
	# a forced target (Bola de Neve of a unit) may be a Leader or an exhausted unit that "enemy_unit" would refuse
	if context.forced_target and pick != 0 and (pick < 0 or context.game.find_unit(pick) != null):
		return [pick]
	if context.game.valid_targets(context.controller, name, context.self_uid).has(pick):
		return [pick]
	return []
