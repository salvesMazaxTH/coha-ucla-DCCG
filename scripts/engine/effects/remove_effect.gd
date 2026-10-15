class_name RemoveEffect
extends Effect
## Ways to take a unit off the board, told apart by `action`:
## "destroy": the target unit dies. Not damage: ignores size and Escudo, but Indestrutível stops
##   it (only removal from the game, e.g. banish, bypasses it).
##   "shield_leader_damage": N = if the unit had Escudo, its owner's Leader takes N damage.
## "banish": exile, stronger than destroy. Ignores Indestrutível, the unit never dies (no Ao
##   Morrer, no Aliado Morre) and never reaches the graveyard; its equipment does.
## "destroy_artifact": the target free-standing artifact goes to the graveyard, freeing its slot.

var shield_leader_damage := 0

func _read_parameters(data: Dictionary) -> void:
	shield_leader_damage = int(data.get("shield_leader_damage", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	if action == "banish":
		_banish(context, target_uid)
	elif action == "destroy_artifact":
		var artifact := context.game.find_relic(target_uid)
		if artifact != null:
			context.game.destroy_relic(artifact)
	else:
		_destroy(context, target_uid)

func _destroy(context: EffectContext, target_uid: int) -> void:
	var doomed := context.game.find_unit(target_uid)
	if doomed == null or doomed.has_kw("indestrutivel"):
		return
	var had_shield: bool = doomed.shield
	doomed.damage = 1000000
	context.game._emit({"type": "destroy", "uid": target_uid})
	if had_shield and shield_leader_damage > 0:
		context.game._deal_damage(GameState.LEADER_UID[doomed.owner], shield_leader_damage, null)

func _banish(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var exiled := game.find_unit(target_uid)
	if exiled == null:
		return
	game.banish_unit(exiled)
