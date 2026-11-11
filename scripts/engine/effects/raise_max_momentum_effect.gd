class_name RaiseMaxMomentumEffect
extends Effect
## "raise_max_momentum": raises the controller's Reservoir cap by `amount` for the rest of the game.

var amount := 1

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	game.add_momentum_cap_extras(context.controller, amount)
	game.refresh_scaling()
	game.emit_event({"type": "momentum", "player": context.controller})
