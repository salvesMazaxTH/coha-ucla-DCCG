class_name ExhaustEffect
extends Effect
## "exhaust": the target unit becomes exhausted (tapped). An exhausted unit cannot attack, and the opponent
## may challenge it. It stands up again at the start of its owner's next turn, so against an enemy unit
## this opens a window to challenge it during the effect's controller's own turn.

func is_already_applied_to(unit: Card) -> bool:
	return unit.exhausted

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null or unit.exhausted or unit.data().get("inert", false): # an inert unit never taps
		return
	unit.exhausted = true
	game._emit({"type": "exhaust", "uid": target_uid})
