class_name TideMarkEffect
extends Effect
## "tide_mark": puts the Marca da Maré on the target unit.

func apply(context: EffectContext, target_uid: int) -> void:
	var unit := context.game.find_unit(target_uid)
	if unit != null:
		unit.tide_mark = true
		context.game._emit({"type": "tide_mark", "uid": target_uid})
