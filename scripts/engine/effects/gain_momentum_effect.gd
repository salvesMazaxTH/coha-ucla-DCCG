class_name GainMomentumEffect
extends Effect
## "gain_momentum": +amount Momentum right now (never above the cap), or at the start of the
## controller's next turn ("next_turn": true). A negative amount with "next_turn" is a debt: the
## next turn starts with that much less Momentum (never below 0).
## "per": "leaked" refunds the Momentum that leaked past the Reserva this turn instead:
## floor(leaked / divisor), at most `max`.

var amount := 0
var per := ""
var divisor := 1
var maximum := GameState.MOMENTUM_CAP
var next_turn := false

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 0))
	per = String(data.get("per", ""))
	divisor = maxi(1, int(data.get("divisor", 1)))
	maximum = int(data.get("max", GameState.MOMENTUM_CAP))
	next_turn = bool(data.get("next_turn", false))

func apply(context: EffectContext, _target_uid: int) -> void:
	var player: Dictionary = context.game.players[context.controller]
	var gain := amount
	if per == "leaked":
		gain = mini(maximum, int(player["leaked"]) / divisor)
		if gain <= 0:
			return
	if next_turn:
		player["next_momentum"] += gain
	else:
		player["momentum"] = mini(GameState.MOMENTUM_CAP, int(player["momentum"]) + gain)
		context.game._emit({"type": "momentum", "player": context.controller})
