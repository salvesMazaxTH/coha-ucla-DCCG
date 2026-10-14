class_name FreezeEffect
extends Effect
## "freeze": the target unit's ATK is 0 until the next turn starts (whoever's turn that is),
## so the freeze only lasts for the turn in which it was applied.
## Exception: a unit that was still summoning sick never had the chance to act (tap, challenge or hit
## the Leader), so its freeze also covers its owner's next turn: the owner loses one opportunity.

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	# `frozen` holds the turn at whose START the unit thaws
	var thaw_turn: int = game.turn + 1
	if unit.sick:
		# skip over the owner's next turn too: it comes at turn+2 if the owner is playing now, else turn+1
		thaw_turn = game.turn + (3 if unit.owner == game.active else 2)
	unit.frozen = maxi(unit.frozen, thaw_turn)
	game._emit({"type": "freeze", "uid": target_uid})
