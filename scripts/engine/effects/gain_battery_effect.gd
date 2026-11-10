class_name GainBatteryEffect
extends Effect
## "gain_battery": adds `amount` to the controller's Bateria, up to its cap.

var amount := 1

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))

func apply(context: EffectContext, _target_uid: int) -> void:
	var player: Dictionary = context.game.players[context.controller]
	player["battery"] = mini(GameState.BATTERY_CAP, int(player["battery"]) + amount)
	context.game.emit_event({"type": "momentum", "player": context.controller}) # redraws the Momentum bar
