class_name SilenceEffect
extends Effect
## "silence": Silêncio. The target unit loses every keyword and every ability (Constante, Ao Atacar, Ao Morrer,
## Condicional, Ativar...) for as long as it stays on the board, and goes back to its printed Ataque and Vida (buffs and
## equipment stats are lost). It keeps its damage and status effects. See Card.silence(). Leaders can't be silenced (units only).

func is_already_applied_to(unit: Card) -> bool:
	return unit.is_silenced()

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null or unit.is_silenced():
		return
	unit.silence()
	game._emit({"type": "silence", "uid": target_uid})
