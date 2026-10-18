class_name RandomTarget
extends TargetSelector
## Random picks with the match RNG: random_enemy (any enemy unit or the enemy Leader), random_enemy_unit, random_enemy_unit_twice (two independent picks, the same unit can be picked twice: 2 damage handed out one by one), random_enemy_unit_spread (the effect's "hits" independent picks over units), random_enemy_spread (the same, including the Leader), random_frozen_enemy_unit
## (only enemy units that are already Congeladas), random_enemy_and_adjacent, random_ally_unit, random_other_ally_unit (both accept the effect's "only_species": the pool only holds allies of those species). The RNG is only rolled when there is something
## to pick, so replays stay identical.
## A status effect (freeze, exhaust...) never rolls on a unit that already has that status: the pool only holds
## units that can still receive it (Effect.is_already_applied_to), and an empty pool means no target.

const NAMES := ["random_enemy", "random_enemy_unit", "random_enemy_unit_twice", "random_enemy_unit_spread", "random_enemy_spread", "random_frozen_enemy_unit", "random_enemy_and_adjacent", "random_ally_unit", "random_other_ally_unit"]

func resolve(context: EffectContext, effect: Effect) -> Array:
	var game := context.game
	var enemy_board: Array = game.players[context.opponent()]["board"]
	match name:
		"random_enemy":
			# the enemy Leader is in the pool too, so there is always something to hit
			var pool: Array = [GameState.LEADER_UID[context.opponent()]]
			for unit: Card in enemy_board:
				if not effect.is_already_applied_to(unit):
					pool.append(unit.uid)
			return [pool[game.rng.randi_range(0, pool.size() - 1)]]
		"random_enemy_unit":
			var enemy_pool: Array = []
			for unit: Card in enemy_board:
				if not effect.is_already_applied_to(unit):
					enemy_pool.append(unit.uid)
			if enemy_pool.is_empty():
				return []
			return [enemy_pool[game.rng.randi_range(0, enemy_pool.size() - 1)]]
		"random_enemy_unit_twice":
			var twice_pool: Array = []
			for unit: Card in enemy_board:
				if not effect.is_already_applied_to(unit):
					twice_pool.append(unit.uid)
			if twice_pool.is_empty():
				return []
			return [twice_pool[game.rng.randi_range(0, twice_pool.size() - 1)], twice_pool[game.rng.randi_range(0, twice_pool.size() - 1)]]
		"random_enemy_unit_spread":
			var spread_pool: Array = []
			for unit: Card in enemy_board:
				spread_pool.append(unit.uid)
			if spread_pool.is_empty():
				return []
			var spread_picks: Array = []
			for hit in int(effect.raw.get("hits", 1)):
				spread_picks.append(spread_pool[game.rng.randi_range(0, spread_pool.size() - 1)])
			return spread_picks
		"random_enemy_spread":
			# Unlike the unit-only Repique selector, every hit may also land on the enemy Leader.
			var all_enemy_pool: Array = [GameState.LEADER_UID[context.opponent()]]
			for unit: Card in enemy_board:
				all_enemy_pool.append(unit.uid)
			var all_enemy_picks: Array = []
			for hit in int(effect.raw.get("hits", 1)):
				all_enemy_picks.append(all_enemy_pool[game.rng.randi_range(0, all_enemy_pool.size() - 1)])
			return all_enemy_picks
		"random_frozen_enemy_unit":
			var frozen_pool: Array = []
			for unit: Card in enemy_board:
				if game.is_frozen(unit):
					frozen_pool.append(unit.uid)
			if frozen_pool.is_empty():
				return []
			return [frozen_pool[game.rng.randi_range(0, frozen_pool.size() - 1)]]
		"random_enemy_and_adjacent":
			if enemy_board.is_empty():
				return []
			var center := game.rng.randi_range(0, enemy_board.size() - 1)
			var uids: Array = []
			for index in range(maxi(center - 1, 0), mini(center + 1, enemy_board.size() - 1) + 1):
				if not effect.is_already_applied_to(enemy_board[index]):
					uids.append(enemy_board[index].uid)
			return uids
		"random_ally_unit", "random_other_ally_unit":
			var pool: Array = []
			for unit: Card in game.players[context.controller]["board"]:
				if (name == "random_ally_unit" or unit.uid != context.self_uid) and not effect.is_already_applied_to(unit) and _has_wanted_species(unit, effect):
					pool.append(unit.uid)
			if pool.is_empty():
				return []
			return [pool[game.rng.randi_range(0, pool.size() - 1)]]
	return []

## True when the effect asks for no species ("only_species" missing) or the unit's card has one of them.
func _has_wanted_species(unit: Card, effect: Effect) -> bool:
	var wanted_species: Array = effect.raw.get("only_species", [])
	if wanted_species.is_empty():
		return true
	for species in CardDB.card(unit.card_id).get("species", []):
		if wanted_species.has(species):
			return true
	return false
