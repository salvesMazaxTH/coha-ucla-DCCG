class_name TableOverlays
extends RefCounted
## The windows drawn over the table: card overlay, pause and concede menus, graveyard viewer and search reveal.
## Main (`host`) owns the table and the match state they read.
const HubGlyphIconScript = preload("res://scripts/ui/hub_glyph_icon.gd")
## Hash of the pending search the player folded away to look at the table (-1 = none). Comparing the
## hash instead of a flag means the next search always opens expanded.
var search_minimized_signature := -1
var search_opened_signature := -1 ## the opponent's choice the player asked to see (those start folded)
var grave_panel: PanelContainer
var grave_scroll: ScrollContainer
var grave_owner := 0
var grave_filter := "all"
var grave_drag_ms := -1000 ## last finger-drag in the viewer: taps right after it are not clicks
var search_scroll: ScrollContainer ## the one-row card strip of the open pick window (null when none)
var search_drag_ms := -1000 ## last scroll of that strip: taps and long-presses right after it are not picks
## A finger always trembles a little during a tap; it only counts as a swipe once it has travelled this far (screen pixels).
const SWIPE_START_DISTANCE := 14.0

var host


func _init(host_node) -> void:
	host = host_node


## " (agora: N)" for cards whose text counts something (Jeff: unit cards in the own graveyard), so the
## player can add it to the base stats; " (N/M)" for the Gigantes. Empty for the rest.
func scale_suffix(p: int, cd: Dictionary, card_id := "") -> String:
	# a "shared_x" card (Drex): the X grows during the match, so the overlay shows the current value
	if card_id != "" and cd.has("shared_x"):
		return " (X agora: %d)" % host.g.shared_x_of(p, card_id)
	var progress: Dictionary = host.g.window_progress(p, cd)
	if not progress.is_empty():
		# cost reductions that ask for an amount over a window (Gigantes): how far along, e.g. "(3/8)"
		return " (%d/%d)" % [progress["have"], progress["need"]]
	var n: int = host.g.scale_count(p, cd)
	return " (agora: %d)" % n if n >= 0 else ""


func show_equipment_collection(unit: Card, owner: int) -> void:
	if unit.equipped_cards.is_empty():
		return
	close_overlay()
	host.overlay = ColorRect.new()
	host.overlay.color = Color(0, 0, 0, 0.84)
	host.overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.overlay.gui_input.connect(_dismiss_overlay_on_input)
	host.add_child(host.overlay)

	var columns := mini(5, unit.equipped_cards.size())
	var gap := 12.0
	var card_scale := minf(1.0, (host.stage_w - 120.0 - gap * (columns - 1)) / (columns * CardView.BASE.x))
	var grid_width := columns * CardView.BASE.x * card_scale + gap * (columns - 1)
	var rows := ceili(float(unit.equipped_cards.size()) / columns)
	var grid_height := rows * CardView.BASE.y * card_scale + gap * (rows - 1)

	var panel := PanelContainer.new()
	var panel_style := UITheme.panel(14)
	panel_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.custom_minimum_size.x = grid_width + 48.0
	host.overlay.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	content.add_child(
		host.make_label(
			"EQUIPAMENTOS DE %s" % String(CardDB.card(unit.card_id).get("name", unit.card_id)),
			28,
			UITheme.GOLD_LIGHT,
			HORIZONTAL_ALIGNMENT_CENTER,
			"title_bold",
			5,
		)
	)
	content.add_child(
		host.make_label(
			"%d equipamento(s) · clique em uma carta para inspecionar" % unit.equipped_cards.size(),
			17,
			UITheme.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER,
			"body",
		)
	)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(grid_width, minf(grid_height, host.STAGE_H - 280.0))
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", int(gap))
	grid.add_theme_constant_override("v_separation", int(gap))
	scroll.add_child(grid)
	for worn: Card in unit.equipped_cards:
		var equipment_data := { "uid": worn.uid }
		if worn.durability_left() >= 0:
			equipment_data["durability_left"] = worn.durability_left()
		var card_view := CardView.new().setup(worn.card_id, equipment_data, card_scale)
		card_view.snowball_level = int(host.g.players[owner]["snowball"])
		card_view.left_clicked.connect(show_overlay)
		card_view.right_clicked.connect(show_overlay)
		grid.add_child(card_view)

	var close_button: Button = host.make_button("FECHAR", close_overlay)
	close_button.custom_minimum_size = Vector2(grid_width, 44)
	content.add_child(close_button)
	panel.reset_size()
	panel.position = (Vector2(host.stage_w, host.STAGE_H) - panel.size) / 2.0


func _dismiss_overlay_on_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		close_overlay()


func show_overlay(v: CardView) -> void:
	if v.face_down:
		return
	close_overlay()
	var cd := CardDB.card_for(v.card_id, v.inst)
	host.overlay = ColorRect.new()
	host.overlay.color = Color(0, 0, 0, 0.82)
	host.overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# above board badges (the "N EQ." tag uses z 20) and flying card ghosts (up to 30)
	host.overlay.z_index = 45
	host.overlay.gui_input.connect(
		func(e):
			if e is InputEventMouseButton and e.pressed:
				close_overlay(),
	)
	host.add_child(host.overlay)
	# the big card and the full text are built by CardOverlay (tools/view_card.gd shows the same thing)
	var rt_x := CardOverlay.build(
		host.overlay,
		host.stage_w,
		v.card_id,
		v.inst,
		v.cost_override,
		v.text_suffix,
		v.snowball_level,
		v.text_bonuses,
	)
	_add_base_card_button(v.card_id)
	_add_full_art_button(String(cd.get("art", "")))
	var show_activate: bool = cd.has("activated") and host.g != null and host.viewer_can_act() and host.g.can_activate(
			host.viewer,
			v.uid,
			true,
		)
	var show_field_equip: bool = cd.has("equip_from_field") and host.g != null and host.viewer_can_act() and host.g.can_equip_from_field(
			host.viewer,
			v.uid,
			true,
		)
	var action_count := int(show_activate) + int(show_field_equip)
	var action_width := 520.0 if action_count < 2 else 250.0
	var action_index := 0
	if show_activate:
		var ab: Dictionary = cd["activated"]
		var ab_uid := v.uid
		var ab_btn: Button = host.make_button(
			"Ativar (%d)" % int(ab["cost"]),
			func():
				close_overlay()
				# during an animation the activation waits for it to end (and checks again that it is still allowed)
				host.run_or_queue_input(
					func():
						if not host.viewer_can_act() or not host.g.can_activate(host.viewer, ab_uid, true):
							return
						if ab.has("extra_cost"):
							# the extra cost (discard a card or sacrifice an ally) is chosen first, in a two-block window
							host.open_activation_cost_prompt(ab_uid)
							return
						var spec: String = host.g.target_spec(ab["effects"])
						if spec == "":
							host.handle_action_result(host.g.activate(host.viewer, ab_uid, 0))
						else:
							host.targeting = { "kind": "unit_ability", "uid": ab_uid, "spec": spec }
							if host.views.has(ab_uid) and is_instance_valid(host.views[ab_uid]):
								host.begin_aim(host.visual_rect_of(host.views[ab_uid] as Control).get_center())
							host.render_table(),
				),
			true,
		)
		ab_btn.position = Vector2(rt_x + action_index * (action_width + 20.0), 820.0 + host.BOT)
		ab_btn.custom_minimum_size = Vector2(action_width, 96)
		host.overlay.add_child(ab_btn)
		action_index += 1
	if show_field_equip:
		var equip_uid := v.uid
		var equip_action: Dictionary = cd["equip_from_field"]
		var equip_btn: Button = host.make_button(
			"Equipar (%d)" % int(equip_action["cost"]),
			func():
				close_overlay()
				host.run_or_queue_input(
					func():
						if not host.viewer_can_act() or not host.g.can_equip_from_field(host.viewer, equip_uid, true):
							return
						var spec: String = host.g.target_spec(equip_action["effects"])
						if spec == "":
							return
						host.targeting = { "kind": "field_equip", "uid": equip_uid, "spec": spec }
						if host.views.has(equip_uid) and is_instance_valid(host.views[equip_uid]):
							host.begin_aim(host.visual_rect_of(host.views[equip_uid] as Control).get_center())
						host.render_table(),
				),
			true,
		)
		equip_btn.position = Vector2(rt_x + action_index * (action_width + 20.0), 820.0 + host.BOT)
		equip_btn.custom_minimum_size = Vector2(action_width, 96)
		host.overlay.add_child(equip_btn)
	if host.g != null and host.viewer_can_act() and requiem_uids(host.viewer).has(v.uid):
		# a Réquiem spell opened from the graveyard viewer: cast it from here (it is banished afterwards)
		var requiem_uid := v.uid
		var requiem_card_id := v.card_id
		var requiem_btn: Button = host.make_button(
			"Lançar Réquiem (%d)" % v.cost_override,
			func():
				close_overlay()
				close_graveyard()
				host.cast_requiem(requiem_uid, requiem_card_id),
			true,
		)
		requiem_btn.position = Vector2(rt_x, 820.0 + host.BOT)
		requiem_btn.custom_minimum_size = Vector2(520, 96)
		host.overlay.add_child(requiem_btn)
	if cd.has("transform") and host.g != null and host.viewer_can_act() and host.g.can_transform(host.viewer, v.uid):
		var tb: Button = host.make_button(
			"Transformar (%d)" % int(cd["transform"]["cost"]),
			func():
				close_overlay()
				host.handle_action_result(host.g.transform(host.viewer, v.uid)),
			true,
		)
		tb.position = Vector2(rt_x, 820.0 + host.BOT)
		tb.custom_minimum_size = Vector2(520, 96)
		host.overlay.add_child(tb)


## An eye button above the big card in the overlay: while it is held, the card and its text are shown as
## printed (no buffs, debuffs, markers or resets); letting go brings the live card back.
func _add_base_card_button(card_id: String) -> void:
	# call right after CardOverlay.build: the text panel is the overlay's last child at this point
	var text_panel := host.overlay.get_child(host.overlay.get_child_count() - 1) as RichTextLabel
	var live_text := text_panel.text
	var printed_text := CardOverlay.describe(card_id, { }, -1, "", GameState.SNOWBALL_BASE_LEVEL)
	# the printed card has no buffs or debuffs, so the Modificadores column hides while it shows
	var modifiers_panel := host.overlay.get_node_or_null(CardOverlay.StatModifiersPanel.NODE_NAME) as Control
	var card_scale := CardOverlay.big_card_scale(host.stage_w, modifiers_panel != null)
	var base_card := CardOverlay.build_base_card(host.overlay, host.stage_w, card_id, card_scale)
	var button_size := Vector2(CardView.BASE.x * card_scale, 84.0)
	var button := Button.new()
	button.custom_minimum_size = button_size
	button.size = button_size
	button.position = Vector2(CardOverlay.big_card_position(host.stage_w, card_scale).x, CardOverlay.BIG_CARD_Y - button_size.y - 16.0)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Segure para ver a carta como foi impressa."
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(56.0, button_size.y / 2.0)
	icon.draw.connect(
		func():
			# an eye: two lens-shaped lids around a round pupil
			var upper_lid := PackedVector2Array()
			var lower_lid := PackedVector2Array()
			for step in range(-10, 11):
				var across := step / 10.0
				var lid_height := 15.0 * (1.0 - across * across)
				upper_lid.append(Vector2(across * 26.0, -lid_height))
				lower_lid.append(Vector2(across * 26.0, lid_height))
			icon.draw_polyline(upper_lid, UITheme.GOLD_LIGHT, 3.0)
			icon.draw_polyline(lower_lid, UITheme.GOLD_LIGHT, 3.0)
			icon.draw_circle(Vector2.ZERO, 8.0, UITheme.GOLD_LIGHT),
	)
	button.add_child(icon)
	var caption: Label = host.make_label("Segure: ver carta base", 26, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "bold")
	caption.position = Vector2(104.0, 0.0)
	caption.size = Vector2(button_size.x - 120.0, button_size.y)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(caption)
	button.button_down.connect(
		func():
			base_card.visible = true
			text_panel.text = printed_text
			if modifiers_panel != null:
				modifiers_panel.visible = false,
	)
	button.button_up.connect(
		func():
			base_card.visible = false
			text_panel.text = live_text
			if modifiers_panel != null:
				modifiers_panel.visible = true,
	)
	host.overlay.add_child(button)


## A picture-icon button next to the "ver carta base" one: opens the card's art alone, full screen.
func _add_full_art_button(art_file: String) -> void:
	if art_file == "":
		return
	var button_size := Vector2(84.0, 84.0)
	var button := Button.new()
	button.custom_minimum_size = button_size
	button.size = button_size
	button.position = Vector2(
		CardOverlay.big_card_position(host.stage_w).x + CardView.BASE.x * CardOverlay.BIG_CARD_SCALE + 28.0,
		CardOverlay.BIG_CARD_Y - button_size.y - 16.0,
	)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Ver a arte em tela cheia."
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = button_size / 2.0
	icon.draw.connect(
		func():
			# the universal "image" icon: a frame holding a sun and two mountains
			icon.draw_rect(Rect2(-28.0, -22.0, 56.0, 44.0), UITheme.GOLD_LIGHT, false, 3.0)
			icon.draw_circle(Vector2(-12.0, -8.0), 5.0, UITheme.GOLD_LIGHT)
			icon.draw_colored_polygon(
				PackedVector2Array(
					[Vector2(-26.0, 20.0), Vector2(-6.0, -2.0), Vector2(6.0, 10.0), Vector2(14.0, 2.0), Vector2(26.0, 20.0)]
				),
				UITheme.GOLD_LIGHT,
			),
	)
	button.add_child(icon)
	button.pressed.connect(
		func():
			_show_full_art(art_file),
	)
	host.overlay.add_child(button)


## The raw art on a black screen covering the whole window (not just the stage), fitted whole with no crop,
## frame, badges or seals. A click, a tap or Esc closes it and goes back to the card overlay.
func _show_full_art(art_file: String) -> void:
	var viewer := ColorRect.new()
	viewer.color = Color.BLACK
	var window_size: Vector2 = host.get_viewport().get_visible_rect().size
	viewer.position = -host.position # Main sits centered inside the window; this puts the viewer at the window's corner
	viewer.size = window_size
	viewer.focus_mode = Control.FOCUS_ALL
	viewer.gui_input.connect(
		func(e):
			var clicked: bool = e is InputEventMouseButton and e.pressed
			var escaped: bool = e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE
			if clicked or escaped:
				viewer.accept_event()
				viewer.queue_free(),
	)
	var art := TextureRect.new()
	art.texture = CardView.raw_art_texture(art_file)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewer.add_child(art)
	host.overlay.add_child(viewer)
	viewer.grab_focus()


func close_overlay() -> void:
	if host.overlay == null:
		return
	var old_overlay = host.overlay
	host.overlay = null
	# Detach immediately; queue_free alone keeps the modal in the scene tree until the end of the
	# frame, which is exactly the visual glitch seen when a render happens during the overlay.
	if is_instance_valid(old_overlay) and old_overlay.get_parent() != null:
		old_overlay.get_parent().remove_child(old_overlay)
	old_overlay.queue_free()

# ---------------------------------------------------------------- concede


## Confirmation before giving up; a persistent child of Main so re-renders (AI/opponent moves) don't dismiss it.
func ask_concede() -> void:
	ask_confirm("CONCEDER A PARTIDA?", "O oponente vence na hora.", "CONCEDER", "CONTINUAR JOGANDO", _confirm_concede)


## Generic yes/no dialog (same persistent slot as the concede one).
func ask_confirm(title: String, text: String, yes_label: String, no_label: String, on_yes: Callable) -> void:
	if host.g == null or host.g.phase == "over" or host.concede_view:
		return
	var box := _open_modal_box(title)
	box.add_child(host.make_label(text, 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var yes: Button = host.make_button(yes_label, on_yes, true)
	yes.custom_minimum_size = Vector2(460, 54)
	box.add_child(yes)
	var no: Button = host.make_button(no_label, close_concede)
	no.custom_minimum_size = Vector2(460, 48)
	box.add_child(no)
	_center_modal(box)


## Opens the dimmed full-screen modal in the persistent `concede_view` slot and returns the empty
## column (already holding the gold title) for the caller to fill; call `_center_modal(box)` when done.
func _open_modal_box(title: String) -> VBoxContainer:
	host.concede_view = Control.new()
	host.concede_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.concede_view.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.concede_view.add_child(dim)
	var pc := PanelContainer.new()
	var sb := UITheme.panel(14)
	sb.set_content_margin_all(36)
	sb.border_color = Color(UITheme.GOLD, 0.6)
	sb.shadow_size = 40
	pc.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 14)
	pc.add_child(box)
	box.add_child(host.make_label(title, 34, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6))
	host.concede_view.add_child(pc)
	return box


func _center_modal(box: VBoxContainer) -> void:
	var pc: Control = box.get_parent()
	host.add_child(host.concede_view)
	pc.reset_size()
	pc.position = (Vector2(host.stage_w, host.STAGE_H) - pc.size) / 2.0
	host.center_in_screen.call_deferred(pc)


## The in-game menu: settings and the ways out, without leaving the match. Same persistent slot as the
## confirmations, so opponent moves and re-renders don't close it.
func open_pause_menu() -> void:
	if host.g == null or host.concede_view:
		return
	var box := _open_modal_box("MENU")
	# the controls are rebuilt after a toggle so the switch is redrawn in its new position
	var reopen := func():
		close_concede()
		open_pause_menu.call_deferred()
	var volume_control: Control = host.make_volume_slider(Vector2(460, 52))
	box.add_child(volume_control)
	var sound_toggle: Button = host.make_toggle_button(
		"SOM",
		Sfx.is_enabled(),
		func():
			Sfx.set_enabled(not Sfx.is_enabled())
			reopen.call(),
	)
	sound_toggle.custom_minimum_size = Vector2(460, 52)
	box.add_child(sound_toggle)
	# the music has its own volume and switch, apart from the sound effects
	var music_volume_control: Control = host.make_volume_slider(Vector2(460, 52), true)
	box.add_child(music_volume_control)
	var music_toggle: Button = host.make_toggle_button(
		"MÚSICA",
		Music.is_enabled(),
		func():
			Music.set_enabled(not Music.is_enabled())
			reopen.call(),
	)
	music_toggle.custom_minimum_size = Vector2(460, 52)
	box.add_child(music_toggle)
	var fullscreen_button: Button = host.make_button("Tela cheia (F11)", host.toggle_fullscreen)
	fullscreen_button.custom_minimum_size = Vector2(460, 48)
	box.add_child(fullscreen_button)
	var continue_button: Button = host.make_button("CONTINUAR JOGANDO", close_concede, true)
	continue_button.custom_minimum_size = Vector2(460, 54)
	box.add_child(continue_button)
	var concede_button: Button = host.make_button(
		"Conceder",
		func():
			close_concede()
			ask_concede(),
	)
	concede_button.custom_minimum_size = Vector2(460, 48)
	box.add_child(concede_button)
	var leave_button: Button = host.make_button(
		"Sair para o menu principal",
		func():
			close_concede()
			_ask_leave_match(),
	)
	leave_button.custom_minimum_size = Vector2(460, 48)
	box.add_child(leave_button)
	_center_modal(box)


## Confirmation before leaving the table for the main menu (the only way out that isn't a concede).
func _ask_leave_match() -> void:
	if host.g == null or host.g.phase == "over": # the match ended while the menu was open: nothing left to lose
		host.menu_screens.show_menu()
		return
	var consequence := "A partida online continua salva: você pode retomá-la pelo lobby online." if host.online \
			else "Esta partida será perdida."
	ask_confirm("SAIR PARA O MENU?", consequence, "SAIR PARA O MENU", "VOLTAR AO JOGO", host.menu_screens.show_menu)


func close_concede() -> void:
	if host.concede_view:
		host.concede_view.queue_free()
		host.concede_view = null


func _confirm_concede() -> void:
	close_concede()
	if host.g == null or host.g.phase == "over":
		return
	host.handle_action_result(host.g.concede(host.viewer))

# ---------------------------------------------------------------- graveyard viewer

const GRAVE_FILTERS := [["all", "TODAS"], ["unit", "UNIDADES"], ["spell", "FEITIÇOS"], ["artifact", "ARTEFATOS"]]


## Persistent viewer (survives re-renders) for either player's graveyard, newest card first.
func show_graveyard(p: int) -> void:
	if host.grave_view and grave_owner == p:
		close_graveyard()
		return
	close_graveyard()
	grave_owner = p
	grave_filter = "requiem" if requiem_uids(p).size() > 0 else "all" # the glow on the icon promised a castable card in here
	host.grave_view = Control.new()
	host.grave_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.grave_view.mouse_filter = Control.MOUSE_FILTER_STOP
	host.grave_view.gui_input.connect(
		func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				close_graveyard(),
	)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.grave_view.add_child(dim)
	var pc := PanelContainer.new()
	var sb := UITheme.panel(14)
	sb.set_content_margin_all(28)
	sb.set_border_width_all(2)
	sb.border_color = Color(UITheme.GOLD, 0.6)
	sb.shadow_size = 40
	sb.bg_color = Color("#0e0c14", 0.97)
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.custom_minimum_size = Vector2(minf(host.stage_w - 80.0, 1180.0), 800)
	pc.size = pc.custom_minimum_size
	pc.position = (Vector2(host.stage_w, host.STAGE_H) - pc.size) / 2.0
	host.grave_view.add_child(pc)
	grave_panel = pc
	host.add_child(host.grave_view)
	refresh_graveyard()


func close_graveyard() -> void:
	if host.grave_view:
		host.grave_view.queue_free()
		host.grave_view = null
		grave_scroll = null
		grave_panel = null


## Uids of the Réquiem spells the viewer can cast from the own graveyard right now (empty for the opponent's).
func requiem_uids(p: int) -> Array:
	var uids: Array = []
	if p != host.viewer or host.is_ai(p) or host.g.phase not in ["main", "combat"]:
		return uids
	for requiem_card: Card in host.g.requiem_cards(p):
		uids.append(requiem_card.uid)
	return uids


## Rebuilds the panel contents (on open, filter change and after every _render).
func refresh_graveyard() -> void:
	if not host.grave_view or not is_instance_valid(host.grave_view):
		return
	var keep := grave_scroll.scroll_vertical if grave_scroll and is_instance_valid(grave_scroll) else 0
	for c in grave_panel.get_children():
		grave_panel.remove_child(c)
		c.queue_free()
	var entries: Array = host.g.players[grave_owner]["graveyard"].duplicate()
	entries.reverse() # newest first
	var castable_uids := requiem_uids(grave_owner)
	var counts := { "all": entries.size(), "unit": 0, "spell": 0, "artifact": 0, "requiem": castable_uids.size() }
	for grave_card: Card in entries:
		var grave_data := CardDB.card(grave_card.card_id)
		counts[grave_data["type"]] += 1
		if CardDB.is_unit_artifact(grave_data):
			counts["artifact"] += 1 # a unit-artifact is listed under both Unidades and Artefatos
	if grave_filter == "requiem" and castable_uids.is_empty():
		grave_filter = "all" # nothing castable anymore (Momentum spent, priority passed)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	grave_panel.add_child(box)

	# header: title + owner, close button
	var head := HBoxContainer.new()
	box.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	head.add_child(titles)
	titles.add_child(host.make_label("CEMITÉRIO", 34, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "title_bold", 6))
	var whose := "Seu cemitério" if grave_owner == host.viewer and not host.is_ai(grave_owner) else "Cemitério de %s" % host.player_name(
		grave_owner
	)
	var n := entries.size()
	var grave_owner_leader_name: String = CardDB.leader(host.g.players[grave_owner]["leader_id"])["name"]
	titles.add_child(
		host.make_label(
			"%s · %s · %d %s" % [whose, grave_owner_leader_name, n, "carta" if n == 1 else "cartas"],
			17,
			UITheme.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_LEFT,
			"body",
		)
	)
	var close: Button = host.make_button("", close_graveyard)
	close.custom_minimum_size = Vector2(52, 48)
	HubGlyphIconScript.attach_to_button(close, HubGlyphIconScript.Kind.CLOSE, 22.0, UITheme.TEXT, "center")
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(close)
	var rule := ColorRect.new()
	rule.color = Color(UITheme.GOLD, 0.3)
	rule.custom_minimum_size = Vector2(0, 2)
	box.add_child(rule)

	# filter tabs with counts
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	var filters: Array = GRAVE_FILTERS.duplicate()
	if not castable_uids.is_empty():
		filters.push_front(["requiem", "RÉQUIEM"])
	for f in filters:
		var fid: String = f[0]
		var b: Button = host.make_button(
			"%s  %d" % [f[1], counts[fid]],
			func():
				grave_filter = fid
				refresh_graveyard(),
			grave_filter == fid,
		)
		b.custom_minimum_size = Vector2(0, 44)
		b.disabled = counts[fid] == 0 and fid != "all"
		tabs.add_child(b)

	# card grid
	var shown: Array = entries
	if grave_filter == "requiem":
		shown = entries.filter(
			func(grave_card: Card):
				return castable_uids.has(grave_card.uid),
		)
	elif grave_filter != "all":
		shown = entries.filter(
			func(grave_card: Card):
				return CardDB.has_type(CardDB.card(grave_card.card_id), grave_filter),
		)
	if shown.is_empty():
		var empty := VBoxContainer.new()
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.add_theme_constant_override("separation", 8)
		empty.add_child(host.make_label("☠", 72, Color(UITheme.TEXT, 0.25), HORIZONTAL_ALIGNMENT_CENTER))
		empty.add_child(
			host.make_label(
				"Nenhuma carta aqui." if entries.is_empty() else "Nenhuma carta deste tipo.",
				24,
				UITheme.TEXT_DIM,
				HORIZONTAL_ALIGNMENT_CENTER,
				"title",
			)
		)
		box.add_child(empty)
		grave_scroll = null
	else:
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(sc)
		var grid := GridContainer.new()
		grid.columns = maxi(1, int((grave_panel.custom_minimum_size.x - 72.0) / 146.0))
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 14)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(grid)
		for grave_card: Card in shown:
			var cv := CardView.new().setup(grave_card.card_id, host.display_instance_for_card(grave_card), 1.1)
			cv.snowball_level = int(host.g.players[grave_owner]["snowball"])
			cv.text_suffix = scale_suffix(grave_owner, CardDB.card(grave_card.card_id), grave_card.card_id)
			if grave_owner == host.viewer and host.g.is_requiem(grave_card):
				# Réquiem shows what it costs from here (base + 2) and glows when it can be cast now
				cv.cost_override = host.g.cost_of(host.viewer, CardDB.card(grave_card.card_id), grave_card)
				if castable_uids.has(grave_card.uid):
					cv.highlight = host.OK
			cv.left_clicked.connect(_grave_card_click)
			cv.right_clicked.connect(_grave_card_click)
			grid.add_child(cv)
		grave_scroll = sc
		_restore_scroll.call_deferred(sc, keep)
	host.grave_view.move_to_front()
	if host.overlay:
		host.overlay.move_to_front()


func _grave_card_click(v: CardView) -> void:
	if Time.get_ticks_msec() - grave_drag_ms > 250:
		show_overlay(v)


func _restore_scroll(sc: ScrollContainer, v: int) -> void:
	if is_instance_valid(sc):
		sc.scroll_vertical = v


## Wheel and finger-drag scrolling: the cards swallow those events before the ScrollContainer sees them.
func grave_scroll_input(e: InputEvent) -> bool:
	if not grave_scroll or not is_instance_valid(grave_scroll) or host.overlay:
		return false
	var xf := grave_scroll.get_global_transform_with_canvas()
	var local: Vector2 = xf.affine_inverse() * e.position if "position" in e else Vector2(-1, -1)
	if not Rect2(Vector2.ZERO, grave_scroll.size).has_point(local):
		return false
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		grave_scroll.scroll_vertical += (-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1) * 120
		return true
	if e is InputEventScreenDrag:
		if not _finger_is_swiping(e):
			return false # still a tap: the card under the finger must get it
		grave_scroll.scroll_vertical -= int(e.relative.y / xf.get_scale().y)
		grave_drag_ms = Time.get_ticks_msec()
		return true
	return false


const SEARCH_MAX_CARD_SCALE := 1.835 ## few cards: they are shown at most this big (1.0 = a card on the table)
const SEARCH_SIDE_ROOM := 160.0 ## stage width kept free around the cards (panel margins and borders)
const SEARCH_VERTICAL_ROOM := 440.0 ## stage height kept free for title, texts, scrollbar, deck map and buttons
const SEARCH_CARD_GAP := 12.0 ## space between two cards of the strip
const SEARCH_ROW_MARGIN := 10.0 ## space around the strip, so a glowing card is not cut at the edges
const SEARCH_SCROLLBAR_HEIGHT := 16.0
const SEARCH_DRAG_CLICK_GUARD_MSEC := 250 ## taps this soon after a scroll are not picks


## True right after the strip was scrolled (finger swipe, wheel, arrow): the tap that ends a swipe must not pick a card.
func _search_just_scrolled() -> bool:
	return Time.get_ticks_msec() - search_drag_ms < SEARCH_DRAG_CLICK_GUARD_MSEC


## True once the finger of the current touch has moved far enough to be a swipe, not a trembling tap.
## Without this, the tiny drag of every real tap on a phone was taken as a scroll and the tap was thrown away.
func _finger_is_swiping(drag: InputEventScreenDrag) -> bool:
	if not host.finger_is_swiping and drag.position.distance_to(host.finger_press_position) > SWIPE_START_DISTANCE:
		host.finger_is_swiping = true
	return host.finger_is_swiping


## Wheel and finger-drag scrolling of the pick window's strip: the cards swallow those events before the ScrollContainer sees them.
func search_scroll_input(e: InputEvent) -> bool:
	if not is_instance_valid(search_scroll) or host.overlay:
		return false
	if (
		e is InputEventMouseButton and e.pressed
		and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	):
		var forward: bool = e.button_index == MOUSE_BUTTON_WHEEL_DOWN or e.button_index == MOUSE_BUTTON_WHEEL_RIGHT
		search_scroll.scroll_horizontal += int(search_scroll.get_meta("wheel_step", 120)) * (1 if forward else -1)
		search_drag_ms = Time.get_ticks_msec()
		return true
	if e is InputEventScreenDrag:
		var xf := search_scroll.get_global_transform_with_canvas()
		var local: Vector2 = xf.affine_inverse() * e.position
		if not Rect2(Vector2.ZERO, search_scroll.size).has_point(local):
			return false
		if not _finger_is_swiping(e):
			return false # still a tap: the card under the finger must get it (a pick may be mandatory)
		search_scroll.scroll_horizontal -= int(e.relative.x / xf.get_scale().x)
		search_drag_ms = Time.get_ticks_msec()
		return true
	return false


## Gold themed bars for the pick window's strip.
func _style_search_scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_h_scroll_bar()
	bar.custom_minimum_size.y = SEARCH_SCROLLBAR_HEIGHT
	bar.add_theme_stylebox_override("scroll", UITheme.box(Color(1, 1, 1, 0.10), 8))
	bar.add_theme_stylebox_override("grabber", UITheme.box(Color(UITheme.GOLD, 0.75), 8))
	bar.add_theme_stylebox_override("grabber_highlight", UITheme.box(UITheme.GOLD_LIGHT, 8))
	bar.add_theme_stylebox_override("grabber_pressed", UITheme.box(UITheme.GOLD_LIGHT, 8))


## Tells the player where the cards that glow are when the strip is wider than the screen: pulsing gold arrows
## at both edges (with how many glowing cards hide on that side; a tap jumps to the nearest one) and a map of the
## whole strip below it (gold ticks = glowing cards, outlined box = what is on screen; a tap jumps there).
## `deck_ends` labels the map TOPO / FUNDO (the strip shows the deck in its order, top first).
func _add_search_scroll_guides(
	box: VBoxContainer,
	stage: Control,
	scroll: ScrollContainer,
	eligible_flags: Array[bool],
	card_stride: float,
	card_width: float,
	viewport_width: float,
	deck_ends: bool,
) -> void:
	var strip_width := (viewport_width - 2.0 * SEARCH_ROW_MARGIN) # card_row width + margins is the scrolled content
	var content_width := eligible_flags.size() * card_stride - SEARCH_CARD_GAP + 2.0 * SEARCH_ROW_MARGIN
	var nearest := { "left": -1, "right": -1 } # index of the closest glowing card hidden on each side
	var arrow_size := Vector2(120, 64)
	var arrows := { }
	for side in ["left", "right"]:
		var arrow: Button = host.make_button(
			"",
			func():
				_scroll_search_to_card(scroll, nearest[side], card_stride, card_width, viewport_width),
			true,
		)
		arrow.custom_minimum_size = arrow_size
		arrow.size = arrow_size
		arrow.position = Vector2(
			8.0 if side == "left" else viewport_width - arrow_size.x - 8.0,
			(stage.custom_minimum_size.y - arrow_size.y) / 2.0,
		)
		arrow.add_theme_font_size_override("font_size", 26)
		# the arrow is drawn with shapes (the web font on phones lacks the arrow characters); the button text is only the count
		HubGlyphIconScript.attach_to_button(
			arrow,
			HubGlyphIconScript.Kind.ARROW_LEFT if side == "left" else HubGlyphIconScript.Kind.ARROW_RIGHT,
			22.0,
			UITheme.TEXT,
			side,
			14.0,
		)
		arrow.visible = false
		stage.add_child(arrow)
		var pulse := arrow.create_tween().set_loops()
		pulse.tween_property(arrow, "modulate", Color(1.55, 1.3, 0.75), 0.5)
		pulse.tween_property(arrow, "modulate", Color.WHITE, 0.5)
		arrows[side] = arrow
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 10)
	map_row.alignment = BoxContainer.ALIGNMENT_CENTER
	if deck_ends:
		map_row.add_child(host.make_label("TOPO", 16, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT, "bold"))
	var map := Control.new()
	map.custom_minimum_size = Vector2(maxf(120.0, strip_width - (170.0 if deck_ends else 0.0)), 28)
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map_row.add_child(map)
	if deck_ends:
		map_row.add_child(host.make_label("FUNDO", 16, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "bold"))
	box.add_child(map_row)
	map.draw.connect(
		func():
			var width := map.size.x
			map.draw_rect(Rect2(0, 10, width, 8), Color(1, 1, 1, 0.12))
			for index in eligible_flags.size():
				if eligible_flags[index]:
					var tick_x := (SEARCH_ROW_MARGIN + index * card_stride + card_width / 2.0) / content_width * width
					map.draw_rect(Rect2(tick_x - 3.0, 2, 6, 24), UITheme.GOLD_LIGHT)
			var seen_left := scroll.scroll_horizontal / content_width * width
			map.draw_rect(Rect2(seen_left, 4, viewport_width / content_width * width, 20), Color(UITheme.GOLD, 0.9), false, 2.0),
	)
	map.gui_input.connect(
		func(event: InputEvent):
			var pressing: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
			var dragging: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
			if pressing or dragging:
				scroll.scroll_horizontal = int(event.position.x / map.size.x * content_width - viewport_width / 2.0)
				search_drag_ms = Time.get_ticks_msec(),
	)
	var refresh := func():
		var seen_from: float = scroll.scroll_horizontal
		var counts := { "left": 0, "right": 0 }
		nearest["left"] = -1
		nearest["right"] = -1
		for index in eligible_flags.size():
			if not eligible_flags[index]:
				continue
			var card_left := SEARCH_ROW_MARGIN + index * card_stride
			if card_left + card_width <= seen_from + 4.0:
				counts["left"] += 1
				nearest["left"] = index # the last one found is the closest to the screen
			elif card_left >= seen_from + viewport_width - 4.0:
				counts["right"] += 1
				if nearest["right"] == -1:
					nearest["right"] = index
		for side in ["left", "right"]:
			var arrow: Button = arrows[side]
			arrow.visible = counts[side] > 0
			arrow.text = str(counts[side])
		map.queue_redraw()
	scroll.get_h_scroll_bar().value_changed.connect(
		func(_value):
			refresh.call(),
	)
	refresh.call()


## Slides the strip so card number `index` is centered; a short glide, so the player sees what was skipped.
func _scroll_search_to_card(scroll: ScrollContainer, index: int, card_stride: float, card_width: float, viewport_width: float) -> void:
	if index < 0 or not is_instance_valid(scroll):
		return
	search_drag_ms = Time.get_ticks_msec()
	var target := int(SEARCH_ROW_MARGIN + index * card_stride - (viewport_width - card_width) / 2.0)
	scroll.create_tween().tween_property(scroll, "scroll_horizontal", maxi(target, 0), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(
		Tween.EASE_OUT
	)


func render_search_reveal() -> void:
	if host.g.pending_search.is_empty():
		return
	var owner: int = host.g.decider()
	var look: bool = host.g.pending_search.get("look", false)
	# a private look is face up only for its owner (online, the server already masks the cards)
	var discard_hand: bool = host.g.pending_search.get("discard_hand", false)
	var hand_summon: bool = host.g.pending_search.get("hand_summon", false)
	var hand_bottom: bool = host.g.pending_search.get("hand_bottom", false)
	var own_hand_bottom: bool = host.g.pending_search.get("own_hand_bottom", false)
	var hidden: bool = (look or discard_hand or hand_summon or hand_bottom or own_hand_bottom) and not host.viewer_can_act()
	# the options of a deck search are shown only to the searcher; the opponent just sees that a search is happening
	var deck_search: bool = host.g.pending_search.get("deck_search", false)
	var secret_search: bool = deck_search and not host.viewer_can_act()
	var summoning: bool = host.g.pending_search.get("summon_from", false) # "summon_from": a free summon from the deck, hand or graveyard
	var sacrifice_pick: bool = host.g.pending_search.get("sacrifice_pick", false) # Censo de Baixas: a public pick among units on the board
	var reservoir_pick: bool = host.g.pending_search.get("reservoir_pick", false) # Agiota: the top card or the unseen bottom card goes to the Reservoir
	var title := "BUSCA NO DECK"
	if sacrifice_pick:
		title = "SACRIFÍCIO"
	elif summoning:
		title = "INVOCAÇÃO GRATUITA"
	elif hand_summon:
		title = "CAMPEÃO DA MÃO"
	elif hand_bottom:
		title = "MÃO DO OPONENTE"
	elif own_hand_bottom:
		title = "FUNDO DO DECK"
	elif discard_hand:
		title = "DESCARTAR DA MÃO"
	elif host.g.pending_search.get("grave", false):
		title = "CEMITÉRIO"
	elif look:
		title = "FUNDO DO DECK" if host.g.pending_search.get("from_bottom", false) else "TOPO DO DECK"
	var search_signature: int = host.g.pending_search.hash()
	# the opponent's choice starts folded: there is nothing to do in it, and the table is what matters
	var opponent_choice_is_folded: bool = not host.viewer_can_act() and search_opened_signature != search_signature
	if search_minimized_signature == search_signature or opponent_choice_is_folded:
		_render_search_minimized(title, not host.viewer_can_act())
		return
	search_scroll = null
	host.search_overlay = host.make_veil(0.84)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	host.search_overlay.add_child(box)
	box.add_child(host.make_label(title, 30, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6))
	var grave: bool = host.g.pending_search.get("grave", false)
	var whole_deck: bool = host.g.pending_search.get("whole_deck", false) # a search of the whole deck: it is shown in full, in order
	var sub := "%s está procurando uma carta no deck" % host.player_name(owner)
	if deck_search and host.viewer_can_act():
		sub = "Você procurou no deck e encontrou estas cartas; as que brilham podem ser escolhidas"
		if host.g.pending_search.has("to_bottom"):
			if host.g.pending_search.get("cards", []).is_empty():
				sub = "Você olhou as %d cartas do topo do deck e nenhuma pode ser escolhida" % int(host.g.pending_search["looked"])
			else:
				sub = "Você olhou as %d cartas do topo do deck; escolha uma das que brilham" % int(host.g.pending_search["looked"])
		elif whole_deck:
			if host.g.pending_search.get("cards", []).is_empty():
				sub = "Você olhou o deck inteiro, na ordem em que estava, e nenhuma carta pode ser escolhida"
			else:
				sub = "Você olhou o deck inteiro, na ordem em que estava; escolha uma das que brilham"
	if secret_search and host.g.pending_search.has("to_bottom"):
		sub = "%s está olhando as %d cartas do topo do deck" % [host.player_name(owner), int(host.g.pending_search["looked"])]
	elif secret_search and whole_deck:
		sub = "%s está olhando o deck inteiro" % host.player_name(owner)
	if sacrifice_pick:
		sub = (
			"Você escolhe uma unidade sua para sacrificar"
			if host.viewer_can_act()
			else "%s escolhe uma unidade sua para sacrificar" % host.player_name(owner)
		)
	elif hand_summon:
		sub = "%s escolhe um campeão da mão para entrar em campo (será banido no fim do turno)" % host.player_name(owner)
	elif discard_hand:
		sub = "%s escolhe uma carta da mão para descartar" % host.player_name(owner)
	elif look and host.g.pending_search.get("from_bottom", false):
		if host.viewer_can_act():
			sub = "Você pode escolher uma destas cartas do fundo do deck; ela vai para a sua mão"
		else:
			sub = "%s está olhando cartas do fundo do deck" % host.player_name(owner)
	elif reservoir_pick:
		if host.viewer_can_act():
			sub = "Você olhou a carta do topo do deck"
		else:
			sub = "%s está olhando a carta do topo do deck" % host.player_name(owner)
	elif look:
		sub = "%s está olhando as %d cartas do topo do deck" % [host.player_name(owner), host.g.pending_search["cards"].size()]
	if summoning:
		if host.viewer_can_act():
			sub = "Você pode invocar uma destas cartas de graça"
		else:
			sub = "%s está escolhendo uma carta para invocar de graça" % host.player_name(owner)
		if host.g.pending_search.has("looked_cards") and host.viewer_can_act():
			sub = "Você revelou estas cartas do topo do deck, na ordem; a que brilha pode ser invocada de graça"
		elif host.g.pending_search.has("looked_cards"):
			sub = "%s está revelando as cartas do topo do deck" % host.player_name(owner)
	box.add_child(host.make_label(sub, 20, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var shown_options: Array = [] if secret_search else host.g.pending_search["cards"]
	# a top-N look and a whole-deck search show every card looked at: the eligible ones glow and can be picked, the others are dimmed
	var looked_cards: Array = host.g.pending_search.get("looked_cards", [])
	var eligible_uids: Dictionary = { }
	for option in shown_options:
		eligible_uids[int(option["uid"])] = true
	if not secret_search and not looked_cards.is_empty():
		shown_options = looked_cards
	# every pick window is ONE row of cards, big enough to read the card text; a row wider than the screen
	# scrolls sideways instead of wrapping into more lines or shrinking the cards
	var card_scale := minf(SEARCH_MAX_CARD_SCALE, (host.STAGE_H + host.BOT - SEARCH_VERTICAL_ROOM) / CardView.BASE.y)
	var room_for_row: float = host.stage_w - SEARCH_SIDE_ROOM
	card_scale = minf(card_scale, room_for_row / CardView.BASE.x) # at least one whole card is always on screen
	var card_size := (CardView.BASE * card_scale).round()
	var card_stride := card_size.x + SEARCH_CARD_GAP
	var row_width := shown_options.size() * card_stride - SEARCH_CARD_GAP + 2.0 * SEARCH_ROW_MARGIN
	var row_overflows := row_width > room_for_row
	box.custom_minimum_size = Vector2(maxf(1115.0, minf(row_width, room_for_row)), 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var scrollbar_height := SEARCH_SCROLLBAR_HEIGHT if row_overflows else 0.0
	var window_size := Vector2(minf(row_width, room_for_row), card_size.y + 2.0 * SEARCH_ROW_MARGIN + scrollbar_height)
	scroll.custom_minimum_size = window_size
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_style_search_scrollbar(scroll)
	# the cards swallow wheel and finger events, so search_scroll_input slides the strip (one card per wheel notch)
	scroll.set_meta("wheel_step", int(card_stride))
	search_scroll = scroll
	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", int(SEARCH_ROW_MARGIN))
	row_margin.add_theme_constant_override("margin_right", int(SEARCH_ROW_MARGIN))
	row_margin.add_theme_constant_override("margin_top", int(SEARCH_ROW_MARGIN))
	row_margin.add_theme_constant_override("margin_bottom", int(SEARCH_ROW_MARGIN))
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", int(SEARCH_CARD_GAP))
	row_margin.add_child(card_row)
	scroll.add_child(row_margin)
	var scroll_stage := Control.new() # the scroll window plus the arrows that float over its edges
	scroll_stage.custom_minimum_size = window_size
	scroll_stage.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll_stage.add_child(scroll)
	box.add_child(scroll_stage)
	var eligible_flags: Array[bool] = []
	for option in shown_options:
		eligible_flags.append(eligible_uids.has(int(option["uid"])) and host.viewer_can_act())
	if row_overflows and eligible_flags.has(true):
		_add_search_scroll_guides(
			box,
			scroll_stage,
			scroll,
			eligible_flags,
			card_stride,
			card_size.x,
			window_size.x,
			whole_deck or host.g.pending_search.has("to_bottom"),
		)
	for option in shown_options:
		var card_uid: int = option["uid"]
		var eligible: bool = eligible_uids.has(card_uid)
		var cv := CardView.new().setup(
			option["card_id"],
			host.display_instance_for_id(String(option["card_id"]), owner, card_uid),
			card_scale,
		)
		cv.face_down = hidden or String(option["card_id"]) == ""
		if not cv.face_down:
			cv.text_suffix = scale_suffix(owner, CardDB.card(option["card_id"]), option["card_id"])
			cv.snowball_level = int(host.g.players[owner]["snowball"])
		# every card can be inspected (right click / long press), picked or not: some rules texts
		# only make sense in the full-screen view. Only the eligible ones can be chosen.
		var can_pick: bool = eligible and host.viewer_can_act()
		if can_pick:
			cv.highlight = host.OK # a glow marks what can be clicked, for every kind of choice
		elif not eligible:
			cv.modulate = Color(1, 1, 1, 0.4)
		# a swipe along the strip is not a tap nor a long-press: a pick can't be undone
		cv.right_clicked.connect(
			func(view):
				if not _search_just_scrolled():
					show_overlay(view),
		)
		if can_pick:
			cv.left_clicked.connect(
				func(_v):
					if not _search_just_scrolled():
						host.on_search_choice(card_uid),
			)
		card_row.add_child(cv)
	var summon_hint := "Clique na carta que brilha para invocá-la de graça, ou escolha não invocar nenhuma."
	if host.g.pending_search.has("looked_cards") and host.g.pending_search.get("leftover", "bottom") == "bottom":
		summon_hint += " As outras cartas reveladas vão para o fundo do deck."
	var grave_optional: bool = host.g.pending_search.get("grave_optional", false) # "grave_to_hand" (Rebobinar): the pick may be skipped
	var whole_deck_hint := (
		"Nenhuma carta do deck pode ser escolhida; o deck será embaralhado."
		if host.g \
				.pending_search \
				.get("cards", []) \
				.is_empty()
		else "Clique em uma carta que brilha para adicioná-la à sua mão; depois o deck é embaralhado."
	)
	if row_overflows and whole_deck:
		whole_deck_hint += " Deslize para o lado para ver o deck todo."
	var hand_tax_amount: int = int(host.g.pending_search.get("cost_increase", 0))
	var hint: String
	if own_hand_bottom:
		hint = (
			"Clique em uma carta da sua mão para colocá-la no fundo do deck e comprar %d; ou escolha nenhuma."
			% int(host.g.pending_search.get("draw_after", 1))
		)
	elif summoning:
		hint = summon_hint
	elif grave_optional:
		hint = "Clique em uma carta para levá-la à sua mão, ou escolha não pegar nenhuma; as outras ficam no cemitério."
	elif hand_summon:
		hint = "Clique em um campeão para colocá-lo em campo sem pagar o custo, ou escolha não colocar nenhum."
	elif hand_bottom and hand_tax_amount == 0:
		if host.g.pending_search.get("exclude_type", "") == "unit":
			hint = "Clique em uma carta que brilha (não é unidade) para mandá-la ao fundo do deck do dono, ou escolha nenhuma."
		else:
			hint = (
				"Clique em uma carta para mandá-la ao fundo do deck do dono. "
				+ "Se for uma unidade, você descarta %d cartas; ou escolha nenhuma."
				% int(host.g.pending_search.get("discard_if_unit", 0))
			)
	elif hand_bottom:
		if host.g.pending_search.get("only_type", "") == "spell":
			hint = (
				"Clique em um feitiço que brilha para ele custar %d a mais enquanto estiver na mão do dono; ou escolha nenhuma."
				% hand_tax_amount
			)
		else:
			hint = (
				"Clique em uma carta para ela custar %d a mais enquanto estiver na mão do dono; ou escolha nenhuma." % hand_tax_amount
			)
	elif discard_hand:
		hint = "Clique em uma carta para descartá-la (ela vai para o cemitério)."
	elif grave:
		hint = "Clique em uma carta para adicioná-la à sua mão; as outras ficam no cemitério."
	elif reservoir_pick:
		hint = "Escolha qual carta vai para o Reservatório: esta, do topo, ou a do fundo do deck (que você não viu)."
	elif look:
		if host.g.pending_search.get("from_bottom", false):
			hint = "Escolha 1 para a mão; as outras continuam onde estavam no fundo do deck."
		else:
			hint = "Escolha 1 para a mão; as outras vão para o fundo do deck."
	elif host.g.pending_search.has("to_bottom"):
		if host.g.pending_search.get("cards", []).is_empty():
			hint = "Nenhuma das cartas olhadas pode ser escolhida; o deck será embaralhado."
		else:
			hint = "Clique em uma carta que brilha para adicioná-la à sua mão; as outras vão para o fundo do deck."
	elif whole_deck:
		hint = whole_deck_hint
	else:
		hint = "Clique em uma carta que brilha para adicioná-la à sua mão e embaralhar o deck, ou escolha não pegar nenhuma."
	var footer: Label = host.make_label(
		hint if host.viewer_can_act() else "A escolha pertence ao oponente.",
		18,
		host.SEL if host.viewer_can_act() else UITheme.TEXT_DIM,
		HORIZONTAL_ALIGNMENT_CENTER,
		"body",
	)
	box.add_child(footer)
	if not secret_search:
		box.add_child(
			host.make_label(
				"Botão direito (ou segurar o dedo) em uma carta abre ela em tela cheia.",
				15,
				UITheme.TEXT_DIM,
				HORIZONTAL_ALIGNMENT_CENTER,
				"body",
			)
		)
	# a top-N look and a whole-deck search are mandatory when a card is eligible: their only button is the way out of a whiff
	var mandatory_deck_look: bool = (
		(host.g.pending_search.has("to_bottom") or whole_deck) and not host.g.pending_search.get("cards", []).is_empty()
	)
	if (
		(hand_summon or deck_search or summoning or grave_optional or hand_bottom or own_hand_bottom)
		and host.viewer_can_act() and not mandatory_deck_look
	):
		# these picks are optional: uid 0 means "take no card" (Dona Gertrudes puts no champion in play)
		# in a deck search that found nothing, the button shuffles the deck
		var skip_text := (
			"NÃO INVOCAR NENHUMA"
			if summoning
			else (
				"NÃO COLOCAR NENHUM"
				if hand_summon
				else (
					"NÃO ESCOLHER NENHUMA"
					if (hand_bottom or own_hand_bottom)
					else "EMBARALHAR O DECK" if (host.g.pending_search.has("to_bottom") or whole_deck) and not grave_optional else "NÃO PEGAR NENHUMA"
				)
			)
		)
		var skip_button: Button = host.make_button(
			skip_text,
			func():
				host.on_search_choice(0),
		)
		skip_button.custom_minimum_size = Vector2(360, 52)
		skip_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(skip_button)
	if reservoir_pick and host.viewer_can_act():
		var top_uid: int = int(host.g.pending_search["cards"][0]["uid"])
		var top_button: Button = host.make_button(
			"ESTA, DO TOPO",
			func():
				host.on_search_choice(top_uid),
		)
		top_button.custom_minimum_size = Vector2(360, 52)
		top_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(top_button)
		var bottom_button: Button = host.make_button(
			"A DO FUNDO DO DECK",
			func():
				host.on_search_choice(GameState.RESERVOIR_PICK_BOTTOM),
		)
		bottom_button.custom_minimum_size = Vector2(360, 52)
		bottom_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(bottom_button)
	if host.g.pending_search.has("then_activate") and host.viewer_can_act():
		# this discard pays an Ao Ativar: backing out spends nothing
		var cancel_activation_button: Button = host.make_button(
			"CANCELAR",
			func():
				host.on_search_choice(0),
		)
		cancel_activation_button.custom_minimum_size = Vector2(360, 52)
		cancel_activation_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(cancel_activation_button)
	var minimize_button: Button = host.make_button(
		"VER A MESA",
		func():
			search_minimized_signature = search_signature
			search_opened_signature = -1
			host.render_table(),
	)
	minimize_button.custom_minimum_size = Vector2(360, 52)
	HubGlyphIconScript.attach_to_button(minimize_button, HubGlyphIconScript.Kind.ARROW_DOWN, 20.0, UITheme.TEXT, "left", 18.0)
	minimize_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(minimize_button)
	host.center_in_screen.call_deferred(host.search_overlay)


## The search folded into a small bar at the top of the screen, so the table can be seen (and cards on
## it inspected). The bar brings the full choice back.
func _render_search_minimized(title: String, opponents_choice := false) -> void:
	var bar := PanelContainer.new()
	var style := UITheme.panel(14)
	style.set_content_margin_all(10)
	style.border_color = Color(UITheme.GOLD, 0.6)
	style.shadow_size = 24
	bar.add_theme_stylebox_override("panel", style)
	host.layer.add_child(bar)
	# the leading spaces leave room for the arrow icon drawn at the left edge of the button
	var restore_text := "      VER A ESCOLHA DO OPONENTE · %s" if opponents_choice else "      VOLTAR À ESCOLHA · %s"
	var restore_button: Button = host.make_button(
		restore_text % title,
		func():
			search_minimized_signature = -1
			search_opened_signature = host.g.pending_search.hash()
			host.render_table(),
		true,
	)
	restore_button.custom_minimum_size = Vector2(520, 60)
	HubGlyphIconScript.attach_to_button(restore_button, HubGlyphIconScript.Kind.ARROW_UP, 22.0, UITheme.TEXT, "left", 18.0)
	bar.add_child(restore_button)
	host.search_overlay = bar
	_place_at_top_center.call_deferred(bar)


func _place_at_top_center(control: Control) -> void:
	control.reset_size()
	control.position = Vector2((host.size.x - control.size.x) / 2.0, 8.0)
