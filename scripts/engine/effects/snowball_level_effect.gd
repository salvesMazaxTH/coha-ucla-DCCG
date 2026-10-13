class_name SnowballLevelEffect
extends Effect
## "snowball_level": raises the controller's Bola de Neve level by `amount` (default 1) WITHOUT casting
## one. The level is the starting damage of every future Bola de Neve (see SnowballEffect).
## Use it with target "none".

var amount := 1

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))

func apply(context: EffectContext, _target_uid: int) -> void:
	var player: Dictionary = context.game.players[context.controller]
	player["snowball"] = int(player["snowball"]) + amount
	context.game._emit({"type": "snowball_level", "player": context.controller, "level": int(player["snowball"])})
