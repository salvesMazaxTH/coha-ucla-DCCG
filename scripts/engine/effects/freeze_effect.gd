class_name FreezeEffect
extends Effect
## "freeze": the target unit can't attack or block until the end of its owner's next turn.

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	# thaws at the end of its owner's next turn
	var until: int = game.turn + (2 if unit.owner == game.active else 1)
	unit.frozen = maxi(unit.frozen, until)
	game._emit({"type": "freeze", "uid": target_uid})
