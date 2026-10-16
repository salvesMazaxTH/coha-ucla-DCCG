class_name RemoveEffect
extends Effect
## Ways to take a unit off the board, told apart by `action`:
## "destroy": the target unit dies. Not damage: ignores size and Escudo, but Indestrutível stops
##   it (only removal from the game, e.g. banish, bypasses it).
##   "shield_leader_damage": N = if the unit had Escudo, its owner's Leader takes N damage.
## "banish": exile, stronger than destroy. Ignores Indestrutível, the unit never dies (no Ao
##   Morrer, no Aliado Morre) and never reaches the graveyard; its equipment does.
##   "requires_markers": {"dot": "veneno", "amount": X}: the banish only happens if the unit holds
##   at least X markers of that kind, otherwise nothing happens.
## "destroy_artifact": the target free-standing artifact goes to the graveyard, freeing its slot.
## "kill_leader": the targeted Leader dies on the spot, but only if it holds the "requires_markers"
##   amount of that marker kind (Viprax's execution). Câmara de Êxtase does not save it.

var shield_leader_damage := 0
var required_dot := ""
var required_dot_amount := 0


func _read_parameters(data: Dictionary) -> void:
	shield_leader_damage = int(data.get("shield_leader_damage", 0))
	var requirement: Dictionary = data.get("requires_markers", {})
	required_dot = String(requirement.get("dot", ""))
	required_dot_amount = int(requirement.get("amount", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	if action == "banish":
		_banish(context, target_uid)
	elif action == "kill_leader":
		_kill_leader(context, target_uid)
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

func _kill_leader(context: EffectContext, target_uid: int) -> void:
	var leader_player := GameState.LEADER_UID.find(target_uid)
	if leader_player < 0:
		return
	if context.game.leader_dot_markers(leader_player, required_dot) < required_dot_amount:
		return
	context.game.kill_leader_outright(leader_player, required_dot)

func _banish(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var exiled := game.find_unit(target_uid)
	if exiled == null:
		return
	if required_dot != "" and int(exiled.dot_markers.get(required_dot, 0)) < required_dot_amount:
		return
	game.banish_unit(exiled)
