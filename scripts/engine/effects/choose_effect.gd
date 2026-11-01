extends Effect
## Pauses the current effect until its controller selects one option and, if needed, a target.

func apply(context: EffectContext, _target_uid: int) -> void:
	context.game.begin_effect_choice(context, raw)
