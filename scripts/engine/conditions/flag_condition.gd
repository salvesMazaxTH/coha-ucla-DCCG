class_name FlagCondition
extends Condition
## The simple string conditions: "if": "momentum_left" | "reserve_full" | "played_two".

const NAMES := ["momentum_left", "reserve_full", "played_two"]

var name := ""

func _init(flag_name: String) -> void:
	name = flag_name

func check(context: EffectContext) -> bool:
	var player: Dictionary = context.game.players[context.controller]
	match name:
		"momentum_left": return player["momentum"] > 0
		"reserve_full": return player["reserve"] >= GameState.RESERVE_CAP
		"played_two": return player["played_two"]
	return true
