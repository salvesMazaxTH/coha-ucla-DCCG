class_name SpendAllMomentumEffect
extends Effect
## "spend_all_momentum": the controller loses ALL of their plain Momentum right now (Barão Estrondoso).
## The Reserva is not touched. Use it with "target": "none" and an "if" on the Momentum left to be spent.

func apply(context: EffectContext, _target_uid: int) -> void:
	var player: Dictionary = context.game.players[context.controller]
	if int(player["momentum"]) <= 0:
		return
	player["momentum"] = 0
	context.game._refresh_scaling() # a surge (11+ Momentum) may have just turned off
	context.game._emit({"type": "momentum", "player": context.controller})
