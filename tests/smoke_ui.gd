extends SceneTree
## Headless UI smoke test: builds the table and renders several states.

func _init() -> void:
	# autoloads (Sfx, SupabaseAuth...) join the tree only after _init, and main.gd cannot compile without them
	await process_frame
	var m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	m._show_menu()
	m._show_hub(false)
	m.sel_deck = "obscura_lento"
	m._show_hub(true) # step 1: your deck, then "PRÓXIMO"
	m._show_hub(true, "", true) # step 2: the AI's deck, then "JOGAR"
	await process_frame
	var play: Button = null
	for c in m.layer.get_children():
		if c is Button and c.text == "JOGAR":
			play = c
	if play == null:
		push_error("hub vs IA sem botão JOGAR")
		quit(1)
		return
	play.pressed.emit()
	if m.g == null or not m.vs_ai or m.g.players[0]["leader_id"] != "jeff":
		push_error("hub vs IA não iniciou a partida com o deck escolhido")
		quit(1)
		return
	m._start(false, "fogo", "agua")
	m.pending_pass = false
	m._render()
	var performance_report: String = m._performance_summary(60)
	if not performance_report.contains("Artes:") or not performance_report.contains("Fotos:"):
		push_error("o relatório de diagnóstico está incompleto")
		quit(1)
		return
	m._do(m.g.mulligan(0, []))
	m.pending_pass = false
	m._do(m.g.mulligan(1, []))
	m.pending_pass = false
	for i in 30:
		if m.g.phase == "over":
			break
		var ev = SimpleAI.step(m.g, m.g.decider())
		m.viewer = m.g.decider()
		m._do(ev)
		m.pending_pass = false
		m._render()
		var v = null
		for c in m.layer.get_children():
			if c is CardView and not c.face_down:
				v = c
		if v:
			m._show_overlay(v)
			m._close_overlay()
		if i % 5 == 0: # graveyard viewer: open, every filter, survive a re-render, close
			m._show_graveyard(i % 2)
			for f in m.GRAVE_FILTERS:
				m.grave_filter = f[0]
				m._refresh_graveyard()
			m._render()
			# search/over close it on purpose (see _render)
			if m.grave_view == null and not m.g.phase in ["search", "over"]:
				push_error("cemitério fechou no re-render")
				quit(1)
				return
			m._close_graveyard()
		await process_frame
	var last_turn: int = m.g.turn
	if not await _check_effect_choice_ui(m):
		quit(1)
		return
	if not await _check_activation_cost_choice_ui(m):
		quit(1)
		return
	if not await _check_equipment_ui(m):
		quit(1)
		return
	if not await _check_field_equip_input(m):
		quit(1)
		return
	if not await _check_deck_builder(m): # leaves the match, so the turn was read first
		quit(1)
		return
	if not await _check_hub_with_own_deck(m):
		quit(1)
		return
	print("smoke ok, turn ", last_turn)
	quit()

func _check_effect_choice_ui(m) -> bool:
	m._start(false, "fogo", "agua")
	m.pending_pass = false
	m.g.mulligan(0, [])
	m.g.mulligan(1, [])
	m.g.active = 0
	m.g.phase = "combat"
	m.g.window = "attacks"
	m.g.priority = 0
	m.g.players[0]["momentum"] = 0
	m.g.players[1]["momentum"] = 0
	m.g.players[0]["ability_used"] = true
	m.g.players[1]["ability_used"] = true
	var nicolas := Card.new(m.g._uid(), "nicolas", 0, "board")
	var challenged := Card.new(m.g._uid(), "geodo_vivo", 1, "board")
	var other := Card.new(m.g._uid(), "geodo_vivo", 1, "board")
	nicolas.enter_board(false)
	challenged.enter_board(false)
	other.enter_board(false)
	nicolas.sick = false
	challenged.exhausted = true
	m.g.players[0]["board"].append(nicolas)
	m.g.players[1]["board"].append(challenged)
	m.g.players[1]["board"].append(other)
	m.g.attack_unit(0, nicolas.uid, challenged.uid)
	m.viewer = 0
	m.pending_pass = false
	m._render_now()
	if m.g.phase != "effect_choice" or not m.option_prompt.get("mandatory", false) or m.option_prompt["options"].size() != 2:
		push_error("a escolha do Nicolas não abriu a janela: phase=%s decider=%s viewer=%s prompt=%s" % [m.g.phase, m.g.decider(), m.viewer, m.option_prompt])
		return false
	m._close_option_prompt()
	if m.option_prompt.is_empty():
		push_error("uma escolha obrigatória não pode ser fechada")
		return false
	m.option_prompt["options"][0]["callback"].call()
	if m.targeting.get("kind") != "effect_choice" or not m._is_target(other.uid) or m._is_target(challenged.uid):
		push_error("o Tiro não ofereceu apenas os alvos válidos")
		return false
	m._cancel_targeting()
	m._render_now()
	if m.option_prompt.is_empty():
		push_error("cancelar a mira deve voltar à escolha")
		return false
	m.option_prompt["options"][0]["callback"].call()
	m._fire_target(other.uid)
	if other.damage != 4 or m.g.phase == "effect_choice":
		push_error("o Tiro escolhido pela UI não foi resolvido")
		return false
	await process_frame
	return true

func _check_activation_cost_choice_ui(m) -> bool:
	m._start(false, "fogo", "agua")
	m.pending_pass = false
	m.g.mulligan(0, [])
	m.g.mulligan(1, [])
	m.g.active = 0
	m.g.priority = 0
	m.g.phase = "main"
	m.g.players[0]["momentum"] = 3
	m.viewer = 0
	var drex := Card.new(m.g._uid(), "drex", 0, "board")
	var ally := Card.new(m.g._uid(), "geodo_vivo", 0, "board")
	drex.enter_board(false)
	ally.enter_board(false)
	m.g.players[0]["board"].append(drex)
	m.g.players[0]["board"].append(ally)
	m._open_activation_cost_prompt(drex.uid)
	if m.option_prompt["options"].size() != 2 or not m.option_prompt["options"][0]["enabled"] or not m.option_prompt["options"][1]["enabled"]:
		push_error("Drex: a janela não oferece ambos os custos")
		return false
	m._close_option_prompt()
	if not m.option_prompt.is_empty() or m.g.players[0]["momentum"] != 3:
		push_error("Drex: cancelar a janela não deve pagar o custo")
		return false
	m.g.players[0]["board"].erase(ally)
	m._open_activation_cost_prompt(drex.uid)
	if not m.option_prompt["options"][0]["enabled"] or m.option_prompt["options"][1]["enabled"]:
		push_error("Drex: sem outro aliado apenas descarte fica disponível")
		return false
	m._close_option_prompt()
	m.g.players[0]["board"].append(ally)
	m._open_activation_cost_prompt(drex.uid)
	m._render_now()
	var sacrifice_button: Button = null
	for node in m.layer.find_children("*", "Button", true, false):
		if node.text.begins_with("Sacrificar uma unidade"):
			sacrifice_button = node
			break
	if sacrifice_button == null:
		push_error("Drex: botão de sacrifício não foi renderizado")
		return false
	sacrifice_button.pressed.emit()
	if m.targeting.get("kind") != "unit_cost" or not m._is_target(ally.uid) or m._is_target(drex.uid):
		push_error("Drex: o sacrifício deve oferecer apenas outra unidade aliada")
		return false
	m._cancel_targeting()
	if m.g.players[0]["momentum"] != 3 or m.g.find_unit(ally.uid) == null:
		push_error("Drex: cancelar a mira não deve pagar o custo")
		return false
	m._open_activation_cost_prompt(drex.uid)
	m.option_prompt["options"][0]["callback"].call()
	if m.g.phase != "search" or not m.g.pending_search.get("discard_hand", false):
		push_error("Drex: o descarte deve abrir a escolha da mão")
		return false
	m.g.choose_search(0, 0)
	if m.g.players[0]["momentum"] != 3 or drex.activated_turn == m.g.turn:
		push_error("Drex: cancelar o descarte não deve ativar a habilidade")
		return false
	m.g.players[0]["hand"].clear()
	m._open_activation_cost_prompt(drex.uid)
	if m.option_prompt["options"][0]["enabled"] or not m.option_prompt["options"][1]["enabled"]:
		push_error("Drex: descarte indisponível e sacrifício disponível")
		return false
	m.option_prompt["options"][1]["callback"].call()
	m._fire_target(ally.uid)
	if m.g.find_unit(ally.uid) != null or m.g.players[0]["momentum"] != 2 or drex.activated_turn != m.g.turn:
		push_error("Drex: sacrifício deve pagar o custo e ativar")
		return false
	await process_frame
	return true

func _check_equipment_ui(m) -> bool:
	m._start(false, "fogo", "agua")
	m.pending_pass = false
	var tobias := Card.new(m.g._uid(), "sacoleiro_tobias_bolso_fundo", 0, "board")
	m.g.players[0]["board"].append(tobias)
	var fixture_ids := ["amuleto_do_primeiro_floco", "manoplas_incandescentes"]
	for index in 4:
		tobias.equipped_cards.append(Card.new(m.g._uid(), fixture_ids[index % fixture_ids.size()], 0, "equipped"))
	m._render()
	await process_frame
	var badge: Button = m.views.get("eqbadge%d" % tobias.uid)
	if badge == null:
		push_error("o indicador de equipamentos não foi renderizado (board=%d, equipamentos=%d, views=%s)" % [
			m.g.players[0]["board"].size(), tobias.equipped_cards.size(), m.views.keys()])
		return false
	if not badge.tooltip_text.contains(String(CardDB.card(fixture_ids[0])["name"])) \
			or not badge.tooltip_text.contains(String(CardDB.card(fixture_ids[1])["name"])):
		push_error("o tooltip não identifica os quatro equipamentos: %s" % badge.tooltip_text)
		return false
	var back_preview: CardView = m.views.get("eqpreview%d_0" % tobias.uid)
	var front_preview: CardView = m.views.get("eqpreview%d_1" % tobias.uid)
	if back_preview == null or front_preview == null \
			or not is_equal_approx(front_preview.position.y - back_preview.position.y, 6.0):
		push_error("a pilha deveria mostrar só duas cartas com uma borda traseira discreta")
		return false
	badge.pressed.emit()
	await process_frame
	var panel: PanelContainer = m.overlay.get_child(0)
	var content: VBoxContainer = panel.get_child(0)
	var grid: GridContainer = content.get_child(2).get_child(0)
	if grid.get_child_count() != 4:
		push_error("o inspetor deveria mostrar os quatro equipamentos")
		return false
	m._close_overlay()

	tobias.equipped_cards.clear()
	for index in 10:
		tobias.equipped_cards.append(Card.new(m.g._uid(), fixture_ids[index % fixture_ids.size()], 0, "equipped"))
	m._render()
	await process_frame
	badge = m.views.get("eqbadge%d" % tobias.uid)
	if badge == null or badge.text != "10 EQ." or not badge.tooltip_text.contains("e mais 6"):
		push_error("a UI não resumiu corretamente os dez equipamentos do Tobias")
		return false
	badge.pressed.emit()
	await process_frame
	panel = m.overlay.get_child(0)
	content = panel.get_child(0)
	grid = content.get_child(2).get_child(0)
	if grid.get_child_count() != 10 or panel.position.y < 0 or panel.position.y + panel.size.y > 1034.0:
		push_error("o inspetor não exibiu os dez equipamentos dentro da área da mesa")
		return false
	m._close_overlay()

	tobias.equipped_cards.clear()
	for index in 100:
		tobias.equipped_cards.append(Card.new(m.g._uid(), fixture_ids[index % fixture_ids.size()], 0, "equipped"))
	m._render()
	await process_frame
	badge = m.views.get("eqbadge%d" % tobias.uid)
	if badge == null or badge.text != "100 EQ." or not badge.tooltip_text.contains("e mais 96"):
		push_error("a UI não resumiu corretamente cem equipamentos do Tobias")
		return false
	badge.pressed.emit()
	await process_frame
	panel = m.overlay.get_child(0)
	content = panel.get_child(0)
	grid = content.get_child(2).get_child(0)
	if grid.get_child_count() != 100 or panel.position.y < 0 or panel.position.y + panel.size.y > 1034.0:
		push_error("o inspetor ultrapassou a área da mesa com cem equipamentos")
		return false
	var preview_count := 0
	for key in m.views:
		if str(key).begins_with("eqpreview%d_" % tobias.uid):
			preview_count += 1
	if preview_count != 2:
		push_error("o volume de cem equipamentos desenhou %d cartas de prévia, não duas" % preview_count)
		return false
	m._close_overlay()
	return true

func _check_field_equip_input(m) -> bool:
	var tap_state := _prepare_field_equip_match(m, "engrenagem_solta")
	var artifact: Card = tap_state["artifact"]
	var unit: Card = tap_state["unit"]
	var artifact_view: CardView = m.views[artifact.uid]
	var tap_position: Vector2 = artifact_view.get_global_transform_with_canvas() * (artifact_view.size / 2.0)
	_send_touch(m, artifact_view, 0, true, tap_position)
	_send_touch(m, artifact_view, 0, false, tap_position)
	if m.overlay == null:
		push_error("tocar no artefato solto não abriu suas ações")
		return false
	var equip_button: Button = null
	for node in m.overlay.find_children("*", "Button", true, false):
		if node.text.begins_with("Equipar"):
			equip_button = node
			break
	if equip_button == null:
		push_error("o artefato solto não ofereceu a ação Equipar")
		return false
	equip_button.pressed.emit()
	if m.targeting.get("kind") != "field_equip" or not m._is_target(unit.uid):
		push_error("Equipar não iniciou a seleção da unidade aliada")
		return false
	var unit_view: CardView = m.views[unit.uid]
	var unit_position: Vector2 = unit_view.get_global_transform_with_canvas() * (unit_view.size / 2.0)
	_send_touch(m, unit_view, 1, true, unit_position)
	_send_touch(m, unit_view, 1, false, unit_position)
	if m.g.stack.is_empty() or m.g.stack[-1]["kind"] != "artifact_equip" or m.g.stack[-1]["uid"] != artifact.uid:
		push_error("tocar na unidade não equipou o artefato do campo")
		return false
	if m.overlay != null:
		push_error("o toque de seleção abriu uma segunda interface inesperadamente")
		return false

	var drag_state := _prepare_field_equip_match(m, "cristal_do_poder")
	artifact = drag_state["artifact"]
	unit = drag_state["unit"]
	artifact_view = m.views[artifact.uid]
	unit_view = m.views[unit.uid]
	var source_position: Vector2 = artifact_view.get_global_transform_with_canvas() * (artifact_view.size / 2.0)
	unit_position = unit_view.get_global_transform_with_canvas() * (unit_view.size / 2.0)
	_send_touch(m, artifact_view, 2, true, source_position)
	_send_touch_drag(m, artifact_view, 2, unit_position)
	if m.targeting.get("kind") != "field_equip" or not m._is_target(unit.uid):
		push_error("arrastar o artefato não iniciou a mira de Equipar")
		return false
	_send_touch(m, artifact_view, 2, false, unit_position)
	if m.g.stack.is_empty() or m.g.stack[-1]["kind"] != "artifact_equip" or m.g.stack[-1]["uid"] != artifact.uid:
		push_error("soltar o artefato sobre a unidade não equipou")
		return false
	await process_frame
	return true

## A finger touching `view`, delivered the way Godot does it: Main's _input receives the position on
## the screen, while the card's own _gui_input receives it relative to the card (its top-left is 0, 0).
func _send_touch(m, view: CardView, finger: int, pressed: bool, screen_position: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = finger
	touch.pressed = pressed
	touch.position = screen_position
	m._input(touch)
	touch = touch.duplicate()
	touch.position = view.get_global_transform_with_canvas().affine_inverse() * screen_position
	view._gui_input(touch)

func _send_touch_drag(m, view: CardView, finger: int, screen_position: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = finger
	drag.position = screen_position
	m._input(drag)
	drag = drag.duplicate()
	drag.position = view.get_global_transform_with_canvas().affine_inverse() * screen_position
	view._gui_input(drag)

func _prepare_field_equip_match(m, artifact_id: String) -> Dictionary:
	m._start(false, "fogo", "agua")
	m.pending_pass = false
	m.g.mulligan(0, [])
	m.g.mulligan(1, [])
	m.g.active = 0
	m.g.priority = 0
	m.g.phase = "main"
	m.g.players[0]["momentum"] = 5
	m.g.auto_pass[1] = false
	var unit := Card.new(m.g._uid(), "geodo_vivo", 0, "board")
	m.g.players[0]["board"].append(unit)
	var artifact := Card.new(m.g._uid(), artifact_id, 0, "relics")
	m.g.players[0]["relics"].append(artifact)
	m.viewer = 0
	m._render()
	return {"artifact": artifact, "unit": unit}

## The player's own decks show up in the hub as the third section, and a match can start with one.
func _check_hub_with_own_deck(m) -> bool:
	var scratch_path := "user://smoke_hub_decks.json"
	DirAccess.remove_absolute(scratch_path)
	if m.deck_store != null:
		m.deck_store.queue_free()
	var store = load("res://scripts/net/deck_store.gd").new()
	store.use_web_storage = false
	store.allow_cloud = false # a saved Google session on this machine must not receive test decks
	store.local_path = scratch_path
	m._use_deck_store(store)
	var template: Dictionary = DeckDB.get_deck("fogo")
	store.save_deck("", "Meu fogo", template["leader"], template["cards"], "Cópia de teste")
	store.save_deck("", "Pela metade", template["leader"], {}, "") # incomplete: hidden from the hub
	m._show_menu()
	m._show_hub(true)
	await process_frame
	var own_ids: Array[String] = DeckDB.custom_ids(DeckDB.PLAYER_PREFIX)
	if own_ids.size() != 1 or DeckDB.get_deck(own_ids[0])["name"] != "Meu fogo" or m.incomplete_player_decks != 1:
		push_error("hub não registrou só o deck pronto do jogador (%s, incompletos %d)" % [own_ids, m.incomplete_player_decks])
		return false
	if m.HUB_SECTIONS[m.HUB_SECTIONS.size() - 1]["id"] != DeckDB.SECTION_MINE:
		push_error("MEUS DECKS não é a terceira seção do hub")
		return false
	if m.sel_deck.begins_with(DeckDB.PLAYER_PREFIX):
		push_error("a escolha padrão do hub deveria ser um deck pronto")
		return false
	m.sel_deck = own_ids[0]
	m._show_hub(true, "", true)
	await process_frame
	var play: Button = null
	for c in m.layer.get_children():
		if c is Button and c.text == "JOGAR":
			play = c
	if play == null:
		push_error("hub com deck próprio sem botão JOGAR")
		return false
	play.pressed.emit()
	if m.g == null or m.g.players[0]["leader_id"] != template["leader"]:
		push_error("partida não iniciou com o deck do jogador")
		return false
	# an online room delivers the decks' contents under "room:" ids; the client registers them before the match
	var room_deck_id := "room:TEST:0"
	m._register_room_decks({room_deck_id: {"name": "Sala", "description": "", "leader": template["leader"], "cards": template["cards"]}})
	if not DeckDB.has(room_deck_id):
		push_error("deck de sala não foi registrado")
		return false
	m._show_menu()
	if DeckDB.has(room_deck_id):
		push_error("deck de sala não foi limpo ao voltar ao menu")
		return false
	store.delete_deck(String(store.list()[0]["id"]))
	DirAccess.remove_absolute(scratch_path)
	return true

## "MEUS DECKS": open from the menu and leave, then create / edit / save / duplicate / delete a deck
## against a throwaway file so the player's real decks are never touched.
func _check_deck_builder(m) -> bool:
	m._show_menu()
	m._open_deck_builder()
	await process_frame
	if not is_instance_valid(m.deck_builder):
		push_error("MEUS DECKS não abriu")
		return false
	m.deck_builder.closed.emit()
	await process_frame
	if m.deck_builder != null:
		push_error("MEUS DECKS não limpou a referência ao fechar")
		return false

	var scratch_path := "user://smoke_decks.json"
	DirAccess.remove_absolute(scratch_path)
	# loaded at run time, not named as a type: scripts that use the autoloads (Sfx...) cannot be compiled
	# while this test script itself compiles, because autoloads are only added to the tree afterwards
	var builder = load("res://scripts/ui/deck_builder.gd").new()
	builder.local_deck_path = scratch_path
	m.layer.add_child(builder)
	await process_frame
	var cheap_artifact_id := ""
	var cheap_unit_id := ""
	for card_id in CardDB.data()["cards"]:
		var card: Dictionary = CardDB.card(String(card_id))
		if int(card.get("cost", 99)) != 2:
			continue
		if String(card.get("type", "")) == "artifact" and cheap_artifact_id == "":
			cheap_artifact_id = String(card_id)
		elif String(card.get("type", "")) == "unit" and cheap_unit_id == "":
			cheap_unit_id = String(card_id)
	if cheap_artifact_id == "" or cheap_unit_id == "":
		push_error("assistente de deck: catálogo precisa de artefato e unidade de custo 2 para testar aggro")
		return false
	builder._assistant_enabled = true
	builder._assistant_profile = "aggro"
	builder._assistant_focus = "board"
	builder._cards = {cheap_artifact_id: 16}
	var assistant_notes: Array[Dictionary] = builder._coach_notes()
	if not _assistant_notes_contain(assistant_notes, "poucas unidades de custo 0 a 2 (0)"):
		push_error("assistente de deck contou 16 artefatos como unidades baratas para aggro de mesa")
		return false
	builder._cards = {cheap_artifact_id: 8, cheap_unit_id: 8}
	assistant_notes = builder._coach_notes()
	if not _assistant_notes_contain(assistant_notes, "Só 8 unidades de custo 0 a 2"):
		push_error("assistente de deck não contou só as 8 unidades baratas entre 16 cartas")
		return false
	var template: Dictionary = DeckDB.get_deck("obscura_lento")
	builder._open_editor({"id": "", "name": "Deck de teste", "description": "", "leader": template["leader"], "cards": {}, "problems": []})
	await process_frame
	await process_frame # the card grid renders one frame later
	var added := 0
	for card_id in template["cards"]:
		if DeckDB.is_deckable(String(card_id)):
			builder._add_card(String(card_id))
			added += 1
			if added >= 6:
				break
	builder._remove_card(String(template["cards"].keys()[0]))
	builder._save()
	if builder._dirty or builder.store.list().size() != 1:
		push_error("MEUS DECKS não salvou o deck")
		return false
	var saved_deck: Dictionary = builder.store.list()[0]
	builder._back() # nothing unsaved: goes straight to the list
	await process_frame
	builder._duplicate(saved_deck)
	if builder.store.list().size() != 2:
		push_error("MEUS DECKS não duplicou o deck")
		return false
	for deck in builder.store.list():
		builder.store.delete_deck(String(deck["id"]))
	if not builder.store.list().is_empty():
		push_error("MEUS DECKS não excluiu os decks")
		return false
	builder.queue_free()
	await process_frame
	DirAccess.remove_absolute(scratch_path)
	return true

func _assistant_notes_contain(notes: Array[Dictionary], phrase: String) -> bool:
	for note in notes:
		if String(note["text"]).contains(phrase):
			return true
	return false
