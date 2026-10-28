class_name FreezeEffect
extends Effect
## "freeze": Congelada until the end of the next turn (whoever's turn that is): it doesn't attack,
## doesn't untap and doesn't guard its Leader. Its ATK stays whole (it strikes back normally) and it
## keeps the position it had (freezing doesn't tap it).
## "unfreeze": the target thaws on the spot (Jovahr melts the ice with fire). Does nothing to a unit that isn't frozen.

var ignores_immunity := false

func _read_parameters(data: Dictionary) -> void:
	ignores_immunity = bool(data.get("ignores_immunity", false))

func is_already_applied_to(unit: Card) -> bool:
	return unit.is_frozen()

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	if action == "unfreeze":
		if unit.is_frozen():
			unit.frozen = 0
			game._emit({"type": "thaw", "uid": target_uid})
		return
	# Gelo units are innately immune, including when the freeze comes from an area effect.
	if CardDB.has_element(unit.data(), "gelo") and not ignores_immunity:
		game._emit({"type": "dot_immune", "uid": target_uid, "dot": "congelar"})
		return
	# `frozen` holds the turn at whose END the unit thaws
	unit.frozen = maxi(unit.frozen, game.turn + 1)
	game._emit({"type": "freeze", "uid": target_uid})
