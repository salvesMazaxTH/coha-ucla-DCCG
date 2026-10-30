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
	if not await _check_equipment_ui(m):
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
