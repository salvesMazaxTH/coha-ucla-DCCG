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
	_test_art_crop()
	_test_sfx()
	_test_off_essence()
	_test_naelys_leader()
	_test_secondary_essences()
	_test_death_order()
	_test_sacrifice_damage()
	_test_spell_shield_scope()
	_test_supreme_shield()
	_test_limited_charges()
	_test_artifact_subtypes()
	_test_twin_bolts()
	_test_setup()
	_test_first_player()
	_test_concede()
	_test_search()
	_test_freeze()
	_test_stun_and_cap()
	_test_burn()
	_test_condemn()
	_test_constant()
	_test_obscura()
	_test_vegetal()
	_test_ai_spell_preview()
	_test_obscura_rules()
	_test_cleanse()
	_test_sagrada_board_control()
	_test_eletrica()
	_test_intimidacao()
	_test_play_slot()
	_test_ossuario()
	_test_yresa_fusion()
	_test_glacial()
	_test_glacial_combo()
	_test_gertrudes()
	_test_myrra_activate()
	_test_hoje_ninguem_erra()
	_test_devaneio_permanent()
	_test_metalica()
	_test_deslizamento()
	_test_self_response()
	_test_custo_e_contagem()
	_test_ban()
	_test_combat()
	_test_toque_letal()
	_test_toxico()
	_test_leader_poison()
	_test_veneno_hold()
	_test_veneno_lethal()
	_test_hulglack_death_freeze()
	_test_venenosa_deck()
	_test_hikari_decoy()
	_test_dot_immunity()
	_test_provocacao()
	_test_persistent_damage()
	_test_triggers()
	_test_listeners()
	_test_stack()
	_test_reaction()
	_test_summon_window()
	_test_subito()
	_test_combat_step()
	_test_leader_cycle()
	_test_enter_target()
	_test_ai_enter_damage()
	_test_ai_armor_ability()
	_test_ai_incarnation_priority()
	_test_incarnation_retire()
	_test_fatigue()
	_test_naelys_bounce_discount()
	_test_counter()
	_test_fight()
	_test_conditional_counter()
	_test_reserve()
	_test_challenge_triggers()
	_test_strike_order()
	_test_critico()
	_test_critico_temp()
	_test_double_attack()
	_test_dying_card_filter()
	_test_critico_data()
	_test_overkill()
	_test_dud()
	_test_ai_no_waste()
	_test_ai_attack_clauses()
	_test_ai_burn_plan()
	_test_requiem()
	_test_rusco()
	_test_elite_limits()
	_test_armor()
	_test_tharox_armor_growth()
	_test_isarelis_hit_leader()
	_test_silence_and_david()
	_test_silence_keeps_ally_auras()
	_test_tech_cards()
	_test_vorn_staged_damage()
	_test_adjacent_armor()
	_test_sagrada_engine()
	_test_maria_helena()
	_test_champion_rework()
	_test_momentum_overflow()
	_test_eryon_deck()
	_test_ralia_deal_damage()
	_test_play_restrictions()
	_test_cortina_de_fumaca()
	_test_sim()
	for e in CardDB.errors():
		check(false, e)
	_test_card_validation()
	# the golden replays are NOT run here: every card/deck balance change would break them.
	# Run tests/golden_check.gd by hand before committing an engine/rules change.
	print("tests done, failures: ", failures)
	quit(1 if failures > 0 else 0)

## (The Sfx autoload does not exist in -s mode, so the script is loaded directly; its table and mapping are static.)
## Any spell card: effects run with it as their source count as coming from a spell (Escudo de Feitiço cancels them)
const SPELL_SOURCE := "lianas_capturantes"
const SfxScript := preload("res://scripts/audio/sfx.gd")
const MusicScript := preload("res://scripts/audio/music.gd")

## Sound effects: every file in the SOUNDS table exists, and engine events map to the sound that fits.
func _test_sfx() -> void:
	for sound_name in SfxScript.SOUNDS:
		for file_name in SfxScript.SOUNDS[sound_name]["files"]:
			check(ResourceLoader.exists(SfxScript.sound_path(file_name)), "sfx %s: arquivo %s não existe" % [sound_name, file_name])
	check(SfxScript.sound_for_event({"type": "damage", "amount": 3, "src": 5}, true) == "hit_light", "sfx: golpe de combate leve")
	check(SfxScript.sound_for_event({"type": "damage", "amount": 7, "src": 5}, true) == "hit_heavy", "sfx: golpe de combate pesado")
	check(SfxScript.sound_for_event({"type": "damage", "amount": 3, "src": 5}, false) == "direct_damage", "sfx: dano de efeito fora do combate")
	check(SfxScript.sound_for_event({"type": "damage", "amount": 0, "src": 5}, true) == "", "sfx: dano zero é silencioso")
	check(SfxScript.sound_for_event({"type": "heal", "amount": 2}, false) == "heal", "sfx: cura")
	check(SfxScript.sound_for_event({"type": "draw"}, false) == "card_draw", "sfx: compra de carta")
	check(SfxScript.sound_for_event({"type": "banish"}, false) == "banish", "sfx: banimento")
	check(SfxScript.sound_for_event({"type": "mulligan"}, false) == "card_fan", "sfx: mulligan")
	check(SfxScript.sound_for_event({"type": "play", "card_id": "alexa_neruvya"}, false) == "card_place", "sfx: jogar unidade")
	check(SfxScript.sound_for_event({"type": "play", "card_id": "afogar"}, false) == "spell_cast", "sfx: jogar feitiço")
	check(SfxScript.sound_for_event({"type": "play", "card_id": "pingente_das_ondas"}, false) == "relic", "sfx: jogar artefato")
	check(SfxScript.sound_for_event({"type": "buff", "atk": 0, "hp": 0}, false) == "", "sfx: buff vazio é silencioso")
	check(SfxScript.sound_for_event({"type": "tipo_que_nao_existe"}, false) == "", "sfx: evento desconhecido é silencioso")
	check(SfxScript.sound_for_event({"type": "passive", "player": 0}, false) == "", "sfx: passiva de Líder (início de turno) é silenciosa")
	check(SfxScript.sound_for_event({"type": "ability", "player": 0}, false) == "", "sfx: poder de Líder é silencioso")
	check(not SfxScript.SOUNDS.has("ability"), "sfx: o som do poder foi removido da tabela")
	check(float(SfxScript.SOUNDS["card_shuffle"].get("speed", 1.0)) == 2.25, "sfx: embaralhar do início da partida toca 2,25x mais rápido")
	# the match music is a separate autoload with its own settings, apart from the effects
	var total_plays := 0
	for step in MusicScript.ROTEIRO:
		check(load(step["path"]) is AudioStreamOggVorbis, "música: %s existe e é um OGG" % step["path"])
		total_plays += int(step["plays"])
	check(MusicScript.ROTEIRO.size() == 4 and total_plays == 5, "música: roteiro de 4 faixas (chefe 1x, Winter Dust 2x, duas do CSA legado 1x cada)")
	check(MusicScript.SETTINGS_PATH == SfxScript.SETTINGS_PATH, "música: salva no mesmo arquivo de configurações dos efeitos")
	check(SfxScript.DEFAULT_VOLUME == 0.5 and MusicScript.DEFAULT_VOLUME == 0.5, "áudio: efeitos e música começam em 50%")
	check(MusicScript.DEFAULT_VOLUME > 0.0 and MusicScript.DEFAULT_VOLUME < 1.0, "música: volume padrão fica no meio do slider")

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

func _new_game(seed_value := 42) -> GameState:
	var g := GameState.new("fogo", "agua", seed_value)
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
## Purificar: Luz Transbordante tira os marcadores do Líder e de uma unidade; o Ao Entrar do Mefi'Urdim tira os do Líder e dos aliados que ele buffa.
func _test_cleanse() -> void:
	var g := _new_game()
	g.players[0]["leader_dots"] = {"veneno": 3}
	g.players[0]["leader_hp"] -= 5
	var light := Card.new(g._uid(), "luz_transbordante", 0, "hand")
	g.players[0]["hand"].append(light)
	g.players[0]["momentum"] = 10
	g.play_card(0, light.uid, GameState.LEADER_UID[0])
	g._flush()
	check(g.leader_dot_markers(0, "veneno") == 0, "Luz Transbordante purifica o Líder")
	var ally := _put(g, 0, "esqueleto_guerreiro")
	ally.dot_markers = {"veneno": 2, "queimadura": 1}
	var light2 := Card.new(g._uid(), "luz_transbordante", 0, "hand")
	g.players[0]["hand"].append(light2)
	g.play_card(0, light2.uid, ally.uid)
	g._flush()
	check(ally.dot_markers.is_empty(), "Luz Transbordante purifica a unidade alvo")
	g.players[0]["leader_dots"] = {"veneno": 4}
	var angel := _put(g, 0, "uriel")
	angel.dot_markers = {"veneno": 2}
	_put(g, 0, "mefi_urdim")
	check(g.leader_dot_markers(0, "veneno") == 0, "Mefi'Urdim purifica o Líder ao entrar")
	check(angel.dot_markers.is_empty(), "Mefi'Urdim purifica as unidades que ele buffa")

func _test_sagrada_board_control() -> void:
	# Seymour, o limpador: curas e feitiços Sagrados causam 1 de dano duas vezes,
	# cada uma a uma unidade inimiga aleatória
	var g := _new_game()
	var foe := _put(g, 1, "estrondador_igneo")
	_put(g, 0, "seymour")
	g.players[0]["leader_hp"] -= 6
	g._heal_leader(0, 2)
	g._check_state()
	check(g.find_unit(foe.uid).damage == 2, "Seymour reage à cura do Líder: 2 pontos de dano distribuídos (sobrou %d)" % g.find_unit(foe.uid).damage)
	var ally := _put(g, 0, "esqueleto_guerreiro")
	ally.damage = 1
	var light := Card.new(g._uid(), "luz_transbordante", 0, "hand")
	g.players[0]["hand"].append(light)
	g.players[0]["momentum"] = 10
	g.play_card(0, light.uid, ally.uid)
	g._check_state()
	# Luz Transbordante é feitiço Sagrado (+1) e cura uma aliada (+1)
	check(g.find_unit(foe.uid) == null, "Seymour reage a cura de aliado e a feitiço Sagrado (a 2ª condicional do turno, mais 2 pontos de dano, mata a inimiga)")
	var g_start := _new_game()
	var start_foe := _put(g_start, 1, "estrondador_igneo")
	var seymour_start := _put(g_start, 0, "seymour")
	g_start.active = 0
	g_start.bus().emit(_turn_start_event(g_start, seymour_start))
	g_start._check_state()
	check(g_start.find_unit(start_foe.uid).damage == 0, "Seymour não causa dano no início do turno")
	# as condicionais ativam no máximo 2x por turno: a 3ª não faz nada
	var g_cap := _new_game()
	var cap_foe := _put(g_cap, 1, "anciao_do_primeiro_bosque")
	var seymour_cap := _put(g_cap, 0, "seymour")
	g_cap.active = 0
	g_cap.players[0]["leader_hp"] -= 6
	g_cap.bus().emit(_turn_start_event(g_cap, seymour_cap))
	g_cap._heal_leader(0, 1)
	g_cap._heal_leader(0, 1)
	g_cap._check_state()
	check(g_cap.find_unit(cap_foe.uid).damage == 4, "Seymour: 2 curas condicionais causam 4 de dano (deu %d)" % g_cap.find_unit(cap_foe.uid).damage)
	g_cap._heal_leader(0, 1)
	g_cap._check_state()
	check(g_cap.find_unit(cap_foe.uid).damage == 4, "Seymour: a 3ª condicional no mesmo turno não causa dano")
	# no turno seguinte do dono o contador volta a zero
	g_cap.turn += 2
	g_cap._heal_leader(0, 1)
	g_cap._check_state()
	check(g_cap.find_unit(cap_foe.uid).damage == 6, "Seymour: em outro turno ele volta a ativar")
	# só age no turno do dono: cura durante o turno do oponente não faz nada
	var g_theirs := _new_game()
	var theirs_foe := _put(g_theirs, 1, "estrondador_igneo")
	_put(g_theirs, 0, "seymour")
	g_theirs.active = 1
	g_theirs.players[0]["leader_hp"] -= 3
	g_theirs._heal_leader(0, 1)
	g_theirs._check_state()
	check(g_theirs.find_unit(theirs_foe.uid).damage == 0, "Seymour não reage a cura no turno do oponente")
	# sem unidade inimiga, não acontece nada
	var g_empty := _new_game()
	_put(g_empty, 0, "seymour")
	g_empty._heal_leader(0, 1)
	g_empty._check_state()
	var g_small := _new_game()
	var small_foe := _put(g_small, 1, "salamandra")
	var small_foe_two := _put(g_small, 1, "salamandra")
	_put(g_small, 0, "seymour")
	g_small.players[0]["leader_hp"] -= 3
	g_small._heal_leader(0, 1)
	g_small._check_state()
	check(g_small.find_unit(small_foe.uid) == null or g_small.find_unit(small_foe_two.uid) == null, "Seymour: a cura mata ao menos uma salamandra de 1 de Vida")
	# Lucien: 2 de dano a até 3 unidades inimigas diferentes ao entrar
	_tcard("t_lucien_target", 0, 10, [])
	var g2 := _new_game()
	var lucien_targets: Array = []
	for i in 5:
		lucien_targets.append(_put(g2, 1, "t_lucien_target"))
	_put(g2, 0, "lucien")
	g2._check_state()
	var damaged_by_lucien: Array = lucien_targets.filter(func(unit: Card): return unit.damage > 0)
	check(damaged_by_lucien.size() == 3 and damaged_by_lucien.all(func(unit: Card): return unit.damage == 2),
		"Lucien causa 2 de dano a 3 unidades diferentes, sem distribuir os pontos (%d alvos)" % damaged_by_lucien.size())
	_put(g2, 0, "uriel")
	g2._check_state()
	check(lucien_targets.filter(func(unit: Card): return unit.damage > 0).size() == 3,
		"Uriel não causa dano ao entrar")
	var uriel_data: Dictionary = CardDB.card("uriel")
	check(int(uriel_data["atk"]) == 5 and int(uriel_data["hp"]) == 6
		and not uriel_data["keywords"].has("roubo_de_vida"), "Uriel é 5/6 e não tem Roubo de Vida inato")
	var uriel_game := _new_game()
	_quiet(uriel_game)
	uriel_game.players[0]["leader_hp"] = 10
	var uriel := _put(uriel_game, 0, "uriel")
	check(uriel_game.players[0]["leader_hp"] == 10, "Uriel não tem Ao Entrar")
	_hit(uriel_game, uriel)
	uriel_game._flush()
	check(uriel_game.players[0]["leader_hp"] == 14,
		"Uriel cura 4 do Líder ao atacar, sem Roubo de Vida adicional (%d)" % uriel_game.players[0]["leader_hp"])
	# Nerithia: Ímpeto, e o Ao Desafiar dá sempre ao menos +2 de Ataque
	var g3 := _new_game()
	var nerithia := _put(g3, 0, "nerithia")
	check(g3.has_kw(nerithia, "impeto") and not g3.has_kw(nerithia, "provocacao"), "Nerithia tem Ímpeto e não tem Provocação")
	var challenge_buff := BuffEffect.new()
	challenge_buff.setup({"action": "buff", "target": "self", "copy_atk": "highest_ally", "copy_atk_min_gain": 2, "temp": true})
	challenge_buff.apply(EffectContext.new(g3, 0), nerithia.uid)
	check(g3.atk_of(nerithia) == 4, "Nerithia ganha ao menos +2 de Ataque ao Desafiar, mesmo sem aliada mais forte (Ataque %d)" % g3.atk_of(nerithia))

func _turn_start_event(g: GameState, unit: Card) -> GameEvent:
	return GameEvent.new("on_turn_start", unit.owner, unit)

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

## Escudo de Feitiço only cancels what comes from a spell or from a Leader's ability.
func _test_spell_shield_scope() -> void:
	_tcard("t_ss_enter", 1, 1, [{"trigger": "on_enter", "action": "damage", "target": "enemy_unit", "amount": 2}])
	_tcard("t_ss_foe", 1, 9, [])
	# a unit's own effect (Ao Entrar) goes through and the shield stays
	var g := _new_game()
	_quiet(g)
	var foe := _put(g, 1, "t_ss_foe")
	foe.spell_shield = true
	g._run_effect_dicts(0, CardDB.card("t_ss_enter")["effects"], "on_enter", foe.uid, 999)
	check(foe.damage == 2 and foe.spell_shield, "Escudo de Feitiço não anula o Ao Entrar de uma unidade (e não se gasta)")
	# the same effect coming from a spell is cancelled
	g._run_effect_dicts(0, CardDB.card("t_ss_enter")["effects"], "on_enter", foe.uid, 0, SPELL_SOURCE)
	check(foe.damage == 2 and not foe.spell_shield, "o mesmo efeito vindo de um feitiço é anulado")
	# an artifact is not a spell
	var artifact_context := EffectContext.new(g, 0, "")
	artifact_context.source_card_id = "baluarte_santo"
	check(not artifact_context.comes_from_spell_or_leader_ability(), "artefato não conta como feitiço para o Escudo de Feitiço")
	# the Leader's ability reads as a spell
	g = _new_game() # fogo: Ronan's Pavio Curto
	_quiet(g)
	var ability_victim := _put(g, 1, "t_ss_foe")
	ability_victim.spell_shield = true
	g.players[0]["ability_used"] = false
	g.players[0]["momentum"] = 5
	g.use_ability(0, ability_victim.uid)
	g.pass_priority(1)
	g._flush()
	check(not ability_victim.spell_shield and ability_victim.damage == 0, "Escudo de Feitiço anula a Habilidade de Líder")
	# the "then" effects of a spell keep the spell origin: Mordida de Defunto's damage is cancelled too
	g = _new_game()
	_quiet(g)
	var sacrificed := _put(g, 0, "esqueleto_guerreiro")
	var shielded_foe := _put(g, 1, "t_ss_foe")
	shielded_foe.spell_shield = true
	var bite := Card.new(g._uid(), "mordida_de_defunto", 0, "hand")
	g.players[0]["hand"].append(bite)
	g.players[0]["momentum"] = 10
	g.play_card(0, bite.uid, sacrificed.uid, shielded_foe.uid)
	g.pass_priority(1)
	g._flush()
	check(g.find_unit(sacrificed.uid) == null and shielded_foe.damage == 0 and not shielded_foe.spell_shield, "o dano do 'então' de um feitiço de sacrifício também é anulado pelo Escudo de Feitiço")

## Escudo Supremo: one charge that absorbs damage and any effect, from any source, including sacrifice.
func _test_supreme_shield() -> void:
	_tcard("t_sup_unit", 1, 9, [])
	_tcard("t_sup_hit", 1, 1, [{"trigger": "on_enter", "action": "damage", "target": "enemy_unit", "amount": 2}])
	var g := _new_game()
	_quiet(g)
	# a unit's own effect (which Escudo de Feitiço lets through) is absorbed, and the charge is spent
	var holder := _put(g, 1, "t_sup_unit")
	holder.grant_supreme_shield()
	g._run_effect_dicts(0, CardDB.card("t_sup_hit")["effects"], "on_enter", holder.uid, 999)
	check(holder.damage == 0 and not holder.supreme_shield, "Escudo Supremo absorve o efeito de uma unidade e se gasta")
	# plain damage (a direct hit, not an effect) is absorbed as well
	holder.grant_supreme_shield()
	check(g._deal_damage(holder.uid, 3, null) == 0 and holder.damage == 0 and not holder.supreme_shield, "Escudo Supremo absorve dano comum")
	# a destroy effect from a spell is absorbed
	holder.grant_supreme_shield()
	g._apply_effect(0, {"action": "destroy", "target": "enemy_unit"}, holder.uid, SPELL_SOURCE)
	check(g.find_unit(holder.uid) != null and not holder.supreme_shield, "Escudo Supremo absorve destruir")
	# it even absorbs the owner's own sacrifice: nobody dies and the charge is spent
	holder.grant_supreme_shield()
	g._apply_effect(1, {"action": "sacrifice", "target": "ally_unit"}, holder.uid, SPELL_SOURCE)
	check(g.find_unit(holder.uid) != null and not holder.supreme_shield, "Escudo Supremo absorve até o sacrifício do próprio dono")
	# the charge is gone: the next hit lands
	g._deal_damage(holder.uid, 3, null)
	check(holder.damage == 3, "sem a carga, o dano passa")
	# expiry: end_turn goes at the end of the turn, next_turn at the start of the controller's next turn
	holder.grant_supreme_shield("end_turn")
	g._finish_turn()
	check(not holder.supreme_shield, "Escudo Supremo 'neste turno' acaba no fim do turno")
	holder.grant_supreme_shield("next_turn")
	holder.grant_supreme_shield("end_turn") # a shorter grant never shortens a longer charge
	check(holder.supreme_shield_expires == "next_turn", "conceder um Supremo mais curto não encurta o que já existe")
	holder.grant_supreme_shield()
	holder.grant_supreme_shield("end_turn")
	check(holder.supreme_shield_expires == "", "um Supremo temporário não encurta o permanente")
	# Silenciar removes it
	holder.silence()
	check(not holder.supreme_shield, "silenciar remove o Escudo Supremo")
	# save and restore keep the charge and its length
	holder.grant_supreme_shield("next_turn")
	var restored := Card.from_dict(holder.to_dict(), "board", 1)
	check(restored.supreme_shield and restored.supreme_shield_expires == "next_turn", "Escudo Supremo sobrevive ao to_dict/from_dict")
	# a free-standing artifact (Baluarte Santo) is born with it and survives Desmontador de Quinquilharia
	g = _new_game()
	_quiet(g)
	var bulwark := Card.new(g._uid(), "baluarte_santo", 0)
	g._place_relic(0, bulwark)
	g._flush()
	check(bulwark.supreme_shield, "Baluarte Santo nasce com Escudo Supremo")
	g._run_effect_dicts(1, CardDB.card("desmontador_de_quinquilharia")["effects"], "on_enter", bulwark.uid, 999)
	g._flush()
	check(g.find_relic(bulwark.uid) != null and not bulwark.supreme_shield, "Desmontador de Quinquilharia não destrói o Baluarte Santo: só gasta o Escudo Supremo")
	g._run_effect_dicts(1, CardDB.card("desmontador_de_quinquilharia")["effects"], "on_enter", bulwark.uid, 999)
	g._flush()
	check(g.find_relic(bulwark.uid) == null, "sem o Escudo Supremo, o segundo Desmontador destrói o Baluarte")

func _test_limited_charges() -> void:
	# Ampola Curativa: 2 usos; cura o Líder ao sofrer dano e a unidade aliada que sofrer dano e sobreviver
	var g := _new_game()
	_quiet(g)
	var vial := Card.new(g._uid(), "ampola_curativa", 0)
	g._place_relic(0, vial)
	g._flush()
	check(vial.charges_left() == 2, "Ampola Curativa começa com 2 usos")
	check(Card.from_dict(vial.to_dict(), "relics", 0).charges_left() == 2, "usos intactos no to_dict/from_dict")
	var leader_uid: int = GameState.LEADER_UID[0]
	g.players[0]["leader_hp"] -= 6
	var leader_before: int = g.players[0]["leader_hp"]
	g._deal_damage(leader_uid, 3, null)
	g._check_state()
	g._flush()
	check(g.players[0]["leader_hp"] == leader_before - 3 + 2, "Ampola cura 2 do Líder que sofreu dano")
	check(vial.charges_left() == 1, "a cura do Líder gastou 1 uso")
	check(Card.from_dict(vial.to_dict(), "relics", 0).charges_left() == 1, "usos gastos sobrevivem ao to_dict/from_dict")
	# a lethal hit on an ally unit does not trigger it; a surviving hit does
	var tough := _put(g, 0, "vigia_do_farol_do_norte")
	g._deal_damage(tough.uid, 1000, null)
	g._check_state()
	g._flush()
	check(vial.charges_left() == 1 and g.find_relic(vial.uid) != null, "golpe letal em unidade aliada não gasta uso")
	var survivor := _put(g, 0, "sentinela_coral")
	var survivor_hp := survivor.hp_left()
	g._deal_damage(survivor.uid, 1, null)
	g._check_state()
	g._flush()
	check(survivor.hp_left() == survivor_hp, "Ampola cura a unidade aliada que sofreu dano e sobreviveu")
	check(g.find_relic(vial.uid) == null and g.players[0]["graveyard"].has(vial), "no último uso a Ampola é destruída")
	# Garrafão Curativo is strictly better: more uses, more healing, higher cost
	var small: Dictionary = CardDB.card("ampola_curativa")
	var big: Dictionary = CardDB.card("garrafao_curativo")
	check(int(big["charges"]) > int(small["charges"]) and int(big["cost"]) > int(small["cost"])
		and int(big["effects"][0]["amount"]) > int(small["effects"][0]["amount"]), "Garrafão: mais usos, custo e cura que a Ampola")

func _test_artifact_subtypes() -> void:
	# Subtipos de artefato são comparáveis: filtro "subtype" nos alvos de artefato e no match do PlayRestriction
	var plain_card := {"name": "t_plain_artifact", "type": "artifact", "subtypes": [], "rarity": "common", "essence": "neutra",
		"cost": 1, "effects": [], "text": "", "flavor": "", "art": "", "tags": []}
	var local_card := plain_card.duplicate(true)
	local_card["name"] = "t_local_artifact"
	local_card["subtypes"] = ["local"]
	CardDB.data()["cards"]["t_plain_artifact"] = plain_card
	CardDB.data()["cards"]["t_local_artifact"] = local_card
	var g := _new_game()
	_quiet(g)
	var enemy_plain := Card.new(g._uid(), "t_plain_artifact", 1)
	var enemy_local := Card.new(g._uid(), "t_local_artifact", 1)
	var own_local := Card.new(g._uid(), "t_local_artifact", 0)
	g._place_relic(1, enemy_plain)
	g._place_relic(1, enemy_local)
	g._place_relic(0, own_local)
	g._flush()
	var destroy_any := [{"action": "destroy_artifact", "target": "enemy_artifact"}]
	var destroy_local := [{"trigger": "on_play", "action": "destroy_artifact", "target": "enemy_artifact", "subtype": "local"}]
	check(g.valid_targets(0, "enemy_artifact", 0, false, destroy_any).size() == 2, "enemy_artifact sem subtype: qualquer artefato inimigo")
	check(g.valid_targets(0, "enemy_artifact", 0, false, destroy_local) == [enemy_local.uid], "enemy_artifact com subtype local: só o Local inimigo")
	check(g.valid_targets(0, "ally_artifact") == [own_local.uid], "ally_artifact: só os artefatos do próprio lado")
	check(g.valid_targets(0, "any_artifact").size() == 3, "any_artifact: artefatos dos dois lados")
	check(g.valid_targets(0, "any_artifact", 0, false, [{"target": "any_artifact", "subtype": "equipment"}]).is_empty(), "subtype equipment não pega artefato solto")
	# a pick that stops being valid fizzles on resolution (the effect rechecks the subtype)
	g._run_effect_dicts(0, destroy_local, "on_play", enemy_plain.uid, 0)
	check(g.find_relic(enemy_plain.uid) != null, "destroy_artifact com subtype não destrói artefato de outro subtipo")
	g._run_effect_dicts(0, destroy_local, "on_play", enemy_local.uid, 0)
	check(g.find_relic(enemy_local.uid) == null, "destroy_artifact com subtype destrói o artefato daquele subtipo")
	# PlayRestriction: "não pode jogar Locais"
	var forbid_local := {"mode": "forbid", "match": {"subtype": ["local"]}}
	check(PlayRestriction.blocks(forbid_local, local_card) and not PlayRestriction.blocks(forbid_local, plain_card), "restriction subtype: barra só os Locais")
	check(PlayRestriction.error_of(forbid_local, CardDB.data()["essences"]) == "", "restriction subtype local é válida")
	check(PlayRestriction.error_of({"mode": "forbid", "match": {"subtype": ["nada"]}}, CardDB.data()["essences"]) != "", "restriction subtype desconhecido é recusado")

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
	check(DeckDB.validate_cards(leader, champ).filter(func(e): return "Campeão" in e).is_empty(), "Campeão de fora da essência é permitido (conta nas 12 de fora)")

## Fogo deck with every off-essence card removed, plus the given off-essence cards; only the secondary-essence errors are returned.
func _secondary_essence_errors(off_essence_cards: Dictionary) -> Array:
	var leader: String = DeckDB.get_deck("fogo")["leader"]
	var cards: Dictionary = {}
	for k in DeckDB.get_deck("fogo")["cards"]:
		var essences := CardDB.essences_of(CardDB.card(k))
		if essences.has("neutra") or essences.has("ignea"):
			cards[k] = DeckDB.get_deck("fogo")["cards"][k]
	for k in off_essence_cards:
		cards[k] = off_essence_cards[k]
	return DeckDB.validate_cards(leader, cards).filter(func(e): return "secundárias" in e)

func _test_secondary_essences() -> void:
	check(_secondary_essence_errors({"afogar": 3, "tsunami": 3}).is_empty(), "uma essência secundária é legal")
	check(_secondary_essence_errors({"afogar": 3, "arena_tectonica": 3}).is_empty(), "duas essências secundárias são legais")
	check(not _secondary_essence_errors({"afogar": 3, "arena_tectonica": 3, "carga_acumulada": 1}).is_empty(), "três essências secundárias são ilegais")
	# Morwenna is obscura + vegetal: she fits under the obscura secondary essence
	check(_secondary_essence_errors({"afogar": 3, "morwenna_raiz_podre": 2, "necrofago_espectral": 3}).is_empty(), "carta dupla serve a uma essência secundária pela outra metade")
	check(not _secondary_essence_errors({"afogar": 3, "morwenna_raiz_podre": 2, "necrofago_espectral": 3, "arena_tectonica": 1}).is_empty(), "carta dupla não abre uma terceira essência secundária")
	# a neutral Leader picks its secondary essences like any other Leader (Vael: elétrica + ígnea)
	var vael_cards: Dictionary = DeckDB.get_deck("vael")["cards"].duplicate()
	check(DeckDB.validate_cards("vael", vael_cards).filter(func(e): return "secundárias" in e).is_empty(), "Líder neutro com duas essências secundárias é legal")
	vael_cards["afogar"] = 1
	check(not DeckDB.validate_cards("vael", vael_cards).filter(func(e): return "secundárias" in e).is_empty(), "Líder neutro com três essências secundárias é ilegal")

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
	_tcard("t_sturdy", 1, 4, []) # the Ao Entrar now waits on the stack, so a 1-life unit with 1 damage would die before the heal
	var hurt := _put(g, 0, "t_sturdy")
	hurt.damage = 1
	g.players[0]["momentum"] = 10
	var alx := _give(g, 0, "alexa_neruvya_primordial")
	g.play_card(0, alx, 0)
	_resolve_stack(g)
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
	# equipping an already equipped unit returns the old equipment to the hand (it does not go to the graveyard)
	var second_equipment_uid := _give(g, 0, "manoplas_incandescentes")
	var first_equipment: Card = holder.equipment
	g.players[0]["momentum"] = 10
	var graveyard_before_swap: int = g.players[0]["graveyard"].size()
	g.play_card(0, second_equipment_uid, holder.uid)
	g._resolve_stack()
	g._flush()
	check(holder.equipment != first_equipment and holder.equipment.uid == second_equipment_uid, "reequipar: a unidade passa a usar o novo equipamento")
	check(g.players[0]["hand"].has(first_equipment) and first_equipment.zone == "hand", "reequipar: o equipamento anterior volta para a mão")
	check(g.players[0]["graveyard"].size() == graveyard_before_swap, "reequipar: o equipamento anterior não vai ao cemitério")
	check(holder.atk == atk0 + 3, "reequipar: o bônus do equipamento anterior sai da unidade (só o do novo vale)")
	# Equipment buffs belong to the equipment: swapping takes back Vida and keywords, and never kills the unit
	var swap_unit := _put(g, 0, "rato_do_ossuario")
	var swap_base_hp: int = swap_unit.hp
	var swap_base_keywords: Array = swap_unit.keywords.duplicate()
	g.players[0]["momentum"] = 10
	g.play_card(0, _give(g, 0, "pingente_das_ondas"), swap_unit.uid)
	g._resolve_stack()
	g._flush()
	check(swap_unit.hp == swap_base_hp + 1 and swap_unit.keywords.has("roubo_de_vida"), "equipamento dá +1 Vida e Roubo de Vida")
	swap_unit.damage = swap_unit.hp - 1 # one Vida left
	g.players[0]["momentum"] = 10
	g.play_card(0, _give(g, 0, "manoplas_incandescentes"), swap_unit.uid)
	g._resolve_stack()
	g._flush()
	check(g.find_unit(swap_unit.uid) != null, "perder a Vida do equipamento não mata a unidade")
	check(swap_unit.hp_left() == 1, "a unidade fica com 1 de Vida quando perder o equipamento a mataria")
	check(swap_unit.hp == swap_base_hp and swap_unit.keywords == swap_base_keywords, "trocar o equipamento remove a Vida e o Roubo de Vida dele")
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

func _test_incarnation_retire() -> void:
	var g := _new_game()
	_quiet(g)
	var l: Dictionary = g.players[0]["incarnation"]
	g.players[0]["momentum"] = 10
	g.cast_incarnation(0)
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
	check(l["retired"] and not l["in_zone"] and not g.can_cast_incarnation(0), "encarnação: custo acima de 10 aposenta")
	check(g.players[0]["deck"].size() == deck_n + 1 and bottom.card_id == l["card_id"], "encarnação: vai para o fundo do deck")
	g.players[0]["deck"].erase(bottom)
	g.players[0]["hand"].append(bottom)
	g.players[0]["momentum"] = 10
	check(g.can_play(0, bottom.uid), "encarnação aposentada: jogável da mão pelo custo normal")

	# banishing the Encarnação behaves like its death: back to the Santuário while the next cast is payable
	var banish_game := _new_game()
	_quiet(banish_game)
	var banish_incarnation_state: Dictionary = banish_game.players[0]["incarnation"]
	banish_game.players[0]["momentum"] = 10
	banish_game.cast_incarnation(0)
	if banish_game.phase == "enter_target":
		banish_game.choose_enter_target(0, 0)
	if banish_game.summon_window:
		banish_game.pass_priority(1)
	banish_game.banish_unit(banish_game.players[0]["board"].back())
	check(banish_incarnation_state["in_zone"] and not banish_incarnation_state.get("retired", false) and banish_game.players[0]["banished"].is_empty(), "encarnação: banida volta ao Santuário")
	# ...and retires when the next cast would pass the Momentum cap, just like a death
	banish_incarnation_state["casts"] = 10
	banish_incarnation_state["in_zone"] = false
	banish_game._summon(0, Card.new(banish_game._uid(), banish_incarnation_state["card_id"], 0), true, 0)
	banish_game.banish_unit(banish_game.players[0]["board"].back())
	check(banish_incarnation_state["retired"] and not banish_incarnation_state["in_zone"], "encarnação: banida com custo acima de 10 aposenta")

	# the Encarnação CAN return to hand (any return-to-hand effect); it only goes back to the Santuário
	# when it would go to the graveyard or be banished. Legendary RARITY has nothing to do with it.
	var bounce_game := _new_game()
	_quiet(bounce_game)
	var bounce_state: Dictionary = bounce_game.players[0]["incarnation"]
	bounce_game.players[0]["momentum"] = 10
	bounce_game.cast_incarnation(0)
	if bounce_game.phase == "enter_target":
		bounce_game.choose_enter_target(0, 0)
	if bounce_game.summon_window:
		bounce_game.pass_priority(1)
	var incarnation_unit: Card = bounce_game.players[0]["board"].back()
	var cost_with_tax: int = bounce_game.incarnation_cost(0)
	check(bounce_game.return_to_hand(incarnation_unit) and bounce_game.players[0]["hand"].has(incarnation_unit), "encarnação: pode voltar para a mão por um efeito de devolver")
	check(incarnation_unit.incarnation and not bounce_state["in_zone"] and bounce_game.incarnation_in_hand(0), "encarnação: na mão continua sendo a Encarnação e não está no Santuário")
	bounce_game.players[0]["momentum"] = 10
	check(bounce_game.can_play(0, incarnation_unit.uid), "encarnação na mão: pode ser jogada de lá")
	bounce_game.play_card(0, incarnation_unit.uid)
	if bounce_game.phase == "enter_target":
		bounce_game.choose_enter_target(0, 0)
	if bounce_game.summon_window:
		bounce_game.pass_priority(1)
	check(incarnation_unit.zone == "board" and incarnation_unit.incarnation and int(bounce_state["casts"]) == 1, "encarnação jogada da mão: custo normal, sem contar como nova conjuração")
	check(bounce_game.incarnation_cost(0) == cost_with_tax, "encarnação jogada da mão: a taxa do Santuário não muda")
	incarnation_unit.damage = 999
	bounce_game._check_state()
	check(bounce_state["in_zone"] and bounce_game.players[0]["graveyard"].is_empty(), "encarnação: morrer depois de voltar da mão leva ao Santuário")
	# discarded or banished from the hand, it also goes to the Santuário instead of the graveyard / banished zone
	for destination in ["graveyard", "banished"]:
		var hand_game := _new_game()
		_quiet(hand_game)
		var hand_state: Dictionary = hand_game.players[0]["incarnation"]
		var hand_copy := Card.new(hand_game._uid(), hand_state["card_id"], 0, "hand")
		hand_copy.incarnation = true
		hand_state["in_zone"] = false
		hand_game.players[0]["hand"].append(hand_copy)
		hand_game.players[0]["hand"].erase(hand_copy)
		hand_game.players[0][destination].append(hand_copy)
		hand_game._move(hand_copy, destination)
		check(hand_state["in_zone"] and hand_game.players[0]["graveyard"].is_empty() and hand_game.players[0]["banished"].is_empty(),
			"encarnação na mão (%s): volta ao Santuário, não ao cemitério nem aos banidos" % destination)
	# a token that would return to hand is deleted from the game
	_tcard("t_incarnation_token", 1, 1, [])
	CardDB.data()["cards"]["t_incarnation_token"]["token"] = true
	var token_game := _new_game()
	_quiet(token_game)
	var token_card := _put(token_game, 0, "t_incarnation_token")
	var token_hand_before: int = token_game.players[0]["hand"].size()
	check(not token_game.return_to_hand(token_card) and token_game.find_unit(token_card.uid) == null and token_game.players[0]["hand"].size() == token_hand_before,
		"ficha: se fosse voltar para a mão, é apagada do jogo")

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
	# the unit itself as the only possible target is no real choice: no prompt, it is the target
	var lone := _new_game()
	_quiet(lone)
	lone.players[0]["momentum"] = 10
	var myrra := _give(lone, 0, "myrra")
	lone.play_card(0, myrra)
	check(lone.phase != "enter_target" and lone.atk_of(lone.find_unit(myrra)) == 5, "Myrra sozinha no tabuleiro: não pede alvo e ganha o +1")
	if lone.summon_window:
		lone.pass_priority(1)
	var myrra_ally := _give(lone, 0, "myrra")
	lone.play_card(0, myrra_ally)
	check(lone.phase == "enter_target", "Myrra com outra unidade aliada: pede alvo")

func _test_naelys_bounce_discount() -> void:
	_tcard("t_naelys_bounce_ally", 1, 3, [])
	_tcard("t_naelys_bounce_draw", 1, 3, [])
	CardDB.data()["cards"]["t_naelys_bounce_draw"]["cost"] = 4
	CardDB.data()["cards"]["t_naelys_bounce_ally"]["cost"] = 3

	var g := _new_game()
	_quiet(g)
	var p: int = g.active
	var ally := _put(g, p, "t_naelys_bounce_ally")
	g.players[p]["deck"].clear()
	var drawn := Card.new(g._uid(), "t_naelys_bounce_draw", p, "deck")
	g.players[p]["deck"].append(drawn)
	var naelys := Card.new(g._uid(), "naelys", p, "hand")
	g.players[p]["hand"].append(naelys)
	g.players[p]["hand"].erase(naelys)
	g._summon(p, naelys, false, 0, {}, true)
	var targets := g.valid_targets(p, "other_ally_unit", naelys.uid)
	check(g.phase == "enter_target" and targets.has(ally.uid) and not targets.has(naelys.uid), "Naelys só oferece outra unidade aliada como alvo")
	g.choose_enter_target(p, ally.uid)
	check(g.find_unit(ally.uid) == null and _hand_has(g, p, ally.uid), "Naelys devolve a aliada escolhida à mão")
	check(drawn.discount == 1 and drawn.turn_discount == 0 and g.cost_of(p, CardDB.card(drawn.card_id), drawn) == 3, "Naelys: a carta comprada leva só o desconto de 1, sem o adicional")
	check(ally.turn_discount == 1 and g.cost_of(p, CardDB.card(ally.card_id), ally) == 2, "Naelys: a carta devolvida custa 1 a menos neste turno")
	var mirrored := Card.from_dict(ally.to_dict(), "hand", p)
	check(mirrored.turn_discount == 1, "o desconto temporário da Naelys é sincronizado")
	g.end_turn(p)
	check(ally.turn_discount == 0 and g.cost_of(p, CardDB.card(ally.card_id), ally) == 3, "o desconto da carta devolvida expira no fim do turno")
	ally.turn_discount = 1
	g.end_turn(g.active)
	check(ally.turn_discount == 0, "desconto temporário expira mesmo se o dono da carta não for o jogador ativo")

	var skipped := _new_game()
	_quiet(skipped)
	p = skipped.active
	var skipped_ally := _put(skipped, p, "t_naelys_bounce_ally")
	skipped.players[p]["deck"].clear()
	var skipped_draw := Card.new(skipped._uid(), "t_naelys_bounce_draw", p, "deck")
	skipped.players[p]["deck"].append(skipped_draw)
	var skipped_naelys := Card.new(skipped._uid(), "naelys", p, "hand")
	skipped.players[p]["hand"].append(skipped_naelys)
	skipped.players[p]["hand"].erase(skipped_naelys)
	skipped._summon(p, skipped_naelys, false, 0, {}, true)
	skipped.choose_enter_target(p, 0)
	check(skipped.find_unit(skipped_ally.uid) != null and skipped_draw.discount == 1 and skipped_ally.turn_discount == 0, "pular o alvo mantém a compra e não devolve unidade")

	var no_draw := _new_game()
	_quiet(no_draw)
	p = no_draw.active
	var retained_ally := _put(no_draw, p, "t_naelys_bounce_ally")
	no_draw.players[p]["deck"].clear()
	var no_draw_naelys := Card.new(no_draw._uid(), "naelys", p, "hand")
	no_draw.players[p]["hand"].append(no_draw_naelys)
	no_draw.players[p]["hand"].erase(no_draw_naelys)
	no_draw._summon(p, no_draw_naelys, false, 0, {}, true)
	check(no_draw.phase != "enter_target" and no_draw.find_unit(retained_ally.uid) != null, "Naelys não pede alvo nem devolve aliada se o deck não tem carta para descontar")

	# the AI only bounces a unit that comes back with an Ao Entrar to repeat: the weakest such unit, never a plain strong one
	_tcard("t_naelys_ai_strong", 5, 5, [])
	_tcard("t_naelys_ai_enter_weak", 1, 1, [{"trigger": "on_enter", "action": "draw", "target": "none", "amount": 1}])
	_tcard("t_naelys_ai_enter_strong", 3, 3, [{"trigger": "on_enter", "action": "draw", "target": "none", "amount": 1}])
	var ai_game := _new_game()
	_quiet(ai_game)
	p = ai_game.active
	var strong_plain := _put(ai_game, p, "t_naelys_ai_strong")
	var naelys_source := Card.new(ai_game._uid(), "naelys", p, "hand")
	check(SimpleAI._pick_target(ai_game, p, "other_ally_unit", CardDB.card("naelys"), naelys_source.uid) == 0, "IA: Naelys não devolve aliada sem Ao Entrar para repetir")
	var enter_strong := _put(ai_game, p, "t_naelys_ai_enter_strong")
	var enter_weak := _put(ai_game, p, "t_naelys_ai_enter_weak")
	var ai_choice := SimpleAI._pick_target(ai_game, p, "other_ally_unit", CardDB.card("naelys"), naelys_source.uid)
	check(ai_choice == enter_weak.uid and ai_choice != strong_plain.uid and ai_choice != enter_strong.uid, "IA: Naelys devolve a aliada mais fraca que tem Ao Entrar")

## The AI's spell preview: before casting a spell it tries it on a copy of the game and skips it when
## nothing would change (here: Repique Desgovernado, which only hits enemy units, against an empty board).
func _sagrada_preview_game() -> GameState:
	var g := GameState.new("sagrada", "fogo", 42)
	g.mulligan(0, [])
	g.mulligan(1, [])
	_quiet(g)
	g.players[0]["hand"].clear()
	g.players[0]["incarnation"]["in_zone"] = false
	g.players[0]["momentum"] = 5
	return g

func _hand_has(g: GameState, p: int, uid: int) -> bool:
	for card: Card in g.players[p]["hand"]:
		if card.uid == uid:
			return true
	return false

## Líder Naelys, "Maré de Retorno": Lenta, 3 Momentum, uma vez por turno. Devolve uma unidade aliada (ela custa 1 a menos
## neste turno) e compra 1 carta só se a mão tiver 4 ou menos cartas depois da devolução (a compra não tem desconto).
func _test_naelys_leader() -> void:
	var ability: Dictionary = CardDB.leader("naelys")["ability"]
	check(int(ability["cost"]) == 3 and ability["speed"] == "lento" and ability.get("once_per_turn", false), "Maré de Retorno: Lenta, custo 3, uma vez por turno")
	check(CardDB.leader("naelys")["incarnation"] == "naelys" and DeckDB.validate("mare_consagrada").is_empty(), "Líder Naelys: o deck Maré Consagrada é legal")
	_tcard("t_tide_ally", 2, 2, [])
	CardDB.data()["cards"]["t_tide_ally"]["cost"] = 4

	# hand of 3 before: 4 after the bounce, so the extra card is drawn
	var g := _new_game()
	_quiet(g)
	var p: int = g.active
	g.players[p]["leader_id"] = "naelys"
	g.players[p]["ability_used"] = false
	g.players[p]["momentum"] = 8
	var ally := _put(g, p, "t_tide_ally")
	g.players[p]["hand"].clear()
	for filler in 3:
		g.players[p]["hand"].append(Card.new(g._uid(), "t_tide_ally", p, "hand"))
	var deck_before: int = g.players[p]["deck"].size()
	check(g.can_use_ability(p), "Maré de Retorno: disponível com uma unidade aliada em campo")
	g.use_ability(p, ally.uid)
	_resolve_stack(g)
	check(g.find_unit(ally.uid) == null and _hand_has(g, p, ally.uid), "Maré de Retorno: devolve a unidade aliada à mão")
	check(ally.turn_discount == 1 and g.cost_of(p, CardDB.card(ally.card_id), ally) == 3, "Maré de Retorno: a unidade devolvida custa 1 a menos neste turno")
	check(g.players[p]["hand"].size() == 5 and g.players[p]["deck"].size() == deck_before - 1, "Maré de Retorno: mão com 4 ou menos depois da devolução compra 1 carta")
	check(int(g.players[p]["momentum"]) == 5, "Maré de Retorno: custa 3 de Momentum")
	var drawn: Card = g.players[p]["hand"][g.players[p]["hand"].size() - 1]
	check(drawn.discount == 0 and drawn.turn_discount == 0, "Maré de Retorno: a carta comprada não ganha desconto")
	check(not g.can_use_ability(p), "Maré de Retorno: só uma vez por turno")

	# hand of 4 before: 5 after the bounce, so nothing is drawn
	var full := _new_game()
	_quiet(full)
	p = full.active
	full.players[p]["leader_id"] = "naelys"
	full.players[p]["ability_used"] = false
	full.players[p]["momentum"] = 8
	var full_ally := _put(full, p, "t_tide_ally")
	full.players[p]["hand"].clear()
	for filler in 4:
		full.players[p]["hand"].append(Card.new(full._uid(), "t_tide_ally", p, "hand"))
	var full_deck_before: int = full.players[p]["deck"].size()
	full.use_ability(p, full_ally.uid)
	_resolve_stack(full)
	check(_hand_has(full, p, full_ally.uid) and full.players[p]["hand"].size() == 5 and full.players[p]["deck"].size() == full_deck_before, "Maré de Retorno: com mais de 4 cartas na mão depois da devolução não compra")

func _test_ai_spell_preview() -> void:
	# a copy looks exactly like the game it came from, and playing on it leaves the real game alone
	var original := _sagrada_preview_game()
	var copy := original.preview_copy()
	check(copy != null and copy.preview_snapshot() == original.preview_snapshot(), "IA/prévia: a cópia é idêntica ao jogo original")
	var bell_uid := _give(copy, 0, "repique_desgovernado")
	copy.play_card(0, bell_uid)
	check(original.players[0]["momentum"] == 5 and original.players[0]["hand"].is_empty(), "IA/prévia: jogar na cópia não mexe no jogo real")

	# 1. empty enemy board: the spell would do nothing, so the AI keeps the card and the Momentum
	var empty := _sagrada_preview_game()
	var wasted_bell := _give(empty, 0, "repique_desgovernado")
	SimpleAI.step(empty, 0)
	check(_hand_has(empty, 0, wasted_bell), "IA/prévia: não lança Repique Desgovernado com o campo inimigo vazio") # it may spend Momentum on other plays, just not on the Repique

	# 2. an enemy unit to hit: now the spell changes something, so the AI casts it
	var target_game := _sagrada_preview_game()
	_put(target_game, 1, "bastionario_de_basalto")
	var useful_bell := _give(target_game, 0, "repique_desgovernado")
	SimpleAI.step(target_game, 0)
	check(not _hand_has(target_game, 0, useful_bell), "IA/prévia: lança Repique Desgovernado quando há unidade inimiga")

## The AI's Ao Entrar damage (Ronan): it is never skipped when the damage stays marked on a target,
## even though Ronan also has an Ao Sofrer Dano buff. It is skipped only when it would be wasted.
func _test_ai_enter_damage() -> void:
	# 1. a plain enemy that survives the 2 damage: the damage is permanent, so the AI uses it
	var g := _new_game()
	_quiet(g)
	var bastion := _put(g, 1, "bastionario_de_basalto")
	g.players[0]["momentum"] = 10
	g.play_card(0, _give(g, 0, "ronan"))
	check(g.phase == "enter_target", "IA/Ronan: pede alvo do Ao Entrar")
	SimpleAI.step(g, 0)
	check(g.find_unit(bastion.uid).damage == 2, "IA/Ronan: causa o dano do Ao Entrar em unidade sem regeneração")

	# 2. the only enemies would heal (Regeneração) or grow from the damage (Ao Sofrer Dano): nothing gained
	var wasted := _new_game()
	_quiet(wasted)
	var coral := _put(wasted, 1, "sentinela_coral")
	var enemy_ronan := _put(wasted, 1, "ronan")
	wasted.players[0]["momentum"] = 10
	wasted.play_card(0, _give(wasted, 0, "ronan"))
	SimpleAI.step(wasted, 0)
	check(wasted.find_unit(coral.uid).damage == 0 and wasted.find_unit(enemy_ronan.uid).damage == 0, "IA/Ronan: pula o Ao Entrar quando o dano se perderia ou fortaleceria o alvo")
	check(wasted.phase != "enter_target", "IA/Ronan: recusar o Ao Entrar encerra a escolha")

	# 3. one regenerating enemy next to one that keeps the damage: it picks the one that keeps it
	var mixed := _new_game()
	_quiet(mixed)
	var healing := _put(mixed, 1, "sentinela_coral")
	var lasting := _put(mixed, 1, "bastionario_de_basalto")
	mixed.players[0]["momentum"] = 10
	mixed.play_card(0, _give(mixed, 0, "ronan"))
	SimpleAI.step(mixed, 0)
	check(mixed.find_unit(healing.uid).damage == 0 and mixed.find_unit(lasting.uid).damage == 2, "IA/Ronan: ignora quem regenera e fere quem guarda o dano")

## Tharox's Massa Inamolgável (+1 Armadura until his next turn): the AI only spends the Momentum when an
## exhausted ally would die to an enemy challenge without it and survive with it.
func _test_ai_armor_ability() -> void:
	_tcard("t_armor_ally", 2, 3, [])
	_tcard("t_armor_hit3", 3, 4, [])
	_tcard("t_armor_hit5", 5, 4, [])

	# 1. no enemy unit on the table: the bonus would be wasted
	var empty := GameState.new("rochosa", "agua", 42)
	empty.mulligan(0, [])
	empty.mulligan(1, [])
	empty.players[0]["hand"].clear()
	empty.players[0]["incarnation"]["in_zone"] = false
	empty.players[0]["momentum"] = 5
	empty.players[0]["ability_used"] = false
	var lone_ally := _put(empty, 0, "t_armor_ally")
	lone_ally.exhausted = true
	SimpleAI.step(empty, 0)
	check(empty.players[0]["ability_used"] == false and empty.players[0]["momentum"] == 5, "IA/Tharox: sem unidade inimiga não gasta Momentum na Massa Inamolgável")

	# 2. an enemy that kills the ally anyway (5 attack vs 3 life, armor 1 is not enough): wasted too
	var hopeless := GameState.new("rochosa", "agua", 42)
	hopeless.mulligan(0, [])
	hopeless.mulligan(1, [])
	hopeless.players[0]["hand"].clear()
	hopeless.players[0]["incarnation"]["in_zone"] = false
	hopeless.players[0]["momentum"] = 5
	hopeless.players[0]["ability_used"] = false
	var doomed := _put(hopeless, 0, "t_armor_ally")
	doomed.exhausted = true
	_put(hopeless, 1, "t_armor_hit5")
	SimpleAI.step(hopeless, 0)
	check(hopeless.players[0]["ability_used"] == false, "IA/Tharox: não gasta Momentum quando 1 de Armadura não salva a unidade")

	# 3. an enemy with 3 attack against a 3 life ally: the extra Armadura saves it, so the AI uses it on that ally
	var threatened := GameState.new("rochosa", "agua", 42)
	threatened.mulligan(0, [])
	threatened.mulligan(1, [])
	threatened.players[0]["hand"].clear()
	threatened.players[0]["incarnation"]["in_zone"] = false
	threatened.players[0]["momentum"] = 5
	threatened.players[0]["ability_used"] = false
	var safe_ally := _put(threatened, 0, "t_armor_ally")
	var saved_ally := _put(threatened, 0, "t_armor_ally")
	saved_ally.exhausted = true
	_put(threatened, 1, "t_armor_hit3")
	SimpleAI.step(threatened, 0)
	check(threatened.players[0]["ability_used"] == true, "IA/Tharox: usa a Massa Inamolgável quando ela salva uma unidade")
	check(threatened.armor_of(threatened.find_unit(saved_ally.uid)) == 1 and threatened.armor_of(threatened.find_unit(safe_ally.uid)) == 0, "IA/Tharox: a Armadura vai para a unidade ameaçada")

## The Encarnação is a fallback after worthwhile hand plays, not an automatic first action.
func _test_ai_incarnation_priority() -> void:
	_tcard("t_ai_incarnation_alternative", 2, 2, [])
	var hand_play := GameState.new("vegetal", "agua", 42)
	hand_play.mulligan(0, [])
	hand_play.mulligan(1, [])
	hand_play.players[0]["hand"].clear()
	hand_play.players[0]["momentum"] = 6
	var alternative_uid := _give(hand_play, 0, "t_ai_incarnation_alternative")
	SimpleAI.step(hand_play, 0)
	check(not _hand_has(hand_play, 0, alternative_uid), "IA/Encarnação: joga uma carta viável da mão antes de conjurar a Encarnação")
	check(hand_play.players[0]["incarnation"]["in_zone"] and hand_play.players[0]["momentum"] == 5,
		"IA/Encarnação: preserva o Momentum restante e deixa a Encarnação no Santuário após a jogada da mão")

	var fallback := GameState.new("vegetal", "agua", 43)
	fallback.mulligan(0, [])
	fallback.mulligan(1, [])
	fallback.players[0]["hand"].clear()
	fallback.players[0]["momentum"] = 6
	SimpleAI.step(fallback, 0)
	check(not fallback.players[0]["incarnation"]["in_zone"] and fallback.players[0]["momentum"] == 0,
		"IA/Encarnação: conjura como fallback quando não há jogadas viáveis na mão")

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

## Tharox only gains Armadura from a hit whose damage (before Armadura) is equal to or bigger than the Armadura he already has.
func _test_tharox_armor_growth() -> void:
	var g := _new_game()
	var tharox := _put(g, 0, "tharox")
	check(g.armor_of(tharox) == 0, "Tharox começa sem Armadura")
	# each row: [damage of the hit, expected Armadura afterwards]
	for step in [[1, 1], [1, 2], [1, 2], [2, 3], [2, 3], [3, 4]]:
		g._deal_damage(tharox.uid, step[0], null)
		g._check_state()
		check(g.armor_of(tharox) == step[1], "Tharox: golpe de %d deixa a Armadura em %d (%d)" % [step[0], step[1], g.armor_of(tharox)])

## Vørn Ω grows in three steps, one per Ao Sofrer Dano of that instance (across turns); later hits do nothing.
func _test_vorn_staged_damage() -> void:
	var g := _new_game()
	var vorn := _put(g, 0, "vorn_omega")
	check(vorn.atk == 3 and g.armor_of(vorn) == 0, "Vørn Ω começa com 3 de Ataque e nenhuma Armadura (%d/%d)" % [vorn.atk, g.armor_of(vorn)])
	var other_vorn := _put(g, 0, "vorn_omega")
	# each row: [expected Ataque, expected Armadura] after one more hit; a turn passes between hits
	for step in [[5, 0], [10, 0], [10, 3], [10, 3], [10, 3]]:
		g._deal_damage(vorn.uid, 1, null)
		g._check_state()
		check(vorn.atk == step[0] and g.armor_of(vorn) == step[1], "Vørn Ω: Ataque %d e Armadura %d após o golpe (%d/%d)" % [step[0], step[1], vorn.atk, g.armor_of(vorn)])
		g.turn += 1
	check(other_vorn.atk == 3, "a contagem é por instância: o outro Vørn Ω continua no 1º degrau")

## Bastionário gives Armadura only to the allies standing right next to it on the board.
## A Constante of an ally is the ALLY's effect: silencing the unit it buffs does not turn it off; silencing the carrier does.
func _test_silence_keeps_ally_auras() -> void:
	_tcard("t_sil_aura_source", 1, 5, [{"trigger": "constante", "action": "species_aura", "species": ["anjo"],
		"atk": 1, "hp": 1, "armor": 1}])
	CardDB.data()["cards"]["t_sil_aura_source"]["species"] = ["humano"]
	_tcard("t_sil_aura_angel", 2, 4, [])
	CardDB.data()["cards"]["t_sil_aura_angel"]["species"] = ["anjo"]
	var g := _new_game()
	_quiet(g)
	var source := _put(g, 0, "t_sil_aura_source")
	var angel := _put(g, 0, "t_sil_aura_angel")
	g._refresh_scaling()
	check(g.atk_of(angel) == 3 and g.hp_left(angel) == 5 and g.armor_of(angel) == 1, "aura: o Anjo começa com +1/+1 e Armadura 1")
	angel.damage = 4 # 1 Vida left, counting the aura
	g._apply_effect(0, {"action": "silence", "target": "enemy_unit"}, angel.uid)
	g._check_state()
	check(angel.is_silenced(), "aura: o Anjo foi silenciado")
	check(g.atk_of(angel) == 3 and g.armor_of(angel) == 1, "aura: silenciar o buffado NÃO tira o bônus da Constante aliada (%d, arm %d)" % [g.atk_of(angel), g.armor_of(angel)])
	check(g.hp_left(angel) == 1, "aura: o Silêncio não cura nem mata o buffado (sobra %d)" % g.hp_left(angel))
	g._apply_effect(0, {"action": "silence", "target": "enemy_unit"}, source.uid)
	g._check_state()
	check(g.atk_of(angel) == 2 and g.armor_of(angel) == 0, "aura: silenciar quem carrega a Constante desliga o bônus (%d, arm %d)" % [g.atk_of(angel), g.armor_of(angel)])
	check(g.find_unit(angel.uid) != null and g.hp_left(angel) == 1, "aura: perder a aura (fonte silenciada) nunca mata o aliado ferido, sobra 1 Vida (%d)" % g.hp_left(angel))

	# the aura source dying (not just silenced) does not kill the wounded ally either
	g = _new_game()
	_quiet(g)
	source = _put(g, 0, "t_sil_aura_source")
	angel = _put(g, 0, "t_sil_aura_angel")
	g._refresh_scaling()
	angel.damage = 4
	source.damage = source.hp
	g._check_state()
	check(g.find_unit(source.uid) == null, "aura: a fonte morreu")
	check(g.find_unit(angel.uid) != null and g.hp_left(angel) == 1, "aura: a fonte morrer também não mata o aliado ferido (sobra %d)" % g.hp_left(angel))
	angel.damage = angel.hp
	g._check_state()
	check(g.find_unit(angel.uid) == null, "aura: dano de verdade ainda mata")

	# adjacent_armor: the Armadura comes from the neighbour's Constante
	g = _new_game()
	_quiet(g)
	var left := _put(g, 0, "bastionario_de_basalto")
	var guard := _put(g, 0, "bastionario_de_basalto")
	var right := _put(g, 0, "escudeiro_de_cascalho")
	g._apply_effect(0, {"action": "silence", "target": "enemy_unit"}, right.uid)
	check(g.armor_of(right) == 1, "Armadura adjacente: silenciar quem recebe não tira o que o vizinho dá")
	g._apply_effect(0, {"action": "silence", "target": "enemy_unit"}, guard.uid)
	check(g.armor_of(right) == 0, "Armadura adjacente: silenciar o Bastionário desliga a Constante dele")
	check(g.armor_of(left) == 0, "Armadura adjacente: o Bastionário silenciado também não dá ao outro lado")

func _test_adjacent_armor() -> void:
	var g := _new_game()
	var left := _put(g, 0, "bastionario_de_basalto")
	var guard := _put(g, 0, "bastionario_de_basalto")
	var right := _put(g, 0, "escudeiro_de_cascalho")
	var far := _put(g, 0, "escudeiro_de_cascalho")
	check(g.armor_of(left) == 1 and g.armor_of(guard) == 1 and g.armor_of(right) == 1, "Armadura adjacente vem dos vizinhos, não da própria unidade")
	check(g.armor_of(far) == 0, "unidade longe do Bastionário não recebe")
	check(g._deal_damage(right.uid, 1, null) == 1, "dano 1 passa mesmo com a Armadura adjacente (mínimo 1)")
	# Contador Exagerado doubles the adjacent Armadura (a text Constante), and never stacks
	_put(g, 0, "contador_exagerado")
	check(g.armor_of(right) == 2 and g.armor_of(left) == 2, "Contador: a Armadura adjacente conta em dobro")
	check(g.armor_of(far) == 0, "Contador: quem não está ao lado de um Bastionário continua sem Armadura")
	_put(g, 0, "contador_exagerado")
	check(g.armor_of(right) == 2, "Contador: dois Contadores não dão x4 na Armadura adjacente")

## Atordoamento (stacking, auto-exhausting freeze-like status) and the cap_stats effect behind Última Badalada.
func _test_stun_and_cap() -> void:
	_tcard("t_stn_hit", 1, 5, [])
	_tcard("t_stn_vic", 3, 5, [])
	var g := _new_game()
	_quiet(g)
	var hitter := _put(g, 0, "t_stn_hit")
	var victim := _put(g, 1, "t_stn_vic")
	check(not victim.exhausted and not victim.is_stunned(), "atordoamento: unidade começa em pé e sem marcador")
	g._apply_effect(0, {"action": "stun", "target": "enemy_unit"}, victim.uid)
	check(victim.is_stunned() and victim.stun_markers == 1 and victim.exhausted, "atordoar: 1 marcador e a unidade fica exausta na hora")
	check(not g.can_attack(victim) and victim.rapidez_total() == 0, "atordoada: não ataca e a Rapidez é suprimida")
	check(g.combat_system().attack_targets(hitter).has(victim.uid), "atordoada: está exausta, então pode ser desafiada")
	_hit(g, hitter, victim.uid)
	check(hitter.damage == 3 and victim.damage == 1, "atordoada: desafiada, revida com o ATK cheio")
	# stacking: two markers cost two untaps
	g._apply_effect(0, {"action": "stun", "target": "enemy_unit"}, victim.uid)
	check(victim.stun_markers == 2, "atordoar de novo acumula marcadores")
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and victim.stun_markers == 1 and victim.exhausted, "início do turno do dono: tira 1 marcador e NÃO desvira")
	_quiet(g)
	g.end_turn(1)
	g.end_turn(0)
	check(g.active == 1 and victim.stun_markers == 0 and victim.exhausted, "segundo marcador: ainda exausta, só desvira no turno seguinte")
	_quiet(g)
	g.end_turn(1)
	g.end_turn(0)
	check(not victim.exhausted and g.can_attack(victim), "sem marcadores: desvira e ataca normalmente")
	# a stunned Provocação forces nothing
	_tcard("t_stn_taunt", 2, 5, [])
	CardDB.data()["cards"]["t_stn_taunt"]["keywords"] = ["provocacao"]
	g = _new_game()
	_quiet(g)
	hitter = _put(g, 0, "t_stn_hit")
	var taunt := _put(g, 1, "t_stn_taunt")
	taunt.exhausted = true
	check(g.combat_system().attack_targets(hitter) == [taunt.uid], "Provocação exausta obriga o ataque")
	g._apply_effect(0, {"action": "stun", "target": "enemy_unit"}, taunt.uid)
	check(g.combat_system().forced_taunts(hitter).is_empty(), "Provocação atordoada não obriga ataques")
	# Escudo de Feitiço cancels the stun, like it cancels a freeze
	var shielded := _put(g, 1, "t_stn_vic")
	shielded.spell_shield = true
	g._apply_effect(0, {"action": "stun", "target": "enemy_unit"}, shielded.uid, SPELL_SOURCE)
	check(not shielded.is_stunned() and not shielded.spell_shield, "Escudo de Feitiço anula o atordoamento")
	# the shield cancels the whole card on that unit: Lianas Capturantes' -3 Ataque must not land after the exhaust is cancelled
	g = _new_game()
	_quiet(g)
	var vines_target := _put(g, 1, "t_stn_vic")
	vines_target.spell_shield = true
	var vines_atk_before := g.atk_of(vines_target)
	g._run_effect_dicts(0, CardDB.card("lianas_capturantes")["effects"], "on_play", vines_target.uid, 0, "lianas_capturantes")
	check(not vines_target.spell_shield and not vines_target.exhausted and g.atk_of(vines_target) == vines_atk_before, "Escudo de Feitiço cancela todos os efeitos da carta na unidade (exaurir e -3 Ataque)")
	g._run_effect_dicts(0, CardDB.card("lianas_capturantes")["effects"], "on_play", vines_target.uid, 0)
	check(vines_target.exhausted and g.atk_of(vines_target) == maxi(0, vines_atk_before - 3), "sem escudo, Lianas Capturantes exaure e dá -3 Ataque")
	# separate hits of one effect are separate spells: Repique's first hit only breaks the shield, the other two land
	g = _new_game()
	_quiet(g)
	_tcard("t_rep_vic", 1, 20, [])
	var repique_target := _put(g, 1, "t_rep_vic")
	repique_target.spell_shield = true
	g._run_effect_dicts(0, CardDB.card("repique_desgovernado")["effects"], "on_play", 0, 0, "repique_desgovernado")
	check(not repique_target.spell_shield and repique_target.damage == 8, "Repique Desgovernado: o Escudo de Feitiço anula só o primeiro hit (8 dos 9 acertam)")
	# save/load keeps the markers
	var restored := Card.from_dict(taunt.to_dict(), "board", 1)
	check(restored.stun_markers == 1, "atordoamento sobrevive a salvar e carregar")

	# cap_stats: big units shrink, small ones stay, damage never kills, temporary bonuses go first
	_tcard("t_cap_big", 5, 5, [])
	_tcard("t_cap_small", 1, 1, [])
	g = _new_game()
	_quiet(g)
	var big := _put(g, 0, "t_cap_big")
	var small := _put(g, 1, "t_cap_small")
	var wounded := _put(g, 1, "t_cap_big")
	wounded.damage = 4
	var buffed := _put(g, 0, "t_cap_big")
	buffed.temp_atk = 2
	buffed.temp_hp = 2
	g._apply_effect(0, {"action": "cap_stats", "target": "all_units", "atk": 2, "hp": 2}, big.uid)
	g._apply_effect(0, {"action": "cap_stats", "target": "all_units", "atk": 2, "hp": 2}, small.uid)
	g._apply_effect(0, {"action": "cap_stats", "target": "all_units", "atk": 2, "hp": 2}, wounded.uid)
	g._apply_effect(0, {"action": "cap_stats", "target": "all_units", "atk": 2, "hp": 2}, buffed.uid)
	check(g.atk_of(big) == 2 and big.hp_left() == 2, "cap_stats: 5/5 vira 2/2 (inclusive a unidade de quem joga)")
	check(g.atk_of(small) == 1 and small.hp_left() == 1, "cap_stats: unidade menor não cresce")
	check(wounded.hp_left() == 1 and g.find_unit(wounded.uid) != null, "cap_stats: unidade ferida (1 de Vida) fica com 1 e não morre")
	check(buffed.temp_atk == 0 and buffed.temp_hp == 0 and g.atk_of(buffed) == 2 and buffed.hp_left() == 2, "cap_stats: bônus temporário sai primeiro e o resultado é 2/2")
	g._apply_effect(0, {"action": "buff", "target": "ally_unit", "atk": 3, "hp": 3}, big.uid)
	check(g.atk_of(big) == 5 and big.hp_left() == 5, "cap_stats não é trava: buffs depois ainda crescem a unidade")

	# the real spell: Última Badalada in a Sagrada vs Fogo game
	var sg := GameState.new("sagrada", "fogo", 7)
	sg.mulligan(0, [])
	sg.mulligan(1, [])
	sg.self_response_enabled = false
	_quiet(sg)
	var cd := CardDB.card("ultima_badalada")
	check(cd["type"] == "spell" and int(cd["cost"]) == 5 and cd["rarity"] == "epic", "Última Badalada: feitiço épico de custo 5")
	check(int(DeckDB.get_deck("sagrada")["cards"].get("ultima_badalada", 0)) == 2, "Última Badalada: 2 cópias no deck Sagrada")
	var wall := _put(sg, 0, "uriel")
	var foe_a := _put(sg, 1, "t_cap_big")
	var foe_b := _put(sg, 1, "t_cap_big")
	sg.players[0]["momentum"] = 30
	_cast_and_resolve(sg, 0, "ultima_badalada")
	check(sg.atk_of(wall) == 2 and wall.hp_left() == 2, "Última Badalada: encolhe a própria unidade (Uriel 5/5 -> 2/2)")
	var survivors: Array = [foe_a, foe_b].filter(func(c: Card): return sg.find_unit(c.uid) != null)
	check(survivors.all(func(c: Card): return c.is_stunned() and c.exhausted), "Última Badalada: todo inimigo que sobrou está atordoado e exausto")
	check(not wall.is_stunned(), "Última Badalada: não atordoa as próprias unidades")
	var total_damage := 0
	for foe in [foe_a, foe_b]:
		total_damage += 2 if sg.find_unit(foe.uid) == null else (2 - foe.hp_left())
	check(total_damage >= 2, "Última Badalada: os 5 golpes de 1 caem nos inimigos (2/2 cada: pode matar)")

func _test_freeze() -> void:
	# Congelada: doesn't attack and doesn't untap until the end of its owner's next turn; ATK stays whole
	_tcard("t_frz_hit", 1, 5, [])
	_tcard("t_frz_vic", 3, 5, [])
	var g := _new_game()
	_quiet(g)
	var hitter := _put(g, 0, "t_frz_hit")
	var tapped := _put(g, 1, "t_frz_vic")
	var standing := _put(g, 1, "t_frz_vic")
	tapped.exhausted = true
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, tapped.uid)
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, standing.uid)
	check(g.is_frozen(tapped) and g.is_frozen(standing), "congelar marca a unidade")
	check(g.atk_of(tapped) == 3 and tapped.rapidez_total() == 0, "congelada: ATK segue o mesmo, Rapidez é suprimida (vira 0)")
	check(not standing.exhausted, "congelar não exaure: a unidade em pé continua em pé")
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and g.is_frozen(tapped) and g.is_frozen(standing), "congelada no meu turno: segue congelada no turno seguinte (do dono)")
	check(tapped.exhausted, "congelada: não desvira no início do turno do dono")
	check(not g.can_attack(standing), "congelada: não pode atacar no turno do dono")
	_quiet(g)
	g.end_turn(1)
	check(g.active == 0 and not g.is_frozen(tapped) and not g.is_frozen(standing), "descongela no fim do turno seguinte")
	check(tapped.exhausted, "a exausta só desvira no turno seguinte do dono, já descongelada")
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and not tapped.exhausted and g.can_attack(standing), "descongelada: desvira e ataca normalmente")
	# frozen during its owner's own turn (an Instantâneo in their pre-combat): no attack now, and it
	# doesn't guard its Leader through my next turn; it thaws at the end of my turn
	standing.exhausted = true
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, standing.uid)
	check(g.is_frozen(standing), "congelada no próprio turno do dono")
	_quiet(g)
	g.end_turn(1)
	var my_attacker := _put(g, 0, "t_frz_hit")
	check(g.active == 0 and g.is_frozen(standing) and g.combat_system().attack_targets(my_attacker).has(GameState.LEADER_UID[1]), "congelada no turno do dono: no meu turno segue congelada e não protege o Líder")
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and not g.is_frozen(standing) and not standing.exhausted, "congelada no turno do dono: descongela no fim do meu turno e desvira no turno dele")
	_quiet(g)
	g.end_turn(1)
	# a unit frozen while still summoning sick is no exception: it can't attack in its owner's next turn
	var fresh := _put(g, 1, "t_frz_vic", false)
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, fresh.uid)
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and g.is_frozen(fresh) and not fresh.sick and not g.can_attack(fresh), "congelada com enjoo: no turno do dono, sem enjoo mas sem atacar")
	_quiet(g)
	g.end_turn(1)
	check(not g.is_frozen(fresh), "congelada com enjoo: descongela no fim do turno do dono")
	var s := _put(g, 1, "tritao_lanceiro")
	s.spell_shield = true
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, s.uid, SPELL_SOURCE)
	check(not g.is_frozen(s) and not s.spell_shield, "Escudo de Feitiço anula congelar")
	# a frozen tapped unit can be challenged and strikes back with its full ATK
	g = _new_game()
	_quiet(g)
	hitter = _put(g, 0, "t_frz_hit")
	var ice := _put(g, 1, "t_frz_vic")
	ice.exhausted = true
	var enemy_leader: int = GameState.LEADER_UID[1]
	check(g.combat_system().attack_targets(hitter) == [ice.uid, enemy_leader], "exausta não congelada: pode ser desafiada ou ignorada (a face segue aberta)")
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, ice.uid)
	var targets: Array = g.combat_system().attack_targets(hitter)
	check(targets.has(ice.uid) and targets.has(enemy_leader), "congelada exausta: pode ser desafiada e o Líder segue como alvo")
	var guard := _put(g, 1, "t_frz_vic")
	guard.exhausted = true
	check(g.combat_system().attack_targets(hitter).has(enemy_leader), "outra exausta não congelada também não fecha a face")
	_hit(g, hitter, ice.uid)
	check(hitter.damage == 3 and ice.damage == 1, "congelada: desafiada, revida com o ATK cheio")
	# a frozen Provocação forces nothing
	_tcard("t_frz_taunt", 2, 5, [])
	CardDB.data()["cards"]["t_frz_taunt"]["keywords"] = ["provocacao"]
	g = _new_game()
	_quiet(g)
	hitter = _put(g, 0, "t_frz_hit")
	var taunt := _put(g, 1, "t_frz_taunt")
	taunt.exhausted = true
	check(g.combat_system().attack_targets(hitter) == [taunt.uid], "Provocação exausta obriga o ataque")
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, taunt.uid)
	targets = g.combat_system().attack_targets(hitter)
	check(g.combat_system().forced_taunts(hitter).is_empty() and targets.has(taunt.uid) and targets.has(GameState.LEADER_UID[1]), "Provocação congelada não obriga nem protege o Líder")
	check(CardDB.has_essence(CardDB.card("sabrina"), "glacial") and CardDB.has_essence(CardDB.card("sabrina"), "aquatica"), "sabrina é aquática e glacial")
	# Sabrina: 1 damage, or 3 if the target was already Congelada (a freeze by the same effect doesn't count)
	g = _new_game()
	_quiet(g)
	var cold := _put(g, 1, "t_frz_taunt")
	var warm := _put(g, 1, "t_frz_taunt")
	g._apply_effect(0, {"action": "freeze", "target": "enemy_unit"}, cold.uid)
	for victim in [cold, warm]:
		g._apply_effect(0, {"action": "damage", "target": "enemy_unit", "amount": 1, "amount_if_frozen": 3}, victim.uid)
	check(cold.damage == 3 and warm.damage == 1, "dano extra só em alvo já Congelado")
	check(CardDB.card("sabrina")["effects"].size() == 1 and not CardDB.card("sabrina")["effects"][0].has("freeze"), "sabrina não congela mais")

func _test_burn() -> void:
	# Queimadura accumulates, uses its periodic-damage rule at the controller's turn start, then clears.
	_tcard("t_burn", 1, 8, [])
	_tcard("t_tank", 1, 13, [])
	var g := _new_game()
	_quiet(g)
	var victim := _put(g, 1, "t_burn")
	var tank := _put(g, 1, "t_tank")
	g._apply_effect(0, {"action": "add_dot", "dot": "queimadura", "target": "enemy_unit", "amount": 2}, victim.uid)
	g._apply_effect(0, {"action": "add_dot", "dot": "queimadura", "target": "enemy_unit", "amount": 1}, victim.uid)
	check(int(victim.dot_markers.get("queimadura", 0)) == 3, "Queimadura acumula marcadores genéricos")
	check(g.dot_damage("veneno", victim, 3) == 6 and g.dot_damage("sangramento", tank, 3) == 5, "Veneno causa 2 de dano por marcador e Sangramento usa a fórmula por faixa de Vida")
	victim.temp_hp = 2
	check(g.dot_damage("veneno", victim, 3) == 6 and CardDB.keyword("veneno")["name"] == "Veneno" and CardDB.keyword("sangramento")["name"] == "Sangramento", "Veneno ignora Vida máxima e as keywords estão no dicionário")
	victim.temp_hp = 0
	var before := victim.to_dict()
	var mirror := Card.from_dict(before, "board", 1)
	check(int(mirror.dot_markers.get("queimadura", 0)) == 3, "marcadores de Queimadura sobrevivem ao espelho de rede genérico")
	g._start_turn(1, false)
	check(victim.damage == 3 and victim.dot_markers.is_empty(), "no início do turno, Queimadura causa o total e remove os marcadores")
	# Queimadura bypasses Armadura and Escudo: the full marker count becomes damage, and the shield stays.
	victim.armor = 1
	victim.shield = true
	victim.dot_markers["queimadura"] = 2
	g._start_turn(1, false)
	check(victim.damage == 5 and victim.dot_markers.is_empty() and victim.shield, "Queimadura ignora Armadura e Escudo, causando o total e limpando os marcadores")
	# Indestrutível remains the stronger protection currently defined by the game.
	victim.keywords.append("indestrutivel")
	victim.dot_markers["queimadura"] = 2
	g._start_turn(1, false)
	check(victim.damage == 5 and victim.dot_markers.is_empty(), "Queimadura ainda respeita Indestrutível como proteção superior")
	# Escudo de Feitiço cancels the marker application just like any other targeted effect.
	victim.spell_shield = true
	g._apply_effect(0, {"action": "add_dot", "dot": "queimadura", "target": "enemy_unit", "amount": 2}, victim.uid, SPELL_SOURCE)
	check(victim.dot_markers.is_empty() and not victim.spell_shield, "Escudo de Feitiço anula a aplicação de Queimadura")

func _test_condemn() -> void:
	# Condenada: the unit dies at the start of the marker-giver's next turn, even if the source is long gone
	_tcard("t_cdm_vic", 3, 5, [])
	var g := _new_game()
	_quiet(g)
	var first := _put(g, 1, "t_cdm_vic")
	var second := _put(g, 1, "t_cdm_vic")
	var condemn_spec := {"action": "condemn", "target": "enemy_unit"}
	g._apply_effect(0, condemn_spec, first.uid)
	check(first.is_condemned() and not second.is_condemned(), "condenar marca só a unidade alvo")
	check(CondemnEffect.new().is_already_applied_to(first) and not CondemnEffect.new().is_already_applied_to(second), "condenada: já marcada conta como aplicada")
	var round_trip := Card.from_dict(first.to_dict(), "board", 1)
	check(round_trip.condemned_turn == first.condemned_turn, "condenada: a marca sobrevive a to_dict/from_dict")
	_quiet(g)
	g.end_turn(0)
	check(g.active == 1 and g.find_unit(first.uid) != null, "condenada no meu turno: segue viva no turno do dono")
	_quiet(g)
	g.end_turn(1)
	check(g.active == 0 and g.find_unit(first.uid) == null and g.find_unit(second.uid) != null, "condenada: morre no início do meu próximo turno")
	# marked during the opponent's own turn: it dies already at the start of my very next turn
	_quiet(g)
	g.end_turn(0)
	g._apply_effect(0, condemn_spec, second.uid)
	_quiet(g)
	g.end_turn(1)
	check(g.active == 0 and g.find_unit(second.uid) == null, "condenada no turno do dono: morre no início do meu turno seguinte")
	# Escudo de Feitiço cancels the mark
	g = _new_game()
	_quiet(g)
	var shielded := _put(g, 1, "t_cdm_vic")
	shielded.spell_shield = true
	g._apply_effect(0, condemn_spec, shielded.uid, SPELL_SOURCE)
	check(not shielded.is_condemned() and not shielded.spell_shield, "Escudo de Feitiço anula condenar")
	# Indestrutível survives, and the mark is spent
	var tough := _put(g, 1, "t_cdm_vic")
	tough.keywords.append("indestrutivel")
	g._apply_effect(0, condemn_spec, tough.uid)
	_quiet(g)
	g.end_turn(0)
	g.end_turn(1)
	check(g.find_unit(tough.uid) != null and not tough.is_condemned(), "Indestrutível resiste à condenação e a marca é gasta")
	# leaving the board undoes the mark
	var leaver := _put(g, 1, "t_cdm_vic")
	g._apply_effect(0, condemn_spec, leaver.uid)
	leaver.enter_board(false)
	check(not leaver.is_condemned(), "sair de campo desfaz a condenação")
	# the Ceifador marks two different enemy units, and they still die when it is gone
	g = _new_game()
	_quiet(g)
	var victim_a := _put(g, 1, "t_cdm_vic")
	var victim_b := _put(g, 1, "t_cdm_vic")
	var victim_c := _put(g, 1, "t_cdm_vic")
	g.players[0]["momentum"] = 10
	var reaper_uid := _give(g, 0, "ceifador_do_ultimo_toque")
	g.play_card(0, reaper_uid)
	if g.phase == "enter_target":
		g.choose_enter_target(0, victim_a.uid)
	check(g.phase == "enter_target", "Ceifador: depois do primeiro alvo pede o segundo")
	g.choose_enter_target(0, victim_a.uid)
	check(victim_a.is_condemned() == false and g.phase == "enter_target", "Ceifador: não deixa repetir o mesmo alvo")
	g.choose_enter_target(0, victim_c.uid)
	if g.summon_window:
		g.pass_priority(1)
	var marked := 0
	for victim in [victim_a, victim_b, victim_c]:
		if victim.is_condemned():
			marked += 1
	check(victim_a.is_condemned() and victim_c.is_condemned() and not victim_b.is_condemned() and marked == 2, "Ceifador: condena exatamente os dois alvos escolhidos")
	var reaper := g.find_unit(reaper_uid)
	if reaper != null:
		_kill(g, reaper)
	check(g.find_unit(reaper_uid) == null, "Ceifador removido de campo")
	_quiet(g)
	g.end_turn(0)
	g.end_turn(1)
	check(_count(g, 1, "t_cdm_vic") == 1, "as duas condenadas morrem mesmo sem o Ceifador em campo")

func _test_setup() -> void:
	var g := GameState.new("fogo", "agua", 1)
	check(g.players[0]["hand"].size() == GameState.START_HAND and g.players[1]["hand"].size() == GameState.START_HAND, "starting hands")
	check(g.players[0]["deck"].size() == DeckDB.DECK_SIZE - GameState.START_HAND, "incarnation not in deck")
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
	var a := _put(g, 0, "kai") # 2/2, Rapidez 1
	var b := _put(g, 1, "tritao_lanceiro") # 2/2, sem Rapidez, Ao Ser Desafiada: 1 de dano ao atacante
	check(g.attack_targets(a) == [GameState.LEADER_UID[1]], "unidade pronta não pode ser desafiada: só o Líder é alvo")
	b.exhausted = true
	check(g.attack_targets(a) == [b.uid, GameState.LEADER_UID[1]], "unidade exaurida pode ser desafiada (e não fecha o Líder)")
	_hit(g, a, b.uid)
	check(g.find_unit(b.uid) == null, "Rapidez 1 mata o desafiado (sem Rapidez) antes dele revidar")
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
	_put(g, 1, "t_c33") # standing (not tapped): it doesn't close the face
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
	check(g.attack_targets(rushing) == [tapped_enemy.uid, GameState.LEADER_UID[1]], "Ímpeto no turno seguinte: unidade normal, desafia a exaurida ou vai no Líder")
	g.players[1]["board"].erase(tapped_enemy)
	check(g.attack_targets(rushing) == [GameState.LEADER_UID[1]], "Ímpeto no turno seguinte: sem exauridas, o Líder volta a ser alvo")

	# Rompante: the turn it enters, the unit ignores ordinary tapped units and hits the Leader; only a tapped Provocação stops it
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
	check(g.attack_targets(charging) == [taunt_foe.uid], "Rompante recém-chegado: a Provocação exaurida a obriga a desafiar")
	check(_hit(g, charging).is_empty(), "Rompante recém-chegado não passa por cima da Provocação")
	g.players[1]["board"].erase(taunt_foe)
	var leader_before: int = g.players[1]["leader_hp"]
	_hit(g, charging, GameState.LEADER_UID[1])
	check(g.players[1]["leader_hp"] == leader_before - 1 and charging.exhausted, "Rompante bate no Líder e fica exausta")
	charging.sick = false
	charging.exhausted = false
	check(g.attack_targets(charging) == [tapped_foe.uid, GameState.LEADER_UID[1]], "Rompante no turno seguinte: unidade normal, desafia a exaurida ou vai no Líder")

	# Voo: a flying attacker sails over ordinary tapped units, so it may challenge them or hit the Leader
	g = _new_game()
	_quiet(g)
	var flyer := _put(g, 0, "gaivota_da_tempestade")
	var grounded_foe := _put(g, 1, "t_c33")
	grounded_foe.exhausted = true
	check(g.has_kw(flyer, "voo"), "teste Voo: a Gaivota da Tempestade voa")
	check(g.attack_targets(flyer) == [grounded_foe.uid, GameState.LEADER_UID[1]], "Voo: pode desafiar a exaurida ou ir direto no Líder")

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
	_put(g, 1, "serpente_marinha").exhausted = true
	check(g.attack_targets(obsessed) == [GameState.LEADER_UID[1]], "obsessão: só ataca o Líder")
	# ...but a tapped Provocação still holds it back: it must challenge it (a frozen one forces nothing)
	_tcard("t_obsession_taunt", 1, 6, [])
	CardDB.data()["cards"]["t_obsession_taunt"]["keywords"] = ["provocacao"]
	var obsession_taunt := _put(g, 1, "t_obsession_taunt")
	obsession_taunt.exhausted = true
	check(g.attack_targets(obsessed) == [obsession_taunt.uid], "obsessão: Provocação exaurida obriga a desafiar")
	obsession_taunt.frozen = 1
	check(g.attack_targets(obsessed) == [obsession_taunt.uid, GameState.LEADER_UID[1]], "obsessão: Provocação Congelada não obriga (desafia ou vai no Líder)")

	# Prudência (the opposite of Obsessão): it only challenges, the Leader's face is never a target
	g = _new_game()
	var wary := _put(g, 0, "tharox")
	check(g.has_kw(wary, "prudencia") and g.has_kw(_put(g, 0, "cryo_hulglack"), "prudencia") \
		and g.has_kw(_put(g, 0, "anciao_do_primeiro_bosque"), "prudencia"), "prudência: Tharox, Hulglack e Ancião têm")
	check(g.attack_targets(wary).is_empty(), "prudência: sem unidade exaurida para desafiar, não ataca (nem o Líder)")
	var wary_prey := _put(g, 1, "serpente_marinha")
	wary_prey.exhausted = true
	check(g.attack_targets(wary) == [wary_prey.uid], "prudência: desafia a unidade exaurida e nunca vai no Líder")
	check(g.attack_unit(0, wary.uid, GameState.LEADER_UID[1]).is_empty(), "prudência: o ataque direto ao Líder é recusado")

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
	# only Inalcançável enemies left: the screen keeps the aimed action enabled (to explain the refusal), the engine stays strict
	g.players[1]["board"] = [far]
	check(g.valid_targets(0, "enemy_unit").is_empty() and g.targets_blocked_by_reach(0, "enemy_unit"), "inalcançável: só ele no campo bloqueia o alvo por alcance")
	check(g.valid_targets(0, "enemy_unit", 0, true) == [far.uid], "inalcançável: aparece na lista quando se pede o motivo")
	g.players[1]["board"] = []
	check(not g.targets_blocked_by_reach(0, "enemy_unit"), "inalcançável: campo vazio não é bloqueio por alcance")

	# Roubo de Vida on the Leader's face
	g = _new_game()
	_quiet(g)
	var thief := _put(g, 0, "gorvakharr") # 4/3 roubo de vida
	g.players[0]["leader_hp"] = 10
	_hit(g, thief)
	check(g.players[0]["leader_hp"] == 14, "roubo de vida cura o Líder")

func _test_toque_letal() -> void:
	var legendary := CardDB.card("ceifador_do_ultimo_toque")
	var early := CardDB.card("rastejante_do_fim")
	check(CardDB.keyword("toque_letal")["name"] == "Toque Letal", "Toque Letal: keyword registrada")
	check(int(legendary["cost"]) == 10 and int(legendary["atk"]) == 3 and String(legendary["text"]).contains("condene"), "Ceifador: custo 10, ATK 3 e texto de Contrato com a Morte")
	check(int(early["cost"]) == 2 and early["rarity"] == "epic" and early["text"] == "", "Rastejante: épica de early game e texto vazio")

	_tcard("t_lethal", 1, 4, [])
	CardDB.data()["cards"]["t_lethal"]["keywords"] = ["toque_letal"]
	_tcard("t_target", 2, 4, [])
	_tcard("t_target_shield", 2, 4, [])
	CardDB.data()["cards"]["t_target_shield"]["keywords"] = ["escudo"]
	var g := _new_game()
	_quiet(g)
	var attacker := _put(g, 0, "t_lethal")
	var target := _put(g, 1, "t_target")
	target.exhausted = true
	_hit(g, attacker, target.uid)
	check(g.find_unit(target.uid) == null, "Toque Letal: dano de combate destrói a unidade")

	g = _new_game()
	_quiet(g)
	attacker = _put(g, 0, "t_lethal")
	var shielded := _put(g, 1, "t_target_shield")
	shielded.exhausted = true
	_hit(g, attacker, shielded.uid)
	check(g.find_unit(shielded.uid) != null and shielded.damage == 0 and not shielded.shield, "Toque Letal: Escudo bloqueia dano e impede a morte")

	_tcard("t_target_immune", 2, 4, [])
	CardDB.data()["cards"]["t_target_immune"]["keywords"] = ["indestrutivel"]
	g = _new_game()
	_quiet(g)
	attacker = _put(g, 0, "t_lethal")
	var immune := _put(g, 1, "t_target_immune")
	immune.exhausted = true
	_hit(g, attacker, immune.uid)
	check(g.find_unit(immune.uid) != null and immune.damage == 0, "Toque Letal: Indestrutível sobrevive")

func _test_toxico() -> void:
	check(CardDB.keyword("toxico")["name"] == "Tóxico", "Tóxico: keyword registrada")
	_tcard("t_toxic", 1, 4, [])
	CardDB.data()["cards"]["t_toxic"]["keywords"] = ["toxico"]
	_tcard("t_plain", 1, 6, [])
	_tcard("t_plain_shield", 1, 6, [])
	CardDB.data()["cards"]["t_plain_shield"]["keywords"] = ["escudo"]
	var g := _new_game()
	_quiet(g)
	var attacker := _put(g, 0, "t_toxic")
	var target := _put(g, 1, "t_plain")
	target.exhausted = true
	_hit(g, attacker, target.uid)
	check(int(target.dot_markers.get("veneno", 0)) == 1, "Tóxico: dano de combate coloca 1 marcador de Veneno")

	g = _new_game()
	_quiet(g)
	attacker = _put(g, 0, "t_toxic")
	var shielded := _put(g, 1, "t_plain_shield")
	shielded.exhausted = true
	_hit(g, attacker, shielded.uid)
	check(shielded.dot_markers.is_empty(), "Tóxico: dano bloqueado pelo Escudo não coloca Veneno")

	g = _new_game()
	_quiet(g)
	attacker = _put(g, 0, "t_toxic")
	_hit(g, attacker)
	check(attacker.dot_markers.is_empty() and g.players[1]["leader_hp"] < g.players[1]["leader_max"], "Tóxico: bater no Líder causa o dano e não coloca Veneno")

	g = _new_game()
	_quiet(g)
	attacker = _put(g, 0, "t_plain")
	var toxic_defender := _put(g, 1, "t_toxic")
	toxic_defender.exhausted = true # only exhausted units can be challenged
	_hit(g, attacker, toxic_defender.uid)
	check(int(attacker.dot_markers.get("veneno", 0)) == 1, "Tóxico: quem revida também envenena")

	# Tóxico X: the card's level is how many markers each hit leaves
	_tcard("t_toxic_three", 1, 4, [])
	CardDB.data()["cards"]["t_toxic_three"]["keywords"] = ["toxico"]
	CardDB.data()["cards"]["t_toxic_three"]["toxico_level"] = 3
	g = _new_game()
	_quiet(g)
	attacker = _put(g, 0, "t_toxic_three")
	target = _put(g, 1, "t_plain")
	target.exhausted = true
	_hit(g, attacker, target.uid)
	check(int(target.dot_markers.get("veneno", 0)) == 3, "Tóxico 3: dano de combate coloca 3 marcadores")

	# Tóxico X where X is the Ataque: temporary and permanent buffs both count
	_tcard("t_toxic_attack", 2, 9, [])
	CardDB.data()["cards"]["t_toxic_attack"]["keywords"] = ["toxico"]
	CardDB.data()["cards"]["t_toxic_attack"]["toxico_equals_attack"] = true
	g = _new_game()
	_quiet(g)
	attacker = _put(g, 0, "t_toxic_attack")
	attacker.atk += 2 # a permanent buff, like Zophiróx's
	attacker.temp_atk = 1
	target = _put(g, 1, "t_plain")
	target.exhausted = true
	_hit(g, attacker, target.uid)
	check(int(target.dot_markers.get("veneno", 0)) == 5, "Tóxico X = Ataque: 2 base +2 permanente +1 temporário = 5 marcadores")

	# the tag on the card face
	var level_three_data: Dictionary = CardDB.card("t_toxic_three")
	check(CardView.toxico_tag_of_view(level_three_data, {}) == "Tóxico 3", "Tag: Tóxico com nível mostra o número")
	check(CardView.toxico_tag_of_view(CardDB.card("t_toxic"), {}) == "Tóxico", "Tag: Tóxico comum não mostra número")
	var attack_data: Dictionary = CardDB.card("t_toxic_attack")
	check(CardView.toxico_tag_of_view(attack_data, {}) == "Tóxico X", "Tag: fora do campo o Tóxico por Ataque mostra X")
	check(CardView.toxico_tag_of_view(attack_data, attacker.to_dict()) == "Tóxico 5", "Tag: no campo mostra o Ataque atual")

	# Veneno on a unit deals 2 damage per marker, then removes half the pile rounded up; Queimadura is still consumed whole
	g = _new_game()
	_quiet(g)
	_tcard("t_decay_tank", 1, 60, [])
	var decaying := _put(g, 1, "t_decay_tank")
	g.add_dot_markers(decaying, "veneno", 3)
	g.add_dot_markers(decaying, "queimadura", 2)
	g.resolve_dot(decaying, "veneno")
	g.resolve_dot(decaying, "queimadura")
	check(decaying.damage == 8 and int(decaying.dot_markers.get("veneno", 0)) == 1, "Veneno em unidade: 3 marcadores causam 6 e caem para 1 depois do tick")
	check(int(decaying.dot_markers.get("queimadura", 0)) == 0, "Queimadura em unidade: continua sendo consumida inteira")
	g.resolve_dot(decaying, "veneno")
	g.resolve_dot(decaying, "veneno")
	check(int(decaying.dot_markers.get("veneno", 0)) == 0, "Veneno em unidade: a metade arredondada para cima some depois de 2 ticks")

## Veneno on Leaders: Tóxico exception per card, markers that tick but stay, the card-made kill at 12+ and the X+ banish.
func _test_leader_poison() -> void:
	_tcard("t_toxic_leader", 1, 4, [])
	CardDB.data()["cards"]["t_toxic_leader"]["keywords"] = ["toxico"]
	CardDB.data()["cards"]["t_toxic_leader"]["toxico_hits_leader"] = true
	var g := _new_game()
	_quiet(g)
	var attacker := _put(g, 0, "t_toxic_leader")
	_hit(g, attacker)
	check(g.leader_dot_markers(1, "veneno") == 1, "Veneno no Líder: Tóxico com exceção coloca 1 marcador ao bater no Líder")

	# the Leader's markers hurt it at the start of its controller's turn (2 per marker) and are consumed, like a unit's
	var leader_hp_before: int = g.players[1]["leader_hp"]
	g.end_turn(g.active)
	g._flush()
	check(g.players[1]["leader_hp"] == leader_hp_before - 2, "Veneno no Líder: no início do turno dele, 2 de dano por marcador")
	check(g.leader_dot_markers(1, "veneno") == 0, "Veneno no Líder: os marcadores são consumidos depois de causar dano")
	g.end_turn(g.active)
	g.end_turn(g.active)
	g._flush()
	check(g.players[1]["leader_hp"] == leader_hp_before - 2, "Veneno no Líder: sem marcadores, o turno seguinte não causa dano adicional")

	# Veneno loses half the pile rounded up: a pile of 3 hurts for 6, then 2
	g = _new_game()
	_quiet(g)
	g.add_leader_dot_markers(1, "veneno", 3)
	leader_hp_before = g.players[1]["leader_hp"]
	g.end_turn(g.active)
	g._flush()
	check(g.players[1]["leader_hp"] == leader_hp_before - 6 and g.leader_dot_markers(1, "veneno") == 1, "Veneno no Líder: 3 marcadores ferem 6 e sobra 1")
	g.end_turn(g.active)
	g.end_turn(g.active)
	g._flush()
	check(g.players[1]["leader_hp"] == leader_hp_before - 8 and g.leader_dot_markers(1, "veneno") == 0, "Veneno no Líder: no turno seguinte o marcador restante fere 2 e some")

	# Queimadura on a Leader is untouched by the decay rule: it still goes away in full
	g = _new_game()
	_quiet(g)
	g.add_leader_dot_markers(1, "queimadura", 3)
	g.end_turn(g.active)
	g._flush()
	check(g.leader_dot_markers(1, "queimadura") == 0, "Queimadura no Líder: continua sendo consumida inteira")

	# Tóxico X on a Leader: only a card with toxico_hits_leader leaves X markers, and X is its level
	_tcard("t_toxic_three", 1, 4, [])
	CardDB.data()["cards"]["t_toxic_three"]["keywords"] = ["toxico"]
	CardDB.data()["cards"]["t_toxic_three"]["toxico_level"] = 3
	CardDB.data()["cards"]["t_toxic_three"]["toxico_hits_leader"] = true
	g = _new_game()
	_quiet(g)
	attacker = _put(g, 0, "t_toxic_three")
	_hit(g, attacker)
	check(g.leader_dot_markers(1, "veneno") == 3, "Tóxico 3 com exceção: bater no Líder coloca 3 marcadores")

	# add_dot reaches a Leader through its negative uid
	g = _new_game()
	_quiet(g)
	var add_marker: Effect = EffectRegistry.parse_list([{"trigger": "on_play", "action": "add_dot", "target": "enemy_leader", "dot": "veneno", "amount": 3}])[0]
	add_marker.apply(EffectContext.new(g, 0, ""), GameState.LEADER_UID[1])
	check(g.leader_dot_markers(1, "veneno") == 3 and g.players[1]["leader_hp"] == g.players[1]["leader_max"], "Veneno no Líder: add_dot põe marcadores sem tirar Vida")

	# the engine never kills by markers alone: 12+ markers are harmless until a card effect asks
	add_marker = EffectRegistry.parse_list([{"trigger": "on_play", "action": "add_dot", "target": "enemy_leader", "dot": "veneno", "amount": 9}])[0]
	add_marker.apply(EffectContext.new(g, 0, ""), GameState.LEADER_UID[1])
	g._check_leaders()
	check(g.leader_dot_markers(1, "veneno") == 12 and g.phase != "over", "Veneno no Líder: 12 marcadores sozinhos não matam (não é regra do motor)")

	var execution: Effect = EffectRegistry.parse_list([{"trigger": "on_play", "action": "kill_leader", "target": "enemy_leader", "requires_markers": {"dot": "veneno", "amount": 12}}])[0]
	var short_game := _new_game()
	_quiet(short_game)
	short_game.add_leader_dot_markers(1, "veneno", 11)
	execution.apply(EffectContext.new(short_game, 0, ""), GameState.LEADER_UID[1])
	short_game._check_leaders()
	check(short_game.phase != "over", "kill_leader: com 11 marcadores nada acontece")
	execution.apply(EffectContext.new(g, 0, ""), GameState.LEADER_UID[1])
	g._check_leaders()
	check(g.players[1]["leader_hp"] <= 0 and g.phase == "over" and g.winner == 0, "kill_leader: com 12 marcadores o Líder morre na hora")

	# banish only if the unit holds enough markers
	g = _new_game()
	_quiet(g)
	_tcard("t_plain", 1, 6, [])
	var marked := _put(g, 1, "t_plain")
	var banish: Effect = EffectRegistry.parse_list([{"trigger": "on_play", "action": "banish", "target": "enemy_unit", "requires_markers": {"dot": "veneno", "amount": 3}}])[0]
	g.add_dot_markers(marked, "veneno", 2)
	banish.apply(EffectContext.new(g, 0, ""), marked.uid)
	check(g.find_unit(marked.uid) != null, "Banir por Veneno: com marcadores a menos nada acontece")
	g.add_dot_markers(marked, "veneno", 1)
	banish.apply(EffectContext.new(g, 0, ""), marked.uid)
	check(g.find_unit(marked.uid) == null, "Banir por Veneno: com marcadores suficientes a unidade é banida")

	# the AI must not aim Ponto Final Sem Vírgula at units that do not hold 3+ Veneno markers
	var ai_game := _new_game()
	_quiet(ai_game)
	var unpoisoned := _put(ai_game, 1, "t_plain")
	var barely_poisoned := _put(ai_game, 1, "t_plain")
	ai_game.add_dot_markers(barely_poisoned, "veneno", 2)
	var final_period := CardDB.card("ponto_final_sem_virgula")
	check(SimpleAI._pick_target(ai_game, 0, "enemy_unit", final_period, 0, true) == 0, "IA: sem alvo com 3+ marcadores de Veneno, Ponto Final Sem Vírgula não escolhe ninguém")
	ai_game.add_dot_markers(barely_poisoned, "veneno", 1)
	check(SimpleAI._pick_target(ai_game, 0, "enemy_unit", final_period, 0, true) == barely_poisoned.uid, "IA: Ponto Final Sem Vírgula mira a unidade com 3+ marcadores de Veneno, e só ela")

	# the human player gets the same rule: units without 3+ Veneno are not valid targets, and playing on one is refused
	var human_game := _new_game()
	_quiet(human_game)
	var caster: int = human_game.active
	var foe := 1 - caster
	var weak_victim := _put(human_game, foe, "t_plain")
	var poisoned_victim := _put(human_game, foe, "t_plain")
	human_game.add_dot_markers(weak_victim, "veneno", 2)
	var final_period_uid := _give(human_game, caster, "ponto_final_sem_virgula")
	human_game.players[caster]["momentum"] = 10
	check(human_game.card_targets(caster, final_period).is_empty() and not human_game.can_play(caster, final_period_uid), "Ponto Final Sem Vírgula: ninguém com 3+ Veneno, a carta não pode ser jogada")
	check(human_game.play_card(caster, final_period_uid, weak_victim.uid).is_empty() and human_game.find_unit(weak_victim.uid) != null, "Ponto Final Sem Vírgula: jogar em unidade com 2 Veneno é recusado")
	human_game.add_dot_markers(poisoned_victim, "veneno", 3)
	check(human_game.card_targets(caster, final_period) == [poisoned_victim.uid], "Ponto Final Sem Vírgula: só a unidade com 3+ Veneno é alvo")
	check(human_game.valid_targets(caster, "enemy_unit", 0, false, final_period["effects"]) == [poisoned_victim.uid], "valid_targets filtra por requires_markers")

## Antídoto Fora de Estoque (the Leader's Veneno stays for its next 2 turns) and Greve Geral dos Antídotos
## (nobody's Veneno is consumed for one turn start of each player). Both still hurt, and both expire.
func _test_veneno_hold() -> void:
	_tcard("t_hold_dummy", 1, 30, [])

	# Antídoto Fora de Estoque: 1 marker now, and the Leader's markers survive its next two turn starts
	var g := _new_game()
	_quiet(g)
	var caster: int = g.active
	var victim := 1 - caster
	var antidote_effects := EffectRegistry.parse_list(CardDB.card("antidoto_fora_de_estoque")["effects"])
	for antidote_effect: Effect in antidote_effects:
		antidote_effect.apply(EffectContext.new(g, caster, ""), GameState.LEADER_UID[victim])
	g.add_leader_dot_markers(victim, "veneno", 2)
	var poisoned_unit := _put(g, victim, "t_hold_dummy")
	g.add_dot_markers(poisoned_unit, "veneno", 1)
	var leader_hp_start: int = g.players[victim]["leader_hp"]
	_next_turn(g) # the victim's first turn start
	check(g.players[victim]["leader_hp"] == leader_hp_start - 6, "Antídoto: o Veneno do Líder ainda fere (3 marcadores = 6 de dano)")
	check(g.leader_dot_markers(victim, "veneno") == 3, "Antídoto: os marcadores do Líder ficam no primeiro turno dele")
	check(poisoned_unit.dot_markers.get("veneno", 0) == 0, "Antídoto: só vale pro Líder, o Veneno de unidade é consumido normal")
	_next_turn(g)
	_next_turn(g) # the victim's second turn start
	check(g.leader_dot_markers(victim, "veneno") == 3 and g.players[victim]["leader_hp"] == leader_hp_start - 12, "Antídoto: ferem e ficam também no segundo turno dele")
	_next_turn(g)
	_next_turn(g) # the victim's third turn start: the hold is over
	check(g.leader_dot_markers(victim, "veneno") == 1 and g.players[victim]["leader_hp"] == leader_hp_start - 18, "Antídoto: no terceiro turno o Veneno fere e remove metade arredondada para cima")

	# Greve Geral dos Antídotos: units and Leaders keep their Veneno for one turn start of each player
	g = _new_game()
	_quiet(g)
	caster = g.active
	victim = 1 - caster
	var strike_effect: Effect = EffectRegistry.parse_list(CardDB.card("greve_geral_dos_antidotos")["effects"])[0]
	strike_effect.apply(EffectContext.new(g, caster, ""), 0)
	var enemy_unit := _put(g, victim, "t_hold_dummy")
	var own_unit := _put(g, caster, "t_hold_dummy")
	g.add_dot_markers(enemy_unit, "veneno", 2)
	g.add_dot_markers(enemy_unit, "queimadura", 1)
	g.add_dot_markers(own_unit, "veneno", 1)
	g.add_leader_dot_markers(victim, "veneno", 2)
	_next_turn(g) # the victim's turn start
	check(enemy_unit.dot_markers.get("veneno", 0) == 2 and g.leader_dot_markers(victim, "veneno") == 2, "Greve: unidade e Líder inimigos mantêm o Veneno no turno do dono")
	check(enemy_unit.dot_markers.get("queimadura", 0) == 0, "Greve: só segura Veneno, Queimadura continua sendo consumida")
	_next_turn(g) # the caster's turn start
	check(own_unit.dot_markers.get("veneno", 0) == 1, "Greve: o Veneno de quem jogou também fica no turno dele")
	_next_turn(g) # the victim's next turn start: the hold is over
	check(enemy_unit.dot_markers.get("veneno", 0) == 1 and g.leader_dot_markers(victim, "veneno") == 1, "Greve: depois da rodada, o Veneno volta a cair pela metade")
	_next_turn(g)
	check(own_unit.dot_markers.get("veneno", 0) == 0, "Greve: o Veneno de quem jogou também volta a cair pela metade")

## Neráxia: until the start of the caster's next turn, the Veneno tick takes all the Vida a poisoned unit has left.
## The window closes right before the caster's own tick, so only the opponent's units are reached, and only once.
func _test_hulglack_death_freeze() -> void:
	# Cryo Hulglack: Ao Morrer congela 3 unidades inimigas aleatórias, sempre 3 diferentes
	var g := _new_game()
	_quiet(g)
	var hulglack := _put(g, 0, "cryo_hulglack")
	var foes: Array = [_put(g, 1, "geodo_vivo"), _put(g, 1, "geodo_vivo"), _put(g, 1, "geodo_vivo"), _put(g, 1, "geodo_vivo")]
	_kill(g, hulglack)
	var frozen_count := foes.filter(func(foe: Card): return foe.frozen > 0).size()
	check(frozen_count == 3, "Cryo Hulglack: ao morrer congela exatamente 3 unidades inimigas diferentes (%d)" % frozen_count)
	var few := _new_game()
	_quiet(few)
	var lone_hulglack := _put(few, 0, "cryo_hulglack")
	var only_foes: Array = [_put(few, 1, "geodo_vivo"), _put(few, 1, "geodo_vivo")]
	_kill(few, lone_hulglack)
	check(only_foes.all(func(foe: Card): return foe.frozen > 0), "Cryo Hulglack: com menos de 3 inimigas, congela todas as que existem")

func _test_veneno_lethal() -> void:
	_tcard("t_lethal_dummy", 1, 10, [])
	var g := _new_game()
	_quiet(g)
	var caster: int = g.active
	var victim := 1 - caster
	var lethal_effect: Effect = EffectRegistry.parse_list(CardDB.card("neraxia_flor_do_ultimo_suspiro")["effects"])[0]
	lethal_effect.apply(EffectContext.new(g, caster, ""), 0)
	var enemy_unit := _put(g, victim, "t_lethal_dummy")
	var enemy_unit_without_poison := _put(g, victim, "t_lethal_dummy")
	var own_unit := _put(g, caster, "t_lethal_dummy")
	g.add_dot_markers(enemy_unit, "veneno", 1)
	g.add_dot_markers(own_unit, "veneno", 1)
	var enemy_leader_hp_before: int = g.players[victim]["leader_hp"]
	g.add_leader_dot_markers(victim, "veneno", 1)
	_next_turn(g) # the victim's turn start: inside the window
	check(not g.players[victim]["board"].has(enemy_unit), "Neráxia: o tique de Veneno mata a unidade inimiga envenenada (10 de Vida, 1 marcador)")
	check(g.players[victim]["board"].has(enemy_unit_without_poison), "Neráxia: unidade sem Veneno não é afetada")
	check(g.players[victim]["leader_hp"] == enemy_leader_hp_before - 2, "Neráxia: o Líder não é unidade e leva o tique normal")
	_next_turn(g) # the caster's turn start: the window is already closed
	check(own_unit.hp_left() == 8, "Neráxia: a unidade envenenada de quem jogou leva só o tique normal (2)")

	# a second, later tick on an enemy unit is back to normal
	g = _new_game()
	_quiet(g)
	caster = g.active
	victim = 1 - caster
	lethal_effect.apply(EffectContext.new(g, caster, ""), 0)
	_next_turn(g) # the victim's first turn start (inside the window)
	_next_turn(g) # the caster's turn start
	var late_unit := _put(g, victim, "t_lethal_dummy")
	g.add_dot_markers(late_unit, "veneno", 1)
	_next_turn(g) # the victim's second turn start after the cast: the window is over
	check(late_unit.hp_left() == 8, "Neráxia: depois da janela o Veneno volta ao tique normal (2)")

## Ends the active player's turn and settles everything that starts the next one.
func _next_turn(g: GameState) -> void:
	g.end_turn(g.active)
	g._flush()

## Hikari's Decoy: a 0/2 inert token that takes the blow in her place (when challenged) or the counter-blow
## (when she challenges, but only if she would have suffered it).
## Innate immunity to markers by essence: Venenosa and Metálica ignore Veneno, Ígnea ignores
## Queimadura (units and Leaders alike); effects that say "ignores_immunity" go through anyway.
func _test_dot_immunity() -> void:
	_tcard("t_neutral_target", 1, 9, [])
	var g := _new_game()
	_quiet(g)
	var poison_unit := _put(g, 1, "cobra_de_sofa") # Venenosa
	var steel_unit := _put(g, 1, "fresadora_dona_cleide") # Metálica
	var fire_unit := _put(g, 1, "irina_lancachamas") # Ígnea
	var plain_unit := _put(g, 1, "t_neutral_target")

	g.add_dot_markers(poison_unit, "veneno", 2)
	g.add_dot_markers(steel_unit, "veneno", 2)
	check(poison_unit.dot_markers.get("veneno", 0) == 0, "Imunidade: unidade Venenosa não recebe Veneno")
	check(steel_unit.dot_markers.get("veneno", 0) == 0, "Imunidade: unidade Metálica não recebe Veneno")
	g.add_dot_markers(poison_unit, "queimadura", 1)
	check(poison_unit.dot_markers.get("queimadura", 0) == 1, "Imunidade: Venenosa continua vulnerável à Queimadura")

	g.add_dot_markers(fire_unit, "queimadura", 2)
	check(fire_unit.dot_markers.get("queimadura", 0) == 0, "Imunidade: unidade Ígnea não recebe Queimadura")
	g.add_dot_markers(fire_unit, "veneno", 1)
	check(fire_unit.dot_markers.get("veneno", 0) == 1, "Imunidade: Ígnea continua vulnerável ao Veneno")
	g.add_dot_markers(plain_unit, "veneno", 1)
	g.add_dot_markers(plain_unit, "queimadura", 1)
	check(plain_unit.dot_markers.get("veneno", 0) == 1 and plain_unit.dot_markers.get("queimadura", 0) == 1, "Imunidade: unidade neutra recebe tudo")

	# the immune float: an event, and nothing is added
	g.add_dot_markers(poison_unit, "veneno", 3)
	check(poison_unit.dot_markers.get("veneno", 0) == 0, "Imunidade: segunda tentativa também é barrada")

	# an effect that ignores immunity goes through
	g.add_dot_markers(poison_unit, "veneno", 2, true)
	g.add_dot_markers(fire_unit, "queimadura", 2, true)
	check(poison_unit.dot_markers.get("veneno", 0) == 2 and fire_unit.dot_markers.get("queimadura", 0) == 2, "Imunidade: ignores_immunity passa por cima")
	var bypass: Effect = EffectRegistry.parse_list([{"trigger": "on_play", "action": "add_dot", "dot": "veneno", "target": "enemy_unit", "amount": 1, "ignores_immunity": true}])[0]
	bypass.apply(EffectContext.new(g, 0, ""), steel_unit.uid)
	check(steel_unit.dot_markers.get("veneno", 0) == 1, "Imunidade: o efeito add_dot com ignores_immunity coloca Veneno em Metálica")
	var blocked: Effect = EffectRegistry.parse_list([{"trigger": "on_play", "action": "add_dot", "dot": "veneno", "target": "enemy_unit", "amount": 1}])[0]
	blocked.apply(EffectContext.new(g, 0, ""), steel_unit.uid)
	check(steel_unit.dot_markers.get("veneno", 0) == 1, "Imunidade: o mesmo efeito sem a marca é barrado")

	# Leaders have no immunity: Venenosa and Metálica Leaders take Veneno, an Ígnea Leader takes Queimadura
	for leader_id in ["tox_vipranna", "morakhan"]:
		g.players[1]["leader_id"] = leader_id
		var poison_before: int = g.leader_dot_markers(1, "veneno")
		g.add_leader_dot_markers(1, "veneno", 2)
		check(g.leader_dot_markers(1, "veneno") == poison_before + 2, "Líder %s aceita Veneno (Líderes não têm imunidade)" % leader_id)
	g.players[1]["leader_id"] = "ronan"
	g.add_leader_dot_markers(1, "queimadura", 2)
	check(g.leader_dot_markers(1, "queimadura") == 2, "Líder Ígneo aceita Queimadura")

	# Tóxico: Viprax's combat poison ignores it, a plain Tóxico unit does not
	var g2 := _new_game()
	_quiet(g2)
	var viprax := _put(g2, 0, "viprax")
	var plain_toxic := _put(g2, 0, "naja_cobradora")
	var steel_victim := _put(g2, 1, "fresadora_dona_cleide")
	g2.add_dot_markers(steel_victim, "veneno", 1, viprax.data().get("toxico_ignores_immunity", false))
	check(steel_victim.dot_markers.get("veneno", 0) == 1, "Imunidade: Viprax marca o Tóxico para ignorar imunidade")
	check(not plain_toxic.data().get("toxico_ignores_immunity", false), "Imunidade: Tóxico comum não ignora imunidade")

	# Viprax's Ao Ativar adds a marker first, so 7 markers are already enough; 6 are not
	var execution_game := _new_game()
	_quiet(execution_game)
	var executioner := _put(execution_game, 0, "viprax")
	execution_game.players[0]["momentum"] = 6
	execution_game.add_leader_dot_markers(1, "veneno", 6)
	execution_game.activate(0, executioner.uid)
	execution_game._flush()
	check(execution_game.leader_dot_markers(1, "veneno") == 7 and execution_game.phase != "over", "Viprax: Ao Ativar com 6 marcadores coloca o 7º e o Líder sobrevive")
	executioner.activated_turn = -1
	var execution_events: Array = execution_game.activate(0, executioner.uid)
	check(execution_game.phase == "over" and execution_game.winner == 0, "Viprax: Ao Ativar com 7 marcadores coloca o 8º e executa o Líder")
	var executed_events := execution_events.filter(func(e): return e["type"] == "leader_executed")
	var leader_damage_events := execution_events.filter(func(e): return e["type"] == "damage" and e["uid"] == GameState.LEADER_UID[1])
	check(executed_events.size() == 1 and executed_events[0]["hp_before"] > 0, "Execução: emite um evento leader_executed com a Vida anterior do Líder")
	check(leader_damage_events.is_empty(), "Execução: o Líder não recebe evento de dano (a UI toca a animação própria)")

	# the printed cards: D'Lorafya's Queimadura and Tox Vipranna's Veneno carry the flag
	var dlorafya_effects: Array = CardDB.card("dlorafya")["effects"]
	check(dlorafya_effects.any(func(e): return e.get("action", "") == "add_dot" and e.get("ignores_immunity", false)), "Imunidade: D'Lorafya ignora imunidade")
	check(CardDB.card("tox_vipranna")["effects"][0].get("ignores_immunity", false), "Imunidade: Tox Vipranna ignora imunidade ao entrar")
	check(CardDB.leader("tox_vipranna")["ability"]["effects"][0].get("ignores_immunity", false), "Imunidade: Beijo de Jardim ignora imunidade")

func _test_hikari_decoy() -> void:
	_tcard("t_hitter", 3, 5, []) # strikes at Rapidez 0
	_tcard("t_counter", 2, 5, [])
	_tcard("t_frail", 2, 3, [])
	var decoy_count := func(g: GameState, p: int) -> int:
		var total := 0
		for unit: Card in g.players[p]["board"]:
			if unit.card_id == "hikari_dummy":
				total += 1
		return total

	# challenged: the Decoy takes the blow and Hikari is untouched; the token leaves no card behind
	var g := _new_game()
	_quiet(g)
	var hikari := _put(g, 1, "hikari")
	hikari.exhausted = true
	var hitter := _put(g, 0, "t_hitter")
	var second_hitter := _put(g, 0, "t_hitter") # ready before combat starts, so the same combat goes on
	_hit(g, hitter, hikari.uid) # no _pass_windows here: passing in the attacks window would end the combat
	check(hikari.damage == 0 and hitter.damage == 0, "Decoy: ao ser desafiada, a Hikari não recebe o golpe (e nada volta no atacante)")
	check(decoy_count.call(g, 1) == 0 and g.players[1]["graveyard"].is_empty(), "Decoy: a ficha morre e não deixa carta no cemitério")
	# once per turn: a second challenger in the same turn hits Hikari for real
	_hit(g, second_hitter, hikari.uid)
	check(g.find_unit(hikari.uid) == null and decoy_count.call(g, 1) == 0, "Decoy: só uma vez por turno ao ser desafiada")

	# board full: no room for the Decoy, Hikari takes the blow
	g = _new_game()
	_quiet(g)
	hikari = _put(g, 1, "hikari")
	hikari.exhausted = true
	while g.has_free_slot(1):
		_put(g, 1, "t_frail")
	hitter = _put(g, 0, "t_hitter")
	_hit(g, hitter, hikari.uid)
	_pass_windows(g)
	check(g.find_unit(hikari.uid) == null, "Decoy: campo cheio, a Hikari recebe o golpe")

	# challenging: the counter-blow lands on the Decoy
	g = _new_game()
	_quiet(g)
	hikari = _put(g, 0, "hikari")
	var counter := _put(g, 1, "t_counter")
	counter.exhausted = true
	_hit(g, hikari, counter.uid)
	_pass_windows(g)
	check(counter.damage == 3 and hikari.damage == 0, "Decoy: ao desafiar, o revide cai no Decoy (alvo %d, Hikari %d)" % [counter.damage, hikari.damage])
	check(decoy_count.call(g, 0) == 0, "Decoy: o Decoy que tomou o revide morreu (0/2 contra 2 de dano)")

	# challenging something she kills first (Rapidez 1 vs 0): no counter-blow, so no Decoy is summoned
	g = _new_game()
	_quiet(g)
	hikari = _put(g, 0, "hikari")
	var frail := _put(g, 1, "t_frail")
	frail.exhausted = true
	_hit(g, hikari, frail.uid)
	_pass_windows(g)
	check(g.find_unit(frail.uid) == null and hikari.damage == 0, "Decoy: Hikari mata antes e não sofre revide")
	check(decoy_count.call(g, 0) == 0, "Decoy: sem revide para evitar, nada é invocado")

	# the Decoy itself never attacks or taps
	g = _new_game()
	var token := _put(g, 0, "hikari_dummy")
	check(not g.can_attack(token), "Decoy: inerte, não pode atacar")
	var tapper: Effect = EffectRegistry.parse_list([{"action": "exhaust", "target": "enemy_unit"}])[0]
	tapper.apply(EffectContext.new(g, 1, ""), token.uid)
	check(not token.exhausted, "Decoy: inerte, nem efeito consegue virá-lo")

## The Venenosa cards that need engine support: Hikari's damage per marker, Tox Vipranna healing from
## Veneno ticks, Az'Kharon poisoning whoever challenges it.
func _test_venenosa_deck() -> void:
	check(DeckDB.validate("venenosa").is_empty(), "deck Jardim da Rainha Tox é legal: %s" % [DeckDB.validate("venenosa")])
	_tcard("t_target_dummy", 1, 12, [])

	# Hikari: 2 damage per Veneno marker on the target (no markers = no damage)
	var g := _new_game()
	_quiet(g)
	var dummy := _put(g, 1, "t_target_dummy")
	var hikari_damage: Effect = EffectRegistry.parse_list(CardDB.card("hikari")["effects"])[0]
	hikari_damage.apply(EffectContext.new(g, 0, ""), dummy.uid)
	check(dummy.damage == 0, "Hikari: sem marcadores de Veneno não causa dano")
	g.add_dot_markers(dummy, "veneno", 3)
	hikari_damage.apply(EffectContext.new(g, 0, ""), dummy.uid)
	check(dummy.damage == 6, "Hikari: 3 marcadores de Veneno = 6 de dano")

	# Tox Vipranna: an enemy unit taking Veneno damage heals her owner's Leader by 2
	g = _new_game()
	_quiet(g)
	var vipranna := _put(g, 0, "tox_vipranna")
	var poisoned := _put(g, 1, "t_target_dummy")
	g.players[0]["leader_max"] = 100
	g.players[0]["leader_hp"] = 20
	g.add_dot_markers(poisoned, "veneno", 2)
	g.resolve_dot(poisoned, "veneno")
	g._check_state()
	check(g.players[0]["leader_hp"] == 22 and vipranna.temp_hp_until_next_turn == 1 and vipranna.vipranna_heal_total == 2, "Tox Vipranna: 2 marcadores causam 4, curam 2 e dão +1 Vida temporária")
	# The cap is per turn and per Vipranna; the trigger that crosses 15 still resolves in full.
	var big_target := _put(g, 1, "t_target_dummy") # 6 markers hurt for 12, half is 6
	g.players[0]["leader_hp"] = 20
	g.add_dot_markers(big_target, "veneno", 6)
	g.resolve_dot(big_target, "veneno")
	g._check_state()
	check(g.players[0]["leader_hp"] == 26 and vipranna.temp_hp_until_next_turn == 2 and vipranna.vipranna_heal_total == 8, "Tox Vipranna: tick de 12 de dano cura 6 e acumula 8 no turno")
	var odd_target := _put(g, 1, "t_target_dummy") # 9 markers hurt for 18, half is 9: the total goes from 8 to 17
	g.players[0]["leader_hp"] = 20
	g.add_dot_markers(odd_target, "veneno", 9)
	g.resolve_dot(odd_target, "veneno")
	g._check_state()
	check(g.players[0]["leader_hp"] == 29 and vipranna.vipranna_heal_locked and vipranna.vipranna_heal_total == 17, "Tox Vipranna: a cura que cruza 15 resolve inteira e bloqueia as seguintes")
	_tcard("t_small_tank", 1, 5, [])
	var small_target := _put(g, 1, "t_small_tank") # 1 marker hurts for 2, half is 1 (below the minimum of 2)
	g.players[0]["leader_hp"] = 20
	g.add_dot_markers(small_target, "veneno", 1)
	g.resolve_dot(small_target, "veneno")
	g._check_state()
	check(g.players[0]["leader_hp"] == 20 and vipranna.temp_hp_until_next_turn == 3, "Tox Vipranna: depois de cruzar 15 nenhum trigger futuro cura ou dá Vida temporária")
	g.players[0]["leader_hp"] = 20
	var own_poisoned := _put(g, 0, "t_target_dummy")
	g.add_dot_markers(own_poisoned, "veneno", 2)
	g.resolve_dot(own_poisoned, "veneno")
	g._check_state()
	check(g.players[0]["leader_hp"] == 20, "Tox Vipranna: Veneno em unidade aliada não cura")
	# the Leader ticks heal her owner too: 2 damage per marker, half rounded up, minimum 2
	g = _new_game()
	_quiet(g)
	vipranna = _put(g, 0, "tox_vipranna")
	g.players[0]["leader_max"] = 100
	g.players[0]["leader_hp"] = 20
	g.add_leader_dot_markers(1, "veneno", 5)
	g._resolve_leader_dot(1, "veneno")
	g._check_state()
	check(g.players[0]["leader_hp"] == 25, "Tox Vipranna: tick de 10 de Veneno no Líder inimigo cura 5")
	g.players[0]["leader_hp"] = 20
	g.players[1]["leader_dots"].clear() # isolate the next tick
	g.add_leader_dot_markers(1, "veneno", 1)
	g._resolve_leader_dot(1, "veneno")
	g._check_state()
	check(g.players[0]["leader_hp"] == 22, "Tox Vipranna: tick de 1 de Veneno no Líder inimigo cura o mínimo de 2")
	g.players[0]["leader_hp"] = 20
	g.add_leader_dot_markers(0, "veneno", 4)
	g._resolve_leader_dot(0, "veneno")
	check(g.players[0]["leader_hp"] == 12, "Tox Vipranna: Veneno no Líder dela causa 2 por marcador e não cura")
	check(vipranna.temp_hp_until_next_turn == 2, "Tox Vipranna: cada trigger aceito acumula Vida temporária")
	g._deal_damage(vipranna.uid, 1, null)
	check(vipranna.hp_left() == 6, "Tox Vipranna: a Vida temporária absorve dano antes de expirar")
	g._start_turn(vipranna.owner, false)
	check(vipranna.temp_hp_until_next_turn == 0 and vipranna.damage == 0, "Tox Vipranna: a Vida temporária dura até o início do próximo turno dela")
	var reset_target := _put(g, 1, "t_target_dummy")
	g.players[0]["leader_hp"] = 20
	g.add_dot_markers(reset_target, "veneno", 1)
	g.resolve_dot(reset_target, "veneno")
	g._check_state()
	check(g.players[0]["leader_hp"] == 22 and vipranna.vipranna_heal_total == 2 and not vipranna.vipranna_heal_locked, "Tox Vipranna: o limite de 15 reinicia no turno seguinte")

	# Julian: played from the hand, his Ao Entrar asks for two picks after he enters: who takes the 2 damage, then who gets the Veneno
	g = _new_game()
	_quiet(g)
	var julian_hurt := _put(g, 1, "t_target_dummy")
	var julian_poisoned := _put(g, 1, "t_target_dummy")
	var julian_uid := _give(g, 0, "julian")
	g.players[0]["momentum"] = 10
	check(not g.play_card(0, julian_uid).is_empty(), "Julian: dá pra jogar da mão sem alvo extra")
	check(g.phase == "enter_target" and not g.pending_enter.has("first"), "Julian: primeiro pede o alvo do dano")
	g.choose_enter_target(0, julian_hurt.uid)
	check(g.phase == "enter_target" and int(g.pending_enter.get("first", 0)) == julian_hurt.uid, "Julian: depois do primeiro alvo pede o segundo (Veneno)")
	g.choose_enter_target(0, julian_poisoned.uid)
	g.stack_system().settle()
	g._flush()
	check(julian_hurt.damage == 2 and int(julian_hurt.dot_markers.get("veneno", 0)) == 0, "Julian: o primeiro alvo toma 2 de dano e nenhum Veneno")
	check(julian_poisoned.damage == 0 and int(julian_poisoned.dot_markers.get("veneno", 0)) == 1, "Julian: o segundo alvo toma 1 Veneno e nenhum dano")
	# the same unit may take both
	g = _new_game()
	_quiet(g)
	var julian_both := _put(g, 1, "t_target_dummy")
	julian_uid = _give(g, 0, "julian")
	g.players[0]["momentum"] = 10
	g.play_card(0, julian_uid)
	g.choose_enter_target(0, julian_both.uid)
	g.choose_enter_target(0, julian_both.uid)
	g.stack_system().settle()
	g._flush()
	check(julian_both.damage == 2 and int(julian_both.dot_markers.get("veneno", 0)) == 1, "Julian: pode dar dano e Veneno na mesma unidade")
	# declining the second pick keeps the damage and drops only the Veneno
	g = _new_game()
	_quiet(g)
	var julian_half := _put(g, 1, "t_target_dummy")
	julian_uid = _give(g, 0, "julian")
	g.players[0]["momentum"] = 10
	g.play_card(0, julian_uid)
	g.choose_enter_target(0, julian_half.uid)
	g.choose_enter_target(0, 0)
	g.stack_system().settle()
	g._flush()
	check(g.phase == "main" and julian_half.damage == 2 and int(julian_half.dot_markers.get("veneno", 0)) == 0, "Julian: pular o segundo alvo mantém o dano e tira só o Veneno")
	# no unit may ask for a second pick when played: its picks are asked after it enters
	for unit_id in CardDB.data()["cards"]:
		var unit_data: Dictionary = CardDB.card(unit_id)
		if unit_data["type"] == "unit":
			check(g.second_spec(unit_data) == "", "%s: unidade não pede segundo alvo ao ser jogada (o Ao Entrar pergunta depois)" % unit_id)

	# Az'Kharon: the unit that challenges it leaves with 1 Veneno marker
	g = _new_game()
	_quiet(g)
	var wall := _put(g, 1, "azkharon")
	var challenger := _put(g, 0, "t_target_dummy")
	g.stack_system().settle() # Az'Kharon's own Ao Entrar must be resolved before combat can open
	wall.exhausted = true # a unit can only be challenged while tapped
	_hit(g, challenger, wall.uid)
	_pass_windows(g)
	check(int(challenger.dot_markers.get("veneno", 0)) == 1, "Az'Kharon: quem a desafia recebe 1 marcador de Veneno")

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

## Janela B: a declared attack is only answered when it matters and the defender really can answer.
## A fresh game where player 1 (the defender) holds only the given cards and has the given Momentum.
func _reaction_game(defender_cards: Array, defender_momentum: int) -> GameState:
	var g := _new_game()
	_quiet(g)
	g.players[1]["hand"] = []
	g.players[1]["momentum"] = defender_momentum
	for card_id in defender_cards:
		_give(g, 1, card_id)
	return g

func _test_reaction() -> void:
	_tcard("t_hitter", 2, 3, [])
	_tcard("t_sponge", 1, 9, [])
	_tcard("t_glass", 1, 2, [])
	# Instantâneos with a real cost, so "enough Momentum" matters
	_tspell("t_react_heal", "instantaneo", [{"trigger": "on_play", "action": "buff", "target": "any_unit", "hp": 3}])
	_tspell("t_react_kill", "instantaneo", [{"trigger": "on_play", "action": "damage", "target": "any_unit", "amount": 9}])
	CardDB.data()["cards"]["t_react_heal"]["cost"] = 2
	CardDB.data()["cards"]["t_react_kill"]["cost"] = 2
	var leader_max: int = GameState.new("fogo", "agua", 1).players[1]["leader_hp"]

	# no Instantâneo in hand: the attack lands without anybody being asked
	var g := _reaction_game([], 5)
	var hitter := _put(g, 0, "t_hitter")
	_hit(g, hitter)
	check(not g.combat_system().is_reacting(1) and g.priority == 0, "reagir: sem Instantânea na mão ninguém é perguntado")
	check(g.players[1]["leader_hp"] == leader_max - 2, "reagir: sem Instantânea o dano ao Líder cai na hora")

	# an Instantâneo and Momentum for it, attack on the Leader: the defender is asked and the blows wait
	g = _reaction_game(["t_react_heal"], 5)
	hitter = _put(g, 0, "t_hitter")
	g.players[1]["leader_hp"] = 18
	_hit(g, hitter)
	check(not g.combat_system().is_reacting(1) and g.players[1]["leader_hp"] == 16, "reagir: ataque à face que deixa o Líder acima de 15 não abre janela")

	# an attack that would leave the Leader at 15 HP opens the reaction window
	g = _reaction_game(["t_react_heal"], 5)
	hitter = _put(g, 0, "t_hitter")
	var second_hitter := _put(g, 0, "t_hitter")
	g.players[1]["leader_hp"] = 17
	var events := _hit(g, hitter)
	check(_has_event(events, "reaction"), "reagir: o ataque ao Líder emite o evento de reação")
	check(g.combat_system().is_reacting(1) and g.priority == 1 and g.decider() == 1, "reagir: o defensor recebe a prioridade")
	check(g.players[1]["leader_hp"] == 17, "reagir: enquanto o defensor decide, o dano não caiu")
	check(not g.combat_system().in_attacks_window(0) and g.attack_unit(0, second_hitter.uid, GameState.LEADER_UID[1]).is_empty(), "reagir: o atacante espera, não declara outro ataque")
	check(g.pass_priority(0).is_empty() and g.end_combat(0).is_empty(), "reagir: o atacante também não encerra o combate")

	# passing the prompt lets the attack land and gives the turn owner the next attack back
	g.pass_priority(1)
	check(g.players[1]["leader_hp"] == 15 and not g.combat_system().is_reacting(1), "reagir: passar deixa o ataque acontecer")
	check(g.priority == 0 and g.combat_system().in_attacks_window(0) and g.combat_system().pending_attack.is_empty(), "reagir: depois de passar o dono do turno volta a atacar")
	_hit(g, second_hitter)
	check(g.combat_system().is_reacting(1), "reagir: o segundo ataque pergunta de novo")

	# not enough Momentum for the Instantâneo (cost 2): not asked
	g = _reaction_game(["t_react_heal"], 1)
	g.players[1]["leader_hp"] = 17
	_hit(g, _put(g, 0, "t_hitter"))
	check(not g.combat_system().is_reacting(1) and g.players[1]["leader_hp"] == 15, "reagir: sem Momentum para a Instantânea ninguém é perguntado")

	# a challenge that cannot kill anybody (2 dmg vs 9 HP, 1 counter vs 3 HP): not asked
	g = _reaction_game(["t_react_heal"], 5)
	hitter = _put(g, 0, "t_hitter")
	var sponge := _put(g, 1, "t_sponge")
	sponge.exhausted = true # only a tapped unit can be challenged
	_hit(g, hitter, sponge.uid)
	check(not g.combat_system().is_reacting(1) and g.find_unit(sponge.uid).damage == 2, "reagir: desafio sem risco de morte não pergunta")

	# the blow could kill the defender's unit: asked
	g = _reaction_game(["t_react_heal"], 5)
	hitter = _put(g, 0, "t_hitter")
	var glass := _put(g, 1, "t_glass")
	glass.exhausted = true
	_hit(g, hitter, glass.uid)
	check(g.combat_system().is_reacting(1) and g.find_unit(glass.uid) != null, "reagir: o golpe pode matar a unidade do defensor, então pergunta")

	# the counter-blow could kill the attacker: asked too
	g = _reaction_game(["t_react_heal"], 5)
	var fragile_attacker := _put(g, 0, "t_glass")
	var counter_hitter := _put(g, 1, "t_hitter")
	counter_hitter.exhausted = true
	_hit(g, fragile_attacker, counter_hitter.uid)
	check(g.combat_system().is_reacting(1), "reagir: o contragolpe pode matar o atacante, então pergunta")

	# the defender answers by killing the attacker: the attack fizzles and the Leader is untouched
	g = _reaction_game(["t_react_kill"], 5)
	hitter = _put(g, 0, "t_hitter")
	_put(g, 0, "t_sponge") # a second attacker, so combat goes on
	g.players[1]["leader_hp"] = 17
	_hit(g, hitter)
	var kill_uid: int = g.players[1]["hand"][0].uid
	g.play_card(1, kill_uid, hitter.uid)
	_pass_windows_until_attacks(g)
	check(g.find_unit(hitter.uid) == null and g.players[1]["leader_hp"] == 17, "reagir: a resposta mata o atacante e o ataque não acontece")
	check(g.stack.is_empty() and not g.combat_system().is_reacting(1) and g.combat_system().pending_attack.is_empty(), "reagir: nada fica pendente depois do ataque cancelado")

	# a cast that resolves without stopping the attack: the defender is asked again, and can still pass
	g = _reaction_game(["t_react_heal", "t_react_heal"], 4)
	hitter = _put(g, 0, "t_hitter")
	sponge = _put(g, 1, "t_sponge")
	g.players[1]["leader_hp"] = 17
	_hit(g, hitter)
	g.play_card(1, g.players[1]["hand"][0].uid, sponge.uid)
	_pass_windows_until_attacks(g)
	check(g.combat_system().is_reacting(1) and g.players[1]["leader_hp"] == 17, "reagir: resolvida a primeira resposta, o defensor é perguntado de novo")
	g.pass_priority(1)
	check(g.players[1]["leader_hp"] == 15 and not g.combat_system().is_reacting(1), "reagir: passando na segunda vez o ataque cai")

	# the switches: PASSAR TUDO lets it land; auto-pass off or on still asks (the defender has a real play)
	g = _reaction_game(["t_react_heal"], 5)
	g.players[1]["leader_hp"] = 17
	g.pass_rest_of_turn(1)
	_hit(g, _put(g, 0, "t_hitter"))
	check(not g.combat_system().is_reacting(1) and g.players[1]["leader_hp"] == 15, "reagir: passar tudo deixa o ataque cair sem perguntar")
	for auto in [true, false]:
		g = _reaction_game(["t_react_heal"], 5)
		g.players[1]["leader_hp"] = 17
		g.auto_pass[1] = auto
		_hit(g, _put(g, 0, "t_hitter"))
		check(g.combat_system().is_reacting(1), "reagir: com passe automático %s o defensor com jogada ainda é perguntado" % auto)

	# an AI defender never gets stuck: it either answers or passes, and the attack resolves
	g = _reaction_game(["t_react_heal"], 5)
	_put(g, 1, "t_sponge")
	_hit(g, _put(g, 0, "t_hitter"))
	for step in 6:
		if g.combat_system().is_reacting(1) or g.stack.size() > 0:
			SimpleAI.step(g, g.decider())
	check(not g.combat_system().is_reacting(1) and g.stack.is_empty(), "reagir: a IA defensora responde ou passa, sem travar")
	check(g.players[1]["leader_hp"] == leader_max - 2, "reagir: depois da IA decidir o ataque ao Líder acontece")

## Lets the pass/response priorities settle until the attacker declares again (or combat is over).
func _pass_windows_until_attacks(g: GameState) -> void:
	for i in 10:
		if g.phase != "combat" or g.combat_system().in_attacks_window(g.active) or g.combat_system().is_reacting(g.opponent(g.active)):
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
	check(g.attack_targets(attacker) == [other.uid, GameState.LEADER_UID[1]], "provocação pronta não obriga ninguém (a outra exaurida só é um alvo possível)")
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

	# an ordinary tapped unit doesn't guard the Leader: only a Provocação closes the face
	g = _new_game()
	_quiet(g)
	var guard := _put(g, 1, "t_other")
	var bruiser := _put(g, 0, "serpente_marinha")
	check(g.attack_targets(bruiser) == [GameState.LEADER_UID[1]], "sem exauridas: o Líder é o alvo")
	guard.exhausted = true
	check(g.attack_targets(bruiser) == [guard.uid, GameState.LEADER_UID[1]], "exaurida sem Provocação não fecha o Líder")
	var leader_hp_before: int = g.players[1]["leader_hp"]
	check(not _hit(g, bruiser).is_empty() and g.players[1]["leader_hp"] < leader_hp_before, "dá para ir no Líder mesmo com uma exaurida desafiável")
	# one it can't reach (Voo) doesn't close the face
	g = _new_game()
	_put(g, 1, "fenix_menor").exhausted = true
	check(g.attack_targets(_put(g, 0, "serpente_marinha")) == [GameState.LEADER_UID[1]], "exaurida inalcançável (Voo) não fecha o Líder")

	# Voo / Furtividade only limit who can CHALLENGE a unit; they no longer change whether the face is open
	_tcard("t_sneak", 1, 6, [])
	CardDB.data()["cards"]["t_sneak"]["keywords"] = ["furtividade"]
	var leader_uid: int = GameState.LEADER_UID[1]
	g = _new_game()
	var plain_guard := _put(g, 1, "t_other")
	plain_guard.exhausted = true
	var sneaker := _put(g, 0, "t_sneak")
	check(g.attack_targets(sneaker) == [plain_guard.uid, leader_uid], "Furtividade: desafia a exaurida comum ou vai no Líder")
	var sneaky_guard := _put(g, 1, "t_sneak")
	sneaky_guard.exhausted = true
	check(g.attack_targets(sneaker) == [plain_guard.uid, sneaky_guard.uid, leader_uid], "Furtividade: pode desafiar a exaurida com Furtividade e o Líder segue aberto")
	var flyer_vs_flyer := _put(g, 0, "fenix_menor")
	check(g.attack_targets(flyer_vs_flyer) == [plain_guard.uid, leader_uid], "Voo: desafia a exaurida comum ou vai no Líder")
	var flying_guard := _put(g, 1, "fenix_menor")
	flying_guard.exhausted = true
	check(g.attack_targets(flyer_vs_flyer) == [plain_guard.uid, flying_guard.uid, leader_uid], "Voo: pode desafiar a exaurida voadora e o Líder segue aberto")
	check(not g.attack_targets(sneaker).has(flying_guard.uid), "Furtividade sem Voo não alcança a exaurida voadora")
	# a Provocação still holds back any attacker that can challenge it
	g = _new_game()
	var tapped_taunt := _put(g, 1, "t_taunt")
	tapped_taunt.exhausted = true
	check(g.attack_targets(_put(g, 0, "t_sneak")) == [tapped_taunt.uid], "Furtividade: Provocação exaurida ainda obriga a desafiar")
	g = _new_game()
	var tapped_taunt_vs_flyer := _put(g, 1, "t_taunt")
	tapped_taunt_vs_flyer.exhausted = true
	check(g.attack_targets(_put(g, 0, "fenix_menor")) == [tapped_taunt_vs_flyer.uid], "Voo: Provocação exaurida ainda obriga a desafiar")

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

	# Regeneração: all damage healed at the start of every turn
	g = _new_game()
	_quiet(g)
	var coral := _put(g, 1, "sentinela_coral")
	check(g.has_kw(coral, "regeneracao"), "sentinela de coral tem regeneração")
	g._deal_damage(coral.uid, 2, null)
	check(coral.damage == 2, "regeneração não cura no meio do turno")
	g.end_turn(0)
	check(coral.damage == 0, "regeneração cura no início do próximo turno (até o do oponente)")

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
	# the reserve (2) is spent before the Momentum, whatever the spell costs now
	var momentum_left := 1 - maxi(0, CardDB.card("bola_de_fogo")["cost"] - GameState.RESERVE_CAP)
	check(g.players[p]["reserve"] == 0 and g.players[p]["momentum"] == momentum_left, "feitiço gasta a reserva primeiro")
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

	# "Passar tudo": the opponent has a usable Rápido, yet every window is passed until the turn ends
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 6
	g.players[1]["momentum"] = 3
	var fast_in_hand := _give(g, 1, "t_sw_fast")
	g.play_card(0, _give(g, 0, "t_sw"), 0)
	check(g.summon_window and g.priority == 1 and g.can_play(1, fast_in_hand), "com jogada válida a janela fica aberta")
	check(g.pass_rest_of_turn(0).is_empty(), "o jogador da vez não pode usar o passar tudo")
	g.pass_rest_of_turn(1)
	check(not g.summon_window and g.priority == 0 and g.skip_rest_of_turn[1], "passar tudo fecha a janela atual")
	g.play_card(0, _give(g, 0, "t_sw"), 0)
	check(not g.summon_window and g.priority == 0 and g.players[0]["board"].size() == 2, "passar tudo: a próxima janela é pulada mesmo com o Rápido na mão")
	g.end_turn(0)
	check(not g.skip_rest_of_turn[1] and not g.skip_rest_of_turn[0], "passar tudo vale só até o fim do turno")

	# the switch can be armed with no priority at all, and only affects windows opened afterwards
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 6
	g.players[1]["momentum"] = 3
	_give(g, 1, "t_sw_fast")
	check(g.priority == 0 and not g.pass_rest_of_turn(1).is_empty() and g.skip_rest_of_turn[1], "passar tudo pode ser armado sem prioridade")
	check(g.pass_rest_of_turn(1).is_empty(), "armar de novo não faz nada")
	g.play_card(0, _give(g, 0, "t_sw"), 0)
	check(not g.summon_window and g.priority == 0 and g.players[0]["board"].size() == 1, "armado antes: a jogada seguinte do oponente é passada")

	# turning it off only clears the flag: the next window is asked again
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 6
	g.players[1]["momentum"] = 3
	_give(g, 1, "t_sw_fast")
	check(g.cancel_pass_rest_of_turn(1).is_empty(), "desligar sem estar ligado não faz nada")
	g.pass_rest_of_turn(1)
	var off_events := g.cancel_pass_rest_of_turn(1)
	check(not g.skip_rest_of_turn[1] and off_events.any(func(e): return e["type"] == "pass_all_off"), "desligar limpa a flag")
	g.play_card(0, _give(g, 0, "t_sw"), 0)
	check(g.summon_window and g.priority == 1, "desligado: a janela volta a ser perguntada")

	# safety exception: a stack item that would kill the Leader is still asked, a harmless one is passed
	for lethal in [true, false]:
		g = _new_game()
		_quiet(g)
		_tspell("t_pa_finisher", "lento", [{"trigger": "on_play", "action": "damage", "target": "enemy_leader", "amount": 5}])
		_tspell("t_pa_answer", "instantaneo", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 1}])
		g.players[0]["momentum"] = 6
		g.players[1]["momentum"] = 3
		g.players[1]["leader_hp"] = 5 if lethal else 6
		_give(g, 1, "t_pa_answer") # only an Instantâneo can answer a spell on the stack
		_put(g, 0, "t_sw") # a target, so the answer is playable and the window would stay open
		g.pass_rest_of_turn(1)
		g.play_card(0, _give(g, 0, "t_pa_finisher"), 0)
		if lethal:
			check(g.priority == 1 and not g.stack.is_empty() and g.players[1]["leader_hp"] == 5, "passar tudo: jogada letal ainda pergunta ao dono do Líder")
			g.pass_priority(1)
			check(g.players[1]["leader_hp"] <= 0, "passar manualmente deixa a jogada letal resolver")
		else:
			check(g.stack.is_empty() and g.players[1]["leader_hp"] == 1, "passar tudo: jogada não letal é passada sozinha")

	# the flag travels in the snapshot and RemoteState mirrors it
	g = _new_game()
	_quiet(g)
	g.pass_rest_of_turn(1)
	var mirror := RemoteState.new()
	mirror.apply_snapshot(StateView.snapshot(g, 1))
	check(mirror.skip_rest_of_turn == [false, true], "RemoteState espelha o passar tudo do servidor")

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
	check(g.stack.is_empty(), "search: the Ao Entrar already resolved (nobody could answer a Rápido)")
	g.choose_search(0, int(g.pending_search["cards"][0]["uid"]))
	check(g.phase == "main" and not g.summon_window and g.priority == 0 and g.stack.is_empty(), "search done: the response moment already happened, the turn goes on")
	check(not g.can_play(1, fast3), "a Rápido cannot answer an Ao Entrar (only Instantâneo)")

	_test_enter_response()

## A unit's Ao Entrar waits on the stack as its own item: the opponent may answer with an Instantâneo first.
func _test_enter_response() -> void:
	_tcard("t_sw_enter", 1, 1, [{"trigger": "on_enter", "action": "damage", "target": "enemy_leader", "amount": 3}])
	_tspell("t_sw_inst_kill", "instantaneo", [{"trigger": "on_play", "action": "damage", "target": "any_unit", "amount": 9}])
	_tspell("t_sw_inst_buff", "instantaneo", [{"trigger": "on_play", "action": "buff", "target": "ally_unit", "hp": 2}])
	_tspell("t_sw_counter", "instantaneo", [{"trigger": "on_play", "action": "counter", "target": "enemy_stack"}])

	# the Ao Entrar sits on the stack, the opponent has priority, nothing happened yet
	var g := _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 3
	g.players[1]["momentum"] = 3
	g.set_auto_pass(0, false)
	g.set_auto_pass(1, false) # otherwise the stack resolves as soon as someone has nothing left to answer with
	var inst_kill := _give(g, 1, "t_sw_inst_kill")
	var enter_unit_id := _give(g, 0, "t_sw_enter")
	var foe_hp: int = g.players[1]["leader_hp"]
	g.play_card(0, enter_unit_id, 0)
	check(g.find_unit(enter_unit_id) != null and g.stack.size() == 1 and g.stack[0]["kind"] == "enter_trigger", "Ao Entrar goes on the stack as its own item")
	check(g.players[1]["leader_hp"] == foe_hp and g.priority == 1, "the Ao Entrar has not resolved: the opponent has priority")
	check(g.can_play(1, inst_kill), "opponent can answer with an Instantâneo")
	check(g.valid_targets(1, "enemy_stack").is_empty(), "the Ao Entrar cannot be countered")

	# the opponent kills the entering unit in response; the owner answers the answer; the Ao Entrar still resolves
	g.players[0]["momentum"] = 3
	var inst_buff := _give(g, 0, "t_sw_inst_buff")
	g.play_card(1, inst_kill, enter_unit_id)
	check(g.stack.size() == 2 and g.priority == 0, "the response stacks on top and the owner gets priority")
	check(g.can_play(0, inst_buff), "the owner can answer the answer")
	g.play_card(0, inst_buff, enter_unit_id)
	check(g.stack.size() == 3 and g.priority == 1, "the owner's answer stacks as a third item")
	_resolve_stack(g)
	check(g.stack.is_empty() and g.phase == "main" and g.priority == 0, "the whole stack resolved")
	check(g.find_unit(enter_unit_id) == null, "newest-first: the buff came first, the 9 damage still killed it")
	check(g.players[1]["leader_hp"] == foe_hp - 3, "the Ao Entrar resolved even though its unit died in response")

	# no Instantâneo in the opponent's hand: no window, the Ao Entrar resolves at once
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 3
	foe_hp = g.players[1]["leader_hp"]
	g.play_card(0, _give(g, 0, "t_sw_enter"), 0)
	check(g.stack.is_empty() and g.players[1]["leader_hp"] == foe_hp - 3 and g.priority == 0, "no Instantâneo to answer with: the Ao Entrar resolves at once")

	# a unit with no Ao Entrar keeps the old summon window
	_tcard("t_sw_plain", 1, 1, [])
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 3
	g.set_auto_pass(1, false)
	g.play_card(0, _give(g, 0, "t_sw_plain"), 0)
	check(g.summon_window and g.stack.is_empty(), "a unit without Ao Entrar still opens the summon window")

	# an Instantâneo response only helps if auto-pass is off: manual pass resolves the Ao Entrar
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 3
	g.set_auto_pass(1, false)
	foe_hp = g.players[1]["leader_hp"]
	g.play_card(0, _give(g, 0, "t_sw_enter"), 0)
	check(g.stack.size() == 1 and g.priority == 1, "auto-pass off: the window stays open for the opponent")
	g.pass_priority(1)
	_resolve_stack(g)
	check(g.stack.is_empty() and g.players[1]["leader_hp"] == foe_hp - 3, "opponent passes: the Ao Entrar resolves")

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
	check(not g.can_play(1, _give(g, 1, "bola_de_fogo")), "lento cannot respond")
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
	check(not g.can_play(0, _give(g, 0, "bola_de_fogo")), "sem lento fora da fase principal")

	# Janela A: between two attacks the attacker may cast an Instantânea (never a Rápido), the defender answers it
	g = _new_game()
	g.players[0]["momentum"] = 5
	g.players[1]["momentum"] = 5
	var first_attacker := _put(g, 0, "t_wall2")
	var second_attacker := _put(g, 0, "t_wall2")
	var defender_wall := _put(g, 1, "t_wall")
	var window_instant := _give(g, 0, "t_inst_hp")
	var window_fast := _give(g, 0, "t_fast")
	var window_slow := _give(g, 0, "bola_de_fogo")
	var defender_instant := _give(g, 1, "t_inst_hp")
	_open_attacks(g)
	check(g.window == "attacks" and g.priority == 0, "janela A: ataques, o dono do turno tem a prioridade")
	check(g.can_play(0, window_instant), "janela A: entre ataques o dono do turno joga Instantânea")
	check(not g.can_play(0, window_fast) and not g.can_play(0, window_slow), "janela A: entre ataques nem Rápido nem Lento")
	check(not g.can_play(1, defender_instant), "janela A: o defensor não começa nada, só responde")
	# the defender's hand is set aside for this first attack: holding an Instantâneo would make the game ask them to react (Janela B)
	var defender_hand: Array = g.players[1]["hand"]
	g.players[1]["hand"] = []
	g.players[1]["ability_used"] = true # the Leader's ability is a play too, and would be offered the same way
	g.attack_unit(0, first_attacker.uid, GameState.LEADER_UID[1])
	g.players[1]["hand"] = defender_hand
	check(g.combat_system().in_attacks_window(0), "janela A: depois de um ataque a janela continua aberta")
	g.play_card(0, window_instant, first_attacker.uid)
	check(g.stack.size() == 1 and g.priority == 1, "janela A: a Instantânea vai para a pilha e o defensor recebe a prioridade")
	check(not g.combat_system().in_attacks_window(0) and not g.combat_system().in_attacks_window(1), "janela A: com a pilha cheia ninguém declara ataque")
	check(g.can_play(1, defender_instant), "janela A: o defensor responde com Instantânea")
	g.play_card(1, defender_instant, defender_wall.uid)
	check(g.stack.size() == 2 and g.priority == 0, "janela A: a resposta empilha e a prioridade volta ao dono do turno")
	g.pass_priority(0)
	g.pass_priority(1)
	check(g.stack.is_empty(), "janela A: os dois passaram, a pilha resolve")
	check(g.find_unit(first_attacker.uid).hp == 5 and g.find_unit(defender_wall.uid) != null, "janela A: as duas Instantâneas resolveram")
	check(g.window == "attacks" and g.combat_system().in_attacks_window(0), "janela A: resolvida a pilha, o dono do turno volta a atacar")
	var second_events := g.attack_unit(0, second_attacker.uid, GameState.LEADER_UID[1])
	check(not second_events.is_empty(), "janela A: o segundo ataque acontece normalmente")
	g.pass_priority(0)
	check(g.phase != "combat" or g.window != "attacks", "janela A: passar com a pilha vazia ainda encerra o combate")

	# Escudo de Feitiço (Neraqa only shields another ally; she is Inalcançável herself)
	g = _new_game()
	g.players[0]["momentum"] = 5
	var ner := _put(g, 1, "neraqa")
	check(not g.has_kw(ner, "escudo_feitico"), "neraqa never shields herself")
	check(not g.card_targets(0, CardDB.card("labareda")).has(ner.uid), "neraqa is Inalcançável: enemy spells can't target her")
	# the screen keeps the spell enabled (to explain the refusal) but the auto-pass still sees no play
	g.players[0]["hand"] = []
	var blocked_spell := _give(g, 0, "labareda")
	check(not g.can_play(0, blocked_spell) and g.can_play(0, blocked_spell, true), "inalcançável: feitiço só habilitado para a tela")
	check(g.stack_system().has_play(0) == g.can_use_ability(0), "inalcançável: o auto-passe não conta o feitiço bloqueado como jogada")
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

## Registers a unit fixture with Crítico already parsed (level) and optional extra card fields.
func _tcrit(id: String, atk: int, hp: int, level: int, extra := {}) -> void:
	_tcard(id, atk, hp, [])
	CardDB.data()["cards"][id]["critico"] = level
	CardDB.data()["cards"][id].merge(extra, true)

## Crítico: chance per level, +2 flat damage, Desdém (imune_critico), Vael's growth and +4 at level 4.
func _test_critico() -> void:
	# level 4 always crits: +2 damage on the Leader hit, no RNG involved
	_tcrit("t_crit4", 3, 5, 4)
	var g := _new_game()
	_quiet(g)
	var striker := _put(g, 0, "t_crit4")
	var leader_before: int = g.players[1]["leader_hp"]
	var events := _hit(g, striker)
	check(_has_event(events, "crit"), "crítico 4: o golpe sempre é crítico")
	check(g.players[1]["leader_hp"] == leader_before - 5, "crítico: +2 de dano no Líder (3 + 2)")

	# a unit with no Crítico never crits
	_tcard("t_nocrit", 3, 5, [])
	var g_plain := _new_game()
	_quiet(g_plain)
	var plain := _put(g_plain, 0, "t_nocrit")
	check(not _has_event(_hit(g_plain, plain), "crit"), "sem Crítico não há crítico")

	# Desdém: the crit is negated and no bonus is added; the retaliation of a Crítico unit is also rolled
	_tcrit("t_desdem", 1, 9, 0, {"imune_critico": true})
	var g_immune := _new_game()
	_quiet(g_immune)
	var immune := _put(g_immune, 1, "t_desdem")
	immune.exhausted = true
	var crit_attacker := _put(g_immune, 0, "t_crit4")
	var immune_events := _hit(g_immune, crit_attacker, immune.uid)
	check(_has_event(immune_events, "crit_negated") and not _has_event(immune_events, "crit"), "Desdém anula o crítico")
	check(immune.damage == 3, "Desdém: dano normal, sem o +2 (%d)" % immune.damage)

	# Crítico also rolls on the retaliation
	_tcard("t_sturdy", 1, 9, [])
	var g_retal := _new_game()
	_quiet(g_retal)
	var retal_attacker := _put(g_retal, 0, "t_sturdy")
	var retal_defender := _put(g_retal, 1, "t_crit4")
	retal_defender.exhausted = true
	var retal_events := _hit(g_retal, retal_attacker, retal_defender.uid)
	check(_has_event(retal_events, "crit") and retal_attacker.damage == 5, "Crítico também vale no revide (3 + 2 = 5, foi %d)" % retal_attacker.damage)

	# Vael: +1 permanent level per crit, up to 4; at level 4 the bonus is +3 and he attacks twice
	_tcrit("t_vael", 3, 9, 1, {"critico_growth": true, "critico_maximo": {"bonus": 3, "ataque_duplo": true}})
	# a level-1 Vael crits 25% of the time: try seeds until one lands (each attack ends the combat, so a fresh game per try)
	var grew := false
	var vael: Card = null
	var g_vael: GameState = null
	for seed_value in 80:
		g_vael = _new_game(seed_value)
		_quiet(g_vael)
		g_vael.players[1]["leader_hp"] = 999
		vael = _put(g_vael, 0, "t_vael")
		var vael_events := _hit(g_vael, vael)
		if _has_event(vael_events, "crit"):
			check(vael.critico == 2 and _has_event(vael_events, "critico_up"), "Vael sobe 1 nível de Crítico a cada crítico")
			grew = true
			break
		check(vael.critico == 1, "sem crítico o nível do Vael não muda")
	check(grew, "Vael acabou acertando um crítico em 80 sementes de 25%")
	check(g_vael.attacks_allowed(vael) == 1, "Vael abaixo do nível 4 ataca uma vez")
	# the level is shared by every copy of Vael of that player: hand, deck, field and copies that show up later
	var g_shared := _new_game()
	_quiet(g_shared)
	var vael_on_field := _put(g_shared, 0, "t_vael")
	var vael_in_hand := Card.new(g_shared._uid(), "t_vael", 0, "hand")
	g_shared.players[0]["hand"].append(vael_in_hand)
	var vael_in_deck := Card.new(g_shared._uid(), "t_vael", 0, "deck")
	g_shared.players[0]["deck"].append(vael_in_deck)
	var vael_of_opponent := _put(g_shared, 1, "t_vael")
	g_shared.grow_critico(vael_on_field)
	check(vael_on_field.critico == 2 and vael_in_hand.critico == 2 and vael_in_deck.critico == 2, "o Crítico do Vael sobe em todas as cópias (campo, mão e deck)")
	check(vael_of_opponent.critico == 1, "o Crítico do Vael do oponente não muda")
	var vael_later := Card.new(g_shared._uid(), "t_vael", 0, "deck")
	g_shared._move(vael_later, "hand")
	check(vael_later.critico == 2, "cópia que aparece depois já vem com o Crítico alcançado")
	var vael_summoned := Card.new(g_shared._uid(), "t_vael", 0, "hand")
	g_shared._summon(0, vael_summoned, false, 0)
	check(vael_summoned.critico == 2, "cópia que entra em campo depois começa no Crítico alcançado")
	for step in 5:
		g_shared.grow_critico(vael_on_field)
	check(vael_in_hand.critico == 4 and vael_summoned.critico == 4, "o Crítico compartilhado para no nível 4")
	# at level 4: +3 damage, and two attacks per turn
	var g_max := _new_game()
	_quiet(g_max)
	g_max.players[1]["leader_hp"] = 999
	var vael_max := _put(g_max, 0, "t_vael")
	vael_max.critico = 4
	check(g_max.attacks_allowed(vael_max) == 2, "Vael no Crítico 4 ganha Ataque Duplo")
	_hit(g_max, vael_max)
	check(g_max.players[1]["leader_hp"] == 999 - 6, "Vael no Crítico 4: +3 de dano (3 + 3)")
	check(g_max.can_attack(vael_max), "Vael no Crítico 4 ainda pode atacar a segunda vez")
	# what the client shows: the live level (temporary included) and the Ataque Duplo state
	var vael_card := CardDB.card("t_vael")
	check(CardView.critico_of_view(vael_card, {"critico": 3, "temp_critico": 2}) == 4, "a tela soma o Crítico temporário e trava em 4")
	check(CardView.critico_of_view({}, {"temp_critico": 2}) == 2, "uma unidade sem Crítico impresso mostra o temporário")
	check(CardView.critico_of_view(vael_card, {}) == int(vael_card.get("critico", 0)), "fora do campo a tela mostra o Crítico impresso")
	check(CardView.attacks_allowed_of_view(vael_card, vael_max.to_dict()) == 2, "a tela mostra o Ataque Duplo do Vael no Crítico 4")
	check(CardView.attacks_allowed_of_view(vael_card, {"critico": 3}) == 1, "a tela não mostra o Ataque Duplo abaixo do Crítico 4")
	check(CardView.attacks_allowed_of_view(vael_card, {"critico": 3, "temp_critico": 1}) == 2, "o Crítico temporário até 4 também liga o Ataque Duplo (como no motor)")

## "critico_temp" (Afiar a Lâmina) lasts until the end of the turn and never goes past level 4.
func _test_critico_temp() -> void:
	_tcrit("t_edge", 2, 5, 0)
	var g := _new_game()
	_quiet(g)
	var unit := _put(g, 0, "t_edge")
	var sharpen: Effect = EffectRegistry.parse_list([{"trigger": "on_play", "action": "buff", "target": "ally_unit", "critico_temp": 3}])[0]
	sharpen.apply(EffectContext.new(g, 0, ""), unit.uid)
	check(unit.critico_total() == 3, "critico_temp soma níveis (%d)" % unit.critico_total())
	sharpen.apply(EffectContext.new(g, 0, ""), unit.uid)
	check(unit.critico_total() == 4, "critico_temp nunca passa do nível 4 (%d)" % unit.critico_total())
	g.end_turn(0)
	check(unit.temp_critico == 0 and unit.critico_total() == 0, "o Crítico temporário some no fim do turno")

## Ataque Duplo: the unit stays tapped between the two attacks and is spent after the second.
func _test_double_attack() -> void:
	_tcard("t_double", 2, 5, [])
	CardDB.data()["cards"]["t_double"]["keywords"] = ["ataque_duplo"]
	var g := _new_game()
	_quiet(g)
	g.players[1]["leader_hp"] = 999
	var unit := _put(g, 0, "t_double")
	check(g.can_attack(unit), "Ataque Duplo: pronta para o primeiro ataque")
	_hit(g, unit)
	check(unit.exhausted and g.can_attack(unit), "Ataque Duplo: fica virada mas ainda pode atacar a segunda vez")
	var second := _hit(g, unit)
	check(not second.is_empty() and g.players[1]["leader_hp"] == 999 - 4, "Ataque Duplo: o segundo ataque acerta o Líder")
	check(not g.can_attack(unit), "Ataque Duplo: esgotada depois do segundo ataque")
	g.end_turn(0)
	check(unit.attacks_made == 0 or g.active == 1, "contador de ataques zera no início do turno do dono")

	# a normal unit is spent after one attack
	_tcard("t_single", 2, 5, [])
	var g_single := _new_game()
	_quiet(g_single)
	var single := _put(g_single, 0, "t_single")
	_hit(g_single, single)
	check(not g_single.can_attack(single), "sem Ataque Duplo, um ataque esgota a unidade")

## Luto: an Aliado Morre effect with "dying_card" only hears that one card dying.
func _test_dying_card_filter() -> void:
	_tcrit("t_mourner", 2, 9, 0)
	CardDB.data()["cards"]["t_mourner"]["effects"] = [{"trigger": "on_ally_death", "dying_card": "t_beloved",
		"action": "buff", "target": "self", "atk": 2, "temp": true, "critico_temp": 4}]
	_tcard("t_beloved", 1, 1, [])
	_tcard("t_stranger", 1, 1, [])
	var g := _new_game()
	_quiet(g)
	var mourner := _put(g, 0, "t_mourner")
	var stranger := _put(g, 0, "t_stranger")
	_kill(g, stranger)
	check(mourner.temp_atk == 0 and mourner.temp_critico == 0, "Luto: outra aliada morrendo não dispara")
	var beloved := _put(g, 0, "t_beloved")
	_kill(g, beloved)
	check(mourner.temp_atk == 2 and mourner.temp_critico == 4, "Luto: a amada morrendo dá +2 ATK e Crítico 4 no turno (atk %d, crit %d)" % [mourner.temp_atk, mourner.temp_critico])

## The new Crítico fields survive the network mirror, and "critico:N" is parsed from keywords.
func _test_critico_data() -> void:
	_tcard("t_mirror", 2, 2, [])
	var g := _new_game()
	var unit := _put(g, 0, "t_mirror")
	unit.critico = 2
	unit.temp_critico = 1
	unit.attacks_made = 1
	var copy := Card.from_dict(unit.to_dict(), "board", 0)
	check(copy.critico == 2 and copy.temp_critico == 1 and copy.attacks_made == 1 and copy.critico_total() == 3, "Crítico e ataques sobrevivem ao to_dict/from_dict")
	var parsed := CardDB.card_for("t_mirror", {})
	check(not parsed.has("critico"), "carta sem Crítico não tem o campo")

func _test_strike_order() -> void:
	check(_strike_result(0, 0) == "--", "rapidez igual: os dois morrem")
	check(_strike_result(1, 0) == "A-", "atacante mais rápido mata antes")
	check(_strike_result(0, 1) == "-B", "desafiado mais rápido mata antes")
	check(_strike_result(3, 2) == "A-", "Rapidez 3 bate antes da 2")
	check(_strike_result(2, 2) == "--", "Rapidez 2 contra 2: simultâneo")
	check(_strike_result(0, 3, true) == "--", "congelada: sem Rapidez (suprimida), bate junto com um atacante sem Rapidez")
	check(_strike_result(1, 3, true) == "A-", "congelada: com a Rapidez suprimida, o atacante com Rapidez bate primeiro")

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

	# A Plant entering supplies the event source itself, and the custom temporary Vida lasts
	# until that unit's controller starts their next turn.
	_tcard("t_growth", 1, 3, [{"listen": "unit_entered", "scope": "ally", "zones": ["board"],
		"when": {"plant": true}, "action": "buff", "target": "event_source", "hp_temp_until_next_turn": 1}])
	g = _new_game()
	_put(g, 0, "t_growth")
	var entering_plant := _put(g, 0, "mudinha_do_dossel")
	var entering_human := _put(g, 0, "guardia_dos_ninhos")
	g._check_state()
	check(entering_plant.temp_hp_until_next_turn == 1,
		"listen unit_entered: Planta recebe Vida temporária até o próximo turno")
	check(entering_human.temp_hp_until_next_turn == 0, "listen unit_entered: não dispara para unidade que não é Planta")

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
	check(g.find_unit(foe.uid).damage == 3 and int(g.find_unit(foe.uid).dot_markers.get("queimadura", 0)) == 1 and g.find_unit(foe2.uid) == null, "dlorafya: enemies take 3 e recebem Queimadura")
	check(g.find_unit(d.uid).damage == 1, "dlorafya: self takes 1")

	g = _new_game()
	var sal := _put(g, 0, "salamandra")
	hp = g.players[1]["leader_hp"]
	_hit(g, sal)
	check(g.players[1]["leader_hp"] == hp - 3, "salamandra Ao Atacar (1 + 2 hit)")

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
	check(f.atk == 2 and f.hp == 2, "fenix is 2/2")
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
	check(DeckDB.validate_cards(leader, base).is_empty(), "fogo: legal")
	# three more champions go over the Campeões + Lendárias cap (the deck has 18 of 20)
	base["kael_drath_vulcano"] = 3
	base["salamandra"] = 2
	check(not DeckDB.validate_cards(leader, base).filter(func(e): return "Campeões + Lendárias" in e).is_empty(), "21 campeões é ilegal")
	# legendary default is 2 copies
	_tcard("t_lenda", 1, 1, [])
	CardDB.card("t_lenda")["rarity"] = "legendary"
	var lenda_deck: Dictionary = {"t_lenda": 3}
	check(not DeckDB.validate_cards(leader, lenda_deck).filter(func(e): return "mais de 2 cópias" in e).is_empty(), "lendária: 3 cópias é ilegal")
	lenda_deck["t_lenda"] = 2
	check(DeckDB.validate_cards(leader, lenda_deck).filter(func(e): return "t_lenda" in e).is_empty(), "lendária: 2 cópias é legal")

func _test_vegetal() -> void:
	var g := GameState.new("vegetal", "fogo", 4242)
	g.mulligan(0, [])
	g.mulligan(1, [])
	_quiet(g)
	# Thalvaressa: on her owner's turn, each of the first 2 tokens gives +1 Vida to ANOTHER random plant
	# (never the token that just entered, never a non-plant)
	var human_ally := _put(g, 0, "guardia_dos_ninhos") # put first: her own Ao Entrar would buff a plant already on the board
	var plant_ally := _put(g, 0, "semente_teimosa")
	var plant_base_hp: int = int(CardDB.card("semente_teimosa")["hp"])
	var human_base_hp: int = int(CardDB.card("guardia_dos_ninhos")["hp"])
	var first_token := _put(g, 0, "mudinha_do_dossel")
	g._check_state()
	check(first_token.hp == 1 and first_token.atk == 0, "Thalvaressa: a ficha invocada não recebe o próprio Crescimento do Dossel")
	check(plant_ally.hp == plant_base_hp + 1 and plant_ally.atk == int(CardDB.card("semente_teimosa")["atk"]), "Thalvaressa: a outra planta aliada ganha só +1 de Vida")
	check(human_ally.hp == human_base_hp, "Thalvaressa: aliado que não é planta não recebe o buff")
	var second_token := _put(g, 0, "mudinha_do_dossel")
	g._check_state()
	var tokens_hp_gained: int = (first_token.hp - 1) + (second_token.hp - 1)
	check((plant_ally.hp - plant_base_hp) + tokens_hp_gained == 2, "Thalvaressa: o segundo trigger do turno também dispara")
	var third_token := _put(g, 0, "mudinha_do_dossel")
	g._check_state()
	var all_hp_gained: int = (plant_ally.hp - plant_base_hp) + (first_token.hp - 1) + (second_token.hp - 1) + (third_token.hp - 1)
	check(all_hp_gained == 2, "Thalvaressa: o terceiro trigger do turno não dispara (máximo 2)")
	# on the opponent's turn the passive stays silent
	g.active = 1
	g._start_turn(1, false)
	var hp_before_enemy_turn: int = all_hp_gained
	var token_on_enemy_turn := _put(g, 0, "mudinha_do_dossel")
	g._check_state()
	var hp_after_enemy_turn: int = (plant_ally.hp - plant_base_hp) + (first_token.hp - 1) + (second_token.hp - 1) + (third_token.hp - 1) + (token_on_enemy_turn.hp - 1)
	check(hp_after_enemy_turn == hp_before_enemy_turn, "Thalvaressa: fora do turno do dono o passivo não dispara")
	# Cultivador da Clareira: the +1/+1 goes to ANOTHER unit that was already there (not himself, not the token he summons).
	# Fresh game so the board from the Thalvaressa checks above does not get in the way.
	var garden := _new_game()
	var lone_gardener := _put(garden, 0, "cultivador_da_clareira")
	check(lone_gardener.atk == 2 and lone_gardener.hp == 3, "Cultivador: sozinho, ele não buffa a si mesmo")
	var gardener_ally := _put(garden, 0, "guardia_dos_ninhos")
	var stats_before_second: int = 0
	for unit: Card in garden.players[0]["board"]:
		stats_before_second += unit.atk + unit.hp + unit.temp_atk + unit.temp_hp
	var second_gardener := _put(garden, 0, "cultivador_da_clareira")
	check(second_gardener.atk == 2 and second_gardener.hp == 3, "Cultivador: não buffa a si mesmo com aliados em campo")
	var stats_after_second: int = 0
	for unit: Card in garden.players[0]["board"]:
		stats_after_second += unit.atk + unit.hp + unit.temp_atk + unit.temp_hp # the buff is temporary now, so it lives in temp_atk/temp_hp
	# second Cultivador (2/3) + exactly one temporary +2/+1 on a unit already in play
	check(stats_after_second - stats_before_second == (2 + 3) + 3, "Cultivador: o buff temporário +2/+1 caiu numa unidade que já estava em campo")
	check(gardener_ally.hp >= 5, "Cultivador: Guardiã continua intacta ou buffada, nunca reduzida")
	# Thalvaressa with nobody to buff (only a non-plant and the token itself): the passive stays silent and keeps its uses
	var quiet_garden := GameState.new("vegetal", "fogo", 4243)
	quiet_garden.mulligan(0, [])
	quiet_garden.mulligan(1, [])
	_quiet(quiet_garden)
	_put(quiet_garden, 0, "guardia_dos_ninhos")
	_put(quiet_garden, 0, "mudinha_do_dossel")
	quiet_garden._check_state()
	check(int(quiet_garden.players[0].get("passive_uses", 0)) == 0 and not quiet_garden.players[0]["passive_used"], "Thalvaressa: sem alvo válido o passivo não é anunciado nem gasta um uso")
	_put(quiet_garden, 0, "semente_teimosa")
	_put(quiet_garden, 0, "mudinha_do_dossel")
	quiet_garden._check_state()
	check(int(quiet_garden.players[0].get("passive_uses", 0)) == 1, "Thalvaressa: com uma planta aliada em campo o passivo volta a disparar")
	# Flor Voraz uses two independent 1-damage rolls that include the Leader in their pool.
	var spread := EffectRegistry.parse({"action": "damage", "target": "random_enemy_spread", "hits": 2, "amount": 1})
	var spread_picks: Array = spread.target.resolve(EffectContext.new(g, 0, ""), spread)
	check(spread_picks.size() == 2, "Flor Voraz: produz dois sorteios de dano")
	var only_face := spread_picks.all(func(uid: int) -> bool: return uid == GameState.LEADER_UID[1])
	check(only_face, "Flor Voraz: sem unidades inimigas, os dois sorteios atingem o Líder")
	var flower := _put(g, 0, "flor_voraz")
	var hp_before: int = int(g.players[1]["leader_hp"])
	g._fire(flower, "on_turn_end")
	g._check_state()
	check(int(g.players[1]["leader_hp"]) == hp_before - 1, "Flor Voraz: com 0 de Ataque causa um golpe")
	flower.atk = 1
	g._fire(flower, "on_turn_end")
	g._check_state()
	check(int(g.players[1]["leader_hp"]) == hp_before - 3, "Flor Voraz: com 1 de Ataque causa dois golpes")
	flower.atk = 3
	g._fire(flower, "on_turn_end")
	g._check_state()
	check(int(g.players[1]["leader_hp"]) == hp_before - 7, "Flor Voraz: com 3 de Ataque causa quatro golpes")

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
	# A listener is presented as a Condicional on the physical card, so its full-screen rules text
	# must carry the same explicit label for CardView.colorize_rules to render it in orange and bold.
	for card_id in CardDB.data()["cards"]:
		if String(card_id).begins_with("t_"):
			continue # synthetic fixtures use intentionally terse text
		var cd: Dictionary = CardDB.card(card_id)
		if cd.get("effects", []).any(func(e: Dictionary): return e.has("listen")):
			var listener_text := String(cd.get("text", ""))
			check(listener_text.contains("Condicional:") or listener_text.contains("Condicional ("), "%s: listener precisa escrever 'Condicional:' (ou 'Condicional (limite):') no texto" % card_id)

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
	check(g.cost_of(a, vx) == 14 and g.cost_of(a, fg) == 14, "eletrica: custos base 14 e 14")
	# only what leaks past the Reserva (2) at the start of the owner's next turn counts
	g.players[a]["momentum"] = 3
	g.players[a]["reserve"] = 1
	g.end_turn(a)
	g.players[o]["momentum"] = 0
	g.end_turn(o)
	check(g.players[a]["saved_momentum"] == 2 and g.players[a]["idle_turns"] == 1, "eletrica: conta só o que vazou da Reserva (1+3-2)")
	check(g.players[o]["saved_momentum"] == 0 and g.players[o]["idle_turns"] == 0, "eletrica: o que cabe na Reserva não conta")
	check(g.cost_of(a, vx) == 12 and g.cost_of(a, fg) == 11, "eletrica: custo cai com o que vazou")
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
	check(g.cost_of(a, gg) == 9 and int(gg["atk"]) == 8 and int(gg["hp"]) == 7, "gigante: 8/7 custando 9")
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
	var l: Dictionary = g.players[a]["incarnation"]
	l["casts"] = 1
	g.players[a]["saved_momentum"] = 0
	check(g.incarnation_cost(a) == 15, "voltexz: sem redução, 2a conjuração custa 15")
	g.players[a]["saved_momentum"] = 8
	check(g.incarnation_cost(a) == 7, "voltexz: custo atual 6 + taxa 1 = 7")
	l["in_zone"] = false
	g._incarnation_leaves(a)
	check(l["in_zone"] and not l.get("retired", false), "voltexz: volta ao Santuário com custo atual 7")
	g.players[a]["saved_momentum"] = 4
	l["in_zone"] = false
	g._incarnation_leaves(a)
	check(l.get("retired", false), "voltexz: custo atual 10 + taxa 1 = 11 (Momentum vazado 4) aposenta")
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
	check(atk_ok(g, ally, 3 + 5, 5 + 5) and ally.rapidez_total() == 1, "voltexz: aliados +5/+5 e Rapidez 1")
	check(g.atk_of(vs) == 8 and vs.rapidez_total() == 3, "voltexz: não bufa a si própria (ATK base 8, Rapidez 3 nativa)")
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
	# Jack: +1 attack per Momentum left at end of turn
	g = _eletrica_game()
	a = g.active
	o = g.opponent(a)
	var jk := _put(g, a, "jack")
	g.end_turn(a)
	check(g.atk_of(jk) == 3, "jack: sem Momentum sobrando não cresce")
	g.end_turn(o)
	g.players[a]["momentum"] = 2
	g.end_turn(a)
	check(g.atk_of(jk) == 5, "jack: Momentum sobrando dá +1 de Ataque por ponto")
	# Layla: +1 attack per damage taken, up to +3
	# Layla: +1 attack per damage taken, no cap
	var ly := _put(g, g.active, "layla")
	for i in 5:
		g._deal_damage(ly.uid, 1, null)
		g._check_state()
		ly.damage = 0
	check(g.atk_of(ly) == 9, "layla: +1 por dano, sem limite (%d)" % g.atk_of(ly))
	_tcard("t_layla_wall", 0, 20, []) # survives the fight, so the damage can be read
	# Layla: Ao Atacar, 1 de dano à unidade atacada (2 se Atordoada), e nada se o ataque for no Líder
	g = _new_game()
	_quiet(g)
	var layla_attacker := _put(g, g.active, "layla")
	var healthy_victim := _put(g, g.opponent(g.active), "t_layla_wall")
	healthy_victim.exhausted = true # only a tapped unit can be challenged
	_hit(g, layla_attacker, healthy_victim.uid)
	var combat_damage := layla_attacker.atk_total() # the challenge itself also hurts the victim
	check(healthy_victim.damage == combat_damage + 1, "layla: Ao Atacar causa 1 de dano à unidade atacada (%d)" % healthy_victim.damage)
	g = _new_game()
	_quiet(g)
	layla_attacker = _put(g, g.active, "layla")
	var stunned_victim := _put(g, g.opponent(g.active), "t_layla_wall")
	g._apply_effect(g.active, {"action": "stun", "target": "enemy_unit"}, stunned_victim.uid)
	_hit(g, layla_attacker, stunned_victim.uid)
	check(stunned_victim.damage == layla_attacker.atk_total() + 2, "layla: Ao Atacar causa 2 de dano a uma unidade Atordoada (%d)" % stunned_victim.damage)
	g = _new_game()
	_quiet(g)
	layla_attacker = _put(g, g.active, "layla")
	var leader_hp_before: int = g.players[g.opponent(g.active)]["leader_hp"]
	_hit(g, layla_attacker)
	check(g.players[g.opponent(g.active)]["leader_hp"] == leader_hp_before - layla_attacker.atk_total(), "layla: Ao Atacar não causa dano extra quando o alvo é o Líder")
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
	var strong := _put(g, a, "voltexz") # Rapidez 3, same as Thorwells
	g._deal_damage(th.uid, 1, strong)
	check(th.damage == 3, "esquiva: Rapidez igual ou maior não é evitada")
	g.turn += 1
	g._deal_damage(th.uid, 1, weak)
	check(th.damage == 3, "esquiva: de novo no turno seguinte")
	g._combat_damage = false
	g.turn += 1
	g._deal_damage(th.uid, 1, weak)
	check(th.damage == 4, "esquiva: dano fora de combate não é evitado")
	# Esquiva with an override: Espírito Carregado dodges anything with Rapidez 0 (no Rapidez)
	var sp := _put(g, o, "espirito_carregado")
	var slow := _put(g, a, "jack")
	var fast := _put(g, a, "layla") # Rapidez 1
	g.turn += 1
	g._combat_damage = true
	g._deal_damage(sp.uid, 1, fast)
	check(sp.damage == 1, "esquiva (override): Rapidez 1 acerta")
	g._deal_damage(sp.uid, 1, slow)
	check(sp.damage == 1, "esquiva (override): sem Rapidez é evitada, mesmo com ATK maior")
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
	# nothing to refund (first turn, or leaked 0/1): the passive does not even show up in the Crônica
	g = _eletrica_game()
	a = g.active
	g.players[a]["leaked"] = 1
	g._flush()
	g._fire_leader_passive(a, "on_turn_start")
	check(not _has_event(g._flush(), "passive"), "sobrecarga: sem nada a devolver, não anuncia a passiva")
	g.players[a]["leaked"] = 2
	g._fire_leader_passive(a, "on_turn_start")
	check(_has_event(g._flush(), "passive"), "sobrecarga: com Momentum a devolver, anuncia a passiva")

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
	check(rt.card_id == "tony_raiturus_primordial" and g.atk_of(rt) == 9 and rt.hp == 9 and g.has_kw(rt, "intimidacao") and g.has_kw(rt, "impeto") and g.has_kw(rt, "voo") and g.stack.is_empty(), "raiturus vira o Primordial 9/9 Intimidacao + Ímpeto + Voo")
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
	g5.players[p5]["incarnation"]["in_zone"] = false # the AI would cast its Leader first
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

## The AI doesn't waste Momentum: Mordida only as a finisher, no heals at almost full life,
## no pointless revives, no sweeper for a lone unit when comfortable.
func _test_ai_no_waste() -> void:
	var g := _new_game()
	_quiet(g)
	var mordida := CardDB.card("mordida_de_defunto")
	var big := _put(g, 0, "esqueleto_guerreiro")
	big.atk = 6
	var small := _put(g, 0, "broto_zumbi")
	g.players[1]["leader_hp"] = 20
	check(SimpleAI._plan_sacrifice_spell(g, 0, mordida).is_empty(), "IA: Mordida sem letal e sem troca boa não é lançada")
	g.players[1]["leader_hp"] = 6
	var plan := SimpleAI._plan_sacrifice_spell(g, 0, mordida)
	check(plan.size() == 2 and plan[0] == big.uid and plan[1] == GameState.LEADER_UID[1], "IA: Mordida na face quando o ATK de um aliado mata o Líder (plano %s)" % [plan])
	big.atk = 3
	small.atk = 6
	plan = SimpleAI._plan_sacrifice_spell(g, 0, mordida)
	check(plan.size() == 2 and plan[0] == small.uid, "IA: sacrifica o aliado que fecha o letal, não o maior")
	# heal
	var heal := CardDB.card("mare_curativa")
	g.players[0]["leader_hp"] = g.players[0]["leader_max"] - 1
	check(not SimpleAI._spell_is_worth_it(g, 0, heal), "IA: não gasta cura de 4 com Líder a 1 da vida máxima")
	g.players[0]["leader_hp"] = g.players[0]["leader_max"] - 4
	check(SimpleAI._spell_is_worth_it(g, 0, heal), "IA: cura de 4 vale com 4 de vida faltando")
	# revive
	var revive := CardDB.card("chamado_do_alem")
	check(not SimpleAI._spell_is_worth_it(g, 0, revive), "IA: não ressuscita sem alvo")
	g.players[0]["graveyard"].append(Card.new(g._uid(), "esqueleto_guerreiro", 0, "graveyard"))
	var revived_cost := int(CardDB.card("esqueleto_guerreiro")["cost"])
	check(SimpleAI._spell_is_worth_it(g, 0, revive) == (revived_cost >= 2 and revived_cost <= 4), "IA: só ressuscita unidade que não seja descartável (custo %d)" % revived_cost)
	# sweeper: one enemy unit while comfortable -> no; two or more -> yes
	var sweeper := CardDB.card("tsunami")
	g.players[0]["leader_hp"] = g.players[0]["leader_max"]
	var lone := _put(g, 1, "broto_zumbi")
	lone.hp = 3
	check(not SimpleAI._spell_is_worth_it(g, 0, sweeper), "IA: não usa varredura para matar 1 unidade sem pressão")
	var second := _put(g, 1, "broto_zumbi")
	second.hp = 3
	check(SimpleAI._spell_is_worth_it(g, 0, sweeper), "IA: usa varredura que mata 2+ unidades")
	# this-turn buffs (Choque de Largada: +1 ATK and Ímpeto): only when an ally attacks with them
	var shock := CardDB.card("choque_de_largada")
	var g2 := _new_game()
	_quiet(g2)
	g2.active = 0
	var fresh := _put(g2, 0, "broto_zumbi")
	fresh.sick = true
	check(not SimpleAI._spell_is_worth_it(g2, 0, shock), "IA: Choque de Largada não é lançado com o campo inimigo vazio (Ímpeto não vai na face)")
	var tapped_enemy := _put(g2, 1, "broto_zumbi")
	tapped_enemy.exhausted = true
	check(SimpleAI._spell_is_worth_it(g2, 0, shock), "IA: Choque de Largada vale para dar Ímpeto e desafiar uma unidade virada")
	g2.active = 1
	check(not SimpleAI._spell_is_worth_it(g2, 0, shock), "IA: buff de turno não é lançado no turno do inimigo")

## The AI's attack clauses: face instead of chip challenges, no pointless trades, no feeding Roubo de Vida.
func _test_ai_attack_clauses() -> void:
	_tcard("t_ai_wall", 2, 6, [])
	_tcard("t_ai_even", 3, 3, [])
	_tcard("t_ai_bruiser", 4, 4, [])
	_tcard("t_ai_big", 5, 5, [])
	_tcard("t_ai_glass", 4, 2, [])
	_tcard("t_ai_small", 2, 2, [])
	_tcard("t_ai_engine", 2, 2, [{"trigger": "on_turn_end", "action": "heal_leader", "amount": 1}])
	# 1. a chip challenge is not worth it: the unhurt wall can't punish a 2/5, so the AI goes face
	_tcard("t_ai_chipper", 2, 5, [])
	var g := _new_game()
	_quiet(g)
	var chipper := _put(g, 0, "t_ai_chipper")
	var wall := _put(g, 1, "t_ai_wall")
	wall.exhausted = true # only a tapped unit can be challenged
	g.players[1]["leader_hp"] = 20
	g.go_to_combat(0)
	SimpleAI._try_attack(g, 0)
	check(g.players[1]["leader_hp"] == 18 and wall.damage == 0, "IA: sem troca boa e sem risco, vai na face em vez de bater de leve (vida %d)" % g.players[1]["leader_hp"])
	# 2. an even trade that leaves the Leader healthy is not taken: the unit stays home
	g = _new_game()
	_quiet(g)
	_put(g, 0, "t_ai_even")
	var rival := _put(g, 1, "t_ai_bruiser")
	rival.exhausted = true
	g.players[1]["leader_hp"] = 25
	g.go_to_combat(0)
	var events := SimpleAI._try_attack(g, 0)
	check(events.is_empty() and rival.damage == 0 and g.players[1]["leader_hp"] == 25, "IA: troca igual com o inimigo saudável não acontece, nem exposição à toa")
	# 3. a Roubo de Vida target is a worse trade: its strike-back heals the enemy Leader
	_tcard("t_ai_leech", 3, 3, [])
	CardDB.card("t_ai_leech")["keywords"] = ["roubo_de_vida"]
	g = _new_game()
	_quiet(g)
	var attacker := _put(g, 0, "t_ai_even")
	var plain_target := _put(g, 1, "t_ai_even")
	var leech_target := _put(g, 1, "t_ai_leech")
	var plain_score := SimpleAI._challenge_score(g, attacker, plain_target)
	var leech_score := SimpleAI._challenge_score(g, attacker, leech_target)
	check(leech_score < plain_score, "IA: desafiar Roubo de Vida vale menos (cura o Líder inimigo): %d vs %d" % [leech_score, plain_score])
	# 4. a great trade (kills for free) is still taken even with the face open
	g = _new_game()
	_quiet(g)
	g.players[0]["hand"].clear() # a random burn card in hand would turn this into a rush
	_put(g, 0, "t_ai_big")
	var glass := _put(g, 1, "t_ai_glass")
	glass.exhausted = true
	g.players[1]["leader_hp"] = 20
	g.go_to_combat(0)
	var kill_events := SimpleAI._try_attack(g, 0)
	check(g.find_unit(glass.uid) == null and g.players[1]["leader_hp"] == 20, "IA: matar de graça ainda é melhor que a face")
	# 5. burn in hand makes the exposed engine hit acceptable (the Leader ends inside burn reach)
	g = _new_game()
	_quiet(g)
	var engine := _put(g, 0, "t_ai_engine")
	_put(g, 1, "t_ai_even")
	g.players[1]["leader_hp"] = 15
	check(not SimpleAI._face_hit_is_acceptable(g, 0, engine, 0), "IA: engine exposta não vai na face sem motivo")
	check(SimpleAI._face_hit_is_acceptable(g, 0, engine, 13), "IA: engine exposta vai na face se o burn da mão termina o jogo")
	# 6. rush: the enemy is about to die, so the exposed unit swings at the face instead of trading
	g = _new_game()
	_quiet(g)
	var rusher := _put(g, 0, "t_ai_small")
	_put(g, 0, "t_ai_small")
	var guard := _put(g, 1, "t_ai_even")
	g.players[1]["leader_hp"] = 8
	g.go_to_combat(0)
	SimpleAI._try_attack(g, 0)
	check(g.players[1]["leader_hp"] == 6 and guard.damage == 0, "IA: com o Líder inimigo perto de morrer, ataca a face em vez de trocar (vida %d)" % g.players[1]["leader_hp"])

## The AI holds Bola de Fogo for the face when its board is racing, and fires it for lethal.
func _test_ai_burn_plan() -> void:
	_tcard("t_ai_racer", 2, 2, [])
	_tcard("t_ai_blocker", 1, 3, [])
	var fireball := CardDB.card("bola_de_fogo")
	var g := _new_game()
	_quiet(g)
	g.active = 0
	g.players[0]["max_momentum"] = 5
	g.players[0]["momentum"] = 5
	g.players[0]["hand"].clear()
	g.players[0]["incarnation"]["in_zone"] = false # the Leader's Encarnação would be cast before anything else
	_give(g, 0, "bola_de_fogo")
	_put(g, 0, "t_ai_racer")
	_put(g, 0, "t_ai_racer")
	_put(g, 1, "t_ai_blocker")
	g.players[1]["leader_hp"] = 8
	check(SimpleAI._burn_plan(g, 0) == "hold", "IA: aggro perto do fim guarda a Bola de Fogo para a face (plano %s)" % SimpleAI._burn_plan(g, 0))
	check(not SimpleAI._spell_is_worth_it(g, 0, fireball), "IA: Bola de Fogo guardada não é gasta em unidade")
	g.players[1]["leader_hp"] = 40
	check(SimpleAI._burn_plan(g, 0) == "free" and SimpleAI._spell_is_worth_it(g, 0, fireball), "IA: contra um inimigo longe de morrer, a Bola de Fogo é usada normalmente")
	g.players[1]["leader_hp"] = 5
	check(SimpleAI._burn_plan(g, 0) == "lethal", "IA: burn + ataques fecham o letal (plano %s)" % SimpleAI._burn_plan(g, 0))
	var events := SimpleAI._try_play(g, 0)
	check(not events.is_empty() and g.players[1]["leader_hp"] == 2, "IA: lança a Bola de Fogo na face antes de gastar o Momentum (vida %d)" % g.players[1]["leader_hp"])

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

## Deck "Ladeira Ascendente": Ritual do Degelo (+3 Momentum agora, -2 no próximo turno; não mexe no nível), Ladeira Abaixo e Sem Freio (sobe metade do nível, arredondada para cima),
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

## Dona Gertrudes Fura-Fila: Ao Entrar, a champion from the hand enters for free and is banished at the end of the turn.
func _test_gertrudes() -> void:
	_tcard("teste_alvo_gelo", 0, 20, [])
	# the same-turn Wanessa line: Gertrudes (4) + Ladeira (4) out of 10 Momentum, Wanessa never paid for
	var g := _glacial_game()
	g.players[0]["hand"].clear() # the opening hand is random: start from an empty one
	g.players[1]["hand"].clear()
	var a := g.active
	var o := g.opponent(a)
	g.players[a]["momentum"] = 10
	g.players[a]["reserve"] = 0
	g.players[a]["snowball"] = 5
	g.players[o]["leader_hp"] = 60
	var wanessa_uid := _give(g, a, "princesa_wanessa")
	_give(g, a, "teste_alvo_gelo") # a non-champion in hand is not offered
	var gertrudes_uid := _give(g, a, "dona_gertrudes_fura_fila")
	check(g.cost_of(a, CardDB.card("dona_gertrudes_fura_fila")) == 4, "Gertrudes custa 4")
	g.play_card(a, gertrudes_uid, 0)
	for guard in 8:
		if g.stack.is_empty():
			break
		g.pass_priority(g.priority)
	g._flush()
	check(g.phase == "search" and g.pending_search.get("hand_summon", false), "Gertrudes: o Ao Entrar abre a escolha de um campeão da mão")
	var offered: Array = g.pending_search["cards"]
	check(offered.size() == 1 and int(offered[0]["uid"]) == wanessa_uid, "Gertrudes: só campeões da mão são oferecidos")
	check(g.choose_search(1 - a, wanessa_uid).is_empty(), "Gertrudes: o oponente não escolhe por você")
	check(not g.choose_search(a, wanessa_uid).is_empty(), "Gertrudes: a escolha é aceita")
	var wanessa := g.find_unit(wanessa_uid)
	check(wanessa != null and wanessa.zone == "board" and wanessa.banish_at_turn_end, "Gertrudes: a Princesa Wanessa entra em campo, marcada para ser banida")
	check(int(g.players[a]["momentum"]) == 6, "Gertrudes: só o custo dela foi pago (10 - 4), a Wanessa entrou de graça")
	_cast_and_resolve(g, a, "ladeira_abaixo_e_sem_freio")
	check(wanessa.card_id == "wanessa_tempesfrost" and not wanessa.sick, "Gertrudes: a Ladeira cruza para Grande e a Wanessa já ataca no mesmo turno")
	check(wanessa.banish_at_turn_end, "Gertrudes: transformar não tira a marca de banimento")
	_hit(g, wanessa, GameState.LEADER_UID[o])
	check(int(g.players[o]["leader_hp"]) < 60, "Gertrudes: a Tempesfrost machucou o Líder inimigo")
	g.end_turn(a)
	check(g.find_unit(wanessa_uid) == null and g.players[a]["banished"].has(wanessa), "Gertrudes: no fim do turno a Wanessa é banida (não vai ao cemitério)")
	check(g.find_unit(gertrudes_uid) != null, "Gertrudes: ela mesma continua em campo")

	# the Ao Entrar of the champion fires: Wanessa freezes an enemy unit
	var enter := _glacial_game()
	enter.players[0]["hand"].clear() # the opening hand is random: start from an empty one
	enter.players[1]["hand"].clear()
	var enter_player := enter.active
	var enemy := _put(enter, enter.opponent(enter_player), "teste_alvo_gelo")
	enter.players[enter_player]["momentum"] = 10
	var enter_wanessa := _give(enter, enter_player, "princesa_wanessa")
	enter.play_card(enter_player, _give(enter, enter_player, "dona_gertrudes_fura_fila"), 0)
	for guard in 8:
		if enter.stack.is_empty():
			break
		enter.pass_priority(enter.priority)
	enter._flush()
	enter.choose_search(enter_player, enter_wanessa)
	if enter.phase == "enter_target":
		enter.choose_enter_target(enter_player, enemy.uid)
	check(enemy.frozen > 0, "Gertrudes: o Ao Entrar da Wanessa dispara e congela uma unidade inimiga")

	# no champion in hand: nothing to choose, the game carries on
	var empty := _glacial_game()
	empty.players[0]["hand"].clear() # the opening hand is random: start from an empty one
	empty.players[1]["hand"].clear()
	var empty_player := empty.active
	empty.players[empty_player]["momentum"] = 10
	empty.play_card(empty_player, _give(empty, empty_player, "dona_gertrudes_fura_fila"), 0)
	for guard in 8:
		if empty.stack.is_empty():
			break
		empty.pass_priority(empty.priority)
	empty._flush()
	check(empty.phase != "search", "Gertrudes: sem campeão na mão, não abre escolha")

	# a full board: there is no slot for the champion
	var crowded := _glacial_game()
	crowded.players[0]["hand"].clear() # the opening hand is random: start from an empty one
	crowded.players[1]["hand"].clear()
	var crowded_player := crowded.active
	crowded.players[crowded_player]["momentum"] = 10
	_give(crowded, crowded_player, "princesa_wanessa")
	for i in GameState.BOARD_LIMIT - 1:
		_put(crowded, crowded_player, "teste_alvo_gelo")
	crowded.play_card(crowded_player, _give(crowded, crowded_player, "dona_gertrudes_fura_fila"), 0)
	for guard in 8:
		if crowded.stack.is_empty():
			break
		crowded.pass_priority(crowded.priority)
	crowded._flush()
	check(crowded.phase != "search", "Gertrudes: com o campo cheio não há onde colocar o campeão")

	# the pick is private: the other seat sees it face down
	var hidden := _glacial_game()
	hidden.players[0]["hand"].clear() # the opening hand is random: start from an empty one
	hidden.players[1]["hand"].clear()
	var hidden_player := hidden.active
	hidden.players[hidden_player]["momentum"] = 10
	_give(hidden, hidden_player, "princesa_wanessa")
	hidden.play_card(hidden_player, _give(hidden, hidden_player, "dona_gertrudes_fura_fila"), 0)
	for guard in 8:
		if hidden.stack.is_empty():
			break
		hidden.pass_priority(hidden.priority)
	hidden._flush()
	var seen_by_opponent: Dictionary = StateView.snapshot(hidden, 1 - hidden_player)
	check(String(seen_by_opponent["pending_search"]["cards"][0]["card_id"]) == "", "Gertrudes: o adversário não vê qual campeão está na mão")

## Devaneio Gelado: draws 2 and raises the level the Bola de Neve goes back to every turn, for the rest of the game.
## Myrra's Ao Ativar: Escudo + 1 level of Crítico on an ally; Vael also gets +1/+1 for good, anyone else does not.
func _test_myrra_activate() -> void:
	for target_card in ["vael", "guerreiro_igneo"]:
		var g := _new_game()
		_quiet(g)
		g.players[0]["momentum"] = 5
		g.players[0]["reserve"] = 0
		var myrra := _put(g, 0, "myrra")
		var ally := _put(g, 0, target_card)
		var base_attack: int = ally.atk
		var base_health: int = ally.hp
		g.auto_pass[1] = true
		check(g.can_activate(0, myrra.uid), "Myrra pode ativar")
		g.activate(0, myrra.uid, ally.uid)
		g._flush()
		for guard in 8:
			if g.stack.is_empty():
				break
			g.pass_priority(g.priority)
		g._flush()
		check(ally.shield and ally.temp_critico == 1, "Myrra (%s): Escudo e +1 de Crítico" % target_card)
		var expected_bonus := 1 if target_card == "vael" else 0
		check(ally.atk == base_attack + expected_bonus and ally.hp == base_health + expected_bonus, "Myrra (%s): +1/+1 permanente só para o Vael" % target_card)
		check(int(g.players[0]["momentum"]) == 4 and not g.can_activate(0, myrra.uid), "Myrra: custa 1 e é 1x por turno")

## Hoje Ninguém Erra: every ally that has Crítico goes to Crítico 4 this turn, whatever level it had; the others are untouched.
func _test_hoje_ninguem_erra() -> void:
	var g := _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	var gatuno := _put(g, 0, "gatuno_do_beco_torto")
	var myrra := _put(g, 0, "myrra")
	var akane := _put(g, 0, "akane")
	var plain := _put(g, 0, "lancheiro_sem_freio")
	_cast_and_resolve(g, 0, "hoje_ninguem_erra")
	check(gatuno.critico_total() == 4 and myrra.critico_total() == 4 and akane.critico_total() == 4, "Hoje Ninguém Erra: quem tem Crítico (1 ou 4) fica com 4")
	check(plain.critico_total() == 0, "Hoje Ninguém Erra: quem não tem Crítico continua sem")
	g.end_turn(0)
	check(gatuno.critico_total() == 1 and myrra.critico_total() == 1 and akane.critico_total() == 4, "Hoje Ninguém Erra: no fim do turno cada um volta ao seu nível")

func _metalica_game() -> GameState:
	var g := GameState.new("metalica", "fogo", 42)
	g.mulligan(0, [])
	g.mulligan(1, [])
	g.self_response_enabled = false
	_quiet(g)
	return g

## Metálica: milling the opponent's deck, Reflexão, artifact-count scaling and Morakhan's leader power.
func _test_metalica() -> void:
	# Zeladorbot 3000: "who": "enemy" sends the opponent's top cards to THEIR graveyard, the own deck is untouched
	var g := _metalica_game()
	var a := g.active
	var b: int = g.opponent(a)
	g.players[a]["momentum"] = 20
	var enemy_deck_before: int = g.players[b]["deck"].size()
	var enemy_graveyard_before: int = g.players[b]["graveyard"].size()
	var own_deck_before: int = g.players[a]["deck"].size()
	var own_hand_before: int = g.players[a]["hand"].size()
	_cast_and_resolve(g, a, "zeladorbot_3000")
	check(g.phase == "search" and g.pending_search.get("discard_hand", false), "Zeladorbot: depois de comprar, abre a escolha de descarte")
	g.choose_search(a, int(g.pending_search["cards"][0]["uid"]))
	check(g.players[b]["deck"].size() == enemy_deck_before - 1, "Zeladorbot: o deck do oponente perde 1 carta")
	check(g.players[b]["graveyard"].size() == enemy_graveyard_before + 1, "Zeladorbot: a carta moída vai para o cemitério do oponente")
	check(g.players[a]["deck"].size() == own_deck_before - 1, "Zeladorbot: comprou 1 carta do próprio deck")
	check(g.players[a]["hand"].size() == own_hand_before, "Zeladorbot: comprou 1 e descartou 1 (o próprio Zeladorbot já saiu da mão)")

	# Trituração em Massa: mills 2 and replaces itself (draws 1) for 2 Momentum
	g = _metalica_game()
	a = g.active
	b = g.opponent(a)
	g.players[a]["momentum"] = 20
	enemy_deck_before = g.players[b]["deck"].size()
	own_deck_before = g.players[a]["deck"].size()
	var momentum_before: int = g.players[a]["momentum"]
	_cast_and_resolve(g, a, "trituracao_em_massa")
	check(g.players[b]["deck"].size() == enemy_deck_before - 2, "Trituração em Massa: o deck do oponente perde 2 cartas")
	check(g.players[a]["deck"].size() == own_deck_before - 1, "Trituração em Massa: compra 1 carta")
	check(g.players[a]["momentum"] == momentum_before - 2, "Trituração em Massa: custa 2")

	# Tyren: no innate Armadura; a hit sets it to 1 (never lowers a higher one); only spell damage grants a temporary Escudo Supremo
	g = _metalica_game()
	a = g.active
	b = g.opponent(a)
	g.players[a]["momentum"] = 30
	var tyren := _put(g, b, "tyren")
	check(g.armor_of(tyren) == 0 and not tyren.spell_shield, "Tyren: sem Armadura nem Escudo de Feitiço ao entrar")
	g._deal_damage(tyren.uid, 1, null)
	g._check_state() # a direct hit only queues the Ao Sofrer Dano trigger; this resolves it
	check(tyren.armor == 1, "Tyren: dano que não é de feitiço faz a Armadura passar a ser 1")
	check(not tyren.spell_shield, "Tyren: dano que não é de feitiço não dá Escudo de Feitiço")
	tyren.armor = 3
	g._deal_damage(tyren.uid, 1, null)
	g._check_state() # a direct hit only queues the Ao Sofrer Dano trigger; this resolves it
	check(tyren.armor == 3, "Tyren: uma Armadura maior que 1 não é diminuída")
	tyren.armor = 0
	tyren.damage = 0 # the earlier hits would otherwise leave too little Vida for a 3-damage spell
	var tyren_hp_before: int = g.hp_left(tyren)
	_cast_and_resolve(g, a, "golpe_de_marreta", tyren.uid)
	check(g.hp_left(tyren) == tyren_hp_before - 3, "Tyren: o feitiço que o atinge causa o dano inteiro (o escudo é para o próximo)")
	check(tyren.armor == 1 and tyren.supreme_shield and tyren.supreme_shield_expires == "next_turn", "Tyren: dano de feitiço dá Armadura 1 e Escudo Supremo temporário")
	tyren_hp_before = g.hp_left(tyren)
	_cast_and_resolve(g, a, "golpe_de_marreta", tyren.uid)
	check(g.hp_left(tyren) == tyren_hp_before and not tyren.supreme_shield, "Tyren: o próximo feitiço inimigo é absorvido e gasta o Escudo Supremo")
	check(not tyren.spell_shield, "Tyren: não ganha Escudo de Feitiço")
	tyren.grant_supreme_shield("next_turn")
	g._start_turn(b, false)
	check(not tyren.supreme_shield and tyren.supreme_shield_expires == "", "Tyren: o Escudo Supremo acaba no início do próximo turno do controlador")

	# Biblioteca de Peças: only the 5 cards on top are searched; an artifact buried deeper is not found
	# (the filler is a spell, which is never eligible: Metálica units of cost 4 or less count as "peças" too)
	g = _metalica_game()
	a = g.active
	g.players[a]["deck"].clear()
	for card_id in ["engrenagem_solta", "golpe_de_marreta", "golpe_de_marreta", "golpe_de_marreta", "golpe_de_marreta", "golpe_de_marreta"]:
		g.players[a]["deck"].append(Card.new(g._uid(), card_id, a, "deck"))
	g.players[a]["momentum"] = 20
	_cast_and_resolve(g, a, "biblioteca_de_pecas")
	check(g.phase != "search", "Biblioteca de Peças: o artefato fora das 5 do topo não é encontrado")
	# with the artifact among the top 5 it is offered face up, and the rest of the top 5 goes to the bottom
	g.players[a]["deck"].append(Card.new(g._uid(), "moedor_de_sucata", a, "deck"))
	_cast_and_resolve(g, a, "biblioteca_de_pecas")
	check(g.phase == "search" and g.pending_search["cards"].size() == 1 and g.pending_search["cards"][0]["card_id"] == "moedor_de_sucata", "Biblioteca de Peças: oferece o artefato do topo")
	if g.phase == "search":
		# the options of a deck search are private: the opponent's view has no cards at all, the searcher's has them
		check(not StateView.snapshot(g, a)["pending_search"]["cards"].is_empty(), "Biblioteca de Peças: quem busca vê as opções")
		check(StateView.snapshot(g, 1 - a)["pending_search"]["cards"].is_empty(), "Biblioteca de Peças: o oponente não vê as opções")
		var reveal_events: Array = StateView.filter_events([{"type": "search_reveal", "player": a, "private": true, "cards": g.pending_search["cards"]}], 1 - a)
		check(reveal_events[0]["cards"].is_empty(), "Biblioteca de Peças: evento da busca escondido do oponente")
		g.choose_search(a, int(g.pending_search["cards"][0]["uid"]))
		check(g.players[a]["deck"].size() == 6 and g.players[a]["deck"][0].card_id == "golpe_de_marreta", "Biblioteca de Peças: as outras vão para o fundo")

	# Biblioteca de Peças also finds Metálica units of cost 4 or less, but not a bigger unit nor another essence's unit
	g = _metalica_game()
	a = g.active
	g.players[a]["momentum"] = 20
	g.players[a]["deck"].clear()
	for card_id in ["golpe_de_marreta", "brontharax", "kai", "tyren", "golpe_de_marreta"]:
		g.players[a]["deck"].append(Card.new(g._uid(), card_id, a, "deck"))
	_cast_and_resolve(g, a, "biblioteca_de_pecas")
	var offered_ids: Array = []
	if g.phase == "search":
		for offered in g.pending_search["cards"]:
			offered_ids.append(offered["card_id"])
	check(offered_ids == ["tyren"], "Biblioteca de Peças: só a unidade Metálica de custo <= 4 é oferecida (%s)" % [offered_ids])

	# Hora Extra Compulsória: the opponent suffers their next Fadiga now, with cards still in the deck, and the counter advances
	g = _metalica_game()
	a = g.active
	b = g.opponent(a)
	g.players[a]["momentum"] = 20
	var enemy_hp_before_fatigue: int = g.players[b]["leader_hp"]
	var enemy_deck_before_fatigue: int = g.players[b]["deck"].size()
	_cast_and_resolve(g, a, "hora_extra_compulsoria")
	check(enemy_hp_before_fatigue - g.players[b]["leader_hp"] == 2, "Hora Extra Compulsória: a primeira Fadiga causa 2")
	check(g.players[b]["deck"].size() == enemy_deck_before_fatigue, "Hora Extra Compulsória: o deck do oponente não muda")
	enemy_hp_before_fatigue = g.players[b]["leader_hp"]
	_cast_and_resolve(g, a, "hora_extra_compulsoria")
	check(enemy_hp_before_fatigue - g.players[b]["leader_hp"] == 4, "Hora Extra Compulsória: a segunda Fadiga já vem dobrada (4)")

	# Moer um deck que acabou (ou que não tem cartas suficientes) faz o oponente sofrer 1 Fadiga; moer o próprio deck não
	g = _metalica_game()
	a = g.active
	b = g.opponent(a)
	g.players[a]["momentum"] = 20
	while g.players[b]["deck"].size() > 1:
		g.players[b]["deck"].pop_back()
	var enemy_hp_before_overmill: int = g.players[b]["leader_hp"]
	_cast_and_resolve(g, a, "trituracao_em_massa")
	check(g.players[b]["deck"].is_empty(), "Trituração em Massa: moeu a carta que restava")
	check(enemy_hp_before_overmill - g.players[b]["leader_hp"] == 2, "Trituração em Massa: faltou carta para moer, então 1 Fadiga (2 de dano)")
	enemy_hp_before_overmill = g.players[b]["leader_hp"]
	_cast_and_resolve(g, a, "trituracao_em_massa")
	check(enemy_hp_before_overmill - g.players[b]["leader_hp"] == 4, "Trituração em Massa: com o deck vazio, cada uso é 1 Fadiga (a segunda é 4)")

	# Devolução ao Remetente: cancels a spell aimed at an ally and hits the enemy Leader for 3
	g = _metalica_game()
	a = g.active
	b = g.opponent(a)
	g.players[a]["momentum"] = 20
	g.players[b]["momentum"] = 20
	var protected_unit := _put(g, b, "rakhana")
	var caster_leader_hp: int = g.players[a]["leader_hp"]
	var counter_uid := _give(g, b, "devolucao_ao_remetente") # in hand BEFORE the spell, or the stack resolves without waiting for a response
	g.play_card(a, _give(g, a, "golpe_de_marreta"), protected_unit.uid)
	g.play_card(b, counter_uid, g.stack[0]["sid"])
	_resolve_stack(g)
	check(protected_unit.damage == 0, "Devolução ao Remetente: o feitiço que mirava a unidade aliada foi anulado")
	check(g.players[a]["leader_hp"] == caster_leader_hp - 3, "Devolução ao Remetente: 3 de dano no Líder de quem lançou")

	# Reflexão: the attacker takes half (rounded up) of the damage; the reflected hit does not reflect again
	g = _metalica_game()
	a = g.active
	b = g.opponent(a)
	# Fixture mirrors without Armadura, so the numbers don't move whenever Rakhana is rebalanced
	_tcard("t_mirror", 3, 6, [])
	CardDB.data()["cards"]["t_mirror"]["keywords"] = ["reflexao"]
	var mirror_a := _put(g, a, "t_mirror")
	var mirror_b := _put(g, b, "t_mirror")
	g._deal_damage(mirror_a.uid, 5, mirror_b)
	g._flush()
	check(g.hp_left(mirror_a) == 1, "Reflexão: quem tem Reflexão sofre o dano normal (5)")
	check(g.hp_left(mirror_b) == 3, "Reflexão: o atacante sofre metade do dano, arredondada para cima (3)")
	check(g.hp_left(mirror_a) == 1, "Reflexão: o dano refletido não reflete de volta")

	# Berengar Voss grows with every own artifact in play: relics and equipment both count
	g = _metalica_game()
	a = g.active
	g.players[a]["momentum"] = 20
	var uncle := _put(g, a, "berengar_voss")
	var other := _put(g, a, "zeladorbot_3000")
	check(g.atk_of(uncle) == 1 and g.hp_left(uncle) == 3, "Berengar Voss: sem artefatos é 1/3")
	_cast_and_resolve(g, a, "moedor_de_sucata")
	check(g.atk_of(uncle) == 2 and g.hp_left(uncle) == 4, "Berengar Voss: um artefato em campo dá +1/+1")
	_cast_and_resolve(g, a, "engrenagem_solta", other.uid)
	check(g.atk_of(uncle) == 3 and g.hp_left(uncle) == 5, "Berengar Voss: artefato equipado também conta")

	# Morakhan's leader power: an ally gets Reflexão until the end of the turn
	g = _metalica_game()
	a = g.active
	var ally := _put(g, a, "zeladorbot_3000")
	g.players[a]["ability_used"] = false
	g.players[a]["momentum"] = 5
	check(g.can_use_ability(a), "Morakhan: Postura da Montanha disponível")
	g.use_ability(a, ally.uid)
	_resolve_stack(g)
	check(g.has_kw(ally, "reflexao"), "Morakhan: a unidade ganha Reflexão")
	check(int(g.players[a]["momentum"]) == 3, "Morakhan: Postura da Montanha custa 2")
	g.end_turn(a)
	check(not g.has_kw(ally, "reflexao"), "Morakhan: a Reflexão some no fim do turno")

	# Morakhan the champion: 0/13 with no Escudo, +1 Ataque each time it is damaged, until its controller's next turn starts
	g = _metalica_game()
	a = g.active
	b = g.opponent(a)
	var mountain := _put(g, a, "morakhan")
	var attacker := _put(g, b, "rakhana")
	check(g.atk_of(mountain) == 0 and g.hp_left(mountain) == 13, "Morakhan: 0/13")
	check(not mountain.shield and not g.has_kw(mountain, "escudo"), "Morakhan: sem Escudo")
	check(g.has_kw(mountain, "reflexao"), "Morakhan: tem Reflexão")
	var deck_before_hits: int = g.players[b]["deck"].size()
	g._deal_damage(mountain.uid, 3, attacker)
	g._check_state() # a direct hit only queues the Ao Sofrer Dano trigger; this resolves it
	check(g.atk_of(mountain) == 1, "Morakhan: ao sofrer dano ganha +1 de Ataque")
	g._deal_damage(mountain.uid, 3, attacker)
	g._check_state()
	check(g.atk_of(mountain) == 1, "Morakhan: o Ao Sofrer Dano é uma vez por turno (o segundo dano não dá bônus)")
	check(g.players[b]["deck"].size() == deck_before_hits - 1, "Morakhan: só mói 1 carta por turno, mesmo sofrendo dois danos")
	g.end_turn(g.active)
	check(g.atk_of(mountain) == 1, "Morakhan: o bônus continua durante o turno do oponente")
	g._deal_damage(mountain.uid, 3, attacker)
	g._check_state()
	check(g.atk_of(mountain) == 2, "Morakhan: no turno seguinte o gatilho volta a funcionar")
	g.end_turn(g.active)
	check(g.atk_of(mountain) == 0, "Morakhan: o bônus some quando o próximo turno do controlador começa")

	# A unit with 0 ATK may attack and challenge: it deals no damage but the attack happens normally
	g = _metalica_game()
	a = g.active
	b = g.opponent(a)
	mountain = _put(g, a, "morakhan")
	check(g.atk_of(mountain) == 0 and g.can_attack(mountain), "0 de Ataque: a unidade pode atacar")
	var enemy_leader_hp_before: int = g.players[b]["leader_hp"]
	var face_events := _hit(g, mountain)
	check(not face_events.is_empty() and mountain.exhausted, "0 de Ataque: o ataque ao Líder acontece e vira a unidade")
	check(g.players[b]["leader_hp"] == enemy_leader_hp_before, "0 de Ataque: o ataque ao Líder não causa dano")
	check(g.atk_of(mountain) == 0 and mountain.damage == 0, "0 de Ataque: bater no Líder não machuca quem ataca")

	g = _metalica_game()
	a = g.active
	b = g.opponent(a)
	mountain = _put(g, a, "morakhan")
	var tapped_enemy := _put(g, b, "rakhana")
	tapped_enemy.exhausted = true
	check(g.attack_targets(mountain).has(tapped_enemy.uid), "0 de Ataque: pode desafiar uma unidade virada")
	var challenge_events := _hit(g, mountain, tapped_enemy.uid)
	g._check_state()
	check(not challenge_events.is_empty(), "0 de Ataque: o desafio acontece")
	# the only damage the target takes is Morakhan's Reflexão (half of what it struck back), never a blow of its own
	check(tapped_enemy.damage == ceili(mountain.damage / 2.0), "0 de Ataque: o desafio não causa dano ao alvo (só a Reflexão volta)")
	check(mountain.damage > 0, "0 de Ataque: o defensor revida e Morakhan se machuca")
	check(g.atk_of(mountain) == 1, "0 de Ataque: Morakhan se autoinduz dano e ganha +1 de Ataque")

func _test_devaneio_permanent() -> void:
	var g := _glacial_game()
	var a := g.active
	g.players[a]["momentum"] = 20
	check(g.players[a]["snowball_base"] == 2, "Devaneio: a base da Bola começa em 2")
	_cast_and_resolve(g, a, "devaneio_gelado")
	check(g.players[a]["snowball"] == 3 and g.players[a]["snowball_base"] == 3, "Devaneio: o nível atual e a base sobem 1")
	_cast_and_resolve(g, a, "devaneio_gelado")
	check(g.players[a]["snowball"] == 4 and g.players[a]["snowball_base"] == 4, "Devaneio: duas conjurações somam na base")
	g.players[a]["snowball"] = 9
	g.reset_snowball_level(a)
	check(g.players[a]["snowball"] == 4, "Devaneio: no fim do turno a Bola volta à base elevada, não a 2")
	var other: int = g.opponent(a)
	check(g.players[other]["snowball_base"] == 2, "Devaneio: a base do adversário não muda")

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
			check(int(g.players[a]["snowball"]) == _after_ladeira(level), "combo (%s): o Ritual não mexe no nível da Bola de Neve" % label)
			_cast_and_resolve(g, a, "ladeira_abaixo_e_sem_freio")
			check(int(g.players[a]["snowball"]) == _after_ladeira(_after_ladeira(level)) and g.snowball_is_grande(a), "combo (%s): a segunda Ladeira leva o nível a Grande (%d)" % [label, int(g.players[a]["snowball"])])
			check(princess.card_id == "wanessa_tempesfrost" and not princess.sick, "combo (%s): Wanessa vira Tempesfrost ao nível virar Grande e já pode atacar" % label)
			check(g.players[o]["board"].all(func(c: Card): return c.frozen > 0), "combo (%s): ao transformar, todas as unidades inimigas ficam congeladas" % label)
			check(waiting_bola.card_id == "grande_bola_de_neve", "combo (%s): a Bola de Neve que esperava na mão evoluiu ao cruzar o nível 8" % label)
			var grande_cost := g.cost_of(a, CardDB.card(waiting_bola.card_id))
			check(grande_cost == 3 and g.budget(a, true) == 4, "combo (%s): sobram 4 de Momentum para a Grande Bola de Neve (custo %d, sobra %d)" % [label, grande_cost, g.budget(a, true)])
			g.play_card(a, waiting_bola.uid, first_enemy.uid)
			for guard in 8:
				if g.stack.is_empty():
					break
				g.pass_priority(g.priority)
			g._flush()
			check(g.budget(a, true) == 1, "combo (%s): o combo do 8º turno termina com 1 de Momentum sobrando" % label)
			_hit(g, princess, GameState.LEADER_UID[o])
			var leader_damage: int = 60 - int(g.players[o]["leader_hp"])
			check(leader_damage >= 10, "combo (%s): dano ao Líder inimigo foi %d (esperado 10 ou mais)" % [label, leader_damage])

	# two turns earlier (6 Momentum + 2 Reserva) the last Grande Bola de Neve no longer fits
	var early := _combo_game(3, 1, 6, 2)
	var early_game: GameState = early["game"]
	var early_player: int = early["me"]
	_cast_and_resolve(early_game, early_player, "ladeira_abaixo_e_sem_freio")
	_cast_and_resolve(early_game, early_player, "ritual_do_degelo")
	_cast_and_resolve(early_game, early_player, "ladeira_abaixo_e_sem_freio")
	var early_bola := _give(early_game, early_player, "grande_bola_de_neve")
	check(not early_game.can_play(early_player, early_bola), "combo: no 6º turno falta Momentum para a Grande Bola de Neve")

	# two Rituais: both Momentum gains land and the debts add up for the next turn
	var twice := _combo_game(3, 1, 5, 0)
	var twice_game: GameState = twice["game"]
	_cast_and_resolve(twice_game, twice["me"], "ritual_do_degelo")
	_cast_and_resolve(twice_game, twice["me"], "ritual_do_degelo")
	check(int(twice_game.players[twice["me"]]["momentum"]) == 9 and int(twice_game.players[twice["me"]]["next_momentum"]) == -4, "dois Rituais: Momentum 5 - 1 + 3 - 1 + 3 = 9 e dívida de 4 no próximo turno")

	# Ritual alone: the level stays put and the 3 Momentum come back (net +2)
	var ritual := _combo_game(3, 1, 7, 0)
	var ritual_game: GameState = ritual["game"]
	_cast_and_resolve(ritual_game, ritual["me"], "ritual_do_degelo")
	check(int(ritual_game.players[ritual["me"]]["snowball"]) == 3 and int(ritual_game.players[ritual["me"]]["momentum"]) == 9, "Ritual do Degelo: o nível continua 3 e o Momentum é 7 - 1 + 3 = 9")
	check(int(ritual_game.players[ritual["me"]]["next_momentum"]) == -2, "Ritual do Degelo: deixa uma dívida de 2 Momentum para o próximo turno")
	# the debt is charged when the next turn starts and never takes Momentum below 0
	var debt_player: int = ritual["me"]
	ritual_game.players[debt_player]["max_momentum"] = 5
	ritual_game._start_turn(debt_player, false)
	check(int(ritual_game.players[debt_player]["max_momentum"]) == 6 and int(ritual_game.players[debt_player]["momentum"]) == 4 and int(ritual_game.players[debt_player]["next_momentum"]) == 0, "Ritual do Degelo: a dívida tira 2 só do Momentum daquele turno, sem mexer no máximo")
	ritual_game._start_turn(debt_player, false)
	check(int(ritual_game.players[debt_player]["max_momentum"]) == 7 and int(ritual_game.players[debt_player]["momentum"]) == 7, "Ritual do Degelo: no turno seguinte o Momentum volta ao máximo, sem dívida")
	ritual_game.players[debt_player]["max_momentum"] = 1
	ritual_game.players[debt_player]["next_momentum"] = -2
	ritual_game._start_turn(debt_player, false)
	check(int(ritual_game.players[debt_player]["momentum"]) == 0, "Ritual do Degelo: a dívida nunca deixa o Momentum negativo")

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

	# Princesa Wanessa: Ao Entrar also freezes AND exhausts the chosen enemy unit
	var wanessa := _combo_game(8, 2, 10, 0)
	var wanessa_game: GameState = wanessa["game"]
	var wanessa_victim: Card = wanessa["enemies"][0]
	_cast_and_resolve(wanessa_game, wanessa["me"], "princesa_wanessa")
	wanessa_game.choose_enter_target(wanessa["me"], wanessa_victim.uid)
	wanessa_game._flush()
	check(wanessa_victim.exhausted and wanessa_victim.frozen > 0, "Princesa Wanessa: Ao Entrar congela e exaure a unidade escolhida")
	check(not wanessa["enemies"][1].exhausted and wanessa["enemies"][1].frozen == 0, "Princesa Wanessa: a outra unidade inimiga não é afetada")

	# Princesa Wanessa: o congelamento por feitiço glacial é 1x por turno e só no turno do dono
	var spell_freeze := _combo_game(3, 5, 30, 0)
	var spell_freeze_game: GameState = spell_freeze["game"]
	_cast_and_resolve(spell_freeze_game, spell_freeze["me"], "devaneio_gelado")
	var frozen_after_first: int = spell_freeze["enemies"].filter(func(c: Card): return c.frozen > 0).size()
	check(frozen_after_first == 1, "Princesa Wanessa: o primeiro feitiço glacial do turno congela 1 unidade (%d)" % frozen_after_first)
	_cast_and_resolve(spell_freeze_game, spell_freeze["me"], "devaneio_gelado")
	var frozen_after_second: int = spell_freeze["enemies"].filter(func(c: Card): return c.frozen > 0).size()
	check(frozen_after_second == 1, "Princesa Wanessa: o segundo feitiço glacial no mesmo turno não congela de novo (%d)" % frozen_after_second)
	var off_turn := _combo_game(3, 5, 30, 0)
	var off_turn_game: GameState = off_turn["game"]
	off_turn_game.active = off_turn["foe"] # pretend it is the opponent's turn
	_cast_and_resolve(off_turn_game, off_turn["me"], "devaneio_gelado")
	var frozen_off_turn: int = off_turn["enemies"].filter(func(c: Card): return c.frozen > 0).size()
	check(frozen_off_turn == 0, "Princesa Wanessa: no turno do oponente o feitiço glacial não congela (%d)" % frozen_off_turn)

	# Rei Gelado: 5 random slots of the enemy field. Units in them are frozen+exhausted, empty ones are blocked,
	# so units hit + slots blocked is always 5 (whatever the draw)
	check(int(CardDB.card("rei_gelado")["atk"]) == 6 and int(CardDB.card("rei_gelado")["hp"]) == 9, "Rei Gelado: 6/9")
	for enemy_count in [0, 3, 6, 8]:
		var rei := _combo_game(8, enemy_count, 10, 0)
		var rei_game: GameState = rei["game"]
		var rei_foe: int = rei["foe"]
		_cast_and_resolve(rei_game, rei["me"], "rei_gelado")
		var frozen_units: Array = rei["enemies"].filter(func(c: Card): return c.frozen > 0)
		var blocked_slots: int = int(rei_game.players[rei_foe]["frozen_slots"])
		check(frozen_units.size() + blocked_slots == 5, "Rei Gelado (%d inimigas): unidades atingidas (%d) + espaços vazios bloqueados (%d) = 5" % [enemy_count, frozen_units.size(), blocked_slots])
		check(frozen_units.all(func(c: Card): return c.exhausted), "Rei Gelado (%d inimigas): toda unidade atingida também fica exausta" % enemy_count)
		check(rei["enemies"].all(func(c: Card): return c.frozen > 0 or not c.exhausted), "Rei Gelado (%d inimigas): unidade fora dos espaços sorteados não é afetada" % enemy_count)
		check(rei["princess"].frozen == 0 and int(rei_game.players[rei["me"]]["frozen_slots"]) == 0, "Rei Gelado (%d inimigas): o campo de quem lançou não é afetado" % enemy_count)

	# empty frozen slots take room: with 8 empty slots 5 are blocked, so only 3 units fit
	var block := _combo_game(8, 0, 10, 0)
	var block_game: GameState = block["game"]
	var block_foe: int = block["foe"]
	_cast_and_resolve(block_game, block["me"], "rei_gelado")
	check(int(block_game.players[block_foe]["frozen_slots"]) == 5, "Rei Gelado: campo inimigo vazio tem 5 espaços congelados")
	for filler in 3:
		check(block_game.has_free_slot(block_foe), "Rei Gelado: ainda cabe a unidade %d nos 3 espaços livres" % (filler + 1))
		_put(block_game, block_foe, "teste_alvo_gelo")
	check(not block_game.has_free_slot(block_foe), "Rei Gelado: com 3 unidades e 5 espaços congelados o campo inimigo está cheio")
	# they thaw at the END of the victim's own next turn, not before
	block_game.end_turn(block["me"])
	check(block_game.active == block_foe and int(block_game.players[block_foe]["frozen_slots"]) == 5, "Rei Gelado: os espaços seguem congelados durante o turno do oponente")
	block_game.end_turn(block_foe)
	check(int(block_game.players[block_foe]["frozen_slots"]) == 0 and block_game.has_free_slot(block_foe), "Rei Gelado: os espaços descongelam no fim do turno do oponente")

	# Rei Gelado never rolls on what is already frozen: 6 of 8 enemy units are Congeladas, so only the 2 others are hit
	var thin := _combo_game(8, 8, 10, 0)
	var thin_game: GameState = thin["game"]
	var already_frozen: Array = thin["enemies"].slice(0, 6)
	for frozen_unit: Card in already_frozen:
		frozen_unit.frozen = thin_game.turn + 1
	_cast_and_resolve(thin_game, thin["me"], "rei_gelado")
	var newly_hit: Array = thin["enemies"].slice(6).filter(func(c: Card): return c.frozen > 0 and c.exhausted)
	check(newly_hit.size() == 2, "Rei Gelado: as 2 unidades ainda descongeladas são as atingidas (%d)" % newly_hit.size())
	check(already_frozen.all(func(c: Card): return not c.exhausted), "Rei Gelado: unidade que já estava congelada não gasta um sorteio (nem é exaurida)")

	# ...and neither on a slot that is already frozen: 5 blocked, then another 5 asked, only the 3 left get blocked
	var overlap := _combo_game(8, 0, 10, 0)
	var overlap_game: GameState = overlap["game"]
	var overlap_freeze := EffectRegistry.parse({"action": "freeze_slots", "count": 5, "target": "none"})
	overlap_freeze.apply(EffectContext.new(overlap_game, overlap["me"], "on_enter"), 0)
	overlap_freeze.apply(EffectContext.new(overlap_game, overlap["me"], "on_enter"), 0)
	check(int(overlap_game.players[overlap["foe"]]["frozen_slots"]) == 8, "Rei Gelado: o segundo sorteio só alcança os 3 espaços ainda livres (8 no total)")

	# at the start of its owner's turn Rei Gelado freezes ONE more slot of the enemy field
	var tick := _combo_game(8, 0, 10, 0)
	var tick_game: GameState = tick["game"]
	_put(tick_game, tick["me"], "rei_gelado")
	var after_enter: int = int(tick_game.players[tick["foe"]]["frozen_slots"]) # his Ao Entrar already froze 5 empty slots
	tick_game.end_turn(tick["me"])
	check(int(tick_game.players[tick["foe"]]["frozen_slots"]) == after_enter, "Rei Gelado: no turno do oponente ele não congela nada")
	tick_game.end_turn(tick["foe"])
	check(int(tick_game.players[tick["foe"]]["frozen_slots"]) == 1, "Rei Gelado: os 5 do Ao Entrar descongelam e, no início do próprio turno, ele congela 1 espaço novo do campo inimigo")

	# a random status pick (Wanessa / Weyne) never lands on a unit that already has the status
	var picker := _new_game()
	_quiet(picker)
	var pick_units: Array = [_put(picker, 1, "geodo_vivo"), _put(picker, 1, "geodo_vivo"), _put(picker, 1, "geodo_vivo")]
	pick_units[0].frozen = picker.turn + 1
	pick_units[1].frozen = picker.turn + 1
	var random_freeze := EffectRegistry.parse({"action": "freeze", "target": "random_enemy_unit"})
	var random_context := EffectContext.new(picker, 0, "")
	var only_free_unit_picked := true
	for roll in 30:
		only_free_unit_picked = only_free_unit_picked and random_freeze.target.resolve(random_context, random_freeze) == [pick_units[2].uid]
	check(only_free_unit_picked, "alvo aleatório de congelar: só sorteia unidade que ainda não está congelada")
	pick_units[2].frozen = picker.turn + 1
	check(random_freeze.target.resolve(random_context, random_freeze).is_empty(), "alvo aleatório de congelar: tudo congelado = sem alvo (nada é desperdiçado)")
	var random_damage := EffectRegistry.parse({"action": "damage", "target": "random_enemy_unit", "amount": 1})
	check(not random_damage.target.resolve(random_context, random_damage).is_empty(), "alvo aleatório de dano: continua podendo acertar unidade congelada")

	var distinct_damage := EffectRegistry.parse({"action": "damage", "target": "random_enemy_units", "count": 3, "amount": 2})
	var distinct_picks_work := true
	for roll in 30:
		var distinct_picks: Array = distinct_damage.target.resolve(random_context, distinct_damage)
		var seen: Dictionary = {}
		for picked_uid in distinct_picks:
			seen[picked_uid] = true
		distinct_picks_work = distinct_picks_work and distinct_picks.size() == 3 and seen.size() == 3
	check(distinct_picks_work, "unidades inimigas aleatórias: escolhe até 3 alvos distintos")
	var short_board := _new_game()
	_quiet(short_board)
	_put(short_board, 1, "geodo_vivo")
	_put(short_board, 1, "geodo_vivo")
	var short_context := EffectContext.new(short_board, 0, "")
	check(distinct_damage.target.resolve(short_context, distinct_damage).size() == 2,
		"unidades inimigas aleatórias: nunca escolhe mais alvos do que há no campo")
	var empty_board := _new_game()
	_quiet(empty_board)
	check(distinct_damage.target.resolve(EffectContext.new(empty_board, 0, ""), distinct_damage).is_empty(),
		"unidades inimigas aleatórias: sem unidades não há alvos")

	# Repique Desgovernado: "hits" picks over the enemy units (each hit is 1 damage), nothing to pick on an empty board
	var spread := EffectRegistry.parse({"action": "damage", "target": "random_enemy_unit_spread", "hits": 9, "amount": 1})
	var spread_picks: Array = spread.target.resolve(random_context, spread)
	check(spread_picks.size() == 9, "dano dividido: sorteia uma unidade por ponto de dano (%d)" % spread_picks.size())
	var spread_only_enemy_units := true
	for picked_uid in spread_picks:
		spread_only_enemy_units = spread_only_enemy_units and pick_units.any(func(unit: Card) -> bool: return unit.uid == picked_uid)
	check(spread_only_enemy_units, "dano dividido: só cai em unidades inimigas")
	var spread_game := _new_game()
	_quiet(spread_game)
	spread_game.players[0]["momentum"] = 10
	_tcard("t_spread_target", 1, 10, [])
	var spread_victims: Array = [_put(spread_game, 1, "t_spread_target"), _put(spread_game, 1, "t_spread_target")]
	var health_before := 0
	for victim: Card in spread_victims:
		health_before += spread_game.hp_left(victim)
	check(int(CardDB.card("repique_desgovernado")["effects"][0]["hits"]) == 9, "Repique Desgovernado: o JSON da carta distribui 9 de dano (X = 9)")
	_cast_and_resolve(spread_game, 0, "repique_desgovernado")
	var health_after := 0
	for victim: Card in spread_victims:
		health_after += spread_game.hp_left(victim)
	check(health_before - health_after == 9, "Repique Desgovernado: tira exatamente os pontos de dano da carta de Vida somados das unidades inimigas (sem sobra de Vida alta)")
	# Total Vida below the 9 hits: every hit must find a unit that still has Vida (no hit wasted on an overkilled one),
	# and the Ao Morrer of the first casualties waits for the end of the spell, so its token is never hit.
	_tcard("t_spread_low", 1, 3, [])
	var spread_always_clears := true
	var spread_token_untouched := true
	for roll_seed in 25:
		var spread_wipe := _new_game()
		_quiet(spread_wipe)
		spread_wipe.rng.seed = roll_seed + 1
		spread_wipe.players[0]["momentum"] = 10
		var wipe_victims: Array = [_put(spread_wipe, 1, "semente_teimosa"), _put(spread_wipe, 1, "t_spread_low"), _put(spread_wipe, 1, "t_spread_low")]
		_cast_and_resolve(spread_wipe, 0, "repique_desgovernado")
		var survivors: Array = spread_wipe.players[1]["board"].filter(func(unit: Card) -> bool: return wipe_victims.has(unit))
		spread_always_clears = spread_always_clears and survivors.is_empty()
		var seedlings: Array = spread_wipe.players[1]["board"].filter(func(unit: Card) -> bool: return unit.card_id == "mudinha_do_dossel")
		spread_token_untouched = spread_token_untouched and seedlings.size() == 1 and seedlings[0].damage == 0
	check(spread_always_clears, "Repique Desgovernado: com Vida total abaixo de 9, nenhuma unidade sobrevive (nenhum ponto some em excesso)")
	check(spread_token_untouched, "Repique Desgovernado: a ficha do Ao Morrer só nasce depois do feitiço e não leva dano")
	var empty_spread_game := _new_game()
	_quiet(empty_spread_game)
	empty_spread_game.players[0]["momentum"] = 10
	_cast_and_resolve(empty_spread_game, 0, "repique_desgovernado")
	check(empty_spread_game.players[1]["leader_hp"] == empty_spread_game.players[1]["leader_max"], "Repique Desgovernado: sem unidades inimigas não atinge o Líder")

	# Chamado da Nevasca looks at the top 5 cards and finds a Glacial spell that costs 4 or less there, and nothing else
	var search := _combo_game(3, 0, 10, 0)
	var search_game: GameState = search["game"]
	var searcher: int = search["me"]
	search_game.players[searcher]["deck"].clear()
	var wanted: Array = []
	# the top of the deck is the END of the list: Bola de Neve and Ritual do Degelo qualify but are too deep (not in the top 5);
	# Zero Absoluto costs 5, Nythera is a unit and Carga Acumulada is not Glacial
	for card_id in ["bola_de_neve", "ritual_do_degelo", "ladeira_abaixo_e_sem_freio", "estilhaco_gelido", "zero_absoluto", "nythera", "carga_acumulada"]:
		var deck_card := Card.new(search_game._uid(), card_id, searcher, "deck")
		search_game.players[searcher]["deck"].append(deck_card)
		if card_id in ["ladeira_abaixo_e_sem_freio", "estilhaco_gelido"]:
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
	check(offered == wanted, "Chamado da Nevasca: oferece só feitiços Glaciais de custo 4 ou menos entre as 5 do topo (%s)" % [offered])
	# the overlay must show every card looked at (topmost first), with the eligible ones a subset of them
	var looked_cards: Array = search_game.pending_search["looked_cards"]
	var looked_card_uids: Array = looked_cards.map(func(option: Dictionary): return int(option["uid"]))
	check(looked_cards.size() == 5, "Chamado da Nevasca: mostra as 5 cartas olhadas, não só as elegíveis (%d)" % looked_cards.size())
	check(offered.all(func(uid): return looked_card_uids.has(uid)), "Chamado da Nevasca: as elegíveis são um subconjunto das olhadas")
	check(search_game.players[searcher]["deck"][search_game.players[searcher]["deck"].size() - 1].uid == looked_card_uids[0], "Chamado da Nevasca: a primeira olhada é a carta do topo do deck")
	var opponent_view: Dictionary = StateView.snapshot(search_game, 1 - searcher)["pending_search"]
	check(opponent_view["looked_cards"].is_empty(), "Chamado da Nevasca: o oponente não vê as cartas olhadas")
	# taking one sends the other four looked-at cards to the bottom (no shuffle); the 2 deeper cards stay on top of them
	var taken_uid: int = int(search_game.pending_search["cards"][0]["uid"])
	var looked_uids: Array = search_game.pending_search["to_bottom"].duplicate()
	search_game.choose_search(searcher, taken_uid)
	var deck_after: Array = search_game.players[searcher]["deck"]
	check(deck_after.size() == 6, "Chamado da Nevasca: a carta escolhida sai do deck")
	var bottom_uids: Array = deck_after.slice(0, 4).map(func(card: Card): return card.uid)
	looked_uids.erase(taken_uid)
	bottom_uids.sort()
	looked_uids.sort()
	check(bottom_uids == looked_uids, "Chamado da Nevasca: as outras cartas olhadas vão para o fundo do deck")

	# the new deck: legal and holding the combo pieces
	var combo_deck := DeckDB.get_deck("glacial_combo")
	check(DeckDB.validate("glacial_combo").is_empty() and combo_deck["cards"].has("ritual_do_degelo") and combo_deck["cards"].has("ladeira_abaixo_e_sem_freio"), "deck Ladeira Ascendente é legal e tem as peças do combo")

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
	_resolve_stack(g)

## Lets everything on the stack resolve (the Ao Entrar of a played unit waits there for a response).
## A Provocação asking "enter tapped?" is answered "no".
func _resolve_stack(g: GameState) -> void:
	for guard in 12:
		if g.phase == "enter_tapped":
			g.choose_enter_tapped(g.decider(), false)
		elif g.stack.is_empty():
			break
		else:
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

	# Bola de Neve from the edge: 2, then 3, then 4 (the level starts at 2; the direction has no choice at the edge)
	check(g.players[a]["snowball"] == GameState.SNOWBALL_BASE_LEVEL and GameState.SNOWBALL_BASE_LEVEL == 2, "o nível da Bola de Neve começa em 2")
	_cast_and_resolve(g, a, "bola_de_neve", first.uid)
	check(first.hp_left() == 18 and middle.hp_left() == 17 and last.hp_left() == 16, "bola de neve: 2, 3 e 4 de dano nos quiques (%d/%d/%d)" % [first.hp_left(), middle.hp_left(), last.hp_left()])
	check(g.players[a]["snowball"] == 4, "bola de neve: a próxima começa onde esta parou")
	_cast_and_resolve(g, a, "bola_de_neve", first.uid)
	check(first.hp_left() == 14 and g.players[a]["snowball"] == 6, "segunda bola começa em 4 e termina em 6")

	# the card text shows the owner's current level where it says {nivel}
	var bola_text := String(CardDB.card("bola_de_neve")["text"])
	check(bola_text.contains("{nivel}"), "texto da bola de neve tem o marcador {nivel}")
	var shown_text := CardView.fill_live_numbers(bola_text, int(g.players[a]["snowball"]))
	check(not shown_text.contains("{nivel}") and shown_text.contains("Cause 6 de dano"), "texto da bola de neve mostra o nível atual (6)")
	check(CardView.fill_live_numbers(bola_text, GameState.SNOWBALL_BASE_LEVEL).contains("Cause 2 de dano"), "sem dono, o texto mostra o nível inicial (2)")

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
	check(g.players[o]["leader_hp"] == leader_before - 6 and g.players[a]["snowball"] == 6, "bola no Líder: um golpe só, sem aumentar o nível")
	check(g.players[a]["graveyard"].size() == unit_cast_graveyard_before, "bola de unidade: não deixa carta no cemitério")

	# the level is temporary: at the end of the owner's own turn it goes back to 2, and the Grande cards go back to normal
	g.players[a]["snowball"] = 9
	var grande_in_hand := Card.new(g._uid(), "grande_bola_de_neve", a, "hand")
	var grande_in_deck := Card.new(g._uid(), "grande_bola_de_neve", a, "deck")
	g.players[a]["hand"].append(grande_in_hand)
	g.players[a]["deck"].append(grande_in_deck)
	g.players[o]["snowball"] = 6
	g.end_turn(a)
	check(g.players[a]["snowball"] == 2 and not g.snowball_is_grande(a), "fim do turno: o nível da Bola de Neve volta a 2")
	check(grande_in_hand.card_id == "bola_de_neve" and grande_in_deck.card_id == "bola_de_neve", "fim do turno: Grande Bola de Neve (mão e deck) volta a ser Bola de Neve")
	check(g.players[o]["snowball"] == 6, "fim do turno de um jogador não mexe no nível do outro")
	g.end_turn(o)
	check(g.players[o]["snowball"] == 2, "o nível do outro jogador volta a 2 no fim do turno DELE")

	# Grande Bola de Neve is its own card: own cost, and every hit has Sobrepujança
	check(g.cost_of(a, CardDB.card("bola_de_neve")) == 3, "Bola de Neve comum custa 3")
	check(g.cost_of(a, CardDB.card("grande_bola_de_neve")) == 3, "Grande Bola de Neve custa o mesmo que a Bola de Neve comum (3)")
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
		var top_card: Card = g.players[a]["deck"].back()
		var expected_top := "grande_bola_de_neve" if level == 8 else "bola_de_neve"
		check(top_card.card_id == expected_top and top_card.zone == "deck", "Nythera ao entrar (nível %d): põe %s no topo do deck" % [level, expected_top])
		check(g.players[o]["leader_hp"] == leader_before and nythera_target.frozen == 0 and int(g.players[a]["snowball"]) == level, "Nythera ao entrar (nível %d): não lança a Bola (sem dano nem nível novo) e não congela mais" % level)

	# Zero Absoluto: rápido, custa 4 e congela todas as unidades inimigas (e só elas)
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	_tcard("teste_alvo_gelo", 3, 20, [])
	var frozen_one := _put(g, o, "teste_alvo_gelo")
	var frozen_two := _put(g, o, "teste_alvo_gelo")
	var own_unit := _put(g, a, "teste_alvo_gelo")
	check(g.cost_of(a, CardDB.card("zero_absoluto")) == 5 and CardDB.card("zero_absoluto")["speed"] == "lento", "Zero Absoluto custa 5 e é lento")
	_cast_and_resolve(g, a, "zero_absoluto")
	check(g.is_frozen(frozen_one) and g.is_frozen(frozen_two) and not g.is_frozen(own_unit), "Zero Absoluto congela todas as unidades inimigas e nenhuma aliada")

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
	check(g.cost_of(a, avalanche) == int(avalanche["cost"]) - 2, "amuleto: o primeiro feitiço glacial custa 2 a menos")
	var momentum_before: int = g.players[a]["momentum"]
	_cast_and_resolve(g, a, "avalanche")
	check(momentum_before - int(g.players[a]["momentum"]) == int(avalanche["cost"]) - 2, "amuleto: pagou 2 a menos")
	check(g.cost_of(a, avalanche) == int(avalanche["cost"]), "amuleto: o segundo feitiço do turno custa o normal")

	# two amulets add their discounts, but the amulet's own floor keeps the spell at cost 1 or more
	g = _glacial_game()
	a = g.active
	g.stack_system().attach(_put(g, a, "teste_alvo_gelo"), Card.new(g._uid(), "amuleto_do_primeiro_floco", a))
	g.stack_system().attach(_put(g, a, "teste_alvo_gelo"), Card.new(g._uid(), "amuleto_do_primeiro_floco", a))
	var expensive_spell: Dictionary = CardDB.card("zero_absoluto")
	check(g.cost_of(a, expensive_spell) == int(expensive_spell["cost"]) - 4, "dois amuletos: os descontos se somam")
	var cheap_spell: Dictionary = CardDB.card("bola_de_neve")
	check(g.cost_of(a, cheap_spell) >= 1, "dois amuletos: nunca deixam o feitiço abaixo de 1")

	# Câmara de Êxtase: cancels a lethal damage once, then negates the next 3 hits until the end of the next turn
	g = _glacial_game()
	a = g.active
	var chamber := Card.new(g._uid(), "camara_de_extase", a)
	g._place_relic(a, chamber)
	g.players[a]["leader_hp"] = 5
	g._deal_damage(GameState.LEADER_UID[a], 9, null)
	check(g.players[a]["leader_hp"] == 5, "câmara: o dano que mataria é anulado")
	check(g.find_relic(chamber.uid) == null, "câmara: é destruída ao proteger")
	# the next 3 hits do nothing, in this same turn; the 4th one lands in full
	for hit_number in 3:
		g._deal_damage(GameState.LEADER_UID[a], 3, null)
		check(g.players[a]["leader_hp"] == 5, "câmara: o golpe %d depois de proteger é reduzido a 0" % (hit_number + 1))
	g._deal_damage(GameState.LEADER_UID[a], 3, null)
	check(g.players[a]["leader_hp"] == 2, "câmara: o 4º golpe causa o dano inteiro")
	# the protection ends with the controller's next turn, even if hits are left
	g = _glacial_game()
	a = g.active
	g._place_relic(a, Card.new(g._uid(), "camara_de_extase", a))
	g.players[a]["leader_hp"] = 5
	g._deal_damage(GameState.LEADER_UID[a], 9, null)
	g.turn += 3
	g._deal_damage(GameState.LEADER_UID[a], 3, null)
	check(g.players[a]["leader_hp"] == 2, "câmara: depois do fim do próximo turno do dono o dano volta ao normal")

	# the Chamber's event names the unit whose blow was cancelled (the screen needs it to show the hit landing)
	g = _glacial_game()
	a = g.active
	var ward_chamber := Card.new(g._uid(), "camara_de_extase", a)
	g._place_relic(a, ward_chamber)
	g.players[a]["leader_hp"] = 5
	var striker := _put(g, g.opponent(a), "teste_alvo_gelo")
	g._events.clear()
	g._deal_damage(GameState.LEADER_UID[a], 9, striker)
	var ward_event := {}
	for event: Dictionary in g._events:
		if event["type"] == "lethal_ward":
			ward_event = event
	check(not ward_event.is_empty() and int(ward_event["src"]) == striker.uid and int(ward_event["uid"]) == ward_chamber.uid, "câmara: o evento traz a unidade que bateu e a própria câmara")
	check(int(ward_event.get("hits", 0)) == 3 and g.leader_negations_left(a) == 3, "câmara: começa com 3 camadas (evento e contador)")
	# each negated hit emits an event with the layers still standing, so the screen can break the outer shell
	for expected_left in [2, 1, 0]:
		g._events.clear()
		g._deal_damage(GameState.LEADER_UID[a], 3, striker)
		var negated_events: Array = g._events.filter(func(e): return e["type"] == "leader_hit_negated")
		check(negated_events.size() == 1 and int(negated_events[0]["left"]) == expected_left and int(negated_events[0]["src"]) == striker.uid, "câmara: o golpe anulado informa %d camada(s) restante(s)" % expected_left)
		check(g.leader_negations_left(a) == expected_left, "câmara: contador de camadas em %d" % expected_left)
	g.turn += 3
	check(g.leader_negations_left(a) == 0, "câmara: sem camadas depois que a janela termina")

	# Morwenna Raiz-Podre: +2/+2 per ally death, at most 3 times (1/3 grows to 7/9 and stops)
	g = _obscura_game()
	a = g.active
	var morwenna := _put(g, a, "morwenna_raiz_podre")
	for ally_number in 5:
		_kill(g, _put(g, a, "teste_alvo_gelo"))
		if ally_number == 0:
			check(g.atk_of(morwenna) == 3 and g.hp_left(morwenna) == 5, "morwenna: a primeira morte de aliado dá +2/+2 (3/5)")
	check(g.atk_of(morwenna) == 7 and g.hp_left(morwenna) == 9, "morwenna: depois de 5 mortes de aliados ela para em 7/9")

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

	# Mestra do Gelo Frígido: every glacial spell cast pings a random enemy unit that is already Congelada
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	var frozen_victim := _put(g, o, "teste_alvo_gelo")
	var thawed_bystander := _put(g, o, "teste_alvo_gelo")
	_put(g, a, "mestra_do_gelo_frigido")
	# nobody is frozen yet: the spell goes off and the Mestra has nothing to ping
	_cast_and_resolve(g, a, "estilhaco_gelido", thawed_bystander.uid)
	check(frozen_victim.hp_left() == 20 and thawed_bystander.hp_left() == 20 - 2, "Mestra do Gelo Frígido: sem unidade Congelada, não causa dano extra")
	frozen_victim.frozen = g.turn + 1
	_cast_and_resolve(g, a, "estilhaco_gelido", thawed_bystander.uid)
	check(frozen_victim.hp_left() == 20 - 1 and thawed_bystander.hp_left() == 20 - 2 - 2, "Mestra do Gelo Frígido: o feitiço glacial dá 1 de dano na unidade Congelada (e só nela)")
	_cast_and_resolve(g, a, "estilhaco_gelido", thawed_bystander.uid)
	check(frozen_victim.hp_left() == 20 - 2, "Mestra do Gelo Frígido: age a cada feitiço glacial, não só uma vez por turno")
	check(CardDB.card("mestra_do_gelo_frigido")["atk"] == 2 and CardDB.card("mestra_do_gelo_frigido")["hp"] == 6 and CardDB.card("mestra_do_gelo_frigido")["cost"] == 4, "Mestra do Gelo Frígido é 2/6 de custo 4")

	# Estilhaço Gélido: 2 damage, 4 when the target is already Congelada
	g = _glacial_game()
	a = g.active
	o = g.opponent(a)
	g.players[a]["momentum"] = 30
	var shard_cold := _put(g, o, "teste_alvo_gelo")
	var shard_warm := _put(g, o, "teste_alvo_gelo")
	shard_cold.frozen = g.turn + 1
	_cast_and_resolve(g, a, "estilhaco_gelido", shard_warm.uid)
	_cast_and_resolve(g, a, "estilhaco_gelido", shard_cold.uid)
	check(shard_warm.hp_left() == 20 - 2 and shard_cold.hp_left() == 20 - 4, "Estilhaço Gélido: 2 de dano, 4 se o alvo estiver Congelado (%d/%d)" % [shard_warm.hp_left(), shard_cold.hp_left()])

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
	# the search must survive the end of combat (it used to be overwritten by the return to the Main Phase)
	check(g.phase == "search", "Bruno: a busca pela Bola de Neve fica aberta depois do ataque (fase %s)" % g.phase)
	if g.phase == "search":
		g.choose_search(a, int(g.pending_search["cards"][0]["uid"]))
		g._flush()
		var bola_in_hand: Array = g.players[a]["hand"].filter(func(c: Card): return c.card_id == "bola_de_neve")
		check(bola_in_hand.size() == 1 and g.phase == "main", "Bruno: a Bola de Neve escolhida vai para a mão e o jogo volta à Fase Principal (fase %s)" % g.phase)

	# Ysvane: Ao Entrar buffs another random ally and takes a Bola de Neve back from the graveyard (banished after its next cast);
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
	# the buff always goes to ANOTHER ally (never Ysvane herself, who already has Escudo of her own)
	check(protege.shield and ysvane_card.shield and ysvane_card.hp_left() == int(CardDB.card("ysvane")["hp"]), "Ysvane: Ao Entrar dá +2 de Vida e Escudo a outra aliada, nunca a si mesma (vida da Ysvane %d)" % ysvane_card.hp_left())
	check(protege.hp_left() + ysvane_card.hp_left() == 28, "Ysvane: a outra aliada ganha +2 de Vida (vida somada %d)" % (protege.hp_left() + ysvane_card.hp_left()))
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
	check(shielded_count == 0, "Ysvane: lançar feitiço glacial não dá mais Escudo (%d)" % shielded_count)
	g.players[a]["leader_hp"] = 10
	_kill(g, ysvane_card)
	check(g.players[a]["leader_hp"] == 14, "Ysvane: Ao Morrer cura 4 do Líder (%d)" % g.players[a]["leader_hp"])

## Engine pieces of the Sagrada essence: Pacifista, Baluarte (activated death ward + Ao Morrer + put_artifact),
## opt-in overflow heal, "ao conjurar feitiço da essência" and the undraftable flag.
func _test_sagrada_engine() -> void:
	var mefi_ability: Dictionary = CardDB.leader("mefi_urdim")["ability"]
	var baluarte_data: Dictionary = CardDB.card("baluarte_santo")
	check(int(mefi_ability["cost"]) == 4, "Mefi'Urdim: Erguer o Baluarte custa 4 Momentum")
	check(baluarte_data.get("death_ward", false) and not baluarte_data.has("redirects_destroy")
		and not baluarte_data.has("activated"),
		"Baluarte: a proteção é automática, sem Ao Ativar")
	# Bênção de Ferro Batido: Armadura 2 and Roubo de Vida, both only until the end of this turn
	_tcard("t_blessing_target", 2, 4, [])
	var blessing_game := _new_game()
	_quiet(blessing_game)
	blessing_game.players[0]["momentum"] = 10
	var blessed := _put(blessing_game, 0, "t_blessing_target")
	_cast_and_resolve(blessing_game, 0, "bencao_de_ferro_batido", blessed.uid)
	check(blessed.armor_total() == 2 and blessing_game.has_kw(blessed, "roubo_de_vida"), "Bênção: Armadura 2 e Roubo de Vida neste turno")
	blessing_game._finish_turn()
	check(blessed.armor_total() == 0 and blessed.armor == 0 and not blessing_game.has_kw(blessed, "roubo_de_vida"), "Bênção: Armadura e Roubo de Vida somem no fim do turno")
	# Pacifista: the combat blow is always 0, even with a big Ataque, but it still takes the retaliation
	_tcard("t_pacifist", 5, 6, [])
	CardDB.data()["cards"]["t_pacifist"]["keywords"] = ["pacifista", "toxico"]
	_tcard("t_pacifist_target", 2, 4, [])
	var g := _new_game()
	_quiet(g)
	var pacifist := _put(g, 0, "t_pacifist")
	var leader_before: int = g.players[1]["leader_hp"]
	_hit(g, pacifist)
	check(g.players[1]["leader_hp"] == leader_before, "Pacifista: o golpe no Líder causa 0 mesmo com Ataque 5")
	g = _new_game()
	_quiet(g)
	pacifist = _put(g, 0, "t_pacifist")
	var pacifist_target := _put(g, 1, "t_pacifist_target")
	pacifist_target.exhausted = true
	_hit(g, pacifist, pacifist_target.uid)
	check(g.find_unit(pacifist_target.uid) != null and pacifist_target.damage == 0, "Pacifista: 0 de dano na unidade, e o Tóxico não dispara")
	check(pacifist.damage == 2, "Pacifista: ainda sofre o golpe de volta (%d)" % pacifist.damage)
	check(g.atk_of(pacifist) == 5, "Pacifista: o Ataque continua valendo para o resto (Intimidação, escala)")

	# Baluarte: its activated ward prevents any real unit death; its Ao Morrer heals the Leader by 3
	_tcard("t_ward_unit", 1, 5, [])
	_tcard("t_ward_immune", 1, 5, [])
	CardDB.data()["cards"]["t_ward_immune"]["keywords"] = ["indestrutivel"]
	CardDB.data()["cards"]["t_bulwark"] = {"name": "t_bulwark", "type": "artifact", "subtypes": ["local"], "rarity": "common",
		"essence": "neutra", "cost": 0, "art": "", "text": "", "flavor": "", "tags": [], "death_ward": true,
		"activated": {"cost": 2, "speed": "rapido", "effects": [{"action": "arm_death_ward", "target": "none"}]},
		"effects": [{"trigger": "on_death", "action": "heal_leader", "target": "own_leader", "amount": 3}]}
	_tspell("t_kill_ally", "lento", [{"trigger": "on_play", "action": "destroy", "target": "ally_unit"}])
	check(CardDB.is_local(CardDB.card("t_bulwark")) and CardDB.is_relic(CardDB.card("t_bulwark")), "Baluarte: artefato do subtipo local")
	g = _new_game()
	_quiet(g)
	var player: int = g.active
	var protected_unit := _put(g, player, "t_ward_unit")
	var bulwark := Card.new(g._uid(), "t_bulwark", player)
	g._place_relic(player, bulwark)
	g.players[player]["leader_hp"] = 20
	g.players[player]["momentum"] = 2
	check(g.can_activate(player, bulwark.uid), "Baluarte: Ao Ativar custa 2 e está disponível")
	g.activate(player, bulwark.uid)
	_resolve_stack(g)
	check(bulwark.death_ward_armed and g.players[player]["momentum"] == 0, "Baluarte: a ativação arma a proteção e paga 2")
	protected_unit.damage = protected_unit.hp
	g._check_state()
	check(g.find_unit(protected_unit.uid) != null and protected_unit.hp_left() == 1, "Baluarte: a próxima morte por dano é negada")
	check(g.find_relic(bulwark.uid) == null, "Baluarte: é destruído depois de negar a morte")
	check(g.players[player]["leader_hp"] == 23, "Baluarte: Ao Morrer cura 3 do Líder (%d)" % g.players[player]["leader_hp"])
	_cast_and_resolve(g, player, "t_kill_ally", protected_unit.uid)
	check(g.find_unit(protected_unit.uid) == null, "Baluarte: depois de consumido, a unidade morre normalmente")
	# The real Baluarte Santo has no Ao Ativar: it guards on its own, with no activation or Momentum
	g = _new_game()
	_quiet(g)
	player = g.active
	protected_unit = _put(g, player, "t_ward_unit")
	bulwark = Card.new(g._uid(), "baluarte_santo", player)
	g._place_relic(player, bulwark)
	_cast_and_resolve(g, player, "t_kill_ally", protected_unit.uid)
	check(g.find_relic(bulwark.uid) == null and g.find_unit(protected_unit.uid) != null, "Baluarte: protege sozinho, sem ativação")
	# Indestrutível survives destruction without spending an armed Baluarte.
	g = _new_game()
	_quiet(g)
	player = g.active
	var immune_unit := _put(g, player, "t_ward_immune")
	bulwark = Card.new(g._uid(), "t_bulwark", player)
	g._place_relic(player, bulwark)
	g.players[player]["momentum"] = 2
	g.activate(player, bulwark.uid)
	_resolve_stack(g)
	_cast_and_resolve(g, player, "t_kill_ally", immune_unit.uid)
	check(g.find_relic(bulwark.uid) != null and bulwark.death_ward_armed and g.find_unit(immune_unit.uid) != null, "Baluarte: não gasta com unidade Indestrutível")
	# Banimento também bypasses the death ward and leaves it armed for a later death.
	var banished_unit := _put(g, player, "t_ward_unit")
	g.banish_unit(banished_unit)
	check(g.find_relic(bulwark.uid) != null and bulwark.death_ward_armed, "Baluarte: banimento não consome a proteção")

	# put_artifact through a Lenta Leader ability: unique, needs a free slot, never charges for a no-op
	CardDB.data()["leaders"]["t_leader"] = {"name": "t_leader", "hp": 30, "art": "", "incarnation": "ronan", "essences": ["neutra"],
		"ability": {"name": "Erguer", "cost": 3, "speed": "lento", "text": "",
			"effects": [{"action": "put_artifact", "target": "none", "card": "t_bulwark", "unique": true}]}}
	g = _new_game()
	_quiet(g)
	player = g.active
	g.players[player]["leader_id"] = "t_leader"
	g.players[player]["ability_used"] = false
	g.players[player]["momentum"] = 8
	check(g.can_use_ability(player), "Erguer o Baluarte: disponível com o campo livre")
	g.use_ability(player)
	_resolve_stack(g)
	check(g.players[player]["relics"].size() == 1 and g.players[player]["relics"][0].card_id == "t_bulwark", "Erguer o Baluarte: o artefato entra no campo")
	check(int(g.players[player]["momentum"]) == 5, "Erguer o Baluarte: custo 3")
	g.players[player]["ability_used"] = false
	check(not g.can_use_ability(player), "Erguer o Baluarte: bloqueado enquanto já existe um em campo (unique)")
	g.destroy_relic(g.players[player]["relics"][0])
	g._flush()
	check(g.can_use_ability(player), "Erguer o Baluarte: pode erguer de novo quando não há nenhum")

	# lockout_turns: after a Baluarte falls (own turn X, opponent's X+1 or the next own turn X+2) no new one until a clean own turn
	CardDB.data()["leaders"]["t_leader"]["ability"]["effects"][0]["lockout_turns"] = 2
	g = _new_game()
	_quiet(g)
	player = g.active
	g.players[player]["leader_id"] = "t_leader"
	g.players[player]["momentum"] = 8
	var fall_turn: int = g.turn
	g._place_relic(player, Card.new(g._uid(), "t_bulwark", player))
	g.destroy_relic(g.players[player]["relics"][0])
	g._flush()
	check(not g.can_use_ability(player), "Erguer o Baluarte: caiu neste turno, bloqueado")
	g.turn = fall_turn + 1
	check(g.relic_fell_within(player, "t_bulwark", 2), "Erguer o Baluarte: caiu no turno X, ainda bloqueado em X+1")
	g.turn = fall_turn + 2
	check(not g.can_use_ability(player), "Erguer o Baluarte: caiu no turno X, bloqueado em X+2")
	g.turn = fall_turn + 4
	check(g.can_use_ability(player), "Erguer o Baluarte: depois de um turno seu sem queda, libera de novo")
	g.turn = fall_turn + 5 # an opponent's turn: the fall happens there
	g._place_relic(player, Card.new(g._uid(), "t_bulwark", player))
	g.destroy_relic(g.players[player]["relics"][0])
	g._flush()
	g.turn += 1
	check(not g.can_use_ability(player), "Erguer o Baluarte: caiu no turno do oponente, bloqueado no turno seguinte do dono")
	g.turn += 2
	check(g.can_use_ability(player), "Erguer o Baluarte: a queda no turno do oponente não bloqueia o turno seguinte limpo")
	check(not g.relic_fell_within(1 - player, "t_bulwark", 2), "Erguer o Baluarte: a trava é de quem perdeu o Baluarte, não do oponente")
	# overflow heal is opt-in: without "overflow_max_hp" nothing grows, with it the surplus becomes maximum Vida
	_tspell("t_heal_plain", "lento", [{"trigger": "on_play", "action": "heal_unit", "target": "ally_or_own_leader", "amount": 3}])
	_tspell("t_heal_overflow", "lento", [{"trigger": "on_play", "action": "heal_unit", "target": "ally_or_own_leader", "amount": 3, "overflow_max_hp": 1}])
	g = _new_game()
	_quiet(g)
	player = g.active
	var healed_unit := _put(g, player, "t_ward_unit")
	var max_before: int = g.players[player]["leader_max"]
	g.players[player]["leader_hp"] = max_before
	_cast_and_resolve(g, player, "t_heal_plain", GameState.LEADER_UID[player])
	check(g.players[player]["leader_max"] == max_before, "cura sem overflow_max_hp: o Líder cheio não ganha Vida máxima")
	_cast_and_resolve(g, player, "t_heal_plain", healed_unit.uid)
	check(healed_unit.hp == 5, "cura sem overflow_max_hp: a unidade cheia não ganha Vida máxima")
	_cast_and_resolve(g, player, "t_heal_overflow", GameState.LEADER_UID[player])
	check(g.players[player]["leader_max"] == max_before + 1 and g.players[player]["leader_hp"] == max_before + 1, "overflow_max_hp: a cura que passa do máximo dá +1 Vida máxima ao Líder")
	healed_unit.damage = 1
	_cast_and_resolve(g, player, "t_heal_overflow", healed_unit.uid)
	check(healed_unit.hp == 6 and healed_unit.damage == 0, "overflow_max_hp: a unidade curada além do que faltava ganha +1 Vida máxima")
	healed_unit.damage = 3
	_cast_and_resolve(g, player, "t_heal_overflow", healed_unit.uid)
	check(healed_unit.hp == 6 and healed_unit.damage == 0, "overflow_max_hp: cura exata não passa do máximo, sem bônus")

	# "ao conjurar feitiço da essência": spell_cast carries essence_<id>, so a listener can filter on it
	_tcard("t_caster_fan", 1, 5, [{"listen": "spell_cast", "scope": "ally", "when": {"essence_glacial": true},
		"action": "buff", "target": "self", "atk": 1}])
	CardDB.data()["cards"]["t_glacial_spell"] = {"name": "t_glacial_spell", "type": "spell", "rarity": "common", "essence": "glacial",
		"cost": 0, "speed": "lento", "art": "", "effects": [], "text": "", "flavor": "", "tags": []}
	_tspell("t_neutral_spell", "lento", [])
	g = _new_game()
	_quiet(g)
	player = g.active
	var fan := _put(g, player, "t_caster_fan")
	_cast_and_resolve(g, player, "t_neutral_spell")
	check(g.atk_of(fan) == 1, "listen spell_cast: feitiço de outra essência não dispara")
	_cast_and_resolve(g, player, "t_glacial_spell")
	check(g.atk_of(fan) == 2, "listen spell_cast: feitiço da essência certa dá +1 Ataque (%d)" % g.atk_of(fan))

	# undraftable: the deck check refuses a card flagged in the JSON
	var base_deck: Dictionary = DeckDB.get_deck(DeckDB.ids()[0])
	var undraftable_cards: Dictionary = base_deck["cards"].duplicate()
	CardDB.data()["cards"]["t_undraftable"] = {"name": "t_undraftable", "type": "artifact", "rarity": "common", "essence": "neutra",
		"cost": 0, "art": "", "text": "", "flavor": "", "tags": [], "effects": [], "undraftable": true}
	undraftable_cards["t_undraftable"] = 1
	var undraftable_errors := DeckDB.validate_cards(base_deck["leader"], undraftable_cards)
	check(undraftable_errors.any(func(e: String): return e.begins_with("t_undraftable:")), "undraftable: o deck com a carta é recusado")

	# species_aura: the OTHER allied units sharing a listed species get Ataque/Vida/Armadura while the source is in play
	_tcard("t_aura_source", 1, 5, [{"trigger": "constante", "action": "species_aura", "species": ["divindade", "celestial", "anjo"],
		"atk": 1, "hp": 1, "armor": 1}])
	CardDB.data()["cards"]["t_aura_source"]["species"] = ["humano"]
	_tcard("t_aura_angel", 2, 4, [])
	CardDB.data()["cards"]["t_aura_angel"]["species"] = ["anjo"]
	_tcard("t_aura_two_species", 2, 4, [])
	CardDB.data()["cards"]["t_aura_two_species"]["species"] = ["divindade", "celestial"]
	_tcard("t_aura_human", 2, 4, [])
	CardDB.data()["cards"]["t_aura_human"]["species"] = ["humano"]
	g = _new_game()
	_quiet(g)
	var angel := _put(g, 0, "t_aura_angel")
	check(g.atk_of(angel) == 2, "species_aura: sem a fonte em campo não há bônus")
	var aura_source := _put(g, 0, "t_aura_source")
	var two_species := _put(g, 0, "t_aura_two_species")
	var aura_human := _put(g, 0, "t_aura_human")
	var enemy_angel := _put(g, 1, "t_aura_angel")
	g._move_dead_units()
	check(g.atk_of(angel) == 3 and g.hp_left(angel) == 5 and g.armor_of(angel) == 1, "species_aura: Anjo ganha +1/+1 e Armadura 1 (%d/%d, arm %d)" % [g.atk_of(angel), g.hp_left(angel), g.armor_of(angel)])
	check(g.atk_of(two_species) == 3 and g.armor_of(two_species) == 1, "species_aura: duas espécies na lista dão o bônus uma vez só")
	check(g.atk_of(aura_human) == 2 and g.armor_of(aura_human) == 0, "species_aura: espécie fora da lista não ganha")
	check(g.atk_of(aura_source) == 1 and g.armor_of(aura_source) == 0, "species_aura: a própria fonte não se beneficia")
	check(g.atk_of(enemy_angel) == 2 and g.armor_of(enemy_angel) == 0, "species_aura: unidades do oponente não ganham")
	g.players[0]["board"].erase(aura_source)
	g._move_dead_units()
	check(g.atk_of(angel) == 2 and g.armor_of(angel) == 0, "species_aura: o bônus some quando a fonte sai de campo")

	# species_aura with "include_self": the source benefits from its own aura too (Mefi'Urdim)
	_tcard("t_aura_self_source", 1, 5, [{"trigger": "constante", "action": "species_aura", "species": ["celestial"],
		"include_self": true, "atk": 1, "hp": 1}])
	CardDB.data()["cards"]["t_aura_self_source"]["species"] = ["celestial"]
	g = _new_game()
	_quiet(g)
	var self_source := _put(g, 0, "t_aura_self_source")
	g._move_dead_units()
	check(g.atk_of(self_source) == 2 and g.hp_left(self_source) == 6, "species_aura include_self: a fonte ganha +1/+1 (%d/%d)" % [g.atk_of(self_source), g.hp_left(self_source)])

	# buff "only_species": units of other species are left untouched
	_tcard("t_only_species_buff", 1, 5, [{"trigger": "on_enter", "action": "buff", "target": "all_ally_units",
		"only_species": ["anjo"], "keywords": ["escudo_feitico"]}])
	g = _new_game()
	_quiet(g)
	var only_angel := _put(g, 0, "t_aura_angel")
	var only_human := _put(g, 0, "t_aura_human")
	_put(g, 0, "t_only_species_buff")
	check(only_angel.spell_shield and not only_human.spell_shield, "buff only_species: só a espécie listada ganha o Escudo de Feitiço")

	# Mefi'Urdim: Ao Entrar heals 10, raises the Baluarte Santo, gives Escudo de Feitiço to his tribe; Constante +1/+1 to the tribe and himself
	g = _new_game()
	_quiet(g)
	g.players[0]["leader_hp"] = 15
	var mefi_angel := _put(g, 0, "uriel")
	var mefi_human := _put(g, 0, "t_aura_human")
	var mefi := _put(g, 0, "mefi_urdim")
	g._move_dead_units()
	check(g.players[0]["leader_hp"] == 25, "Mefi'Urdim: Ao Entrar cura 10 do Líder (%d)" % g.players[0]["leader_hp"])
	check(g.players[0]["relics"].any(func(relic: Card): return relic.card_id == "baluarte_santo"), "Mefi'Urdim: Ao Entrar invoca o Baluarte Santo")
	check(mefi_angel.spell_shield and mefi.spell_shield and not mefi_human.spell_shield, "Mefi'Urdim: Escudo de Feitiço na tribo, incluindo ele, e em mais ninguém")
	check(g.atk_of(mefi) == 6 and g.hp_left(mefi) == 11, "Mefi'Urdim: ele mesmo ganha +1/+1 da própria aura (%d/%d)" % [g.atk_of(mefi), g.hp_left(mefi)])
	check(g.atk_of(mefi_angel) == 6 and g.atk_of(mefi_human) == 2, "Mefi'Urdim: o Anjo ganha +1 de Ataque e o humano nada (%d / %d)" % [g.atk_of(mefi_angel), g.atk_of(mefi_human)])

	# Vidal: heals every allied unit fully, purifies them and the Leader, then grants other allies +3/+3.
	_tcard("t_vidal_ally", 2, 5, [])
	g = _new_game()
	_quiet(g)
	g.players[0]["leader_hp"] = 10
	g.players[0]["leader_dots"] = {"veneno": 2, "queimadura": 1}
	var vidal_ally := _put(g, 0, "t_vidal_ally")
	vidal_ally.damage = 3
	vidal_ally.dot_markers = {"veneno": 2, "sangramento": 1}
	var vidal_ally_two := _put(g, 0, "t_vidal_ally")
	var vidal_ally_three := _put(g, 0, "t_vidal_ally")
	g.players[0]["momentum"] = 10
	var vidal_uid := _give(g, 0, "vidal")
	g.play_card(0, vidal_uid)
	var vidal := g.find_unit(vidal_uid)
	check(g.phase == "enter_target", "Vidal: Ao Entrar pede o primeiro alvo")
	check(not g.valid_targets(0, "other_ally_unit", vidal.uid).has(vidal.uid), "Vidal: ele mesmo não é alvo válido")
	g.choose_enter_target(0, vidal_ally.uid)
	check(g.phase == "enter_target", "Vidal: depois do primeiro alvo pede o segundo")
	g.choose_enter_target(0, vidal_ally.uid)
	check(g.phase == "enter_target", "Vidal: não deixa repetir o mesmo alvo")
	g.choose_enter_target(0, vidal_ally_three.uid)
	g._flush()
	g._move_dead_units()
	check(int(CardDB.card("vidal")["cost"]) == 8, "Vidal: custo 8")
	check(vidal_ally.damage == 0 and vidal_ally.dot_markers.is_empty(), "Vidal: cura e purifica totalmente as unidades aliadas")
	check(g.players[0]["leader_hp"] == 10 and g.leader_dot_markers(0, "veneno") == 0 and g.leader_dot_markers(0, "queimadura") == 0, "Vidal: purifica o Líder sem alterar sua Vida")
	check(g.atk_of(vidal_ally) == 5 and g.hp_left(vidal_ally) == 8 and g.atk_of(vidal_ally_three) == 5 and g.hp_left(vidal_ally_three) == 8, "Vidal: os dois alvos escolhidos ganham +3/+3 permanentes")
	check(g.atk_of(vidal_ally_two) == 2 and g.hp_left(vidal_ally_two) == 5 and g.atk_of(vidal) == 0 and g.hp_left(vidal) == 7, "Vidal: a terceira unidade e ele mesmo não ganham nada")

	# Arcanjo Uriel: grows by 1 Ataque every time his Leader is healed
	g = _new_game()
	_quiet(g)
	g.players[0]["leader_hp"] = 10
	var archangel := _put(g, 0, "uriel")
	var attack_before := g.atk_of(archangel)
	g._heal_leader(0, 3)
	g._check_state()
	check(g.atk_of(archangel) == attack_before + 1, "Uriel: cura do Líder dá +1 de Ataque (%d -> %d)" % [attack_before, g.atk_of(archangel)])

	# graveyard_armor: +1 Armadura per spell of the essence in the owner's graveyard (damage never below 1)
	_tcard("t_grave_armor", 1, 20, [{"trigger": "constante", "action": "graveyard_armor", "essence": "sagrada", "card_type": "spell"}])
	_tspell("t_sagrada_spell", "lento", [])
	CardDB.data()["cards"]["t_sagrada_spell"]["essence"] = "sagrada"
	_tspell("t_neutral_spell", "lento", [])
	g = _new_game()
	_quiet(g)
	var graveyard_unit := _put(g, 0, "t_grave_armor")
	check(g.armor_of(graveyard_unit) == 0, "graveyard_armor: cemitério sem feitiços Sagrados, Armadura 0")
	g.players[0]["graveyard"].append(Card.new(g._uid(), "t_neutral_spell", 0, "graveyard"))
	check(g.armor_of(graveyard_unit) == 0, "graveyard_armor: feitiço de outra essência não conta")
	for i in 3:
		g.players[0]["graveyard"].append(Card.new(g._uid(), "t_sagrada_spell", 0, "graveyard"))
	check(g.armor_of(graveyard_unit) == 3, "graveyard_armor: 3 feitiços Sagrados, Armadura 3 (%d)" % g.armor_of(graveyard_unit))
	g._deal_damage(graveyard_unit.uid, 5, null)
	check(graveyard_unit.damage == 2, "graveyard_armor: dano 5 vira 2 (%d)" % graveyard_unit.damage)
	for i in 8:
		g.players[0]["graveyard"].append(Card.new(g._uid(), "t_sagrada_spell", 0, "graveyard"))
	graveyard_unit.damage = 0
	g._deal_damage(graveyard_unit.uid, 5, null)
	check(graveyard_unit.damage == 1, "graveyard_armor: nunca reduz o dano a menos de 1 (%d)" % graveyard_unit.damage)

	# Nerithia: a partir de 2 feitiços Sagrados, reduz dano para ceil(dano / 2) - 1, sem piso de 1
	g = _new_game()
	_quiet(g)
	var nerithia := _put(g, 0, "nerithia")
	check(g.damage_after_armor(nerithia, 5) == 5, "Nerithia: sem feitiços Sagrados, dano normal")
	g.players[0]["graveyard"].append(Card.new(g._uid(), "t_sagrada_spell", 0, "graveyard"))
	check(g.damage_after_armor(nerithia, 5) == 5, "Nerithia: 1 feitiço Sagrado ainda não ativa a redução")
	g.players[0]["graveyard"].append(Card.new(g._uid(), "t_sagrada_spell", 0, "graveyard"))
	check(g._deal_damage(nerithia.uid, 1, null) == 0 and nerithia.damage == 0, "Nerithia: dano leve pode virar 0")
	check(g.damage_after_armor(nerithia, 5) == 2, "Nerithia: metade de dano ímpar arredonda para cima e reduz 1")
	g._deal_damage(nerithia.uid, 10, null)
	check(nerithia.damage == 4, "Nerithia: dano alto usa ceil(10 / 2) - 1 (%d)" % nerithia.damage)

	# Imunidade contra Obscura: combat damage and AIMED effects of enemy Obscura cards do nothing; area effects still hit
	_tcard("t_immune_obscura", 1, 10, [])
	CardDB.data()["cards"]["t_immune_obscura"]["keywords"] = ["imunidade_obscura"]
	_tcard("t_dark_attacker", 3, 6, [])
	CardDB.data()["cards"]["t_dark_attacker"]["essence"] = "obscura"
	_tcard("t_plain_attacker", 3, 6, [])
	_tspell("t_plain_bolt", "lento", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 3}])
	_tspell("t_dark_bolt", "lento", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 3}])
	CardDB.data()["cards"]["t_dark_bolt"]["essence"] = "obscura"
	_tspell("t_dark_blast", "lento", [{"trigger": "on_play", "action": "damage", "target": "all_enemy_units", "amount": 3}])
	CardDB.data()["cards"]["t_dark_blast"]["essence"] = "obscura"
	# combat: a fresh game per attacker (a unit that attacked leaves the main phase)
	g = _new_game()
	_quiet(g)
	var attacker_side: int = g.active
	var immune_unit_obscura := _put(g, g.opponent(attacker_side), "t_immune_obscura")
	immune_unit_obscura.exhausted = true # only an exhausted unit can be challenged
	_hit(g, _put(g, attacker_side, "t_dark_attacker"), immune_unit_obscura.uid)
	_pass_windows(g)
	check(immune_unit_obscura.damage == 0, "Imunidade contra Obscura: golpe de unidade Obscura causa 0 (%d)" % immune_unit_obscura.damage)
	g = _new_game()
	_quiet(g)
	attacker_side = g.active
	immune_unit_obscura = _put(g, g.opponent(attacker_side), "t_immune_obscura")
	immune_unit_obscura.exhausted = true
	_hit(g, _put(g, attacker_side, "t_plain_attacker"), immune_unit_obscura.uid)
	_pass_windows(g)
	check(immune_unit_obscura.damage == 3, "Imunidade contra Obscura: unidade de outra essência causa dano normal (%d)" % immune_unit_obscura.damage)
	# spells: aimed ones are ignored, area ones still hit
	g = _new_game()
	_quiet(g)
	attacker_side = g.active
	immune_unit_obscura = _put(g, g.opponent(attacker_side), "t_immune_obscura")
	_cast_and_resolve(g, attacker_side, "t_dark_bolt", immune_unit_obscura.uid)
	check(immune_unit_obscura.damage == 0, "Imunidade contra Obscura: feitiço Obscuro mirado é ignorado (%d)" % immune_unit_obscura.damage)
	_cast_and_resolve(g, attacker_side, "t_plain_bolt", immune_unit_obscura.uid)
	check(immune_unit_obscura.damage == 3, "Imunidade contra Obscura: feitiço de outra essência mirado funciona (%d)" % immune_unit_obscura.damage)
	immune_unit_obscura.damage = 0
	_cast_and_resolve(g, attacker_side, "t_dark_blast")
	check(immune_unit_obscura.damage == 3, "Imunidade contra Obscura: efeito em área Obscuro ainda atinge (%d)" % immune_unit_obscura.damage)
	# The immunity is generic: each essence has its own keyword "imunidade_<essência>" and only blocks that essence
	CardDB.data()["cards"]["t_immune_ignea"] = CardDB.data()["cards"]["t_immune_obscura"].duplicate(true)
	CardDB.data()["cards"]["t_immune_ignea"]["keywords"] = ["imunidade_ignea"]
	g = _new_game()
	_quiet(g)
	attacker_side = g.active
	var immune_unit_ignea := _put(g, g.opponent(attacker_side), "t_immune_ignea")
	_cast_and_resolve(g, attacker_side, "t_dark_bolt", immune_unit_ignea.uid)
	check(immune_unit_ignea.damage == 3, "Imunidade contra Ígnea não protege de feitiço Obscuro (%d)" % immune_unit_ignea.damage)
	CardDB.data()["cards"]["t_dark_bolt"]["essence"] = "ignea"
	immune_unit_ignea.damage = 0
	_cast_and_resolve(g, attacker_side, "t_dark_bolt", immune_unit_ignea.uid)
	check(immune_unit_ignea.damage == 0, "Imunidade contra Ígnea ignora feitiço Ígneo mirado (%d)" % immune_unit_ignea.damage)

	# return_to_hand: general bounce. Not a death (no Ao Morrer), tokens vanish, cost_increase is optional and accumulates
	_tcard("t_bounce_unit", 1, 5, [{"trigger": "on_death", "action": "damage", "target": "enemy_leader", "amount": 5}])
	_tspell("t_bounce_ally", "lento", [{"trigger": "on_play", "action": "return_to_hand", "target": "ally_unit"}])
	_tspell("t_bounce_enemy", "lento", [{"trigger": "on_play", "action": "return_to_hand", "target": "enemy_unit", "cost_increase": 2}])
	g = _new_game()
	_quiet(g)
	player = g.active
	var enemy_side: int = g.opponent(player)
	var enemy_leader_hp: int = g.players[enemy_side]["leader_hp"]
	var bounced_unit := _put(g, player, "t_bounce_unit")
	_cast_and_resolve(g, player, "t_bounce_ally", bounced_unit.uid)
	check(g.find_unit(bounced_unit.uid) == null and g.players[player]["hand"].has(bounced_unit), "return_to_hand: a unidade sai do campo e vai para a mão")
	check(bounced_unit.cost_mod == 0 and bounced_unit.zone == "hand", "return_to_hand: sem cost_increase o custo não muda")
	check(g.players[enemy_side]["leader_hp"] == enemy_leader_hp, "return_to_hand: não é morte, o Ao Morrer não dispara")
	check(not g.players[player]["graveyard"].has(bounced_unit), "return_to_hand: não passa pelo cemitério")
	var enemy_bounced := _put(g, enemy_side, "t_bounce_unit")
	_cast_and_resolve(g, player, "t_bounce_enemy", enemy_bounced.uid)
	check(g.players[enemy_side]["hand"].has(enemy_bounced) and enemy_bounced.cost_mod == 2, "return_to_hand: a unidade inimiga volta para a mão do DONO, com cost_increase 2")
	# a token has no card to put in the hand: it just vanishes
	CardDB.data()["cards"]["t_bounce_token"] = CardDB.data()["cards"]["t_bounce_unit"].duplicate(true)
	CardDB.data()["cards"]["t_bounce_token"]["token"] = true
	var token_unit := _put(g, player, "t_bounce_token")
	var hand_before: int = g.players[player]["hand"].size()
	_cast_and_resolve(g, player, "t_bounce_ally", token_unit.uid)
	check(g.find_unit(token_unit.uid) == null and g.players[player]["hand"].size() == hand_before, "return_to_hand: a ficha some, não vira carta na mão")

	# Ao Morrer + self_card + cost_increase: comes back from the graveyard, one more expensive each time, with no cap
	_tcard("t_resilient", 2, 4, [{"trigger": "on_death", "action": "return_to_hand", "target": "self_card", "cost_increase": 1}])
	g = _new_game()
	_quiet(g)
	player = g.active
	var resilient := _put(g, player, "t_resilient")
	for round_number in range(1, 4):
		g._deal_damage(resilient.uid, 99, null)
		g._check_state() # moves the dead unit out and resolves its Ao Morrer
		check(g.players[player]["hand"].has(resilient) and not g.players[player]["graveyard"].has(resilient), "return_to_hand (Ao Morrer): volta do cemitério para a mão (volta %d)" % round_number)
		check(resilient.cost_mod == round_number, "return_to_hand: o custo sobe 1 por volta, sem teto (%d)" % resilient.cost_mod)
		g.players[player]["hand"].erase(resilient)
		g._summon(player, resilient, false, 0)
		g._flush()
		resilient.sick = false

	# copy_atk "highest_ally": the Ataque rises to the strongest OTHER ally; never lowers; "temp" ends with the turn
	_tcard("t_copycat", 1, 9, [])
	_tcard("t_strong_ally", 4, 9, [])
	_tcard("t_weak_ally", 2, 9, [])
	_tspell("t_copy_spell", "lento", [{"trigger": "on_play", "action": "buff", "target": "ally_unit", "copy_atk": "highest_ally", "temp": true}])
	g = _new_game()
	_quiet(g)
	player = g.active
	var copycat := _put(g, player, "t_copycat")
	var strong_ally := _put(g, player, "t_strong_ally")
	_put(g, player, "t_weak_ally")
	_cast_and_resolve(g, player, "t_copy_spell", copycat.uid)
	check(g.atk_of(copycat) == 4, "copy_atk: copia o Ataque da aliada mais forte (%d)" % g.atk_of(copycat))
	_cast_and_resolve(g, player, "t_copy_spell", strong_ally.uid)
	check(g.atk_of(strong_ally) == 4, "copy_atk: quem já tem o maior Ataque não ganha nada (%d)" % g.atk_of(strong_ally))
	g.end_turn(player)
	check(g.atk_of(copycat) == 1, "copy_atk com temp: o Ataque copiado acaba no fim do turno (%d)" % g.atk_of(copycat))
	# Ao Desafiar integration: the strike goes out with the copied Ataque
	_tcard("t_challenger", 1, 9, [{"trigger": "on_challenge", "action": "buff", "target": "self", "copy_atk": "highest_ally", "temp": true}])
	_tcard("t_challenged_target", 0, 20, [])
	g = _new_game()
	_quiet(g)
	attacker_side = g.active
	var challenger := _put(g, attacker_side, "t_challenger")
	_put(g, attacker_side, "t_strong_ally")
	var challenged := _put(g, g.opponent(attacker_side), "t_challenged_target")
	challenged.exhausted = true
	_hit(g, challenger, challenged.uid)
	_pass_windows(g)
	check(challenged.damage == 4, "copy_atk (Ao Desafiar): o golpe sai com o Ataque copiado (%d)" % challenged.damage)

	# bonus_if_species: extra permanent Ataque/Vida only when the target has one of the listed species
	_tcard("t_species_angel", 1, 3, [])
	CardDB.data()["cards"]["t_species_angel"]["species"] = ["anjo"]
	_tcard("t_species_human", 1, 3, [])
	CardDB.data()["cards"]["t_species_human"]["species"] = ["humano"]
	_tspell("t_species_buff", "lento", [{"trigger": "on_play", "action": "buff", "target": "ally_unit", "atk": 1, "hp": 1,
		"bonus_if_species": {"species": ["divindade", "celestial", "anjo"], "atk": 1, "hp": 1}}])
	g = _new_game()
	_quiet(g)
	player = g.active
	var species_angel := _put(g, player, "t_species_angel")
	var species_human := _put(g, player, "t_species_human")
	_cast_and_resolve(g, player, "t_species_buff", species_angel.uid)
	_cast_and_resolve(g, player, "t_species_buff", species_human.uid)
	check(g.atk_of(species_angel) == 3 and g.hp_left(species_angel) == 5, "bonus_if_species: Anjo ganha +1/+1 e o extra +1/+1 (%d/%d)" % [g.atk_of(species_angel), g.hp_left(species_angel)])
	check(g.atk_of(species_human) == 2 and g.hp_left(species_human) == 4, "bonus_if_species: Humano só ganha o bônus base (%d/%d)" % [g.atk_of(species_human), g.hp_left(species_human)])

	# counter with only_if_destroys: Intercessão can only be aimed at an item that destroys or banishes units
	_tspell("t_kill_spell", "lento", [{"trigger": "on_play", "action": "destroy", "target": "enemy_unit"}])
	_tspell("t_bolt_spell", "lento", [{"trigger": "on_play", "action": "damage", "target": "enemy_unit", "amount": 1}])
	_tspell("t_counter_destroy", "instantaneo", [{"trigger": "on_play", "action": "counter", "target": "enemy_stack",
		"only_if_targets_ally": true, "only_if_destroys": true}])
	g = _new_game()
	_quiet(g)
	attacker_side = g.active
	var defender_side: int = g.opponent(attacker_side)
	var defended_unit := _put(g, defender_side, "t_species_human")
	_give(g, defender_side, "t_counter_destroy") # holding a response keeps the spell waiting on the stack
	g.play_card(attacker_side, _give(g, attacker_side, "t_bolt_spell"), defended_unit.uid)
	check(g.stack.is_empty() and defended_unit.damage == 1, "only_if_destroys: sem alvo possível para o contra-feitiço, o dano resolve direto (%d)" % defended_unit.damage)
	check(g.card_targets(defender_side, CardDB.card("t_counter_destroy")).is_empty(), "only_if_destroys: não dá para anular um feitiço de dano")
	g = _new_game()
	_quiet(g)
	attacker_side = g.active
	defender_side = g.opponent(attacker_side)
	defended_unit = _put(g, defender_side, "t_species_human")
	_give(g, defender_side, "t_counter_destroy")
	g.play_card(attacker_side, _give(g, attacker_side, "t_kill_spell"), defended_unit.uid)
	check(g.stack.size() == 1, "only_if_destroys: o feitiço de destruição espera na pilha")
	check(g.card_targets(defender_side, CardDB.card("t_counter_destroy")).size() == 1, "only_if_destroys: um feitiço que destrói a unidade aliada pode ser anulado")

## Santa Maria Helena: 0/6 for five, periodic Leader healing, and one first-hit reduction per turn.
## Jack (Attack per leftover Momentum), Kai (Queimadura on any combat damage he deals) and Isarelis (executes a weak enemy).
## Momentum above the normal cap of 10 (Eryon's deck): a temporary overflow, the "momentum_surge" static
## effect that wakes up with it, and "auto_attack" (an extra attack at a random target).
func _test_momentum_overflow() -> void:
	var surge_condition := {"compare": {"stat": "momentum", "op": ">=", "value": 11}}
	_tcard("t_surge_baron", 5, 7, [
		{"trigger": "constante", "action": "momentum_surge", "min_momentum": 11, "atk": 15,
			"keywords": ["escudo", "sobrepujanca", "impeto"], "critico": 4},
		{"trigger": "before_attack", "action": "auto_attack", "target": "none", "if": surge_condition}])

	# gaining: a plain gain never lowers an overflowing pool, an overflow gain stops at the overflow cap
	var g := _new_game()
	var a := g.active
	g.players[a]["momentum"] = 9
	g.gain_momentum(a, 3, true)
	check(g.players[a]["momentum"] == 12, "overflow: 9 + 3 com overflow chega a 12")
	g.gain_momentum(a, 2)
	check(g.players[a]["momentum"] == 12, "overflow: ganho comum não derruba nem sobe acima do teto 10")
	g.gain_momentum(a, 50, true)
	check(g.players[a]["momentum"] == GameState.MOMENTUM_OVERFLOW_CAP, "overflow: nunca passa do teto temporário")

	# spending: only neutral cards (and leader abilities) see the part above 10
	g.players[a]["momentum"] = 13
	var neutral_data := CardDB.card("t_surge_baron")
	var other_essence_data := CardDB.card("jack")
	check(g.budget(a, false, neutral_data) == 13, "overflow: carta neutra enxerga os 13")
	check(g.budget(a, false, other_essence_data) == GameState.MOMENTUM_CAP, "overflow: carta de outra essência enxerga só 10")
	check(g.budget(a, true) == 13, "overflow: habilidade de Líder enxerga os 13")

	# the excess vanishes at the end of the owner's turn
	g.end_turn(a)
	check(g.players[a]["momentum"] == GameState.MOMENTUM_CAP, "overflow: o que passa de 10 some no fim do turno")

	# the surge: off at 10, on at 11, off again when the Momentum is spent
	g = _new_game()
	_quiet(g)
	a = g.active
	var baron := _put(g, a, "t_surge_baron")
	g.players[a]["momentum"] = 10
	g._refresh_scaling()
	check(g.atk_of(baron) == 5 and not g.has_kw(baron, "sobrepujanca") and baron.critico_total() == 0, "surto: com 10 de Momentum o Barão é comum")
	g.gain_momentum(a, 1, true)
	check(g.atk_of(baron) == 20 and g.has_kw(baron, "sobrepujanca") and g.has_kw(baron, "impeto") and baron.critico_total() == 4, "surto: com 11 vira +15 Ataque, Sobrepujança, Ímpeto e Crítico 4")
	check(baron.shield and g.has_kw(baron, "escudo"), "surto: ao ligar, o Barão ganha Escudo")
	var restored := Card.from_dict(baron.to_dict(), "board", a)
	check(restored.surge_keywords == baron.surge_keywords and restored.surge_critico == 4, "surto: sobrevive ao salvar e carregar")
	check(restored.surge_active and restored.shield, "surto: o estado ligado e o Escudo sobrevivem ao salvar e carregar")
	check(not baron.surge_keywords.has("escudo"), "surto: Escudo não vira palavra-chave fixa, é concedido uma vez")
	# the Escudo is spent by the first damage and is NOT granted again while the surge stays on
	baron.shield = false
	g._refresh_scaling()
	check(not baron.shield, "surto: Escudo gasto não volta a cada atualização enquanto o surto continua")
	# only after the surge goes off and on again is the Escudo granted again
	g.players[a]["momentum"] = 10
	g._refresh_scaling()
	check(not baron.surge_active and not baron.shield, "surto: desligado, sem Escudo")
	g.gain_momentum(a, 1, true)
	check(baron.shield, "surto: ligar de novo concede um novo Escudo")
	g.players[a]["momentum"] = 10
	g._refresh_scaling()
	baron.shield = false
	g.players[a]["momentum"] = 10
	g._refresh_scaling()
	check(g.atk_of(baron) == 5 and not g.has_kw(baron, "impeto"), "surto: volta ao normal quando o Momentum cai para 10")

	# auto_attack: with the surge on the Barão hits twice (the second blow ends a Leader at 3 life)
	g = _new_game()
	_quiet(g)
	a = g.active
	var enemy: int = g.opponent(a)
	baron = _put(g, a, "t_surge_baron")
	g.players[a]["momentum"] = 11
	g._refresh_scaling()
	g.players[enemy]["leader_hp"] = 30
	_hit(g, baron)
	check(baron.attacks_made == 2, "auto_attack: o Barão atacou duas vezes")
	check(g.players[enemy]["leader_hp"] <= 0 or g.phase == "over", "auto_attack: duas pancadas de 20 derrubam o Líder")

	# without the surge the condition fails: one blow, no extra attack
	g = _new_game()
	_quiet(g)
	a = g.active
	enemy = g.opponent(a)
	baron = _put(g, a, "t_surge_baron")
	g.players[a]["momentum"] = 10
	g._refresh_scaling()
	g.players[enemy]["leader_hp"] = 30
	_hit(g, baron)
	check(baron.attacks_made == 1 and g.players[enemy]["leader_hp"] == 25, "auto_attack: sem o surto é um golpe só")

	# order: the extra attack happens (and animates) BEFORE the declared one, and never at the unit being challenged
	_tcard("t_surge_wall", 1, 40, [])
	g = _new_game()
	_quiet(g)
	a = g.active
	enemy = g.opponent(a)
	baron = _put(g, a, "t_surge_baron")
	var challenged := _put(g, enemy, "t_surge_wall")
	var other_wall := _put(g, enemy, "t_surge_wall")
	challenged.exhausted = true
	other_wall.exhausted = true
	g.players[a]["momentum"] = 11
	g._refresh_scaling()
	var events := _hit(g, baron, challenged.uid)
	var attack_targets: Array = []
	var damage_steps := 0
	for e in events:
		if e["type"] == "attack":
			attack_targets.append(int(e["target"]))
		elif e["type"] == "combat_damage":
			damage_steps += 1
	check(attack_targets.size() == 2 and attack_targets[1] == challenged.uid, "auto_attack: o ataque declarado vem por último")
	check(attack_targets.size() == 2 and attack_targets[0] != challenged.uid, "auto_attack: o ataque extra nunca escolhe a unidade desafiada")
	check(damage_steps == 2 and baron.attacks_made == 2, "auto_attack: dois combates completos, o extra primeiro")

	# the random pick has NO restriction: even a Barão with Ímpeto (sick) can hit the Leader, and an untapped
	# Etérea / Furtiva / Voo / Provocação unit is a valid pick too. Over many seeds, both ends get picked.
	_tcard("t_surge_ghost", 1, 40, [])
	CardDB.data()["cards"]["t_surge_ghost"]["keywords"] = ["eterea", "furtividade", "voo", "provocacao"]
	var ghost_picked := false
	var leader_picked := false
	for seed_value in range(1, 41):
		g = _new_game()
		_quiet(g)
		g.rng.seed = seed_value
		a = g.active
		enemy = g.opponent(a)
		baron = _put(g, a, "t_surge_baron", false)
		challenged = _put(g, enemy, "t_surge_wall")
		var ghost := _put(g, enemy, "t_surge_ghost") # untapped on purpose
		challenged.exhausted = true
		g.players[a]["momentum"] = 11
		g._refresh_scaling()
		events = _hit(g, baron, challenged.uid)
		attack_targets = []
		for e in events:
			if e["type"] == "attack":
				attack_targets.append(int(e["target"]))
		check(attack_targets.size() == 2 and attack_targets[1] == challenged.uid and attack_targets[0] != challenged.uid, "auto_attack: sempre um golpe extra antes do declarado (seed %d)" % seed_value)
		if attack_targets.size() == 2:
			ghost_picked = ghost_picked or attack_targets[0] == ghost.uid
			leader_picked = leader_picked or attack_targets[0] == GameState.LEADER_UID[enemy]
	check(ghost_picked, "auto_attack: uma unidade desvirada, Etérea e com Furtividade pode ser sorteada")
	check(leader_picked, "auto_attack: o Líder pode ser sorteado mesmo com Ímpeto")

	# the Barão dies to the counter-blow of the extra attack: the declared attack fizzles and combat still closes
	_tcard("t_surge_brute", 50, 60, [])
	var died_once := false
	for seed_value in range(1, 41):
		g = _new_game()
		_quiet(g)
		g.rng.seed = seed_value
		a = g.active
		enemy = g.opponent(a)
		baron = _put(g, a, "t_surge_baron")
		challenged = _put(g, enemy, "t_surge_brute")
		var other_brute := _put(g, enemy, "t_surge_brute")
		challenged.exhausted = true
		other_brute.exhausted = true
		g.players[a]["momentum"] = 11
		g._refresh_scaling()
		baron.shield = false # the surge Escudo would absorb the first counter-blow; this test wants the Barão to die
		events = _hit(g, baron, challenged.uid)
		var attack_count := 0
		for e in events:
			if e["type"] == "attack":
				attack_count += 1
		# the Barão may also die to the counter-blow of the DECLARED attack (then both attacks happened)
		if attack_count == 1:
			died_once = true
			check(g.find_unit(baron.uid) == null and g.hp_left(challenged) == 60, "auto_attack: o ataque declarado se desfez junto com o atacante (seed %d)" % seed_value)
			check(g.phase != "over" and g.combat_system().pending_attack.is_empty(), "auto_attack: nada fica pendente depois do golpe extra (seed %d)" % seed_value)
		else:
			check(attack_count == 2, "auto_attack: sem morte no golpe extra, os dois ataques acontecem (seed %d)" % seed_value)
	check(died_once, "auto_attack: em alguma seed o Barão morreu no contra-ataque do golpe extra")

## The Eryon deck: the Leader's loan, Eryon's sacrifice-for-Momentum, Cobrador's overflow and the named search.
func _test_eryon_deck() -> void:
	# Leader: +1 Momentum now (past 10 allowed), 1 less at the start of the next turn
	var g := _new_game()
	_quiet(g)
	var a := g.active
	g.players[a]["leader_id"] = "eryon"
	g.players[a]["momentum"] = 10
	g.players[a]["next_momentum"] = 0
	g.players[a]["ability_used"] = false # _quiet blocks the Leader ability; this test needs it
	g.use_ability(a)
	check(g.players[a]["momentum"] == 11, "Eryon Líder: +1 Momentum passa de 10 (%d)" % g.players[a]["momentum"])
	check(g.players[a]["next_momentum"] == -1, "Eryon Líder: dívida de 1 no próximo turno (%d)" % g.players[a]["next_momentum"])

	# the loan is paid by the debt alone: it does NOT restrict the cards the turn can play
	var other_essence_card_uid := _give(g, a, "esqueleto_guerreiro")
	var neutral_card_uid := _give(g, a, "ajudante_de_gambiarra")
	check(g.can_play(a, other_essence_card_uid), "Eryon Líder: depois do empréstimo ainda joga carta não neutra")
	check(g.can_play(a, neutral_card_uid), "Eryon Líder: depois do empréstimo ainda joga carta neutra")
	check(not g.is_play_restricted(a, CardDB.card("esqueleto_guerreiro")), "Eryon Líder: o empréstimo não cria restrição de jogo")

	# the turn the debt is paid, the loan is blocked; the turn after that it works again
	g._start_turn(a, false)
	check(g.players[a]["paid_debt_this_turn"], "Eryon Líder: pagar a dívida marca o turno como 'com dívida paga'")
	check(not g.can_use_ability(a), "Eryon Líder: no turno em que paga a dívida não pode emprestar de novo")
	g.players[a]["momentum"] = 10
	g._start_turn(a, false)
	check(not g.players[a]["paid_debt_this_turn"], "Eryon Líder: sem dívida no turno seguinte, a marca some")
	check(g.can_use_ability(a), "Eryon Líder: no turno seguinte ao pagamento pode emprestar de novo")

	# Encarnação Eryon: sacrifices ANOTHER ally and gains its cost, at most 3
	g = _new_game()
	_quiet(g)
	a = g.active
	var eryon := _put(g, a, "eryon")
	check(g.valid_targets(a, "other_ally_unit", eryon.uid).is_empty(), "Eryon: sozinho não tem a quem sacrificar")
	var fodder := _put(g, a, "cobrador_de_pedagio_torto")
	g.players[a]["momentum"] = 10
	g.players[g.opponent(a)]["leader_hp"] = 99 # the 10 blows of 2 must not end the game and cut the rest of the effect
	g.activate(a, eryon.uid, fodder.uid)
	check(g.find_unit(fodder.uid) == null, "Eryon: a unidade sacrificada morre")
	# the activation only gains Momentum: the blows wait for the end of the turn, so the player keeps the Momentum to spend
	check(g.players[a]["momentum"] == 13 and g.players[g.opponent(a)]["leader_hp"] == 99,
		"Eryon: ativar só ganha Momentum, sem golpes na hora (%d / %d)" % [g.players[a]["momentum"], g.players[g.opponent(a)]["leader_hp"]])
	check(g.is_play_restricted(a, CardDB.card("esqueleto_guerreiro")), "Eryon: sacrificar para ganhar Momentum trava o turno só para cartas neutras")
	var expensive := _put(g, a, "barao_estrondoso")
	g.players[a]["momentum"] = 10
	eryon.activated_turn = -1
	g.activate(a, eryon.uid, expensive.uid)
	check(g.players[a]["momentum"] == 14, "Eryon: custo 7 rende no máximo 4 (%d)" % g.players[a]["momentum"])
	g._finish_turn()
	g._flush()
	check(g.players[g.opponent(a)]["leader_hp"] == 99 - 22, "Eryon: no fim do turno, 14 de Momentum = 11 golpes de 2 (%d)" % g.players[g.opponent(a)]["leader_hp"])
	check(g.players[a]["momentum"] == 0, "Eryon: no fim do turno, acima de 10, gasta todo o Momentum (%d)" % g.players[a]["momentum"])

	# Eryon, 11+ Momentum after the gain: 3 blows of 2 spread over the enemies (Leader included); below 11 nothing happens
	g = _new_game()
	_quiet(g)
	a = g.active
	var eryon_enemy: int = g.opponent(a)
	eryon = _put(g, a, "eryon")
	fodder = _put(g, a, "barao_estrondoso")
	g.players[a]["momentum"] = 7
	g.players[eryon_enemy]["leader_hp"] = 60
	g.activate(a, eryon.uid, fodder.uid)
	g._finish_turn()
	g._flush()
	check(g.players[a]["momentum"] == 0, "Eryon: com 11 de Momentum no fim do turno gasta todo o Momentum (%d)" % g.players[a]["momentum"])
	check(g.players[eryon_enemy]["leader_hp"] == 44, "Eryon: 11 de Momentum = 8 golpes de 2 só no Líder (%d)" % g.players[eryon_enemy]["leader_hp"])
	# with overflow the blows grow: 10 + 4 = 14 Momentum = 11 blows = 22 damage
	g = _new_game()
	_quiet(g)
	a = g.active
	eryon_enemy = g.opponent(a)
	eryon = _put(g, a, "eryon")
	fodder = _put(g, a, "barao_estrondoso")
	g.players[a]["momentum"] = 10
	g.players[a]["reserve"] = 2
	g.players[eryon_enemy]["leader_hp"] = 60
	g.activate(a, eryon.uid, fodder.uid)
	g._finish_turn()
	g._flush()
	check(g.players[eryon_enemy]["leader_hp"] == 38, "Eryon: 14 de Momentum = 11 golpes de 2 (%d)" % g.players[eryon_enemy]["leader_hp"])
	check(g.players[a]["momentum"] == 0 and g.players[a]["reserve"] == 2, "Eryon: gasta o Momentum e preserva a Reserva (%d/%d)" % [g.players[a]["momentum"], g.players[a]["reserve"]])
	g = _new_game()
	_quiet(g)
	a = g.active
	eryon_enemy = g.opponent(a)
	eryon = _put(g, a, "eryon")
	fodder = _put(g, a, "cobrador_de_pedagio_torto")
	g.players[a]["momentum"] = 5
	g.players[eryon_enemy]["leader_hp"] = 60
	g.activate(a, eryon.uid, fodder.uid)
	check(g.players[a]["momentum"] == 8, "Eryon: 5 + 3 de Momentum (%d)" % g.players[a]["momentum"])
	g._fire(eryon, "on_turn_end")
	g._flush()
	check(g.players[a]["momentum"] == 8 and g.players[eryon_enemy]["leader_hp"] == 60,
		"Eryon: terminando o turno com menos de 11 de Momentum não causa dano (%d / %d)" % [g.players[a]["momentum"], g.players[eryon_enemy]["leader_hp"]])

	# the point of waiting: the Momentum is spent on the Barão first, so at the end of the turn nothing is left to blow up
	g = _new_game()
	_quiet(g)
	a = g.active
	eryon_enemy = g.opponent(a)
	eryon = _put(g, a, "eryon")
	g.players[a]["momentum"] = 11
	g.players[eryon_enemy]["leader_hp"] = 60
	var spender := _put(g, a, "barao_estrondoso")
	g._refresh_scaling()
	_hit(g, spender)
	g._flush()
	var leader_hp_after_baron: int = g.players[eryon_enemy]["leader_hp"]
	g._finish_turn()
	g._flush()
	check(g.players[eryon_enemy]["leader_hp"] == leader_hp_after_baron,
		"Eryon: depois que o Barão gasta o Momentum, o fim do turno não dá golpes (%d -> %d)" % [leader_hp_after_baron, g.players[eryon_enemy]["leader_hp"]])

	# the end-of-turn blows don't need the activation: ending the turn with 11+ Momentum is enough
	g = _new_game()
	_quiet(g)
	a = g.active
	eryon_enemy = g.opponent(a)
	eryon = _put(g, a, "eryon")
	g.players[a]["momentum"] = 12
	g.players[eryon_enemy]["leader_hp"] = 60
	g._finish_turn()
	g._flush()
	check(g.players[eryon_enemy]["leader_hp"] == 42 and g.players[a]["momentum"] == 0,
		"Eryon: sem ativar, terminar com 12 de Momentum dá 9 golpes de 2 (%d / %d)" % [g.players[eryon_enemy]["leader_hp"], g.players[a]["momentum"]])

	# Barão with the real card: Ímpeto and Escudo are innate; the surge turns on at 11 Momentum
	var baron := _put(g, a, "barao_estrondoso")
	g.players[a]["momentum"] = 10
	g._refresh_scaling()
	check(g.atk_of(baron) == 5 and g.has_kw(baron, "impeto") and baron.shield
		and not g.has_kw(baron, "sobrepujanca") and baron.critico_total() == 0,
		"Barão: com 10 de Momentum já tem Ímpeto e Escudo, sem o bônus")
	baron.shield = false
	g.players[a]["momentum"] = 11
	g._refresh_scaling()
	check(g.atk_of(baron) == 20 and g.has_kw(baron, "impeto") and not baron.shield
		and g.has_kw(baron, "sobrepujanca") and baron.critico_total() == 4,
		"Barão: com 11 de Momentum ganha +15, Sobrepujança e Crítico 4 sem renovar Escudo")

	# Barão, Ao Atingir o Líder: a hit of 10+ with more than 8 Momentum spends all plain Momentum (never the Reserva)
	g = _new_game()
	_quiet(g)
	a = g.active
	var baron_enemy: int = g.opponent(a)
	baron = _put(g, a, "barao_estrondoso")
	g.players[a]["momentum"] = 11
	g.players[a]["reserve"] = 2
	g._refresh_scaling()
	g.players[baron_enemy]["leader_hp"] = 60
	_hit(g, baron)
	g._flush()
	# two blows of 22 (20 ATK + 2 of Crítico 4): the Momentum is spent only after BOTH, so the declared blow keeps the surge
	check(g.players[baron_enemy]["leader_hp"] == 16, "Barão: o gasto de Momentum espera os dois golpes, ambos com o surto (Líder com %d)" % g.players[baron_enemy]["leader_hp"])
	check(g.players[a]["momentum"] == 0 and g.players[a]["reserve"] == 2,
		"Barão: golpe de 10+ no Líder gasta todo o Momentum e preserva a Reserva (%d/%d)" % [g.players[a]["momentum"], g.players[a]["reserve"]])
	g = _new_game()
	_quiet(g)
	a = g.active
	baron_enemy = g.opponent(a)
	baron = _put(g, a, "barao_estrondoso")
	g.players[a]["momentum"] = 10
	g._refresh_scaling()
	g.players[baron_enemy]["leader_hp"] = 60
	_hit(g, baron)
	g._flush()
	check(g.players[a]["momentum"] == 10, "Barão: golpe de 5 no Líder (abaixo de 10) não gasta Momentum (%d)" % g.players[a]["momentum"])

	# Cobrador de Pedágio Torto: only the oldest copy in play gives +1 Momentum, and never above 10
	var baseline_momentum := 0
	for copies in [0, 1, 3]:
		g = _new_game()
		_quiet(g)
		a = g.active
		for copy_number in copies:
			_put(g, a, "cobrador_de_pedagio_torto")
		g._start_turn(a, false)
		if copies == 0:
			baseline_momentum = int(g.players[a]["momentum"])
		else:
			check(int(g.players[a]["momentum"]) == baseline_momentum + 1, "Cobrador: %d cópia(s) em campo rendem só +1 Momentum (%d)" % [copies, g.players[a]["momentum"]])
	g = _new_game()
	_quiet(g)
	a = g.active
	for copy_number in 2:
		_put(g, a, "cobrador_de_pedagio_torto")
	g.players[a]["max_momentum"] = GameState.MOMENTUM_CAP
	g._start_turn(a, false)
	check(int(g.players[a]["momentum"]) <= GameState.MOMENTUM_CAP, "Cobrador: o Momentum dele nunca passa de 10 (%d)" % g.players[a]["momentum"])
	# The Cobrador no longer restricts playable cards when it grants Momentum.
	g = _new_game()
	_quiet(g)
	a = g.active
	_put(g, a, "cobrador_de_pedagio_torto")
	g.players[a]["max_momentum"] = 4
	g._start_turn(a, false)
	check(not g.is_play_restricted(a, CardDB.card("esqueleto_guerreiro")), "Cobrador: ganhar Momentum não restringe cartas de outras essências")
	check(not g.is_play_restricted(a, CardDB.card("ajudante_de_gambiarra")), "Cobrador: ganhar Momentum mantém cartas neutras jogáveis")
	g = _new_game()
	_quiet(g)
	a = g.active
	_put(g, a, "cobrador_de_pedagio_torto")
	g.players[a]["max_momentum"] = GameState.MOMENTUM_CAP
	g._start_turn(a, false)
	check(not g.is_play_restricted(a, CardDB.card("esqueleto_guerreiro")), "Cobrador: sem ganho real de Momentum (já em 10) não há trava")

	# Recado Urgente finds the Barão (or Gertrudes) anywhere in the deck
	g = _new_game()
	_quiet(g)
	a = g.active
	var deck: Array = g.players[a]["deck"]
	deck.push_front(Card.new(g._uid(), "barao_estrondoso", a))
	g._begin_search(a, {"card_ids": ["barao_estrondoso", "dona_gertrudes_fura_fila"]}, 0)
	check(g.phase == "search" and g.pending_search["cards"].size() == 1, "Recado Urgente: oferece só o Barão do deck")

	# Gertrudes in the deck is NOT offered, and with no Barão left the spell draws 1 card instead of whiffing
	g = _new_game()
	_quiet(g)
	a = g.active
	g.players[a]["deck"].push_front(Card.new(g._uid(), "dona_gertrudes_fura_fila", a))
	var hand_before: int = g.players[a]["hand"].size()
	g._begin_search(a, {"card_ids": ["barao_estrondoso"], "fallback_draw": 1}, 0)
	check(g.phase != "search", "Recado Urgente: sem o Barão no deck não abre escolha (Gertrudes não conta)")
	check(g.players[a]["hand"].size() == hand_before + 1, "Recado Urgente: sem o Barão no deck compra 1 carta (%d)" % (g.players[a]["hand"].size() - hand_before))

## Ao Causar Dano de Combate (on_deal_combat_damage) and Rália: every damage instance she really deals throws X damage
## (her Ataque) at up to 4 different random enemies, the Leader included, and that damage heals her Leader.
func _test_ralia_deal_damage() -> void:
	var ralia_data: Dictionary = CardDB.card("ralia")
	check(ralia_data["atk"] == 3 and ralia_data["hp"] == 7 and ralia_data["keywords"] == ["intimidacao", "roubo_de_vida"] \
		and ralia_data.get("imune_critico", false), "Rália é 3/7 com Intimidação, Roubo de Vida e Desdém")

	# hitting the face: the only enemy is the Leader, so the effect hits it once more (3 + 3)
	var g := _new_game()
	_quiet(g)
	var a := g.active
	var enemy := g.opponent(a)
	var ralia := _put(g, a, "ralia")
	g.players[enemy]["leader_hp"] = 99
	g.players[a]["leader_hp"] = g.players[a]["leader_max"] - 10
	ralia.damage = 5
	_hit(g, ralia)
	check(g.players[enemy]["leader_hp"] == 93, "Rália: bate 3 no Líder e o Ao Causar Dano de Combate bate mais 3 (%d)" % g.players[enemy]["leader_hp"])
	check(g.players[a]["leader_hp"] == g.players[a]["leader_max"] - 4, "Rália: o Líder cura 3 do golpe (Roubo de Vida inato) e 3 do efeito (%d)" % g.players[a]["leader_hp"])
	check(ralia.damage == 2, "Rália: o efeito também cura a própria Rália em 3, o golpe não (%d)" % ralia.damage)

	# challenging with 4 enemy units + the Leader in the pool: exactly 4 different picks of 3 each,
	# and the effect's own damage (no source) never fires it again
	_tcard("t_ralia_dummy", 0, 30, [])
	g = _new_game()
	_quiet(g)
	a = g.active
	enemy = g.opponent(a)
	ralia = _put(g, a, "ralia")
	var dummies: Array = []
	for i in 4:
		dummies.append(_put(g, enemy, "t_ralia_dummy"))
	for dummy: Card in dummies:
		dummy.exhausted = true
	g.players[enemy]["leader_hp"] = 99
	g.players[a]["leader_hp"] = g.players[a]["leader_max"] - 20
	_hit(g, ralia, dummies[0].uid)
	var effect_hits := 0
	var hit_twice := false
	for dummy: Card in dummies:
		var effect_damage := dummy.damage - (3 if dummy == dummies[0] else 0)
		effect_hits += effect_damage / 3
		hit_twice = hit_twice or effect_damage > 3
	var leader_effect_damage := 99 - int(g.players[enemy]["leader_hp"])
	effect_hits += leader_effect_damage / 3
	hit_twice = hit_twice or leader_effect_damage > 3
	check(effect_hits == 4 and not hit_twice, "Rália: 4 inimigos diferentes levam 3 cada (%d golpes, repetido: %s)" % [effect_hits, hit_twice])
	check(g.players[a]["leader_hp"] == g.players[a]["leader_max"] - 5, "Rália: o golpe cura 3 e o efeito cura 12 (4 x 3) (%d)" % g.players[a]["leader_hp"])

	# she dies to the counter-attack: the effect still resolves with the Ataque she had when she hit
	_tcard("t_ralia_brute", 9, 30, [])
	g = _new_game()
	_quiet(g)
	a = g.active
	enemy = g.opponent(a)
	ralia = _put(g, a, "ralia")
	var brute := _put(g, enemy, "t_ralia_brute")
	brute.exhausted = true
	g.players[enemy]["leader_hp"] = 99
	_hit(g, ralia, brute.uid)
	check(g.find_unit(ralia.uid) == null, "Rália: morre no revide de 9")
	check(brute.damage == 6 and g.players[enemy]["leader_hp"] == 96, "Rália morta: o efeito ainda usa o Ataque 3 dela (bruto %d, Líder %d)" % [brute.damage, g.players[enemy]["leader_hp"]])

	# a Silenciada Rália deals her combat damage with no Ao Causar Dano
	g = _new_game()
	_quiet(g)
	a = g.active
	enemy = g.opponent(a)
	ralia = _put(g, a, "ralia")
	g._apply_effect(enemy, {"action": "silence", "target": "enemy_unit"}, ralia.uid)
	g.players[enemy]["leader_hp"] = 99
	_hit(g, ralia)
	check(g.players[enemy]["leader_hp"] == 96, "Rália Silenciada: só o golpe de 3, sem o efeito (%d)" % g.players[enemy]["leader_hp"])

## The generic play restriction (PlayRestriction + restrict_play + add_play_restriction): filters by
## essence, rarity, card type and cost, "only" vs "forbid", durations in turns, and catalog validation.
func _test_play_restrictions() -> void:
	var fire_spell := CardDB.card("bola_de_fogo") # ígnea, comum, magia, custo 2
	var fire_champion := CardDB.card("ronan") # ígnea, campeão, unidade, custo 4
	var fire_artifact := CardDB.card("manoplas_incandescentes") # ígnea, artefato
	var dark_unit := CardDB.card("esqueleto_guerreiro") # obscura, comum, unidade, custo 1
	var neutral_unit := CardDB.card("ajudante_de_gambiarra")

	var only_fire := {"mode": "only", "match": {"essence": ["ignea"]}}
	check(not PlayRestriction.blocks(only_fire, fire_spell) and PlayRestriction.blocks(only_fire, dark_unit), "restrição: só ígneas barra a não ígnea")
	check(PlayRestriction.blocks(only_fire, neutral_unit), "restrição: só ígneas barra também a neutra")
	var no_champions := {"mode": "forbid", "match": {"rarity": ["champion"]}}
	check(PlayRestriction.blocks(no_champions, fire_champion) and not PlayRestriction.blocks(no_champions, fire_spell), "restrição: proibir campeões")
	var only_spells := {"mode": "only", "match": {"card_type": ["spell"]}}
	check(not PlayRestriction.blocks(only_spells, fire_spell) and PlayRestriction.blocks(only_spells, fire_champion) and PlayRestriction.blocks(only_spells, fire_artifact), "restrição: só magias barra unidade e artefato")
	var cheap_only := {"mode": "only", "match": {"cost": {"op": "<=", "value": 2}}}
	check(not PlayRestriction.blocks(cheap_only, dark_unit) and not PlayRestriction.blocks(cheap_only, fire_spell) and PlayRestriction.blocks(cheap_only, fire_champion), "restrição: só custo <= 2")
	var expensive_forbidden := {"mode": "forbid", "match": {"cost": {"op": ">=", "value": 4}}}
	check(PlayRestriction.blocks(expensive_forbidden, fire_champion) and not PlayRestriction.blocks(expensive_forbidden, fire_spell), "restrição: proibir custo >= 4")
	var combined := {"mode": "forbid", "match": {"essence": ["ignea"], "card_type": ["unit"]}}
	check(PlayRestriction.blocks(combined, fire_champion) and not PlayRestriction.blocks(combined, fire_spell) and not PlayRestriction.blocks(combined, dark_unit), "restrição: filtros combinados exigem todos")

	# duration: turns 1 = rest of this turn only; turns 2 also covers the next turn (whoever's it is)
	var g := _new_game()
	_quiet(g)
	var a: int = g.active
	g.add_play_restriction(a, {"mode": "only", "match": {"essence": ["ignea"]}})
	check(g.is_play_restricted(a, dark_unit) and not g.is_play_restricted(1 - a, dark_unit), "restrição: vale só para quem a recebeu")
	g._start_turn(1 - a, false)
	check(not g.is_play_restricted(a, dark_unit), "restrição de 1 turno acaba quando o próximo turno começa")
	g = _new_game()
	_quiet(g)
	a = g.active
	g.add_play_restriction(a, {"mode": "forbid", "match": {"rarity": ["champion"]}, "turns": 2})
	g._start_turn(1 - a, false)
	check(g.is_play_restricted(a, fire_champion), "restrição de 2 turnos ainda vale no turno seguinte")
	g._start_turn(a, false)
	check(not g.is_play_restricted(a, fire_champion), "restrição de 2 turnos acaba no terceiro turno")

	# it blocks the real play paths: hand and the Encarnação
	g = _new_game()
	_quiet(g)
	a = g.active
	g.players[a]["momentum"] = 10
	var fire_spell_uid := _give(g, a, "bola_de_fogo")
	check(g.can_play(a, fire_spell_uid), "restrição: sem restrição a magia ígnea é jogável")
	g.add_play_restriction(a, {"mode": "forbid", "match": {"card_type": ["spell"]}})
	check(not g.can_play(a, fire_spell_uid), "restrição: proibir magias bloqueia can_play")

	# the restrict_play effect, on the controller and on the opponent
	g = _new_game()
	_quiet(g)
	a = g.active
	var restrict_rival := EffectRegistry.parse({"action": "restrict_play", "target": "none", "who": "opponent",
		"restriction": {"mode": "only", "match": {"essence": ["neutra"]}}})
	restrict_rival.apply(EffectContext.new(g, a), 0)
	check(g.is_play_restricted(1 - a, dark_unit) and not g.is_play_restricted(a, dark_unit), "restrict_play com who=opponent restringe o rival")

	# catalog validation
	var essences: Dictionary = CardDB.data()["essences"]
	check(PlayRestriction.error_of(only_fire, essences) == "", "validação: regra válida passa")
	check(PlayRestriction.error_of({"mode": "xx", "match": {"rarity": ["common"]}}, essences) != "", "validação: mode inválido")
	check(PlayRestriction.error_of({"match": {}}, essences) != "", "validação: match vazio")
	check(PlayRestriction.error_of({"match": {"essence": ["nao_existe"]}}, essences) != "", "validação: essência inexistente")
	check(PlayRestriction.error_of({"match": {"rarity": ["raro_demais"]}}, essences) != "", "validação: raridade inexistente")
	check(PlayRestriction.error_of({"match": {"card_type": ["terreno"]}}, essences) != "", "validação: tipo de carta inexistente")
	check(PlayRestriction.error_of({"match": {"cost": {"op": "~", "value": 2}}}, essences) != "", "validação: operador de custo inválido")
	check(PlayRestriction.error_of({"match": {"mana": [1]}}, essences) != "", "validação: filtro desconhecido")
	check(PlayRestriction.error_of({"match": {"rarity": ["common"]}, "turns": 0}, essences) != "", "validação: turns precisa ser >= 1")

func _test_cortina_de_fumaca() -> void:
	# Cortina de Fumaça Barata: every ally unit gets Furtividade until its owner's next turn starts
	var g := _new_game()
	_quiet(g)
	var a := g.active
	var first_unit := _put(g, a, "esqueleto_guerreiro")
	var second_unit := _put(g, a, "esqueleto_guerreiro")
	var curtain := Card.new(g._uid(), "cortina_de_fumaca_barata", a, "hand")
	g.players[a]["hand"].append(curtain)
	g.players[a]["momentum"] = 10
	g.play_card(a, curtain.uid)
	g._flush()
	check(g.has_kw(first_unit, "furtividade") and g.has_kw(second_unit, "furtividade"), "Cortina de Fumaça: todas as unidades aliadas ganham Furtividade")
	g._start_turn(a, false)
	check(not g.has_kw(first_unit, "furtividade") and not g.has_kw(second_unit, "furtividade"), "Cortina de Fumaça: a Furtividade acaba quando o turno do dono começa")

func _test_champion_rework() -> void:
	# Jack: at the end of the turn he gains +1 Attack for each Momentum left, and no Vida
	var jack_game := _new_game()
	_quiet(jack_game)
	var jack := _put(jack_game, 0, "jack")
	var jack_attack_before := jack_game.atk_of(jack)
	var jack_health_before := jack.hp
	jack_game.players[0]["momentum"] = 3
	jack_game._fire(jack, "on_turn_end")
	jack_game._check_state()
	check(jack_game.atk_of(jack) == jack_attack_before + 3, "Jack: ganha +3 de Ataque com 3 de Momentum sobrando (%d)" % jack_game.atk_of(jack))
	check(jack.hp == jack_health_before, "Jack: não ganha Vida")
	jack_game.players[0]["momentum"] = 0
	jack_game._fire(jack, "on_turn_end")
	jack_game._check_state()
	check(jack_game.atk_of(jack) == jack_attack_before + 3, "Jack: sem Momentum sobrando não ganha nada")

	# Kai's Ao Atacar damages the Leader without burning; only his combat damage burns.
	var kai_game := _new_game()
	_quiet(kai_game)
	var kai := _put(kai_game, 0, "kai")
	var kai_leader_hp := int(kai_game.players[1]["leader_hp"])
	_hit(kai_game, kai)
	check(int(kai_game.players[1]["leader_hp"]) == kai_leader_hp - 3 and kai_game.leader_dot_markers(1, "queimadura") == 1,
		"Kai: Ao Atacar (1) e dano de combate (2) machucam o Líder, mas só o dano de combate queima 1")
	var kai_victim := _put(kai_game, 1, "geodo_vivo")
	kai_victim.dot_markers.clear()
	var kai_second := _put(kai_game, 0, "kai")
	kai_game.players[0]["attacked"] = false
	var markers_before := int(kai_victim.dot_markers.get("queimadura", 0))
	kai_game._deal_damage(kai_victim.uid, 1, kai_second)
	check(int(kai_victim.dot_markers.get("queimadura", 0)) == markers_before,
		"Kai: dano fora de combate causado por ele não deixa Queimadura")
	var other_burn := kai_game.leader_dot_markers(1, "queimadura")
	kai_game._deal_damage(GameState.LEADER_UID[1], 1, null)
	check(kai_game.leader_dot_markers(1, "queimadura") == other_burn, "Kai: dano que não é dele não queima")

	# Ao Sofrer Dano fires when the unit survives the hit, but not when the hit kills it
	_tcard("t_avenger", 1, 3, [{"trigger": "on_damaged", "action": "damage", "target": "enemy_leader", "amount": 2}])
	var avenger_game := _new_game()
	_quiet(avenger_game)
	var surviving_avenger := _put(avenger_game, 0, "t_avenger")
	var enemy_life_before: int = avenger_game.players[1]["leader_hp"]
	avenger_game._deal_damage(surviving_avenger.uid, 1, null)
	avenger_game._check_state()
	check(avenger_game.players[1]["leader_hp"] == enemy_life_before - 2, "Ao Sofrer Dano: dispara quando a unidade sobrevive")
	avenger_game._deal_damage(surviving_avenger.uid, 5, null)
	avenger_game._check_state()
	check(avenger_game.players[1]["leader_hp"] == enemy_life_before - 2, "Ao Sofrer Dano: não dispara com dano letal")

	# Isarelis: Ao Entrar can only pick an enemy unit with Vida <= 3 and destroys it (Escudo does not save it)
	_tcard("t_weak_foe", 1, 3, [])
	_tcard("t_strong_foe", 1, 4, [])
	var isa_game := _new_game()
	_quiet(isa_game)
	isa_game.players[0]["momentum"] = 10
	var weak_foe := _put(isa_game, 1, "t_weak_foe")
	var strong_foe := _put(isa_game, 1, "t_strong_foe")
	strong_foe.damage = 0
	var isarelis := _give(isa_game, 0, "isarelis")
	isa_game.play_card(0, isarelis)
	check(isa_game.phase == "enter_target", "Isarelis: pede o alvo ao entrar")
	var execution_targets := isa_game.valid_targets(0, isa_game.pending_enter["spec"], isarelis)
	check(execution_targets.has(weak_foe.uid) and not execution_targets.has(strong_foe.uid), "Isarelis: só dá para escolher inimigo com 3 de Vida ou menos")
	check(isa_game.choose_enter_target(0, strong_foe.uid).is_empty(), "Isarelis: alvo com Vida acima de 3 é recusado")
	weak_foe.shield = true
	isa_game.choose_enter_target(0, weak_foe.uid)
	_resolve_stack(isa_game)
	check(isa_game.find_unit(weak_foe.uid) == null, "Isarelis: destrói o alvo mesmo com Escudo")
	check(isa_game.find_unit(strong_foe.uid) != null, "Isarelis: o inimigo forte fica")
	# a wounded big unit counts by its current Vida
	var wounded_game := _new_game()
	_quiet(wounded_game)
	var wounded := _put(wounded_game, 1, "t_strong_foe")
	wounded.damage = 1
	check(wounded_game.valid_targets(0, "weak_enemy_unit").has(wounded.uid), "Isarelis: unidade ferida entra pela Vida atual")

## Silêncio: the unit loses keywords, every ability and its buffs (back to the printed stats); David destroys the 4 strongest enemy units (Ataque 8+).
func _test_silence_and_david() -> void:
	CardDB.data()["cards"]["t_loud"] = {"name": "t_loud", "type": "unit", "rarity": "common", "essence": "neutra", "cost": 1,
		"atk": 3, "hp": 5, "keywords": ["provocacao", "escudo"], "art": "", "text": "", "flavor": "", "tags": [],
		"effects": [{"trigger": "on_turn_start", "action": "damage", "target": "enemy_leader", "amount": 2},
			{"listen": "leader_damaged", "scope": "enemy", "action": "damage", "target": "own_leader", "amount": 1}]}
	_tcard("t_silencer", 1, 1, [{"trigger": "on_enter", "action": "silence", "target": "enemy_unit"}])

	# the silence itself, applied by a card (a chosen target)
	var g := _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	var loud := _put(g, 1, "t_loud")
	check(loud.has_kw("provocacao") and loud.shield, "Silêncio: a unidade começa com Provocação e Escudo")
	loud.atk += 2 # a buff received before the silence is lost with it
	var silencer := _give(g, 0, "t_silencer")
	g.play_card(0, silencer)
	check(g.phase == "enter_target", "Silêncio: pede o alvo ao entrar")
	g.choose_enter_target(0, loud.uid)
	_resolve_stack(g)
	loud = g.find_unit(loud.uid)
	check(loud.is_silenced(), "Silêncio: a unidade fica Silenciada")
	check(not loud.has_kw("provocacao") and not loud.shield, "Silêncio: perde Provocação e Escudo")
	check(loud.data()["effects"].is_empty(), "Silêncio: os efeitos somem dos dados da unidade")
	check(g.atk_of(loud) == 3 and loud.hp == 5, "Silêncio: volta ao Ataque e à Vida impressos (perde o buff)")
	# temporary buffs, damage already taken and a Vida buff that would not cover it
	var buffed := _put(g, 1, "t_loud")
	buffed.atk += 4
	buffed.hp += 3
	buffed.temp_atk = 2
	buffed.damage = 6 # 5 + 3 Vida: alive with 2 left; after the silence only 5 Vida remain
	buffed.silence()
	check(g.atk_of(buffed) == 3 and buffed.hp == 5, "Silêncio: buffs permanentes e temporários somem")
	check(buffed.hp_left() == 1, "Silêncio: o dano fica, mas a unidade nunca morre por perder Vida (sobra 1)")
	var leader_before: int = g.players[0]["leader_hp"]
	var own_leader_before: int = g.players[1]["leader_hp"]
	g._fire(loud, "on_turn_start")
	g._check_state()
	check(g.players[0]["leader_hp"] == leader_before, "Silêncio: o efeito Ao Iniciar o Turno não dispara mais")
	g._deal_damage(GameState.LEADER_UID[0], 1, null)
	g._check_state()
	check(g.players[1]["leader_hp"] == own_leader_before, "Silêncio: o Condicional (listen) não reage mais")
	leader_before = g.players[0]["leader_hp"]
	var copy := Card.from_dict(loud.to_dict(), "board", 1)
	check(copy.is_silenced() and not copy.has_kw("provocacao"), "Silêncio: sobrevive ao espelho de rede (to_dict/from_dict)")

	# an unsilenced twin still works (the silence is per unit, not per card)
	var twin := _put(g, 1, "t_loud")
	check(not twin.is_silenced() and twin.has_kw("provocacao"), "Silêncio: outra cópia da mesma carta não é afetada")
	leader_before = g.players[0]["leader_hp"]
	own_leader_before = g.players[1]["leader_hp"]
	g._fire(twin, "on_turn_start")
	g._check_state()
	check(g.players[0]["leader_hp"] == leader_before - 2, "Silêncio: a cópia sem Silêncio continua disparando")
	check(g.players[1]["leader_hp"] == own_leader_before - 1, "Silêncio: e o Condicional da cópia também reage")

	# David: the 4 strongest enemy units with Ataque 8 or more
	for attack in [7, 8, 9]:
		_tcard("t_atk_%d" % attack, attack, 3, [])
	var david_game := _new_game()
	_quiet(david_game)
	david_game.players[0]["momentum"] = 10
	var big_one := _put(david_game, 1, "t_atk_9")
	var big_two := _put(david_game, 1, "t_atk_9")
	var tied: Array = []
	for i in 3:
		tied.append(_put(david_game, 1, "t_atk_8"))
	var weak := _put(david_game, 1, "t_atk_7")
	var david := _give(david_game, 0, "david_ruina_dos_titas")
	david_game.play_card(0, david)
	_resolve_stack(david_game)
	check(david_game.find_unit(big_one.uid) == null and david_game.find_unit(big_two.uid) == null, "David: destrói as duas de Ataque 9")
	var tied_survivors := tied.filter(func(unit: Card) -> bool: return david_game.find_unit(unit.uid) != null)
	check(tied_survivors.size() == 1, "David: no empate pela última vaga, 2 das 3 de Ataque 8 caem e 1 fica")
	check(david_game.find_unit(weak.uid) != null, "David: unidade de Ataque 7 nunca é alvo")
	check(david_game.find_unit(david) != null, "David: ele mesmo (6/4) fica em campo")

	# fewer than 4 qualify: all of them go, and no dice are rolled
	var few_game := _new_game()
	_quiet(few_game)
	few_game.players[0]["momentum"] = 10
	var only_big := _put(few_game, 1, "t_atk_9")
	var only_weak := _put(few_game, 1, "t_atk_7")
	var rng_state_before := few_game.rng.state
	few_game.play_card(0, _give(few_game, 0, "david_ruina_dos_titas"))
	_resolve_stack(few_game)
	check(few_game.find_unit(only_big.uid) == null and few_game.find_unit(only_weak.uid) != null, "David: com menos de 4 qualificadas, destrói só as de Ataque 8+")
	check(few_game.rng.state == rng_state_before, "David: sem empate cruzando o corte, não rola dado")

## Plays `card_id` from player p's hand, aims it at `target_uid` (a unit's Ao Entrar asks for it, a spell/artifact takes it
## with the play) and resolves the stack. Returns the uid the card had in the hand.
func _play_aimed(g: GameState, p: int, card_id: String, target_uid: int) -> int:
	var hand_uid := _give(g, p, card_id)
	if CardDB.card(card_id)["type"] == "unit":
		g.play_card(p, hand_uid)
		if g.phase == "enter_target":
			g.choose_enter_target(p, target_uid)
	else:
		g.play_card(p, hand_uid, target_uid)
	_resolve_stack(g)
	return hand_uid

## True when player p has a card of this kind in the given zone ("hand", "graveyard"...).
func _zone_has(g: GameState, p: int, zone: String, card_id: String) -> bool:
	return g.players[p][zone].any(func(card: Card) -> bool: return card.card_id == card_id)

## The neutral "tech" pack: targeted answers, Mala Sem Alça and the three doublers.
func _test_tech_cards() -> void:
	_tcard("t_plain", 1, 4, [])
	CardDB.data()["cards"]["t_flyer"] = {"name": "t_flyer", "type": "unit", "rarity": "common", "essence": "neutra", "cost": 1,
		"atk": 1, "hp": 4, "keywords": ["voo"], "art": "", "effects": [], "text": "", "flavor": "", "tags": []}
	CardDB.data()["cards"]["t_wall"] = {"name": "t_wall", "type": "unit", "rarity": "common", "essence": "neutra", "cost": 1,
		"atk": 1, "hp": 6, "armor": 2, "keywords": ["provocacao", "escudo"], "art": "", "effects": [], "text": "", "flavor": "", "tags": []}
	_tcard("t_token", 1, 1, [])
	CardDB.data()["cards"]["t_token"]["token"] = true

	# Remendeira de Esquina: heals the own Leader
	var g := _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	g.players[0]["leader_max"] = 100
	g.players[0]["leader_hp"] = 20
	_play_aimed(g, 0, "remendeira_de_esquina", GameState.LEADER_UID[0])
	check(g.players[0]["leader_hp"] == 23, "Remendeira: cura 3 do Líder")

	# Estilingueiro Teimoso: 2 damage, only to an enemy with Voo
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	var flyer := _put(g, 1, "t_flyer")
	var grounded := _put(g, 1, "t_plain")
	var flying_targets := g.valid_targets(0, "enemy_flying_unit")
	check(flying_targets.has(flyer.uid) and not flying_targets.has(grounded.uid), "Estilingueiro: só mira unidade com Voo")
	_play_aimed(g, 0, "estilingueiro_teimoso", flyer.uid)
	check(flyer.damage == 2 and grounded.damage == 0, "Estilingueiro: 2 de dano na unidade com Voo")

	# Saltador de Cerca: the Provocação is gone until the end of the turn
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	var wall := _put(g, 1, "t_wall")
	_play_aimed(g, 0, "saltador_de_cerca", wall.uid)
	check(not wall.has_kw("provocacao"), "Saltador: o alvo perde Provocação")
	g.end_turn(0)
	check(wall.has_kw("provocacao"), "Saltador: a Provocação volta no fim do turno")

	# Furador de Casca: no Escudo, no Armadura
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	wall = _put(g, 1, "t_wall")
	check(wall.shield and g.armor_of(wall) == 2, "Furador: o alvo começa com Escudo e Armadura 2")
	_play_aimed(g, 0, "furador_de_casca", wall.uid)
	check(not wall.shield and g.armor_of(wall) == 0, "Furador: Escudo e Armadura somem")

	# Tia Odete: destroys every enemy ficha and nothing else
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	var token_one := _put(g, 1, "t_token")
	var token_two := _put(g, 1, "t_token")
	var real_unit := _put(g, 1, "t_plain")
	var own_token := _put(g, 0, "t_token")
	_play_aimed(g, 0, "tia_odete_faz_tudo", 0)
	check(g.find_unit(token_one.uid) == null and g.find_unit(token_two.uid) == null, "Tia Odete: destrói as fichas inimigas")
	check(g.find_unit(real_unit.uid) != null and g.find_unit(own_token.uid) != null, "Tia Odete: poupa unidades normais e fichas aliadas")

	# Desmontador de Quinquilharia: destroys a free-standing enemy artifact
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	var relic := Card.new(g._uid(), "t_relic", 1, "relics")
	CardDB.data()["cards"]["t_relic"] = {"name": "t_relic", "type": "artifact", "rarity": "common", "essence": "neutra", "cost": 1,
		"effects": [], "text": "", "flavor": "", "art": "", "tags": []}
	g.players[1]["relics"].append(relic)
	_play_aimed(g, 0, "desmontador_de_quinquilharia", relic.uid)
	check(g.players[1]["relics"].is_empty(), "Desmontador: destrói o artefato inimigo")

	# Zeladora Shhh: silences
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	wall = _put(g, 1, "t_wall")
	_play_aimed(g, 0, "zeladora_shhh", wall.uid)
	check(wall.is_silenced() and not wall.has_kw("provocacao"), "Zeladora Shhh: silencia a unidade")

	# Capa de Última Hora: Escudo for an ally
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	var plain := _put(g, 0, "t_plain")
	_play_aimed(g, 0, "capa_de_ultima_hora", plain.uid)
	check(plain.shield, "Capa de Última Hora: a unidade ganha Escudo")

	# Mala Sem Alça: +1/+1, returns to the hand only when the unit DIES
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	plain = _put(g, 0, "t_plain")
	_play_aimed(g, 0, "mala_sem_alca", plain.uid)
	check(g.atk_of(plain) == 2 and g.hp_left(plain) == 5, "Mala: a unidade ganha +1/+1")
	plain.damage = 99
	g._check_state()
	check(_zone_has(g, 0, "hand", "mala_sem_alca"), "Mala: volta para a mão quando a unidade morre")
	check(not _zone_has(g, 0, "graveyard", "mala_sem_alca"), "Mala: não fica no cemitério")
	g = _new_game()
	_quiet(g)
	g.players[0]["momentum"] = 10
	var second := _put(g, 0, "t_plain")
	_play_aimed(g, 0, "mala_sem_alca", second.uid)
	check(not _zone_has(g, 0, "hand", "mala_sem_alca"), "Mala: depois de jogada, sai da mão")
	g._release_equipment(second) # the unit leaves without dying (a bounce or a banish)
	g._check_state()
	check(_zone_has(g, 0, "graveyard", "mala_sem_alca") and not _zone_has(g, 0, "hand", "mala_sem_alca"), "Mala: se a unidade só sai (sem morrer), a Mala fica no cemitério")

	# Arauto Repeteco: other units' Ao Entrar happen twice, two Arautos still only twice
	_tcard("t_enter_hit", 1, 3, [{"trigger": "on_enter", "action": "damage", "target": "enemy_leader", "amount": 2}])
	g = _new_game()
	_quiet(g)
	var leader_before: int = g.players[1]["leader_hp"]
	_put(g, 0, "t_enter_hit")
	check(g.players[1]["leader_hp"] == leader_before - 2, "Arauto: sem o Arauto o Ao Entrar acontece uma vez")
	var herald := _put(g, 0, "arauto_repeteco")
	check(g.players[1]["leader_hp"] == leader_before - 2, "Arauto: o Ao Entrar do próprio Arauto não é dobrado (ele não tem nenhum)")
	_put(g, 0, "arauto_repeteco")
	leader_before = g.players[1]["leader_hp"]
	_put(g, 0, "t_enter_hit")
	check(g.players[1]["leader_hp"] == leader_before - 4, "Arauto: com Arautos o Ao Entrar acontece duas vezes (e dois Arautos não dão quatro)")
	check(herald != null, "Arauto: continua em campo")

	# Coveiro Bis: Ao Morrer twice, including when the Coveiro dies along with the unit
	_tcard("t_death_hit", 1, 3, [{"trigger": "on_death", "action": "damage", "target": "enemy_leader", "amount": 2}])
	g = _new_game()
	_quiet(g)
	var death_unit := _put(g, 0, "t_death_hit")
	leader_before = g.players[1]["leader_hp"]
	death_unit.damage = 99
	g._check_state()
	check(g.players[1]["leader_hp"] == leader_before - 2, "Coveiro: sem o Coveiro o Ao Morrer acontece uma vez")
	var gravedigger := _put(g, 0, "coveiro_bis")
	death_unit = _put(g, 0, "t_death_hit")
	leader_before = g.players[1]["leader_hp"]
	death_unit.damage = 99
	g._check_state()
	check(g.players[1]["leader_hp"] == leader_before - 4, "Coveiro: com o Coveiro o Ao Morrer acontece duas vezes")
	death_unit = _put(g, 0, "t_death_hit")
	leader_before = g.players[1]["leader_hp"]
	death_unit.damage = 99
	gravedigger.damage = 99
	g._check_state()
	check(g.players[1]["leader_hp"] == leader_before - 4, "Coveiro: morrendo junto com a unidade ainda dobra o Ao Morrer dela")

	# Contador Exagerado: text Constantes count double (and never stack)
	_tcard("t_scaler", 1, 1, [{"trigger": "constante", "action": "scale", "per": "own_graveyard_units", "atk": 1, "hp": 1}])
	g = _new_game()
	_quiet(g)
	var scaler := _put(g, 0, "t_scaler")
	for i in 3:
		g.players[0]["graveyard"].append(Card.new(g._uid(), "t_plain", 0, "graveyard"))
	g._refresh_scaling()
	check(g.atk_of(scaler) == 4, "Contador: sem ele, +1 por unidade do cemitério (1+3)")
	_put(g, 0, "contador_exagerado")
	g._refresh_scaling()
	check(g.atk_of(scaler) == 7, "Contador: com ele conta em dobro (1+6)")
	_put(g, 0, "contador_exagerado")
	g._refresh_scaling()
	check(g.atk_of(scaler) == 7, "Contador: dois Contadores não dão x4")

## Isarelis' Ao Atingir o Líder destroys the most wounded enemy unit that has Vida <= 3 (an execution).
func _test_isarelis_hit_leader() -> void:
	_tcard("t_big_foe", 1, 8, [])
	var g := _new_game()
	_quiet(g)
	var isarelis := _put(g, 0, "isarelis") # first, so her Ao Entrar has nobody to execute
	var unhurt := _put(g, 1, "t_big_foe")
	var healthy_wounded := _put(g, 1, "t_big_foe")
	healthy_wounded.damage = 2 # Vida 6: wounded, but too healthy to be executed
	var low_a := _put(g, 1, "t_big_foe")
	low_a.damage = 5 # Vida 3
	var low_b := _put(g, 1, "t_big_foe")
	low_b.damage = 6 # Vida 2: the most wounded of the executable ones
	g._fire(isarelis, "on_hit_leader")
	g._check_state()
	check(g.find_unit(low_b.uid) == null, "Isarelis: Ao Atingir o Líder destrói a mais ferida com 3 de Vida ou menos")
	check(g.find_unit(unhurt.uid) != null and g.find_unit(healthy_wounded.uid) != null and g.find_unit(low_a.uid) != null, "Isarelis: não destrói as outras (sem ferida, Vida acima de 3, menos ferida)")
	g._fire(isarelis, "on_hit_leader")
	g._check_state()
	check(g.find_unit(low_a.uid) == null, "Isarelis: no golpe seguinte vai para a próxima mais ferida")
	g._fire(isarelis, "on_hit_leader")
	g._check_state()
	check(g.find_unit(unhurt.uid) != null and g.find_unit(healthy_wounded.uid) != null, "Isarelis: sem ferida elegível, não destrói ninguém")

func _test_maria_helena() -> void:
	var cd := CardDB.card("maria_helena")
	check(int(cd["cost"]) == 5 and int(cd["atk"]) == 0 and int(cd["hp"]) == 6, "Santa Maria Helena: continua custo 5 e vira 0/6")
	check(int(cd["leader_damage_reduction"]) == 3, "Santa Maria Helena: redução do primeiro dano é 3")

	var g := _new_game()
	_quiet(g)
	g.players[0]["leader_max"] = 100
	g.players[0]["leader_hp"] = 20
	var maria := _put(g, 0, "maria_helena")
	check(maria.hp == 6, "Santa Maria Helena: Vida base 6")
	g._fire(maria, "on_turn_start")
	g._check_state()
	check(g.players[0]["leader_hp"] == 22, "Santa Maria Helena: cura 2 no início do turno")

	var before: int = g.players[0]["leader_hp"]
	check(g._deal_damage(GameState.LEADER_UID[0], 5, null) == 2 and g.players[0]["leader_hp"] == before - 2,
		"Santa Maria Helena: primeiro dano do turno é reduzido em 3")
	before = g.players[0]["leader_hp"]
	check(g._deal_damage(GameState.LEADER_UID[0], 5, null) == 5 and g.players[0]["leader_hp"] == before - 5,
		"Santa Maria Helena: danos seguintes do mesmo turno não são reduzidos")

	g._start_turn(0, false)
	before = g.players[0]["leader_hp"]
	check(g._deal_damage(GameState.LEADER_UID[0], 2, null) == 1 and g.players[0]["leader_hp"] == before - 1,
		"Santa Maria Helena: a redução nunca transforma dano em menos de 1 e reinicia no turno seguinte")

func _test_art_crop() -> void:
	var tall_art := Vector2(1000, 2000)
	var window := Vector2(106, 98)
	var plain := CardView.art_source_rect(tall_art, window, {})
	check(is_equal_approx(plain.size.x, 1000.0) and is_equal_approx(plain.position.y, 0.0), "art_crop: sem recorte a arte preenche a largura e fica no topo")
	var moved := CardView.art_source_rect(tall_art, window, {"y": 1.0})
	check(is_equal_approx(moved.end.y, 2000.0), "art_crop: y=1 encosta a janela no fim da arte")
	var zoomed := CardView.art_source_rect(tall_art, window, {"zoom": 2.0, "x": 0.0, "y": 0.0})
	check(is_equal_approx(zoomed.size.x, 500.0) and is_equal_approx(zoomed.position.x, 0.0), "art_crop: zoom 2 mostra metade da arte")
	var past_edges := CardView.art_source_rect(tall_art, window, {"zoom": 9.0, "x": 5.0, "y": -3.0})
	check(Rect2(Vector2.ZERO, tall_art).encloses(past_edges), "art_crop: x, y e zoom absurdos continuam dentro da arte")
	for card_id in CardDB.data()["cards"]:
		check(not CardDB.errors().any(func(error: String): return error.contains("art_crop") and error.contains(card_id)), "art_crop inválido em %s" % card_id)
