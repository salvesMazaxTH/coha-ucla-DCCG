class_name CounterEffect
extends Effect
## "counter": cancels the chosen card on the stack. Not stopped by Escudo Mágico (it hits a
## stack item, not a unit), so it skips that check.

func apply_to(context: EffectContext, target_uid: int) -> void:
	context.game._counter(context.controller, target_uid)
