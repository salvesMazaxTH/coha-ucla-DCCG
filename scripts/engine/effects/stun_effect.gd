class_name StunEffect
extends Effect
## "stun": Atordoamento. The unit is tapped at once and stays Atordoada until the END of the next turn (whoever's
## turn that is), the same timing as Congelada; it does not untap while stunned, but untaps the moment it recovers.
## While stunned it can't attack, has no Rapidez and its Provocação forces nothing, but its ATK stays whole (it
## strikes back normally) and, being tapped, it can be challenged. Stunning it again renews the deadline; it never stacks.

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	# `stunned` holds the turn at whose END the unit recovers
	unit.stunned = maxi(unit.stunned, game.turn + 1)
	if not unit.has_kw("inerte"):
		unit.exhausted = true
	game.emit_event({"type": "stun", "uid": target_uid})
	# cards listening to "unit_stunned" react to it (Layla Veyr); 'player' is the stunned unit's owner
	game.bus().emit(GameEvent.new("unit_stunned", unit.owner, unit))
