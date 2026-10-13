class_name GroupTarget
extends TargetSelector
## Every unit of a group: all_enemy_units, all_units (own side first), all_ally_units, other_ally_units,
## center_enemy_units (the middle of the enemy board as it stands: 1 unit if the count is odd, the 2 middle ones if even).

const NAMES := ["all_enemy_units", "all_units", "all_ally_units", "other_ally_units", "center_enemy_units"]

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
		"center_enemy_units":
			var count := enemy_board.size()
			if count % 2 == 1:
				uids.append(enemy_board[count / 2].uid)
			elif count > 0:
				uids.append(enemy_board[count / 2 - 1].uid)
				uids.append(enemy_board[count / 2].uid)
	return uids
