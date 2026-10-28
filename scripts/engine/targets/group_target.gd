class_name GroupTarget
extends TargetSelector
## Every unit of a group: all_enemy_units, all_units (own side first), other_units (all_units without the unit that
## runs the effect), all_ally_units, other_ally_units, all_enemy_tokens (only the enemy fichas), center_enemy_units
## (the middle of the enemy board as it stands: 1 unit if the count is odd, the 2 middle ones if even).
## Any group can be narrowed by a "unit_filter" in the effect's JSON: a CardFilter dictionary checked against each
## unit's printed card, e.g. {"max_cost": 4} keeps only the units that cost 4 or less (Kazeminus).
## "unit_state": "frozen" keeps only the units that are Congeladas right now (Jovahr); checked live, when the effect runs.

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
	if effect.raw.get("unit_state", "") == "frozen":
		uids = uids.filter(func(uid: int) -> bool: return context.game.find_unit(uid).is_frozen())
	return uids
