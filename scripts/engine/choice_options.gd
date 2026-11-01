extends RefCounted
## Shared option availability and target selection for choices made at different times.

static func target_spec(game, option: Dictionary) -> String:
	if option.has("effects"):
		return game.target_spec(option["effects"])
	return String(option.get("pick", ""))

static func targets(game, player: int, source_uid: int, opposed_uid: int, option: Dictionary) -> Array:
	var spec := target_spec(game, option)
	if spec == "":
		return []
	var result: Array = []
	if spec == "hand_card":
		for card: Card in game.players[player]["hand"]:
			result.append(card.uid)
	else:
		result = game.valid_targets(player, spec, source_uid, false, option.get("effects", []))
	if option.get("exclude_opposed", false):
		result.erase(opposed_uid)
	return result

static func available(game, player: int, source_uid: int, opposed_uid: int, option: Dictionary) -> bool:
	if option.get("requires_opposed", false) and game.find_unit(opposed_uid) == null:
		return false
	return target_spec(game, option) == "" or not targets(game, player, source_uid, opposed_uid, option).is_empty()
