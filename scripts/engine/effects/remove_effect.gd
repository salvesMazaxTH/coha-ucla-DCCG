class_name RemoveEffect
extends Effect
## Ways to take a unit off the board, told apart by `action`:
## "destroy": the target unit dies. Not damage: ignores size and Escudo, but Indestrutível stops
##   it (only removal from the game, e.g. banish, bypasses it).
## "banish": exile, stronger than destroy. Ignores Indestrutível, the unit never dies (no Ao
##   Morrer, no Aliado Morre) and never reaches the graveyard; its equipment does.

func apply(context: EffectContext, target_uid: int) -> void:
	if action == "banish":
		_banish(context, target_uid)
	else:
		_destroy(context, target_uid)

func _destroy(context: EffectContext, target_uid: int) -> void:
	var doomed := context.game.find_unit(target_uid)
	if doomed == null or doomed.has_kw("indestrutivel"):
		return
	doomed.damage = 1000000
	context.game._emit({"type": "destroy", "uid": target_uid})

func _banish(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var exiled := game.find_unit(target_uid)
	if exiled == null:
		return
	var owner_player: int = exiled.owner
	game.players[owner_player]["board"].erase(exiled)
	game._release_equipment(exiled)
	if exiled.data().get("token", false):
		game._move(exiled, "") # a banished ficha just vanishes
	else:
		game.players[owner_player]["banished"].append(exiled)
		game._move(exiled, "banished")
	game._emit({"type": "banish", "uid": target_uid, "player": owner_player, "card_id": exiled.card_id})
