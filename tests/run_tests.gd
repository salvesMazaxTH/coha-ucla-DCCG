extends SceneTree
## Headless: godot --headless --path . -s tests/run_tests.gd

var failures := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)

func _init() -> void:
	for d in DeckDB.ids():
		var errs := DeckDB.validate(d)
		check(errs.is_empty(), "deck %s: %s" % [d, errs])
		check(DeckDB.get_deck(d)["cards"].keys() == DeckDB.sorted_cards(DeckDB.get_deck(d)["cards"]).keys(), "deck %s: cartas fora de ordem de custo (rode tools/sort_decks.gd)" % d)
	_test_flavor()
	_test_off_essence()
	_test_death_order()
	_test_sacrifice_damage()
	_test_twin_bolts()
	_test_setup()
	_test_first_player()
	_test_concede()
	_test_search()
	_test_freeze()
	_test_constant()
	_test_obscura()
	_test_obscura_rules()
	_test_eletrica()
	_test_intimidacao()
	_test_play_slot()
	_test_ossuario()
	_test_yresa_fusion()
	_test_glacial()
	_test_glacial_combo()
	_test_deslizamento()
	_test_self_response()
	_test_custo_e_contagem()
	_test_ban()
	_test_combat()
	_test_provocacao()
	_test_persistent_damage()
	_test_triggers()
	_test_listeners()
	_test_stack()
	_test_summon_window()
	_test_subito()
	_test_combat_step()
	_test_leader_cycle()
	_test_enter_target()
	_test_legendary_retire()
	_test_fatigue()
	_test_counter()
	_test_fight()
	_test_conditional_counter()
	_test_reserve()
	_test_challenge_triggers()
	_test_strike_order()
	_test_overkill()
	_test_dud()
	_test_requiem()
	_test_rusco()
	_test_elite_limits()
	_test_armor()
	_test_adjacent_armor()
	_test_sim()
	for e in CardDB.errors():
		check(false, e)
	_test_card_validation()
	for e in preload("res://tests/golden_replay.gd").compare():
		check(false, e)
	print("tests done, failures: ", failures)
	quit(1 if failures > 0 else 0)

func _test_flavor() -> void:
	for id in CardDB.data()["cards"]:
		var f: Variant = CardDB.card(id).get("flavor", "")
		check(f is String or (f is Array and f.size() <= 3), "%s: flavor é texto ou lista de até 3" % id)
	var ronan := CardDB.card("ronan")
	var lines := CardDB.flavor_lines(ronan)
	check(lines.size() == 3 and CardDB.flavor_for(ronan) == lines[0], "ronan: frase principal fora da partida")
	CardDB.reroll_flavor()
	var first := CardDB.flavor_for(ronan, true)
	check(lines.has(first) and CardDB.flavor_for(ronan, true) == first, "ronan: frase fixa durante a partida")
	check(CardDB.flavor_for({"flavor": "x"}, true) == "x" and CardDB.flavor_for({}, true) == "", "flavor em texto simples ou ausente")

func _new_game() -> GameState:
	var g := GameState.new("fogo", "agua", 42)
	g.mulligan(0, [])
	g.mulligan(1, [])
	# the old stack tests expect priority to go straight to the opponent; _test_self_response turns it back on
	g.self_response_enabled = false
	return g

func _put(g: GameState, p: int, card_id: String, ready := true) -> Card:
	var uid := g._uid()
	g._summon(p, Card.new(uid, card_id, p), false, 0)
	g._flush()
	if g.phase == "search":
		var options: Array = g.pending_search["cards"]
		g.choose_search(p, int(options[0]["uid"]))
		g._flush()
	var c := g.find_unit(uid)
	# a Provocação put here skips the "enter tapped?" question: tests tap units by hand
	g.pending_tap.erase(uid)
	if ready:
		c.sick = false
	return c

func _test_search() -> void:
	var g := _new_game()
	var deck: Array = g.players[1]["deck"]
	var top: Array = deck.slice(deck.size() - 4)
	var deck_size: int = deck.size()
	var uid := g._uid()
	g._summon(1, Card.new(uid, "serpente_marinha", 1), false, 0)
	var evs: Array = g._flush()
	check(g.phase == "search" and g.pending_search.get("look", false), "serpente olha o topo do deck")
	check(g.pending_search["cards"].size() == 4, "olha 4 cartas")
	var mine: Dictionary = StateView.snapshot(g, 1)["pending_search"]
	var theirs: Dictionary = StateView.snapshot(g, 0)["pending_search"]
	check(mine["cards"][0]["card_id"] != "", "dono vê as cartas do topo")
	check(theirs["cards"].all(func(c): return c["card_id"] == ""), "oponente não vê as cartas do topo")
	var look_ev: Array = StateView.filter_events(evs, 0).filter(func(e): return e["type"] == "look_top")
	check(look_ev.size() == 1 and look_ev[0]["cards"].all(func(c): return c["card_id"] == ""), "evento do topo mascarado pro oponente")
	var chosen: Card = top[1]
	var before_hand: int = g.players[1]["hand"].size()
	var picked: Array = g.choose_search(1, int(chosen.uid))
	check(g.phase == "main", "olhar termina após escolha")
	check(g.players[1]["hand"].size() == before_hand + 1 and g.players[1]["hand"][-1].uid == chosen.uid, "carta escolhida vai para a mão")
	deck = g.players[1]["deck"]
	check(deck.size() == deck_size - 1, "deck perde só a escolhida")
	var bottom_uids: Array = deck.slice(0, 3).map(func(c): return c["uid"])
	var rest: Array = top.filter(func(c): return c["uid"] != chosen.uid).map(func(c): return c["uid"])
	check(rest.all(func(u): return bottom_uids.has(u)), "as outras vão para o fundo do deck")
	check(_has_event(picked, "search_take") and _has_event(picked, "look_bottom") and not _has_event(picked, "search_shuffle"), "serpente: fundo do deck, sem embaralhar")
	var taken: Array = StateView.filter_events(picked, 0).filter(func(e): return e["type"] == "search_take")
	check(taken.size() == 1 and taken[0]["card_id"] == chosen.card_id, "oponente vê a carta pega")

	# Oráculo das Marés: same look, but the rest stay in the deck and it is shuffled
	g = _new_game()
	deck = g.players[1]["deck"]
	deck_size = deck.size()
	g._summon(1, Card.new(g._uid(), "oraculo_das_mares", 1), false, 0)
	g._flush()
	check(g.phase == "search" and g.pending_search["cards"].size() == 4, "oráculo olha 4 cartas")
	var pick: int = int(g.pending_search["cards"][2]["uid"])
	var picked2: Array = g.choose_search(1, pick)
	check(g.players[1]["deck"].size() == deck_size - 1, "oráculo: deck perde só a escolhida")
	check(_has_event(picked2, "search_shuffle") and not _has_event(picked2, "look_bottom"), "oráculo embaralha o deck")
	check(StateView.filter_events(picked2, 0).any(func(e): return e["type"] == "search_take" and e["uid"] == pick and e["card_id"] != ""), "oráculo: oponente vê a carta pega")

func _test_constant() -> void:
	var g := _new_game()
	var jeff := _put(g, 0, "jeff")
	check(g.atk_of(jeff) == 3 and g.hp_left(jeff) == 3, "jeff sem cemitério é 3/3")
	g.players[0]["graveyard"].append(Card.new(g._uid(), "serpente_marinha", 0, "graveyard"))
	g.players[0]["graveyard"].append(Card.new(g._uid(), "gaivota_da_tempestade", 0, "graveyard"))
	g.players[0]["graveyard"].append(Card.new(g._uid(), "bola_de_fogo", 0, "graveyard"))
	g._check_state()
	check(g.atk_of(jeff) == 5 and g.hp_left(jeff) == 5, "jeff +1/+1 por unidade no cemitério (feitiço não conta)")
	g.players[1]["graveyard"].append(Card.new(g._uid(), "serpente_marinha", 1, "graveyard"))
	g._check_state()
	check(g.atk_of(jeff) == 5, "cemitério inimigo não conta")
	g.players[0]["graveyard"].pop_back()
	g.players[0]["graveyard"].pop_back()
	g._check_state()
	check(g.atk_of(jeff) == 4, "bônus encolhe quando o cemitério encolhe")
	jeff.damage = 1
	g.players[0]["graveyard"].clear()
	g._check_state()
	check(g.hp_left(jeff) == 2, "dano persiste ao perder o bônus")

func _obscura_game() -> GameState:
	var g := GameState.new("obscura_rapido", "fogo", 7)
	g.mulligan(0, [])
	g.mulligan(1, [])
	return g

## Kills a unit by damage and resolves the deaths (revives and triggers included).
func _test_sacrifice_damage() -> void:
	var g := _new_game()
	var jeff := _put(g, 0, "jeff")
	for i in 3:
		g.players[0]["graveyard"].append(Card.new(g._uid(), "esqueleto_guerreiro", 0, "graveyard"))
	g._check_state()
	var atk: int = g.atk_of(jeff)
	check(atk == 6, "jeff com 3 unidades no cemitério tem 6 de ataque")
	var foe := _put(g, 1, "serpente_marinha")
	var ally := _put(g, 0, "esqueleto_guerreiro")
	var spell := Card.new(g._uid(), "mordida_de_defunto", 0, "hand")
	g.players[0]["hand"].append(spell)
	g.players[0]["momentum"] = 10
	# the target of the damage can't be the sacrificed unit
	check(g.play_card(0, spell.uid, jeff.uid, jeff.uid).is_empty(), "não pode causar dano na própria unidade sacrificada")
	var lf: int = g.players[1]["leader_hp"]
	g.play_card(0, spell.uid, jeff.uid, GameState.LEADER_UID[1])
	g.pass_priority(1)
	g._flush()
	check(g.find_unit(jeff.uid) == null, "unidade foi sacrificada")
	check(g.players[1]["leader_hp"] == lf - atk, "dano no Líder = ataque total do sacrificado (%d)" % atk)
	# works against a unit, and against an ally
	var s2 := Card.new(g._uid(), "mordida_de_defunto", 0, "hand")
	g.players[0]["hand"].append(s2)
	g.play_card(0, s2.uid, ally.uid, foe.uid)
	g.pass_priority(1)
	g._flush()
	check(g.find_unit(ally.uid) == null and g.find_unit(foe.uid).damage == 1, "dano também acerta unidade (ataque 1 do esqueleto)")

func _test_death_order() -> void:
	# simultaneous deaths on both sides resolve active player first (APNAP)
	for first in 2:
		var g := _new_game()
		g.active = first
		var a := _put(g, 0, "vigia_do_farol_do_norte")
		var b := _put(g, 1, "vigia_do_farol_do_norte")
		a.damage = 1000
		b.damage = 1000
		g._check_state()
		var order: Array = []
		for e in g._flush():
			if e.get("type") == "death":
				order.append(int(e["player"]))
		check(order == [first, 1 - first], "mortes simultâneas: jogador da vez (%d) primeiro" % first)

func _test_off_essence() -> void:
	# fire deck: swap in off-essence (aquática) cards; neutral and own-essence cards don't count
	var base: Dictionary = DeckDB.get_deck("fogo")["cards"].duplicate()
	var leader: String = DeckDB.get_deck("fogo")["leader"]
	var victims: Array = base.keys().filter(func(k): return k != DeckDB.get_deck("fogo")["leader"] and CardDB.card(k).get("rarity", "") != "champion")
	var swapped := 0
	for k in victims:
		if swapped >= 12:
			break
		var take: int = mini(int(base[k]), 12 - swapped)
		base[k] -= take
		if base[k] == 0:
			base.erase(k)
		swapped += take
	base["afogar"] = 3
	base["tsunami"] = 3
	base["bencao_das_profundezas"] = 3
	base["espirito_da_mare"] = 3
	check(DeckDB.validate_cards(leader, base).filter(func(e): return "fora da essência" in e).is_empty(), "12 cartas de fora da essência são permitidas")
	var over: Dictionary = base.duplicate()
	over["tritao_lanceiro"] = 1
	over[over.keys().filter(func(k): return k != "afogar" and k != "tsunami" and k != "bencao_das_profundezas" and k != "espirito_da_mare" and k != leader)[0]] -= 1
	check(not DeckDB.validate_cards(leader, over).filter(func(e): return "máximo 12" in e).is_empty(), "13 cartas de fora da essência são ilegais")
	var champ: Dictionary = base.duplicate()
	champ["alexa_neruvya"] = 1 # a champion of another essence
	check(not DeckDB.validate_cards(leader, champ).filter(func(e): return "Campeão" in e).is_empty(), "Campeão de fora da essência é ilegal")

func _kill(g: GameState, c: Card) -> void:
	c.damage = 1000
	g._check_state()
	g._flush()

func _count(g: GameState, p: int, card_id: String) -> int:
	return g.players[p]["board"].filter(func(c: Card): return c.card_id == card_id).size()

func _test_obscura() -> void:
	var g := _obscura_game()
	check(g.players[0]["leader_id"] == "jeff", "deck obscura tem o Jeff como Líder")
	g.players[0]["passive_used"] = true # silence the Leader passive: it has its own test below
	var deck_before: int = g.players[0]["deck"].size()
	# Necrófago: hiena zumbi 0 custo 3/2, no mill any more
	var nec := _put(g, 0, "necrofago_espectral")
	check(g.players[0]["deck"].size() == deck_before and g.players[0]["graveyard"].is_empty(), "necrófago não manda mais o topo do deck ao cemitério")
	check(g.atk_of(nec) == 3 and g.hp_left(nec) == 2 and CardDB.card("necrofago_espectral")["species"] == ["morto_vivo", "fera"], "necrófago é uma hiena zumbi 3/2")
	# Replicador summons one copy of itself without the effect (no chain)
	var repl := _put(g, 0, "replicador_maldito")
	check(_count(g, 0, "replicador_maldito") == 1, "replicador não invoca ao entrar")
	_kill(g, repl)
	check(_count(g, 0, "replicador_maldito") == 1, "replicador invoca uma cópia ao morrer")
	var copies: Array = g.players[0]["board"].filter(func(c: Card): return c.card_id == "replicador_maldito" and g.card_of(c)["effects"].is_empty())
	check(copies.size() == 1, "a cópia não tem o efeito")
	# Revivente returns forever, as a new instance
	var first_uid: int = _put(g, 0, "revivente_eterno").uid
	for i in 3:
		var cur: Array = g.players[0]["board"].filter(func(c: Card): return c.card_id == "revivente_eterno")
		check(cur.size() == 1, "revivente está em campo (morte %d)" % i)
		_kill(g, cur[0])
	var back: Array = g.players[0]["board"].filter(func(c: Card): return c.card_id == "revivente_eterno")
	check(back.size() == 1 and back[0].uid != first_uid and g.atk_of(back[0]) == 3 and g.hp_left(back[0]) == 2, "revivente volta sempre, como nova instância")
	check(not g.players[0]["graveyard"].any(func(e): return e["card_id"] == "revivente_eterno"), "revivente em campo não fica no cemitério")
	# Fênix: back with -2/-2 of what it had; stops at 0
	var fen := _put(g, 0, "fenix_da_chama_profana")
	_kill(g, fen)
	var fb: Array = g.players[0]["board"].filter(func(c: Card): return c.card_id == "fenix_da_chama_profana")
	check(fb.size() == 1 and g.atk_of(fb[0]) == 2 and g.hp_left(fb[0]) == 2, "fênix 4/4 volta com -2/-2 (2/2)")
	_kill(g, fb[0])
	check(_count(g, 0, "fenix_da_chama_profana") == 0, "fênix com 0 de ataque ou vida não volta")
	check(g.players[0]["graveyard"].any(func(e): return e["card_id"] == "fenix_da_chama_profana"), "fênix acaba no cemitério")
	# Titânico: 5/6 Roubo de Vida, no Voo, mill 2
	var gy: int = g.players[0]["graveyard"].size()
	var dk: int = g.players[0]["deck"].size()
	var tit := _put(g, 0, "titanico_morcegalma")
	check(g.atk_of(tit) == 5 and g.hp_left(tit) == 6 and g.has_kw(tit, "roubo_de_vida") and not g.has_kw(tit, "voo"), "titânico 5/6 Roubo de Vida sem Voo")
	check(g.players[0]["deck"].size() == dk - 2 and g.players[0]["graveyard"].size() == gy + 2, "titânico mói 2")
	# Necromante revives a unit of cost <= 3 (seeded, so it does not depend on what the mill happened to hit)
	g.players[0]["graveyard"].append(Card.new(g._uid(), "esqueleto_guerreiro", 0, "graveyard"))
	gy = g.players[0]["graveyard"].size()
	_put(g, 0, "o_espiritomante")
	check(g.players[0]["graveyard"].size() == gy - 1, "necromante reviveu do cemitério")
	# the revived skeleton has Provocação and would trigger an "enter tapped?" question that blocks later plays: tests tap by hand
	g.pending_tap.clear()
	# Colheita de Almas: sacrifice -> 4 damage to the enemy leader
	var foe: int = g.players[1]["leader_hp"]
	var fodder := _put(g, 0, "esqueleto_guerreiro")
	var spell := _give(g, 0, "colheita_de_almas")
	g.players[0]["momentum"] = 10
	g.play_card(0, spell, fodder.uid)
	g._flush()
	check(g.players[1]["leader_hp"] == foe - 4 and g.find_unit(fodder.uid) == null, "colheita: sacrifica e causa 4")
	# Alexa Primordial: Ao Entrar heals every damaged ally fully
	var hurt := _put(g, 0, "esqueleto_guerreiro")
	hurt.damage = 1
	g.players[0]["momentum"] = 10
	var alx := _give(g, 0, "alexa_neruvya_primordial")
	g.play_card(0, alx, 0)
	g._flush()
	check(hurt.damage == 0, "alexa primordial cura todos os aliados")
	# Alexa transforms into the Primordial in place: 8 Momentum, off the stack, Ao Entrar fires
	var tf_hurt := _put(g, 0, "esqueleto_guerreiro")
	tf_hurt.damage = 1
	var tf := _put(g, 0, "alexa_neruvya")
	g.players[0]["momentum"] = 7
	g.players[0]["reserve"] = 0
	check(not g.can_transform(0, tf.uid), "transformar exige 8 de Momentum")
	g.players[0]["momentum"] = 8
	g.transform(0, tf.uid)
	g._flush()
	check(tf.card_id == "alexa_neruvya_primordial" and tf.atk == 7 and g.has_kw(tf, "sobrepujanca") and g.stack.is_empty(), "alexa vira a Primordial sem usar a pilha")
	check(tf_hurt.damage == 0 and g.players[0]["momentum"] == 0, "transformar paga 8 e dispara o Ao Entrar")
	check(not g.can_transform(0, tf.uid), "a Primordial não transforma de novo")
	# Yuki's Ao Ativar: goes on the stack (Rápido), +2/+2 temporary, once per turn
	var yk := _put(g, 0, "yuki")
	g.players[0]["momentum"] = 4
	g.players[0]["reserve"] = 0
	check(g.can_activate(0, yk.uid), "yuki pode ativar")
	g.auto_pass[1] = false # keep the response window open
	g.activate(0, yk.uid)
	g._flush()
	check(g.stack.size() == 1 and g.stack[0]["kind"] == "unit_ability" and g.priority == 1, "ao ativar vai para a pilha")
	g.pass_priority(1)
	g._flush()
	g.auto_pass[1] = true
	check(g.stack.is_empty() and g.atk_of(yk) == 4 and g.hp_left(yk) == 4 and g.players[0]["momentum"] == 1, "yuki ganha +2/+2 temporário")
	check(not g.can_activate(0, yk.uid), "ao ativar da yuki é 1x por turno")
	# the temporary Vida absorbs damage while it lasts; when it leaves, it takes that much damage with it
	var tg := _new_game()
	var temp_unit := _put(tg, 0, "yuki")
	temp_unit.temp_hp = 2
	temp_unit.temp_atk = 2
	temp_unit.damage = 3
	check(tg.hp_left(temp_unit) == 1, "vida temporária absorve dano")
	tg.end_turn(0)
	check(temp_unit.temp_hp == 0 and temp_unit.temp_atk == 0 and temp_unit.damage == 1 and tg.atk_of(temp_unit) == 2, "+2/+2 temporário some no fim do turno (fica só o dano além dele)")
	# Afogar: rápido, destroys any chosen unit, even one's own, ignoring Escudo
	var af_t := _put(g, 1, "jeff")
	af_t.shield = true
	var af_own := _put(g, 0, "esqueleto_guerreiro")
	g.players[0]["momentum"] = 12
	var af1 := _give(g, 0, "afogar")
	g.play_card(0, af1, af_t.uid)
	g._resolve_stack()
	var af2 := _give(g, 0, "afogar")
	g.play_card(0, af2, af_own.uid)
	g._resolve_stack()
	g._flush()
	check(g.find_unit(af_t.uid) == null and g.find_unit(af_own.uid) == null, "afogar destrói a unidade escolhida, inclusive a própria")
	var af_ind := _put(g, 1, "jeff")
	af_ind.keywords.append("indestrutivel")
	var af3 := _give(g, 0, "afogar")
	g.players[0]["momentum"] = 10
	g.play_card(0, af3, af_ind.uid)
	g._resolve_stack()
	g._flush()
	check(not g.find_unit(af_ind.uid) == null, "afogar não destrói Indestrutível")
	_kill(g, af_ind)
	# Equipment: an artifact attached under the unit; dies with it
	var holder := _put(g, 0, "rato_do_ossuario")
	var eqid := _give(g, 0, "manoplas_incandescentes")
	g.players[0]["momentum"] = 10
	var atk0: int = holder.atk
	g.play_card(0, eqid, holder.uid)
	g._resolve_stack()
	g._flush()
	check(CardDB.is_equipment(CardDB.card("manoplas_incandescentes")) and CardDB.is_artifact(CardDB.card("manoplas_incandescentes")), "equipamento é artefato")
	check(holder.equipment.card_id == "manoplas_incandescentes" and holder.atk == atk0 + 3, "equipamento anexado e buff aplicado")
	var gy0: int = g.players[0]["graveyard"].size()
	_kill(g, holder)
	var gy_ids: Array = g.players[0]["graveyard"].map(func(e): return e["card_id"])
	check(g.players[0]["graveyard"].size() == gy0 + 2 and gy_ids.has("manoplas_incandescentes"), "equipamento vai ao cemitério com a unidade")
	# Julgamento da Era Afogada: destroys every unit on both sides, whatever its size
	var jeff := _put(g, 1, "jeff")
	jeff.shield = true
	jeff.keywords.append("indestrutivel")
	var mine := _put(g, 0, "esqueleto_guerreiro")
	var jul := _give(g, 0, "julgamento_da_era_afogada")
	g.players[0]["momentum"] = 10
	g.play_card(0, jul, 0)
	g._resolve_stack()
	g._flush()
	check(not g.find_unit(jeff.uid) == null and g.find_unit(mine.uid) == null, "julgamento destrói todas as unidades, exceto Indestrutível")
	# damage is always 0 against Indestrutível and does not consume its shield
	var dmg_dealt: int = g._deal_damage(jeff.uid, 50, null)
	check(dmg_dealt == 0 and g.find_unit(jeff.uid).damage == 0 and g.find_unit(jeff.uid).shield, "dano contra Indestrutível é sempre 0")
	_kill(g, jeff)
	# Tributo ao Abismo: sacrifice -> mill 3 -> pick one of those 3 from the graveyard
	var ex_fodder := _put(g, 0, "esqueleto_guerreiro")
	var ex := _give(g, 0, "tributo_ao_abismo")
	g.players[0]["momentum"] = 10
	var ex_deck: int = g.players[0]["deck"].size()
	var ex_hand: int = g.players[0]["hand"].size()
	g.play_card(0, ex, ex_fodder.uid)
	g._flush()
	check(g.phase == "search" and g.pending_search.get("grave", false) and g.pending_search["cards"].size() == 3, "tributo oferece as 3 cartas moídas")
	check(g.players[0]["deck"].size() == ex_deck - 3, "tributo moeu 3")
	var ex_pick: Dictionary = g.pending_search["cards"][1]
	var ex_grave: int = g.players[0]["graveyard"].size()
	check(not g.choose_search(0, int(ex_pick["uid"])).is_empty(), "tributo: escolha aceita")
	check(g.phase != "search" and g.players[0]["graveyard"].size() == ex_grave - 1, "tributo: a carta sai do cemitério")
	check(g.players[0]["hand"].size() == ex_hand - 1 + 1 and g._hand_card(0, int(ex_pick["uid"])) != null, "tributo: a carta vai à mão")

func _test_fatigue() -> void:
	var g := _new_game()
	_quiet(g)
	g.players[0]["deck"].clear()
	var hp: int = g.players[0]["leader_hp"]
	var hits: Array = []
	for i in 3:
		g._draw(0, 1)
		hits.append(hp - g.players[0]["leader_hp"])
		hp = g.players[0]["leader_hp"]
	check(hits == [2, 4, 8] and g.fatigue_next(0) == 16, "fadiga dobra: 2, 4, 8, depois 16")

func _test_legendary_retire() -> void:
	var g := _new_game()
	_quiet(g)
	var l: Dictionary = g.players[0]["legendary"]
	g.players[0]["momentum"] = 10
	g.cast_legendary(0)
	if g.phase == "enter_target":
		g.choose_enter_target(0, 0)
	if g.summon_window:
		g.pass_priority(1)
	var u: Card = g.players[0]["board"].back()
	u.damage = 999
	g._check_state()
	check(l["in_zone"] and not l.get("retired", false), "encarnação: morte com custo pagável volta ao Santuário")
	g.players[0]["momentum"] = 10
	l["casts"] = 10
	l["in_zone"] = false
	g._summon(0, Card.new(g._uid(), l["card_id"], 0), true, 0)
	g.players[0]["board"].back().damage = 999
	var deck_n: int = g.players[0]["deck"].size()
	g._check_state()
	var bottom: Card = g.players[0]["deck"][0]
	check(l["retired"] and not l["in_zone"] and not g.can_cast_legendary(0), "encarnação: custo acima de 10 aposenta")
	check(g.players[0]["deck"].size() == deck_n + 1 and bottom.card_id == l["card_id"], "encarnação: vai para o fundo do deck")
	g.players[0]["deck"].erase(bottom)
	g.players[0]["hand"].append(bottom)
	g.players[0]["momentum"] = 10
	check(g.can_play(0, bottom.uid), "encarnação aposentada: jogável da mão pelo custo normal")

func _test_enter_target() -> void:
	var g := _new_game()
	_quiet(g)
	var foe := _put(g, 1, "esqueleto_guerreiro")
	g.players[0]["momentum"] = 10
	var vul := _give(g, 0, "vulnara")
	g.play_card(0, vul, foe.uid) # a target given with the play is ignored: it is picked on the board
	check(g.phase == "enter_target" and not g.find_unit(vul) == null and g.decider() == 0, "ao entrar: unidade entra antes de escolher o alvo")
	check(g.find_unit(foe.uid).damage == 0 and not g.summon_window, "ao entrar: nada resolve antes da escolha")
	check(g.choose_enter_target(0, vul).is_empty(), "ao entrar: alvo inválido recusado")
	g.choose_enter_target(0, foe.uid)
	check(g.phase == "main" and g.find_unit(foe.uid) == null, "ao entrar: dano no alvo escolhido")
	if g.summon_window:
		g.pass_priority(1)
	var foe2 := _put(g, 1, "esqueleto_guerreiro")
	var ner := _give(g, 0, "neraqa")
	g.play_card(0, ner)
	var neraqa_targets := g.valid_targets(0, g.pending_enter["spec"], ner)
	check(not neraqa_targets.has(ner) and neraqa_targets.has(vul), "neraqa: só outra unidade aliada, nunca ela mesma")
	g.choose_enter_target(0, 0)
	check(g.phase == "main" and not g.find_unit(ner).spell_shield, "ao entrar recusado: sem efeito")
	check(g.find_unit(foe2.uid).damage == 0, "ao entrar recusado: nada acontece")

func _test_leader_cycle() -> void:
	var g := _new_game() # fogo: Ronan's Pavio Curto is once per cycle
	_quiet(g)
	_put(g, 1, "esqueleto_guerreiro")
	g.players[0]["ability_used"] = false
	g.players[0]["momentum"] = 5
	g.players[1]["momentum"] = 5
	check(g.can_use_ability(0), "ronan: habilidade disponível no começo do ciclo")
	g.use_ability(0, g.players[1]["board"][0].uid)
	g.pass_priority(1)
	check(g.players[0]["ability_used"] and not g.can_use_ability(0), "ronan: usou no seu turno, bloqueada")
	g.end_turn(0)
	g.players[0]["momentum"] = 5
	check(g.players[0]["ability_used"] and not g.can_use_ability(0), "ronan: continua bloqueada no turno do oponente")
	g.end_turn(1)
	check(not g.players[0]["ability_used"], "ronan: recarrega no início do próprio turno")
	# not used on own turn: usable on the opponent's turn, then reloads anyway
	g.players[0]["momentum"] = 5
	g.end_turn(0)
	g.players[0]["momentum"] = 5
	g.players[1]["ability_used"] = true
	check(not g.players[0]["ability_used"], "ronan: sem uso no seu turno, ainda disponível no do oponente")

func _test_obscura_rules() -> void:
	# Diabrete: hits the enemy Leader when another ally dies (not for itself), Ao Morrer too
	var g := _obscura_game()
	g.players[0]["passive_used"] = true
	var dia := _put(g, 0, "diabrete_sombrio")
	check(g.atk_of(dia) == 2 and g.hp_left(dia) == 2 and CardDB.card("diabrete_sombrio")["cost"] == 2, "diabrete 2-drop 2/2")
	var fodder := _put(g, 0, "esqueleto_guerreiro")
	var hand: int = g.players[0]["hand"].size()
	var foe0: int = g.players[1]["leader_hp"]
	_kill(g, fodder)
	check(g.players[1]["leader_hp"] == foe0 - 1 and g.players[0]["hand"].size() == hand, "diabrete causa 1 ao Líder quando um aliado morre (e não compra)")
	var foe: int = g.players[1]["leader_hp"]
	_kill(g, dia)
	check(g.players[1]["leader_hp"] == foe - 1, "diabrete não ativa por si mesmo; Ao Morrer fere o Líder")
	# Aliado Morre fires on every death, even a Revivente that comes right back
	var gr := _obscura_game()
	gr.players[0]["passive_used"] = true
	_put(gr, 0, "diabrete_sombrio")
	var rv := _put(gr, 0, "revivente_eterno")
	var hr: int = gr.players[1]["leader_hp"]
	_kill(gr, rv)
	check(gr.players[1]["leader_hp"] == hr - 1 and _count(gr, 0, "revivente_eterno") == 1, "revivente que volta também ativa Aliado Morre")
	# Cientista da Morte summons a skeleton on Aliado Morre, but only when a non-token ally dies
	var sg := _obscura_game()
	sg.players[0]["passive_used"] = true
	_put(sg, 0, "cientista_da_morte")
	var rat := _put(sg, 0, "rato_do_ossuario")
	var n0: int = _count(sg, 0, "esqueleto_guerreiro")
	_kill(sg, rat)
	check(_count(sg, 0, "esqueleto_guerreiro") == n0 + 1, "cientista invoca um esqueleto quando um aliado comum morre")
	var token_skeleton := _put(sg, 0, "esqueleto_guerreiro")
	var n_token: int = _count(sg, 0, "esqueleto_guerreiro")
	_kill(sg, token_skeleton)
	check(_count(sg, 0, "esqueleto_guerreiro") == n_token - 1, "cientista ignora a morte de uma ficha (o esqueleto não gera outro)")
	var rat2 := _put(sg, 0, "rato_do_ossuario")
	var rat3 := _put(sg, 0, "rato_do_ossuario")
	var n1: int = _count(sg, 0, "esqueleto_guerreiro")
	_kill(sg, rat2)
	_kill(sg, rat3)
	check(_count(sg, 0, "esqueleto_guerreiro") == n1 + 2, "cientista invoca um esqueleto por aliado que morre (sem limite por turno)")
	# a death caused by combat damage triggers it too (no restriction)
	sg._combat_damage = true
	var rat4 := _put(sg, 0, "rato_do_ossuario")
	var n3: int = _count(sg, 0, "esqueleto_guerreiro")
	_kill(sg, rat4)
	sg._combat_damage = false
	check(_count(sg, 0, "esqueleto_guerreiro") == n3 + 1, "cientista também invoca quando o aliado morre em combate")
	# an enemy ally dying does not count
	var g2 := _obscura_game()
	g2.players[0]["passive_used"] = true
	_put(g2, 0, "diabrete_sombrio")
	var enemy := _put(g2, 1, "kai")
	var h2: int = g2.players[1]["leader_hp"]
	_kill(g2, enemy)
	check(g2.players[1]["leader_hp"] == h2, "morte de unidade inimiga não ativa Aliado Morre")

	# Jeff passive: once per turn, resets on the next turn
	var j := _obscura_game()
	var a1 := _put(j, 0, "esqueleto_guerreiro")
	var a2 := _put(j, 0, "esqueleto_guerreiro")
	var jh: int = j.players[0]["hand"].size()
	var jf: int = j.players[1]["leader_hp"]
	_kill(j, a1)
	check(j.players[1]["leader_hp"] == jf - 1 and j.players[0]["hand"].size() == jh and j.players[0]["passive_used"], "passiva do Jeff: 1 de dano, sem comprar")
	_kill(j, a2)
	check(j.players[1]["leader_hp"] == jf - 1, "passiva do Jeff só uma vez por turno")
	_quiet(j)
	j.end_turn(0)
	check(not j.players[0]["passive_used"], "passiva reseta no turno seguinte")
	check(not j.can_use_ability(0), "passiva não é ativável")
	# the dead Leader-owner's passive does not fire for the opponent's deaths
	# Ceifa only fires on the owner's own turn
	var jt := _obscura_game()
	jt.active = 1
	var at := _put(jt, 0, "esqueleto_guerreiro")
	var jtf: int = jt.players[1]["leader_hp"]
	_kill(jt, at)
	check(jt.players[1]["leader_hp"] == jtf and not jt.players[0]["passive_used"], "Ceifa não ativa no turno do oponente")
	var j2 := _obscura_game()
	var e1 := _put(j2, 1, "kai")
	var jf2: int = j2.players[1]["leader_hp"]
	_kill(j2, e1)
	check(j2.players[1]["leader_hp"] == jf2 and not j2.players[0]["passive_used"], "aliado inimigo morrendo não ativa a passiva")

	# Vagante Sombria: each card of yours sent to the graveyard makes her 1 cheaper wherever she is; indestructible
	var v := _obscura_game()
	var vag: Dictionary = CardDB.card("a_vagante_sombria")
	var vag_hand := v.find_card(_give(v, 0, "a_vagante_sombria"))
	var vag_deck := Card.new(v._uid(), "a_vagante_sombria", 0, "deck")
	v.players[0]["deck"].append(vag_deck)
	check(v.cost_of(0, vag, vag_hand) == 12, "vagante custa 12 com cemitério vazio")
	for i in 5:
		var dead := Card.new(v._uid(), "esqueleto_guerreiro", 0, "board")
		v.players[0]["graveyard"].append(dead)
		v._move(dead, "graveyard")
	v._check_state() # the listeners were queued by the moves; resolve them
	check(v.cost_of(0, vag, vag_hand) == 7, "vagante na mão custa 1 a menos por carta sua que foi ao cemitério")
	check(v.cost_of(0, vag, vag_deck) == 7, "vagante no deck também baixa o custo")
	for i in 20:
		var dead2 := Card.new(v._uid(), "cova_rasa", 0, "board")
		v.players[0]["graveyard"].append(dead2)
		v._move(dead2, "graveyard")
	v._check_state()
	check(v.cost_of(0, vag, vag_hand) == 0, "custo nunca fica abaixo de 0")
	var enemy_dead := Card.new(v._uid(), "esqueleto_guerreiro", 1, "board")
	v.players[1]["graveyard"].append(enemy_dead)
	v._move(enemy_dead, "graveyard")
	var fresh_copy := Card.new(v._uid(), "a_vagante_sombria", 1, "hand")
	check(v.cost_of(1, vag, fresh_copy) == 12, "carta do inimigo no cemitério não reduz")
	var late := _obscura_game()
	late.players[0]["graveyard"].append(Card.new(late._uid(), "esqueleto_guerreiro", 0, "graveyard"))
	check(late.cost_of(0, vag, late.find_card(_give(late, 0, "a_vagante_sombria"))) == 12, "cartas que já estavam no cemitério não contam")
	check(Card.from_dict(vag_hand.to_dict(), "hand", 0).cost_mod == vag_hand.cost_mod, "cost_mod sobrevive à rede")
	var vc := _put(v, 0, "a_vagante_sombria")
	v._apply_effect(1, {"action": "damage", "target": "any", "amount": 99}, vc.uid)
	check(not v.find_unit(vc.uid) == null and vc.damage == 0, "vagante ignora dano")
	var fresh := _obscura_game()
	fresh.players[0]["passive_used"] = true
	var vc2 := _put(fresh, 0, "a_vagante_sombria")
	var sc := _give(fresh, 0, "colheita_de_almas")
	fresh.players[0]["momentum"] = 10
	fresh.play_card(0, sc, vc2.uid)
	fresh._flush()
	check(fresh.find_unit(vc2.uid) == null, "sacrifício ainda mata a vagante")

	# Necrófago additional cost: sacrifice an ally you control (the AI pays with its weakest)
	var n := _obscura_game()
	n.players[0]["passive_used"] = true
	var nid := _give(n, 0, "necrofago_espectral")
	n.players[0]["momentum"] = 0
	check(not n.can_play(0, nid), "necrófago exige uma unidade para sacrificar")
	var weak := _put(n, 0, "rato_do_ossuario")
	var strong := _put(n, 0, "titanico_morcegalma")
	check(n.can_play(0, nid), "necrófago custa 0 com um aliado para sacrificar")
	check(n.card_spec(CardDB.card("necrofago_espectral")) == "ally_unit", "necrófago pede um alvo aliado")
	check(n.play_card(0, nid, 0).is_empty(), "necrófago sem alvo de sacrifício não entra")
	n.play_card(0, nid, weak.uid)
	n._flush()
	check(n.find_unit(weak.uid) == null and _count(n, 0, "necrofago_espectral") == 1 and not n.find_unit(strong.uid) == null, "necrófago sacrificou o escolhido e entrou")
	check(n.players[0]["graveyard"].any(func(e): return e["card_id"] == "rato_do_ossuario"), "o sacrificado foi ao cemitério")
	# full board: the sacrifice itself frees the slot
	var fb := _obscura_game()
	fb.players[0]["passive_used"] = true
	for i in GameState.BOARD_LIMIT:
		_put(fb, 0, "esqueleto_guerreiro")
	var fid := _give(fb, 0, "necrofago_espectral")
	check(fb.can_play(0, fid), "com o campo cheio o sacrifício libera a vaga")
	var ai_pick := SimpleAI._pick_sacrifice(fb, 0)
	fb.play_card(0, fid, ai_pick)
	fb._flush()
	check(fb.players[0]["board"].size() == GameState.BOARD_LIMIT and _count(fb, 0, "necrofago_espectral") == 1, "campo cheio: troca o sacrificado pelo necrófago")

## Armadura reduces every damage instance, stacks when given again, and the temporary part ends at the owner's next turn.
func _test_armor() -> void:
	var g := _new_game()
	var wall := _put(g, 0, "bastionario_de_basalto") # 1/5, no printed armor
	var armor_effect: Effect = EffectRegistry.parse_list([{"trigger": "on_play", "action": "buff", "target": "ally_unit", "armor": 1, "armor_temp": 2}])[0]
	armor_effect.apply(EffectContext.new(g, 0, ""), wall.uid)
	armor_effect.apply(EffectContext.new(g, 0, ""), wall.uid)
	check(wall.armor_total() == 6, "Armadura soma: 2 x (1 fixa + 2 temporária) = 6 (%d)" % wall.armor_total())
	check(g._deal_damage(wall.uid, 5, null) == 1 and wall.damage == 1, "dano menor ou igual à Armadura passa mesmo assim, como 1")
	check(g._deal_damage(wall.uid, 8, null) == 2 and wall.damage == 3, "dano acima da Armadura passa só o excedente")
	wall.shield = true
	g._deal_damage(wall.uid, 4, null)
	check(not wall.shield, "a Armadura nunca zera o dano: o golpe de 1 gasta o Escudo")
	g._start_turn(0, false)
	check(wall.armor_total() == 2, "a parte temporária some no início do próximo turno do dono (%d)" % wall.armor_total())

## Bastionário gives Armadura only to the allies standing right next to it on the board.
func _test_adjacent_armor() -> void:
	var g := _new_game()
	var left := _put(g, 0, "bastionario_de_basalto")
	var guard := _put(g, 0, "bastionario_de_basalto")
	var right := _put(g, 0, "escudeiro_de_cascalho")
	var far := _put(g, 0, "escudeiro_de_cascalho")
	check(g.armor_of(left) == 1 and g.armor_of(guard) == 1 and g.armor_of(right) == 1, "Armadura adjacente vem dos vizinhos, não da própria unidade")
	check(g.armor_of(far) == 0, "unidade longe do Bastionário não recebe")
	check(g._deal_damage(right.uid, 1, null) == 1, "dano 1 passa mesmo com a Armadura adjacente (mínimo 1)")

func _test_freeze() -> void:
	var g := _new_game()
	var atk := _put(g, 0, "kai")
	var f := _put(g, 1, "tritao_lanceiro")
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, f.uid)
	check(g.is_frozen(f), "congelar marca a unidade")
	check(g.atk_of(f) == 0 and f.rapidez_total() == f.rapidez, "congelada: só o ATK fica 0, a Rapidez continua a mesma")
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and not g.is_frozen(f), "congelamento dura só até o início do próximo turno (aplicado no meu turno, acaba quando o dono joga)")
	# frozen during the opponent's own turn: lasts until the next turn starts too
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, atk.uid)
	check(g.is_frozen(atk), "congelada no turno do oponente")
	_quiet(g)
	g.end_turn(1)
	check(g.active == 0 and not g.is_frozen(atk), "descongela quando o próximo turno começa")
	# exception: a unit frozen while still summoning sick never got to act, so the freeze also covers its owner's next turn
	var fresh := _put(g, 1, "tritao_lanceiro")
	fresh.sick = true
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, fresh.uid)
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and g.is_frozen(fresh) and not fresh.sick, "congelada com enjoo: continua congelada no turno do dono")
	_quiet(g)
	g.end_turn(1)
	check(g.active == 0 and not g.is_frozen(fresh), "congelada com enjoo: descongela no turno seguinte")
	g.end_turn(0)
	var s := _put(g, 1, "tritao_lanceiro")
	s.spell_shield = true
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, s.uid)
	check(not g.is_frozen(s) and not s.spell_shield, "Escudo de Feitiço anula congelar")
	# a frozen unit can still be challenged, but strikes back for 0
	_tcard("t_frz_hit", 1, 5, [])
	_tcard("t_frz_vic", 3, 5, [])
	g = _new_game()
	_quiet(g)
	var hitter := _put(g, 0, "t_frz_hit")
	var ice := _put(g, 1, "t_frz_vic")
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, ice.uid)
	ice.exhausted = true
	_hit(g, hitter, ice.uid)
	check(hitter.damage == 0 and ice.damage == 1, "congelada: desafiada, revida com 0 de dano")
	check(CardDB.has_essence(CardDB.card("sabrina"), "glacial") and CardDB.has_essence(CardDB.card("sabrina"), "aquatica"), "sabrina é aquática e glacial")

func _test_setup() -> void:
	var g := GameState.new("fogo", "agua", 1)
	check(g.players[0]["hand"].size() == GameState.START_HAND and g.players[1]["hand"].size() == GameState.START_HAND, "starting hands")
	check(g.players[0]["deck"].size() == DeckDB.DECK_SIZE - GameState.START_HAND, "legendary not in deck")
	g.mulligan(0, [g.players[0]["hand"][0].uid])
	g.mulligan(1, [])
	check(g.phase == "main" and g.active == 0 and g.players[0]["momentum"] == 1, "turn 1 momentum")
	check(g.players[0]["hand"].size() == GameState.START_HAND, "no draw turn 1")

func _test_first_player() -> void:
	var g := GameState.new("fogo", "agua", 1, 1)
	check(g.players[1]["hand"].size() == GameState.START_HAND and g.players[0]["hand"].size() == GameState.START_HAND, "first=1: mãos iniciais iguais")
	check(g.decider() == 1, "first=1: mulligan começa pelo jogador 1")
	g.mulligan(1, [])
	check(g.decider() == 0, "first=1: depois o jogador 0")
	g.mulligan(0, [])
	check(g.phase == "main" and g.active == 1 and g.turn == 1, "first=1: o jogador 1 abre o turno 1")
	check(g.players[1]["hand"].size() == GameState.START_HAND, "first=1: sem compra no turno 1")
	g.end_turn(1)
	check(g.players[0]["hand"].size() == GameState.START_HAND + 1, "first=1: o segundo jogador compra no turno dele")
	var seen := [[1, 1, 0]]
	g.players[1]["momentum"] = 0
	for t in 5:
		seen.append([g.active, g.players[g.active]["momentum"], g.players[g.active]["reserve"]])
		g.players[g.active]["momentum"] = 0 # spend everything: only the bonus reaches the Reserve
		g.players[g.active]["reserve"] = 0
		g.end_turn(g.active)
	check(seen == [[1, 1, 0], [0, 2, 1], [1, 2, 0], [0, 3, 1], [1, 3, 0], [0, 3, 0]], "segundo jogador: +1 Momentum e +1 de Reserva nos 2 primeiros turnos (%s)" % [seen])
	g = GameState.new("fogo", "agua", 1, 1)
	g.mulligan(1, [])
	g.mulligan(0, [])
	g.end_turn(1)
	g.players[0]["momentum"] = 1 # spent little on the first turn
	g.end_turn(0)
	g.end_turn(1)
	check(g.budget(0, true) == 5 and g.budget(0, false) == 3, "segundo jogador: feitiço de custo 5 no 2º turno se poupou")

func _test_concede() -> void:
	var g := _new_game()
	var ev := g.concede(1) # off-turn: it is player 0's turn
	check(g.phase == "over" and g.winner == 0, "conceder: o oponente vence, mesmo fora do turno")
	check(ev.any(func(e): return e["type"] == "concede" and e["player"] == 1) and ev.any(func(e): return e["type"] == "game_over" and e["winner"] == 0), "conceder: eventos concede + game_over")
	check(g.concede(0).is_empty() and g.winner == 0, "conceder: sem efeito depois do fim")
	g = _new_game()
	g.concede(0)
	check(g.winner == 1, "conceder: o jogador 0 desiste, o 1 vence")

func _test_combat() -> void:
	# only a tapped (exhausted) enemy can be challenged; the faster unit strikes first
	var g := _new_game()
	_quiet(g)
	var a := _put(g, 0, "kai") # 2/2, Rapidez 2
	var b := _put(g, 1, "tritao_lanceiro") # 2/2, Rapidez 1, Ao Ser Desafiada: 1 de dano ao atacante
	check(g.attack_targets(a) == [GameState.LEADER_UID[1]], "unidade pronta não pode ser desafiada: só o Líder é alvo")
	b.exhausted = true
	check(g.attack_targets(a).has(b.uid) and g.attack_targets(a).has(GameState.LEADER_UID[1]), "unidade exaurida pode ser desafiada")
	_hit(g, a, b.uid)
	check(g.find_unit(b.uid) == null, "Rapidez 2 mata o desafiado antes dele revidar")
	check(not g.find_unit(a.uid) == null and a.damage == 1 and a.exhausted, "o atacante exaure e só leva o 1 do Tritão")

	# equal Rapidez: both strike at the same time; hitting the Leader takes nothing back
	_tcard("t_c33", 3, 3, [])
	g = _new_game()
	_quiet(g)
	var left := _put(g, 0, "t_c33")
	var right := _put(g, 1, "t_c33")
	right.exhausted = true
	_hit(g, left, right.uid)
	check(g.find_unit(left.uid) == null and g.find_unit(right.uid) == null, "mesma Rapidez: os dois morrem")
	g = _new_game()
	_quiet(g)
	var face := _put(g, 0, "t_c33")
	_put(g, 1, "t_c33").exhausted = true
	var leader_hp: int = g.players[1]["leader_hp"]
	_hit(g, face)
	check(g.players[1]["leader_hp"] == leader_hp - 3 and face.damage == 0, "atacar o Líder: dano na face, nada volta")
	check(g.phase == "main" and g.players[0]["attacked"], "sem atacantes sobrando, o combate acaba sozinho")

	# Ímpeto: the turn it enters, the unit may only challenge; the Leader's face waits a turn
	g = _new_game()
	_quiet(g)
	var rushing := _put(g, 0, "ronan", false) # Ímpeto, still summoning sick
	check(g.attack_targets(rushing).is_empty(), "Ímpeto recém-chegado: sem unidade exaurida, não há o que atacar")
	var tapped_enemy := _put(g, 1, "t_c33")
	tapped_enemy.exhausted = true
	check(g.attack_targets(rushing) == [tapped_enemy.uid], "Ímpeto recém-chegado: só desafia, o Líder fica para o próximo turno")
	rushing.sick = false
	check(g.attack_targets(rushing).has(GameState.LEADER_UID[1]), "Ímpeto no turno seguinte: o Líder volta a ser alvo")

	# Rompante: the turn it enters, the unit may only hit the Leader (never challenges, ignores Provocação)
	g = _new_game()
	_quiet(g)
	var charging := _put(g, 0, "faisca_errante", false) # Rompante, still summoning sick
	var tapped_foe := _put(g, 1, "t_c33")
	tapped_foe.exhausted = true
	check(g.can_attack(charging), "Rompante recém-chegado pode atacar")
	check(g.attack_targets(charging) == [GameState.LEADER_UID[1]], "Rompante recém-chegado: só o Líder é alvo")
	check(not g.can_challenge(charging, tapped_foe), "Rompante recém-chegado não desafia")
	var taunt_foe := _put(g, 1, "esqueleto_guerreiro") # Provocação
	taunt_foe.exhausted = true
	check(g.attack_targets(charging) == [GameState.LEADER_UID[1]], "Rompante recém-chegado ignora a Provocação")
	var leader_before: int = g.players[1]["leader_hp"]
	_hit(g, charging, GameState.LEADER_UID[1])
	check(g.players[1]["leader_hp"] == leader_before - 1 and charging.exhausted, "Rompante bate no Líder e fica exausta")
	charging.sick = false
	charging.exhausted = false
	check(g.attack_targets(charging) == [taunt_foe.uid], "Rompante no turno seguinte: unidade normal, a Provocação obriga")

	# Sobrepujança against Escudo: the shield soaks the hit, the excess goes to the Leader
	g = _new_game()
	_quiet(g)
	var t := _put(g, 0, "kael_drath_vulcano") # 5/8 sobrepujança
	var s := _put(g, 1, "espirito_da_mare") # 1/2 escudo
	s.exhausted = true
	var hp: int = g.players[1]["leader_hp"]
	_hit(g, t, s.uid)
	check(not g.find_unit(s.uid) == null, "escudo absorve o golpe")
	check(g.players[1]["leader_hp"] == hp - 3, "sobrepujança: excesso contra escudo (%d)" % (hp - g.players[1]["leader_hp"]))

	# Voo: only Voo or Longo Alcance can challenge it
	g = _new_game()
	var fly := _put(g, 1, "fenix_menor") # voo
	fly.exhausted = true
	check(g.can_challenge(_put(g, 0, "tritao_lanceiro"), fly), "longo alcance desafia voo")
	check(g.can_challenge(_put(g, 0, "fenix_menor"), fly), "voo desafia voo")
	check(not g.can_challenge(_put(g, 0, "serpente_marinha"), fly), "sem voo/longo alcance não desafia voo")

	# Furtividade: only Furtividade or Vigilância can challenge it
	g = _new_game()
	var sneak := _put(g, 1, "gorvakharr") # furtividade
	sneak.exhausted = true
	check(g.can_challenge(_put(g, 0, "sentinela_coral"), sneak), "vigilância desafia furtividade")
	check(g.can_challenge(_put(g, 0, "gorvakharr"), sneak), "furtividade desafia furtividade")
	check(not g.can_challenge(_put(g, 0, "serpente_marinha"), sneak), "sem furtividade/vigilância não desafia furtividade")

	# Obsessão: the Revivente only hits the Leader
	var obsessed := _put(g, 0, "revivente_eterno")
	_put(g, 1, "esqueleto_guerreiro").exhausted = true
	check(g.attack_targets(obsessed) == [GameState.LEADER_UID[1]], "obsessão: só ataca o Líder")

	# Etérea: never challenged, not even with Provocação (so it forces nobody)
	_tcard("t_ghost", 1, 3, [])
	CardDB.data()["cards"]["t_ghost"]["keywords"] = ["eterea", "provocacao"]
	g = _new_game()
	var ghost := _put(g, 1, "t_ghost")
	ghost.exhausted = true
	var chaser := _put(g, 0, "serpente_marinha")
	check(not g.can_challenge(chaser, ghost) and g.attack_targets(chaser) == [GameState.LEADER_UID[1]], "etérea: ninguém desafia, a Provocação não obriga")

	# Inalcançável: enemies can't target it, but it can still be challenged
	_tcard("t_far", 1, 3, [])
	CardDB.data()["cards"]["t_far"]["keywords"] = ["inalcancavel"]
	var far := _put(g, 1, "t_far")
	far.exhausted = true
	check(not g.valid_targets(0, "enemy_unit").has(far.uid) and g.can_challenge(chaser, far), "inalcançável: sem alvo de inimigos, mas desafiável")

	# Roubo de Vida on the Leader's face
	g = _new_game()
	_quiet(g)
	var thief := _put(g, 0, "gorvakharr") # 4/3 roubo de vida
	g.players[0]["leader_hp"] = 10
	_hit(g, thief)
	check(g.players[0]["leader_hp"] == 14, "roubo de vida cura o Líder")

## Goes to combat (if still in the Main Phase) and lets the pre-combat window pass, so attacks can be declared.
func _open_attacks(g: GameState) -> void:
	if g.phase == "main":
		g.go_to_combat(g.active)
	for i in 20:
		if g.phase != "combat" or g.window != "pre_combat":
			return
		g.pass_priority(g.priority)

## One attack: `attacker` taps and hits `target_uid` (0 = the enemy Leader's face).
func _hit(g: GameState, attacker: Card, target_uid := 0) -> Array:
	_open_attacks(g)
	if target_uid == 0:
		target_uid = GameState.LEADER_UID[g.opponent(attacker.owner)]
	return g.attack_unit(g.active, attacker.uid, target_uid)

## Lets every combat priority pass (stack responses, the pre-combat window).
func _pass_windows(g: GameState) -> void:
	for i in 20:
		if g.phase != "combat":
			return
		g.pass_priority(g.priority)

func _test_provocacao() -> void:
	_tcard("t_taunt", 1, 6, [])
	CardDB.data()["cards"]["t_taunt"]["keywords"] = ["provocacao"]
	_tcard("t_taunt_fly", 1, 6, [])
	CardDB.data()["cards"]["t_taunt_fly"]["keywords"] = ["provocacao", "voo"]
	_tcard("t_other", 1, 6, [])

	# a tapped Provocação forces every attacker that can challenge it
	var g := _new_game()
	_quiet(g)
	var taunt := _put(g, 1, "t_taunt")
	var other := _put(g, 1, "t_other")
	other.exhausted = true
	var attacker := _put(g, 0, "serpente_marinha")
	check(g.attack_targets(attacker).has(GameState.LEADER_UID[1]), "provocação pronta não obriga ninguém")
	taunt.exhausted = true
	check(g.attack_targets(attacker) == [taunt.uid], "provocação exaurida: o único alvo é ela")
	check(_hit(g, attacker).is_empty() and g.attack_unit(0, attacker.uid, other.uid).is_empty(), "não dá para ir no Líder nem em outra unidade")
	check(not g.attack_unit(0, attacker.uid, taunt.uid).is_empty() and taunt.damage == 4, "desafiar a provocação funciona")

	# "se puder": an attacker that can't challenge it (Voo) is free
	g = _new_game()
	var flying_taunt := _put(g, 1, "t_taunt_fly")
	flying_taunt.exhausted = true
	var walker := _put(g, 0, "serpente_marinha")
	var flyer := _put(g, 0, "fenix_menor")
	check(g.attack_targets(walker) == [GameState.LEADER_UID[1]], "quem não pode desafiar a provocação fica livre")
	check(g.attack_targets(flyer) == [flying_taunt.uid], "quem pode é obrigado")

	# two Provocações: the attacker chooses
	g = _new_game()
	var first_taunt := _put(g, 1, "t_taunt")
	var second_taunt := _put(g, 1, "t_taunt")
	first_taunt.exhausted = true
	second_taunt.exhausted = true
	var targets := g.attack_targets(_put(g, 0, "serpente_marinha"))
	targets.sort()
	check(targets == [first_taunt.uid, second_taunt.uid], "várias provocações: escolhe qualquer uma")

	# played from hand: its controller chooses whether it enters tapped
	for tapped in [true, false]:
		g = _new_game()
		_quiet(g)
		g.players[0]["momentum"] = 1
		var hand_uid := _give(g, 0, "t_taunt")
		g.play_card(0, hand_uid)
		check(g.phase == "enter_tapped" and g.decider() == 0, "provocação da mão: pergunta se entra exaurida")
		check(g.end_turn(0).is_empty(), "nada acontece antes de escolher")
		g.choose_enter_tapped(0, tapped)
		check(g.phase == "main" and g.find_unit(hand_uid).exhausted == tapped, "entrou %s" % ("exaurida" if tapped else "pronta"))

	# entering from an effect asks too
	g = _new_game()
	_quiet(g)
	var uid := g._uid()
	g._summon(0, Card.new(uid, "t_taunt", 0), false, 0)
	g.stack_system().settle()
	check(g.phase == "enter_tapped", "provocação que entra por efeito também pergunta")
	g.choose_enter_tapped(0, true)
	check(g.find_unit(uid).exhausted and g.phase == "main", "entrou exaurida por efeito")

func _test_persistent_damage() -> void:
	_tcard("t_pd", 1, 5, [])
	# damage stays marked between turns
	var g := _new_game()
	_quiet(g)
	var unit := _put(g, 0, "t_pd")
	g._deal_damage(unit.uid, 3, null)
	g.end_turn(0)
	check(unit.damage == 3, "o dano fica marcado entre os turnos")

	# temporary Vida soaks the damage first, and leaves without killing
	g = _new_game()
	_quiet(g)
	var soaker := _put(g, 0, "t_pd")
	g._apply_effect(0, {"action": "buff", "target": "self", "hp": 3, "temp": true}, soaker.uid)
	g._deal_damage(soaker.uid, 2, null)
	var bigger := _put(g, 0, "t_pd")
	g._apply_effect(0, {"action": "buff", "target": "self", "hp": 3, "temp": true}, bigger.uid)
	g._deal_damage(bigger.uid, 7, null)
	g._check_state()
	check(not g.find_unit(bigger.uid) == null, "com Vida temporária, 7 de dano não mata uma 1/5+3")
	g.end_turn(0)
	check(soaker.damage == 0, "vida temporária absorveu o dano todo")
	check(not g.find_unit(bigger.uid) == null and bigger.damage == 4, "o buff acaba e só sobra o dano além dele (%d)" % bigger.damage)

	# Regeneração: all damage healed at the end of every turn
	g = _new_game()
	_quiet(g)
	var coral := _put(g, 1, "sentinela_coral")
	check(g.has_kw(coral, "regeneracao"), "sentinela de coral tem regeneração")
	g._deal_damage(coral.uid, 2, null)
	g.end_turn(0)
	check(coral.damage == 0, "regeneração cura no fim do turno (até no turno do oponente)")

func _give(g: GameState, p: int, card_id: String) -> int:
	var uid := g._uid()
	g.players[p]["hand"].append(Card.new(uid, card_id, p, "hand"))
	return uid

func _tspell(id: String, speed: String, effects: Array) -> void:
	CardDB.data()["cards"][id] = {"name": id, "type": "spell", "rarity": "common", "essence": "neutra", "cost": 0,
		"speed": speed, "art": "", "effects": effects, "text": "", "flavor": "", "tags": []}

func _has_event(events: Array, type: String) -> bool:
	for e in events:
		if e["type"] == type:
			return true
	return false

func _test_reserve() -> void:
	var g := _new_game()
	var p := g.active
	g.players[p]["momentum"] = 5
	g.end_turn(p)
	g.end_turn(g.active)
	check(g.active == p and g.players[p]["reserve"] == GameState.RESERVE_CAP, "reserva guarda o Momentum não gasto, até 2")
	g.players[p]["momentum"] = 0
	var unit := _give(g, p, "guerreiro_igneo")
	check(not g.can_play(p, unit), "reserva não paga unidades")
	g.players[p]["momentum"] = 1
	var hp: int = g.players[1 - p]["leader_hp"]
	var bola := _give(g, p, "bola_de_fogo")
	check(g.can_play(p, bola), "reserva + Momentum pagam feitiço")
	g.play_card(p, bola, GameState.LEADER_UID[1 - p])
	if not g.stack.is_empty(): # Naelthos' ability is instant, so its owner may answer
		g.pass_priority(g.priority)
	_pass_windows(g)
	check(g.players[p]["reserve"] == 0 and g.players[p]["momentum"] == 0, "feitiço gasta a reserva primeiro")
	check(g.players[1 - p]["leader_hp"] < hp, "feitiço pago com reserva resolve")
	var g2 := _new_game()
	var q := g2.active
	g2.players[q]["leader_id"] = "ronan"
	g2.players[q]["momentum"] = 0
	g2.players[q]["reserve"] = 2
	check(g2.can_use_ability(q), "reserva paga habilidade do líder")
	g2.use_ability(q, GameState.LEADER_UID[1 - q])
	check(g2.players[q]["reserve"] == 0, "habilidade gasta a reserva")

## "fight" (Arena Tectônica): ally and enemy hit each other at the same time, outside combat.
func _test_fight() -> void:
	_tcard("t_fighter", 4, 6, [])
	_tcard("t_target", 2, 3, [])
	var g := _new_game()
	g.players[0]["momentum"] = 9
	var ally := _put(g, 0, "t_fighter")
	var foe := _put(g, 1, "t_target")
	g.play_card(0, _give(g, 0, "arena_tectonica"), ally.uid, foe.uid)
	g.pass_priority(1)
	check(g.find_unit(foe.uid) == null, "luta: o inimigo toma o Ataque do aliado e morre")
	check(ally.damage == 2, "luta: o aliado toma o Ataque do inimigo ao mesmo tempo (%d)" % ally.damage)

	# Armadura reduces fight damage like any other damage
	g = _new_game()
	g.players[0]["momentum"] = 9
	var wall := _put(g, 0, "bastionario_de_basalto") # 1/5, Armadura adjacente só para vizinhos
	var big := _put(g, 1, "t_fighter")
	wall.armor += 3
	g.play_card(0, _give(g, 0, "arena_tectonica"), wall.uid, big.uid)
	g.pass_priority(1)
	check(wall.damage == 1 and big.damage == 1, "luta: Armadura reduz o dano (parede %d, inimigo %d)" % [wall.damage, big.damage])

	# Escudo de Feitiço on the enemy cancels the whole fight
	g = _new_game()
	g.players[0]["momentum"] = 9
	ally = _put(g, 0, "t_fighter")
	foe = _put(g, 1, "t_target")
	foe.spell_shield = true
	g.play_card(0, _give(g, 0, "arena_tectonica"), ally.uid, foe.uid)
	g.pass_priority(1)
	check(not foe.spell_shield and foe.damage == 0 and ally.damage == 0, "luta: Escudo de Feitiço cancela a luta inteira")

	# The AI only picks a fight its unit wins and survives
	g = _new_game()
	_put(g, 0, "t_target")
	_put(g, 1, "t_fighter")
	check(SimpleAI._pick_fight(g, 0).is_empty(), "IA não escolhe luta que perde")
	g = _new_game()
	_put(g, 0, "t_fighter")
	_put(g, 1, "t_target")
	check(SimpleAI._pick_fight(g, 0).size() == 2, "IA escolhe luta que ganha")

## Muralha Cara-de-Pedra: only answers a spell that targets one of the caster's opponent's units or Leader.
func _test_conditional_counter() -> void:
	_tspell("t_aoe", "lento", [{"trigger": "on_play", "action": "damage", "target": "all_enemy_units", "amount": 1}])
	var g := _new_game()
	g.players[0]["momentum"] = 9
	g.players[1]["momentum"] = 9
	var wall_card := CardDB.card("muralha_cara_de_pedra")
	g.play_card(0, _give(g, 0, "t_aoe"), 0)
	check(g.card_targets(1, wall_card).is_empty(), "Muralha não anula efeito em área")
	g = _new_game()
	g.players[0]["momentum"] = 9
	g.players[1]["momentum"] = 9
	g.play_card(0, _give(g, 0, "bola_de_fogo"), GameState.LEADER_UID[1])
	check(g.card_targets(1, wall_card).size() == 1, "Muralha anula feitiço que mira o Líder aliado")
	g = _new_game()
	g.players[0]["momentum"] = 9
	g.players[1]["momentum"] = 9
	var mine := _put(g, 1, "kai")
	g.play_card(0, _give(g, 0, "bola_de_fogo"), mine.uid)
	check(g.card_targets(1, wall_card).size() == 1, "Muralha anula feitiço que mira unidade aliada")
	g.play_card(1, _give(g, 1, "muralha_cara_de_pedra"), g.stack[0]["sid"])
	g.pass_priority(0)
	check(g.stack.is_empty() and mine.damage == 0, "Muralha anula o feitiço")

func _test_counter() -> void:
	# Negação de Neraqa: cost-3 spell is in base reach (no extra)
	var g := _new_game()
	g.players[0]["momentum"] = 6
	g.players[1]["momentum"] = 3
	var hp: int = g.players[1]["leader_hp"]
	var neg := _give(g, 1, "negacao_de_neraqa")
	g.play_card(0, _give(g, 0, "bola_de_fogo"), GameState.LEADER_UID[1])
	check(g.can_play(1, neg), "counter can answer a spell on the stack")
	var sid: int = g.stack[0]["sid"]
	g.play_card(1, neg, sid)
	check(g.players[1]["momentum"] == 0, "base counter costs 3")
	check(g.card_targets(0, CardDB.card("negacao_de_neraqa")).size() == 1, "only enemy items are counter targets")
	var ev := g.pass_priority(0)
	check(_has_event(ev, "countered") and g.stack.is_empty(), "counter removes the spell")
	check(g.players[1]["leader_hp"] == hp, "countered spell does nothing")
	var gy: Array = []
	for c in g.players[0]["graveyard"]: gy.append(c.card_id)
	check(gy.has("bola_de_fogo"), "countered card goes to the graveyard")

	# cost-5 spell needs the +2 kicker
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
	check(g.players[1]["momentum"] == 0, "kicker charges +2")
	g.pass_priority(0)
	check(g.stack.is_empty() and g.players[1]["leader_hp"] == hp, "kicked counter stops the big spell")

## Magic-style combat entry: attacking needs the explicit "IR PARA O COMBATE" step first.
func _test_combat_step() -> void:
	_tcard("t_cs", 1, 1, [])
	_tspell("t_cs_slow", "lento", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 1}])
	_tspell("t_cs_fast", "rapido", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 1}])
	var g := _new_game()
	_quiet(g)
	var attacker := _put(g, 0, "t_cs")
	_put(g, 0, "t_cs") # a second attacker, so the combat doesn't end after one attack
	_put(g, 1, "t_cs") # a target, so the spells are castable when allowed
	var slow := _give(g, 0, "t_cs_slow")
	var fast_mine := _give(g, 0, "t_cs_fast")
	var fast_theirs := _give(g, 1, "t_cs_fast")
	g.players[0]["momentum"] = 3
	g.players[1]["momentum"] = 3
	var face: int = GameState.LEADER_UID[1]
	check(g.attack_unit(0, attacker.uid, face).is_empty(), "sem atacar antes de ir para o combate")
	check(g.can_go_to_combat(0), "IR PARA O COMBATE aparece com um atacante pronto")
	g.go_to_combat(0)
	check(g.phase == "combat" and g.window == "pre_combat" and g.priority == 0, "o combate abre a preparação, atacante primeiro")
	check(g.can_play(0, fast_mine) and not g.can_play(0, slow), "preparação: só Rápido/Instantâneo")
	check(g.attack_unit(0, attacker.uid, face).is_empty() and g.end_turn(0).is_empty(), "sem ataques nem fim de turno na preparação")
	g.pass_priority(0)
	check(g.window == "pre_combat" and g.priority == 1 and g.can_play(1, fast_theirs), "o defensor também joga na preparação")
	g.pass_priority(1)
	check(g.window == "attacks" and g.priority == 0, "os dois passaram: começam os ataques")
	check(not g.can_play(0, fast_mine) and not g.can_play(1, fast_theirs), "ninguém joga cartas durante os ataques")
	check(not g.attack_unit(0, attacker.uid, face).is_empty() and g.window == "attacks", "um ataque por vez; o combate continua")
	check(g.attack_unit(0, attacker.uid, face).is_empty(), "quem já atacou (exaurido) não ataca de novo")
	g.end_combat(0)
	check(g.phase == "main" and g.players[0]["attacked"] and not g.can_go_to_combat(0), "ENCERRAR COMBATE: segunda fase principal, sem outro combate")
	check(g.can_play(0, slow), "lento volta na segunda fase principal")
	g.end_turn(0)
	check(g.phase == "main" and g.window == "", "o combate nunca passa para o próximo turno")

	# skipping combat from the Main Phase
	g = _new_game()
	_quiet(g)
	_put(g, 0, "t_cs")
	g.skip_combat(0)
	check(g.players[0]["attacked"] and not g.can_go_to_combat(0), "pular o combate gasta o ataque do turno")

	g = _new_game()
	_quiet(g)
	check(not g.can_go_to_combat(0) and g.go_to_combat(0).is_empty(), "sem atacante pronto: sem combate")

## Súbito (N): a unit summoned at Rápido speed by paying N; the summon goes on the stack and can be countered.
func _test_subito() -> void:
	_tcard("t_sub_trigger", 1, 1, [])
	_tcard("t_sub", 2, 2, [])
	CardDB.data()["cards"]["t_sub"]["subito"] = 3

	# in the opponent's summon window: pays 3, goes on the stack, enters when it resolves
	var g := _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 1
	g.players[1]["momentum"] = 3
	var sub := _give(g, 1, "t_sub")
	check(not g.can_play(1, sub), "Súbito: not playable while the opponent holds the turn and no window is open")
	g.play_card(0, _give(g, 0, "t_sub_trigger"), 0)
	check(g.can_play(1, sub) and g.subito_cost(1, CardDB.card("t_sub")) == 3, "Súbito: playable in the window for its Súbito cost")
	g.set_auto_pass(0, false)
	g.play_card(1, sub)
	check(g.stack.size() == 1 and g.stack[0]["kind"] == "subito" and g.players[1]["momentum"] == 0, "Súbito: paid and put on the stack")
	check(g.find_unit(sub) == null, "Súbito: the unit is not on the board before it resolves")
	g.pass_priority(0)
	check(g.stack.is_empty() and g.find_unit(sub) != null and g.find_unit(sub).owner == 1, "Súbito: the unit enters when it resolves")

	# the Reserva pays for Súbito too (drained first, like any ability)
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 1
	g.players[1]["momentum"] = 1
	g.players[1]["reserve"] = 2
	sub = _give(g, 1, "t_sub")
	g.play_card(0, _give(g, 0, "t_sub_trigger"), 0)
	check(g.can_play(1, sub), "Súbito: 1 Momentum + 2 Reserva are enough for Súbito (3)")
	g.play_card(1, sub)
	check(g.players[1]["reserve"] == 0 and g.players[1]["momentum"] == 0 and g.find_unit(sub) != null, "Súbito: the Reserva is spent first")

	# a counter answers it: the card goes to the graveyard
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 4
	g.players[1]["momentum"] = 3
	sub = _give(g, 1, "t_sub")
	var neg := _give(g, 0, "negacao_de_neraqa")
	g.play_card(0, _give(g, 0, "t_sub_trigger"), 0)
	g.play_card(1, sub)
	check(g.can_play(0, neg), "Súbito: the summon can be countered")
	g.play_card(0, neg, int(g.stack[0]["sid"]))
	g.pass_priority(1)
	var graveyard_ids: Array = []
	for c in g.players[1]["graveyard"]: graveyard_ids.append(c.card_id)
	check(g.find_unit(sub) == null and graveyard_ids.has("t_sub"), "Súbito: countered, the card goes to the graveyard")

	# in your own idle Main Phase it is played normally, at its normal cost, without the stack
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 1
	sub = _give(g, 0, "t_sub")
	check(not g.is_subito_play(0, CardDB.card("t_sub")) and g.can_play(0, sub), "Súbito: normal play in your own Main Phase")
	g.play_card(0, sub)
	check(g.find_unit(sub) != null and g.players[0]["momentum"] == 0, "Súbito: normal play costs the normal cost")

func _test_summon_window() -> void:
	_tcard("t_sw", 1, 1, [])
	_tspell("t_sw_fast", "rapido", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 1}])
	_tspell("t_sw_slow", "lento", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 1}])

	# opponent with a Rápido gets a window after a unit is played from hand
	var g := _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 3
	g.players[1]["momentum"] = 3
	var fast := _give(g, 1, "t_sw_fast")
	var u := _give(g, 0, "t_sw")
	g.play_card(0, u, 0)
	check(g.summon_window and g.priority == 1 and g.decider() == 1, "summon opens a response window for the opponent")
	check(not g.can_play(0, _give(g, 0, "t_sw")), "active player cannot act during the window")
	check(g.end_turn(0).is_empty() and g.go_to_combat(0).is_empty(), "no sorcery-speed actions during the window")
	check(g.can_play(1, fast), "opponent can cast Rápido in the window")
	g.pass_priority(1)
	check(not g.summon_window and g.priority == 0 and g.phase == "main", "pass closes the window, turn goes on")

	# casting in the window stacks the spell and gives priority back
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 3
	g.players[1]["momentum"] = 3
	g.set_auto_pass(0, false) # otherwise the stack resolves at once: player 0 has nothing to answer with
	fast = _give(g, 1, "t_sw_fast")
	var mine := _put(g, 0, "t_sw")
	g.play_card(0, _give(g, 0, "t_sw"), 0)
	g.play_card(1, fast, mine.uid)
	check(not g.summon_window and g.stack.size() == 1 and g.priority == 0, "spell cast in the window stacks, priority returns")
	g.pass_priority(0)
	check(g.stack.is_empty() and g.priority == 0 and g.phase == "main", "stack resolves back to the main phase")

	# a Lento spell is not castable in the window
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 3
	g.players[1]["momentum"] = 3
	var slow := _give(g, 1, "t_sw_slow")
	_put(g, 0, "t_sw")
	g.play_card(0, _give(g, 0, "t_sw"), 0)
	check(not g.summon_window and not g.can_play(1, slow) and g.priority == 0, "nothing to cast: window auto-passes")

	# auto-pass off: the window stays open even with no legal play
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 3
	g.set_auto_pass(1, false)
	g.play_card(0, _give(g, 0, "t_sw"), 0)
	check(g.summon_window and g.priority == 1, "auto-pass off keeps the window open")
	g.pass_priority(1)
	check(not g.summon_window and g.priority == 0, "manual pass closes it")
	g.play_card(0, _give(g, 0, "t_sw"), 0)
	g.set_auto_pass(1, true)
	check(not g.summon_window and g.priority == 0, "turning auto-pass on passes an unusable window")

	# the pre-combat window: with nothing to play it auto-passes; auto-pass off keeps it open
	for auto in [true, false]:
		g = _new_game()
		_quiet(g)
		_put(g, 0, "t_sw")
		g.set_auto_pass(0, auto)
		g.set_auto_pass(1, auto)
		g.go_to_combat(0)
		check((g.window == "attacks") == auto, "preparação sem jogadas: pula só com auto-pass (%s)" % auto)

	# the defender holding a Rápido gets the pre-combat window
	g = _new_game()
	_quiet(g)
	g.players[1]["momentum"] = 3
	var at2 := _put(g, 0, "t_sw")
	var fast2 := _give(g, 1, "t_sw_fast")
	g.go_to_combat(0)
	check(g.window == "pre_combat" and g.priority == 1 and g.can_play(1, fast2), "defensor com Rápido recebe a preparação")
	g.play_card(1, fast2, at2.uid)
	_pass_windows(g)
	check(g.find_unit(at2.uid) == null and g.phase == "main", "o atacante morreu na preparação: sem ataques, o combate acaba")

	# a summon whose on_play searches opens the window once the pick is made
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 9
	g.players[1]["momentum"] = 3
	var fast3 := _give(g, 1, "t_sw_fast")
	_put(g, 1, "t_sw") # no target for the Rápido otherwise
	g.play_card(0, _give(g, 0, "serpente_marinha"), 0)
	check(g.phase == "search" and not g.summon_window, "search comes first")
	g.choose_search(0, int(g.pending_search["cards"][0]["uid"]))
	check(g.phase == "main" and g.summon_window and g.priority == 1 and g.can_play(1, fast3), "search done: opponent gets the summon window")

func _test_stack() -> void:
	_tcard("t_wall2", 1, 2, [])
	_tspell("t_inst_hp", "instantaneo", [{"trigger": "on_play", "action": "buff", "target": "ally_unit", "hp": 3}])
	_tspell("t_inst_kill", "instantaneo", [{"trigger": "on_play", "action": "damage", "target": "any_unit", "amount": 9}])
	_tspell("t_fast", "rapido", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 1}])

	# response resolves first (LIFO): +3 HP lands before the 2 damage
	var g := _new_game()
	g.players[0]["momentum"] = 5
	var foe := _put(g, 1, "t_wall2")
	var lab := _give(g, 0, "labareda")
	var inst := _give(g, 1, "t_inst_hp")
	g.play_card(0, lab, foe.uid)
	check(g.stack.size() == 1 and g.priority == 1, "spell goes on the stack, opponent gets priority")
	check(g.find_unit(foe.uid).damage == 0, "spell waits on the stack")
	check(not g.can_play(1, _give(g, 1, "lanca_das_mares")), "lento cannot respond")
	g.play_card(1, inst, foe.uid)
	check(g.stack.size() == 2 and g.priority == 0, "instant response stacks and passes priority back")
	g.pass_priority(0)
	var fc := g.find_unit(foe.uid)
	check(g.stack.is_empty() and g.priority == 0 and g.phase == "main", "pass resolves the whole stack")
	check(not fc == null and fc.damage == 2, "LIFO: buff before damage")

	# target gone -> fizzle
	g = _new_game()
	g.players[0]["momentum"] = 5
	foe = _put(g, 1, "t_wall2")
	lab = _give(g, 0, "labareda")
	var kill := _give(g, 1, "t_inst_kill")
	g.play_card(0, lab, foe.uid)
	g.play_card(1, kill, foe.uid)
	check(_has_event(g.pass_priority(0), "fizzle"), "spell fizzles when its target is gone")

	# nobody can respond -> resolves at once
	g = _new_game()
	g.players[0]["momentum"] = 1
	foe = _put(g, 1, "t_wall2")
	lab = _give(g, 0, "labareda")
	g.play_card(0, lab, foe.uid)
	check(g.stack.is_empty() and g.find_unit(foe.uid) == null, "auto-pass when opponent has no response")

	# pre-combat window: a Rápido resolves, then both players must pass again in a row
	g = _new_game()
	g.players[0]["momentum"] = 2
	g.players[1]["momentum"] = 2
	var kai := _put(g, 0, "kai")
	_put(g, 1, "t_wall")
	var fast := _give(g, 1, "t_fast")
	g.go_to_combat(0)
	check(g.phase == "combat" and g.window == "pre_combat" and g.priority == 0, "preparação: atacante primeiro")
	if g.priority == 0:
		g.pass_priority(0)
	check(g.priority == 1, "depois o defensor")
	_tspell("t_slow", "lento", [])
	check(not g.can_play(1, _give(g, 1, "t_slow")), "lento não entra no combate")
	g.play_card(1, fast, kai.uid)
	check(g.priority == 0 and g.stack.size() == 1, "rápido vai para a pilha na preparação")
	g.pass_priority(0)
	check(g.find_unit(kai.uid).damage == 1 and g.window == "pre_combat", "resolveu; a preparação continua")
	_open_attacks(g)
	check(g.window == "attacks", "os dois passaram: ataques")
	check(not g.can_play(0, _give(g, 0, "lanca_das_mares")), "sem lento fora da fase principal")

	# Escudo de Feitiço (Neraqa only shields another ally; she is Inalcançável herself)
	g = _new_game()
	g.players[0]["momentum"] = 5
	var ner := _put(g, 1, "neraqa")
	check(not g.has_kw(ner, "escudo_feitico"), "neraqa never shields herself")
	check(not g.card_targets(0, CardDB.card("labareda")).has(ner.uid), "neraqa is Inalcançável: enemy spells can't target her")
	var shielded := _put(g, 1, "t_wall")
	g._apply_effect(1, {"action": "buff", "keywords": ["escudo_feitico"]}, shielded.uid)
	g.play_card(0, _give(g, 0, "labareda"), shielded.uid)
	check(shielded.damage == 0 and not g.has_kw(shielded, "escudo_feitico"), "spell shield cancels the spell, then breaks")
	g.play_card(0, _give(g, 0, "labareda"), shielded.uid)
	check(shielded.damage == 2, "second spell hits")
	var ally := _put(g, 1, "t_wall")
	g._apply_effect(1, {"action": "buff", "keywords": ["escudo_feitico"]}, ally.uid)
	g._apply_effect(1, {"action": "buff", "atk": 1}, ally.uid)
	check(g.has_kw(ally, "escudo_feitico") and ally.atk == 2, "own effects don't pop the spell shield")

	# Mar que Retorna (Naelthos): +1 vida máxima e atual, instantânea, respondível mas não anulável
	g = _new_game()
	g.players[0]["momentum"] = 2 # can respond, so the ability stays on the stack
	g.players[1]["momentum"] = 4
	check(CardDB.leader("naelthos")["ability"]["cost"] == 2 and CardDB.leader("ronan")["ability"]["cost"] == 2, "poderes de Ronan e Naelthos custam 2")
	var start_hp: int = g.players[1]["leader_max"]
	_put(g, 0, "kai")
	g.go_to_combat(0)
	if g.priority == 0:
		g.pass_priority(0)
	check(g.window == "pre_combat" and g.priority == 1, "naelthos (instantânea) recebe a preparação")
	var hp_before: int = g.players[1]["leader_hp"]
	g.use_ability(1)
	check(g.stack.size() == 1 and g.players[1]["leader_hp"] == hp_before, "poder vai para a pilha antes de resolver")
	check(g.valid_targets(0, "enemy_stack").is_empty(), "poder do Naelthos não pode ser alvo de anular")
	g._counter(0, g.stack[0]["sid"])
	check(g.stack.size() == 1, "_counter ignora poder não anulável")
	g._resolve_stack()
	check(g.players[1]["leader_hp"] == hp_before + 1 and g.players[1]["leader_max"] == start_hp + 1, "+1 vida atual e máxima")
	g.players[1]["leader_hp"] = g.players[1]["leader_max"]
	g._apply_effect(1, {"action": "leader_max_up", "amount": 1}, 0)
	check(g.players[1]["leader_hp"] == start_hp + 2 and g.players[1]["leader_max"] == start_hp + 2, "passa da vida inicial")
	g._apply_effect(1, {"action": "heal_leader", "amount": 5}, 0)
	check(g.players[1]["leader_hp"] == start_hp + 2, "cura normal respeita a nova vida máxima")

## A 3/3 challenges a tapped 3/3 with the given Rapidez: "A" = attacker alive, "B" = defender alive.
func _strike_result(attacker_rapidez: int, defender_rapidez: int, defender_frozen := false) -> String:
	_tcard("t_s_att", 3, 3, [])
	_tcard("t_s_def", 3, 3, [])
	CardDB.data()["cards"]["t_s_att"]["rapidez"] = attacker_rapidez
	CardDB.data()["cards"]["t_s_def"]["rapidez"] = defender_rapidez
	var g := _new_game()
	_quiet(g)
	var attacker := _put(g, 0, "t_s_att")
	var defender := _put(g, 1, "t_s_def")
	if defender_frozen:
		g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, defender.uid)
	defender.exhausted = true
	_hit(g, attacker, defender.uid)
	return ("A" if not g.find_unit(attacker.uid) == null else "-") + ("B" if not g.find_unit(defender.uid) == null else "-")

func _test_strike_order() -> void:
	check(_strike_result(1, 1) == "--", "rapidez igual: os dois morrem")
	check(_strike_result(2, 1) == "A-", "atacante mais rápido mata antes")
	check(_strike_result(1, 2) == "-B", "desafiado mais rápido mata antes")
	check(_strike_result(4, 3) == "A-", "rapidez 4 bate antes da 3")
	check(_strike_result(3, 3) == "--", "rapidez 3 contra 3: simultâneo")
	check(_strike_result(1, 4, true) == "A-", "congelada: ATK 0, nem revida (mesmo sendo mais rápida)")

## Triggers that resolve before the strikes can change the fight.
func _test_challenge_triggers() -> void:
	_tcard("t_a22", 2, 2, [])
	_tcard("t_ct_ping", 2, 2, [{"trigger": "on_challenge", "action": "damage", "target": "opposed_unit", "amount": 2}])
	CardDB.data()["cards"]["t_ct_ping"]["keywords"] = ["sobrepujanca"]
	_tcard("t_b12", 1, 2, [])

	# Ao Desafiar kills the challenged unit: it never strikes back
	var g := _new_game()
	_quiet(g)
	var lord := _put(g, 0, "lord_of_the_shadowflame") # 5/5, Ao Desafiar: 2 de dano
	var victim := _put(g, 1, "t_a22")
	victim.exhausted = true
	_hit(g, lord, victim.uid)
	check(g.find_unit(victim.uid) == null and lord.damage == 0, "morto pelo Ao Desafiar: não revida")

	# Sobrepujança with the target already dead: the full hit goes to the Leader
	g = _new_game()
	_quiet(g)
	var trampler := _put(g, 0, "t_ct_ping")
	var small := _put(g, 1, "t_b12")
	small.exhausted = true
	var hp0: int = g.players[1]["leader_hp"]
	_hit(g, trampler, small.uid)
	check(g.find_unit(small.uid) == null and g.players[1]["leader_hp"] == hp0 - 2, "sobrepujança: alvo já morto, dano todo no Líder")

	# the attacker dies to Ao Ser Desafiada: it deals nothing
	g = _new_game()
	_quiet(g)
	var fragile := _put(g, 0, "t_frz_hit") # 1/5
	fragile.damage = 4
	var spear := _put(g, 1, "tritao_lanceiro")
	spear.exhausted = true
	_hit(g, fragile, spear.uid)
	check(g.find_unit(fragile.uid) == null and spear.damage == 0, "atacante morto pelo Ao Ser Desafiada não causa dano")

## No momentum and no leader ability, so only test cards give plays.
func _quiet(g: GameState) -> void:
	for p in 2:
		g.players[p]["momentum"] = 0
		g.players[p]["ability_used"] = true

func _tcard(id: String, atk: int, hp: int, effects: Array) -> void:
	CardDB.data()["cards"][id] = {"name": id, "type": "unit", "rarity": "common", "essence": "neutra", "cost": 1,
		"atk": atk, "hp": hp, "keywords": [], "art": "", "effects": effects, "text": "", "flavor": "", "tags": []}

## "listen": a card reacting to an event from anywhere, written only in JSON.
## Fixture: when the enemy Leader falls below 12 life and I control 4+ units, 3 damage to all enemy units.
func _test_listeners() -> void:
	_tcard("t_cross", 1, 9, [{"listen": "leader_damaged", "scope": "enemy",
		"if": {"all": [{"crossed_below": {"who": "enemy", "value": 12}},
			{"compare": {"stat": "units", "who": "self", "op": ">=", "value": 4}}]},
		"action": "damage", "target": "all_enemy_units", "amount": 3}])
	_tcard("t_tough", 1, 9, [])
	var g := _new_game()
	_put(g, 0, "t_cross")
	for i in 3:
		_put(g, 0, "t_tough")
	var victim := _put(g, 1, "t_tough")
	g.players[1]["leader_hp"] = 14
	g._deal_damage(GameState.LEADER_UID[1], 1, null)
	g._check_state()
	check(g.find_unit(victim.uid).damage == 0, "listen: 13 life has not crossed 12 yet")
	g._deal_damage(GameState.LEADER_UID[1], 3, null)
	g._check_state()
	check(g.find_unit(victim.uid).damage == 3, "listen: crossing below 12 with 4 units hits all enemy units")
	g._deal_damage(GameState.LEADER_UID[1], 1, null)
	g._check_state()
	check(g.find_unit(victim.uid).damage == 3, "listen: fires once, not while the life stays below")

	g = _new_game()
	_put(g, 0, "t_cross")
	for i in 2:
		_put(g, 0, "t_tough") # only 3 units
	victim = _put(g, 1, "t_tough")
	g.players[1]["leader_hp"] = 14
	g._deal_damage(GameState.LEADER_UID[1], 3, null)
	check(g.find_unit(victim.uid).damage == 0, "listen: the if (4+ units) is not met with 3")

	g = _new_game()
	_put(g, 1, "t_cross") # the enemy owns it: scope "enemy" means the card's own Leader does not count
	for i in 3:
		_put(g, 1, "t_tough")
	victim = _put(g, 0, "t_tough")
	g.players[1]["leader_hp"] = 14
	g._deal_damage(GameState.LEADER_UID[1], 3, null)
	check(g.find_unit(victim.uid).damage == 0, "listen: scope enemy ignores its own Leader")

	# the other listenable events: unit_damaged, card_drawn, turn_started, turn_ended
	_tcard("t_pain", 1, 20, [{"listen": "unit_damaged", "scope": "self",
		"action": "buff", "target": "self", "atk": 1}])
	_tcard("t_reader", 1, 9, [{"listen": "card_drawn", "scope": "ally", "zones": "any",
		"action": "buff", "target": "self", "hp": 1}])
	_tcard("t_clock", 1, 9, [{"listen": "turn_ended", "scope": "ally",
		"action": "buff", "target": "self", "atk": 2}])
	g = _new_game()
	var hurt := _put(g, 0, "t_pain")
	g._deal_damage(hurt.uid, 2, null)
	g._check_state()
	check(g.find_unit(hurt.uid).atk == 2, "listen: unit_damaged fires for the unit hurt")
	g = _new_game()
	var reader := _put(g, 0, "t_reader")
	g._draw(0, 1)
	g._draw(1, 1)
	g._check_state()
	check(g.find_unit(reader.uid).hp == 10, "listen: card_drawn with scope ally counts only own draws")
	g = _new_game()
	var clock := _put(g, 0, "t_clock")
	g.end_turn(0)
	check(g.find_unit(clock.uid).atk == 3, "listen: turn_ended fires at the end of its owner's turn")

func _test_triggers() -> void:
	_tcard("t_atk", 1, 5, [{"trigger": "on_attack", "action": "damage", "target": "enemy_leader", "amount": 2}])
	_tcard("t_chd", 1, 5, [{"trigger": "on_challenged", "action": "buff", "target": "self", "atk": 3, "temp": true}])
	_tcard("t_turn", 1, 5, [{"trigger": "on_turn_end", "action": "buff", "target": "self", "atk": 1, "hp": 1}])
	_tcard("t_hurt", 1, 9, [{"trigger": "on_damaged", "action": "damage", "target": "opposed_unit", "amount": 1}])
	var g := _new_game()
	var a := _put(g, 0, "t_atk")
	var hp: int = g.players[1]["leader_hp"]
	_hit(g, a)
	check(g.players[1]["leader_hp"] == hp - 3, "Ao Atacar no Líder (2 do efeito + 1 do golpe)")

	g = _new_game()
	_quiet(g)
	var a2 := _put(g, 0, "t_atk")
	var wall_target := _put(g, 1, "t_turn")
	wall_target.exhausted = true
	hp = g.players[1]["leader_hp"]
	_hit(g, a2, wall_target.uid)
	check(g.players[1]["leader_hp"] == hp - 2, "Ao Atacar também dispara ao desafiar")

	g = _new_game()
	_quiet(g)
	var at := _put(g, 0, "kai")
	var challenged := _put(g, 1, "t_chd")
	challenged.exhausted = true
	_hit(g, at, challenged.uid)
	check(g.find_unit(challenged.uid).temp_atk == 3 and g.find_unit(at.uid) == null, "Ao Ser Desafiada: +3 ATK antes de revidar")

	g = _new_game()
	var tt := _put(g, 0, "t_turn")
	g.end_turn(0)
	check(g.find_unit(tt.uid).atk == 2 and g.find_unit(tt.uid).hp == 6, "on_turn_end fires")

	g = _new_game()
	var h := _put(g, 1, "t_hurt")
	g._deal_damage(h.uid, 1, null)
	check(g.find_unit(h.uid).damage == 1, "on_damaged no-source safe")

	# Cartas reais: Dlorafya, Salamandra, Espírito da Maré, Ronan
	g = _new_game()
	var ally := _put(g, 0, "kai")
	var foe := _put(g, 1, "sentinela_coral") # 1/4
	var foe2 := _put(g, 1, "tritao_lanceiro") # 2/2
	var d := _put(g, 0, "dlorafya")
	check(g.find_unit(ally.uid).damage == 1, "dlorafya: ally igneo takes 1")
	g._check_state()
	check(g.find_unit(foe.uid).damage == 3 and g.find_unit(foe2.uid) == null, "dlorafya: enemies take 3")
	check(g.find_unit(d.uid).damage == 1, "dlorafya: self takes 1")

	g = _new_game()
	var sal := _put(g, 0, "salamandra")
	hp = g.players[1]["leader_hp"]
	_hit(g, sal)
	check(g.players[1]["leader_hp"] == hp - 4, "salamandra Ao Atacar (2 + 2 hit)")

	g = _new_game()
	var lord := _put(g, 0, "lord_of_the_shadowflame")
	_tcard("t_big77", 7, 7, [])
	var big := _put(g, 1, "t_big77")
	big.exhausted = true
	_hit(g, lord, big.uid)
	check(g.find_unit(big.uid) == null, "lorde Ao Desafiar: 2 + 5 de combate matam uma 7/7")

	g = _new_game()
	var kai2 := _put(g, 0, "kai")
	var sp := _put(g, 1, "tritao_lanceiro")
	sp.exhausted = true
	_hit(g, kai2, sp.uid)
	check(g.find_unit(kai2.uid).damage == 1, "tritão Ao Ser Desafiada: 1 de dano no atacante")

	g = _new_game()
	_quiet(g)
	var tide := _put(g, 1, "espirito_da_mare")
	tide.exhausted = true
	g.players[1]["leader_hp"] = 10
	_hit(g, _put(g, 0, "serpente_marinha"), tide.uid)
	check(g.players[1]["leader_hp"] == 12, "espírito da maré Ao Ser Desafiada: cura 2 do Líder")

	g = _new_game()
	var ron := _put(g, 0, "ronan")
	g._deal_damage(ron.uid, 1, null)
	g._check_state()
	check(g.find_unit(ron.uid).atk == 5, "ronan Ao Sofrer Dano +1 atk")

	g = _new_game()
	var vig := _put(g, 0, "vigia_do_farol_do_norte")
	var hand_n: int = g.players[0]["hand"].size()
	g._deal_damage(vig.uid, 5, null)
	g._check_state()
	g._check_state()
	check(g.players[0]["hand"].size() == hand_n + 1, "vigia Ao Morrer draws 1")

	g = _new_game()
	var h0: int = g.players[0]["hand"].size()
	var h1: int = g.players[1]["hand"].size()
	_put(g, 0, "engenheiro_louco")
	check(g.players[0]["hand"].size() == h0 + 2 and g.players[1]["hand"].size() == h1 + 1, "engenheiro louco: você compra 2, o oponente compra 1")

	_tcard("t_wall", 1, 9, [])
	# Estrondador Ígneo: hits the middle of the enemy board (1 unit if odd, the 2 middle ones if even)
	for wall_count in [1, 2, 3, 4]:
		g = _new_game()
		var estr := _put(g, 0, "estrondador_igneo")
		var walls: Array = []
		for _i in wall_count:
			walls.append(_put(g, 1, "t_wall"))
		_quiet(g)
		_hit(g, estr)
		var damages: Array = []
		for w in walls:
			damages.append(int(g.find_unit(w["uid"]).damage))
		var expected: Array = {1: [2], 2: [2, 2], 3: [0, 2, 0], 4: [0, 2, 2, 0]}[wall_count]
		check(damages == expected, "estrondador hits the center of %d enemy units (%s)" % [wall_count, str(damages)])

	# Fênix Menor: dies, revives as 1/1 with no effects
	g = _new_game()
	var f := _put(g, 0, "fenix_menor")
	check(f.atk == 2 and f.hp == 1, "fenix is 2/1")
	g._deal_damage(f.uid, 5, null)
	g._check_state()
	check(g.find_unit(f.uid) == null, "fenix original died")
	check(g.players[0]["board"].size() == 1, "fenix revived")
	var r: Card = g.players[0]["board"][0]
	check(r.card_id == "fenix_menor" and r.atk == 1 and r.hp == 1, "revived as 1/1")
	check(g.card_of(r)["effects"].is_empty() and g.card_of(r)["text"] == "", "revived has no text/effects")
	g._deal_damage(r.uid, 5, null)
	g._check_state()
	check(g.players[0]["board"].is_empty(), "revived fenix stays dead")

func _test_elite_limits() -> void:
	var leader: String = DeckDB.get_deck("fogo")["leader"]
	var base: Dictionary = DeckDB.get_deck("fogo")["cards"].duplicate()
	check(DeckDB.validate_cards(leader, base).is_empty(), "fogo: legal com 20 campeões")
	# one more champion (swapping a common out) goes over the Campeões + Lendárias cap
	base["lord_of_the_shadowflame"] = 2
	base["salamandra"] = 2
	check(not DeckDB.validate_cards(leader, base).filter(func(e): return "Campeões + Lendárias" in e).is_empty(), "21 campeões é ilegal")
	# legendary default is 2 copies
	_tcard("t_lenda", 1, 1, [])
	CardDB.card("t_lenda")["rarity"] = "legendary"
	var lenda_deck: Dictionary = {"t_lenda": 3}
	check(not DeckDB.validate_cards(leader, lenda_deck).filter(func(e): return "mais de 2 cópias" in e).is_empty(), "lendária: 3 cópias é ilegal")
	lenda_deck["t_lenda"] = 2
	check(DeckDB.validate_cards(leader, lenda_deck).filter(func(e): return "t_lenda" in e).is_empty(), "lendária: 2 cópias é legal")

func _test_rusco() -> void:
	var r := CardDB.card("rusco")
	check(r["rarity"] == "champion" and r["essence"] == "neutra" and r["species"] == ["demihumano"], "rusco: champion neutro demihumano")
	check(int(r["cost"]) == 2 and int(r["atk"]) == 2 and int(r["hp"]) == 2 and r["keywords"] == ["escudo"], "rusco: 2/2 custo 2 com Escudo")
	# Única: max_copies 1
	var leader: String = DeckDB.get_deck("fogo")["leader"]
	var base: Dictionary = DeckDB.get_deck("fogo")["cards"].duplicate()
	base["rusco"] = 2
	check(not DeckDB.validate_cards(leader, base).filter(func(e): return "mais de 1 cópia" in e).is_empty(), "rusco: 2 cópias é ilegal")
	base["rusco"] = 1
	check(DeckDB.validate_cards(leader, base).filter(func(e): return "rusco" in e).is_empty(), "rusco: 1 cópia é legal")
	# deck effect: fetches himself at end of turn only after playing a card with cost/ATK/HP == 2
	_tcard("t_one", 1, 1, [])
	_tcard("t_two", 1, 1, [])
	CardDB.card("t_two")["cost"] = 2
	_tcard("t_atk2", 2, 1, [])
	for case in [["t_one", false], ["t_two", true], ["t_atk2", true], ["", false]]:
		var g := _new_game()
		var a := g.active
		g.players[a]["momentum"] = 10
		var ru := Card.new(g._uid(), "rusco", a, "deck")
		g.players[a]["deck"].push_front(ru)
		if case[0] != "":
			var h := Card.new(g._uid(), case[0], a, "hand")
			g.players[a]["hand"].append(h)
			g.play_card(a, h.uid)
		g.end_turn(a)
		var on_board: bool = g.players[a]["board"].any(func(u: Card): return u.uid == ru.uid)
		check(on_board == case[1] and g.players[a]["deck"].has(ru) != case[1] and not g.players[a]["hand"].has(ru), "rusco: carta '%s' -> entra em campo = %s" % [case[0], case[1]])
	# the 2 Momentum is paid like an ability: Reserva first, then Momentum
	for case in [[2, 0, true], [0, 2, true], [1, 1, true], [1, 0, false], [0, 1, false]]:
		var gp := _new_game()
		var pa := gp.active
		var rup := Card.new(gp._uid(), "rusco", pa, "deck")
		gp.players[pa]["deck"].push_front(rup)
		gp.players[pa]["played_two"] = true
		gp.players[pa]["momentum"] = case[0]
		gp.players[pa]["reserve"] = case[1]
		gp._finish_turn()
		var came: bool = gp.players[pa]["board"].any(func(u: Card): return u.uid == rup.uid)
		check(came == case[2] and gp.players[pa]["deck"].has(rup) != case[2], "rusco: Momentum %d + Reserva %d -> entra = %s" % [case[0], case[1], case[2]])
		if came:
			check(gp.players[pa]["momentum"] + gp.players[pa]["reserve"] == case[0] + case[1] - 2 and gp.players[pa]["reserve"] == maxi(0, case[1] - 2), "rusco: paga 2, Reserva primeiro")
	# a Rusco played from the hand does not come back by himself
	var g2 := _new_game()
	var b := g2.active
	g2.players[g2.active]["deck"] = g2.players[g2.active]["deck"].filter(func(c: Card): return c.card_id != "rusco") # the fogo deck has its own
	var ru2 := Card.new(g2._uid(), "rusco", b, "hand")
	g2.players[b]["hand"].append(ru2)
	g2.players[b]["momentum"] = 10
	g2.play_card(b, ru2.uid)
	g2.end_turn(b)
	check(g2.players[b]["hand"].filter(func(c: Card): return c.card_id == "rusco").is_empty(), "rusco: jogado da mão não volta sozinho")

## A typo in a card's JSON is reported on load instead of silently doing nothing.
func _test_card_validation() -> void:
	var errs := CardDB.errors()
	var before := errs.size()
	CardDB._validate_card("teste", {"name": "x", "type": "unit", "cost": 1, "text": "", "atk": 1, "hp": 1,
		"keywords": ["vooo"], "effects": [{"trigger": "on_entr", "action": "dammage", "target": "self"},
		{"trigger": "on_enter", "action": "damage", "target": "inimigo", "if": "sempre"}]})
	check(errs.size() - before == 5, "validação: keyword, trigger, action, target e if errados (%d)" % (errs.size() - before))
	errs.resize(before)

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

func _test_ban() -> void:
	# Overdraw is kept in hand; at the end of the owner's turn they choose what to ban
	var g := _new_game()
	var pl: Dictionary = g.players[0]
	while pl["hand"].size() < GameState.HAND_LIMIT:
		pl["hand"].append(Card.new(g._uid(), "kai", 0, "hand"))
	var gy: int = pl["graveyard"].size()
	g._draw(0, 2)
	g._flush()
	check(pl["hand"].size() == GameState.HAND_LIMIT + 2, "comprar com a mão cheia mantém as cartas na mão")
	_quiet(g)
	g.end_turn(0)
	check(g.phase == "discard", "mão acima de 10 pede banimento no fim do turno")
	var pick: Array = [pl["hand"][0].uid, pl["hand"][1].uid]
	check(g.discard(0, [pick[0]]).is_empty(), "banir menos que o necessário é recusado")
	var ev: Array = g.discard(0, pick)
	check(pl["hand"].size() == GameState.HAND_LIMIT and pl["banished"].size() == 2, "baniu até 10 cartas")
	check(pl["graveyard"].size() == gy, "carta banida não vai ao cemitério")
	check(ev.any(func(e): return e["type"] == "ban") and not ev.any(func(e): return e["type"] == "discard"), "evento ban")
	# the opponent never sees what was banished from the hand
	var snap: Dictionary = StateView.snapshot(g, 1)
	check(snap["players"][0]["banished"].all(func(c): return c["card_id"] == ""), "oponente não vê as cartas banidas da mão")
	check(StateView.snapshot(g, 0)["players"][0]["banished"].all(func(c): return c["card_id"] != ""), "o dono vê as próprias banidas")

func _eletrica_game() -> GameState:
	var g := GameState.new("eletrica_greedy", "fogo", 42)
	g.mulligan(0, [])
	g.mulligan(1, [])
	g.self_response_enabled = false # same reason as in _new_game
	_quiet(g)
	return g

func _test_eletrica() -> void:
	var g := _eletrica_game()
	var a := g.active
	var o := g.opponent(a)
	# Voltexz / Fulgurvoltz: cost drops with Momentum left unspent, with a floor
	var vx: Dictionary = CardDB.card("voltexz")
	var fg: Dictionary = CardDB.card("fulgurvoltz")
	check(g.cost_of(a, vx) == 15 and g.cost_of(a, fg) == 14, "eletrica: custos base 15 e 14")
	# only what leaks past the Reserva (2) at the start of the owner's next turn counts
	g.players[a]["momentum"] = 3
	g.players[a]["reserve"] = 1
	g.end_turn(a)
	g.players[o]["momentum"] = 0
	g.end_turn(o)
	check(g.players[a]["saved_momentum"] == 2 and g.players[a]["idle_turns"] == 1, "eletrica: conta só o que vazou da Reserva (1+3-2)")
	check(g.players[o]["saved_momentum"] == 0 and g.players[o]["idle_turns"] == 0, "eletrica: o que cabe na Reserva não conta")
	check(g.cost_of(a, vx) == 13 and g.cost_of(a, fg) == 11, "eletrica: custo cai com o que vazou")
	# spending on the opponent's turn reduces the savings (counted at the owner's next start)
	g = _eletrica_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 3
	g.players[a]["reserve"] = 2
	g.end_turn(a)
	g.players[a]["momentum"] = 1 # spent 2 during the opponent's turn
	g.end_turn(o)
	check(g.players[a]["saved_momentum"] == 1, "eletrica: gasto no turno do oponente reduz o que vaza")
	g = _eletrica_game()
	a = g.active
	g.players[a]["saved_momentum"] = 40
	g.players[a]["idle_turns"] = 40
	check(g.cost_of(a, vx) == 3 and g.cost_of(a, fg) == 5, "eletrica: pisos 3 e 5")
	# Gigante Elétrico: 9 base, 5 less when 3+ Momentum was left over from the previous turn
	var gg: Dictionary = CardDB.card("gigante_eletrico")
	g = _eletrica_game()
	a = g.active
	o = g.opponent(a)
	check(g.cost_of(a, gg) == 9 and int(gg["atk"]) == 7 and int(gg["hp"]) == 7, "gigante: 7/7 custando 9")
	check(gg["keywords"] == ["sobrepujanca"], "gigante: só Sobrepujança")
	g.players[a]["momentum"] = 3
	g.end_turn(a)
	g.end_turn(o)
	check(g.players[a]["unspent"] == 3 and g.cost_of(a, gg) == 4, "gigante: 3 de Momentum sobrando -> custa 4")
	g.players[a]["momentum"] = 2
	g.end_turn(a)
	g.end_turn(o)
	check(g.players[a]["unspent"] == 2 and g.cost_of(a, gg) == 9, "gigante: só 2 sobrando -> custo base")
	# Fulgurvoltz: no Ao Entrar; Ao Ativar (4, Lento) destroys every enemy unit, from the stack
	var fgd: Dictionary = CardDB.card("fulgurvoltz")
	check(fgd["activated"]["cost"] == 5 and fgd["activated"]["speed"] == "lento", "fulgurvoltz: Ao Ativar custa 5, Lento")
	g = _eletrica_game()
	a = g.active
	o = g.opponent(a)
	var fv := _put(g, a, "fulgurvoltz")
	var foe1 := _put(g, o, "tritao_lanceiro")
	var foe2 := _put(g, o, "serpente_marinha")
	check(not g.find_unit(foe1.uid) == null, "fulgurvoltz: entrar não destrói nada")
	g.players[a]["momentum"] = 3
	g.players[a]["reserve"] = 2 # the Reserva pays abilities, so 5 is reachable the turn it lands
	check(g.can_activate(a, fv.uid), "fulgurvoltz: ativável pagando com a Reserva")
	g.auto_pass[o] = false
	g.activate(a, fv.uid)
	g._flush()
	check(g.stack.size() == 1 and g.players[a]["momentum"] == 0 and g.players[a]["reserve"] == 0, "fulgurvoltz: vai para a pilha pagando 5")
	g.pass_priority(o)
	g._flush()
	g.auto_pass[o] = true
	check(g.find_unit(foe1.uid) == null and g.find_unit(foe2.uid) == null and not g.find_unit(fv.uid) == null, "fulgurvoltz: destrói todas as inimigas e fica")
	# the Ao Ativar exhausts it: no second use, no attack, and now it can be challenged; a new turn refreshes it
	check(fgd["activated"].get("exhaust", false) and fv.exhausted, "fulgurvoltz: ativar o exaure")
	g.players[a]["momentum"] = 5
	check(not g.can_activate(a, fv.uid) and not g.can_attack(fv), "fulgurvoltz: exausto não ativa de novo nem ataca")
	check(not g.can_challenge(_put(g, o, "tritao_lanceiro"), fv) and g.can_challenge(_put(g, o, "serpente_marinha"), fv), "fulgurvoltz exausto: desafiável, mas a Intimidação barra ATK 3 ou menos")
	var fv2 := _put(g, a, "fulgurvoltz")
	fv2.exhausted = true # e.g. it attacked this turn
	check(not g.can_activate(a, fv2.uid), "fulgurvoltz: quem atacou não ativa")
	# a counter on the stack stops it
	g = _eletrica_game()
	a = g.active
	o = g.opponent(a)
	fv = _put(g, a, "fulgurvoltz")
	foe1 = _put(g, o, "tritao_lanceiro")
	g.players[a]["momentum"] = 5
	g.players[o]["momentum"] = 5 # the ability now costs 5: above Negação's limit of 4, so it pays the +2
	var neg2 := _give(g, o, "negacao_de_neraqa")
	g.auto_pass[o] = false
	g.activate(a, fv.uid)
	g._flush()
	check(g.can_play(o, neg2), "fulgurvoltz: Negação de Neraqa pode responder")
	g.play_card(o, neg2, g.stack[0]["sid"])
	g.pass_priority(a)
	g._flush()
	check(g.stack.is_empty() and not g.find_unit(foe1.uid) == null, "fulgurvoltz: habilidade anulada, inimigas ficam")
	# Encarnação retirement uses the current cost (with reductions) plus the tax
	var l: Dictionary = g.players[a]["legendary"]
	l["casts"] = 1
	g.players[a]["saved_momentum"] = 0
	check(g.legendary_cost(a) == 17, "voltexz: sem redução, 2a conjuração custa 17")
	g.players[a]["saved_momentum"] = 8
	check(g.legendary_cost(a) == 9, "voltexz: custo atual 7 + taxa 2 = 9")
	l["in_zone"] = false
	g._legendary_leaves(a)
	check(l["in_zone"] and not l.get("retired", false), "voltexz: volta ao Santuário com custo atual 9")
	g.players[a]["saved_momentum"] = 6
	l["in_zone"] = false
	g._legendary_leaves(a)
	check(l.get("retired", false), "voltexz: custo atual 9 + taxa 2 = 11 (Momentum vazado 6) aposenta")
	# gain_momentum: now and at the next turn
	g = _eletrica_game()
	a = g.active
	o = g.opponent(a)
	_put(g, a, "espirito_carregado")
	check(g.players[a]["next_momentum"] == 1 and g.players[a]["momentum"] == 0, "espírito carregado: +1 só no próximo turno")
	g.players[a]["reserve"] = 0 # keep Sobrecarga (full Reserva) out of the count
	g.end_turn(a)
	g.end_turn(o)
	check(g.players[a]["momentum"] == g.players[a]["max_momentum"] + 1 and g.players[a]["next_momentum"] == 0, "espírito carregado: +1 Momentum no início do próximo turno")
	_put(g, a, "eletroad")
	g.players[a]["momentum"] = 0
	g.end_turn(a)
	g.players[a]["reserve"] = 0
	g.end_turn(o)
	check(g.players[a]["momentum"] == g.players[a]["max_momentum"] + 1, "eletroad: +1 Momentum no início do turno")
	var cu := _give(g, a, "carga_acumulada")
	g.players[a]["momentum"] = 5
	g.play_card(a, cu, 0)
	g._resolve_stack()
	g._flush()
	check(g.players[a]["momentum"] == 6, "carga acumulada: custa 1, dá +2")
	# Voltexz Ao Entrar: scaled buff capped at +5/+5, Ataque Rápido for her other units (not herself)
	g = _eletrica_game()
	a = g.active
	var ally := _put(g, a, "jack")
	g.players[a]["momentum"] = 9
	var vs := _put(g, a, "voltexz")
	check(atk_ok(g, ally, 3 + 5, 5 + 5) and ally.rapidez_total() == 2, "voltexz: aliados +5/+5 e Rapidez 2")
	check(g.atk_of(vs) == 8 and vs.rapidez_total() == 4, "voltexz: não bufa a si própria (ATK base 8, Rapidez 4 nativa)")
	g = _eletrica_game()
	a = g.active
	ally = _put(g, a, "jack")
	g.players[a]["momentum"] = 2
	_put(g, a, "faisca_viva")
	g._run_effect_dicts(a, CardDB.card("voltexz")["effects"], "on_enter", 0, 0)
	check(g.atk_of(ally) == 5 and g.players[a]["board"][0].hp == 7, "voltexz: +1/+1 por Momentum restante")
	g.players[a]["momentum"] = 0
	g._run_effect_dicts(a, CardDB.card("voltexz")["effects"], "on_enter", 0, 0)
	check(g.atk_of(ally) == 6 and g.players[a]["board"][0].hp == 8, "voltexz: sem Momentum sobrando, ainda dá +1/+1")
	# Jack: +1 attack at end of turn only with Momentum left
	g = _eletrica_game()
	a = g.active
	o = g.opponent(a)
	var jk := _put(g, a, "jack")
	g.end_turn(a)
	check(g.atk_of(jk) == 3, "jack: sem Momentum sobrando não cresce")
	g.end_turn(o)
	g.players[a]["momentum"] = 2
	g.end_turn(a)
	check(g.atk_of(jk) == 4, "jack: Momentum sobrando dá +1 permanente")
	# Layla: +1 attack per damage taken, up to +3
	# Layla: +1 attack per damage taken, no cap
	var ly := _put(g, g.active, "layla")
	for i in 5:
		g._deal_damage(ly.uid, 1, null)
		g._check_state()
		ly.damage = 0
	check(g.atk_of(ly) == 9, "layla: +1 por dano, sem limite (%d)" % g.atk_of(ly))
	# Victoria: Ao Atacar, +1 de Ataque permanente
	g = _new_game()
	_quiet(g)
	var vic := _put(g, 0, "victoria")
	_hit(g, vic)
	g._flush()
	check(g.atk_of(vic) == 3 and vic.atk == 3, "victoria: +1 de Ataque permanente ao atacar (%d)" % g.atk_of(vic))
	# Esquiva: the first combat damage per turn from a slower unit is avoided
	g = _eletrica_game()
	a = g.active
	o = g.opponent(a)
	var th := _put(g, o, "thorwells") # 5/6
	var weak := _put(g, a, "jack") # 2/4
	g._combat_damage = true
	g._deal_damage(th.uid, 2, weak)
	check(th.damage == 0, "esquiva: dano de combate de Rapidez menor é evitado")
	g._deal_damage(th.uid, 2, weak)
	check(th.damage == 2, "esquiva: só a primeira vez no turno")
	g._combat_damage = false
	g.turn += 1
	g._combat_damage = true
	var strong := _put(g, a, "voltexz") # Rapidez 4, same as Thorwells
	g._deal_damage(th.uid, 1, strong)
	check(th.damage == 3, "esquiva: Rapidez igual ou maior não é evitada")
	g.turn += 1
	g._deal_damage(th.uid, 1, weak)
	check(th.damage == 3, "esquiva: de novo no turno seguinte")
	g._combat_damage = false
	g.turn += 1
	g._deal_damage(th.uid, 1, weak)
	check(th.damage == 4, "esquiva: dano fora de combate não é evitado")
	# Esquiva with an override: Espírito Carregado dodges anything with Rapidez 1 or less
	var sp := _put(g, o, "espirito_carregado")
	var slow := _put(g, a, "jack")
	var fast := _put(g, a, "layla") # Rapidez 2
	g.turn += 1
	g._combat_damage = true
	g._deal_damage(sp.uid, 1, fast)
	check(sp.damage == 1, "esquiva (override): Rapidez 2 acerta")
	g._deal_damage(sp.uid, 1, slow)
	check(sp.damage == 1, "esquiva (override): Rapidez 1 é evitada, mesmo com ATK maior")
	g._combat_damage = false
	# Sobrecarga: Reserva cheia no início do turno dá +1 Momentum (só ao dono)
	g = _eletrica_game()
	a = g.active
	g.players[a]["momentum"] = 0
	g.players[a]["leaked"] = 0
	g._fire_leader_passive(a, "on_turn_start")
	g._check_state()
	check(g.players[a]["momentum"] == 0, "sobrecarga: nada vazou, nada volta")
	g.players[a]["leaked"] = 1
	g._fire_leader_passive(a, "on_turn_start")
	g._check_state()
	check(g.players[a]["momentum"] == 0, "sobrecarga: vazou 1, metade para baixo é 0")
	g.players[a]["leaked"] = 3
	g._fire_leader_passive(a, "on_turn_start")
	g._check_state()
	check(g.players[a]["momentum"] == 1, "sobrecarga: vazou 3, volta 1 (metade p/ baixo)")
	g.players[a]["momentum"] = 0
	g.players[a]["momentum"] = 0
	g.players[a]["leaked"] = 9
	g._fire_leader_passive(a, "on_turn_start")
	g._check_state()
	check(g.players[a]["momentum"] == 2, "sobrecarga: devolve no máximo 2")

func _test_intimidacao() -> void:
	_tcard("t_int", 4, 4, [])
	CardDB.data()["cards"]["t_int"]["keywords"] = ["intimidacao"]
	_tcard("t_low", 3, 3, [])
	_tcard("t_high", 4, 4, [])
	var g := _new_game()
	_quiet(g)
	var scary := _put(g, 1, "t_int")
	scary.exhausted = true
	var low := _put(g, 0, "t_low")
	var high := _put(g, 0, "t_high")
	check(not g.can_challenge(low, scary) and g.can_challenge(high, scary), "intimidação: ATK 3 ou menos não desafia, ATK 4 desafia")
	low.atk = 4
	check(g.can_challenge(low, scary), "intimidação: usa o ATK atual (buff libera o desafio)")
	high.atk = 3
	check(not g.can_challenge(high, scary), "intimidação: debuff tira o direito de desafiar")
	var plain := _put(g, 1, "t_high")
	plain.exhausted = true
	check(g.can_challenge(high, plain), "intimidação: não afeta quem não tem a palavra-chave")
	# Raiturus: Transformar (8) vira o Primordial 9/9 Intimidacao + Ímpeto sem usar a pilha
	g = _eletrica_game()
	var rt := _put(g, g.active, "tony_raiturus")
	g.players[g.active]["momentum"] = 8
	g.players[g.active]["reserve"] = 0
	check(g.can_transform(g.active, rt.uid), "raiturus pode transformar com 8")
	g.transform(g.active, rt.uid)
	g._flush()
	check(rt.card_id == "tony_raiturus_primordial" and g.atk_of(rt) == 9 and rt.hp == 9 and g.has_kw(rt, "intimidacao") and g.has_kw(rt, "impeto") and g.stack.is_empty(), "raiturus vira o Primordial 9/9 Intimidacao + Ímpeto")
	check(not g.can_transform(g.active, rt.uid), "o Primordial não transforma de novo")
	# a unit transformed the turn it entered is not summoning sick
	g = _eletrica_game()
	var fresh := _put(g, g.active, "tony_raiturus", false)
	g.players[g.active]["momentum"] = 8
	g.players[g.active]["reserve"] = 0
	check(fresh.sick, "raiturus recém-jogado está com enjoo de invocação")
	g.transform(g.active, fresh.uid)
	g._flush()
	check(not fresh.sick and g.can_attack(fresh), "unidade transformada não tem enjoo de invocação")

func atk_ok(g: GameState, c: Card, atk: int, hp: int) -> bool:
	return g.atk_of(c) == atk and c.hp == hp

func _test_custo_e_contagem() -> void:
	# cost reductions aren't "Constante" (they work off the board) and still apply
	for id in ["voltexz", "fulgurvoltz"]:
		for e in CardDB.card(id)["effects"]:
			if e["action"] == "cost_reduction":
				check(e.get("trigger", "") == "" and not str(CardDB.card(id)["text"]).begins_with("Constante"), "%s: redução de custo não é Constante" % id)
	var g := _new_game()
	var vag: Dictionary = CardDB.card("a_vagante_sombria")
	# Jeff: text counts own unit cards in the graveyard
	var jeff: Dictionary = CardDB.card("jeff")
	check(g.scale_count(0, jeff) == g.graveyard_units(0), "jeff: contagem do texto = unidades no cemitério")
	check(g.scale_count(0, vag) == -1, "carta sem escala: -1")

func _test_twin_bolts() -> void:
	_tcard("t_twin_big", 1, 9, [])
	var g := _new_game()
	g.players[0]["momentum"] = 10
	var foe := _put(g, 1, "t_twin_big")
	var foe2 := _put(g, 1, "t_twin_big")
	var leader: int = GameState.LEADER_UID[1]
	var lf: int = g.players[1]["leader_hp"]
	# units only: the enemy Leader is not a valid target for either bolt
	var s0 := _give(g, 0, "relampagos_gemeos")
	check(g.play_card(0, s0, leader, foe.uid).is_empty(), "Relâmpagos Gêmeos não mira o Líder (alvo 1)")
	check(g.play_card(0, s0, foe.uid, leader).is_empty(), "Relâmpagos Gêmeos não mira o Líder (alvo 2)")
	# same target twice
	var s1 := _give(g, 0, "relampagos_gemeos")
	check(not g.play_card(0, s1, foe.uid, foe.uid).is_empty(), "Relâmpagos Gêmeos aceita a mesma unidade duas vezes")
	_pass_windows(g)
	g.pass_priority(1)
	g._flush()
	check(g.find_unit(foe.uid).damage == 6, "mesma unidade recebe 3 + 3 de dano")
	# different targets
	g.players[0]["momentum"] = 10
	var s2 := _give(g, 0, "relampagos_gemeos")
	g.play_card(0, s2, foe.uid, foe2.uid)
	g.pass_priority(1)
	g._flush()
	check(g.find_unit(foe2.uid).damage == 3, "alvo 2 recebeu 3 de dano")
	check(g.find_unit(foe.uid) == null, "alvo 1 recebeu mais 3 de dano (6 + 3 = morreu)")
	check(g.players[1]["leader_hp"] == lf, "o Líder inimigo não leva dano")
	# the first target is gone before it resolves: the second bolt still lands
	g.players[0]["momentum"] = 10
	var s3 := _give(g, 0, "relampagos_gemeos")
	var victim := _put(g, 1, "esqueleto_guerreiro")
	var dmg2: int = g.find_unit(foe2.uid).damage
	g.play_card(0, s3, victim.uid, foe2.uid)
	victim.damage = 1000
	g._check_state()
	g.pass_priority(1)
	g._flush()
	check(g.find_unit(foe2.uid).damage == dmg2 + 3, "alvo 1 sumiu: o segundo raio ainda acerta")
	# Choque Direto: 2 to the face only; Choque de Largada: +1 ATK and Ímpeto until end of turn
	g.players[0]["momentum"] = 10
	var cd_card := CardDB.card("choque_direto")
	check(cd_card["cost"] == 2 and cd_card["speed"] == "rapido", "Choque Direto: custo 2, Rápido")
	var s4 := _give(g, 0, "choque_direto")
	var lf3: int = g.players[1]["leader_hp"]
	g.play_card(0, s4, 0, 0)
	g.pass_priority(1)
	g._flush()
	check(g.players[1]["leader_hp"] == lf3 - 2, "Choque Direto causa 2 ao Líder inimigo")
	var ally := _put(g, 0, "faisca_viva")
	var s5 := _give(g, 0, "choque_de_largada")
	check(CardDB.card("choque_de_largada")["speed"] == "instantaneo" and CardDB.card("choque_de_largada")["cost"] == 1, "Choque de Largada: custo 1, Instantâneo")
	g.play_card(0, s5, ally.uid, 0)
	g.pass_priority(1)
	g._flush()
	check(ally.atk_total() == 2 and g.has_kw(ally, "impeto"), "Choque de Largada: +1 ATK e Ímpeto")
	# Diabrete Elétrico: Ímpeto, and Ao Morrer gives next-turn Momentum
	var d := _put(g, 0, "diabrete_eletrico")
	check(CardDB.card("diabrete_eletrico")["cost"] <= 1 and "demonio" in CardDB.card("diabrete_eletrico")["species"], "Diabrete Elétrico é barato e Demônio")
	d.damage = 1000
	g._check_state()
	g._flush()
	check(g.find_unit(d.uid) == null, "Diabrete Elétrico morre")

func _test_overkill() -> void:
	# Leader at 3: the first attack kills it and the game ends in the middle of the combat
	_tcard("t_ok", 4, 3, [])
	var g := _new_game()
	_quiet(g)
	g.players[1]["leader_hp"] = 3
	var a := _put(g, 0, "t_ok")
	var b := _put(g, 0, "t_ok")
	_hit(g, a)
	check(g.phase == "over" and g.winner == 0, "o jogo acaba no meio do combate")
	check(g.attack_unit(0, b.uid, GameState.LEADER_UID[1]).is_empty() and g.players[1]["leader_hp"] == 3 - 4, "depois do fim, nenhum ataque a mais")
	# runaway chain: past EVENT_CAP no trigger resolves
	var g2 := _new_game()
	g2._events.resize(GameState.EVENT_CAP)
	check(g2._chain_stopped(), "cadeia: acima do limite de eventos os gatilhos param")

## Réquiem: a spell in the graveyard can be cast for its cost + 2, then it is banished (resolved, fizzled or countered).
func _test_requiem() -> void:
	var g := _new_game()
	g.auto_pass = [false, false] # keep the stack open so the test can look at it
	var p := g.active
	var cova := Card.new(g._uid(), "cova_rasa", p, "graveyard")
	g.players[p]["graveyard"].append(cova)
	g.players[p]["momentum"] = 3
	check(g.cost_of(p, CardDB.card("cova_rasa"), cova) == 4, "réquiem: custa o custo base + 2 no cemitério")
	check(not g.can_play(p, cova.uid) and g.requiem_cards(p).is_empty(), "réquiem: sem Momentum para o custo extra não dá para lançar")
	g.players[p]["momentum"] = 4
	check(g.can_play(p, cova.uid) and g.requiem_cards(p) == [cova], "réquiem: com Momentum suficiente a carta é jogável do cemitério")
	var plain := Card.new(g._uid(), "bola_de_fogo", p, "graveyard")
	g.players[p]["graveyard"].append(plain)
	check(not g.can_play(p, plain.uid), "réquiem: feitiço sem a palavra-chave não sai do cemitério")
	var grave_before: int = g.players[p]["graveyard"].size()
	var events := g.play_card(p, cova.uid)
	var play_event: Dictionary = events.filter(func(e): return e["type"] == "play")[0]
	check(play_event.get("requiem", false) and g.players[p]["momentum"] == 0, "réquiem: paga 4 e o evento de jogada marca réquiem")
	check(g.stack.size() == 1 and g.stack[0].get("requiem", false) and cova.zone == "stack", "réquiem: a carta vai para a pilha")
	check(not g.players[p]["graveyard"].has(cova), "réquiem: sai do cemitério ao ser lançada")
	for i in 5:
		if g.stack.is_empty():
			break
		g.pass_priority(g.priority)
	check(cova.zone == "banished" and g.players[p]["banished"].has(cova) and not g.players[p]["graveyard"].has(cova), "réquiem: banida depois de resolver")
	check(g.players[p]["graveyard"].size() == grave_before - 1 + 3, "réquiem: o efeito resolveu (Moer 3)")

	# countered while on the stack: still banished
	var g2 := _new_game()
	g2.auto_pass = [false, false] # keep the stack open so the test can look at it
	var p2 := g2.active
	var chamado := Card.new(g2._uid(), "chamado_do_alem", p2, "graveyard")
	g2.players[p2]["graveyard"].append(chamado)
	g2.players[p2]["graveyard"].append(Card.new(g2._uid(), "t_s_att", p2, "graveyard"))
	g2.players[p2]["momentum"] = 5
	g2.play_card(p2, chamado.uid)
	check(g2.stack.size() == 1 and g2.players[p2]["momentum"] == 0, "réquiem: Chamado do Além custa 5 do cemitério")
	g2._counter(1 - p2, g2.stack[0]["sid"])
	check(chamado.zone == "banished" and g2.players[p2]["banished"].has(chamado), "réquiem: anulada também é banida")

	# fizzled (target gone): still banished
	_tspell("t_requiem_bolt", "lento", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 1}])
	CardDB.data()["cards"]["t_requiem_bolt"]["keywords"] = ["requiem"]
	var g3 := _new_game()
	g3.auto_pass = [false, false] # keep the stack open so the test can look at it
	var p3 := g3.active
	var victim := _put(g3, 1 - p3, "t_s_att")
	var bolt := Card.new(g3._uid(), "t_requiem_bolt", p3, "graveyard")
	g3.players[p3]["graveyard"].append(bolt)
	g3.players[p3]["momentum"] = 2
	g3.play_card(p3, bolt.uid, victim.uid)
	g3.players[1 - p3]["board"].erase(victim)
	for i in 5:
		if g3.stack.is_empty():
			break
		g3.pass_priority(g3.priority)
	check(bolt.zone == "banished", "réquiem: sem alvo (fracassou) também é banida")

	# auto-pass must not skip a window where only a Réquiem is playable
	var g4 := _new_game()
	var p4 := g4.active
	g4.players[p4]["hand"].clear()
	g4.players[p4]["graveyard"].append(Card.new(g4._uid(), "cova_rasa", p4, "graveyard"))
	g4.players[p4]["momentum"] = 4
	check(g4._has_play(p4), "réquiem: conta como jogada possível para o passe automático")

	# the AI casts a Réquiem when it has nothing else
	var g5 := _new_game()
	var p5 := g5.active
	g5.players[p5]["hand"].clear()
	g5.players[p5]["legendary"]["in_zone"] = false # the AI would cast its Leader first
	var cova5 := Card.new(g5._uid(), "cova_rasa", p5, "graveyard")
	g5.players[p5]["graveyard"].append(cova5)
	g5.players[p5]["momentum"] = 4
	SimpleAI.step(g5, p5)
	check(cova5.zone != "graveyard", "réquiem: a IA lança do cemitério")

func _test_dud() -> void:
	var g := _new_game()
	var cd := CardDB.card("chamado_do_alem")
	check(g.is_dud(0, cd), "feitiço de reviver com cemitério vazio é inútil")
	g.players[0]["graveyard"].append(Card.new(9999, "t_s_att", 0, "graveyard"))
	check(not g.is_dud(0, cd), "com uma unidade barata no cemitério o feitiço tem efeito")
	check(not g.is_dud(0, CardDB.card("t_s_att")) , "unidade nunca é considerada inútil")

## Units can enter the board at any position (Hearthstone style), not only on the right edge.
func _test_play_slot() -> void:
	_tcard("t_slot", 1, 1, [])
	var g := _new_game()
	_quiet(g)
	var a := _put(g, 0, "t_slot")
	var b := _put(g, 0, "t_slot")
	g.players[0]["momentum"] = 5
	var left := _give(g, 0, "t_slot")
	check(not g.play_card(0, left, 0, 0, 0).is_empty(), "slot: jogar na esquerda é permitido")
	var uids: Array = g.players[0]["board"].map(func(c: Card): return c.uid)
	check(uids == [left, a.uid, b.uid], "slot 0 entra na ponta esquerda: %s" % [uids])
	var middle := _give(g, 0, "t_slot")
	g.play_card(0, middle, 0, 0, 2)
	uids = g.players[0]["board"].map(func(c: Card): return c.uid)
	check(uids == [left, a.uid, middle, b.uid], "slot 2 entra no meio: %s" % [uids])
	var right := _give(g, 0, "t_slot")
	g.play_card(0, right)
	uids = g.players[0]["board"].map(func(c: Card): return c.uid)
	check(uids.back() == right, "sem slot continua entrando na direita")
	var far := _give(g, 0, "t_slot")
	g.play_card(0, far, 0, 0, 99)
	check(g.players[0]["board"].back().uid == far, "slot além do fim vira direita")

func _test_ossuario() -> void:
	_tcard("t_oss", 1, 1, [])
	var g := _new_game()
	_quiet(g)
	var relic := Card.new(g._uid(), "ossuario_sem_fundo", 0)
	g._place_relic(0, relic)
	g._flush()
	check(g.find_relic(relic.uid) != null, "ossuário: fica em campo como relíquia")
	var unit := _put(g, 0, "t_oss")
	check(g.slots_used(0) == 2, "ossuário: ocupa um espaço de unidade")
	var deck_before: int = g.players[0]["deck"].size()
	_kill(g, unit)
	check(g.players[0]["deck"].size() == deck_before - 1, "ossuário: aliado morre -> Moer 1")
	g.players[0]["momentum"] = 4
	check(g.can_activate(0, relic.uid), "ossuário: pode ativar com 4 e unidade no cemitério")
	g.activate(0, relic.uid)
	g._flush()
	check(g.phase == "search" and g.pending_search.get("revive", false), "ossuário: abre escolha de reviver")
	if g.phase == "search":
		var options: Array = g.pending_search["cards"]
		g.choose_search(0, int(options[0]["uid"]))
		g._flush()
	check(_count(g, 0, "t_oss") == 1, "ossuário: cópia revivida em campo")
	g.destroy_relic(relic)
	g._flush()
	check(g.find_relic(relic.uid) == null and g.slots_used(0) == 1, "ossuário: destruído libera o espaço")

func _test_self_response() -> void:
	var g := _new_game()
	g.self_response_enabled = true
	_quiet(g)
	g.players[0]["hand"].clear() # only the bolts below count as legal plays
	g.auto_pass[1] = false # keep the opponent's window open so the hand-over can be observed
	var foe := _put(g, 1, "geodo_vivo")
	var first_bolt := _give(g, 0, "labareda")
	var second_bolt := _give(g, 0, "labareda")
	var third_bolt := _give(g, 0, "labareda")
	g.players[0]["momentum"] = 10
	g.play_card(0, first_bolt, foe.uid)
	check(g.priority == 1 and not g.stack_passed and g.stack.size() == 1, "feitiço lançado: o oponente decide primeiro")
	g.pass_priority(1)
	check(g.priority == 0 and g.stack_passed and g.stack.size() == 1, "oponente passou: a vez volta pra quem lançou, sem resolver")
	g.play_card(0, second_bolt, foe.uid)
	check(g.priority == 1 and not g.stack_passed and g.stack.size() == 2, "empilha por cima do próprio feitiço: o oponente responde de novo")
	g.pass_priority(1)
	g.pass_priority(0)
	check(g.stack.is_empty(), "os dois passaram em sequência: a pilha resolve")
	# the last bolt leaves no other play in hand, so the caster's turn to follow up is skipped
	g.play_card(0, third_bolt, foe.uid)
	g.pass_priority(1)
	check(g.stack.is_empty(), "sem jogada legal pra quem lançou: a pilha resolve direto quando o oponente passa")

## Deck "Ladeira de Nythera": Ritual do Degelo (+1 nível, +3 Momentum), Ladeira Abaixo e Sem Freio (sobe metade do nível, arredondada para cima),
## a Wanessa que vira Tempesfrost ao cruzar para Grande, e a Bola de Neve que a Tempesfrost lança no Líder.
## Fixture: turn-8 resources (8 Momentum + 2 Reserva), Wanessa untransformed, Bola de Neve level 3-5.
func _combo_game(level: int, enemy_units: int, momentum: int, reserve: int) -> Dictionary:
	var g := _glacial_game()
	var a := g.active
	var o := g.opponent(a)
	g.players[a]["momentum"] = momentum
	g.players[a]["reserve"] = reserve
	g.players[a]["snowball"] = level
	g.players[o]["leader_hp"] = 60
	var enemies: Array = []
	for i in enemy_units:
		enemies.append(_put(g, o, "teste_alvo_gelo"))
	var princess := _put(g, a, "princesa_wanessa")
	return {"game": g, "me": a, "foe": o, "enemies": enemies, "princess": princess}

## Level after one Ladeira: it grows by half of itself, rounded up.
func _after_ladeira(level: int) -> int:
	return level + (level + 1) / 2

func _test_glacial_combo() -> void:
	_tcard("teste_alvo_gelo", 0, 20, [])
	# the full combo: Ladeira, Ritual, Ladeira, Grande Bola de Neve, then Tempesfrost attacks the Leader
	for level in [3, 4]:
		for enemy_count in [1, 2]:
			var label := "nível %d, %d inimigas" % [level, enemy_count]
			var setup := _combo_game(level, enemy_count, 8, 2)
			var g: GameState = setup["game"]
			var a: int = setup["me"]
			var o: int = setup["foe"]
			var princess: Card = setup["princess"]
			var first_enemy: Card = setup["enemies"][0]
			var waiting_bola := Card.new(g._uid(), "bola_de_neve", a, "hand")
			g.players[a]["hand"].append(waiting_bola)
			# Ladeira goes FIRST: the Ritual's +3 Momentum is capped at 10, so casting it with 8 Momentum wastes 1 and the Grande no longer fits
			_cast_and_resolve(g, a, "ladeira_abaixo_e_sem_freio")
			check(int(g.players[a]["snowball"]) == _after_ladeira(level), "combo (%s): a primeira Ladeira sobe metade do nível" % label)
			_cast_and_resolve(g, a, "ritual_do_degelo")
			check(int(g.players[a]["snowball"]) == _after_ladeira(level) + 1, "combo (%s): o Ritual sobe 1 nível" % label)
			_cast_and_resolve(g, a, "ladeira_abaixo_e_sem_freio")
			check(int(g.players[a]["snowball"]) == _after_ladeira(_after_ladeira(level) + 1) and g.snowball_is_grande(a), "combo (%s): a segunda Ladeira leva o nível a Grande (%d)" % [label, int(g.players[a]["snowball"])])
			check(princess.card_id == "wanessa_tempesfrost" and not princess.sick, "combo (%s): Wanessa vira Tempesfrost ao nível virar Grande e já pode atacar" % label)
			check(g.players[o]["board"].all(func(c: Card): return c.frozen > 0), "combo (%s): ao transformar, todas as unidades inimigas ficam congeladas" % label)
			check(waiting_bola.card_id == "grande_bola_de_neve", "combo (%s): a Bola de Neve que esperava na mão evoluiu ao cruzar o nível 8" % label)
			var grande_cost := g.cost_of(a, CardDB.card(waiting_bola.card_id))
			check(grande_cost == 4 and g.budget(a, true) == 4, "combo (%s): sobram exatamente 4 de Momentum para a Grande Bola de Neve (custo %d, sobra %d)" % [label, grande_cost, g.budget(a, true)])
			g.play_card(a, waiting_bola.uid, first_enemy.uid)
			for guard in 8:
				if g.stack.is_empty():
					break
				g.pass_priority(g.priority)
			g._flush()
			check(g.budget(a, true) == 0, "combo (%s): o combo gasta todo o Momentum do 8º turno" % label)
			_hit(g, princess, GameState.LEADER_UID[o])
			var leader_damage: int = 60 - int(g.players[o]["leader_hp"])
			check(leader_damage >= 10, "combo (%s): dano ao Líder inimigo foi %d (esperado 10 ou mais)" % [label, leader_damage])

	# one turn earlier (7 Momentum + 2 Reserva) the last Grande Bola de Neve no longer fits
	var early := _combo_game(3, 1, 7, 2)
	var early_game: GameState = early["game"]
	var early_player: int = early["me"]
	_cast_and_resolve(early_game, early_player, "ladeira_abaixo_e_sem_freio")
	_cast_and_resolve(early_game, early_player, "ritual_do_degelo")
	_cast_and_resolve(early_game, early_player, "ladeira_abaixo_e_sem_freio")
	var early_bola := _give(early_game, early_player, "grande_bola_de_neve")
	check(not early_game.can_play(early_player, early_bola), "combo: no 7º turno falta Momentum para a Grande Bola de Neve")

	# the Ritual first wastes Momentum: the +3 hits the cap of 10, so even at turn 8 the Grande does not fit
	var wasteful := _combo_game(3, 1, 8, 2)
	var wasteful_game: GameState = wasteful["game"]
	var wasteful_player: int = wasteful["me"]
	_cast_and_resolve(wasteful_game, wasteful_player, "ritual_do_degelo")
	_cast_and_resolve(wasteful_game, wasteful_player, "ladeira_abaixo_e_sem_freio")
	_cast_and_resolve(wasteful_game, wasteful_player, "ladeira_abaixo_e_sem_freio")
	var wasteful_bola := _give(wasteful_game, wasteful_player, "grande_bola_de_neve")
	check(not wasteful_game.can_play(wasteful_player, wasteful_bola), "combo: com o Ritual primeiro o teto de 10 desperdiça Momentum e a Grande não cabe")

	# Ritual alone: +1 level and the 3 Momentum come back (net +2)
	var ritual := _combo_game(3, 1, 7, 0)
	var ritual_game: GameState = ritual["game"]
	_cast_and_resolve(ritual_game, ritual["me"], "ritual_do_degelo")
	check(int(ritual_game.players[ritual["me"]]["snowball"]) == 4 and int(ritual_game.players[ritual["me"]]["momentum"]) == 9, "Ritual do Degelo: nível 4 e Momentum 7 - 1 + 3 = 9")

	# the crossing into Grande is heard once: a Wanessa that arrives later is not transformed by a level that was already Grande
	var crossing := _combo_game(5, 1, 10, 0)
	var crossing_game: GameState = crossing["game"]
	_cast_and_resolve(crossing_game, crossing["me"], "ladeira_abaixo_e_sem_freio")
	check(crossing["princess"].card_id == "wanessa_tempesfrost", "Ladeira: nível 5 sobe para 8 e cruza para Grande")
	var late_princess := _put(crossing_game, crossing["me"], "princesa_wanessa")
	crossing_game.set_snowball_level(crossing["me"], 20)
	check(late_princess.card_id == "princesa_wanessa", "snowball_grande só dispara na passagem: já Grande, subir mais não transforma")

	# Tempesfrost: Ao Atacar lança a Bola de Neve no Líder (sem quicar, sem fazer o nível crescer)
	var attack := _combo_game(8, 1, 0, 0)
	var attack_game: GameState = attack["game"]
	var tempesfrost := _put(attack_game, attack["me"], "wanessa_tempesfrost")
	_hit(attack_game, tempesfrost, GameState.LEADER_UID[attack["foe"]])
	_pass_windows(attack_game) # the Bola waits on the stack; combat damage lands once it resolves
	var attack_damage: int = 60 - int(attack_game.players[attack["foe"]]["leader_hp"])
	check(attack_damage >= 10 and attack_damage == 8 + attack_game.atk_of(tempesfrost), "Tempesfrost: o ataque dá a Bola de Neve (8) + ATK no Líder (%d)" % attack_damage)
	check(int(attack_game.players[attack["me"]]["snowball"]) == 8, "Tempesfrost: a Bola lançada no Líder não faz o nível crescer")
	check(attack["enemies"][0].damage == 0, "Tempesfrost: a Bola no Líder não bate na unidade inimiga")

	# Tempesfrost: the Bola goes on the stack (reactable) before combat damage; countering it keeps the combat damage
	var stacked := _combo_game(8, 1, 0, 0)
	var stacked_game: GameState = stacked["game"]
	var stacked_tempesfrost := _put(stacked_game, stacked["me"], "wanessa_tempesfrost")
	stacked_game.auto_pass = [false, false] # nobody passes by themselves: the Bola stays on the stack
	var stacked_graveyard_before: int = stacked_game.players[stacked["me"]]["graveyard"].size()
	_hit(stacked_game, stacked_tempesfrost, GameState.LEADER_UID[stacked["foe"]])
	check(stacked_game.stack.size() == 1 and stacked_game.stack[0]["card_id"] == "grande_bola_de_neve" and stacked_game.stack[0].get("virtual", false), "Tempesfrost: a Grande Bola de Neve (nível 8) vai para a pilha (reagível)")
	check(int(stacked_game.players[stacked["foe"]]["leader_hp"]) == 60, "Tempesfrost: nada de dano enquanto a Bola espera na pilha")
	stacked_game._counter(stacked["foe"], stacked_game.stack[0]["sid"])
	_pass_windows(stacked_game)
	var stacked_damage: int = 60 - int(stacked_game.players[stacked["foe"]]["leader_hp"])
	check(stacked_damage == stacked_game.atk_of(stacked_tempesfrost), "Tempesfrost: Bola anulada, sobra só o dano de combate (%d)" % stacked_damage)
	check(stacked_game.players[stacked["me"]]["graveyard"].size() == stacked_graveyard_before, "Tempesfrost: a Bola virtual não vai ao cemitério")

	# Tempesfrost challenging a tapped enemy unit: the Bola is cast on THAT unit and bounces (the level grows)
	var duel := _combo_game(8, 2, 0, 0)
	var duel_game: GameState = duel["game"]
	var duel_tempesfrost := _put(duel_game, duel["me"], "wanessa_tempesfrost")
	var duel_target: Card = duel["enemies"][0]
	duel_target.exhausted = true
	var duel_leader_before: int = int(duel_game.players[duel["foe"]]["leader_hp"])
	_hit(duel_game, duel_tempesfrost, duel_target.uid)
	_pass_windows(duel_game)
	var duel_total_damage: int = duel["enemies"][0].damage + duel["enemies"][1].damage
	check(duel_target.damage >= 8, "Tempesfrost: desafiar uma unidade lança a Bola de Neve nela (dano %d)" % duel_target.damage)
	check(duel["enemies"][1].damage == 9 or duel_total_damage >= 17, "Tempesfrost: a Bola lançada numa unidade quica para a vizinha (total %d)" % duel_total_damage)
	check(int(duel_game.players[duel["me"]]["snowball"]) >= 9, "Tempesfrost: a Bola numa unidade faz o nível crescer (%d)" % int(duel_game.players[duel["me"]]["snowball"]))
	check(int(duel_game.players[duel["foe"]]["leader_hp"]) == duel_leader_before, "Tempesfrost: desafiar uma unidade não bate no Líder (a unidade tem 20 de Vida, sem sobra)")

	# Fifi Congela-Passos: Ao Entrar freezes AND exhausts the same enemy unit, which Tempesfrost can then challenge
	var fifi := _combo_game(8, 2, 10, 0)
	var fifi_game: GameState = fifi["game"]
	var fifi_victim: Card = fifi["enemies"][0]
	var fifi_bystander: Card = fifi["enemies"][1]
	_cast_and_resolve(fifi_game, fifi["me"], "fifi_congela_passos")
	fifi_game.choose_enter_target(fifi["me"], fifi_victim.uid) # her Ao Entrar target is chosen after she enters
	fifi_game._flush()
	check(fifi_victim.exhausted and fifi_victim.frozen > 0, "Fifi: Ao Entrar congela e exaure a unidade escolhida")
	check(not fifi_bystander.exhausted and fifi_bystander.frozen == 0, "Fifi: a outra unidade inimiga não é afetada")
	var fifi_tempesfrost := _put(fifi_game, fifi["me"], "wanessa_tempesfrost")
	fifi_tempesfrost.sick = false
	_hit(fifi_game, fifi_tempesfrost, fifi_victim.uid)
	_pass_windows(fifi_game)
	check(fifi_victim.damage >= 8, "Fifi + Tempesfrost: a unidade exausta pode ser desafiada e leva a Bola (dano %d)" % fifi_victim.damage)

	# Espectro do Gelo Aprisionante: like Fifi, Ao Entrar freezes AND exhausts the chosen enemy unit (cost 4 now)
	check(int(CardDB.card("espectro_do_gelo_aprisionante")["cost"]) == 5 and int(CardDB.card("espectro_do_gelo_aprisionante")["atk"]) == 2 and int(CardDB.card("espectro_do_gelo_aprisionante")["hp"]) == 4, "Espectro: custo 5, 2/4")
	var espectro := _combo_game(8, 2, 10, 0)
	var espectro_game: GameState = espectro["game"]
	var espectro_victim: Card = espectro["enemies"][0]
	_cast_and_resolve(espectro_game, espectro["me"], "espectro_do_gelo_aprisionante")
	espectro_game.choose_enter_target(espectro["me"], espectro_victim.uid)
	espectro_game._flush()
	check(espectro_victim.exhausted and espectro_victim.frozen > 0, "Espectro: Ao Entrar congela e exaure a unidade escolhida")
	check(not espectro["enemies"][1].exhausted and espectro["enemies"][1].frozen == 0, "Espectro: a outra unidade inimiga não é afetada")

	# Rei Gelado: 4 random slots of the enemy field. Units in them are frozen+exhausted, empty ones are blocked,
	# so units hit + slots blocked is always 4 (whatever the draw)
	check(int(CardDB.card("rei_gelado")["atk"]) == 6 and int(CardDB.card("rei_gelado")["hp"]) == 7, "Rei Gelado: 6/7")
	for enemy_count in [0, 3, 6, 8]:
		var rei := _combo_game(8, enemy_count, 10, 0)
		var rei_game: GameState = rei["game"]
		var rei_foe: int = rei["foe"]
		_cast_and_resolve(rei_game, rei["me"], "rei_gelado")
		var frozen_units: Array = rei["enemies"].filter(func(c: Card): return c.frozen > 0)
		var blocked_slots: int = int(rei_game.players[rei_foe]["frozen_slots"])
		check(frozen_units.size() + blocked_slots == 4, "Rei Gelado (%d inimigas): unidades atingidas (%d) + espaços vazios bloqueados (%d) = 4" % [enemy_count, frozen_units.size(), blocked_slots])
		check(frozen_units.all(func(c: Card): return c.exhausted), "Rei Gelado (%d inimigas): toda unidade atingida também fica exausta" % enemy_count)
		check(rei["enemies"].all(func(c: Card): return c.frozen > 0 or not c.exhausted), "Rei Gelado (%d inimigas): unidade fora dos espaços sorteados não é afetada" % enemy_count)
		check(rei["princess"].frozen == 0 and int(rei_game.players[rei["me"]]["frozen_slots"]) == 0, "Rei Gelado (%d inimigas): o campo de quem lançou não é afetado" % enemy_count)

	# empty frozen slots take room: with 8 empty slots 4 are blocked, so only 4 units fit
	var block := _combo_game(8, 0, 10, 0)
	var block_game: GameState = block["game"]
	var block_foe: int = block["foe"]
	_cast_and_resolve(block_game, block["me"], "rei_gelado")
	check(int(block_game.players[block_foe]["frozen_slots"]) == 4, "Rei Gelado: campo inimigo vazio tem 4 espaços congelados")
	for filler in 4:
		check(block_game.has_free_slot(block_foe), "Rei Gelado: ainda cabe a unidade %d nos 4 espaços livres" % (filler + 1))
		_put(block_game, block_foe, "teste_alvo_gelo")
	check(not block_game.has_free_slot(block_foe), "Rei Gelado: com 4 unidades e 4 espaços congelados o campo inimigo está cheio")
	# they thaw at the END of the victim's own next turn, not before
	block_game.end_turn(block["me"])
	check(block_game.active == block_foe and int(block_game.players[block_foe]["frozen_slots"]) == 4, "Rei Gelado: os espaços seguem congelados durante o turno do oponente")
	block_game.end_turn(block_foe)
	check(int(block_game.players[block_foe]["frozen_slots"]) == 0 and block_game.has_free_slot(block_foe), "Rei Gelado: os espaços descongelam no fim do turno do oponente")

	# Chamado da Nevasca finds any Glacial spell that costs 4 or less, and nothing else
	var search := _combo_game(3, 0, 10, 0)
	var search_game: GameState = search["game"]
	var searcher: int = search["me"]
	search_game.players[searcher]["deck"].clear()
	var wanted: Array = []
	# the first four qualify; Avalanche costs 5, Nythera is a unit and Carga Acumulada is not Glacial
	for card_id in ["bola_de_neve", "ritual_do_degelo", "ladeira_abaixo_e_sem_freio", "estilhaco_gelido", "avalanche", "nythera", "carga_acumulada"]:
		var deck_card := Card.new(search_game._uid(), card_id, searcher, "deck")
		search_game.players[searcher]["deck"].append(deck_card)
		if card_id in ["bola_de_neve", "ritual_do_degelo", "ladeira_abaixo_e_sem_freio", "estilhaco_gelido"]:
			wanted.append(deck_card.uid)
	var chamado_uid := _give(search_game, searcher, "chamado_da_nevasca")
	search_game.play_card(searcher, chamado_uid)
	for guard in 8:
		if search_game.stack.is_empty() or search_game.phase == "search":
			break
		search_game.pass_priority(search_game.priority)
	check(search_game.phase == "search", "Chamado da Nevasca: oferece uma busca (fase %s)" % search_game.phase)
	var offered: Array = search_game.pending_search["cards"].map(func(option: Dictionary): return int(option["uid"]))
	offered.sort()
	wanted.sort()
	check(offered == wanted, "Chamado da Nevasca: oferece só feitiços Glaciais de custo 4 ou menos (%s)" % [offered])

	# the new deck: legal and holding the combo pieces
	var combo_deck := DeckDB.get_deck("glacial_combo")
	check(DeckDB.validate("glacial_combo").is_empty() and combo_deck["cards"].has("ritual_do_degelo") and combo_deck["cards"].has("ladeira_abaixo_e_sem_freio"), "deck Ladeira de Nythera é legal e tem as peças do combo")

func _test_deslizamento() -> void:
	var g := _new_game()
	_quiet(g)
	var left := _put(g, 1, "geodo_vivo")
	var center := _put(g, 1, "geodo_vivo")
	var right := _put(g, 1, "geodo_vivo")
	var far := _put(g, 1, "geodo_vivo")
	var effect := EffectRegistry.parse({"action": "damage", "target": "enemy_unit", "amount": 3, "adjacent_amount": 2})
	var context := EffectContext.new(g, 0, "")
	effect.apply(context, center.uid)
	check(center.damage == 3 and left.damage == 2 and right.damage == 2 and far.damage == 0, "deslizamento: 3 no alvo, 2 nas adjacentes (%d/%d/%d/%d)" % [left.damage, center.damage, right.damage, far.damage])

func _test_yresa_fusion() -> void:
	var g := _new_game()
	_quiet(g)
	var yresa := _put(g, 0, "yresa_petronika")
	g.players[0]["momentum"] = 8
	g.transform(0, yresa.uid)
	check(_count(g, 0, "yresa_sentinel") == 2, "yrêsa primordial: Ao Entrar invoca 2 Stonewards")
	var guard := g.players[0]["board"][1] as Card
	check(g.armor_of(yresa) >= 1, "stoneward: adjacente ganha Armadura 1")
	g.players[0]["momentum"] = 5
	check(g.can_activate(0, yresa.uid), "yrêsa: pode fundir com 2 Stonewards")
	g.activate(0, yresa.uid)
	g.pass_priority(0)
	g.pass_priority(1)
	g._flush()
	check(_count(g, 0, "yresa_sentinel") == 0 and _count(g, 0, "yresa_colossus") == 1, "fusão: 2 Stonewards viram 1 Colossus")
	var colossus: Card = g.players[0]["board"].filter(func(c: Card): return c.card_id == "yresa_colossus")[0]
	check(colossus.atk == 2 and colossus.hp == 4 and colossus.armor == 2, "colossus: +1/+2 e Armadura 1 por Stoneward (%d/%d A%d)" % [colossus.atk, colossus.hp, colossus.armor])
	check(yresa.exhausted and not g.can_activate(0, yresa.uid), "fusão exaure e precisa de 2+ Stonewards")
	check(g.players[0]["graveyard"].is_empty() and guard != null, "fichas fundidas não vão pro cemitério")

# ---- Glacial: Bola de Neve, Amuleto, Câmara de Êxtase, descarte da mão ----

func _glacial_game() -> GameState:
	var g := GameState.new("glacial", "fogo", 42)
	g.mulligan(0, [])
	g.mulligan(1, [])
	g.self_response_enabled = false
	_quiet(g)
	return g

## Casts a spell from the hand and lets the whole stack resolve.
func _cast_and_resolve(g: GameState, p: int, card_id: String, target := 0) -> void:
	var uid := _give(g, p, card_id)
	g.play_card(p, uid, target)
	for guard in 8:
		if g.stack.is_empty():
			break
		g.pass_priority(g.priority)
	g._flush()

func _test_glacial() -> void:
	_tcard("teste_alvo_gelo", 0, 20, [])
	var g := _glacial_game()
	var a := g.active
	var o := g.opponent(a)
	g.players[a]["momentum"] = 30
	var first := _put(g, o, "teste_alvo_gelo")
	var middle := _put(g, o, "teste_alvo_gelo")
	var last := _put(g, o, "teste_alvo_gelo")

	# Bola de Neve from the edge: 1, then 2, then 3 (the direction has no choice at the edge)
	_cast_and_resolve(g, a, "bola_de_neve", first.uid)
	check(first.hp_left() == 19 and middle.hp_left() == 18 and last.hp_left() == 17, "bola de neve: 1, 2 e 3 de dano nos quiques (%d/%d/%d)" % [first.hp_left(), middle.hp_left(), last.hp_left()])
	check(g.players[a]["snowball"] == 3, "bola de neve: a próxima começa onde esta parou")
	_cast_and_resolve(g, a, "bola_de_neve", first.uid)
	check(first.hp_left() == 16 and g.players[a]["snowball"] == 5, "segunda bola começa em 3 e termina em 5")

	# the card text shows the owner's current level where it says {nivel}
	var bola_text := String(CardDB.card("bola_de_neve")["text"])
	check(bola_text.contains("{nivel}"), "texto da bola de neve tem o marcador {nivel}")
	var shown_text := CardView.fill_live_numbers(bola_text, int(g.players[a]["snowball"]))
	check(not shown_text.contains("{nivel}") and shown_text.contains("Cause 5 de dano"), "texto da bola de neve mostra o nível atual (5)")
	check(CardView.fill_live_numbers(bola_text, 1).contains("Cause 1 de dano"), "sem dono, o texto mostra o nível inicial (1)")

	# a Bola aimed at a Leader is a plain hit and the level doesn't grow
	var unit_cast_graveyard_before: int = g.players[a]["graveyard"].size()
	var leader_before: int = g.players[o]["leader_hp"]
	var plain_hit := EffectRegistry.parse({"trigger": "on_attack", "action": "snowball", "target": "random_enemy"})
	var unit_cast_context := EffectContext.new(g, a, "on_attack")
	unit_cast_context.self_uid = first.uid
	plain_hit.apply(unit_cast_context, GameState.LEADER_UID[o])
	# cast by a unit: nothing hits yet, the Bola de Neve card waits on the stack (reactable, counterable)
	check(g.stack.size() == 1 and g.stack[0]["kind"] == "card" and g.stack[0]["card_id"] == "bola_de_neve" and g.stack[0]["virtual"], "bola de unidade: entra na pilha como a carta Bola de Neve")
	check(g.players[o]["leader_hp"] == leader_before, "bola de unidade: não bate antes de resolver")
	for guard in 8:
		if g.stack.is_empty():
			break
		g.pass_priority(g.priority)
	check(g.players[o]["leader_hp"] == leader_before - 5 and g.players[a]["snowball"] == 5, "bola no Líder: um golpe só, sem aumentar o nível")
	check(g.players[a]["graveyard"].size() == unit_cast_graveyard_before, "bola de unidade: não deixa carta no cemitério")

	# Grande Bola de Neve is its own card: own cost, and every hit has Sobrepujança
	check(g.cost_of(a, CardDB.card("bola_de_neve")) == 3, "Bola de Neve comum custa 3")
	check(g.cost_of(a, CardDB.card("grande_bola_de_neve")) == 4, "Grande Bola de Neve custa 4")
	check(CardDB.card("grande_bola_de_neve").get("transform_only", false), "Grande Bola de Neve só existe por evolução (não entra em deck)")
	_tcard("teste_frágil_gelo", 0, 3, [])
	var fragile := _put(g, o, "teste_frágil_gelo")
	g.players[a]["snowball"] = 8
	leader_before = g.players[o]["leader_hp"]
	_cast_and_resolve(g, a, "grande_bola_de_neve", fragile.uid)
	check(g.find_unit(fragile.uid) == null and g.players[o]["leader_hp"] <= leader_before - 5, "Grande Bola: o excesso de dano vai pro Líder")

	# crossing level 8 evolves every Bola de Neve of the player: hand, deck and graveyard
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	var hand_bola := Card.new(g._uid(), "bola_de_neve", a, "hand")
	var deck_bola := Card.new(g._uid(), "bola_de_neve", a, "deck")
	var grave_bola := Card.new(g._uid(), "bola_de_neve", a, "graveyard")
	var foe_bola := Card.new(g._uid(), "bola_de_neve", o, "hand")
	g.players[a]["hand"].append(hand_bola)
	g.players[a]["deck"].append(deck_bola)
	g.players[a]["graveyard"].append(grave_bola)
	g.players[o]["hand"].append(foe_bola)
	g.set_snowball_level(a, 7)
	check(hand_bola.card_id == "bola_de_neve" and deck_bola.card_id == "bola_de_neve", "nível 7: nenhuma Bola evolui ainda")
	g.set_snowball_level(a, 8)
	check(hand_bola.card_id == "grande_bola_de_neve" and deck_bola.card_id == "grande_bola_de_neve" and grave_bola.card_id == "grande_bola_de_neve", "nível 8: Bolas da mão, do baralho e do cemitério evoluem")
	check(foe_bola.card_id == "bola_de_neve", "a Bola do oponente não evolui com o nível de quem joga")
	check(g.snowball_is_grande(a) and not g.snowball_is_grande(o), "snowball_is_grande depende do nível de cada jogador")

	# a plain Bola entering the hand after level 8 is converted on arrival
	var late_bola := Card.new(g._uid(), "bola_de_neve", a, "deck")
	g.players[a]["deck"].append(late_bola)
	g._move(late_bola, "hand")
	check(late_bola.card_id == "grande_bola_de_neve", "uma Bola que chega à mão com nível 8+ já vem Grande")

	# the Bola that raises the level to 8 is on the stack: it lands in the graveyard already as a Grande card
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	g.players[a]["snowball"] = 7
	var crossing_target := _put(g, o, "teste_alvo_gelo")
	_put(g, o, "teste_alvo_gelo") # the second hit (8 damage) is what raises the level from 7 to 8
	var crossing_bola := Card.new(g._uid(), "bola_de_neve", a, "hand")
	g.players[a]["hand"].append(crossing_bola)
	g.play_card(a, crossing_bola.uid, crossing_target.uid)
	for guard in 8:
		if g.stack.is_empty():
			break
		g.pass_priority(g.priority)
	g._flush()
	check(int(g.players[a]["snowball"]) >= 8 and crossing_bola.card_id == "grande_bola_de_neve" and crossing_bola.zone == "graveyard", "a Bola que cruza o nível 8 termina no cemitério já como Grande")

	# Nythera, Ao Entrar: puts a Bola de Neve on top of her owner's deck (born Grande from level 8 on) and freezes
	for level in [7, 8]:
		g = _glacial_game()
		a = g.active
		o = g.opponent(a)
		g.players[a]["momentum"] = 30
		g.players[a]["snowball"] = level
		_tcard("teste_frágil_gelo", 0, 3, [])
		var nythera_target := _put(g, o, "teste_frágil_gelo")
		leader_before = g.players[o]["leader_hp"]
		_cast_and_resolve(g, a, "nythera")
		g.choose_enter_target(a, nythera_target.uid) # her Ao Entrar target is chosen after she enters
		g._flush()
		var top_card: Card = g.players[a]["deck"].back()
		var expected_top := "grande_bola_de_neve" if level == 8 else "bola_de_neve"
		check(top_card.card_id == expected_top and top_card.zone == "deck", "Nythera ao entrar (nível %d): põe %s no topo do deck" % [level, expected_top])
		check(g.players[o]["leader_hp"] == leader_before and nythera_target.frozen > 0 and int(g.players[a]["snowball"]) == level, "Nythera ao entrar (nível %d): não lança a Bola (sem dano nem nível novo) e congela o alvo" % level)

	# Zero Absoluto: rápido, custa 4 e congela todas as unidades inimigas (e só elas)
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	_tcard("teste_alvo_gelo", 3, 20, [])
	var frozen_one := _put(g, o, "teste_alvo_gelo")
	var frozen_two := _put(g, o, "teste_alvo_gelo")
	var own_unit := _put(g, a, "teste_alvo_gelo")
	check(g.cost_of(a, CardDB.card("zero_absoluto")) == 4 and CardDB.card("zero_absoluto")["speed"] == "rapido", "Zero Absoluto custa 4 e é rápido")
	_cast_and_resolve(g, a, "zero_absoluto")
	check(g.atk_of(frozen_one) == 0 and g.atk_of(frozen_two) == 0 and g.atk_of(own_unit) == 3, "Zero Absoluto congela todas as unidades inimigas e nenhuma aliada")

	# Princesa Wanessa becomes Tempesfrost when her controller casts a Grande Bola de Neve
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	var target_unit := _put(g, o, "teste_alvo_gelo")
	var princess := _put(g, a, "princesa_wanessa")
	g.players[a]["snowball"] = 3
	_cast_and_resolve(g, a, "bola_de_neve", target_unit.uid)
	check(princess.card_id == "princesa_wanessa", "Wanessa não se transforma com uma Bola de Neve comum")
	g.players[a]["snowball"] = 8
	_cast_and_resolve(g, a, "grande_bola_de_neve", target_unit.uid)
	check(princess.card_id == "wanessa_tempesfrost" and princess.keywords.has("sobrepujanca") and not princess.keywords.has("voo"), "Wanessa vira Tempesfrost ao ver uma Grande Bola de Neve")

	# Amuleto do Primeiro Floco: only the first glacial spell each turn is cheaper
	g = _glacial_game()
	a = g.active
	g.players[a]["momentum"] = 30
	var holder := _put(g, a, "teste_alvo_gelo")
	var amulet := Card.new(g._uid(), "amuleto_do_primeiro_floco", a)
	g.stack_system().attach(holder, amulet)
	var avalanche: Dictionary = CardDB.card("avalanche")
	check(g.cost_of(a, avalanche) == int(avalanche["cost"]) - 1, "amuleto: o primeiro feitiço glacial custa 1 a menos")
	var momentum_before: int = g.players[a]["momentum"]
	_cast_and_resolve(g, a, "avalanche")
	check(momentum_before - int(g.players[a]["momentum"]) == int(avalanche["cost"]) - 1, "amuleto: pagou 1 a menos")
	check(g.cost_of(a, avalanche) == int(avalanche["cost"]), "amuleto: o segundo feitiço do turno custa o normal")

	# Câmara de Êxtase: cancels a lethal damage once, then halves the damage until the end of the next turn
	g = _glacial_game()
	a = g.active
	var chamber := Card.new(g._uid(), "camara_de_extase", a)
	g._place_relic(a, chamber)
	g.players[a]["leader_hp"] = 5
	g._deal_damage(GameState.LEADER_UID[a], 9, null)
	check(g.players[a]["leader_hp"] == 5, "câmara: o dano que mataria é anulado")
	check(g.find_relic(chamber.uid) == null, "câmara: é destruída ao proteger")
	g._deal_damage(GameState.LEADER_UID[a], 3, null)
	check(g.players[a]["leader_hp"] == 4, "câmara: depois o dano cai pela metade, arredondado pra baixo (3 -> 1)")

	# Folheio Pé-na-Neve: draws 3, then the player picks a card from the hand and it goes to the graveyard
	g = _glacial_game()
	a = g.active
	g.players[a]["momentum"] = 30
	var hand_before: int = g.players[a]["hand"].size()
	var graveyard_before: int = g.players[a]["graveyard"].size()
	var folheio_uid := _give(g, a, "folheio_pe_na_neve")
	g.play_card(a, folheio_uid, 0)
	for guard in 8:
		if g.stack.is_empty():
			break
		g.pass_priority(g.priority)
	check(g.phase == "search" and g.pending_search.get("discard_hand", false), "folheio: abre a escolha de descarte")
	var discarded_uid: int = int(g.pending_search["cards"][0]["uid"])
	g.choose_search(a, discarded_uid)
	var discarded_in_graveyard: bool = g.players[a]["graveyard"].any(func(c: Card): return c.uid == discarded_uid)
	check(g.phase == "main" and discarded_in_graveyard, "folheio: a carta escolhida vai pro cemitério")
	check(g.players[a]["hand"].size() == hand_before + 3 - 1, "folheio: comprou 3 e descartou 1 (a própria carta já saiu da mão)")
	check(g.players[a]["graveyard"].size() == graveyard_before + 2, "folheio: cemitério ganhou o feitiço e a carta descartada")

	# Weyne: her spell trigger works once per turn (buff and freeze), not once per spell
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	var weyne := _put(g, a, "weyne")
	var weyne_victim := _put(g, o, "teste_alvo_gelo")
	var weyne_atk_before: int = g.atk_of(weyne)
	_cast_and_resolve(g, a, "estilhaco_gelido", weyne_victim.uid)
	_cast_and_resolve(g, a, "estilhaco_gelido", weyne_victim.uid)
	check(g.atk_of(weyne) == weyne_atk_before + 1, "weyne: só ganha +1/+1 uma vez por turno, mesmo com 2 feitiços glaciais")

	# Mestra do Gelo Frígido pings when a glacial spell is cast
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	var victim := _put(g, o, "teste_alvo_gelo")
	_put(g, a, "mestra_do_gelo_frigido")
	_cast_and_resolve(g, a, "estilhaco_gelido", victim.uid)
	check(victim.hp_left() == 20 - 3 - 1 and victim.frozen > 0, "Mestra do Gelo Frígido: o primeiro feitiço glacial do turno dá +1 de dano e congela")
	_cast_and_resolve(g, a, "estilhaco_gelido", victim.uid)
	check(victim.hp_left() == 20 - 3 - 1 - 3, "Mestra do Gelo Frígido: só age uma vez por turno (o segundo feitiço não causa o +1)")
	check(CardDB.card("mestra_do_gelo_frigido")["atk"] == 1 and CardDB.card("mestra_do_gelo_frigido")["hp"] == 5, "Mestra do Gelo Frígido é 1/5")

	# Bruno (Rompante): hitting the enemy Leader raises the Bola de Neve level by 1 (no cast) and opens the search
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	var bruno := _put(g, a, "bruno", false)
	check(g.attack_targets(bruno) == [GameState.LEADER_UID[o]], "Bruno: Rompante, só o Líder é alvo")
	var level_before: int = g.players[a]["snowball"]
	_hit(g, bruno, GameState.LEADER_UID[o])
	g._flush()
	check(g.players[a]["snowball"] == level_before + 1, "Bruno: bater no Líder sobe o nível da Bola de Neve em 1 (%d -> %d)" % [level_before, g.players[a]["snowball"]])

	# Ysvane: Ao Entrar buffs a random ally and takes a Bola de Neve back from the graveyard (banished after its next cast);
	# each glacial spell shields a random ally; death heals the Leader
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	var protege := _put(g, a, "teste_alvo_gelo")
	var bola_in_graveyard := Card.new(g._uid(), "bola_de_neve", a, "graveyard")
	g.players[a]["graveyard"].append(bola_in_graveyard)
	var ysvane_uid := _give(g, a, "ysvane")
	g.play_card(a, ysvane_uid)
	for guard in 8:
		if g.stack.is_empty() or g.phase == "search":
			break
		g.pass_priority(g.priority)
	check(g.phase == "search", "Ysvane: Ao Entrar oferece a Bola de Neve do cemitério (fase %s)" % g.phase)
	g.choose_search(a, bola_in_graveyard.uid)
	g._flush()
	var ysvane_card: Card = g.players[a]["board"].filter(func(c: Card): return c.card_id == "ysvane")[0]
	check(g.players[a]["hand"].has(bola_in_graveyard) and not g.players[a]["graveyard"].has(bola_in_graveyard), "Ysvane: a Bola de Neve volta do cemitério para a mão")
	check(bola_in_graveyard.banish_after_cast, "Ysvane: a Bola recuperada fica marcada para ser banida depois de lançada")
	var shields_on_enter: int = g.players[a]["board"].filter(func(c: Card): return c.shield).size()
	check(shields_on_enter == 1 and protege.hp_left() + ysvane_card.hp_left() == 27, "Ysvane: Ao Entrar dá +2 de Vida e Escudo a uma aliada aleatória (escudos %d, vida %d)" % [shields_on_enter, protege.hp_left() + ysvane_card.hp_left()])
	protege.shield = false
	ysvane_card.shield = false
	var enemy_target := _put(g, o, "teste_alvo_gelo")
	g.play_card(a, bola_in_graveyard.uid, enemy_target.uid)
	for guard in 8:
		if g.stack.is_empty():
			break
		g.pass_priority(g.priority)
	g._flush()
	check(g.players[a]["banished"].has(bola_in_graveyard) and not g.players[a]["graveyard"].has(bola_in_graveyard), "Ysvane: a Bola recuperada é banida depois de lançada, não vai ao cemitério")
	var shielded_count: int = g.players[a]["board"].filter(func(c: Card): return c.shield).size()
	check(shielded_count == 1, "Ysvane: um feitiço glacial dá Escudo a uma aliada aleatória (%d)" % shielded_count)
	g.players[a]["leader_hp"] = 10
	_kill(g, ysvane_card)
	check(g.players[a]["leader_hp"] == 14, "Ysvane: Ao Morrer cura 4 do Líder (%d)" % g.players[a]["leader_hp"])
