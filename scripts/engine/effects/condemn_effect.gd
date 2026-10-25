class_name CondemnEffect
extends Effect
## "condemn": the target unit becomes Condenada. At the start of its marker-giver's next turn it
## dies (see GameState._resolve_condemned). The mark is just a turn number on the unit, so it
## still works if the card that placed it has already left the board. Healing doesn't help; only
## Indestrutível, leaving the board or an enemy Escudo Mágico (which cancels the mark) do.

func is_already_applied_to(unit: Card) -> bool:
	return unit.is_condemned()

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null or unit.is_condemned():
		return
	# The sentence is carried out when the controller's next turn starts: two turns from now when
	# this is the controller's own turn, otherwise the very next turn.
	var turns_until_sentence := 2 if game.active == context.controller else 1
	unit.condemned_turn = game.turn + turns_until_sentence
	game._emit({"type": "condemn", "uid": target_uid})
