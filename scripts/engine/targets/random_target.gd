class_name RandomTarget
extends TargetSelector
## Random picks with the match RNG: random_enemy (any enemy unit or the enemy Leader), random_enemy_unit, random_enemy_units (up to "count" different enemy units), random_enemy_unit_twice (two independent picks, the same unit can be picked twice: 2 damage handed out one by one), random_enemy_unit_spread (the effect's "hits" independent picks over units), random_enemy_spread (the same, including the Leader), random_frozen_enemy_unit
## (only enemy units that are already Congeladas), most_wounded_enemy_unit (the enemy unit that took the most damage and still has Vida 3 or less, an execution; a tie is rolled; Isarelis), strongest_enemy_units (the "count" enemy units with the highest Ataque, only those with Ataque "min_atk" or more; a tie at the cut-off is rolled; David), random_enemy_and_adjacent, random_ally_unit, random_other_ally_unit (both accept the effect's "only_species": the pool only holds allies of those species). The RNG is only rolled when there is something
## to pick, so replays stay identical.
## A status effect (freeze, exhaust...) never rolls on a unit that already has that status: the pool only holds
## units that can still receive it (Effect.is_already_applied_to), and an empty pool means no target.

const NAMES := ["random_enemy", "random_enemy_unit", "random_enemy_units", "random_enemy_unit_twice", "random_enemy_unit_spread", "random_enemy_spread", "random_frozen_enemy_unit", "most_wounded_enemy_unit", "strongest_enemy_units", "random_enemy_and_adjacent", "random_ally_unit", "random_other_ally_unit"]

const WOUNDED_TARGET_MAX_HP := 3 ## "most_wounded_enemy_unit" only picks units with this much current Vida or less

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
		"random_enemy_units":
			var distinct_pool: Array = []
			for unit: Card in enemy_board:
				if not effect.is_already_applied_to(unit):
					distinct_pool.append(unit.uid)
			var distinct_picks: Array = []
			var pick_count := mini(maxi(0, int(effect.raw.get("count", 1))), distinct_pool.size())
			for pick in pick_count:
				var index := game.rng.randi_range(0, distinct_pool.size() - 1)
				distinct_picks.append(distinct_pool[index])
				distinct_pool.remove_at(index)
			return distinct_picks
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
			var hits := int(effect.raw.get("hits", 1))
			if effect.raw.get("hits_from", "") == "self_atk":
				var source := game.find_unit(context.self_uid)
				hits = maxi(0, (game.atk_of(source) if source != null else 0) + int(effect.raw.get("hits_from_add", 0)))
			for hit in maxi(0, hits):
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
		"most_wounded_enemy_unit":
			# only wounded units with Vida atual <= WOUNDED_TARGET_MAX_HP; among them the one with the most damage taken
			var most_damage := 0
			var wounded_pool: Array = []
			for unit: Card in enemy_board:
				if unit.damage <= 0 or game.hp_left(unit) > WOUNDED_TARGET_MAX_HP:
					continue
				if unit.damage > most_damage:
					most_damage = unit.damage
					wounded_pool = []
				if unit.damage == most_damage:
					wounded_pool.append(unit.uid)
			if wounded_pool.is_empty():
				return []
			return [wounded_pool[game.rng.randi_range(0, wounded_pool.size() - 1)]]
		"strongest_enemy_units":
			return _strongest_enemy_units(context, effect)
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
			var pool: Array = _ally_pool(context, effect)
			if pool.is_empty():
				return []
			return [pool[game.rng.randi_range(0, pool.size() - 1)]]
	return []

## The three multi-hit selectors are rolled again before every hit (see TargetSelector.hits_one_at_a_time).
func hits_one_at_a_time() -> bool:
	return name in ["random_enemy_unit_twice", "random_enemy_unit_spread", "random_enemy_spread"]

func hit_count(context: EffectContext, effect: Effect) -> int:
	match name:
		"random_enemy_unit_twice":
			return 2
		"random_enemy_unit_spread":
			return maxi(0, int(effect.raw.get("hits", 1)))
		"random_enemy_spread":
			if effect.raw.get("hits_from", "") == "self_atk":
				var source := context.game.find_unit(context.self_uid)
				return maxi(0, (context.game.atk_of(source) if source != null else 0) + int(effect.raw.get("hits_from_add", 0)))
			return maxi(0, int(effect.raw.get("hits", 1)))
	return 0

## One roll over the enemies that can still take a hit: a unit whose Vida is already used up stays on the board
## until the whole effect has resolved (its Ao Morrer waits for that), but it is no longer a candidate, so no hit is
## wasted on it. The Leader is always a candidate for "random_enemy_spread".
func resolve_hit(context: EffectContext, effect: Effect) -> Array:
	var game := context.game
	var pool: Array = []
	if name == "random_enemy_spread":
		pool.append(GameState.LEADER_UID[context.opponent()])
	for unit: Card in game.players[context.opponent()]["board"]:
		if game.hp_left(unit) > 0 and not effect.is_already_applied_to(unit):
			pool.append(unit.uid)
	if pool.is_empty():
		return []
	return [pool[game.rng.randi_range(0, pool.size() - 1)]]

## The enemy units with the highest Ataque: at most the effect's "count", and only units with at least "min_atk".
## The dice are only rolled when a tie really crosses the cut-off (units share the last place that still fits).
func _strongest_enemy_units(context: EffectContext, effect: Effect) -> Array:
	var game := context.game
	var how_many := int(effect.raw.get("count", 1))
	var minimum_attack := int(effect.raw.get("min_atk", 0))
	var candidates: Array = []
	for unit: Card in game.players[context.opponent()]["board"]:
		if game.atk_of(unit) >= minimum_attack:
			candidates.append(unit)
	if candidates.size() <= how_many:
		return candidates.map(func(unit: Card) -> int: return unit.uid)
	candidates.sort_custom(func(first: Card, second: Card) -> bool: return game.atk_of(first) > game.atk_of(second))
	# everyone stronger than the last place is in for sure; the units tied with the last place compete for the rest
	var cut_off_attack: int = game.atk_of(candidates[how_many - 1])
	var picked: Array = []
	var tied: Array = []
	for unit: Card in candidates:
		if game.atk_of(unit) > cut_off_attack:
			picked.append(unit.uid)
		elif game.atk_of(unit) == cut_off_attack:
			tied.append(unit.uid)
	var places_left := how_many - picked.size()
	if tied.size() <= places_left:
		picked.append_array(tied)
		return picked
	for place in places_left:
		var roll := game.rng.randi_range(0, tied.size() - 1)
		picked.append(tied[roll])
		tied.remove_at(roll)
	return picked

## The allies this selector may pick from (no dice rolled, so it is safe to ask "is there anyone?" first).
func _ally_pool(context: EffectContext, effect: Effect) -> Array:
	var pool: Array = []
	for unit: Card in context.game.players[context.controller]["board"]:
		if (name == "random_ally_unit" or unit.uid != context.self_uid) and not effect.is_already_applied_to(unit) and _has_wanted_species(unit, effect):
			pool.append(unit.uid)
	return pool

## True when this selector is a random ally pick that has nobody to pick right now. Other selectors
## return false: they are never asked, so a caller only skips what it knows is empty.
func has_no_ally_candidates(context: EffectContext, effect: Effect) -> bool:
	return name in ["random_ally_unit", "random_other_ally_unit"] and _ally_pool(context, effect).is_empty()

## True when the effect asks for no species ("only_species" missing) or the unit's card has one of them.
func _has_wanted_species(unit: Card, effect: Effect) -> bool:
	var wanted_species: Array = effect.raw.get("only_species", [])
	if wanted_species.is_empty():
		return true
	for species in CardDB.card(unit.card_id).get("species", []):
		if wanted_species.has(species):
			return true
	return false
