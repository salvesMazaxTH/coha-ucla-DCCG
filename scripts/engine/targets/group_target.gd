class_name GroupTarget
extends TargetSelector
## Every unit of a group: all_enemy_units, all_units (own side first), all_ally_units, other_ally_units.

const NAMES := ["all_enemy_units", "all_units", "all_ally_units", "other_ally_units"]

func resolve(context: EffectContext, _effect: Effect) -> Array:
	var players: Array = context.game.players
	var own_board: Array = players[context.controller]["board"]
	var enemy_board: Array = players[context.opponent()]["board"]
	var uids: Array = []
	match name:
		"all_enemy_units":
			for unit: Card in enemy_board: uids.append(unit.uid)
		"all_units":
			for unit: Card in own_board + enemy_board: uids.append(unit.uid)
		"all_ally_units":
			for unit: Card in own_board: uids.append(unit.uid)
		"other_ally_units":
			for unit: Card in own_board:
				if unit.uid != context.self_uid: uids.append(unit.uid)
	return uids
