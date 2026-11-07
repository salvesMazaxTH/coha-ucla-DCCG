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
	if failures == 0:
		print("Cast fx smoke tests passed.")
	quit(failures)

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
	# a trigger the card has no harmful area effect for is still not an area cast, with or without hit_fx
	check(not casts.is_area("t_plain_fire", "on_play"), "gatilho sem efeito em área não é conjuração de área")
	for card_id in ["t_plain_fire", "t_own_shots", "t_own_shots_and_cast", "t_plain_fire_spell", "t_own_shots_spell"]:
		CardDB.data()["cards"].erase(card_id)

## Registers a throwaway card in the loaded card data (this process only, nothing is written to disk).
func _add_temporary_card(card_id: String, fields: Dictionary) -> void:
	var card := {"name": card_id, "type": "unit", "rarity": "common", "essence": "furia", "cost": 1, "atk": 1, "hp": 1,
		"art": "", "text": "", "flavor": "", "tags": [], "effects": []}
	card.merge(fields, true)
	CardDB.data()["cards"][card_id] = card
