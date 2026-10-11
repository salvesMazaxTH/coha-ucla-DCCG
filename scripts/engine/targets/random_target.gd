class_name RandomTarget
extends TargetSelector
## Random picks with the match RNG: random_enemy (any enemy unit or the enemy Leader), random_enemy_unit, random_enemy_and_adjacent,
## random_ally_unit, random_other_ally_unit. The RNG is only rolled when there is something
## to pick, so replays stay identical.

const NAMES := ["random_enemy", "random_enemy_unit", "random_enemy_and_adjacent", "random_ally_unit", "random_other_ally_unit"]

func resolve(context: EffectContext, _effect: Effect) -> Array:
	var game := context.game
	var enemy_board: Array = game.players[context.opponent()]["board"]
	match name:
		"random_enemy":
			# the enemy Leader is in the pool too, so there is always something to hit
			var pool: Array = [GameState.LEADER_UID[context.opponent()]]
			for unit: Card in enemy_board:
				pool.append(unit.uid)
			return [pool[game.rng.randi_range(0, pool.size() - 1)]]
		"random_enemy_unit":
			if enemy_board.is_empty():
				return []
			return [enemy_board[game.rng.randi_range(0, enemy_board.size() - 1)].uid]
		"random_enemy_and_adjacent":
			if enemy_board.is_empty():
				return []
			var center := game.rng.randi_range(0, enemy_board.size() - 1)
			var uids: Array = []
			for index in range(maxi(center - 1, 0), mini(center + 1, enemy_board.size() - 1) + 1):
				uids.append(enemy_board[index].uid)
			return uids
		"random_ally_unit", "random_other_ally_unit":
			var pool: Array = []
			for unit: Card in game.players[context.controller]["board"]:
				if name == "random_ally_unit" or unit.uid != context.self_uid:
					pool.append(unit.uid)
			if pool.is_empty():
				return []
			return [pool[game.rng.randi_range(0, pool.size() - 1)]]
	return []
