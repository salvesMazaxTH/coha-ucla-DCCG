extends RefCounted
## Playtest da ação summon_random: um Feitiço no cemitério por invocação, até a mesa encher.

const PLAYER_DECK := "agua"
const ENEMY_DECK := "fogo"
const TEST_CARD_ID := "scenario_summon_random_playtest"
const SPELL_COUNT := 12

static func setup(g: GameState) -> void:
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	g.active = 0
	g.players[0]["hand"].clear()

	var card_id := _random_common_unit(g)
	if card_id == "":
		return
	var card_data := CardDB.card(card_id).duplicate(true)
	card_data["name"] = "Teste Aleatório"
	card_data["effects"] = [{
		"trigger": "on_enter",
		"action": "summon_random",
		"target": "none",
		"domain": "all",
		"include_tokens": false,
		"rarity_any": ["epic", "legendary"],
		"min_cost": 4,
		"per_graveyard_spell": true,
	}]
	card_data["keywords"] = []
	card_data["text"] = "Ao Entrar: para cada Feitiço no seu cemitério, esta unidade invoca uma unidade aleatória Épica ou Lendária de custo 4 ou mais, de qualquer domínio. Para quando sua mesa encher."
	card_data["flavor"] = ""
	card_data.erase("activated")
	card_data.erase("transform")
	CardDB.data()["cards"][TEST_CARD_ID] = card_data

	var spell_ids: Array[String] = []
	for candidate_id in CardDB.data()["cards"]:
		if CardDB.card(String(candidate_id)).get("type", "") == "spell":
			spell_ids.append(String(candidate_id))
	spell_ids.sort()
	if spell_ids.is_empty():
		push_error("summon_random_playtest precisa de pelo menos um Feitiço no catálogo")
		return
	for i in SPELL_COUNT:
		var spell_id: String = spell_ids[i % spell_ids.size()]
		g.players[0]["graveyard"].append(Card.new(g._uid(), spell_id, 0, "graveyard"))

	var test_card := Card.new(g._uid(), TEST_CARD_ID, 0, "hand")
	g.players[0]["hand"].append(test_card)
	g.players[0]["max_momentum"] = 10
	g.players[0]["momentum"] = 10
	g._flush()

static func _random_common_unit(g: GameState) -> String:
	var candidates: Array[String] = []
	for card_id in CardDB.data()["cards"]:
		var card_data := CardDB.card(String(card_id))
		if card_data.get("type", "") != "unit" or card_data.get("rarity", "") != "common":
			continue
		if bool(card_data.get("token", false)) or bool(card_data.get("transform_only", false)) \
				or bool(card_data.get("undraftable", false)) or card_data.has("activated") \
				or int(card_data.get("cost", 99)) > 10:
			continue
		candidates.append(String(card_id))
	candidates.sort()
	if candidates.is_empty():
		push_error("summon_random_playtest não encontrou uma unidade Comum jogável")
		return ""
	return candidates[g.rng.randi_range(0, candidates.size() - 1)]
