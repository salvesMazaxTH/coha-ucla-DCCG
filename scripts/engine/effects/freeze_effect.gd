class_name FreezeEffect
extends Effect
## "freeze": Congelada until the end of the next turn (whoever's turn that is): it doesn't attack,
## doesn't untap and doesn't guard its Leader. Its ATK stays whole (it strikes back normally) and it
## keeps the position it had (freezing doesn't tap it).

func is_already_applied_to(unit: Card) -> bool:
	return unit.is_frozen()

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	# `frozen` holds the turn at whose END the unit thaws
	unit.frozen = maxi(unit.frozen, game.turn + 1)
	game._emit({"type": "freeze", "uid": target_uid})
