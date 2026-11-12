class_name RandomTarget
extends TargetSelector
## Random picks with the match RNG. Each selector name (the JSON "target") is only a small description in SPECS:
##   side         "enemy" | "ally": whose board is looked at
##   leader       "never" (default) | "always" | "if_asked" (the effect's "include_leader": true) | "if_no_unit" (only when the board is empty)
##   state        "frozen": only units that are already Congeladas
##   skip_source  true: the unit that owns the effect is never picked
##   pick         "one" (default) | "distinct" ("count" different targets) | "adjacent" (a unit and its neighbours)
##                | "strongest" (the "count" highest Ataque, a tie at the cut-off is rolled)
##                | "most_damaged" (the unit that took the most damage, a tie is rolled)
##                | "hits" (one roll per hit, made just before each hit)
##   hits         fixed number of hits for pick "hits"; without it the effect's "hits" / "hits_from" decide
## Filters the effect itself may carry, for any selector:
##   only_tribe ([...] of tribes), unit_filter (a CardFilter, e.g. {"token": true}), min_atk, max_hp_left (current Vida),
##   all_or_nothing (pick "distinct": exactly "count" targets or none), prefer_without_magic_shield.
## A status effect (freeze, exhaust...) never rolls on a unit that already has that status (Effect.is_already_applied_to).
## The RNG is only rolled when there is something to pick, so replays stay identical.

const SPECS := {
	"random_enemy": { "side": "enemy", "leader": "always" },
	"random_enemy_unit": { "side": "enemy" },
	"random_enemy_unit_else_leader": { "side": "enemy", "leader": "if_no_unit" },
	"random_enemy_units": { "side": "enemy", "leader": "if_asked", "pick": "distinct" },
	"random_enemy_unit_twice": { "side": "enemy", "pick": "hits", "hits": 2 },
	"random_enemy_unit_spread": { "side": "enemy", "pick": "hits" },
	"random_enemy_spread": { "side": "enemy", "leader": "always", "pick": "hits" },
	"random_frozen_enemy_unit": { "side": "enemy", "state": "frozen" },
	"most_wounded_enemy_unit": { "side": "enemy", "pick": "most_damaged" },
	"strongest_enemy_units": { "side": "enemy", "pick": "strongest" },
	"random_enemy_and_adjacent": { "side": "enemy", "pick": "adjacent" },
	"random_ally_unit": { "side": "ally" },
	"random_other_ally_unit": { "side": "ally", "skip_source": true },
	"random_other_ally_units": { "side": "ally", "skip_source": true, "pick": "distinct" },
}

static var NAMES: Array = SPECS.keys()

var spec: Dictionary = {}

func _init(target_name: String = "") -> void:
	super(target_name)
	spec = SPECS.get(target_name, {})

func resolve(context: EffectContext, effect: Effect) -> Array:
	match spec.get("pick", "one"):
		"one":
			return _pick_one(context, effect)
		"distinct":
			return _pick_distinct(context, effect)
		"adjacent":
			return _pick_with_neighbours(context, effect)
		"strongest":
			return _pick_strongest(context, effect)
		"most_damaged":
			return _pick_most_damaged(context, effect)
		"hits":
			var picks: Array = []
			for hit in hit_count(context, effect):
				picks.append_array(resolve_hit(context, effect))
			return picks
	return []

# ---------- pools ----------

func _board(context: EffectContext) -> Array:
	return context.game.players[_side_owner(context)]["board"]

func _side_owner(context: EffectContext) -> int:
	return context.opponent() if spec.get("side", "enemy") == "enemy" else context.controller

func _leader_uid(context: EffectContext) -> int:
	return GameState.LEADER_UID[_side_owner(context)]

## The units of the selector's side that can be picked right now (no dice rolled).
func _candidate_units(context: EffectContext, effect: Effect) -> Array:
	var units: Array = []
	var without_magic_shield: Array = []
	for unit: Card in _board(context):
		if _can_pick(context, effect, unit):
			units.append(unit)
			if not unit.magic_shield:
				without_magic_shield.append(unit)
	if bool(effect.raw.get("prefer_without_magic_shield", false)) and not without_magic_shield.is_empty():
		return without_magic_shield
	return units

func _can_pick(context: EffectContext, effect: Effect, unit: Card) -> bool:
	if bool(spec.get("skip_source", false)) and unit.uid == context.self_uid:
		return false
	if effect.is_already_applied_to(unit):
		return false
	if spec.get("state", "") == "frozen" and not context.game.is_frozen(unit):
		return false
	return _passes_effect_filters(context.game, effect, unit)

## The optional filters written in the effect itself (see the header).
func _passes_effect_filters(game: GameState, effect: Effect, unit: Card) -> bool:
	var raw := effect.raw
	if raw.has("min_atk") and game.atk_of(unit) < int(raw["min_atk"]):
		return false
	if raw.has("max_hp_left") and game.hp_left(unit) > int(raw["max_hp_left"]):
		return false
	var unit_filter: Dictionary = raw.get("unit_filter", {})
	if not unit_filter.is_empty() and not CardFilter.matches(unit.card_id, unit_filter):
		return false
	var wanted_tribes: Array = raw.get("only_tribe", [])
	if wanted_tribes.is_empty():
		return true
	for tribe in CardDB.card(unit.card_id).get("tribe", []):
		if wanted_tribes.has(tribe):
			return true
	return false

## The uids a pick may land on: the Leader when the selector allows it (first), then the candidate units.
func _pool(context: EffectContext, effect: Effect) -> Array:
	var pool: Array = []
	var leader_mode: String = spec.get("leader", "never")
	if leader_mode == "always" or (leader_mode == "if_asked" and bool(effect.raw.get("include_leader", false))):
		pool.append(_leader_uid(context))
	for unit: Card in _candidate_units(context, effect):
		pool.append(unit.uid)
	return pool

## True when this selector picks from the controller's own side and has nobody to pick right now. Other
## selectors return false: they are never asked, so a caller only skips what it knows is empty.
func has_no_ally_candidates(context: EffectContext, effect: Effect) -> bool:
	return spec.get("side", "") == "ally" and _pool(context, effect).is_empty()

# ---------- picks ----------

func _roll(context: EffectContext, pool: Array) -> int:
	return pool[context.game.rng.randi_range(0, pool.size() - 1)]

func _pick_one(context: EffectContext, effect: Effect) -> Array:
	var pool := _pool(context, effect)
	if pool.is_empty():
		return [_leader_uid(context)] if spec.get("leader", "never") == "if_no_unit" else []
	return [_roll(context, pool)]

## Up to "count" different targets (never the same twice).
func _pick_distinct(context: EffectContext, effect: Effect) -> Array:
	var pool := _pool(context, effect)
	var wanted_count := maxi(0, int(effect.raw.get("count", 1)))
	if bool(effect.raw.get("all_or_nothing", false)) and pool.size() < wanted_count:
		return []
	var picks: Array = []
	for pick in mini(wanted_count, pool.size()):
		var index := context.game.rng.randi_range(0, pool.size() - 1)
		picks.append(pool[index])
		pool.remove_at(index)
	return picks

## A random unit and the units next to it. The first roll is over the whole board.
func _pick_with_neighbours(context: EffectContext, effect: Effect) -> Array:
	var board := _board(context)
	if board.is_empty():
		return []
	var center := context.game.rng.randi_range(0, board.size() - 1)
	var uids: Array = []
	for index in range(maxi(center - 1, 0), mini(center + 1, board.size() - 1) + 1):
		if not effect.is_already_applied_to(board[index]):
			uids.append(board[index].uid)
	return uids

## The unit that took the most damage; a tie is rolled.
func _pick_most_damaged(context: EffectContext, effect: Effect) -> Array:
	var most_damage := 0
	var tied: Array = []
	for unit: Card in _candidate_units(context, effect):
		if unit.damage <= 0:
			continue
		if unit.damage > most_damage:
			most_damage = unit.damage
			tied = []
		if unit.damage == most_damage:
			tied.append(unit.uid)
	return [] if tied.is_empty() else [_roll(context, tied)]

## The units with the highest Ataque: at most "count". The dice are only rolled when a tie really crosses the
## cut-off (units share the last place that still fits).
func _pick_strongest(context: EffectContext, effect: Effect) -> Array:
	var game := context.game
	var how_many := int(effect.raw.get("count", 1))
	var candidates := _candidate_units(context, effect)
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
		var index := game.rng.randi_range(0, tied.size() - 1)
		picked.append(tied[index])
		tied.remove_at(index)
	return picked

# ---------- one roll per hit ----------

## Multi-hit selectors are rolled again before every hit (see TargetSelector.hits_one_at_a_time).
func hits_one_at_a_time() -> bool:
	return spec.get("pick", "one") == "hits"

## How many hits: a fixed number in the spec, or from the effect ("hits", or "hits_from": "shared_x" | "self_atk" | "momentum"
## read right now, with "hits_from_add" and a floor "hits_from_min").
func hit_count(context: EffectContext, effect: Effect) -> int:
	if spec.has("hits"):
		return int(spec["hits"])
	var game := context.game
	var raw := effect.raw
	var floor_hits := maxi(0, int(raw.get("hits_from_min", 0)))
	var added_hits := int(raw.get("hits_from_add", 0))
	match raw.get("hits_from", ""):
		"shared_x":
			return maxi(0, game.shared_x_of(context.controller, context.source_id()) + added_hits)
		"self_atk":
			var source := game.find_unit(context.self_uid)
			return maxi(floor_hits, (game.atk_of(source) if source != null else 0) + added_hits)
		"momentum":
			return maxi(floor_hits, int(game.players[context.controller]["momentum"]) + added_hits)
	return maxi(0, int(raw.get("hits", 1)))

## One roll over the targets that can still take a hit: a unit whose Vida is already used up stays on the board
## until the whole effect has resolved (its Ao Morrer waits for that), but it is no longer a candidate, so no hit is
## wasted on it. A Leader the selector allows is always a candidate.
func resolve_hit(context: EffectContext, effect: Effect) -> Array:
	var pool: Array = []
	if spec.get("leader", "never") == "always":
		pool.append(_leader_uid(context))
	for unit: Card in _candidate_units(context, effect):
		if context.game.hp_left(unit) > 0:
			pool.append(unit.uid)
	return [] if pool.is_empty() else [_roll(context, pool)]
