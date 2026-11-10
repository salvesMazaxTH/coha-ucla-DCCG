class_name SummonRandomEffect
extends Effect
## Randomly summons units from the full card catalog, applying CardFilter and the Leader-domain option.

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	var player := context.controller
	var count := int(raw.get("count", 1))
	if bool(raw.get("per_graveyard_spell", false)):
		count = game.graveyard_size_of_kind(player, "spell")
	elif raw.has("per_graveyard"):
		count = _count_from_graveyard(game, player)
	if count <= 0 or not game.has_free_slot(player):
		return

	# "as_token": the summoned unit is a ficha (it vanishes instead of going to the graveyard or back to the hand)
	var summon_overrides := {"token": true} if bool(raw.get("as_token", false)) else {}
	var candidates := _candidate_ids(game, player)
	if candidates.is_empty():
		game.emit_event({"type": "search_empty", "player": player, "source_uid": context.self_uid})
		return

	for _i in count:
		if not game.has_free_slot(player):
			return
		var card_id: String = candidates[game.rng.randi_range(0, candidates.size() - 1)]
		game._summon(player, Card.new(game._uid(), card_id, player), false, 0, summon_overrides)

## One unit per `per` graveyard cards that pass the filter written in `per_graveyard` (rounded down).
## The filter uses the same keys as CardFilter (tribe, element, type...); `per` is the group size (default 1).
func _count_from_graveyard(game: GameState, player: int) -> int:
	var graveyard_rule: Dictionary = raw["per_graveyard"]
	var group_size := maxi(1, int(graveyard_rule.get("per", 1)))
	var matching_cards := 0
	for graveyard_card: Card in game.players[player]["graveyard"]:
		if CardFilter.matches(graveyard_card.card_id, graveyard_rule):
			matching_cards += 1
	return matching_cards / group_size

func _candidate_ids(game: GameState, player: int) -> Array[String]:
	var domain: Variant = raw.get("domain", "all")
	if not domain is String or String(domain) not in ["all", "leader"]:
		push_error("summon_random.domain precisa ser \"all\" ou \"leader\"")
		return []

	var include_tokens := bool(raw.get("include_tokens", false))
	var leader_id := String(game.players[player]["leader_id"])
	var candidates: Array[String] = []
	for raw_id in CardDB.data()["cards"]:
		var card_id := String(raw_id)
		var card_data := CardDB.card(card_id)
		if not CardDB.has_type(card_data, "unit"):
			continue
		if not include_tokens and bool(card_data.get("token", false)):
			continue
		if bool(card_data.get("transform_only", false)) or bool(card_data.get("undraftable", false)):
			continue
		if domain == "leader" and not DeckDB.is_in_leader_domain(leader_id, card_id):
			continue
		if not CardFilter.matches(card_id, raw):
			continue
		candidates.append(card_id)
	candidates.sort()
	return candidates
