class_name VenenoLethalEffect
extends Effect
## "veneno_lethal": until the start of the caster's next turn, the Veneno tick of every poisoned unit
## deals damage equal to that unit's current Vida instead of 2 per marker (Neráxia). Use target "none".
## The markers are still consumed as usual, Leaders are not units and keep the normal tick, and a unit
## that is protected from periodic damage (Indestrutível) still survives.

func apply(context: EffectContext, _target_uid: int) -> void:
	context.game.make_veneno_lethal_until_next_turn_of(context.controller)
