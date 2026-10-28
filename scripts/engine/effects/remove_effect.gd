class_name RemoveEffect
extends Effect
## Ways to take a unit off the board, told apart by `action`:
## "destroy": the target unit dies. Not damage: ignores size and Escudo, but Indestrutível stops
##   it (only removal from the game, e.g. banish, bypasses it).
##   "shield_leader_damage": N = if the unit had Escudo, its owner's Leader takes N damage.
##   "banish_instead_domain": a unit of that domain is banished by this effect instead of being destroyed: it never dies
##   (no Ao Morrer, no Aliado Morre), Indestrutível and death wards don't matter (Expurgo Sagrado).
##   "max_target_cost": N = only a unit whose printed cost is N or less is destroyed, otherwise nothing happens
##   (Bicho Papão: a challenged cheap unit dies before combat).
## "banish": exile, stronger than destroy. Ignores Indestrutível, the unit never dies (no Ao
##   Morrer, no Aliado Morre) and never reaches the graveyard; its equipment does.
##   "requires_markers": {"dot": "veneno", "amount": X}: the banish only happens if the unit holds
##   at least X markers of that kind, otherwise nothing happens.
## "destroy_artifact": the target free-standing artifact goes to the graveyard, freeing its slot.
##   "subtype": "local": only an artifact of that subtype can be picked and destroyed (default: any artifact).
## "kill_leader": the targeted Leader dies on the spot, but only if it holds the "requires_markers"
##   amount of that marker kind (Viprax's execution). Câmara de Êxtase does not save it.

var shield_leader_damage := 0
var banish_instead_domain := ""
var required_dot := ""
var required_dot_amount := 0
var required_subtype := ""
var max_target_cost := -1 # -1 = any cost


func _read_parameters(data: Dictionary) -> void:
	shield_leader_damage = int(data.get("shield_leader_damage", 0))
	banish_instead_domain = String(data.get("banish_instead_domain", ""))
	var requirement: Dictionary = data.get("requires_markers", {})
	required_dot = String(requirement.get("dot", ""))
	required_dot_amount = int(requirement.get("amount", 0))
	required_subtype = String(data.get("subtype", ""))
	max_target_cost = int(data.get("max_target_cost", -1))

func harms_own_target() -> bool:
	return true

func apply(context: EffectContext, target_uid: int) -> void:
	if action == "banish":
		_banish(context, target_uid)
	elif action == "kill_leader":
		_kill_leader(context, target_uid)
	elif action == "destroy_artifact":
		var artifact := context.game.find_relic(target_uid)
		if artifact != null and (required_subtype == "" or artifact.data().get("subtypes", []).has(required_subtype)):
			context.game.destroy_relic(artifact)
	else:
		_destroy(context, target_uid)

func _destroy(context: EffectContext, target_uid: int) -> void:
	var doomed := context.game.find_unit(target_uid)
	if doomed == null:
		return
	if max_target_cost >= 0 and int(doomed.data()["cost"]) > max_target_cost:
		return
	if banish_instead_domain != "" and CardDB.has_essence(doomed.data(), banish_instead_domain):
		context.game.banish_unit(doomed) # exiled on the spot: it never dies
		return
	if doomed.has_kw("indestrutivel"):
		return
	if context.game._consume_death_ward(doomed):
		return # cancel this destruction entirely; the ward was sacrificed instead
	var had_shield: bool = doomed.shield
	doomed.damage = 1000000
	context.game._emit({"type": "destroy", "uid": target_uid, "card_id": doomed.card_id})
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
