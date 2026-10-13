class_name TransformEffect
extends Effect
## "transform_self": {"into": <card id>}. The unit that owns this effect becomes that card on the spot,
## with no cost and without using the stack (Princesa Wanessa becomes Wanessa Tempesfrost when
## her controller casts a Grande Bola de Neve). Use it with target "self".

var into_card_id := ""

func _read_parameters(data: Dictionary) -> void:
	into_card_id = String(data.get("into", ""))

func apply(context: EffectContext, target_uid: int) -> void:
	var unit := context.game.find_unit(target_uid)
	if unit == null or unit.card_id == into_card_id:
		return
	context.game.transform_into(unit, into_card_id)
