class_name SpendAllMomentumEffect
extends Effect
## "spend_all_momentum": the controller loses ALL of their plain Momentum (Barão Estrondoso). The Reserva is not touched.
## When it fires from an extra attack (auto_attack), the Momentum is spent only after the attack the player declared
## has landed too, so that blow still has the Momentum surge (see CombatSystem.spend_all_momentum_after_attacks).
## Use it with "target": "none" and an "if" on the Momentum left to be spent.

func apply(context: EffectContext, _target_uid: int) -> void:
	context.game.combat_system().spend_all_momentum_after_attacks(context.controller)
