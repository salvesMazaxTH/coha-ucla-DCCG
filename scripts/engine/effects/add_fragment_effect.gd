class_name AddFragmentEffect
extends Effect
## "add_fragment": puts `amount` Fragmentos de Rai'Emofitir on the target unit (see GameState.add_fragments).
## The Fragmento is a marker that stays on the unit and hops to an ally when it dies, so it is not a periodic status.

var amount := 1

func _read_parameters(data: Dictionary) -> void:
	amount = maxi(1, int(data.get("amount", 1)))

func apply(context: EffectContext, target_uid: int) -> void:
	var unit := context.game.find_unit(target_uid)
	if unit == null:
		return
	context.game.add_fragments(unit, amount, context.source_id())
