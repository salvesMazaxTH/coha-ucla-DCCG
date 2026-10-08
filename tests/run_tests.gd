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
	_test_flavor()
	_test_off_essence()
	_test_death_order()
	_test_setup()
	_test_search()
	_test_freeze()
	_test_constant()
	_test_obscura()
	_test_obscura_rules()
	_test_ban()
	_test_combat()
	_test_triggers()
	_test_stack()
	_test_counter()
	_test_damage_window()
	_test_sim()
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
	return g

func _put(g: GameState, p: int, card_id: String, ready := true) -> Dictionary:
	var uid := g._uid()
	g._summon(p, card_id, uid, false, 0)
	g._flush()
	if g.phase == "search":
		var options: Array = g.pending_search["cards"]
		g.choose_search(p, int(options[0]["uid"]))
		g._flush()
	var c := g.find_unit(uid)
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

func _test_constant() -> void:
	var g := _new_game()
	var jeff := _put(g, 0, "jeff")
	check(g.atk_of(jeff) == 2 and g.hp_left(jeff) == 2, "jeff sem cemitério é 2/2")
	g.players[0]["graveyard"].append({"uid": g._uid(), "card_id": "serpente_marinha"})
	g.players[0]["graveyard"].append({"uid": g._uid(), "card_id": "gaivota_da_tempestade"})
	g.players[0]["graveyard"].append({"uid": g._uid(), "card_id": "bola_de_fogo"})
	g._check_state()
	check(g.atk_of(jeff) == 6 and g.hp_left(jeff) == 6, "jeff +2/+2 por unidade no cemitério (feitiço não conta)")
	g.players[1]["graveyard"].append({"uid": g._uid(), "card_id": "serpente_marinha"})
	g._check_state()
	check(g.atk_of(jeff) == 6, "cemitério inimigo não conta")
	g.players[0]["graveyard"].pop_back()
	g.players[0]["graveyard"].pop_back()
	g._check_state()
	check(g.atk_of(jeff) == 4, "bônus encolhe quando o cemitério encolhe")
	jeff["damage"] = 1
	g.players[0]["graveyard"].clear()
	g._check_state()
	check(g.hp_left(jeff) == 1, "dano persiste ao perder o bônus")

func _obscura_game() -> GameState:
	var g := GameState.new("obscura", "fogo", 7)
	g.mulligan(0, [])
	g.mulligan(1, [])
	return g

## Kills a unit by damage and resolves the deaths (revives and triggers included).
func _test_death_order() -> void:
	# simultaneous deaths on both sides resolve active player first (APNAP)
	for first in 2:
		var g := _new_game()
		g.active = first
		var a := _put(g, 0, "vigia_do_farol_do_norte")
		var b := _put(g, 1, "vigia_do_farol_do_norte")
		a["damage"] = 1000
		b["damage"] = 1000
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

func _kill(g: GameState, c: Dictionary) -> void:
	c["damage"] = 1000
	g._check_state()
	g._flush()

func _count(g: GameState, p: int, card_id: String) -> int:
	return g.players[p]["board"].filter(func(c): return c["card_id"] == card_id).size()

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
	var copies: Array = g.players[0]["board"].filter(func(c): return c["card_id"] == "replicador_maldito" and g.card_of(c)["effects"].is_empty())
	check(copies.size() == 1, "a cópia não tem o efeito")
	# Revivente returns forever, as a new instance
	var rev := _put(g, 0, "revivente_eterno")
	for i in 3:
		var cur: Array = g.players[0]["board"].filter(func(c): return c["card_id"] == "revivente_eterno")
		check(cur.size() == 1, "revivente está em campo (morte %d)" % i)
		_kill(g, cur[0])
	var back: Array = g.players[0]["board"].filter(func(c): return c["card_id"] == "revivente_eterno")
	check(back.size() == 1 and back[0]["uid"] != rev["uid"] and g.atk_of(back[0]) == 2 and g.hp_left(back[0]) == 2, "revivente volta sempre, como nova instância")
	check(not g.players[0]["graveyard"].any(func(e): return e["card_id"] == "revivente_eterno"), "revivente em campo não fica no cemitério")
	# Fênix: back with -2/-2 of what it had; stops at 0
	var fen := _put(g, 0, "fenix_da_chama_profana")
	_kill(g, fen)
	var fb: Array = g.players[0]["board"].filter(func(c): return c["card_id"] == "fenix_da_chama_profana")
	check(fb.size() == 1 and g.atk_of(fb[0]) == 2 and g.hp_left(fb[0]) == 1, "fênix volta com -2/-2")
	_kill(g, fb[0])
	check(_count(g, 0, "fenix_da_chama_profana") == 0, "fênix com 0 de ataque ou vida não volta")
	check(g.players[0]["graveyard"].any(func(e): return e["card_id"] == "fenix_da_chama_profana"), "fênix acaba no cemitério")
	# Titânico: 5/6 Longo Alcance, no Voo, mill 2
	var gy: int = g.players[0]["graveyard"].size()
	var dk: int = g.players[0]["deck"].size()
	var tit := _put(g, 0, "titanico_morcegalma")
	check(g.atk_of(tit) == 5 and g.hp_left(tit) == 6 and g.has_kw(tit, "longo_alcance") and not g.has_kw(tit, "voo"), "titânico 5/6 Longo Alcance sem Voo")
	check(g.players[0]["deck"].size() == dk - 2 and g.players[0]["graveyard"].size() == gy + 2, "titânico mói 2")
	# Necromante revives a unit of cost <= 3
	gy = g.players[0]["graveyard"].size()
	_put(g, 0, "o_espiritomante")
	check(g.players[0]["graveyard"].size() == gy - 1, "necromante reviveu do cemitério")
	# Sacrifice: Cientista kills an ally and draws 1
	g.players[0]["board"].clear()
	var ally := _put(g, 0, "esqueleto_guerreiro")
	var hand: int = g.players[0]["hand"].size()
	var uid := g._uid()
	g._summon(0, "cientista_da_morte", uid, false, ally["uid"])
	g._check_state()
	g._flush()
	check(g.find_unit(ally["uid"]).is_empty(), "cientista sacrificou o aliado")
	check(g.players[0]["hand"].size() == hand + 1, "sacrifício comprou 1 carta")
	check(_count(g, 0, "esqueleto_guerreiro") == 1, "cientista invoca um esqueleto quando um aliado vai ao cemitério")
	# Colheita de Almas: sacrifice -> 4 damage to the enemy leader
	var foe: int = g.players[1]["leader_hp"]
	var fodder := _put(g, 0, "esqueleto_guerreiro")
	var spell := _give(g, 0, "colheita_de_almas")
	g.players[0]["momentum"] = 10
	g.play_card(0, spell, fodder["uid"])
	g._flush()
	check(g.players[1]["leader_hp"] == foe - 4 and g.find_unit(fodder["uid"]).is_empty(), "colheita: sacrifica e causa 4")
	# Alexa Primordial: Ao Entrar heals every damaged ally fully
	var hurt := _put(g, 0, "esqueleto_guerreiro")
	hurt["damage"] = 1
	g.players[0]["momentum"] = 10
	var alx := _give(g, 0, "alexa_neruvya_primordial")
	g.play_card(0, alx, 0)
	g._flush()
	check(hurt["damage"] == 0, "alexa primordial cura todos os aliados")
	# Afogar: rápido, destroys any chosen unit, even one's own, ignoring Escudo
	var af_t := _put(g, 1, "jeff")
	af_t["shield"] = true
	var af_own := _put(g, 0, "esqueleto_guerreiro")
	g.players[0]["momentum"] = 10
	var af1 := _give(g, 0, "afogar")
	g.play_card(0, af1, af_t["uid"])
	g._resolve_stack()
	var af2 := _give(g, 0, "afogar")
	g.play_card(0, af2, af_own["uid"])
	g._resolve_stack()
	g._flush()
	check(g.find_unit(af_t["uid"]).is_empty() and g.find_unit(af_own["uid"]).is_empty(), "afogar destrói a unidade escolhida, inclusive a própria")
	var af_ind := _put(g, 1, "jeff")
	af_ind["keywords"].append("indestrutivel")
	var af3 := _give(g, 0, "afogar")
	g.players[0]["momentum"] = 10
	g.play_card(0, af3, af_ind["uid"])
	g._resolve_stack()
	g._flush()
	check(not g.find_unit(af_ind["uid"]).is_empty(), "afogar não destrói Indestrutível")
	_kill(g, af_ind)
	# Equipment: an artifact attached under the unit; dies with it
	var holder := _put(g, 0, "esqueleto_guerreiro")
	var eqid := _give(g, 0, "manoplas_incandescentes")
	g.players[0]["momentum"] = 10
	var atk0: int = holder["atk"]
	g.play_card(0, eqid, holder["uid"])
	g._resolve_stack()
	g._flush()
	check(CardDB.is_equipment(CardDB.card("manoplas_incandescentes")) and CardDB.is_artifact(CardDB.card("manoplas_incandescentes")), "equipamento é artefato")
	check(holder.get("equipment", {}).get("card_id", "") == "manoplas_incandescentes" and holder["atk"] == atk0 + 2, "equipamento anexado e buff aplicado")
	var gy0: int = g.players[0]["graveyard"].size()
	_kill(g, holder)
	var gy_ids: Array = g.players[0]["graveyard"].map(func(e): return e["card_id"])
	check(g.players[0]["graveyard"].size() == gy0 + 2 and gy_ids.has("manoplas_incandescentes"), "equipamento vai ao cemitério com a unidade")
	# Julgamento da Era Afogada: destroys every unit on both sides, whatever its size
	var jeff := _put(g, 1, "jeff")
	jeff["shield"] = true
	jeff["keywords"].append("indestrutivel")
	var mine := _put(g, 0, "esqueleto_guerreiro")
	var jul := _give(g, 0, "julgamento_da_era_afogada")
	g.players[0]["momentum"] = 10
	g.play_card(0, jul, 0)
	g._resolve_stack()
	g._flush()
	check(not g.find_unit(jeff["uid"]).is_empty() and g.find_unit(mine["uid"]).is_empty(), "julgamento destrói todas as unidades, exceto Indestrutível")
	# damage is always 0 against Indestrutível and does not consume its shield
	var dmg_dealt: int = g._deal_damage(jeff["uid"], 50, {})
	check(dmg_dealt == 0 and g.find_unit(jeff["uid"])["damage"] == 0 and g.find_unit(jeff["uid"])["shield"], "dano contra Indestrutível é sempre 0")
	_kill(g, jeff)
	# Tributo ao Abismo: sacrifice -> mill 3 -> pick one of those 3 from the graveyard
	var ex_fodder := _put(g, 0, "esqueleto_guerreiro")
	var ex := _give(g, 0, "tributo_ao_abismo")
	g.players[0]["momentum"] = 10
	var ex_deck: int = g.players[0]["deck"].size()
	var ex_hand: int = g.players[0]["hand"].size()
	g.play_card(0, ex, ex_fodder["uid"])
	g._flush()
	check(g.phase == "search" and g.pending_search.get("grave", false) and g.pending_search["cards"].size() == 3, "tributo oferece as 3 cartas moídas")
	check(g.players[0]["deck"].size() == ex_deck - 3, "tributo moeu 3")
	var ex_pick: Dictionary = g.pending_search["cards"][1]
	var ex_grave: int = g.players[0]["graveyard"].size()
	check(not g.choose_search(0, int(ex_pick["uid"])).is_empty(), "tributo: escolha aceita")
	check(g.phase != "search" and g.players[0]["graveyard"].size() == ex_grave - 1, "tributo: a carta sai do cemitério")
	check(g.players[0]["hand"].size() == ex_hand - 1 + 1 and not g._hand_card(0, int(ex_pick["uid"])).is_empty(), "tributo: a carta vai à mão")

func _test_obscura_rules() -> void:
	# Diabrete: hits the enemy Leader when another ally dies (not for itself), Ao Morrer too
	var g := _obscura_game()
	g.players[0]["passive_used"] = true
	var dia := _put(g, 0, "diabrete_sombrio")
	check(g.atk_of(dia) == 2 and g.hp_left(dia) == 1 and CardDB.card("diabrete_sombrio")["cost"] == 2, "diabrete 2-drop 2/1")
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
	# Cientista da Morte summons a skeleton on Aliado Morre
	var sg := _obscura_game()
	sg.players[0]["passive_used"] = true
	_put(sg, 0, "cientista_da_morte")
	var sk := _put(sg, 0, "esqueleto_guerreiro")
	var n0: int = _count(sg, 0, "esqueleto_guerreiro")
	_kill(sg, sk)
	check(_count(sg, 0, "esqueleto_guerreiro") == n0, "cientista substitui o esqueleto que foi ao cemitério")
	var sk2 := _put(sg, 0, "esqueleto_guerreiro")
	var sk3 := _put(sg, 0, "esqueleto_guerreiro")
	var n1: int = _count(sg, 0, "esqueleto_guerreiro")
	_kill(sg, sk2)
	_kill(sg, sk3)
	check(_count(sg, 0, "esqueleto_guerreiro") == n1 - 2, "cientista só invoca uma vez por turno (o primeiro já usou o limite)")
	sg.end_turn(0)
	_quiet(sg)
	sg.end_turn(1)
	var sk4: Dictionary = sg.players[0]["board"].filter(func(c): return c["card_id"] == "esqueleto_guerreiro")[0]
	var n2: int = _count(sg, 0, "esqueleto_guerreiro")
	_kill(sg, sk4)
	check(_count(sg, 0, "esqueleto_guerreiro") == n2, "cientista volta a invocar no turno seguinte")
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

	# Vagante Sombria: cost drops with the own graveyard, indestructible
	var v := _obscura_game()
	var vag: Dictionary = CardDB.card("a_vagante_sombria")
	check(v.cost_of(0, vag) == 12, "vagante custa 12 com cemitério vazio")
	for i in 5:
		v.players[0]["graveyard"].append({"uid": v._uid(), "card_id": "esqueleto_guerreiro"})
	check(v.cost_of(0, vag) == 7, "vagante custa 1 a menos por carta no cemitério")
	for i in 20:
		v.players[0]["graveyard"].append({"uid": v._uid(), "card_id": "cova_rasa"})
	check(v.cost_of(0, vag) == 0, "custo nunca fica abaixo de 0")
	check(v.cost_of(1, vag) == 12, "cemitério inimigo não reduz")
	var vc := _put(v, 0, "a_vagante_sombria")
	v._apply(1, {"action": "damage", "target": "any", "amount": 99}, vc["uid"])
	check(not v.find_unit(vc["uid"]).is_empty() and vc["damage"] == 0, "vagante ignora dano")
	var fresh := _obscura_game()
	fresh.players[0]["passive_used"] = true
	var vc2 := _put(fresh, 0, "a_vagante_sombria")
	var sc := _give(fresh, 0, "colheita_de_almas")
	fresh.players[0]["momentum"] = 10
	fresh.play_card(0, sc, vc2["uid"])
	fresh._flush()
	check(fresh.find_unit(vc2["uid"]).is_empty(), "sacrifício ainda mata a vagante")

	# Necrófago additional cost: sacrifice an ally you control (the AI pays with its weakest)
	var n := _obscura_game()
	n.players[0]["passive_used"] = true
	var nid := _give(n, 0, "necrofago_espectral")
	n.players[0]["momentum"] = 0
	check(not n.can_play(0, nid), "necrófago exige uma unidade para sacrificar")
	var weak := _put(n, 0, "esqueleto_guerreiro")
	var strong := _put(n, 0, "titanico_morcegalma")
	check(n.can_play(0, nid), "necrófago custa 0 com um aliado para sacrificar")
	check(n.card_spec(CardDB.card("necrofago_espectral")) == "ally_unit", "necrófago pede um alvo aliado")
	check(n.play_card(0, nid, 0).is_empty(), "necrófago sem alvo de sacrifício não entra")
	n.play_card(0, nid, weak["uid"])
	n._flush()
	check(n.find_unit(weak["uid"]).is_empty() and _count(n, 0, "necrofago_espectral") == 1 and not n.find_unit(strong["uid"]).is_empty(), "necrófago sacrificou o escolhido e entrou")
	check(n.players[0]["graveyard"].any(func(e): return e["card_id"] == "esqueleto_guerreiro"), "o sacrificado foi ao cemitério")
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

func _test_freeze() -> void:
	var g := _new_game()
	var atk := _put(g, 0, "kai")
	var f := _put(g, 1, "tritao_lanceiro")
	g._apply(0, {"action": "freeze", "target": "enemy_unit"}, f["uid"])
	check(g.is_frozen(f), "congelar marca a unidade")
	check(not g.can_block(f, atk), "congelada não bloqueia")
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and g.is_frozen(f) and not g.can_attack(f), "congelada não ataca no próximo turno do dono")
	_quiet(g)
	g.end_turn(1)
	check(not g.is_frozen(f), "descongela no fim do próximo turno do dono")
	var s := _put(g, 1, "tritao_lanceiro")
	s["spell_shield"] = true
	g._apply(0, {"action": "freeze", "target": "enemy_unit"}, s["uid"])
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
	check(g.find_unit(b["uid"]).is_empty(), "first strike kills blocker")
	check(not g.find_unit(a["uid"]).is_empty(), "first striker survives")

	g = _new_game()
	var t := _put(g, 0, "kael_drath_vulcano") # 5/7 sobrepujança
	var s := _put(g, 1, "espirito_da_mare") # 1/2 escudo
	var hp: int = g.players[1]["leader_hp"]
	_attack(g, {t["uid"]: 0})
	_block(g, {t["uid"]: s["uid"]})
	check(not g.find_unit(s["uid"]).is_empty(), "shield absorbs hit")
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
	check(g.find_unit(v["uid"]).is_empty(), "provoked unit forced to block")
	g.end_turn(0)
	check(g.find_unit(k["uid"])["damage"] == 0, "damage resets at end of turn")

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
	_tspell("t_inst_hp", "instantaneo", [{"trigger": "on_play", "action": "buff", "target": "ally_unit", "hp": 3}])
	_tspell("t_inst_kill", "instantaneo", [{"trigger": "on_play", "action": "damage", "target": "any_unit", "amount": 9}])
	_tspell("t_fast", "rapido", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 1}])

	# response resolves first (LIFO): +3 HP lands before the 2 damage
	var g := _new_game()
	g.players[0]["momentum"] = 5
	var foe := _put(g, 1, "t_wall2")
	var lab := _give(g, 0, "labareda")
	var inst := _give(g, 1, "t_inst_hp")
	g.play_card(0, lab, foe["uid"])
	check(g.stack.size() == 1 and g.priority == 1, "spell goes on the stack, opponent gets priority")
	check(g.find_unit(foe["uid"])["damage"] == 0, "spell waits on the stack")
	check(not g.can_play(1, _give(g, 1, "lanca_das_mares")), "lento cannot respond")
	g.play_card(1, inst, foe["uid"])
	check(g.stack.size() == 2 and g.priority == 0, "instant response stacks and passes priority back")
	g.pass_priority(0)
	var fc := g.find_unit(foe["uid"])
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
	check(g.stack.is_empty() and g.find_unit(foe["uid"]).is_empty(), "auto-pass when opponent has no response")

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
	check(g.find_unit(kai["uid"])["damage"] == 1 and g.priority == 1 and g.window == "prepare", "after resolving, window owner gets priority back")
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
	check(g.players[1]["hand"].size() == hn + 1 and not wall.has("tide_mark"), "marked unit survived damage -> draw 1")
	g._deal_damage(wall["uid"], 1, {})
	check(g.players[1]["hand"].size() == hn + 1, "mark draws only once")

func _test_damage_window() -> void:
	_tcard("t_a22", 2, 2, [])
	_tcard("t_tr22", 2, 2, [])
	CardDB.data()["cards"]["t_tr22"]["keywords"] = ["sobrepujanca"]
	_tcard("t_b12", 1, 2, [])
	_tspell("t_kill", "instantaneo", [{"trigger": "on_play", "action": "damage", "target": "any_unit", "amount": 9}])
	_tspell("t_pump", "rapido", [{"trigger": "on_play", "action": "buff", "target": "ally_unit", "atk": 3, "temp": true}])

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
	check(g.find_unit(bl["uid"]).is_empty() and not g.find_unit(at["uid"]).is_empty(), "post-block pump kills the blocker, attacker survives")

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
	check(g.find_unit(bl["uid"]).is_empty() and g.players[1]["leader_hp"] == hp0, "blocks are final: no leader damage")
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
	check(g.phase == "main" and g.find_unit(at["uid"]).is_empty(), "attacker killed, combat over")
	check(g.find_unit(bl["uid"])["damage"] == 0, "blocker untouched")

## No momentum and no leader ability, so only test cards give plays.
func _quiet(g: GameState) -> void:
	for p in 2:
		g.players[p]["momentum"] = 0
		g.players[p]["ability_used"] = true

func _tcard(id: String, atk: int, hp: int, effects: Array) -> void:
	CardDB.data()["cards"][id] = {"name": id, "type": "unit", "rarity": "common", "essence": "neutra", "cost": 1,
		"atk": atk, "hp": hp, "keywords": [], "art": "", "effects": effects, "text": "", "flavor": "", "tags": []}

func _test_triggers() -> void:
	_tcard("t_atk", 1, 5, [{"trigger": "on_attack", "action": "damage", "target": "enemy_leader", "amount": 2}])
	_tcard("t_blk", 1, 5, [{"trigger": "on_block", "action": "buff", "target": "self", "atk": 3, "temp": true}])
	_tcard("t_turn", 1, 5, [{"trigger": "on_turn_end", "action": "buff", "target": "self", "atk": 1, "hp": 1}])
	_tcard("t_hurt", 1, 9, [{"trigger": "on_damaged", "action": "damage", "target": "opposed_unit", "amount": 1}])
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
	check(g.find_unit(bl["uid"]).get("temp_atk", 0) == 3 or g.find_unit(bl["uid"]).is_empty(), "on_block fires")

	g = _new_game()
	var tt := _put(g, 0, "t_turn")
	g.end_turn(0)
	check(g.find_unit(tt["uid"])["atk"] == 2 and g.find_unit(tt["uid"])["hp"] == 6, "on_turn_end fires")

	g = _new_game()
	var h := _put(g, 1, "t_hurt")
	g._deal_damage(h["uid"], 1, {})
	check(g.find_unit(h["uid"])["damage"] == 1, "on_damaged no-source safe")

	# Cartas reais: Dlorafya, Salamandra, Espírito da Maré, Ronan
	g = _new_game()
	var ally := _put(g, 0, "kai")
	var foe := _put(g, 1, "sentinela_coral") # 1/4
	var foe2 := _put(g, 1, "tritao_lanceiro") # 2/2
	var d := _put(g, 0, "dlorafya")
	check(g.find_unit(ally["uid"])["damage"] == 1, "dlorafya: ally igneo takes 1")
	g._check_state()
	check(g.find_unit(foe["uid"])["damage"] == 3 and g.find_unit(foe2["uid"]).is_empty(), "dlorafya: enemies take 3")
	check(g.find_unit(d["uid"])["damage"] == 1, "dlorafya: self takes 1")

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
	check(g.find_unit(blk["uid"]).is_empty(), "lorde Ao Ser Bloqueada: 2 + 5 combat kills 7/7")

	g = _new_game()
	var kai2 := _put(g, 0, "kai")
	var sp := _put(g, 1, "tritao_lanceiro")
	_attack(g, {kai2["uid"]: 0})
	_block(g, {kai2["uid"]: sp["uid"]})
	check(g.find_unit(kai2["uid"]).get("damage", 0) <= 1, "tritao Ao Bloquear hits attacker")

	g = _new_game()
	var ron := _put(g, 0, "ronan")
	g._deal_damage(ron["uid"], 1, {})
	check(g.find_unit(ron["uid"])["atk"] == 5, "ronan Ao Sofrer Dano +1 atk")

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
		hit += int(g.find_unit(w["uid"])["damage"])
	check(hit >= 2 and hit <= 3, "estrondador AoE hits random + adjacent (%d)" % hit)

	# Fênix Menor: dies, revives as 1/1 with no effects
	g = _new_game()
	var f := _put(g, 0, "fenix_menor")
	check(f["atk"] == 2 and f["hp"] == 1, "fenix is 2/1")
	g._deal_damage(f["uid"], 5, {})
	g._check_state()
	check(g.find_unit(f["uid"]).is_empty(), "fenix original died")
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

func _test_ban() -> void:
	# Overdraw is kept in hand; at the end of the owner's turn they choose what to ban
	var g := _new_game()
	var pl: Dictionary = g.players[0]
	while pl["hand"].size() < GameState.HAND_LIMIT:
		pl["hand"].append({"uid": g._uid(), "card_id": "kai"})
	var gy: int = pl["graveyard"].size()
	g._draw(0, 2)
	g._flush()
	check(pl["hand"].size() == GameState.HAND_LIMIT + 2, "comprar com a mão cheia mantém as cartas na mão")
	_quiet(g)
	g.end_turn(0)
	check(g.phase == "discard", "mão acima de 10 pede banimento no fim do turno")
	var pick: Array = [pl["hand"][0]["uid"], pl["hand"][1]["uid"]]
	check(g.discard(0, [pick[0]]).is_empty(), "banir menos que o necessário é recusado")
	var ev: Array = g.discard(0, pick)
	check(pl["hand"].size() == GameState.HAND_LIMIT and pl["banished"].size() == 2, "baniu até 10 cartas")
	check(pl["graveyard"].size() == gy, "carta banida não vai ao cemitério")
	check(ev.any(func(e): return e["type"] == "ban") and not ev.any(func(e): return e["type"] == "discard"), "evento ban")
	# the opponent never sees what was banished from the hand
	var snap: Dictionary = StateView.snapshot(g, 1)
	check(snap["players"][0]["banished"].all(func(c): return c["card_id"] == ""), "oponente não vê as cartas banidas da mão")
	check(StateView.snapshot(g, 0)["players"][0]["banished"].all(func(c): return c["card_id"] != ""), "o dono vê as próprias banidas")
