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
	check(CardDB.card(chosen["card_id"])["element"] == "water" and int(CardDB.card(chosen["card_id"])["cost"]) <= 2, "busca respeita filtro de Água e custo")
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
	var t := _put(g, 0, "sebastian_ignis") # 4/5 avassalar
	var s := _put(g, 1, "espirito_da_mare") # 1/2 escudo
	var hp: int = g.players[1]["leader_hp"]
	g.declare_attack(0, {t["uid"]: 0})
	g.declare_blocks(1, {t["uid"]: s["uid"]})
	check(not g.find_creature(s["uid"]).is_empty(), "shield absorbs hit")
	check(g.players[1]["leader_hp"] == hp - 2, "trample excess vs shield (%d)" % (hp - g.players[1]["leader_hp"]))

	g = _new_game()
	var f := _put(g, 0, "fenix_menor") # voar
	var w := _put(g, 1, "tritao_lanceiro") # longo alcance
	var x := _put(g, 1, "serpente_marinha")
	check(g.can_block(w, f) and not g.can_block(x, f), "voar/longo alcance")

	g = _new_game()
	var gk := _put(g, 0, "gorvakharr") # furtivo roubo de vida
	var y := _put(g, 1, "sentinela_coral") # vigia
	check(g.can_block(y, gk) and not g.can_block(x, gk), "furtivo/vigia")
	g.players[0]["leader_hp"] = 10
	g.declare_attack(0, {gk["uid"]: 0})
	g.declare_blocks(1, {})
	check(g.players[0]["leader_hp"] == 13, "lifesteal heals leader")

	g = _new_game()
	var k := _put(g, 0, "kael_drath_vulcano") # provocar
	var v := _put(g, 1, "serpente_marinha")
	g.declare_attack(0, {k["uid"]: v["uid"]})
	g.declare_blocks(1, {})
	check(g.find_creature(v["uid"]).is_empty(), "provoked creature forced to block")
	g.end_turn(0)
	check(g.find_creature(k["uid"])["damage"] == 0, "damage resets at end of turn")

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
