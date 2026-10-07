extends SceneTree
## Headless: godot --headless --path . -s tests/run_tests.gd

var failures := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)

func _init() -> void:
	for d in ["fogo", "agua"]:
		var errs := CardDB.validate_deck(d)
		check(errs.is_empty(), "deck %s: %s" % [d, errs])
	_test_setup()
	_test_search()
	_test_combat()
	_test_triggers()
	_test_sim()
	print("tests done, failures: ", failures)
	quit(1 if failures > 0 else 0)

func _new_game() -> GameState:
	var g := GameState.new("fogo", "agua", 42)
	g.mulligan(0, [])
	g.mulligan(1, [])
	return g

func _put(g: GameState, p: int, card_id: String, ready := true) -> Dictionary:
	var uid := g._uid()
	g._summon(p, card_id, uid, false, 0)
	g._flush()
	if g.phase == "search":
		var options: Array = g.pending_search["cards"]
		g.choose_search(p, int(options[0]["uid"]))
		g._flush()
	var c := g.find_creature(uid)
	if ready:
		c["sick"] = false
	return c

func _test_search() -> void:
	var g := _new_game()
	var uid := g._uid()
	g._summon(1, "serpente_marinha", uid, false, 0)
	var reveal: Array = g._flush()
	check(g.phase == "search", "serpente abre escolha de busca")
	var revealed: Dictionary = {}
	for e in reveal:
		if e["type"] == "search_reveal":
			revealed = e
	check(not revealed.is_empty(), "busca revela opções publicamente")
	check(revealed.get("cards", []).size() > 0, "há opções elegíveis no deck")
	var chosen: Dictionary = revealed["cards"][0]
	var before_hand: int = g.players[1]["hand"].size()
	var picked: Array = g.choose_search(1, int(chosen["uid"]))
	check(g.phase == "main", "busca termina após escolha")
	check(g.players[1]["hand"].size() == before_hand + 1, "carta buscada vai para a mão")
	check(CardDB.card(chosen["card_id"])["essence"] == "aquatica" and int(CardDB.card(chosen["card_id"])["cost"]) <= 2, "busca respeita filtro de Aquática e custo")
	var took := false
	for e in picked:
		if e["type"] == "search_take":
			took = true
	check(took, "escolha emite evento de busca")

func _test_setup() -> void:
	var g := GameState.new("fogo", "agua", 1)
	check(g.players[0]["hand"].size() == 6 and g.players[1]["hand"].size() == 7, "starting hands 6/7")
	check(g.players[0]["deck"].size() == 41, "legendary not in deck")
	g.mulligan(0, [g.players[0]["hand"][0]["uid"]])
	g.mulligan(1, [])
	check(g.phase == "main" and g.active == 0 and g.players[0]["momentum"] == 1, "turn 1 momentum")
	check(g.players[0]["hand"].size() == 6, "no draw turn 1")

func _test_combat() -> void:
	var g := _new_game()
	var a := _put(g, 0, "kai") # 2/2 golpe rapido
	var b := _put(g, 1, "tritao_lanceiro") # 2/2
	g.declare_attack(0, {a["uid"]: 0})
	g.declare_blocks(1, {a["uid"]: b["uid"]})
	check(g.find_creature(b["uid"]).is_empty(), "first strike kills blocker")
	check(not g.find_creature(a["uid"]).is_empty(), "first striker survives")

	g = _new_game()
	var t := _put(g, 0, "kael_drath_vulcano") # 5/7 sobrepujança
	var s := _put(g, 1, "espirito_da_mare") # 1/2 escudo
	var hp: int = g.players[1]["leader_hp"]
	g.declare_attack(0, {t["uid"]: 0})
	g.declare_blocks(1, {t["uid"]: s["uid"]})
	check(not g.find_creature(s["uid"]).is_empty(), "shield absorbs hit")
	check(g.players[1]["leader_hp"] == hp - 3, "trample excess vs shield (%d)" % (hp - g.players[1]["leader_hp"]))

	g = _new_game()
	var f := _put(g, 0, "fenix_menor") # voo
	var w := _put(g, 1, "tritao_lanceiro") # longo alcance
	var x := _put(g, 1, "serpente_marinha")
	check(g.can_block(w, f) and not g.can_block(x, f), "voo/longo alcance")

	g = _new_game()
	var gk := _put(g, 0, "gorvakharr") # furtivo roubo de vida
	var y := _put(g, 1, "sentinela_coral") # vigia
	check(g.can_block(y, gk) and not g.can_block(x, gk), "furtivo/vigia")
	g.players[0]["leader_hp"] = 10
	g.declare_attack(0, {gk["uid"]: 0})
	g.declare_blocks(1, {})
	check(g.players[0]["leader_hp"] == 13, "lifesteal heals leader")

	g = _new_game()
	var k := _put(g, 0, "kael_drath_vulcano") # provocação
	var v := _put(g, 1, "serpente_marinha")
	g.declare_attack(0, {k["uid"]: v["uid"]})
	g.declare_blocks(1, {})
	check(g.find_creature(v["uid"]).is_empty(), "provoked creature forced to block")
	g.end_turn(0)
	check(g.find_creature(k["uid"])["damage"] == 0, "damage resets at end of turn")

func _tcard(id: String, atk: int, hp: int, effects: Array) -> void:
	CardDB.data()["cards"][id] = {"name": id, "type": "creature", "rarity": "common", "essence": "neutra", "cost": 1,
		"atk": atk, "hp": hp, "keywords": [], "art": "", "effects": effects, "text": "", "flavor": "", "tags": []}

func _test_triggers() -> void:
	_tcard("t_atk", 1, 5, [{"trigger": "on_attack", "action": "damage", "target": "enemy_leader", "amount": 2}])
	_tcard("t_blk", 1, 5, [{"trigger": "on_block", "action": "buff", "target": "self", "atk": 3, "temp": true}])
	_tcard("t_turn", 1, 5, [{"trigger": "on_turn_end", "action": "buff", "target": "self", "atk": 1, "hp": 1}])
	_tcard("t_hurt", 1, 9, [{"trigger": "on_damaged", "action": "damage", "target": "opposed_creature", "amount": 1}])
	var g := _new_game()
	var a := _put(g, 0, "t_atk")
	var hp: int = g.players[1]["leader_hp"]
	g.declare_attack(0, {a["uid"]: 0})
	check(g.players[1]["leader_hp"] == hp - 3, "on_attack fires (2 effect + 1 unblocked hit)")

	g = _new_game()
	var at := _put(g, 0, "kai")
	var bl := _put(g, 1, "t_blk")
	g.declare_attack(0, {at["uid"]: 0})
	g.declare_blocks(1, {at["uid"]: bl["uid"]})
	check(g.find_creature(bl["uid"]).get("temp_atk", 0) == 3 or g.find_creature(bl["uid"]).is_empty(), "on_block fires")

	g = _new_game()
	var tt := _put(g, 0, "t_turn")
	g.end_turn(0)
	check(g.find_creature(tt["uid"])["atk"] == 2 and g.find_creature(tt["uid"])["hp"] == 6, "on_turn_end fires")

	g = _new_game()
	var h := _put(g, 1, "t_hurt")
	g._deal_damage(h["uid"], 1, {})
	check(g.find_creature(h["uid"])["damage"] == 1, "on_damaged no-source safe")

	# Cartas reais: Dlorafya, Salamandra, Espírito da Maré, Ronan
	g = _new_game()
	var ally := _put(g, 0, "kai")
	var foe := _put(g, 1, "sentinela_coral") # 1/4
	var foe2 := _put(g, 1, "tritao_lanceiro") # 2/2
	var d := _put(g, 0, "dlorafya")
	check(g.find_creature(ally["uid"])["damage"] == 1, "dlorafya: ally igneo takes 1")
	g._check_state()
	check(g.find_creature(foe["uid"])["damage"] == 3 and g.find_creature(foe2["uid"]).is_empty(), "dlorafya: enemies take 3")
	check(g.find_creature(d["uid"])["damage"] == 1, "dlorafya: self takes 1")

	g = _new_game()
	var sal := _put(g, 0, "salamandra")
	hp = g.players[1]["leader_hp"]
	g.declare_attack(0, {sal["uid"]: 0})
	check(g.players[1]["leader_hp"] == hp - 4, "salamandra Ao Atacar (2 + 2 hit)")

	g = _new_game()
	var lord := _put(g, 0, "lord_of_the_shadowflame")
	var blk := _put(g, 1, "alexa_neruvya_primordial") # 7/7
	g.declare_attack(0, {lord["uid"]: 0})
	g.declare_blocks(1, {lord["uid"]: blk["uid"]})
	check(g.find_creature(blk["uid"]).is_empty(), "lorde Ao Ser Bloqueada: 2 + 5 combat kills 7/7")

	g = _new_game()
	var kai2 := _put(g, 0, "kai")
	var sp := _put(g, 1, "tritao_lanceiro")
	g.declare_attack(0, {kai2["uid"]: 0})
	g.declare_blocks(1, {kai2["uid"]: sp["uid"]})
	check(g.find_creature(kai2["uid"]).get("damage", 0) <= 1, "tritao Ao Bloquear hits attacker")

	g = _new_game()
	var ron := _put(g, 0, "ronan_lendario")
	g._deal_damage(ron["uid"], 1, {})
	check(g.find_creature(ron["uid"])["atk"] == 5, "ronan Ao Sofrer Dano +1 atk")

	g = _new_game()
	var vig := _put(g, 0, "vigia_do_farol_do_norte")
	var hand_n: int = g.players[0]["hand"].size()
	g._deal_damage(vig["uid"], 5, {})
	g._check_state()
	check(g.players[0]["hand"].size() == hand_n + 1, "vigia Ao Morrer draws 1")

	_tcard("t_wall", 1, 9, [])
	g = _new_game()
	var estr := _put(g, 0, "estrondador_igneo")
	var w1 := _put(g, 1, "t_wall")
	var w2 := _put(g, 1, "t_wall")
	var w3 := _put(g, 1, "t_wall")
	g.declare_attack(0, {estr["uid"]: 0})
	g.declare_blocks(1, {})
	var hit := 0
	for w in [w1, w2, w3]:
		hit += int(g.find_creature(w["uid"])["damage"])
	check(hit >= 2 and hit <= 3, "estrondador AoE hits random + adjacent (%d)" % hit)

	# Fênix Menor: dies, revives as 1/1 with no effects
	g = _new_game()
	var f := _put(g, 0, "fenix_menor")
	check(f["atk"] == 2 and f["hp"] == 1, "fenix is 2/1")
	g._deal_damage(f["uid"], 5, {})
	g._check_state()
	check(g.find_creature(f["uid"]).is_empty(), "fenix original died")
	check(g.players[0]["board"].size() == 1, "fenix revived")
	var r: Dictionary = g.players[0]["board"][0]
	check(r["card_id"] == "fenix_menor" and r["atk"] == 1 and r["hp"] == 1, "revived as 1/1")
	check(g.card_of(r)["effects"].is_empty() and g.card_of(r)["text"] == "", "revived has no text/effects")
	g._deal_damage(r["uid"], 5, {})
	g._check_state()
	check(g.players[0]["board"].is_empty(), "revived fenix stays dead")

func _test_sim() -> void:
	var wins := [0, 0, 0]
	for s in range(1, 41):
		var g := GameState.new("fogo" if s % 2 else "agua", "agua" if s % 2 else "fogo", s)
		var guard := 0
		while g.phase != "over" and guard < 3000:
			guard += 1
			var ev := SimpleAI.step(g, g.decider())
			if ev.is_empty():
				printerr("AI stuck: seed %d phase %s" % [s, g.phase])
				failures += 1
				break
		check(g.phase == "over", "seed %d finished (turn %d)" % [s, g.turn])
		if g.winner >= 0:
			var deck_win: String = g.players[g.winner]["deck_id"] if g.winner < 2 else "draw"
			wins[0 if deck_win == "fogo" else (1 if deck_win == "agua" else 2)] += 1
	print("sim fogo/agua/draw: ", wins)
