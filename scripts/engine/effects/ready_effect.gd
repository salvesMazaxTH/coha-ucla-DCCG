class_name ReadyEffect
extends Effect
## "ready": the target unit stands up again (the opposite of "exhaust"), so it can attack, guard or use an
## Ao Ativar that exhausts it once more this turn. "not_rarity": ["champion"] keeps it off those rarities.
## Both that filter and "requires_exhausted" also narrow the choice of target (GameState.meets_unit_requirement).

var excluded_rarities: Array = []

func _read_parameters(data: Dictionary) -> void:
	excluded_rarities = data.get("not_rarity", [])

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null or not unit.exhausted or excluded_rarities.has(CardDB.card(unit.card_id).get("rarity", "")):
		return
	unit.exhausted = false
	game._emit({"type": "ready", "uid": target_uid})
	# cards listening to "unit_readied" react to it (Moenda do Seu Belmiro mills the opponent's deck);
	# the untap at the start of a turn never comes through here, so it does not count
	game.bus().emit(GameEvent.new("unit_readied", unit.owner, unit))
