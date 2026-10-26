class_name GainReserveEffect
extends Effect
## "gain_reserve": the controller banks `amount` Reserva right now, never above GameState.RESERVE_CAP
## (with a full Reserva it does nothing). The Reserva only pays for spells and abilities.

var amount := 1

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))

func apply(context: EffectContext, _target_uid: int) -> void:
	var player: Dictionary = context.game.players[context.controller]
	player["reserve"] = mini(GameState.RESERVE_CAP, int(player["reserve"]) + amount)
	context.game._emit({"type": "momentum", "player": context.controller}) # redraws the Momentum bar
