class_name SnowballLevelEffect
extends Effect
## "snowball_level": changes the controller's Bola de Neve level WITHOUT casting one. The level is the
## starting damage of every future Bola de Neve (see SnowballEffect).
##   "amount": N  adds N to the level (default 1).
##   "multiply": N  multiplies the level by N instead.
##   "half_up": true  adds half of the current level, rounded up (Ladeira Abaixo e Sem Freio: 6 -> 9, 9 -> 14).
## Use it with target "none". Crossing into Grande is announced by GameState.set_snowball_level.

var amount := 1
var multiply := 0
var half_up := false

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 1))
	multiply = int(data.get("multiply", 0))
	half_up = bool(data.get("half_up", false))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var current_level: int = int(game.players[context.controller]["snowball"])
	var new_level: int = current_level + amount
	if multiply > 0:
		new_level = current_level * multiply
	elif half_up:
		new_level = current_level + (current_level + 1) / 2 # integer division: half of the level, rounded up
	game.set_snowball_level(context.controller, new_level)
	game._emit({"type": "snowball_level", "player": context.controller, "level": new_level})
