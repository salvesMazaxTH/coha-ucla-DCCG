class_name RaiseMaxMomentumEffect
extends Effect
## "raise_max_momentum": real ramp. Raises the controller's maximum Momentum by `amount` for the rest
## of the game (never above GameState.MOMENTUM_CAP), so every later turn starts with that much more.
## It gives nothing this turn: the Momentum in hand stays as it is.

var amount := 1

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))

func apply(context: EffectContext, _target_uid: int) -> void:
	var player: Dictionary = context.game.players[context.controller]
	player["max_momentum"] = mini(GameState.MOMENTUM_CAP, int(player["max_momentum"]) + amount)
