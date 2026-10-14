class_name SnowballLevelEffect
extends Effect
## "snowball_level": changes the controller's Bola de Neve level WITHOUT casting one. The level is the
## starting damage of every future Bola de Neve (see SnowballEffect).
##   "amount": N  adds N to the level (default 1).
##   "multiply": N  multiplies the level by N instead (Ladeira Abaixo e Sem Freio doubles it).
## Use it with target "none". Crossing into Grande is announced by GameState.set_snowball_level.

var amount := 1
var multiply := 0

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))
	multiply = int(data.get("multiply", 0))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var current_level: int = int(game.players[context.controller]["snowball"])
	var new_level: int = current_level * multiply if multiply > 0 else current_level + amount
	game.set_snowball_level(context.controller, new_level)
	game._emit({"type": "snowball_level", "player": context.controller, "level": new_level})
