class_name SilenceEffect
extends Effect
## "silence": Silêncio. The target unit loses every keyword and every ability (Constante, Ao Atacar, Ao Morrer,
## Condicional, Ativar...) for as long as it stays on the board, and goes back to its printed Ataque and Vida (buffs and
## equipment stats are lost). It keeps its damage and status effects. See Card.silence(). Leaders can't be silenced (units only).
## Only the unit's OWN effects are silenced: a Constante of an ally that buffs it (species_aura, adjacent_armor) keeps
## working, and to turn that bonus off you silence the ally that carries the Constante.

func is_already_applied_to(unit: Card) -> bool:
	return unit.is_silenced()

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null or unit.is_silenced():
		return
	unit.silence()
	game._refresh_scaling() # the unit's own scaling is gone, the auras of its allies stay (they are the allies' effects)
	unit.keep_alive_with_one_hp()
	game._emit({"type": "silence", "uid": target_uid})
