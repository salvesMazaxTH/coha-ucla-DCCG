class_name FatigueBurnEffect
extends Effect
## "fatigue_burn": the opponent suffers their next Fadiga right now (damage to their Leader, and the counter advances),
## whatever is left in their deck (Hora Extra Compulsória). It scales with how much Fadiga they already took.

func apply(context: EffectContext, _target_uid: int) -> void:
	context.game.suffer_fatigue(context.game.opponent(context.controller))
