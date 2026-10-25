class_name ExtraTurnEffect
extends Effect
## "extra_turn": the controller plays another turn right after this one, instead of the opponent taking it.
## Only works during the controller's own turn (put it on "on_turn_start", "on_turn_end" or an Ao Ativar).
## An extra turn never grants another one: while the player is in an extra turn, this effect does nothing.
## "max_per_game" (default 0 = no limit): how many extra turns a player can be given in the whole game.
## "draw" (default true): whether the extra turn begins with the normal card draw. Momentum refreshes as in any turn.

var max_per_game := 0
var draws := true

func _read_parameters(data: Dictionary) -> void:
	max_per_game = int(data.get("max_per_game", 0))
	draws = bool(data.get("draw", true))

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var player: Dictionary = game.players[context.controller]
	if context.controller != game.active or player["extra_turn_pending"] or player["in_extra_turn"]:
		return
	if max_per_game > 0 and int(player["extra_turns_taken"]) >= max_per_game:
		return
	player["extra_turns_taken"] += 1
	player["extra_turn_pending"] = true
	player["extra_turn_draws"] = draws
	game._emit({"type": "extra_turn_promised", "player": context.controller})
