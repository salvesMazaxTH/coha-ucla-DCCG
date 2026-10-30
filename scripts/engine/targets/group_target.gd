class_name GroupTarget
extends TargetSelector
## Every unit of a group: all_enemy_units, all_units (own side first), other_units (all_units without the unit that
## runs the effect), all_ally_units, other_ally_units, all_enemy_tokens (only the enemy fichas), center_enemy_units
## (the middle of the enemy board as it stands: 1 unit if the count is odd, the 2 middle ones if even).
## Any group can be narrowed by a "unit_filter" in the effect's JSON: a CardFilter dictionary checked against each
## unit's printed card, e.g. {"max_cost": 4} keeps only the units that cost 4 or less (Kazeminus).
## "unit_state": "frozen" keeps only the units that are Congeladas right now (Jovahr); checked live, when the effect runs.
## "unit_state_any": a list of states (see unit_has_state); a unit stays if it matches at least one (Fulgurvoltz).

const NAMES := ["all_enemy_units", "all_units", "other_units", "all_ally_units", "other_ally_units", "center_enemy_units", "all_enemy_tokens"]

func resolve(context: EffectContext, effect: Effect) -> Array:
	var players: Array = context.game.players
	var own_board: Array = players[context.controller]["board"]
	var enemy_board: Array = players[context.opponent()]["board"]
	var uids: Array = []
	match name:
		"all_enemy_units":
			for unit: Card in enemy_board: uids.append(unit.uid)
		"all_units":
			for unit: Card in own_board + enemy_board: uids.append(unit.uid)
		"other_units":
			for unit: Card in own_board + enemy_board:
				if unit.uid != context.self_uid: uids.append(unit.uid)
		"all_ally_units":
			for unit: Card in own_board: uids.append(unit.uid)
		"other_ally_units":
			for unit: Card in own_board:
				if unit.uid != context.self_uid: uids.append(unit.uid)
		"all_enemy_tokens":
			for unit: Card in enemy_board:
				if unit.data().get("token", false): uids.append(unit.uid)
		"center_enemy_units":
			var count := enemy_board.size()
			if count % 2 == 1:
				uids.append(enemy_board[count / 2].uid)
			elif count > 0:
				uids.append(enemy_board[count / 2 - 1].uid)
				uids.append(enemy_board[count / 2].uid)
	var unit_filter: Dictionary = effect.raw.get("unit_filter", {})
	if not unit_filter.is_empty():
		uids = uids.filter(func(uid: int) -> bool: return CardFilter.matches(context.game.find_unit(uid).card_id, unit_filter))
	var required_state: String = effect.raw.get("unit_state", "")
	if required_state != "":
		uids = uids.filter(func(uid: int) -> bool: return unit_has_state(context.game, context.game.find_unit(uid), required_state, context.self_uid))
	var any_of_states: Array = effect.raw.get("unit_state_any", [])
	if not any_of_states.is_empty():
		uids = uids.filter(func(uid: int) -> bool:
			var unit := context.game.find_unit(uid)
			return any_of_states.any(func(state: String) -> bool: return unit_has_state(context.game, unit, state, context.self_uid)))
	return uids

## One live state a unit can be checked for: "frozen", "exhausted", or "weaker_than_source" (its Ataque + Vida
## is lower than the Ataque + Vida of the unit that runs the effect, Fulgurvoltz). Public so the AI can preview a group.
static func unit_has_state(game: GameState, unit: Card, state: String, source_uid: int) -> bool:
	match state:
		"frozen":
			return unit.is_frozen()
		"exhausted":
			return unit.exhausted
		"weaker_than_source":
			var source := game.find_unit(source_uid)
			return source != null and unit.atk_total() + unit.hp_total() < source.atk_total() + source.hp_total()
	return false
