extends SceneTree
## Headless: godot --headless --path . -s tests/cast_fx_smoke.gd
## Checks which cards get the AREA cast animation (FxCasts.is_area): the one an element or a domain gives by
## default (the wall of flames for fogo...) must never replace the shots of a card that EXPRESSLY declares its own
## "hit_fx" (the rubies of Cuspa-Rubi), not even for its "Ao Entrar".
## This is not inside run_tests.gd on purpose: FxCasts needs the autoloads (Sfx...) to compile, and they only
## join the tree after _init, while run_tests.gd does all of its work inside _init.

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _init() -> void:
	# wait one frame so the autoloads exist before FxCasts (which depends on them) is loaded
	await process_frame
	_test_real_cards()
	_test_temporary_cards()
	_test_leader_death_variants()
	_test_leader_death_shards()
	if failures == 0:
		print("Cast fx smoke tests passed.")
	quit(failures)

## The Leader's death animation: always the burst, unless an alternative is registered AND the 1% roll hits.
func _test_leader_death_variants() -> void:
	var death = load("res://scripts/ui/fx_leader_death.gd").new(null, null)
	check(death.pick_variant(0.0) == "burst", "morte do Líder: sem alternativas, sempre o estouro")
	death.register_variant("outra", func(_leader_view, _t): return 1.0)
	check(death.pick_variant(0.005) == "outra", "morte do Líder: com alternativa, o 1% sorteado a escolhe")
	check(death.pick_variant(0.5) == "burst", "morte do Líder: fora do 1%, o estouro")
	check(death.pick_variant(0.011) == "burst", "morte do Líder: logo acima do 1%, o estouro")

## The top piece of the portrait breaks into a few irregular shards that add up to it (nothing lost, nothing overlapping).
func _test_leader_death_shards() -> void:
	var death_script = load("res://scripts/ui/fx_leader_death.gd")
	var leader_view := LeaderView.new()
	leader_view.leader_id = "ronan"
	var outline := leader_view.top_piece_outline()
	leader_view.free()
	var outline_area: float = death_script.polygon_area(outline)
	check(outline_area > 1000.0, "cacos do Líder: contorno com área")
	check(is_equal_approx(death_script.polygon_area(PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])), 100.0), "polygon_area: quadrado 10x10")
	var random := RandomNumberGenerator.new()
	for seed_number in 5:
		random.seed = seed_number + 1
		var shards: Array = death_script.split_into_shards(outline, random)
		var total_area := 0.0
		var biggest := 0.0
		var smallest := INF
		for shard in shards:
			var area: float = death_script.polygon_area(shard)
			total_area += area
			biggest = maxf(biggest, area)
			smallest = minf(smallest, area)
		check(shards.size() >= 3 and shards.size() <= death_script.SHARD_SEED_COUNT + 3, "cacos do Líder: poucos cacos (%d)" % shards.size())
		check(total_area <= outline_area + 1.0 and total_area >= outline_area * 0.9, "cacos do Líder: as áreas somam o contorno (%.0f de %.0f)" % [total_area, outline_area])
		check(biggest > smallest * 1.5, "cacos do Líder: tamanhos diferentes")

## The script is loaded at runtime (not preloaded) for the same reason: see the top of this file.
func _new_casts():
	# is_area and style_of only read card data, so no table (host) nor effects library is needed
	return load("res://scripts/ui/fx_casts.gd").new(null, null)

## The cards as they are written today.
func _test_real_cards() -> void:
	var casts = _new_casts()
	# the card from the bug: it hits every enemy unit when it enters AND names its own "rubi" shots
	check(String(CardDB.card("cuspa_rubi").get("hit_fx", "")) == "rubi", "cuspa_rubi declara os próprios tiros (hit_fx rubi)")
	check(casts.style_of("cuspa_rubi") == "fogo", "cuspa_rubi: o elemento fogo daria a parede de chamas por padrão")
	check(not casts.is_area("cuspa_rubi", "on_enter"), "cuspa_rubi: o Ao Entrar não vira conjuração de área, ela mantém os rubis")
	# cards with no hit_fx of their own keep the area animation (one trigger and three spells)
	check(casts.is_area("dlorafya", "on_enter"), "dlorafya (sem hit_fx): o Ao Entrar continua varrendo a arena")
	check(casts.is_area("pira_mundo", "on_play"), "pira_mundo: continua com a parede de chamas")
	check(casts.is_area("tsunami", "on_play"), "tsunami: continua com a onda")
	check(casts.is_area("julgamento_da_era_afogada", "on_play"), "julgamento_da_era_afogada: continua com a onda")
	# Coagulhão (Trevas/Fluxo, element sangue by deliberate exception): its Ao Entrar floods the arena with blood
	check(casts.style_of("coagulhao") == "sangue", "coagulhao: elemento sangue dá a maré de sangue")
	check(casts.is_area("coagulhao", "on_enter"), "coagulhao: o Ao Entrar toca a maré de sangue em área")
	# the rule is generic: any card with its own hit_fx (and no cast_fx) is never an area cast, for any trigger
	for card_id in CardDB.data()["cards"]:
		var card: Dictionary = CardDB.card(card_id)
		if not card.has("hit_fx") or card.has("cast_fx"):
			continue
		for effect in card.get("effects", []):
			var trigger := String(effect.get("trigger", ""))
			check(not casts.is_area(card_id, trigger), "%s declara hit_fx, então o gatilho \"%s\" não pode virar conjuração de área" % [card_id, trigger])

## Throwaway cards that differ only in hit_fx / cast_fx, so this test keeps working even if real cards change.
func _test_temporary_cards() -> void:
	var casts = _new_casts()
	# every one of them is fogo and hits all enemy units (when it enters, or when the spell is played)
	var enter_effects := [{"trigger": "on_enter", "action": "damage", "target": "all_enemy_units", "amount": 1}]
	var play_effects := [{"trigger": "on_play", "action": "damage", "target": "all_enemy_units", "amount": 1}]
	_add_temporary_card("t_plain_fire", {"element": "fogo", "effects": enter_effects})
	_add_temporary_card("t_own_shots", {"element": "fogo", "hit_fx": "rubi", "effects": enter_effects})
	_add_temporary_card("t_own_shots_and_cast", {"element": "fogo", "hit_fx": "rubi", "cast_fx": "fogo", "effects": enter_effects})
	_add_temporary_card("t_plain_fire_spell", {"type": "spell", "element": "fogo", "effects": play_effects})
	_add_temporary_card("t_own_shots_spell", {"type": "spell", "element": "fogo", "hit_fx": "rubi", "effects": play_effects})
	check(casts.is_area("t_plain_fire", "on_enter"), "carta fogo sem hit_fx: o Ao Entrar em área toca a conjuração de área")
	check(not casts.is_area("t_own_shots", "on_enter"), "carta fogo com hit_fx: o Ao Entrar em área mantém os tiros dela")
	check(casts.is_area("t_plain_fire_spell", "on_play"), "feitiço fogo sem hit_fx: toca a conjuração de área")
	check(not casts.is_area("t_own_shots_spell", "on_play"), "feitiço fogo com hit_fx: mantém os tiros dele")
	# declaring BOTH is also an express choice of the area animation, so the cast_fx is honored
	check(casts.is_area("t_own_shots_and_cast", "on_enter"), "quem declara hit_fx E cast_fx pediu a conjuração de área, ela toca")
	# no element and no cast_fx (Coagulhão, a Fluxo card that is not water), or an element with no area
	# animation (metal): the area effect flies the default bolts instead
	_add_temporary_card("t_no_element", {"essence": "fluxo", "effects": enter_effects})
	_add_temporary_card("t_metal", {"element": "metal", "effects": enter_effects})
	_add_temporary_card("t_stone", {"element": "pedra", "effects": enter_effects})
	_add_temporary_card("t_vine", {"element": "vegetal", "effects": enter_effects})
	_add_temporary_card("t_no_element_cast", {"cast_fx": "agua", "effects": enter_effects})
	check(not casts.is_area("t_no_element", "on_enter"), "carta Fluxo sem elemento: o domínio não dá animação de área, usa os lasers padrão")
	check(not casts.is_area("t_metal", "on_enter"), "elemento metal (sem animação de área): usa os lasers padrão")
	check(casts.is_area("t_stone", "on_enter"), "elemento pedra: toca o deslizamento de rochas em área")
	check(casts.is_area("t_vine", "on_enter"), "elemento vegetal: toca o espinheiral em área")
	check(casts.is_area("t_no_element_cast", "on_enter"), "cast_fx declarado toca a animação de área mesmo sem elemento")
	# a sangue destroy bleeds the unit dry (its own animation), instead of the red X
	_add_temporary_card("t_blood_destroy", {"type": "spell", "element": "sangue",
		"effects": [{"trigger": "on_play", "action": "destroy", "target": "enemy_unit"}]})
	check(casts.destroy_style_of("t_blood_destroy") == "sangue", "destruição de sangue tem a animação própria (sangrar a unidade)")
	CardDB.data()["cards"].erase("t_blood_destroy")
	# a raio destroy electrocutes the unit, a gelo one freezes and shatters it and a luz one smites it with holy light
	for element_and_style in [["raio", "raio"], ["gelo", "gelo"], ["luz", "luz"]]:
		_add_temporary_card("t_destroy_" + element_and_style[0], {"type": "spell", "element": element_and_style[0],
			"effects": [{"trigger": "on_play", "action": "destroy", "target": "enemy_unit"}]})
		check(casts.destroy_style_of("t_destroy_" + element_and_style[0]) == element_and_style[1], "destruição de %s: animação '%s'" % [element_and_style[0], element_and_style[1]])
		CardDB.data()["cards"].erase("t_destroy_" + element_and_style[0])
	# destroy_fx wins over cast_fx and element, but only for destroys; without it cast_fx keeps deciding
	var destroy_effects := [{"trigger": "on_enter", "action": "destroy", "target": "enemy_unit"}]
	_add_temporary_card("t_destroy_fx", {"element": "fogo", "cast_fx": "agua", "destroy_fx": "sangue", "effects": destroy_effects})
	_add_temporary_card("t_cast_fx_only", {"element": "fogo", "cast_fx": "agua", "effects": destroy_effects})
	_add_temporary_card("t_destroy_fx_invalid", {"element": "fogo", "destroy_fx": "fagulha", "effects": destroy_effects})
	check(casts.destroy_style_of("t_destroy_fx") == "sangue", "destroy_fx ganha do cast_fx e do elemento na destruição")
	check(casts.style_of("t_destroy_fx") == "agua", "destroy_fx não muda a animação de área (cast_fx continua valendo)")
	check(casts.destroy_style_of("t_cast_fx_only") == "agua", "sem destroy_fx, o cast_fx continua decidindo a destruição")
	check(casts.destroy_style_of("t_destroy_fx_invalid") == "", "destroy_fx sem animação de destruição cai no X vermelho")
	for card_id in ["t_destroy_fx", "t_cast_fx_only", "t_destroy_fx_invalid"]:
		CardDB.data()["cards"].erase(card_id)
	# a trigger the card has no harmful area effect for is still not an area cast, with or without hit_fx
	check(not casts.is_area("t_plain_fire", "on_play"), "gatilho sem efeito em área não é conjuração de área")
	for card_id in ["t_plain_fire", "t_own_shots", "t_own_shots_and_cast", "t_plain_fire_spell", "t_own_shots_spell", "t_no_element", "t_metal", "t_stone", "t_vine", "t_no_element_cast"]:
		CardDB.data()["cards"].erase(card_id)

## Registers a throwaway card in the loaded card data (this process only, nothing is written to disk).
func _add_temporary_card(card_id: String, fields: Dictionary) -> void:
	var card := {"name": card_id, "type": "unit", "rarity": "common", "essence": "furia", "cost": 1, "atk": 1, "hp": 1,
		"art": "", "text": "", "flavor": "", "effects": []}
	card.merge(fields, true)
	CardDB.data()["cards"][card_id] = card
