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
	_test_freeze()
	_test_combat()
	_test_triggers()
	_test_stack()
	_test_counter()
	_test_damage_window()
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
	var deck: Array = g.players[1]["deck"]
	var top: Array = deck.slice(deck.size() - 4)
	var deck_size: int = deck.size()
	var uid := g._uid()
	g._summon(1, "serpente_marinha", uid, false, 0)
	var evs: Array = g._flush()
	check(g.phase == "search" and g.pending_search.get("look", false), "serpente olha o topo do deck")
	check(g.pending_search["cards"].size() == 4, "olha 4 cartas")
	var mine: Dictionary = StateView.snapshot(g, 1)["pending_search"]
	var theirs: Dictionary = StateView.snapshot(g, 0)["pending_search"]
	check(mine["cards"][0]["card_id"] != "", "dono vê as cartas do topo")
	check(theirs["cards"].all(func(c): return c["card_id"] == ""), "oponente não vê as cartas do topo")
	var look_ev: Array = StateView.filter_events(evs, 0).filter(func(e): return e["type"] == "look_top")
	check(look_ev.size() == 1 and look_ev[0]["cards"].all(func(c): return c["card_id"] == ""), "evento do topo mascarado pro oponente")
	var chosen: Dictionary = top[1]
	var before_hand: int = g.players[1]["hand"].size()
	var picked: Array = g.choose_search(1, int(chosen["uid"]))
	check(g.phase == "main", "olhar termina após escolha")
	check(g.players[1]["hand"].size() == before_hand + 1 and g.players[1]["hand"][-1]["uid"] == chosen["uid"], "carta escolhida vai para a mão")
	deck = g.players[1]["deck"]
	check(deck.size() == deck_size - 1, "deck perde só a escolhida")
	var bottom_uids: Array = deck.slice(0, 3).map(func(c): return c["uid"])
	var rest: Array = top.filter(func(c): return c["uid"] != chosen["uid"]).map(func(c): return c["uid"])
	check(rest.all(func(u): return bottom_uids.has(u)), "as outras vão para o fundo do deck")
	check(_has_event(picked, "search_take"), "escolha emite evento de busca")

func _test_freeze() -> void:
	var g := _new_game()
	var atk := _put(g, 0, "kai")
	var f := _put(g, 1, "tritao_lanceiro")
	g._apply(0, {"action": "freeze", "target": "enemy_creature"}, f["uid"])
	check(g.is_frozen(f), "congelar marca a criatura")
	check(not g.can_block(f, atk), "congelada não bloqueia")
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and g.is_frozen(f) and not g.can_attack(f), "congelada não ataca no próximo turno do dono")
	_quiet(g)
	g.end_turn(1)
	check(not g.is_frozen(f), "descongela no fim do próximo turno do dono")
	var s := _put(g, 1, "tritao_lanceiro")
	s["spell_shield"] = true
	g._apply(0, {"action": "freeze", "target": "enemy_creature"}, s["uid"])
	check(not g.is_frozen(s) and not s["spell_shield"], "Escudo de Feitiço anula congelar")
	check(CardDB.has_essence(CardDB.card("sabrina"), "glacial") and CardDB.has_essence(CardDB.card("sabrina"), "aquatica"), "sabrina é aquática e glacial")

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
	_attack(g, {a["uid"]: 0})
	_block(g, {a["uid"]: b["uid"]})
	check(g.find_creature(b["uid"]).is_empty(), "first strike kills blocker")
	check(not g.find_creature(a["uid"]).is_empty(), "first striker survives")

	g = _new_game()
	var t := _put(g, 0, "kael_drath_vulcano") # 5/7 sobrepujança
	var s := _put(g, 1, "espirito_da_mare") # 1/2 escudo
	var hp: int = g.players[1]["leader_hp"]
	_attack(g, {t["uid"]: 0})
	_block(g, {t["uid"]: s["uid"]})
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
	_attack(g, {gk["uid"]: 0})
	_block(g, {})
	check(g.players[0]["leader_hp"] == 13, "lifesteal heals leader")

	g = _new_game()
	var k := _put(g, 0, "kael_drath_vulcano") # provocação
	var v := _put(g, 1, "serpente_marinha")
	_attack(g, {k["uid"]: v["uid"]})
	_block(g, {})
	check(g.find_creature(v["uid"]).is_empty(), "provoked creature forced to block")
	g.end_turn(0)
	check(g.find_creature(k["uid"])["damage"] == 0, "damage resets at end of turn")

## Declares an attack and lets every combat window pass.
func _attack(g: GameState, attacks: Dictionary) -> void:
	g.declare_attack(g.active, attacks)
	_pass_windows(g)

## Declares blocks and lets the damage window pass.
func _block(g: GameState, picks: Dictionary) -> void:
	g.declare_blocks(1, picks)
	_pass_windows(g)

func _pass_windows(g: GameState) -> void:
	for i in 20:
		if g.phase != "combat":
			return
		g.pass_priority(g.priority)

func _give(g: GameState, p: int, card_id: String) -> int:
	var uid := g._uid()
	g.players[p]["hand"].append({"uid": uid, "card_id": card_id})
	return uid

func _tspell(id: String, speed: String, effects: Array) -> void:
	CardDB.data()["cards"][id] = {"name": id, "type": "spell", "rarity": "common", "essence": "neutra", "cost": 0,
		"speed": speed, "art": "", "effects": effects, "text": "", "flavor": "", "tags": []}

func _has_event(events: Array, type: String) -> bool:
	for e in events:
		if e["type"] == type:
			return true
	return false

func _test_counter() -> void:
	# Negação de Neraqa: cost-3 spell is in base reach (no extra)
	var g := _new_game()
	g.players[0]["momentum"] = 5
	g.players[1]["momentum"] = 2
	var hp: int = g.players[1]["leader_hp"]
	var neg := _give(g, 1, "negacao_de_neraqa")
	g.play_card(0, _give(g, 0, "bola_de_fogo"), GameState.LEADER_UID[1])
	check(g.can_play(1, neg), "counter can answer a spell on the stack")
	var sid: int = g.stack[0]["sid"]
	g.play_card(1, neg, sid)
	check(g.players[1]["momentum"] == 0, "base counter costs 2")
	check(g.card_targets(0, CardDB.card("negacao_de_neraqa")).size() == 1, "only enemy items are counter targets")
	var ev := g.pass_priority(0)
	check(_has_event(ev, "countered") and g.stack.is_empty(), "counter removes the spell")
	check(g.players[1]["leader_hp"] == hp, "countered spell does nothing")
	var gy: Array = []
	for c in g.players[0]["graveyard"]: gy.append(c["card_id"])
	check(gy.has("bola_de_fogo"), "countered card goes to the graveyard")

	# cost-5 spell needs the +3 kicker
	_tspell("t_big", "lento", [{"trigger": "on_play", "action": "damage", "target": "enemy_leader", "amount": 3}])
	CardDB.data()["cards"]["t_big"]["cost"] = 5
	g = _new_game()
	g.players[0]["momentum"] = 5
	g.players[1]["momentum"] = 4
	neg = _give(g, 1, "negacao_de_neraqa")
	_give(g, 1, "labareda") # keeps priority open (an instant is castable)
	_put(g, 1, "tritao_lanceiro")
	g.play_card(0, _give(g, 0, "t_big"), 0)
	check(g.stack.size() == 1 and not g.can_play(1, neg), "cost 5 out of reach without 5 Momentum")
	g.players[1]["momentum"] = 5
	check(g.can_play(1, neg), "kicker reach with 5 Momentum")
	g.play_card(1, neg, g.stack[0]["sid"])
	check(g.players[1]["momentum"] == 0, "kicker charges +3")
	g.pass_priority(0)
	check(g.stack.is_empty() and g.players[1]["leader_hp"] == hp, "kicked counter stops the big spell")

func _test_stack() -> void:
	_tcard("t_wall2", 1, 2, [])
	_tspell("t_inst_hp", "instantaneo", [{"trigger": "on_play", "action": "buff", "target": "ally_creature", "hp": 3}])
	_tspell("t_inst_kill", "instantaneo", [{"trigger": "on_play", "action": "damage", "target": "any_creature", "amount": 9}])
	_tspell("t_fast", "rapido", [{"trigger": "on_play", "action": "damage", "target": "enemy_creature", "amount": 1}])

	# response resolves first (LIFO): +3 HP lands before the 2 damage
	var g := _new_game()
	g.players[0]["momentum"] = 5
	var foe := _put(g, 1, "t_wall2")
	var lab := _give(g, 0, "labareda")
	var inst := _give(g, 1, "t_inst_hp")
	g.play_card(0, lab, foe["uid"])
	check(g.stack.size() == 1 and g.priority == 1, "spell goes on the stack, opponent gets priority")
	check(g.find_creature(foe["uid"])["damage"] == 0, "spell waits on the stack")
	check(not g.can_play(1, _give(g, 1, "lanca_das_mares")), "lento cannot respond")
	g.play_card(1, inst, foe["uid"])
	check(g.stack.size() == 2 and g.priority == 0, "instant response stacks and passes priority back")
	g.pass_priority(0)
	var fc := g.find_creature(foe["uid"])
	check(g.stack.is_empty() and g.priority == 0 and g.phase == "main", "pass resolves the whole stack")
	check(not fc.is_empty() and fc["damage"] == 2, "LIFO: buff before damage")

	# target gone -> fizzle
	g = _new_game()
	g.players[0]["momentum"] = 5
	foe = _put(g, 1, "t_wall2")
	lab = _give(g, 0, "labareda")
	var kill := _give(g, 1, "t_inst_kill")
	g.play_card(0, lab, foe["uid"])
	g.play_card(1, kill, foe["uid"])
	check(_has_event(g.pass_priority(0), "fizzle"), "spell fizzles when its target is gone")

	# nobody can respond -> resolves at once
	g = _new_game()
	g.players[0]["momentum"] = 1
	foe = _put(g, 1, "t_wall2")
	lab = _give(g, 0, "labareda")
	g.play_card(0, lab, foe["uid"])
	check(g.stack.is_empty() and g.find_creature(foe["uid"]).is_empty(), "auto-pass when opponent has no response")

	# combat windows: attacker -> defender prepare -> attacker last -> blocks
	g = _new_game()
	g.players[0]["momentum"] = 1
	g.players[1]["momentum"] = 1 # Naelthos keeps a Rápida play, so the window doesn't auto-pass
	var kai := _put(g, 0, "kai")
	var wall := _put(g, 1, "t_wall")
	_give(g, 1, "t_fast")
	g.declare_attack(0, {kai["uid"]: 0})
	check(g.phase == "combat" and g.window == "attack" and g.priority == 0, "attacker window")
	g.pass_priority(0)
	check(g.window == "prepare" and g.priority == 1, "defender prepare window")
	check(not g.can_play(1, _give(g, 1, "lanca_das_mares")), "lento not allowed in combat")
	var fast: int = g.players[1]["hand"][-2]["uid"]
	g.play_card(1, fast, kai["uid"])
	check(g.priority == 0 and g.stack.size() == 1, "rapido cast in prepare window")
	g.pass_priority(0)
	check(g.find_creature(kai["uid"])["damage"] == 1 and g.priority == 1 and g.window == "prepare", "after resolving, window owner gets priority back")
	g.pass_priority(1)
	check(g.phase == "blocks", "then blocks")
	check(not g.can_play(0, _give(g, 0, "lanca_das_mares")), "no lento outside main")
	g.declare_blocks(1, {kai["uid"]: wall["uid"]})
	check(g.phase == "combat" and g.window == "damage" and g.priority == 0 and g.blocks.has(kai["uid"]), "damage window after blocks, attacker first")
	g.pass_priority(0)
	check(g.window == "damage" and g.priority == 1, "attacker passed: defender gets priority")
	g.pass_priority(1)
	check(g.phase == "main" and g.priority == 0 and g.blocks.is_empty(), "both passed: damage, back to main")

	# Escudo de Feitiço (Neraqa falls back to herself)
	g = _new_game()
	g.players[0]["momentum"] = 5
	var ner := _put(g, 1, "neraqa")
	check(g.has_kw(ner, "escudo_feitico"), "neraqa grants herself Escudo de Feitiço")
	g.play_card(0, _give(g, 0, "labareda"), ner["uid"])
	check(ner["damage"] == 0 and not g.has_kw(ner, "escudo_feitico"), "spell shield cancels the spell, then breaks")
	g.play_card(0, _give(g, 0, "labareda"), ner["uid"])
	check(ner["damage"] == 2, "second spell hits")
	var ally := _put(g, 1, "t_wall")
	g._apply(1, {"action": "buff", "keywords": ["escudo_feitico"]}, ally["uid"])
	g._apply(1, {"action": "buff", "atk": 1}, ally["uid"])
	check(g.has_kw(ally, "escudo_feitico") and ally["atk"] == 2, "own effects don't pop the spell shield")

	# Mar que Retorna: mark in the prepare window, block, survive -> draw
	g = _new_game()
	g.players[0]["momentum"] = 0
	g.players[1]["momentum"] = 1
	kai = _put(g, 0, "kai")
	wall = _put(g, 1, "t_wall")
	g.declare_attack(0, {kai["uid"]: 0})
	check(g.window == "prepare" and g.priority == 1, "naelthos (rapida) gets the prepare window")
	g.use_ability(1, wall["uid"])
	_pass_windows(g)
	check(wall.get("tide_mark", false), "tide mark resolved")
	var hn: int = g.players[1]["hand"].size()
	_block(g, {kai["uid"]: wall["uid"]})
	check(g.players[1]["hand"].size() == hn + 1 and not wall.has("tide_mark"), "marked creature survived damage -> draw 1")
	g._deal_damage(wall["uid"], 1, {})
	check(g.players[1]["hand"].size() == hn + 1, "mark draws only once")

func _test_damage_window() -> void:
	_tcard("t_a22", 2, 2, [])
	_tcard("t_tr22", 2, 2, [])
	CardDB.data()["cards"]["t_tr22"]["keywords"] = ["sobrepujanca"]
	_tcard("t_b12", 1, 2, [])
	_tspell("t_kill", "instantaneo", [{"trigger": "on_play", "action": "damage", "target": "any_creature", "amount": 9}])
	_tspell("t_pump", "rapido", [{"trigger": "on_play", "action": "buff", "target": "ally_creature", "atk": 3, "temp": true}])

	# post-block trick: pump after blocks kills the blocker, attacker survives
	var g := _new_game()
	_quiet(g)
	var at := _put(g, 0, "t_a22")
	var bl := _put(g, 1, "t_b12")
	var pump := _give(g, 0, "t_pump")
	_attack(g, {at["uid"]: 0})
	g.declare_blocks(1, {at["uid"]: bl["uid"]})
	check(g.window == "damage" and g.priority == 0, "attacker holds priority in damage window")
	g.play_card(0, pump, at["uid"])
	_pass_windows(g)
	check(g.find_creature(bl["uid"]).is_empty() and not g.find_creature(at["uid"]).is_empty(), "post-block pump kills the blocker, attacker survives")

	# blocker dies before damage -> attacker stays blocked
	g = _new_game()
	_quiet(g)
	at = _put(g, 0, "t_a22")
	bl = _put(g, 1, "t_b12")
	var hp0: int = g.players[1]["leader_hp"]
	var kill := _give(g, 0, "t_kill")
	_attack(g, {at["uid"]: 0})
	g.declare_blocks(1, {at["uid"]: bl["uid"]})
	g.play_card(0, kill, bl["uid"])
	_pass_windows(g)
	check(g.find_creature(bl["uid"]).is_empty() and g.players[1]["leader_hp"] == hp0, "blocks are final: no leader damage")
	check(g.phase == "main", "combat ends")

	# Sobrepujança with a dead blocker: everything tramples through
	g = _new_game()
	_quiet(g)
	at = _put(g, 0, "t_tr22")
	bl = _put(g, 1, "t_b12")
	hp0 = g.players[1]["leader_hp"]
	kill = _give(g, 0, "t_kill")
	_attack(g, {at["uid"]: 0})
	g.declare_blocks(1, {at["uid"]: bl["uid"]})
	g.play_card(0, kill, bl["uid"])
	_pass_windows(g)
	check(g.players[1]["leader_hp"] == hp0 - 2, "trample: dead blocker -> full damage to leader")

	# attacker dies in the damage window -> blocker deals nothing, defender acts after attacker passes
	g = _new_game()
	_quiet(g)
	at = _put(g, 0, "t_a22")
	bl = _put(g, 1, "t_b12")
	kill = _give(g, 1, "t_kill")
	_attack(g, {at["uid"]: 0})
	g.declare_blocks(1, {at["uid"]: bl["uid"]})
	check(g.priority == 1, "attacker with no play auto-passes to the defender")
	g.play_card(1, kill, at["uid"])
	check(g.phase == "main" and g.find_creature(at["uid"]).is_empty(), "attacker killed, combat over")
	check(g.find_creature(bl["uid"])["damage"] == 0, "blocker untouched")

## No momentum and no leader ability, so only test cards give plays.
func _quiet(g: GameState) -> void:
	for p in 2:
		g.players[p]["momentum"] = 0
		g.players[p]["ability_used"] = true

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
	_attack(g, {a["uid"]: 0})
	check(g.players[1]["leader_hp"] == hp - 3, "on_attack fires (2 effect + 1 unblocked hit)")

	g = _new_game()
	var at := _put(g, 0, "kai")
	var bl := _put(g, 1, "t_blk")
	_attack(g, {at["uid"]: 0})
	_block(g, {at["uid"]: bl["uid"]})
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
	_attack(g, {sal["uid"]: 0})
	check(g.players[1]["leader_hp"] == hp - 4, "salamandra Ao Atacar (2 + 2 hit)")

	g = _new_game()
	var lord := _put(g, 0, "lord_of_the_shadowflame")
	var blk := _put(g, 1, "alexa_neruvya_primordial") # 7/7
	_attack(g, {lord["uid"]: 0})
	_block(g, {lord["uid"]: blk["uid"]})
	check(g.find_creature(blk["uid"]).is_empty(), "lorde Ao Ser Bloqueada: 2 + 5 combat kills 7/7")

	g = _new_game()
	var kai2 := _put(g, 0, "kai")
	var sp := _put(g, 1, "tritao_lanceiro")
	_attack(g, {kai2["uid"]: 0})
	_block(g, {kai2["uid"]: sp["uid"]})
	check(g.find_creature(kai2["uid"]).get("damage", 0) <= 1, "tritao Ao Bloquear hits attacker")

	g = _new_game()
	var ron := _put(g, 0, "ronan")
	g._deal_damage(ron["uid"], 1, {})
	check(g.find_creature(ron["uid"])["atk"] == 5, "ronan Ao Sofrer Dano +1 atk")

	g = _new_game()
	var vig := _put(g, 0, "vigia_do_farol_do_norte")
	var hand_n: int = g.players[0]["hand"].size()
	g._deal_damage(vig["uid"], 5, {})
	g._check_state()
	check(g.players[0]["hand"].size() == hand_n + 1, "vigia Ao Morrer draws 1")

	g = _new_game()
	var h0: int = g.players[0]["hand"].size()
	var h1: int = g.players[1]["hand"].size()
	_put(g, 0, "engenheiro_louco")
	check(g.players[0]["hand"].size() == h0 + 2 and g.players[1]["hand"].size() == h1 + 2, "engenheiro louco: both draw 2")

	_tcard("t_wall", 1, 9, [])
	g = _new_game()
	var estr := _put(g, 0, "estrondador_igneo")
	var w1 := _put(g, 1, "t_wall")
	var w2 := _put(g, 1, "t_wall")
	var w3 := _put(g, 1, "t_wall")
	_attack(g, {estr["uid"]: 0})
	_block(g, {})
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
