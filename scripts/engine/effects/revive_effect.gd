class_name ReviveEffect
extends Effect
## Returning from the graveyard, told apart by `action`:
## "revive": a random unit card (cost <= max_cost) from the controller's graveyard returns to the board.
## "revive_self" (Ao Morrer): the dying unit comes back as a new instance (so it no longer takes
##   part in the combat it died in), with base atk/hp changed by `atk`/`hp` (usually negative)
##   relative to what it had when it died. It does not return if atk or hp would reach 0.

var max_cost := 99
var attack_change := 0
var health_change := 0

func _read_parameters(data: Dictionary) -> void:
	max_cost = int(data.get("max_cost", 99))
	attack_change = int(data.get("atk", 0))
	health_change = int(data.get("hp", 0))

func apply(context: EffectContext, _target_uid: int) -> void:
	if action == "revive_self":
		_revive_self(context)
	else:
		_revive_random(context)

func _revive_random(context: EffectContext) -> void:
	var game := context.game
	var player: Dictionary = game.players[context.controller]
	if player["board"].size() >= GameState.BOARD_LIMIT:
		return
	var candidates: Array = []
	for grave_card: Card in player["graveyard"]:
		var card_data := CardDB.card(grave_card.card_id)
		if card_data["type"] == "unit" and int(card_data["cost"]) <= max_cost:
			candidates.append(grave_card)
	if candidates.is_empty():
		return
	var pick: Card = candidates[game.rng.randi_range(0, candidates.size() - 1)]
	player["graveyard"].erase(pick)
	game._emit({"type": "revive", "player": context.controller, "card_id": pick.card_id})
	pick.uid = game._uid() # back on the board as a new instance
	game._summon(context.controller, pick, false, 0)

func _revive_self(context: EffectContext) -> void:
	var game := context.game
	var dying := context.dying_card
	if dying == null or dying.legendary:
		return
	var new_attack: int = dying.atk + attack_change
	var new_health: int = dying.hp + health_change
	var player: Dictionary = game.players[context.controller]
	if new_attack <= 0 or new_health <= 0 or player["board"].size() >= GameState.BOARD_LIMIT:
		return
	# while on the board it is not a graveyard card, so it leaves the graveyard
	player["graveyard"].erase(dying)
	var overrides: Dictionary = dying.over.duplicate()
	overrides["atk"] = new_attack
	overrides["hp"] = new_health
	game._emit({"type": "revive", "player": context.controller, "card_id": dying.card_id})
	dying.uid = game._uid() # a new instance: it no longer takes part in the combat it died in
	game._summon(context.controller, dying, false, 0, overrides)
