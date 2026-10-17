extends Control
## Table screen: menu, board rendering, input state machine, AI driver,
## hot-seat pass screen and the full-screen card summary overlay.

const SEL := Color("#ffd23f")
const TARGET := Color("#ff5050")
const OK := Color("#4dff88")
const ICE := Color("#bfefff")
## An exhausted (tapped) unit lies sideways on the table, like a tapped Magic card.
const TAPPED_TILT_DEGREES := 90.0
## A tapped card shrinks only a little: lying down it is wider than its cell, so on a crowded row
## it overlaps its neighbours a bit instead of turning tiny.
const TAPPED_MIN_SCALE := 0.85
const COL_W := 232.0 ## right HUD column width
const STAGE_H := 1034.0
const BOT := 134.0 ## extra stage height under the boards: room for the Leader plate between the board and the hand
const STAGE_MAX_W := 2100.0
var stage_w := 1600.0 ## logical width: 1600 or wider, follows the window aspect
var col_x := 1352.0
var lane_cx := 882.0
var motes: CPUParticles2D

var g: GameState
var vs_ai := true
var viewer := 0 ## whose perspective is drawn
var pending_pass := false
var _over_from := -1 ## index in layer of the first game-over node (-1 = none this frame)
var _leader_ko_t := -1.0 ## time of the last Leader HP change in the current animation
var net: NetClient ## online match link (null offline)
var online := false
var opp_online := true
var code_entry := ""
var sel_deck := "" ## prebuilt deck picked in the online hub
var hub_hotseat := false ## the deck hub's two-step flow is picking decks for hot-seat (player 1, then player 2) instead of AI
var hub_scroll: ScrollContainer ## the deck hub's scrolling gallery (null/freed outside the hub)
var hub_scroll_y := 0 ## how far the gallery was scrolled, kept across the hub's redraws
var hub_drag_distance := 0.0 ## how far the current press has dragged the gallery (a long drag isn't a tap)
const HUB_MARGIN := 40.0 ## space between the hub's panels and the stage sides
const HUB_TILE := Vector2(210, 236) ## every deck tile in the gallery has this size, however many decks exist
const HUB_TILE_GAP := 20.0
const HUB_TILE_PAD := 10.0 ## room around the gallery's tiles for the hover zoom
const HUB_DRAG_SLOP := 12.0 ## pixels a press may move and still count as a tap on a deck
var ai_deck := "" ## deck the AI plays, picked in the second step of the AI hub ("" = a random other deck)

# input state
var picked: Array = [] ## mulligan/discard selection
var targeting := {} ## {"kind": hand|legendary|ability|enter|attack, "uid": int, "spec": String}

var log_lines: Array = []
var bg: TextureRect ## table surface, baked once into bg_vp (the live shader was too heavy for weak phones)
var bg_vp: SubViewport
var bg_rect: ColorRect
var bg_mat: ShaderMaterial
var table: TableView
var layer: Control
var overlay: Control
var search_overlay: Control
var grave_view: Control ## graveyard viewer (child of Main, outlives _render)
var concede_view: Control ## "concede?" confirmation (child of Main, outlives _render)
var conceded := -1 ## player who gave up this match (-1 = nobody); only used for the game-over text
var grave_panel: PanelContainer
var grave_scroll: ScrollContainer
var grave_owner := 0
var grave_filter := "all"
var grave_drag_ms := -1000 ## last finger-drag in the viewer: taps right after it are not clicks
var views := {} ## uid (or "cmd<p>") -> Control on screen, for animations
var barricade_was_up := {} ## unit uid -> was it a tapped, unfrozen Provocação in the previous render? (to spot the moment it slams shut)
var hand_uids := {} ## viewer's hand cards in the current render
var hint_text := "" ## the tip pill fades out after a few seconds and returns when the player seems lost
var hint_since := 0
var hint_until := 0
var last_input_ms := 0
var hint_pill: Control
var aim_arrow: AimArrow ## targeting arrow from the source to the pointer
var aim_drag := false ## the press that started aiming is still held: releasing on a target fires
var aim_start := Vector2.ZERO
var aim_src := Vector2.ZERO ## global source point (leader gem, command card)
var fx: Control ## persistent layer above the table: ghosts, floats, embers
var ai_timer: Timer
## Animations are never cut short: while one is still playing, the next batch of events waits here
## (the engine has already applied it; only the showing is postponed) and plays when the table settles.
var _animation_busy_until_ms := 0
var _waiting_event_batches: Array = [] ## each entry is one Array of events, in the order they happened
var _waiting_events_timer: Timer
## While the table is busy (see _table_busy) the engine may already be ahead of what the screen shows,
## so redrawing would spoil the future (a unit that dies in the waiting batch would vanish before its
## fight is shown). _render only takes note, and the redraw happens once the table settles.
var _render_when_settled := false
## Clicks given while the table is busy are not judged against a screen that is out of date: each one
## waits here, in order, and runs once the last animation has ended (the player's "next move" buffer).
var _queued_inputs: Array[Callable] = []
var _replaying_queued_inputs := false ## true while _run_queued_inputs is running them
## Fires when the animation that is playing now ends, to redraw and run the waiting clicks.
var _settle_timer: Timer
## A unit picked to attack while the table was busy (its click is still waiting in _queued_inputs):
## an arrow already follows the pointer from it, so the player sees the pick counted. 0 = none.
var _queued_attacker_uid := 0
## The press that picked _queued_attacker_uid is still held: releasing it over a card picks the target.
var _queued_attacker_dragging := false

var _hand_base := 0 ## child index of the first hand card in layer


## "Modo leve": renders at the 1600x900 base size and upscales (fewer pixels, softer text).
func _apply_light(on: bool, save := false) -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if on else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if save:
		var cf := ConfigFile.new()
		cf.set_value("ui", "light", on)
		cf.save("user://settings.cfg")

## Phones default to light mode until the player picks one explicitly.
func _light_on() -> bool:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") != Error.OK:
		return _is_phone()
	return bool(cf.get_value("ui", "light", _is_phone()))

## "Auto-passe": the engine skips priority windows where you have nothing legal to do.
func _auto_pass_on() -> bool:
	var cf := ConfigFile.new()
	return cf.load("user://settings.cfg") != Error.OK or bool(cf.get_value("game", "auto_pass", true))

func _set_auto_pass(on: bool) -> void:
	var cf := ConfigFile.new()
	cf.load("user://settings.cfg")
	cf.set_value("game", "auto_pass", on)
	cf.save("user://settings.cfg")
	if g == null:
		return
	if g is RemoteState:
		(g as RemoteState).set_auto_pass(viewer, on)
		return
	var ev := []
	for i in 2:
		if not _is_ai(i):
			ev += g.set_auto_pass(i, on)
	if on and not ev.is_empty():
		for e in ev:
			_log_event(e)
		_show_events(ev)
	else:
		_render()

func _is_phone() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") 			or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())

func _ready() -> void:
	# Main covers the whole stage: with the default STOP filter it swallowed every press on empty
	# table, so `_unhandled_input` (tap outside / right click cancels an aim) never saw it
	mouse_filter = Control.MOUSE_FILTER_PASS
	# the logical screen is as tall as the stage, so a 16:9 window shows all of it (not a cropped middle)
	get_window().content_scale_size = Vector2i(1600, int(STAGE_H))
	_apply_light(_light_on())
	theme = UITheme.make()
	bg_vp = SubViewport.new()
	bg_vp.size = Vector2i(640, 360)
	bg_vp.disable_3d = true
	bg_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(bg_vp)
	bg_rect = ColorRect.new()
	bg_rect.size = Vector2(640, 360)
	bg_mat = ShaderMaterial.new()
	bg_mat.shader = load("res://scripts/ui/shaders/table.gdshader")
	bg_mat.set_shader_parameter("aspect", 1600.0 / 900.0)
	bg_mat.set_shader_parameter("divider_y", TableView.DIVIDER_Y / STAGE_H)
	bg_rect.material = bg_mat
	bg_vp.add_child(bg_rect)
	bg = TextureRect.new()
	bg.texture = bg_vp.get_texture()
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	get_viewport().size_changed.connect(_fit_viewport)
	_fit_viewport()
	table = TableView.new()
	add_child(table)
	motes = _motes()
	add_child(motes)
	_fit_viewport()
	fx = Control.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx)
	_prewarm_fx.call_deferred()
	ai_timer = Timer.new()
	ai_timer.one_shot = true
	ai_timer.wait_time = 0.55
	ai_timer.timeout.connect(_ai_step)
	add_child(ai_timer)
	_waiting_events_timer = Timer.new()
	_waiting_events_timer.one_shot = true
	_waiting_events_timer.timeout.connect(_play_waiting_events)
	add_child(_waiting_events_timer)
	_settle_timer = Timer.new()
	_settle_timer.one_shot = true
	_settle_timer.timeout.connect(_on_table_settled)
	add_child(_settle_timer)
	net = NetClient.new()
	add_child(net)
	net.message.connect(_on_net)
	net.link_changed.connect(_on_link)
	_show_menu()
	_load_scenario()

## Dev only: `-- --scenario=<name>` starts a match vs the AI (Maré vs Fogo) set up by
## tests/scenarios/<name>.gd (static func setup(g)).
func _load_scenario() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--scenario="):
			continue
		var script: GDScript = load("res://tests/scenarios/%s.gd" % a.trim_prefix("--scenario="))
		_start(true, "agua", "fogo")
		script.setup(g)
		g.auto_pass[0] = _auto_pass_on()
		pending_pass = false
		log_lines = ["Cenário de teste carregado."]
		_render()

## The stage is 900 tall and at least 1600 wide: on wider windows (phones in
## landscape) it grows sideways, so the table uses the space instead of leaving
## empty bands. Anchored overlays follow because Main itself is the stage.
func _fit_viewport() -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := clampf(STAGE_H * vp.x / max(1.0, vp.y), 1600.0, STAGE_MAX_W)
	var changed := not is_equal_approx(w, stage_w)
	stage_w = w
	col_x = w - 16.0 - COL_W
	TableView.layout(col_x - 16.0)
	lane_cx = TableView.ENEMY_LANE.get_center().x
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(w, STAGE_H)
	position = (vp - size) / 2.0
	bg.position = -position
	bg.size = vp
	var bw := int(360.0 * vp.x / maxf(1.0, vp.y))
	bg_vp.size = Vector2i(bw, 360)
	bg_rect.size = Vector2(bw, 360)
	bg_mat.set_shader_parameter("aspect", vp.x / vp.y)
	bg_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if motes:
		motes.position = Vector2(w / 2.0, STAGE_H / 2.0)
		motes.emission_rect_extents = Vector2(w / 2.0 + 20.0, STAGE_H / 2.0)
	if changed and layer:
		if table.visible and g:
			_render.call_deferred()
		elif not table.visible:
			_show_menu.call_deferred()

## Slow drifting embers over the whole screen, for depth.
func _motes() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 46
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.position = Vector2(800, 470)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(820, 470)
	p.direction = Vector2(0.2, -1)
	p.spread = 25.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 18.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 0.85, 0.5, 0.0))
	ramp.add_point(0.3, Color(1, 0.85, 0.5, 0.35))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 0.85, 0.5, 0.0))
	p.color_ramp = ramp
	return p

func _set_tints(top: Color, bottom: Color, intensity := 1.0) -> void:
	bg_mat.set_shader_parameter("top_tint", top)
	bg_mat.set_shader_parameter("bottom_tint", bottom)
	bg_mat.set_shader_parameter("intensity", intensity)
	bg_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _leader_color(p: int) -> Color:
	return Color(CardDB.essence(CardDB.leader(g.players[p]["leader_id"])["essences"][0])["color"])

# ---------------------------------------------------------------- menu

func _show_menu() -> void:
	if online:
		net.disconnect_server() ## the saved session stays: RETOMAR PARTIDA in the lobby
		online = false
	g = null
	_close_concede()
	_clear_fx()
	_clear()
	table.visible = false
	_set_tints(Color("#3f7bd9"), Color("#e0572b"), 1.6)
	# the two Leaders of the slice, facing each other from the edges
	for side in [["ignea/ronan.webp", 0.0, 1.0], ["aquatica/naelthos.webp", stage_w - 640.0, 0.0]]:
		var tex := CardView.texture(side[0])
		if tex == null:
			continue
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(side[1], 0)
		tr.size = Vector2(640, STAGE_H)
		tr.flip_h = side[2] == 0.0
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = load("res://scripts/ui/shaders/art_fade.gdshader")
		sm.set_shader_parameter("fade_from_right", side[2])
		sm.set_shader_parameter("strength", 0.55)
		tr.material = sm
		layer.add_child(tr)
	var sup := _label("CHAMPION SHOWDOWN ARENA", 18, Color(UITheme.GOLD, 0.8), HORIZONTAL_ALIGNMENT_CENTER, "title", 4)
	sup.position = Vector2(0, 196)
	sup.size = Vector2(stage_w, 30)
	layer.add_child(sup)
	var title := _label("DUELO DE CARTAS", 76, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 10)
	title.add_theme_color_override("font_shadow_color", Color(UITheme.GOLD, 0.35))
	title.add_theme_constant_override("shadow_outline_size", 22)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.position = Vector2(0, 224)
	title.size = Vector2(stage_w, 100)
	layer.add_child(title)
	layer.add_child(_ornament(Vector2(stage_w / 2.0, 340), 260))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.position = Vector2(stage_w / 2.0 - 210, 390)
	box.custom_minimum_size = Vector2(420, 0)
	layer.add_child(box)
	for opt in [["JOGAR CONTRA A IA", "Escolha o seu deck e o da IA", func() -> void:
				hub_hotseat = false
				_show_hub(true), true],
			["HOT-SEAT", "Dois jogadores no mesmo aparelho, cada um com o deck que quiser", func() -> void:
				hub_hotseat = true
				_show_hub(true), false],
			["ONLINE", "Jogar contra outra pessoa por código de sala", func() -> void: _show_hub(false), false]]:
		var b := _button(opt[0], opt[2], opt[3])
		b.custom_minimum_size = Vector2(420, 58)
		b.tooltip_text = opt[1]
		box.add_child(b)
		var sub := _label(opt[1], 14, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body")
		box.add_child(sub)
	var lt := _toggle_button("MODO LEVE", _light_on(), func():
		_apply_light(not _light_on(), true)
		_show_menu.call_deferred())
	lt.position = Vector2(stage_w - 300, 790.0 + BOT)
	lt.size = Vector2(280, 52)
	layer.add_child(lt)
	var fs := _button("Tela cheia (F11)", _toggle_fullscreen)
	fs.position = Vector2(stage_w - 300, 790.0 + BOT - 64.0)
	fs.size = Vector2(280, 52)
	layer.add_child(fs)
	var ver := _label("0.2.2 Alpha", 13, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, "body")
	ver.position = Vector2(stage_w - 300, 864.0 + BOT)
	ver.size = Vector2(280, 20)
	layer.add_child(ver)

## A thin gold rule with a diamond in the middle, for headings.
func _ornament(center: Vector2, half: float) -> Control:
	var o := Control.new()
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.position = center
	o.draw.connect(func():
		for i in 20:
			var k := float(i) / 20.0
			var a := (1.0 - k) * 0.8
			var x0 := 10 + (half - 10) * k
			var x1 := 10 + (half - 10) * (k + 0.05)
			o.draw_line(Vector2(-x0, 0), Vector2(-x1, 0), Color(UITheme.GOLD, a), 1.5)
			o.draw_line(Vector2(x0, 0), Vector2(x1, 0), Color(UITheme.GOLD, a), 1.5)
		o.draw_colored_polygon(PackedVector2Array([Vector2(0, -6), Vector2(6, 0), Vector2(0, 6), Vector2(-6, 0)]), UITheme.GOLD))
	return o

func _start(ai: bool, deck_a: String, deck_b: String) -> void:
	if online:
		net.disconnect_server()
		online = false
	vs_ai = ai
	g = GameState.new(deck_a, deck_b)
	barricade_was_up.clear() # unit uids restart with every match
	for i in 2:
		g.auto_pass[i] = _auto_pass_on() or _is_ai(i)
	CardDB.reroll_flavor()
	log_lines = ["Partida iniciada. Escolha até 3 cartas para trocar."]
	conceded = -1
	viewer = 0
	pending_pass = not vs_ai
	_reset_input()
	_clear_fx()
	_render()

func _reset_input() -> void:
	picked.clear()
	targeting = {}

# ---------------------------------------------------------------- online

func _show_online(msg := "") -> void:
	_show_hub(false, msg)

## Deck hub, shared by both modes: pick a prebuilt deck from the grid, then either go on to pick the
## AI's deck (ai = true) or create a room / go on to join one by code (online).
## `choosing_ai_deck` is the AI mode's second step: the same grid, but the pick is the AI's deck.
func _show_hub(ai: bool, msg := "", choosing_ai_deck := false) -> void:
	_clear_fx()
	_clear()
	table.visible = false
	_set_tints(Color("#3f7bd9"), Color("#e0572b"), 1.6)
	var ids := DeckDB.ids()
	if not ids.has(sel_deck):
		sel_deck = ids[0]
	if ai_deck != "" and not ids.has(ai_deck):
		ai_deck = ""
	var title := _label(("HOT-SEAT" if hub_hotseat else "CONTRA A IA") if ai else "ONLINE", 56, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 8)
	title.position = Vector2(0, 24)
	title.size = Vector2(stage_w, 72)
	layer.add_child(title)
	layer.add_child(_ornament(Vector2(stage_w / 2.0, 108), 240))
	var subtitle := "Jogador 1: escolha o seu deck" if hub_hotseat else "Escolha o seu deck"
	if choosing_ai_deck:
		subtitle = "Jogador 2: escolha o seu deck" if hub_hotseat else "Escolha o deck da IA (ou deixe no aleatório)"
	var sub := _label(msg if msg != "" else subtitle, 22, UITheme.TEXT if msg != "" else UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	sub.position = Vector2(0, 122)
	sub.size = Vector2(stage_w, 30)
	layer.add_child(sub)

	# Layout: the chosen deck in a big showcase on the left (full description, never cut), and every
	# deck as a fixed-size tile in a gallery on the right. More decks only make the gallery taller,
	# and it scrolls (wheel or finger), so the tiles never shrink however many decks there are.
	var body_top := 172.0
	var body_bottom := STAGE_H - 112.0
	var body_h := body_bottom - body_top
	var showcase_w := 560.0
	var selected_id := ai_deck if choosing_ai_deck else sel_deck
	var showcase := _deck_showcase(selected_id, Vector2(showcase_w, body_h), choosing_ai_deck)
	showcase.position = Vector2(HUB_MARGIN, body_top)
	layer.add_child(showcase)

	var gallery_x := HUB_MARGIN + showcase_w + 32.0
	var gallery_w := stage_w - gallery_x - HUB_MARGIN
	var gallery_ids: Array = ids.duplicate()
	if choosing_ai_deck:
		gallery_ids.push_front("") # the "random deck" tile comes first
	var columns := maxi(1, int((gallery_w + HUB_TILE_GAP) / (HUB_TILE.x + HUB_TILE_GAP)))
	var rows := ceili(float(gallery_ids.size()) / float(columns))
	var content_h := rows * HUB_TILE.y + (rows - 1) * HUB_TILE_GAP
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(gallery_x, body_top)
	scroll.size = Vector2(gallery_w, body_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# the gallery scrolls by finger or wheel (see _hub_scroll_input), so the bar would only add clutter
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	layer.add_child(scroll)
	hub_scroll = scroll
	var content := Control.new()
	# a few pixels of room around the tiles so the hover zoom and the gold border aren't clipped
	content.custom_minimum_size = Vector2(gallery_w, content_h + 2.0 * HUB_TILE_PAD)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(content)
	var grid_w := columns * HUB_TILE.x + (columns - 1) * HUB_TILE_GAP
	var grid_x := (gallery_w - grid_w) / 2.0
	var selected_tile: Control = null
	for i in gallery_ids.size():
		var id: String = gallery_ids[i]
		var is_selected := id == selected_id
		var t := _deck_tile(id, HUB_TILE, is_selected)
		t.position = Vector2(grid_x + (i % columns) * (HUB_TILE.x + HUB_TILE_GAP), HUB_TILE_PAD + (i / columns) * (HUB_TILE.y + HUB_TILE_GAP))
		if is_selected:
			selected_tile = t
		t.gui_input.connect(func(ev: InputEvent) -> void:
			# picks on release, and not at the end of a scroll drag
			var mb := ev as InputEventMouseButton
			if mb == null or mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or hub_drag_distance > HUB_DRAG_SLOP:
				return
			if choosing_ai_deck:
				ai_deck = id
			elif sel_deck != id:
				sel_deck = id
			else:
				return
			hub_scroll_y = scroll.scroll_vertical
			_show_hub.call_deferred(ai, msg, choosing_ai_deck))
		content.add_child(t)
	# edge fades: a hint that there are more decks above or below
	if content_h + 2.0 * HUB_TILE_PAD > body_h:
		for at_top in [true, false]:
			var edge := _hub_edge_fade(at_top)
			edge.position = Vector2(gallery_x, body_top if at_top else body_bottom - 48.0)
			edge.size = Vector2(gallery_w, 48)
			layer.add_child(edge)
			scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _update_hub_edge(edge, scroll, at_top))
			_update_hub_edge.call_deferred(edge, scroll, at_top)
	_restore_hub_scroll.call_deferred(scroll, hub_scroll_y, selected_tile)
	var y := body_bottom + 20.0

	var actions: Array = []
	if ai and not choosing_ai_deck:
		actions.append(["PRÓXIMO: DECK DO JOGADOR 2" if hub_hotseat else "PRÓXIMO: DECK DA IA", func() -> void:
			hub_scroll_y = 0
			_show_hub.call_deferred(true, "", true), true])
	elif ai:
		actions.append(["JOGAR", func() -> void:
			var opponent_deck := ai_deck
			if opponent_deck == "":
				var others := ids.filter(func(d: String) -> bool: return d != sel_deck)
				opponent_deck = String(others.pick_random()) if not others.is_empty() else sel_deck
			_start(not hub_hotseat, sel_deck, opponent_deck), true])
	elif net.load_session():
		actions.append(["RETOMAR PARTIDA (%s)" % net.code, func() -> void:
			online = true
			net.resume(), true])
	if not ai:
		actions.append(["CRIAR SALA", func() -> void:
			online = true
			net.create(sel_deck)
			_show_wait("Criando sala…"), true])
		actions.append(["ENTRAR COM CÓDIGO", func() -> void:
			code_entry = ""
			_show_join(), false])
	# one row: Voltar on the left, then the actions
	var bw := 400.0
	var back_w := 240.0
	var row_w := back_w + actions.size() * (bw + 24.0)
	var bx := (stage_w - row_w) / 2.0
	# from the AI-deck step, Voltar goes back to picking your own deck
	var back_action := (func() -> void:
		hub_scroll_y = 0
		_show_hub.call_deferred(true)) if choosing_ai_deck else _show_menu
	var bk := _button("Voltar", back_action)
	bk.position = Vector2(bx, y)
	bk.size = Vector2(back_w, 72)
	layer.add_child(bk)
	for i in actions.size():
		var b := _button(actions[i][0], actions[i][1], actions[i][2])
		b.position = Vector2(bx + back_w + 24.0 + i * (bw + 24.0), y)
		b.size = Vector2(bw, 72)
		layer.add_child(b)

## Puts the deck gallery back where it was scrolled before the redraw, then makes sure the chosen
## deck's tile is in view (e.g. when coming back to the hub with a deck far down the list).
func _restore_hub_scroll(scroll: ScrollContainer, scroll_y: int, selected_tile: Control) -> void:
	if not is_instance_valid(scroll):
		return
	scroll.scroll_vertical = scroll_y
	if selected_tile != null and is_instance_valid(selected_tile):
		scroll.ensure_control_visible(selected_tile)

## A strip that fades the gallery's top or bottom edge into the background.
func _hub_edge_fade(at_top: bool) -> TextureRect:
	var fade := GradientTexture2D.new()
	var grad := Gradient.new()
	var dark := Color(0.02, 0.02, 0.035)
	grad.colors = PackedColorArray([Color(dark, 0.9), Color(dark, 0.0)] if at_top else [Color(dark, 0.0), Color(dark, 0.9)])
	fade.gradient = grad
	fade.fill_from = Vector2(0, 0)
	fade.fill_to = Vector2(0, 1)
	var edge := TextureRect.new()
	edge.texture = fade
	edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return edge

## Shows an edge fade only while there is more gallery hidden past that edge.
func _update_hub_edge(edge: Control, scroll: ScrollContainer, at_top: bool) -> void:
	if not is_instance_valid(edge) or not is_instance_valid(scroll):
		return
	var bar := scroll.get_v_scroll_bar()
	var hidden_past_edge := bar.value > 1.0 if at_top else bar.value < bar.max_value - bar.page - 1.0
	edge.modulate.a = 1.0 if hidden_past_edge else 0.0

## Wheel and finger-drag scrolling of the deck gallery (the tiles swallow those events before the
## ScrollContainer sees them). Also measures how far a press has moved, so a drag doesn't pick a deck.
func _hub_scroll_input(e: InputEvent) -> bool:
	if not is_instance_valid(hub_scroll) or not hub_scroll.is_visible_in_tree():
		return false
	var xf := hub_scroll.get_global_transform_with_canvas()
	var local: Vector2 = xf.affine_inverse() * e.position if "position" in e else Vector2(-1, -1)
	var inside := Rect2(Vector2.ZERO, hub_scroll.size).has_point(local)
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		hub_drag_distance = 0.0 # a new press: nothing dragged yet
		return false
	if not inside:
		return false
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		hub_scroll.scroll_vertical += (-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1) * 120
		return true
	var drag_y := 0.0
	if e is InputEventScreenDrag:
		drag_y = e.relative.y
	elif e is InputEventMouseMotion and not CardView.touched and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		drag_y = e.relative.y # mouse drag on desktop (on phones the finger already came as a ScreenDrag)
	else:
		return false
	hub_drag_distance += absf(drag_y)
	if hub_drag_distance > HUB_DRAG_SLOP:
		hub_scroll.scroll_vertical -= int(drag_y / xf.get_scale().y)
	return true

## The big panel on the left of the hub: the chosen deck's Leader art, name, Leader line, Encarnação,
## full description and size. `id` "" is the AI's "random deck" choice.
func _deck_showcase(id: String, size: Vector2, choosing_ai_deck: bool) -> Control:
	var bg := Color(0.06, 0.055, 0.085, 0.96)
	var p := Panel.new()
	p.size = size
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var who := ("DECK DO JOGADOR 2" if hub_hotseat else "DECK DA IA") if choosing_ai_deck else ("JOGADOR 1" if hub_hotseat else "SEU DECK")
	if id == "":
		p.add_theme_stylebox_override("panel", UITheme.box(bg, 16, UITheme.GOLD, 3, 20))
		var mark := _label("?", 220, Color(UITheme.GOLD_LIGHT, 0.5), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 8)
		mark.position = Vector2(0, size.y * 0.12)
		mark.size = Vector2(size.x, 300)
		p.add_child(mark)
		_showcase_text(p, size, who, "Deck Aleatório", "", UITheme.GOLD_LIGHT, "A IA joga com um dos outros decks, sorteado na hora de começar.", "", size.y * 0.5)
		return p
	var d := DeckDB.get_deck(id)
	var ld := CardDB.leader(d["leader"])
	var col := Color(String(CardDB.essence(ld["essences"][0]).get("color", "#8a8f98")))
	p.add_theme_stylebox_override("panel", UITheme.box(bg, 16, Color(col, 0.85), 3, 20))
	var art_h := size.y * 0.5
	var art := TextureRect.new()
	art.texture = _top_crop(CardView.texture(String(ld.get("art", ""))), Vector2(size.x - 8, art_h), float(ld.get("art_focus", 0.06)))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = Vector2(4, 4)
	art.size = Vector2(size.x - 8, art_h)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(art)
	p.add_child(_art_fade(bg, Vector2(4, 4 + art_h * 0.45), Vector2(size.x - 8, art_h * 0.55 + 1)))
	var essence_names: Array = []
	for essence_id in ld["essences"]:
		essence_names.append(CardDB.essence(essence_id).get("name", essence_id))
	var leader_line := "%s · %d de vida · %s" % [ld["name"], int(ld["hp"]), " / ".join(essence_names)]
	var footer := "%d cartas · Encarnação: %s" % [DeckDB.card_count(id), CardDB.card(ld["legendary"])["name"]]
	_showcase_text(p, size, who, String(d["name"]), leader_line, col, String(d.get("description", "")), footer, art_h - 30.0)
	return p

## The showcase's text block, from `top` down: a small "SEU DECK" tag, the deck name, the Leader line,
## the full description (wrapped, and smaller only if it would not fit) and a footer.
func _showcase_text(p: Control, size: Vector2, who: String, deck_name: String, leader_line: String, col: Color, description: String, footer: String, top: float) -> void:
	var tag := _label(who, 15, Color(UITheme.GOLD, 0.9), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	tag.position = Vector2(20, top - 26.0)
	tag.size = Vector2(size.x - 40, 22)
	p.add_child(tag)
	var nm := _label(deck_name, 40, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 8)
	nm.position = Vector2(20, top - 6.0)
	nm.size = Vector2(size.x - 40, 52)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	p.add_child(nm)
	var y := top + 50.0
	if leader_line != "":
		var lead := _label(leader_line, 19, col.lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER, "bold", 3)
		lead.position = Vector2(20, y)
		lead.size = Vector2(size.x - 40, 26)
		lead.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		p.add_child(lead)
		y += 32.0
	p.add_child(_ornament(Vector2(size.x / 2.0, y + 8.0), 140))
	y += 26.0
	var footer_h := 40.0 if footer != "" else 0.0
	var room := size.y - y - footer_h - 16.0
	var blurb := _label(description, 23, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "body", 3)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.position = Vector2(32, y)
	blurb.size = Vector2(size.x - 64, room)
	# a very long description steps the font down until it fits, instead of being cut off
	for font_size in [23, 21, 19, 17]:
		blurb.add_theme_font_size_override("font_size", font_size)
		if blurb.get_line_count() * blurb.get_line_height() <= room:
			break
	p.add_child(blurb)
	if footer != "":
		var foot := _label(footer, 17, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold", 3)
		foot.position = Vector2(20, size.y - footer_h)
		foot.size = Vector2(size.x - 40, 24)
		foot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		p.add_child(foot)

## A gradient that melts the bottom of a portrait into the panel color.
func _art_fade(bg: Color, pos: Vector2, size: Vector2) -> TextureRect:
	var fade := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(bg, 0.0), Color(bg, 1.0)])
	fade.gradient = grad
	fade.fill_from = Vector2(0, 0)
	fade.fill_to = Vector2(0, 1)
	var veil := TextureRect.new()
	veil.texture = fade
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.position = pos
	veil.size = size
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return veil

## One deck in the hub gallery: Leader art, deck name and Leader. Always the same size (the full
## description lives in the showcase). `id` "" is the AI's "random deck" tile.
func _deck_tile(id: String, size: Vector2, selected: bool) -> Control:
	var bg := Color(0.06, 0.055, 0.085, 0.94)
	var col := UITheme.GOLD_LIGHT
	var p := Panel.new()
	p.size = size
	p.pivot_offset = size / 2.0
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var art_h := size.y * 0.6
	var deck_name := "Aleatório"
	var leader_name := "sorteado ao jogar"
	if id == "":
		var mark := _label("?", 96, Color(UITheme.GOLD_LIGHT, 0.55), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6)
		mark.position = Vector2(0, art_h * 0.12)
		mark.size = Vector2(size.x, art_h)
		p.add_child(mark)
	else:
		var d := DeckDB.get_deck(id)
		var ld := CardDB.leader(d["leader"])
		col = Color(String(CardDB.essence(ld["essences"][0]).get("color", "#8a8f98")))
		deck_name = String(d["name"])
		leader_name = String(ld["name"])
		var art := TextureRect.new()
		art.texture = _top_crop(CardView.texture(String(ld.get("art", ""))), Vector2(size.x - 8, art_h), float(ld.get("art_focus", 0.06)))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.position = Vector2(4, 4)
		art.size = Vector2(size.x - 8, art_h)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(art)
		p.add_child(_art_fade(bg, Vector2(4, 4 + art_h * 0.5), Vector2(size.x - 8, art_h * 0.5 + 1)))
	p.add_theme_stylebox_override("panel", UITheme.box(bg, 12, UITheme.GOLD if selected else Color(col, 0.55), 4 if selected else 2, 12 if selected else 6))
	# the name may take two lines; long ones shrink a step instead of being cut
	var nm := _label(deck_name, 21, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 5)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.position = Vector2(8, art_h - 14.0)
	nm.size = Vector2(size.x - 16, 54)
	for font_size in [21, 19, 17]:
		nm.add_theme_font_size_override("font_size", font_size)
		if nm.get_line_count() <= 2:
			break
	p.add_child(nm)
	var lead := _label(leader_name, 15, col.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, "bold", 3)
	lead.position = Vector2(8, size.y - 30.0)
	lead.size = Vector2(size.x - 16, 22)
	lead.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	p.add_child(lead)
	if selected:
		var check := _label("✔", 20, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 4)
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.GOLD.darkened(0.6), 0.95), 15, UITheme.GOLD, 2))
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.custom_minimum_size = Vector2(32, 32)
		badge.add_child(check)
		badge.position = Vector2(size.x - 42, 10)
		p.add_child(badge)
	# hover (mouse only): a gentle lift so the gallery feels alive on desktop
	p.mouse_entered.connect(func() -> void:
		if not CardView.touched:
			p.create_tween().tween_property(p, "scale", Vector2.ONE * 1.04, 0.12))
	p.mouse_exited.connect(func() -> void:
		p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.12))
	return p

## Join screen: 4-letter room code keypad, entering with the deck picked in the hub.
func _show_join(msg := "") -> void:
	_clear_fx()
	_clear()
	table.visible = false
	_set_tints(Color("#3f7bd9"), Color("#e0572b"), 1.6)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.position = Vector2(stage_w / 2.0 - 300, 90)
	box.custom_minimum_size = Vector2(600, 0)
	layer.add_child(box)
	box.add_child(_label("ENTRAR NA SALA", 48, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 8))
	box.add_child(_label(msg if msg != "" else "Deck: %s" % DeckDB.get_deck(sel_deck)["name"], 22, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	var slots := _label(_code_text(), 64, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6)
	box.add_child(slots)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for ch in "ABCDEFGHJKMNPQRSTUVWXYZ":
		var kb := _button(ch, func():
			if code_entry.length() < 4:
				code_entry += ch
				slots.text = _code_text())
		kb.custom_minimum_size = Vector2(68, 60)
		kb.add_theme_font_size_override("font_size", 26)
		grid.add_child(kb)
	var back := _button("⌫", func():
		code_entry = code_entry.substr(0, code_entry.length() - 1)
		slots.text = _code_text())
	back.custom_minimum_size = Vector2(68, 60)
	back.add_theme_font_size_override("font_size", 26)
	grid.add_child(back)
	var go := _button("ENTRAR NA SALA", func():
		if code_entry.length() == 4:
			online = true
			net.join(code_entry, sel_deck)
			_show_wait("Entrando na sala…"), true)
	go.custom_minimum_size = Vector2(600, 64)
	box.add_child(go)
	var bk := _button("Voltar", func() -> void: _show_online())
	bk.custom_minimum_size = Vector2(600, 52)
	box.add_child(bk)

func _code_text() -> String:
	return code_entry + "_".repeat(4 - code_entry.length())

func _show_wait(text: String, show_code := "") -> void:
	_clear_fx()
	_clear()
	table.visible = false
	_set_tints(Color("#3f7bd9"), Color("#e0572b"), 1.6)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.position = Vector2(stage_w / 2.0 - 300, 260)
	box.custom_minimum_size = Vector2(600, 0)
	layer.add_child(box)
	if show_code != "":
		box.add_child(_label("CÓDIGO DA SALA", 26, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
		box.add_child(_label(show_code, 120, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 12))
	box.add_child(_label(text, 28, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	var c := _button("Cancelar", func():
		net.forget()
		net.disconnect_server()
		online = false
		_show_menu())
	c.custom_minimum_size = Vector2(600, 56)
	box.add_child(c)

func _on_link(up: bool) -> void:
	if not online or g == null:
		return
	if up:
		_toast("Reconectado.")
	else:
		_toast("Conexão perdida… reconectando.")

func _on_net(m: Dictionary) -> void:
	match m.get("t", ""):
		"room":
			net.code = m["code"]
			net.token = m["token"]
			net.seat = m["seat"]
			net.want_resume = true
			net.remember()
			if m["seat"] == 0:
				_show_wait("Aguardando o oponente entrar…", m["code"])
		"start":
			var d: Array = m["decks"]
			var rs := RemoteState.new(d[0], d[1])
			rs.seat = m["seat"]
			rs.send = net.send
			rs.apply_snapshot(m["snap"])
			if not (g is RemoteState): # a reconnect keeps the lines already seen
				CardDB.reroll_flavor()
			g = rs
			# always resend: a toggle made while disconnected never reached the server
			rs.set_auto_pass(rs.seat, _auto_pass_on())
			vs_ai = false
			online = true
			viewer = m["seat"]
			pending_pass = false
			opp_online = true
			if log_lines.is_empty() or m.get("snap", {}).get("turn", 0) == 0:
				log_lines = ["Partida online iniciada."]
				conceded = -1
			_reset_input()
			_clear_fx()
			_render()
		"events":
			if not (g is RemoteState):
				return
			(g as RemoteState).apply_snapshot(m["snap"])
			_reset_input()
			for e in m["events"]:
				_log_event(e)
			_show_events(m["events"])
		"reject":
			_toast("Ação inválida.")
		"opponent":
			opp_online = m["connected"]
			_toast("Oponente reconectou." if opp_online else "Oponente desconectou.")
		"error":
			net.forget()
			online = false
			_show_online(String(m.get("msg", "Erro.")))

# ---------------------------------------------------------------- actions

func _do(events: Array) -> void:
	if g is RemoteState:
		return ## the server answers with "events" (see _on_net)
	if events.is_empty():
		_toast("Ação inválida.")
		_render() # brings back the action button that greyed out when it was pressed
		return
	_reset_input()
	for e in events:
		_log_event(e)
	var d := g.decider()
	if not vs_ai and d != viewer and g.phase != "over":
		viewer = d
		pending_pass = true
	_show_events(events)

func _ai_step() -> void:
	if g == null or g.phase == "over" or not _is_ai(g.decider()):
		return
	var ev := SimpleAI.step(g, g.decider())
	if ev.is_empty():
		return
	for e in ev:
		_log_event(e)
	_reset_input()
	_show_events(ev)

## Re-renders and animates from the previous frame's positions; the AI
## waits for the animations to play out before its next move.
func _show_events(events: Array) -> void:
	var remaining_ms := _animation_busy_until_ms - Time.get_ticks_msec()
	if remaining_ms > 0 or not _waiting_event_batches.is_empty():
		# an animation is still playing (or others are already waiting): get in line instead of
		# redrawing the table, which would cut the running animation short
		_waiting_event_batches.append(events)
		_waiting_events_timer.start(maxf(remaining_ms / 1000.0, 0.05))
		return
	_play_events(events)

## Plays the oldest waiting batch; the next one (if any) follows when this one settles.
func _play_waiting_events() -> void:
	if _waiting_event_batches.is_empty() or g == null:
		_waiting_event_batches.clear()
		return
	_play_events(_waiting_event_batches.pop_front())
	if not _waiting_event_batches.is_empty():
		_waiting_events_timer.start(maxf((_animation_busy_until_ms - Time.get_ticks_msec()) / 1000.0, 0.05))

func _play_events(events: Array) -> void:
	var old := _snapshot()
	_leader_ko_t = -1.0
	_over_from = -1
	_render_now() # not _render: other batches may still be waiting, and this one must be drawn now
	var end := _animate(events, old)
	_animation_busy_until_ms = Time.get_ticks_msec() + int(end * 1000.0)
	_settle_timer.start(maxf(end, 0.05))
	# the Victory/Defeat screen waits for the killing blow to land instead of spoiling it
	if g.phase == "over" and _over_from >= 0 and end > 0.0:
		var delay := maxf(_leader_ko_t + 0.7, end) if _leader_ko_t >= 0.0 else end
		for n in layer.get_children().slice(_over_from):
			n.modulate.a = 0.0
			var otw: Tween = n.create_tween()
			otw.tween_interval(delay)
			otw.tween_property(n, "modulate:a", 1.0, 0.35)
	if not ai_timer.is_stopped():
		ai_timer.start(max(0.55, end + 0.2))

func _is_ai(p: int) -> bool:
	return vs_ai and p == 1


# ---------------------------------------------------------------- render

func _clear() -> void:
	if layer:
		layer.queue_free()
	layer = Control.new()
	search_overlay = null
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	if fx:
		fx.move_to_front()
	views.clear()
	hand_uids.clear()

func _clear_fx() -> void:
	# a new screen or match: nothing from the previous one should still be waiting to play
	_waiting_event_batches.clear()
	_animation_busy_until_ms = 0
	_render_when_settled = false
	_queued_inputs.clear()
	_queued_attacker_uid = 0
	_queued_attacker_dragging = false
	if _settle_timer:
		_settle_timer.stop()
	if fx:
		for c in fx.get_children():
			c.queue_free()

## True while the screen has not caught up with the game: an animation is still playing, or batches of
## events the engine already applied are still waiting to be shown.
func _table_busy() -> bool:
	return Time.get_ticks_msec() < _animation_busy_until_ms or not _waiting_event_batches.is_empty()

## Redraws the table, unless an animation is playing: then the redraw waits until the table settles
## (drawing now would cut the animation short and could show things that have not happened on screen yet).
func _render() -> void:
	if _table_busy():
		_render_when_settled = true
		return
	_render_now()

## The last animation ended: draw the table if something asked for it meanwhile, then run the clicks
## the player gave during the animation, in the order they were given.
func _on_table_settled() -> void:
	if g == null or not _waiting_event_batches.is_empty():
		return # the next batch plays first (_play_waiting_events), and it starts this timer again
	var remaining_ms := _animation_busy_until_ms - Time.get_ticks_msec()
	if remaining_ms > 0:
		_settle_timer.start(remaining_ms / 1000.0) # the timer fired a hair early: wait the rest
		return
	_queued_attacker_uid = 0 # its waiting click picks it for real now
	_queued_attacker_dragging = false
	if _render_when_settled:
		_render_now()
	_run_queued_inputs()

## Runs the waiting clicks one by one. If one of them starts a new animation (an attack, a play...),
## the rest keep waiting for that one to end too: each click always sees the table it was aimed at.
func _run_queued_inputs() -> void:
	_replaying_queued_inputs = true
	while not _queued_inputs.is_empty() and not _table_busy() and g != null:
		var next_input: Callable = _queued_inputs.pop_front()
		next_input.call()
	_replaying_queued_inputs = false

## True when a click must wait in _queued_inputs instead of running now: the table is still animating,
## or older clicks are already waiting (they go first).
func _input_must_wait() -> bool:
	return _table_busy() or (not _replaying_queued_inputs and not _queued_inputs.is_empty())

## Runs the input now, or stores it to run once the table settles (see _input_must_wait).
func _run_or_queue_input(input: Callable) -> void:
	if _input_must_wait():
		_queued_inputs.append(input)
	else:
		input.call()

## Same idea, for the top of a click handler: when the table is busy, stores `input` (usually the
## handler itself, bound to a uid or player rather than to a view that the next redraw replaces)
## and returns true so the handler stops. The stored input re-checks everything when it runs.
func _wait_for_table(input: Callable) -> bool:
	if not _input_must_wait():
		return false
	_queued_inputs.append(input)
	return true

func _render_now() -> void:
	_render_when_settled = false
	_clear()
	drag_gap_slot = -1 # fresh board views have no gap
	var me := viewer
	var op := g.opponent(me)
	_set_tints(_leader_color(op), _leader_color(me))
	table.enemy_color = _leader_color(op)
	table.my_color = _leader_color(me)
	table.sockets = [Rect2(SANCTUARY_X, SANCTUARY_Y_OP, SANCTUARY_W, 264), Rect2(SANCTUARY_X, SANCTUARY_Y_ME, SANCTUARY_W, 264)]
	table.visible = true
	table.queue_redraw()
	if g.phase == "over":
		_close_concede()
	if pending_pass or g.phase in ["search", "over"]:
		_close_graveyard()
	else:
		_refresh_graveyard()
	if pending_pass:
		_render_pass()
		return
	# draw order = depth: the hands sit at the back, the Leaders in front of them, the units on top
	_render_command(op, Vector2(SANCTUARY_X + 1, SANCTUARY_Y_OP + 6.0))
	_render_command(me, Vector2(SANCTUARY_X + 1, SANCTUARY_Y_ME + 6.0))
	_render_enemy_hand(op)
	_render_hand(me)
	_render_leader(op, Vector2(lane_cx - LeaderView.CX, LEADER_Y_OP), Vector2(20, SANCTUARY_Y_OP - 62.0))
	_render_leader(me, Vector2(lane_cx - LeaderView.CX, LEADER_Y_ME), Vector2(20, SANCTUARY_Y_ME + 272.0))
	_render_board(op, 172)
	_render_board(me, 460)
	_sync_enter_aim()
	_render_side()
	_render_hint()
	if g.phase == "search":
		_render_search_reveal()
	if g.phase == "over":
		_over_from = layer.get_child_count()
		_render_game_over()
	elif _is_ai(g.decider()):
		ai_timer.start()

## Full-screen veil over the table with a centered panel.
func _veil(alpha := 0.72) -> PanelContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, alpha)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var pc := PanelContainer.new()
	var sb := UITheme.panel(14)
	sb.set_content_margin_all(36)
	sb.border_color = Color(UITheme.GOLD, 0.6)
	sb.shadow_size = 40
	pc.add_theme_stylebox_override("panel", sb)
	layer.add_child(pc)
	return pc

func _center(pc: Control) -> void:
	pc.reset_size()
	pc.position = (size - pc.size) / 2.0

func _render_pass() -> void:
	var p := viewer
	var pc := _veil(0.55)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 16)
	pc.add_child(box)
	box.add_child(_label("PASSE O DISPOSITIVO", 30, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6))
	box.add_child(_label("Jogador %d · %s" % [p + 1, CardDB.leader(g.players[p]["leader_id"])["name"]], 20, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	var b := _button("ESTOU PRONTO", func():
		pending_pass = false
		_render(), true)
	b.pressed.connect(func(): b.disabled = true) # answers at once even if the redraw waits for an animation
	b.custom_minimum_size = Vector2(460, 56)
	box.add_child(b)
	_center.call_deferred(pc)

func _render_leader(p: int, pos: Vector2, mom_pos: Vector2) -> void:
	var pl: Dictionary = g.players[p]
	var uid: int = GameState.LEADER_UID[p]
	var lv := LeaderView.new().setup(pl["leader_id"])
	lv.position = pos
	lv.hp = pl["leader_hp"]
	lv.hp_max = pl["leader_max"]
	lv.deck = pl["deck"].size()
	lv.fatigue = g.fatigue_next(p)
	lv.grave = pl["graveyard"].size()
	lv.poison = g.leader_dot_markers(p, "veneno")
	lv.requiem = g.requiem_cards(p).size() if p == viewer and not _is_ai(p) and g.phase in ["main", "combat"] else 0
	lv.ability_ready = p == viewer and g.can_use_ability(p) and not _is_ai(p)
	lv.targetable = _is_target(uid)
	lv.target_selected = _is_first_target(uid)
	lv.active = g.active == p and g.phase != "mulligan"
	lv.ability_clicked.connect(func(): _on_ability(p))
	lv.portrait_clicked.connect(func(): _on_leader_click(p))
	lv.grave_clicked.connect(func(): _show_graveyard(p))
	layer.add_child(lv)
	views[uid] = lv
	if lv.target_selected:
		_add_target_badges(lv, _target_selection_numbers(uid))
	var mb := MomentumBar.new()
	mb.position = mom_pos
	layer.add_child(mb)
	mb.setup(pl["momentum"], pl["max_momentum"], int(pl.get("reserve", 0)))

const HAND_SCALE := 1.4875 ## hand cards are cut at the bottom, so they can be bigger than the room they take
const HAND_SCALE_MIN := 1.3
const HAND_VISIBLE := 0.78 ## share of a hand card's height that shows (the rest hangs off the screen until hover/click)
const ENEMY_HAND_SCALE := 0.8
const ENEMY_HAND_SHOWN := 0.3 ## share of an (upside-down) enemy card that peeks in from the top edge
const HAND_SHRINK_FROM := 6
const HAND_SHRINK_TO := 10
const SANCTUARY_SCALE := 1.48 ## Incarnation card in the Sanctuary
## The Sanctuaries sit in the left margin, each beside its own lane, with the momentum bar next to them
const SANCTUARY_X := 20.0
const SANCTUARY_Y_OP := 132.0
const SANCTUARY_Y_ME := 440.0
const SANCTUARY_W := 180.0
const LEADER_Y_OP := 4.0 ## Leader plates: centered, between each hand and its board
const LEADER_Y_ME := 656.0
const EHAND_DX := 190.0 ## the opponent hand fans out beside their Leader

func _render_command(p: int, pos: Vector2) -> void:
	var l: Dictionary = g.players[p]["legendary"]
	if p == viewer:
		var cap := _label("SANTUÁRIO", 13, Color(UITheme.GOLD, 0.7), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
		cap.position = pos + Vector2(-1, -20)
		cap.size = Vector2(SANCTUARY_W, 16)
		layer.add_child(cap)
	if not l["in_zone"]:
		var empty := _label("NO DECK" if l.get("retired", false) else "EM CAMPO", 12, Color(UITheme.TEXT, 0.35), HORIZONTAL_ALIGNMENT_CENTER, "title", 2)
		empty.position = pos + Vector2(-1, 115)
		empty.size = Vector2(SANCTUARY_W, 20)
		layer.add_child(empty)
		return
	var v := CardView.new().setup(l["card_id"], {}, SANCTUARY_SCALE)
	v.pivot_offset = v.size / 2.0
	v.position = pos
	v.cost_override = g.legendary_cost(p)
	v.text_suffix = _scale_suffix(p, CardDB.card(l["card_id"]))
	v.snowball_level = int(g.players[p]["snowball"])
	if p == viewer and g.can_cast_legendary(p) and not _is_ai(p):
		v.highlight = OK
	if targeting.get("kind") == "legendary" and p == viewer:
		v.highlight = SEL
	v.left_clicked.connect(func(_v): _on_legendary(p))
	v.right_clicked.connect(_show_overlay)
	layer.add_child(v)
	views["cmd%d" % p] = v

## Stage y of the top / bottom edge of the screen. The window can show more than the stage (black
## bands on tall windows); hands hang off these real edges, so the cut is the edge of the screen.
func _screen_top() -> float:
	return -position.y

func _screen_bottom() -> float:
	return get_viewport().get_visible_rect().end.y - position.y

## Opponent's hand: face-down cards fanned along the top edge.
func _render_enemy_hand(p: int) -> void:
	var n: int = g.players[p]["hand"].size()
	for i in n:
		var k := float(i) - (n - 1) / 2.0
		var v := CardView.new().setup("", {}, ENEMY_HAND_SCALE)
		v.face_down = true
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.pivot_offset = v.size / 2.0
		v.rotation = PI - deg_to_rad(k * 4.0) # upside down, as if held facing the opponent
		v.position = Vector2(lane_cx + EHAND_DX + k * 30 - v.size.x / 2.0, _screen_top() - v.size.y * (1.0 - ENEMY_HAND_SHOWN) + k * k * 1.2)
		layer.add_child(v)
	if n > 0:
		var cnt := _label("%d" % n, 15, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 5)
		cnt.position = Vector2(lane_cx + EHAND_DX + (n - 1) / 2.0 * 30 + 52, _screen_top() + 18.0)
		cnt.size = Vector2(30, 20)
		layer.add_child(cnt)

## Horizontal cell of the unit at `index` in a lane holding `count` units: x = left edge, y = width.
## The lane is centered, so adding a unit shifts every cell (used to open a gap while dragging).
func _board_cell(count: int, index: int) -> Vector2:
	var w: float = min(146.0, (TableView.ENEMY_LANE.size.x - 20.0) / max(1, count))
	var x0 := TableView.ENEMY_LANE.get_center().x - count * w / 2.0
	return Vector2(x0 + index * w, w)

func _render_board(p: int, y: float) -> void:
	var board: Array = g.players[p]["board"]
	# units first, then the free-standing artifacts, then the slots frozen by Rei Gelado
	var slots_taken: int = _laid_out_slots(p)
	_render_relics(p, y, slots_taken)
	_render_frozen_slots(p, y, slots_taken)
	var barrier_gaps: Array = [] # where this side's Provocação barrier is open (see TableView.set_barrier)
	for i in board.size():
		var unit: Card = board[i]
		var unit_view_data := unit.to_dict()
		unit_view_data["armor_total"] = g.armor_of(unit) # includes Armadura given by adjacent allies
		var v := CardView.new().setup(unit.card_id, unit_view_data, 1.15)
		v.pivot_offset = v.size / 2.0
		var cell := _board_cell(slots_taken, i)
		v.position = Vector2(roundf(cell.x + (cell.y - v.size.x) / 2.0), roundf(y)) # whole pixels keep the card text crisp
		# exhausted (tapped) units lie sideways: they already attacked or used an ability, and the
		# enemy can challenge them. Lying down, the card's height runs along the row, so it shrinks
		# toward its cell width — but never below TAPPED_MIN_SCALE: on a full row it just overlaps
		# the neighbours slightly, which looks more natural than a tiny card.
		if unit.exhausted:
			v.rotation = deg_to_rad(TAPPED_TILT_DEGREES)
			var fit_cell_scale := (cell.y - 6.0) / v.size.y
			v.scale = Vector2.ONE * clampf(fit_cell_scale, TAPPED_MIN_SCALE, 1.0)
		_decorate_unit(v, unit, p)
		v.left_clicked.connect(_on_unit_click)
		v.right_clicked.connect(_show_overlay)
		# on touch an attacker is also dragged to its target (on a mouse the press already starts the aim)
		v.draggable = CardView.touch_ui() and p == viewer and _my_input() and targeting.is_empty() \
			and g.combat_system().in_attacks_window(viewer)
		v.drag_started.connect(_unit_drag_start)
		layer.add_child(v)
		views[unit.uid] = v
		var barrier_side: int = TableView.SIDE_MINE if p == viewer else TableView.SIDE_ENEMY
		var is_barring: bool = _slam_if_barricade_just_closed(unit, barrier_side, v.position.x + v.size.x / 2.0)
		if is_barring:
			# the opening is as wide as the tapped card lying down; it is the only way through the barrier
			barrier_gaps.append(Vector2(v.position.x + v.size.x / 2.0, v.size.y * v.scale.y + 6.0))
		if unit.is_frozen():
			_tag(v, "CONGELADA", ICE)
		if unit.equipment != null:
			# the equipment card sits under its unit, peeking out toward the middle of the table
			var eq := CardView.new().setup(unit.equipment.card_id, {"uid": unit.equipment.uid}, 1.15)
			eq.position = v.position + Vector2(8, 22 if p == viewer else -22)
			eq.right_clicked.connect(_show_overlay)
			layer.add_child(eq)
			layer.move_child(eq, v.get_index())
			views["eq%d" % unit.uid] = eq # kept so the drag gap can slide it along with its unit
	table.set_barrier(TableView.SIDE_MINE if p == viewer else TableView.SIDE_ENEMY, barrier_gaps)

## A tapped, not Congelada Provocação unit holds the barrier on the divider (drawn by TableView) shut
## except in front of itself. Returns whether `unit` is holding it right now.
## Cards are rebuilt on every render, so we remember last render's state per unit: one that was not
## barring and now is makes the barrier slam shut at its x. A unit seen for the first time only
## slams when it just entered (Provocação enters tapped).
func _slam_if_barricade_just_closed(unit: Card, barrier_side: int, center_x: float) -> bool:
	var barring_now: bool = unit.exhausted and g.has_kw(unit, "provocacao") and not unit.is_frozen()
	var barring_before: bool = barricade_was_up.get(unit.uid, not unit.sick)
	barricade_was_up[unit.uid] = barring_now
	if barring_now and not barring_before:
		table.slam(barrier_side, center_x)
	return barring_now

## Free-standing artifacts (Ossuário Sem Fundo...) stand in the lane right after the units,
## each one taking a slot. Click: pick it as a target, or open the overlay (with its Ativar button).
func _render_relics(p: int, y: float, slots_taken: int) -> void:
	var relics: Array = g.players[p]["relics"]
	var first_relic_slot: int = g.players[p]["board"].size()
	for j in relics.size():
		var relic: Card = relics[j]
		var v := CardView.new().setup(relic.card_id, {"uid": relic.uid}, 1.15)
		v.pivot_offset = v.size / 2.0
		var cell := _board_cell(slots_taken, first_relic_slot + j)
		v.position = Vector2(cell.x + (cell.y - v.size.x) / 2.0, y)
		v.ability_ready = p == viewer and targeting.is_empty() and _my_input() and g.can_activate(viewer, relic.uid)
		var selected_numbers := _target_selection_numbers(relic.uid)
		if not selected_numbers.is_empty():
			v.highlight = SEL
			_add_target_badges(v, selected_numbers)
		elif _is_target(relic.uid):
			v.highlight = TARGET
		v.left_clicked.connect(_on_relic_click)
		v.right_clicked.connect(_show_overlay)
		layer.add_child(v)
		views[relic.uid] = v

## How many cells the lane of player p is divided into: taken slots plus the ones frozen by Rei Gelado.
func _laid_out_slots(p: int) -> int:
	return g.slots_used(p) + int(g.players[p]["frozen_slots"])

## Slots frozen by Rei Gelado: ice tiles at the end of the lane. Nothing can be played into them.
func _render_frozen_slots(p: int, y: float, slots_taken: int) -> void:
	var frozen_count: int = int(g.players[p]["frozen_slots"])
	var first_frozen_slot: int = g.slots_used(p)
	for j in frozen_count:
		var tile := PanelContainer.new()
		tile.custom_minimum_size = CardView.BASE * 1.15
		tile.size = tile.custom_minimum_size
		tile.add_theme_stylebox_override("panel", UITheme.box(Color(ICE.darkened(0.75), 0.55), 8, ICE, 2))
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var snowflake := _label("❄", 44, ICE, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
		snowflake.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tile.add_child(snowflake)
		var cell := _board_cell(slots_taken, first_frozen_slot + j)
		tile.position = Vector2(cell.x + (cell.y - tile.size.x) / 2.0, y)
		layer.add_child(tile)
		_tag(tile, "CONGELADO", ICE)

func _on_relic_click(v: CardView) -> void:
	if _my_input() and not targeting.is_empty() and _wait_for_table(_pick_target_when_settled.bind(v.uid)):
		return
	if _my_input() and not targeting.is_empty() and _is_target(v.uid):
		_fire_target(v.uid)
	elif targeting.is_empty():
		_show_overlay(v)

## A relic (or a spell on the stack) picked as a target during an animation: fires once the table
## settles, if it is still a valid target.
func _pick_target_when_settled(uid: int) -> void:
	if _my_input() and not targeting.is_empty() and _is_target(uid):
		_fire_target(uid)

func _decorate_unit(v: CardView, unit: Card, p: int) -> void:
	# reminder for new players: the unit's "Ao Ativar" can be used now (even the turn it is summoned); Transformar works almost the same way, so it glows too
	v.ability_ready = p == viewer and targeting.is_empty() and _my_input() and (g.can_activate(viewer, unit.uid) or g.can_transform(viewer, unit.uid))
	var selected_numbers := _target_selection_numbers(unit.uid)
	if not selected_numbers.is_empty():
		v.highlight = SEL
		_add_target_badges(v, selected_numbers)
		return
	if _is_target(unit.uid):
		v.highlight = TARGET
		return
	if targeting.get("kind") == "attack" and targeting["uid"] == unit.uid:
		v.highlight = SEL # the attacker being aimed right now
		return
	# during our attacks, every unit that can still attack glows
	if p == viewer and targeting.is_empty() and _my_input() and g.combat_system().in_attacks_window(viewer) \
			and not g.attack_targets(unit).is_empty():
		v.highlight = OK

func _alive(v) -> bool:
	return v != null and is_instance_valid(v) and not v.is_queued_for_deletion() and v.visible

## Small enamel tag above a card ("ATACA", "BLOQUEIA"...).
func _tag(v: Control, t: String, col: Color) -> void:
	var pc := PanelContainer.new()
	var sb := UITheme.box(Color(col.darkened(0.7), 0.92), 4, col, 1, 4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(_label(t, 11, col.lightened(0.4), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3))
	var tag_count := 0
	for child in v.get_children():
		if child is PanelContainer:
			tag_count += 1
	v.add_child(pc)
	pc.reset_size()
	pc.position = Vector2((v.size.x - pc.size.x) / 2.0, -22 - tag_count * 22)

## Large numbered badges on targets already committed by a multi-target effect.
## They sit over the centre of the card art, making the pick order readable at a glance.
## Repeated targets get one badge per pick ("1" and "2").
func _add_target_badges(v: Control, numbers: Array) -> void:
	var badge_size := 60.0
	for i in numbers.size():
		var badge := PanelContainer.new()
		badge.custom_minimum_size = Vector2(badge_size, badge_size)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.z_index = 12
		var sb := UITheme.box(Color("#171221", 0.96), badge_size / 2.0, SEL, 3, 6)
		badge.add_theme_stylebox_override("panel", sb)
		badge.add_child(_label(str(numbers[i]), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 6))
		v.add_child(badge)
		badge.reset_size()
		var art_center := Vector2(v.size.x * 0.5, v.size.y * 0.3353)
		if v is LeaderView:
			art_center = LeaderView.ART.get_center()
		var x := art_center.x + (i - (numbers.size() - 1) / 2.0) * 48.0 - badge_size / 2.0
		badge.position = Vector2(x, art_center.y - badge_size / 2.0)

## The picks made so far by the current targeting flow, indexed from 1 for the UI.
func _target_selection_numbers(uid: int) -> Array:
	if targeting.is_empty():
		return []
	var picks: Array = targeting.get("picks", [])
	if picks.is_empty() and targeting.has("first"):
		picks = [targeting["first"]]
	var out: Array = []
	for i in picks.size():
		if int(picks[i]) == uid:
			out.append(i + 1)
	return out

## Full size up to HAND_SHRINK_FROM cards, shrinking linearly to HAND_SCALE_MIN at HAND_SHRINK_TO.
func _hand_scale(n: int) -> float:
	var t := clampf(float(n - HAND_SHRINK_FROM) / float(HAND_SHRINK_TO - HAND_SHRINK_FROM), 0.0, 1.0)
	return lerpf(HAND_SCALE, HAND_SCALE_MIN, t)

func _render_hand(p: int) -> void:
	var hand: Array = g.players[p]["hand"]
	var n := hand.size()
	_hand_base = layer.get_child_count()
	var sc := _hand_scale(n)
	var cw: float = CardView.BASE.x * sc
	var step: float = min(cw * 0.85, (TableView.ENEMY_LANE.size.x - 20.0 - cw) / max(1, n - 1))
	var ang: float = min(5.0, 36.0 / max(1, n))
	# MTG Arena style: the hand hangs off the bottom edge of the screen, so only HAND_VISIBLE of each
	# card shows. Hovered, dragged or selected cards rise by the hidden part and show whole.
	var hidden_height := CardView.BASE.y * sc * (1.0 - HAND_VISIBLE)
	var rise := hidden_height + 14.0
	var rest_y := _screen_bottom() - CardView.BASE.y * sc * HAND_VISIBLE
	for i in n:
		var hand_card: Card = hand[i]
		var v := CardView.new().setup(hand_card.card_id, hand_card.to_dict(), sc)
		var card_data := CardDB.card(hand_card.card_id)
		if g.is_subito_play(p, card_data):
			v.cost_override = g.subito_cost(p, card_data, hand_card) # Súbito: summoned now at its Súbito cost
		elif g.cost_of(p, card_data, hand_card) != int(card_data["cost"]):
			v.cost_override = g.cost_of(p, card_data, hand_card)
		v.text_suffix = _scale_suffix(p, card_data)
		v.snowball_level = int(g.players[p]["snowball"])
		var k := i - (n - 1) / 2.0
		v.pivot_offset = Vector2(v.size.x / 2.0, v.size.y)
		var pos := Vector2(lane_cx + k * step - v.size.x / 2.0, rest_y + k * k * 1.4)
		var rot := deg_to_rad(k * ang)
		if picked.has(hand_card.uid):
			pos.y -= rise + 20.0 # selected / targeted cards are raised and show whole
			v.highlight = TARGET if g.phase == "discard" else SEL
		elif targeting.get("uid", 0) == hand_card.uid and targeting.get("kind") == "hand":
			pos.y -= rise + 20.0
			v.highlight = SEL
		elif g.phase in ["main", "combat"] and g.can_play(p, hand_card.uid) and not _is_ai(p):
			v.highlight = OK
		v.position = pos
		v.rotation = rot
		v.left_clicked.connect(_on_hand_click)
		v.right_clicked.connect(_show_overlay)
		v.draggable = p == viewer and g.phase in ["main", "combat"] and targeting.is_empty() and _my_input() and g.can_play(p, hand_card.uid)
		v.drag_started.connect(_hand_drag_start)
		v.drag_moved.connect(_hand_drag_move)
		v.drag_ended.connect(_hand_drag_end)
		var rest := {"pos": pos, "rot": rot, "idx": i, "rise": rise}
		v.set_meta("rest", rest) # where a dragged card flies back to when the table can't be redrawn yet
		v.mouse_entered.connect(_hand_hover.bind(v, true, rest))
		v.mouse_exited.connect(_hand_hover.bind(v, false, rest))
		layer.add_child(v)
		views[hand_card.uid] = v
		hand_uids[hand_card.uid] = true

## Fan card lifts, straightens and grows under the cursor, and sits above its
## neighbours (GUI picking follows tree order) until the cursor leaves.
func _hand_hover(v: CardView, on: bool, rest: Dictionary) -> void:
	if not is_instance_valid(v) or v.is_queued_for_deletion() or CardView.touch_ui() or v.dragging:
		return
	if v.has_meta("tw"):
		var old: Tween = v.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	var tw := v.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	v.set_meta("tw", tw)
	if on:
		v.move_to_front()
		v.hit_pad = 40.0
		tw.tween_property(v, "position", rest["pos"] + Vector2(0, -rest["rise"]), 0.14)
		tw.tween_property(v, "rotation", 0.0, 0.14)
		tw.tween_property(v, "zoom", 1.28, 0.14)
	else:
		layer.move_child(v, min(layer.get_child_count() - 1, rest["idx"] + _hand_base))
		v.hit_pad = 0.0
		tw.tween_property(v, "position", rest["pos"], 0.14)
		tw.tween_property(v, "rotation", rest["rot"], 0.14)
		tw.tween_property(v, "zoom", 1.0, 0.14)

## Drag & drop: a playable hand card follows the pointer and is played when released over
## the board (above PLAY_LINE); released over the hand it snaps back.
## The line sits at the lower 20% of our Leader plate: as soon as the pointer is over the Leader
## (clearly out of the hand) the card counts as played, still short of where the hand begins.
const PLAY_LINE := LEADER_Y_ME + LeaderView.SIZE.y * 0.8
var drag_gap_slot := -1 ## slot the board is currently opened at while a unit is dragged (-1 = no gap)

func _hand_drag_start(v: CardView) -> void:
	if v.has_meta("tw"):
		var old: Tween = v.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	v.move_to_front()
	v.set_meta("aim", _hand_spec(v) != "")
	var tw := v.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(v, "rotation", 0.0, 0.12)
	tw.tween_property(v, "zoom", 1.12, 0.12)
	_hand_drag_move(v)

## Board position a unit dropped at local x would take: the number of our units whose centre is
## to its left. Measured on the resting layout (no gap) so the slot does not flicker as the gap opens.
func _drop_slot(x: float) -> int:
	var count: int = _laid_out_slots(viewer)
	var slot := 0
	for i in g.players[viewer]["board"].size(): # artifacts always stay after the units
		var cell := _board_cell(count, i)
		if x > cell.x + cell.y / 2.0:
			slot += 1
	return slot

## Hearthstone style: our units slide apart to leave a gap at `slot` (-1 = close it again).
func _show_drop_gap(slot: int) -> void:
	if slot == drag_gap_slot:
		return
	drag_gap_slot = slot
	var board: Array = g.players[viewer]["board"]
	var count: int = _laid_out_slots(viewer) + (1 if slot >= 0 else 0)
	for relic: Card in g.players[viewer]["relics"]: # artifacts sit after the units, so they always slide right
		var relic_view: Control = views.get(relic.uid)
		if not is_instance_valid(relic_view):
			continue
		var relic_index: int = board.size() + g.players[viewer]["relics"].find(relic) + (1 if slot >= 0 else 0)
		var relic_cell := _board_cell(count, relic_index)
		relic_view.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) 			.tween_property(relic_view, "position:x", relic_cell.x + (relic_cell.y - relic_view.size.x) / 2.0, 0.12)
	for i in board.size():
		var unit: Card = board[i]
		var unit_view: Control = views.get(unit.uid)
		if not is_instance_valid(unit_view):
			continue
		var cell := _board_cell(count, i + (1 if slot >= 0 and i >= slot else 0))
		var new_x := cell.x + (cell.y - unit_view.size.x) / 2.0
		var shift := new_x - unit_view.position.x
		var tw := unit_view.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(unit_view, "position:x", new_x, 0.12)
		var equipment_view: Control = views.get("eq%d" % unit.uid)
		if is_instance_valid(equipment_view):
			var eq_tw := equipment_view.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			eq_tw.tween_property(equipment_view, "position:x", equipment_view.position.x + shift, 0.12)

func _hand_drag_move(v: CardView) -> void:
	var m := layer.get_local_mouse_position()
	var is_unit: bool = CardDB.card(v.card_id)["type"] == "unit"
	# during an animation the board is left alone (the gap would fight the moving units) and no aim
	# starts: the card just follows the finger, and dropping it plays it once the animation ends
	var table_busy := _input_must_wait()
	if is_unit and m.y < PLAY_LINE and _my_input() and not v.get_meta("aim", false) and not table_busy:
		_show_drop_gap(_drop_slot(m.x))
	elif not table_busy:
		_show_drop_gap(-1)
	if v.get_meta("aim", false) and m.y < PLAY_LINE and targeting.is_empty() and _my_input() and not table_busy:
		# a targeted card crossing into the board turns into an aim: it goes back to the hand
		# (raised) and an arrow follows the finger; releasing on a target plays it there
		# (a unit with a sacrifice cost also remembers the slot it was dragged to)
		targeting = {"kind": "hand", "uid": v.uid, "card_id": v.card_id, "spec": _hand_spec(v), "slot": _drop_slot(m.x)}
		aim_drag = true
		aim_start = Vector2.INF
		_render()
		return
	v.position = m - Vector2(v.size.x / 2.0, v.size.y * 0.75)
	v.highlight = SEL if m.y < PLAY_LINE else OK

func _hand_drag_end(v: CardView) -> void:
	var m := layer.get_local_mouse_position()
	if _input_must_wait():
		# an animation is playing: the card flies back to the hand and, if it was dropped on the board,
		# is played from there as soon as the animation ends
		_hand_card_back_to_rest(v)
		if m.y < PLAY_LINE and _my_input():
			_queued_inputs.append(_play_hand_card_when_settled.bind(v.uid, _drop_slot(m.x)))
			v.highlight = SEL
		return
	drag_gap_slot = -1
	if m.y < PLAY_LINE and _my_input():
		_play_from_hand(v, _drop_slot(m.x))
	else:
		_render()

## A dragged hand card glides back to its place in the fan (used when the table can't be redrawn yet).
func _hand_card_back_to_rest(v: CardView) -> void:
	if not v.has_meta("rest"):
		return
	var rest: Dictionary = v.get_meta("rest")
	layer.move_child(v, min(layer.get_child_count() - 1, rest["idx"] + _hand_base))
	var tw := v.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	v.set_meta("tw", tw)
	tw.tween_property(v, "position", rest["pos"], 0.18)
	tw.tween_property(v, "rotation", rest["rot"], 0.18)
	tw.tween_property(v, "zoom", 1.0, 0.18)

## Plays a hand card that was dropped on the board during an animation (if it can still be played).
func _play_hand_card_when_settled(uid: int, slot: int) -> void:
	var view = views.get(uid)
	if _my_input() and is_instance_valid(view) and view is CardView and hand_uids.has(uid):
		_play_from_hand(view, slot)

func _render_side() -> void:
	# chronicle (log)
	var lp := Panel.new()
	lp.position = Vector2(col_x, 14)
	lp.size = Vector2(COL_W, 300)
	lp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(lp)
	var lh := _label("CRÔNICA", 17, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	lh.position = Vector2(0, 4)
	lh.size = Vector2(COL_W, 24)
	lp.add_child(lh)
	lp.add_child(_ornament(Vector2(COL_W / 2.0, 30), 80))
	var vb := VBoxContainer.new()
	vb.position = Vector2(12, 36)
	vb.size = Vector2(COL_W - 24, 258)
	vb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_theme_constant_override("separation", 3)
	vb.clip_contents = true
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lp.add_child(vb)
	var shown := log_lines.slice(max(0, log_lines.size() - 7))
	for i in shown.size():
		var line: String = shown[i]
		var fresh := float(i + 1) / shown.size()
		var head := line.begins_with("—")
		var l: Label
		if head:
			l = _label(line.trim_prefix("— ").trim_suffix(" —").to_upper(), 17, Color(UITheme.GOLD, 0.35 + 0.65 * fresh), HORIZONTAL_ALIGNMENT_CENTER, "title_bold")
		else:
			l = _label(line, 19, Color(UITheme.TEXT, 0.3 + 0.7 * fresh), HORIZONTAL_ALIGNMENT_LEFT, "body")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = COL_W - 24
		vb.add_child(l)

	# turn plaque
	var phase_names := {"mulligan": "Mulligan", "main": "Fase Principal", "discard": "Banimento", "over": "Fim de jogo",
		"combat": "Combate · " + {"pre_combat": "Preparação", "attacks": "Ataques"}.get(g.window, ""), "search": "Busca",
		"enter_target": "Ao Entrar · alvo", "enter_tapped": "Provocação · entrada"}
	var mine := g.decider() == viewer and not _is_ai(viewer)
	var tp := Panel.new()
	tp.position = Vector2(col_x, 326)
	tp.size = Vector2(COL_W, 84)
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := UITheme.panel()
	if mine:
		tsb.border_color = Color(UITheme.GOLD, 0.85)
		tsb.shadow_color = Color(UITheme.GOLD, 0.2)
	tp.add_theme_stylebox_override("panel", tsb)
	layer.add_child(tp)
	var tt := _label("TURNO %d" % g.turn, 24, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 4)
	tt.position = Vector2(0, 4)
	tt.size = Vector2(COL_W, 30)
	tp.add_child(tt)
	var ph_t: String = phase_names.get(g.phase, g.phase)
	if not g.stack.is_empty():
		ph_t = "Resposta · pilha %d" % g.stack.size()
	elif g.summon_window:
		ph_t = "Resposta · invocação"
	var ph := _label(ph_t, 17, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	ph.position = Vector2(0, 33)
	ph.size = Vector2(COL_W, 22)
	tp.add_child(ph)
	var d := g.decider()
	var who := "SUA VEZ" if mine else ("VEZ DA IA" if _is_ai(d) else ("VEZ DO OPONENTE" if online else "VEZ DO JOGADOR %d" % (d + 1)))
	var wl := _label(who, 15, UITheme.GOLD if mine else Color(UITheme.TEXT, 0.5), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	wl.position = Vector2(0, 57)
	wl.size = Vector2(COL_W, 22)
	tp.add_child(wl)

	# actions
	var y := 424.0
	if mine:
		for b: Button in _action_buttons():
			b.position = Vector2(col_x, y)
			b.size = Vector2(COL_W, 56 if b.theme_type_variation == "PrimaryButton" else 40)
			layer.add_child(b)
			y += b.size.y + 10
	elif g.phase != "over":
		var wait := _button("TURNO DO OPONENTE", func(): pass)
		wait.disabled = true
		wait.position = Vector2(col_x, y)
		wait.size = Vector2(COL_W, 56)
		layer.add_child(wait)
	_render_stack()
	var ap_on := _auto_pass_on()
	var ap := _toggle_button("AUTO-PASSE", ap_on, func(): _set_auto_pass(not _auto_pass_on()))
	ap.position = Vector2(col_x, 772.0 + BOT)
	ap.size = Vector2(COL_W, 48)
	ap.tooltip_text = "Pula sozinho as janelas em que você não tem nenhuma jogada válida."
	layer.add_child(ap)
	var half := (COL_W - 8.0) / 2.0
	var menu := _button("Menu", _show_menu)
	menu.position = Vector2(col_x, 832.0 + BOT)
	menu.size = Vector2(COL_W if g.phase == "over" else half, 52)
	menu.add_theme_font_size_override("font_size", 20)
	layer.add_child(menu)
	if g.phase != "over":
		var cc := _button("Conceder", _ask_concede)
		cc.position = Vector2(col_x + half + 8.0, 832.0 + BOT)
		cc.size = Vector2(half, 52)
		cc.add_theme_font_size_override("font_size", 18)
		cc.tooltip_text = "Desiste da partida: o oponente vence."
		layer.add_child(cc)

## The stack as a pile of full cards at the right edge of the table, oldest on top and the
## next one to resolve in front (Arena style). Tap/right-click/hold a card to read it; the
## front card draws an arrow to what it targets.
const STACK_SCALE := 1.3
const STACK_STEP := 80.0 ## vertical peek per card; shrinks when the pile would not fit
const STACK_MAX_H := 590.0
const STACK_MAX := 6
var _stack_seen := {} ## sid -> true for items already drawn once (only new ones animate in)

func _render_stack() -> void:
	if g.stack.is_empty():
		_stack_seen.clear()
		return
	var cw := CardView.BASE.x * STACK_SCALE
	var ch := CardView.BASE.y * STACK_SCALE
	var items: Array = g.stack.slice(maxi(0, g.stack.size() - STACK_MAX))
	var hidden: int = g.stack.size() - items.size()
	var pw := cw + 32.0
	var step := STACK_STEP
	if items.size() > 1:
		step = minf(STACK_STEP, (STACK_MAX_H - 84.0 - ch) / (items.size() - 1))
	var ph := 44.0 + ch + step * (items.size() - 1) + 40.0
	var px := col_x - 14.0 - pw
	var py := clampf(TableView.DIVIDER_Y - ph / 2.0, 118.0, 700.0 - ph)
	var back := Panel.new()
	back.position = Vector2(px, py)
	back.size = Vector2(pw, ph)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bsb := UITheme.box(Color(0.035, 0.03, 0.06, 0.88), 14, Color(UITheme.GOLD, 0.6), 2, 22)
	bsb.shadow_color = Color(UITheme.GOLD, 0.2)
	back.add_theme_stylebox_override("panel", bsb)
	layer.add_child(back)
	var head := _label("PILHA · %d" % g.stack.size(), 16, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	head.position = Vector2(px, py + 10)
	head.size = Vector2(pw, 22)
	layer.add_child(head)
	if hidden > 0:
		var more := _label("+%d antigas" % hidden, 12, Color(UITheme.TEXT, 0.55), HORIZONTAL_ALIGNMENT_CENTER, "body")
		more.position = Vector2(px, py + 30)
		more.size = Vector2(pw, 14)
		layer.add_child(more)
	var cx := px + 16.0
	var y0 := py + 44.0
	var centers := {} ## sid -> center of that card, for arrows that point at a stack item
	var seen := {}
	for i in items.size():
		var it: Dictionary = items[i]
		var sid: int = it["sid"]
		seen[sid] = true
		var pos := Vector2(cx, y0 + step * i)
		centers[sid] = pos + Vector2(cw, ch) / 2.0
		var is_front := i == items.size() - 1
		var node: Control
		if it["kind"] == "ability":
			node = _stack_ability_card(it, Vector2(cw, ch))
		else:
			var v := CardView.new().setup(it["card_id"], {}, STACK_SCALE)
			v.left_clicked.connect(func(view: CardView):
				# a spell on the stack picked as a target during an animation waits for its turn
				if _my_input() and not targeting.is_empty() and _wait_for_table(_pick_target_when_settled.bind(sid)):
					return
				if _is_target(sid):
					_fire_target(sid)
				else:
					_show_overlay(view))
			v.right_clicked.connect(_show_overlay)
			if _is_target(sid):
				v.highlight = SEL
			node = v
		node.position = pos
		layer.add_child(node)
		# owner tab on the left edge: whose spell is whose, at a glance
		var tab := Panel.new()
		tab.position = Vector2(cx - 9.0, pos.y + 4.0)
		tab.size = Vector2(6, (ch if is_front else step) - 8.0)
		tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.add_theme_stylebox_override("panel", UITheme.box(_leader_color(it["player"]), 3))
		layer.add_child(tab)
		if it["kind"] in ["unit_ability", "subito", "enter_trigger"]:
			var rb := _stack_pill({"unit_ability": "AO ATIVAR", "subito": "SÚBITO", "enter_trigger": "AO ENTRAR"}[it["kind"]], UITheme.GOLD_LIGHT)
			rb.position = Vector2(cx + 6.0, pos.y + 4.0)
			layer.add_child(rb)
		var price := _counter_price(sid)
		if price != "":
			var pb := _stack_pill(price, SEL)
			pb.position = Vector2(cx + cw - 8.0 - pb.size.x, pos.y + 4.0)
			layer.add_child(pb)
		if not _stack_seen.has(sid):
			node.modulate.a = 0.0
			node.position = pos + Vector2(-70, 0)
			var tw := node.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(node, "modulate:a", 1.0, 0.22)
			tw.tween_property(node, "position", pos, 0.26)
	_stack_seen = seen
	# caption under the pile: who owns the next thing to resolve, and its speed
	var top: Dictionary = items[-1]
	var sp: String = {"lento": "Lento", "rapido": "Rápido", "instantaneo": "Instantâneo"}.get(top["speed"], "")
	var cap := _label("%s · %s\nresolve primeiro" % [_pname(top["player"]), sp], 13, Color(UITheme.TEXT, 0.7), HORIZONTAL_ALIGNMENT_CENTER, "body")
	cap.position = Vector2(px, py + ph - 38.0)
	cap.size = Vector2(pw, 34)
	layer.add_child(cap)
	_stack_arrow(top, centers, Vector2(px - 4.0, y0 + step * (items.size() - 1) + ch / 2.0))
	_stack_target_badges(top)

## What the front item aims at (a unit, a Leader or another stack item).
func _stack_arrow(it: Dictionary, centers: Dictionary, from: Vector2) -> void:
	var t: int = int(it.get("target", 0))
	if t == 0:
		return
	var to := Vector2.ZERO
	if centers.has(t):
		to = centers[t]
	elif views.get(t) is Control and is_instance_valid(views[t]):
		to = _pose(views[t])["c"]
	else:
		return
	var arrow := AimArrow.new()
	arrow.from = from
	arrow.to = to
	arrow.locked = true
	layer.add_child(arrow)

## Number the targets of the spell/ability currently in front of the stack.
## This keeps the confirmation visible after the second click, including when both
## picks point at the same unit.
func _stack_target_badges(it: Dictionary) -> void:
	var first := int(it.get("target", 0))
	var second := int(it.get("target2", 0))
	if first != 0 and views.has(first) and is_instance_valid(views[first]):
		var numbers: Array = [1]
		if second == first:
			numbers.append(2)
		_add_target_badges(views[first], numbers)
	if second != 0 and second != first and views.has(second) and is_instance_valid(views[second]):
		_add_target_badges(views[second], [2])

func _stack_pill(t: String, col: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.box(Color(0.03, 0.03, 0.05, 0.92), 9, Color(col, 0.8), 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", sb)
	pc.add_child(_label(t, 12, col, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	pc.reset_size()
	return pc

## A Leader ability on the stack: a card-sized plate (it has no card art).
func _stack_ability_card(it: Dictionary, sz: Vector2) -> Control:
	var sid: int = it["sid"]
	var lead := CardDB.leader(g.players[it["player"]]["leader_id"])
	var pnl := Panel.new()
	pnl.size = sz
	var sb := UITheme.box(Color(0.08, 0.06, 0.12), 10, Color(UITheme.GOLD, 0.85), 2, 8)
	sb.bg_color = Color(0.09, 0.07, 0.14)
	if _is_target(sid):
		sb.border_color = SEL
		sb.set_border_width_all(4)
		pnl.mouse_filter = Control.MOUSE_FILTER_STOP
		pnl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_fire_target(sid))
	else:
		pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pnl.add_theme_stylebox_override("panel", sb)
	var nm := _label(String(lead["ability"]["name"]), 19, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	nm.position = Vector2(8, 8)
	nm.size = Vector2(sz.x - 16, 56)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pnl.add_child(nm)
	var sub := _label("Habilidade de Líder\n%s" % String(lead.get("name", "")), 13, Color(UITheme.TEXT, 0.7), HORIZONTAL_ALIGNMENT_CENTER, "body")
	sub.position = Vector2(8, sz.y - 54)
	sub.size = Vector2(sz.x - 16, 44)
	pnl.add_child(sub)
	return pnl

## "Anular: N" for a stack item while a counter is choosing its target ("" otherwise).
func _counter_price(sid: int) -> String:
	if targeting.get("spec") != "enemy_stack" or not _is_target(sid):
		return ""
	for hand_card: Card in g.players[viewer]["hand"]:
		if hand_card.uid == targeting["uid"]:
			var card_data := CardDB.card(hand_card.card_id)
			var extra := g.counter_extra(card_data, sid)
			return "Anular: %d" % (g.cost_of(viewer, card_data) + extra) + (" (+%d)" % extra if extra > 0 else "")
	return ""

## Contextual hint in a pill on the central divider.
func _render_hint() -> void:
	var t := _hint()
	if t == "" or g.phase == "over":
		return
	var pc := PanelContainer.new()
	var sb := UITheme.box(Color(0.03, 0.03, 0.05, 0.94), 20, Color(UITheme.GOLD, 0.75), 2, 8)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := SEL if not targeting.is_empty() or g.phase == "enter_tapped" else UITheme.TEXT
	pc.add_child(_label(t, 26, col, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	layer.add_child(pc)
	pc.reset_size()
	pc.position = Vector2(TableView.ENEMY_LANE.get_center().x - pc.size.x / 2.0, TableView.DIVIDER_Y + 18) # below the divider emblem
	var now := Time.get_ticks_msec()
	if t != hint_text:
		hint_text = t
		hint_since = now
	hint_pill = pc
	if not targeting.is_empty() or g.phase in ["search", "discard", "enter_tapped"]:
		return # choices in progress keep their instructions on screen
	var left := maxi(hint_since + HINT_MS, hint_until) - now
	if left <= 0:
		pc.modulate.a = 0.0
	else:
		_hint_fade(pc, left / 1000.0)

const HINT_MS := 3500

func _hint_fade(pc: Control, hold: float) -> void:
	var tw := pc.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.2)
	tw.tween_interval(hold)
	tw.tween_property(pc, "modulate:a", 0.0, 0.5)

## Bring the tip back (idle for long, or a click that did nothing).
func _hint_nudge() -> void:
	if not is_instance_valid(hint_pill) or hint_pill.modulate.a > 0.01 or not _my_input():
		return
	hint_until = Time.get_ticks_msec() + 5000
	_hint_fade(hint_pill, 5.0)

func _process(_dt: float) -> void:
	_update_aim()
	if g and Time.get_ticks_msec() - last_input_ms > 15000:
		last_input_ms = Time.get_ticks_msec()
		_hint_nudge()

func _hint() -> String:
	if g.phase == "search":
		if g.pending_search.get("hand_summon", false):
			return "Escolha um campeão da sua mão para entrar em campo de graça."
		return "Escolha uma carta da sua mão para descartar." if g.pending_search.get("discard_hand", false) else "Escolha uma das cartas reveladas."
	if targeting.get("kind") == "enter":
		var which := "segundo alvo" if g.pending_enter.has("first") else "alvo"
		return "Ao Entrar de %s: toque no %s ou pule o efeito." % [_cname(g.pending_enter.get("card_id", "")), which]
	if targeting.get("kind") == "attack":
		# say why some targets don't glow: a Provocação forces the challenge, any tapped enemy
		# closes the face, and a unit that just came in with Ímpeto can only challenge
		var attacker := g.find_unit(targeting["uid"])
		var taunts: Array = g.combat_system().forced_taunts(attacker) if attacker != null else []
		if not taunts.is_empty():
			var taunt_names: Array = []
			for taunt_uid in taunts:
				taunt_names.append(_cname(g.find_unit(taunt_uid).card_id))
			return "Provocação: este ataque precisa desafiar %s." % " ou ".join(taunt_names)
		# (a Congelada unit doesn't guard the face, so only say this when the face really is closed)
		if attacker != null and not attacker.sick and not g.combat_system().challengeable_units(attacker).is_empty() 				and not g.combat_system().attack_targets(attacker).has(GameState.LEADER_UID[g.opponent(attacker.owner)]):
			return "Há unidades inimigas exauridas: elimine-as antes de atacar o Líder."
		if attacker != null and g.combat_system().is_rompante_rush(attacker):
			return "Rompante: no turno em que entra, ela ignora as exauridas e vai no Líder (só uma Provocação a segura)."
		if attacker != null and attacker.sick:
			return "Ímpeto: no turno em que entra, ela só pode desafiar (o Líder fica para o próximo turno)."
		if CardView.touch_ui():
			return "Toque no alvo que brilha (Líder ou unidade exaurida) · toque fora cancela."
		return "Arraste até o alvo que brilha (Líder ou unidade exaurida) · botão direito/Esc cancela."
	if not targeting.is_empty():
		if targeting.has("first"):
			var second_hint := "1º alvo escolhido. Escolha o 2º alvo (pode ser o mesmo)." if CardDB.card(targeting["card_id"]).get("same_target_ok", false) else "1º alvo escolhido. Escolha o 2º alvo."
			return second_hint
		var t := "Arraste até o alvo (ou toque nele) · toque fora cancela." if CardView.touch_ui() else "Arraste até o alvo (ou clique nele) · botão direito/Esc cancela."
		if targeting["spec"] == "enemy_stack":
			t = "Toque no feitiço/habilidade da pilha que quer anular."
		return t
	if g.decider() != viewer or _is_ai(viewer):
		return ""
	if g.phase in ["main", "combat"] and g.stack_passed and not g.stack.is_empty():
		return "O oponente passou: empilhe outro Instantâneo ou passe para resolver a pilha."
	if g.phase in ["main", "combat"] and not g.stack.is_empty():
		return "Responda com um Instantâneo ou passe para resolver a pilha."
	if g.phase == "main" and g.summon_window:
		return "Unidade invocada: responda com um efeito Rápido/Instantâneo ou passe."
	match g.phase:
		"combat":
			match g.window:
				"pre_combat":
					if viewer == g.active:
						return "Antes dos ataques: efeitos Rápidos/Instantâneos ou passe."
					return "O oponente vai atacar: responda com Rápidos/Instantâneos ou passe."
				"attacks":
					if viewer == g.active:
						return "Arraste uma unidade até o alvo para atacar · ENCERRAR COMBATE quando acabar."
		"enter_tapped":
			return "%s tem Provocação: entrar exaurida obriga os inimigos a desafiá-la." % _cname(_pending_tap_card_id())
		"mulligan":
			return "Clique em até 3 cartas para trocar."
		"discard":
			return "Mão acima de 10: escolha %d para banir." % (g.players[viewer]["hand"].size() - GameState.HAND_LIMIT)
		"main":
			if CardView.touch_ui():
				return "Arraste cartas para o campo · toque: ver carta · quando acabar, IR PARA O COMBATE"
			return "Arraste cartas para o campo · clique: ver carta · quando acabar, IR PARA O COMBATE"
	return ""

## "RESOLVER" when passing now makes the stack resolve (the other player already passed on it);
## otherwise it just hands the turn to respond over, so it stays "PASSAR".
func _pass_button_label() -> String:
	var passing_resolves: bool = not g.stack.is_empty() and (g.stack_passed or not g.self_response_enabled)
	return "RESOLVER" if passing_resolves else "PASSAR"

## "PASSAR TUDO": while answering the opponent's moves, a second button that passes this window and every
## later one until their turn ends, so the player isn't asked again for each play. Empty on your own turn.
func _pass_everything_buttons() -> Array:
	if g.active == viewer:
		return []
	var button := _action_button("Passar tudo no turno", func(): _do(g.pass_rest_of_turn(viewer)))
	button.add_theme_font_size_override("font_size", 18)
	button.tooltip_text = "Não pergunta mais por respostas até o turno do oponente acabar."
	return [button]

func _action_buttons() -> Array:
	var out: Array = []
	match g.phase:
		"mulligan":
			out.append(_action_button("CONFIRMAR (%d)" % picked.size(), func(): _do(g.mulligan(viewer, picked.duplicate())), true))
		"combat":
			if g.combat_system().in_attacks_window(viewer):
				out.append(_action_button("ENCERRAR COMBATE", func(): _do(g.end_combat(viewer)), true))
			else:
				out.append(_action_button(_pass_button_label(), func(): _do(g.pass_priority(viewer)), true))
				out.append_array(_pass_everything_buttons())
		"main":
			if not g.stack.is_empty() or g.summon_window:
				out.append(_action_button(_pass_button_label(), func(): _do(g.pass_priority(viewer)), true))
				out.append_array(_pass_everything_buttons())
			elif g.can_go_to_combat(viewer):
				out.append(_action_button("IR PARA O COMBATE", func(): _do(g.go_to_combat(viewer)), true))
				out.append(_action_button("Encerrar turno", func(): _do(g.end_turn(viewer))))
			else:
				out.append(_action_button("ENCERRAR TURNO", func(): _do(g.end_turn(viewer)), true))
		"enter_tapped":
			out.append(_action_button("ENTRAR EXAURIDA", func(): _do(g.choose_enter_tapped(viewer, true)), true))
			out.append(_action_button("ENTRAR PRONTA", func(): _do(g.choose_enter_tapped(viewer, false)), true))
		"enter_target":
			out.append(_action_button("PULAR EFEITO", func(): _do(g.choose_enter_target(viewer, 0)), true))
		"discard":
			var need: int = g.players[viewer]["hand"].size() - GameState.HAND_LIMIT
			var b := _action_button("BANIR (%d/%d)" % [picked.size(), need], func(): _do(g.discard(viewer, picked.duplicate())), true)
			b.disabled = picked.size() != need
			out.append(b)
	return out

func _render_game_over() -> void:
	var pc := _veil()
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 14)
	pc.add_child(box)
	var txt := "EMPATE" if g.winner == 2 else "JOGADOR %d VENCEU" % (g.winner + 1)
	var won := true
	if online and g.winner < 2:
		won = g.winner == viewer
		txt = "VITÓRIA" if won else "DERROTA"
	elif vs_ai and g.winner < 2:
		won = g.winner == 0
		txt = "VITÓRIA" if won else "DERROTA"
	var big := _label(txt, 64 if txt.length() < 10 else 44, UITheme.GOLD_LIGHT if won else Color("#e0a8a0"), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 10)
	big.add_theme_color_override("font_shadow_color", Color(UITheme.GOLD if won else UITheme.HP, 0.35))
	big.add_theme_constant_override("shadow_outline_size", 24)
	big.add_theme_constant_override("shadow_offset_x", 0)
	big.add_theme_constant_override("shadow_offset_y", 0)
	box.add_child(big)
	if g.winner < 2:
		var sub := "%s triunfa na arena" % CardDB.leader(g.players[g.winner]["leader_id"])["name"]
		if conceded >= 0:
			sub = "%s desistiu da partida" % ("Você" if (vs_ai and conceded == 0) else _pname(conceded))
		box.add_child(_label(sub, 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	box.add_child(_label("Turno %d" % g.turn, 14, Color(UITheme.TEXT, 0.4), HORIZONTAL_ALIGNMENT_CENTER, "title"))
	var b := _button("VOLTAR AO MENU", _show_menu, true)
	b.custom_minimum_size = Vector2(520, 54)
	box.add_child(b)
	_center.call_deferred(pc)

# ---------------------------------------------------------------- input

## Window <-> full screen (F11 or the menu button). In a browser this is the page's full screen,
## which the browser only allows right after a key press or tap, which is what calls this.
func _toggle_fullscreen() -> void:
	var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_full else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if aim_drag and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		_aim_release()
	elif _queued_attacker_dragging and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		_release_queued_attacker_drag()
	if e is InputEventMouseButton or e is InputEventScreenTouch or e is InputEventKey:
		last_input_ms = Time.get_ticks_msec()
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		CardView.touched = true
	if grave_view and _grave_scroll_input(e):
		get_viewport().set_input_as_handled()
	elif is_instance_valid(hub_scroll) and _hub_scroll_input(e):
		get_viewport().set_input_as_handled()

## Drag-aim released: on a target fires; barely moved (a plain click on the source) keeps
## click-targeting; anywhere else cancels, like dropping the card back.
func _aim_release() -> void:
	aim_drag = false
	if targeting.is_empty() or not _my_input():
		return
	var gp := get_global_mouse_position()
	get_viewport().set_input_as_handled()
	if _input_must_wait():
		# an animation is playing: what is a legal target is decided once it ends, so remember the
		# card under the pointer (any card) and pick it then
		var card_uid := _card_uid_at(gp)
		if card_uid != 0 and card_uid != targeting.get("uid", 0):
			_queued_inputs.append(_click_card_when_settled.bind(card_uid))
		return
	var u := _target_at(gp)
	if u != 0:
		_fire_target(u)
		return
	if gp.distance_to(aim_start) < CardView.DRAG_PX * 2.0 or targeting.has("first") or targeting["spec"] == "enemy_stack" 			or targeting["kind"] == "enter":
		return
	targeting = {}
	_render()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and g and not overlay:
		_hint_nudge() # a click that hit nothing: the player may be lost
	if overlay and e is InputEventMouseButton and e.pressed:
		_close_overlay()
		return
	if grave_view and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_close_graveyard()
		return
	var cancel: bool = (e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE) \
		or (e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_RIGHT or CardView.touch_ui()))
	if cancel and g and _queued_attacker_uid != 0:
		# the attacker picked during the animation is dropped too (its waiting pick is undone right after it)
		_queued_attacker_uid = 0
		_queued_attacker_dragging = false
		_queued_inputs.append(_cancel_targeting)
		return
	if cancel and g and not targeting.is_empty() and targeting["kind"] != "enter":
		if _input_must_wait():
			_queued_inputs.append(_cancel_targeting) # cancels in order, after the clicks already waiting
		else:
			_cancel_targeting()

## Drops the current aim (attacker, targeted card...); an Ao Entrar target can only be skipped by its button.
func _cancel_targeting() -> void:
	if not targeting.is_empty() and targeting["kind"] != "enter":
		targeting = {}
		_render()

func _my_input() -> bool:
	return g.decider() == viewer and not _is_ai(viewer) and not pending_pass

func _on_hand_click(v: CardView) -> void:
	if not _my_input():
		return
	if targeting.get("kind") == "hand" and targeting["uid"] == v.uid:
		targeting = {}
		_render()
		return
	match g.phase:
		"mulligan":
			_toggle_pick(v.uid, GameState.MULLIGAN_MAX)
		"discard":
			_toggle_pick(v.uid, g.players[viewer]["hand"].size() - GameState.HAND_LIMIT)
		"main", "combat":
			_show_overlay(v) # a click/tap only inspects; playing is drag & drop (no misclicks)

## slot: where a unit enters our board (-1 = rightmost); only drag & drop picks one.
func _play_from_hand(v: CardView, slot := -1) -> void:
	if not g.can_play(viewer, v.uid):
		_toast("Não dá para jogar essa carta agora.")
		_render()
		return
	var spec := _hand_spec(v)
	if spec != "":
		targeting = {"kind": "hand", "uid": v.uid, "card_id": v.card_id, "spec": spec, "slot": slot}
		_begin_aim(Vector2.ZERO)
		_render()
	elif CardDB.card(v.card_id)["type"] != "unit" and g.is_dud(viewer, CardDB.card(v.card_id)):
		# allowed (it can bait a counter), but never by accident
		_render()
		_ask_confirm("SEM EFEITO AGORA", "Não há nada para reviver no seu cemitério. Jogar mesmo assim?", "JOGAR MESMO ASSIM", "CANCELAR", _play_dud.bind(v.uid))
	else:
		_do(g.play_card(viewer, v.uid, 0, 0, slot))

## Casts a Réquiem spell from the graveyard through the same flow as a hand card (target aiming, dud confirm).
func _cast_requiem(uid: int, card_id: String) -> void:
	var stand_in := CardView.new().setup(card_id, {"uid": uid}, 1.0) # only its uid/card_id are read
	_play_from_hand(stand_in)
	stand_in.free()

func _play_dud(uid: int) -> void:
	_close_concede()
	if g != null and g.can_play(viewer, uid):
		_do(g.play_card(viewer, uid, 0))

## Target spec of a playable hand card that needs a target now ("" if it plays straight away).
func _hand_spec(v: CardView) -> String:
	var cd := CardDB.card(v.card_id)
	var spec := g.card_spec(cd)
	if spec != "" and not g.card_targets(viewer, cd).is_empty():
		return spec
	return ""

## Starts aiming from `src` (global; ZERO = the pointer). If the press is still held, the
## aim is a drag: releasing over a target fires, elsewhere cancels.
func _begin_aim(src: Vector2) -> void:
	aim_src = src if src != Vector2.ZERO else get_global_mouse_position()
	aim_start = get_global_mouse_position()
	aim_drag = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

## On-screen rectangle a card really covers. get_global_rect() ignores rotation, so for a tapped
## (sideways) card it points at the wrong area; this one turns the card's corners with it.
func _visual_rect(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)

## Valid target (unit or leader) under a global point; 0 if none. Tapped cards may overlap their
## neighbours, so when two are under the point the one drawn on top wins.
func _target_at(gp: Vector2) -> int:
	var found_uid := 0
	var found_draw_order := -1
	for k in views:
		if k is int and k != 0 and _is_target(k) and not hand_uids.has(k):
			var c: Control = views[k]
			if is_instance_valid(c) and _visual_rect(c).has_point(gp) and c.get_index() > found_draw_order:
				found_uid = k
				found_draw_order = c.get_index()
	return found_uid

func _update_aim() -> void:
	# an attacker picked during an animation: the arrow already follows the pointer from it (it never locks
	# on, since what it can hit is only known once the animation ends)
	var waiting_attacker_view = views.get(_queued_attacker_uid) if _queued_attacker_uid != 0 else null
	if g != null and targeting.is_empty() and is_instance_valid(waiting_attacker_view):
		if not is_instance_valid(aim_arrow):
			aim_arrow = AimArrow.new()
			fx.add_child(aim_arrow)
		aim_arrow.visible = true
		aim_arrow.move_to_front()
		var waiting_rect := _visual_rect(waiting_attacker_view)
		var arrow_space := fx.get_global_transform().affine_inverse()
		aim_arrow.from = arrow_space * Vector2(waiting_rect.get_center().x, waiting_rect.position.y + waiting_rect.size.y * 0.3)
		aim_arrow.to = arrow_space * get_global_mouse_position()
		aim_arrow.locked = false
		return
	var on: bool = g != null and not targeting.is_empty() and targeting.get("spec") != "enemy_stack" 		and _my_input() and g.phase in ["main", "combat", "enter_target"]
	if not on:
		if is_instance_valid(aim_arrow):
			aim_arrow.visible = false
		aim_drag = false
		return
	if not is_instance_valid(aim_arrow):
		aim_arrow = AimArrow.new()
		fx.add_child(aim_arrow)
	aim_arrow.visible = true
	aim_arrow.move_to_front()
	var src := aim_src
	if targeting["kind"] in ["hand", "enter", "attack"] and views.has(targeting["uid"]) and is_instance_valid(views[targeting["uid"]]):
		var r: Rect2 = _visual_rect(views[targeting["uid"]] as Control)
		src = Vector2(r.get_center().x, r.position.y + r.size.y * 0.3)
	var inv := fx.get_global_transform().affine_inverse()
	var gp := get_global_mouse_position()
	aim_arrow.from = inv * src
	aim_arrow.to = inv * gp
	aim_arrow.locked = _target_at(gp) != 0

func _toggle_pick(uid: int, cap: int) -> void:
	if picked.has(uid):
		picked.erase(uid)
	elif picked.size() < cap:
		picked.append(uid)
	_render()

func _on_legendary(p: int) -> void:
	if p != viewer or not _my_input():
		return
	if _wait_for_table(_on_legendary.bind(p)):
		return
	if not g.can_cast_legendary(p):
		return
	_do(g.cast_legendary(p)) # its Ao Entrar target (if any) is picked once it is on the board

## While our Ao Entrar waits for a target, aim from the unit on the board; the choice is
## optional (the side button skips it), so it cannot be cancelled away.
func _sync_enter_aim() -> void:
	if g.phase != "enter_target" or not _my_input():
		if targeting.get("kind") == "enter":
			targeting = {}
		return
	var uid := int(g.pending_enter["uid"])
	var first_pick := int(g.pending_enter.get("first", 0)) # set once the first of two picks is made
	if targeting.get("kind") != "enter" or targeting["uid"] != uid or int(targeting.get("first", 0)) != first_pick:
		var asked_spec: String = g.pending_enter["spec2"] if first_pick != 0 else g.pending_enter["spec"]
		targeting = {"kind": "enter", "uid": uid, "spec": asked_spec, "card_id": g.pending_enter["card_id"]}
		if first_pick != 0:
			targeting["first"] = first_pick
		aim_drag = false
		aim_start = Vector2.INF
	if views.has(uid) and is_instance_valid(views[uid]):
		(views[uid] as CardView).highlight = SEL

func _on_ability(p: int) -> void:
	if not _my_input():
		return
	if _wait_for_table(_on_ability.bind(p)):
		return
	if not g.can_use_ability(p):
		return
	var spec := g.target_spec(CardDB.leader(g.players[p]["leader_id"])["ability"]["effects"])
	if spec != "":
		targeting = {"kind": "ability", "uid": 0, "spec": spec}
		var lv: Control = views.get(GameState.LEADER_UID[p])
		_begin_aim(lv.get_global_transform() * LeaderView.AC if is_instance_valid(lv) else Vector2.ZERO)
		_render()
	else:
		_do(g.use_ability(p, 0))

func _on_search_choice(card_uid: int) -> void:
	if not _my_input() or _wait_for_table(_on_search_choice.bind(card_uid)):
		return
	if g.phase != "search":
		return
	_do(g.choose_search(viewer, card_uid))

func _is_target(uid: int) -> bool:
	if targeting.is_empty():
		return false
	if targeting["spec"] == "enemy_stack":
		for hand_card: Card in g.players[viewer]["hand"]:
			if hand_card.uid == targeting["uid"]:
				return g.card_targets(viewer, CardDB.card(hand_card.card_id)).has(uid)
		return false
	if targeting["kind"] == "attack":
		var attacker := g.find_unit(targeting["uid"])
		return attacker != null and g.attack_targets(attacker).has(uid)
	if targeting.has("first") and uid == targeting["first"] and not CardDB.card(targeting["card_id"]).get("same_target_ok", false):
		return false # the sacrificed unit is already gone
	return g.valid_targets(viewer, targeting["spec"], targeting.get("uid", 0)).has(uid)

## True when a multi-target effect has already committed this uid as its first pick.
## It stays separate from `_is_target`: Relâmpagos Gêmeos may legally pick it again,
## but it must remain visibly distinct from the still-available second targets.
func _is_first_target(uid: int) -> bool:
	return not targeting.is_empty() and targeting.has("first") and int(targeting["first"]) == uid

func _fire_target(uid: int) -> void:
	match targeting["kind"]:
		"hand":
			var spec2 := g.second_spec(CardDB.card(targeting["card_id"]))
			if spec2 != "" and not targeting.has("first"):
				# second step: pick the damage target after the sacrifice
				targeting = {"kind": "hand", "uid": targeting["uid"], "card_id": targeting["card_id"], "spec": spec2, "first": uid, "picks": [uid]}
				_render()
			elif targeting.has("first"):
				_do(g.play_card(viewer, targeting["uid"], targeting["first"], uid))
			else:
				_do(g.play_card(viewer, targeting["uid"], uid, 0, targeting.get("slot", -1)))
		"legendary":
			_do(g.cast_legendary(viewer, uid))
		"ability":
			_do(g.use_ability(viewer, uid))
		"unit_ability":
			_do(g.activate(viewer, targeting["uid"], uid))
		"enter":
			_do(g.choose_enter_target(viewer, uid))
		"attack":
			_do(g.attack_unit(viewer, targeting["uid"], uid))

func _on_leader_click(p: int) -> void:
	if _my_input() and _input_must_wait() and _aiming_or_waiting():
		_queue_card_click(GameState.LEADER_UID[p])
		return
	if _my_input() and _is_target(GameState.LEADER_UID[p]):
		_fire_target(GameState.LEADER_UID[p])

## A click on a unit on the field does its job (fire a target, pick an attacker/blocker...);
## when it has nothing to do there it opens the card overlay instead, like a click in the hand.
## During an animation the click waits and runs when it ends (see _queued_inputs).
func _on_unit_click(v: CardView) -> void:
	if _input_must_wait() and _click_should_wait(v.uid):
		_queue_card_click(v.uid)
		return
	if not _unit_click_acted(v):
		_show_overlay(v)

## Touch: a finger pressed on one of our units and moved past the drag threshold. That is the same
## as picking it as an attacker, except the finger is still down: the arrow follows it and lifting
## it over a target fires the attack (see _aim_release).
func _unit_drag_start(v: CardView) -> void:
	if _input_must_wait() and _click_should_wait(v.uid):
		_queue_card_click(v.uid) # picked during an animation: the release is handled by _input
		return
	if not _my_input() or not targeting.is_empty():
		return
	if _unit_click_acted(v):
		aim_drag = true # the press is still held, so the release decides

## True while an aim is open or clicks are already waiting: the next click on a card is a target pick.
func _aiming_or_waiting() -> bool:
	return not targeting.is_empty() or _queued_attacker_uid != 0 or not _queued_inputs.is_empty()

## Should a click on this unit, given during an animation, wait for it to end? Yes when it is meant to
## act (pick a target, pick one of our attackers); a plain look at a card opens its overlay right away.
func _click_should_wait(uid: int) -> bool:
	if not _my_input():
		return false
	if _aiming_or_waiting():
		return true
	if not g.combat_system().in_attacks_window(viewer):
		return false
	var unit := g.find_unit(uid)
	return unit == null or unit.owner == viewer

## Stores a click on a card (unit or Leader) to run when the table settles. A click on one of our
## units during our attacks also shows the aiming arrow from it at once, so the pick visibly counted.
func _queue_card_click(uid: int) -> void:
	var picks_an_attacker: bool = targeting.is_empty() and _queued_attacker_uid == 0 and uid > 0 \
		and g.combat_system().in_attacks_window(viewer)
	if picks_an_attacker:
		var unit := g.find_unit(uid)
		picks_an_attacker = unit != null and unit.owner == viewer
	if picks_an_attacker:
		_queued_attacker_uid = uid
		_queued_attacker_dragging = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	else:
		_queued_attacker_uid = 0 # this click is the waiting attacker's target
		_queued_attacker_dragging = false
	_queued_inputs.append(_click_card_when_settled.bind(uid))

## The press that picked a waiting attacker was released: over another card, that card is its target.
## A plain click (released on the attacker itself or on nothing) keeps the arrow following the pointer.
func _release_queued_attacker_drag() -> void:
	_queued_attacker_dragging = false
	var card_uid := _card_uid_at(get_global_mouse_position())
	if card_uid != 0 and card_uid != _queued_attacker_uid:
		_queue_card_click(card_uid)

## Runs a click stored during an animation, now that the screen shows the real table. The card may be
## gone or no longer a legal target (a Provocação that died in the fight that was playing): then the
## aim is dropped and the attacker stays ready, instead of acting on something the player never saw.
func _click_card_when_settled(uid: int) -> void:
	if not _my_input():
		return
	var acted := false
	if uid < 0:
		if _is_target(uid):
			_fire_target(uid)
			acted = true
	else:
		var view = views.get(uid)
		if is_instance_valid(view) and view is CardView:
			acted = _unit_click_acted(view)
	if not acted and not targeting.is_empty() and targeting["kind"] != "enter":
		_toast("Esse alvo não está mais disponível.")
		_cancel_targeting()

## uid of the unit or Leader drawn under a global point, legal target or not (0 if none).
func _card_uid_at(gp: Vector2) -> int:
	var found_uid := 0
	var found_draw_order := -1
	for k in views:
		if k is int and k != 0 and not hand_uids.has(k):
			var c: Control = views[k]
			if is_instance_valid(c) and _visual_rect(c).has_point(gp) and c.get_index() > found_draw_order:
				found_uid = k
				found_draw_order = c.get_index()
	return found_uid

## Runs the click's action and returns true, or returns false when the click had no action.
func _unit_click_acted(v: CardView) -> bool:
	if not _my_input():
		return false
	var unit := g.find_unit(v.uid)
	if unit == null:
		return true
	if not targeting.is_empty():
		if _is_target(v.uid):
			_fire_target(v.uid)
			return true
		return false
	# our attacks: pick an attacker, then an arrow follows the finger to its target
	if g.combat_system().in_attacks_window(viewer) and unit.owner == viewer:
		if g.attack_targets(unit).is_empty():
			_toast("Essa unidade não pode atacar agora.")
			return true
		targeting = {"kind": "attack", "uid": unit.uid, "spec": "attack"}
		_begin_aim(_visual_rect(v).get_center())
		_render()
		return true
	return false

## card_id of the Provocação waiting for the "enter exhausted?" choice ("" if none).
func _pending_tap_card_id() -> String:
	if g.pending_tap.is_empty():
		return ""
	var unit := g.find_unit(int(g.pending_tap[0]))
	return unit.card_id if unit != null else ""

# ---------------------------------------------------------------- overlay

## " (agora: N)" for cards whose text counts something (Jeff: unit cards in the own graveyard), so the
## player can add it to the base stats. Empty for the rest.
func _scale_suffix(p: int, cd: Dictionary) -> String:
	var n := g.scale_count(p, cd)
	return " (agora: %d)" % n if n >= 0 else ""

func _show_overlay(v: CardView) -> void:
	if v.face_down:
		return
	_close_overlay()
	var cd := CardDB.card_for(v.card_id, v.inst)
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_overlay())
	add_child(overlay)
	# the big card and the full text are built by CardOverlay (tools/view_card.gd shows the same thing)
	var rt_x := CardOverlay.build(overlay, stage_w, v.card_id, v.inst, v.cost_override, v.text_suffix, v.snowball_level)
	if cd.has("activated") and g != null and _my_input() and g.can_activate(viewer, v.uid):
		var ab: Dictionary = cd["activated"]
		var ab_uid := v.uid
		var ab_btn := _button("Ativar (%d)" % int(ab["cost"]), func():
			_close_overlay()
			# during an animation the activation waits for it to end (and checks again that it is still allowed)
			_run_or_queue_input(func():
				if not _my_input() or not g.can_activate(viewer, ab_uid):
					return
				var spec := g.target_spec(ab["effects"])
				if spec == "":
					_do(g.activate(viewer, ab_uid, 0))
				else:
					targeting = {"kind": "unit_ability", "uid": ab_uid, "spec": spec}
					if views.has(ab_uid) and is_instance_valid(views[ab_uid]):
						_begin_aim(_visual_rect(views[ab_uid] as Control).get_center())
					_render()), true)
		ab_btn.position = Vector2(rt_x, 820.0 + BOT)
		ab_btn.custom_minimum_size = Vector2(520, 96)
		overlay.add_child(ab_btn)
	if g != null and _my_input() and _requiem_uids(viewer).has(v.uid):
		# a Réquiem spell opened from the graveyard viewer: cast it from here (it is banished afterwards)
		var requiem_uid := v.uid
		var requiem_card_id := v.card_id
		var requiem_btn := _button("Lançar Réquiem (%d)" % v.cost_override, func():
			_close_overlay()
			_close_graveyard()
			_cast_requiem(requiem_uid, requiem_card_id), true)
		requiem_btn.position = Vector2(rt_x, 820.0 + BOT)
		requiem_btn.custom_minimum_size = Vector2(520, 96)
		overlay.add_child(requiem_btn)
	if cd.has("transform") and g != null and _my_input() and g.can_transform(viewer, v.uid):
		var tb := _button("Transformar (%d)" % int(cd["transform"]["cost"]), func():
			_close_overlay()
			_do(g.transform(viewer, v.uid)), true)
		tb.position = Vector2(rt_x, 820.0 + BOT)
		tb.custom_minimum_size = Vector2(520, 96)
		overlay.add_child(tb)

func _close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null

# ---------------------------------------------------------------- concede

## Confirmation before giving up; a persistent child of Main so re-renders (AI/opponent moves) don't dismiss it.
func _ask_concede() -> void:
	_ask_confirm("CONCEDER A PARTIDA?", "O oponente vence na hora.", "CONCEDER", "CONTINUAR JOGANDO", _confirm_concede)

## Generic yes/no dialog (same persistent slot as the concede one).
func _ask_confirm(title: String, text: String, yes_label: String, no_label: String, on_yes: Callable) -> void:
	if g == null or g.phase == "over" or concede_view:
		return
	concede_view = Control.new()
	concede_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	concede_view.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	concede_view.add_child(dim)
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
	box.add_child(_label(title, 34, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6))
	box.add_child(_label(text, 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var yes := _button(yes_label, on_yes, true)
	yes.custom_minimum_size = Vector2(460, 54)
	box.add_child(yes)
	var no := _button(no_label, _close_concede)
	no.custom_minimum_size = Vector2(460, 48)
	box.add_child(no)
	concede_view.add_child(pc)
	add_child(concede_view)
	pc.reset_size()
	pc.position = (Vector2(stage_w, STAGE_H) - pc.size) / 2.0
	_center.call_deferred(pc)

func _close_concede() -> void:
	if concede_view:
		concede_view.queue_free()
		concede_view = null

func _confirm_concede() -> void:
	_close_concede()
	if g == null or g.phase == "over":
		return
	_do(g.concede(viewer))

# ---------------------------------------------------------------- graveyard viewer

const GRAVE_FILTERS := [["all", "TODAS"], ["unit", "UNIDADES"], ["spell", "FEITIÇOS"], ["artifact", "ARTEFATOS"]]

## Persistent viewer (survives re-renders) for either player's graveyard, newest card first.
func _show_graveyard(p: int) -> void:
	if grave_view and grave_owner == p:
		_close_graveyard()
		return
	_close_graveyard()
	grave_owner = p
	grave_filter = "requiem" if _requiem_uids(p).size() > 0 else "all" # the glow on the icon promised a castable card in here
	grave_view = Control.new()
	grave_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	grave_view.mouse_filter = Control.MOUSE_FILTER_STOP
	grave_view.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_graveyard())
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grave_view.add_child(dim)
	var pc := PanelContainer.new()
	var sb := UITheme.panel(14)
	sb.set_content_margin_all(28)
	sb.set_border_width_all(2)
	sb.border_color = Color(UITheme.GOLD, 0.6)
	sb.shadow_size = 40
	sb.bg_color = Color("#0e0c14", 0.97)
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.custom_minimum_size = Vector2(minf(stage_w - 80.0, 1180.0), 800)
	pc.size = pc.custom_minimum_size
	pc.position = (Vector2(stage_w, STAGE_H) - pc.size) / 2.0
	grave_view.add_child(pc)
	grave_panel = pc
	add_child(grave_view)
	_refresh_graveyard()

func _close_graveyard() -> void:
	if grave_view:
		grave_view.queue_free()
		grave_view = null
		grave_scroll = null
		grave_panel = null

## Uids of the Réquiem spells the viewer can cast from the own graveyard right now (empty for the opponent's).
func _requiem_uids(p: int) -> Array:
	var uids: Array = []
	if p != viewer or _is_ai(p) or g.phase not in ["main", "combat"]:
		return uids
	for requiem_card: Card in g.requiem_cards(p):
		uids.append(requiem_card.uid)
	return uids

## Rebuilds the panel contents (on open, filter change and after every _render).
func _refresh_graveyard() -> void:
	if not grave_view or not is_instance_valid(grave_view):
		return
	var keep := grave_scroll.scroll_vertical if grave_scroll and is_instance_valid(grave_scroll) else 0
	for c in grave_panel.get_children():
		grave_panel.remove_child(c)
		c.queue_free()
	var entries: Array = g.players[grave_owner]["graveyard"].duplicate()
	entries.reverse() # newest first
	var castable_uids := _requiem_uids(grave_owner)
	var counts := {"all": entries.size(), "unit": 0, "spell": 0, "artifact": 0, "requiem": castable_uids.size()}
	for grave_card: Card in entries:
		counts[CardDB.card(grave_card.card_id)["type"]] += 1
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
	titles.add_child(_label("CEMITÉRIO", 34, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "title_bold", 6))
	var whose := "Seu cemitério" if grave_owner == viewer and not _is_ai(grave_owner) else "Cemitério de %s" % _pname(grave_owner)
	var n := entries.size()
	titles.add_child(_label("%s · %s · %d %s" % [whose, CardDB.leader(g.players[grave_owner]["leader_id"])["name"], n, "carta" if n == 1 else "cartas"], 17, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, "body"))
	var close := _button("✕", _close_graveyard)
	close.custom_minimum_size = Vector2(52, 48)
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
		var b := _button("%s  %d" % [f[1], counts[fid]], func():
			grave_filter = fid
			_refresh_graveyard(), grave_filter == fid)
		b.custom_minimum_size = Vector2(0, 44)
		b.disabled = counts[fid] == 0 and fid != "all"
		tabs.add_child(b)

	# card grid
	var shown: Array = entries
	if grave_filter == "requiem":
		shown = entries.filter(func(grave_card: Card): return castable_uids.has(grave_card.uid))
	elif grave_filter != "all":
		shown = entries.filter(func(grave_card: Card): return CardDB.card(grave_card.card_id)["type"] == grave_filter)
	if shown.is_empty():
		var empty := VBoxContainer.new()
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.add_theme_constant_override("separation", 8)
		empty.add_child(_label("☠", 72, Color(UITheme.TEXT, 0.25), HORIZONTAL_ALIGNMENT_CENTER))
		empty.add_child(_label("Nenhuma carta aqui." if entries.is_empty() else "Nenhuma carta deste tipo.", 24, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "title"))
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
			var cv := CardView.new().setup(grave_card.card_id, {"uid": grave_card.uid}, 1.1)
			if grave_owner == viewer and g.is_requiem(grave_card):
				# Réquiem shows what it costs from here (base + 2) and glows when it can be cast now
				cv.cost_override = g.cost_of(viewer, CardDB.card(grave_card.card_id), grave_card)
				if castable_uids.has(grave_card.uid):
					cv.highlight = OK
			cv.left_clicked.connect(_grave_card_click)
			cv.right_clicked.connect(_grave_card_click)
			grid.add_child(cv)
		grave_scroll = sc
		_restore_scroll.call_deferred(sc, keep)
	grave_view.move_to_front()
	if overlay:
		overlay.move_to_front()

func _grave_card_click(v: CardView) -> void:
	if Time.get_ticks_msec() - grave_drag_ms > 250:
		_show_overlay(v)

func _restore_scroll(sc: ScrollContainer, v: int) -> void:
	if is_instance_valid(sc):
		sc.scroll_vertical = v

## Wheel and finger-drag scrolling: the cards swallow those events before the ScrollContainer sees them.
func _grave_scroll_input(e: InputEvent) -> bool:
	if not grave_scroll or not is_instance_valid(grave_scroll) or overlay:
		return false
	var xf := grave_scroll.get_global_transform_with_canvas()
	var local: Vector2 = xf.affine_inverse() * e.position if "position" in e else Vector2(-1, -1)
	if not Rect2(Vector2.ZERO, grave_scroll.size).has_point(local):
		return false
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		grave_scroll.scroll_vertical += (-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1) * 120
		return true
	if e is InputEventScreenDrag:
		grave_scroll.scroll_vertical -= int(e.relative.y / xf.get_scale().y)
		grave_drag_ms = Time.get_ticks_msec()
		return true
	return false

func _render_search_reveal() -> void:
	if g.pending_search.is_empty():
		return
	var owner: int = g.decider()
	search_overlay = _veil(0.84)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1120, 0)
	box.add_theme_constant_override("separation", 12)
	search_overlay.add_child(box)
	var look: bool = g.pending_search.get("look", false)
	# a private look is face up only for its owner (online, the server already masks the cards)
	var discard_hand: bool = g.pending_search.get("discard_hand", false)
	var hand_summon: bool = g.pending_search.get("hand_summon", false)
	var hidden := (look or discard_hand or hand_summon) and not _my_input()
	# the options of a deck search are shown only to the searcher; the opponent just sees that a search is happening
	var deck_search: bool = g.pending_search.get("deck_search", false)
	var secret_search := deck_search and not _my_input()
	box.add_child(_label("CAMPEÃO DA MÃO" if hand_summon else "DESCARTAR DA MÃO" if discard_hand else "CEMITÉRIO" if g.pending_search.get("grave", false) else ("TOPO DO DECK" if look else "BUSCA NO DECK"), 30, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6))
	var grave: bool = g.pending_search.get("grave", false)
	var sub := "%s está procurando uma carta no deck" % _pname(owner)
	if deck_search and _my_input():
		sub = "Você procurou no deck e encontrou estas cartas"
		if g.pending_search.has("to_bottom"):
			sub = "Você olhou as %d cartas do topo do deck; as que brilham podem ser escolhidas" % int(g.pending_search["looked"])
	if secret_search and g.pending_search.has("to_bottom"):
		sub = "%s está olhando as %d cartas do topo do deck" % [_pname(owner), int(g.pending_search["looked"])]
	if hand_summon:
		sub = "%s escolhe um campeão da mão para entrar em campo (será banido no fim do turno)" % _pname(owner)
	elif discard_hand:
		sub = "%s escolhe uma carta da mão para descartar" % _pname(owner)
	elif look:
		sub = "%s está olhando as %d cartas do topo do deck" % [_pname(owner), g.pending_search["cards"].size()]
	box.add_child(_label(sub, 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var grid := GridContainer.new()
	var shown_options: Array = [] if secret_search else g.pending_search["cards"]
	# a top-N look shows every card looked at: the eligible ones glow and can be picked, the others are dimmed
	var looked_cards: Array = g.pending_search.get("looked_cards", [])
	var eligible_uids: Dictionary = {}
	for option in shown_options:
		eligible_uids[int(option["uid"])] = true
	if not secret_search and not looked_cards.is_empty():
		shown_options = looked_cards
	grid.columns = maxi(1, mini(7, shown_options.size()))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for option in shown_options:
		var card_uid: int = option["uid"]
		var eligible: bool = eligible_uids.has(card_uid)
		var cv := CardView.new().setup(option["card_id"], {"uid": card_uid}, 1.05)
		cv.face_down = hidden or String(option["card_id"]) == ""
		if not cv.face_down:
			cv.text_suffix = _scale_suffix(owner, CardDB.card(option["card_id"]))
			cv.snowball_level = int(g.players[owner]["snowball"])
		if eligible and not looked_cards.is_empty():
			cv.highlight = OK
		elif not eligible:
			cv.modulate = Color(1, 1, 1, 0.4)
		var can_pick: bool = eligible and _my_input()
		cv.mouse_filter = Control.MOUSE_FILTER_STOP if can_pick else Control.MOUSE_FILTER_IGNORE
		if can_pick:
			cv.left_clicked.connect(func(_v): _on_search_choice(card_uid))
		grid.add_child(cv)
	var hint := "Clique em um campeão para colocá-lo em campo sem pagar o custo." if hand_summon else "Clique em uma carta para descartá-la (ela vai para o cemitério)." if discard_hand else "Clique em uma carta para adicioná-la à sua mão; as outras ficam no cemitério." if grave else "Escolha 1 para a mão; as outras vão para o fundo do deck." if look else "Clique em uma carta que brilha para adicioná-la à sua mão; as outras cartas olhadas vão para o fundo do deck." if g.pending_search.has("to_bottom") else "Clique em uma carta para adicioná-la à sua mão e embaralhar o deck."
	var footer := _label(hint if _my_input() else "A escolha pertence ao oponente.", 16, SEL if _my_input() else UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body")
	box.add_child(footer)
	_center.call_deferred(search_overlay)


# ---------------------------------------------------------------- feedback

## Pose of a Control as its visual center, rotation and on-screen width.
func _pose(v: Control) -> Dictionary:
	var zoom: float = v.zoom if v is CardView else 1.0 # a zoomed card is bigger without a node scale
	var s: float = v.scale.x * zoom
	return {"c": v.position + v.pivot_offset + (v.size / 2.0 - v.pivot_offset).rotated(v.rotation) * s,
		"rot": v.rotation, "w": v.size.x * s}

func _apply_pose(v: Control, p: Dictionary) -> void:
	var s: float = p["w"] / v.size.x
	v.rotation = p["rot"]
	v.scale = Vector2.ONE * s
	v.position = p["c"] - v.pivot_offset - (v.size / 2.0 - v.pivot_offset).rotated(p["rot"]) * s

## Where every card is right now, taken before a re-render replaces it.
func _snapshot() -> Dictionary:
	var out := {}
	for k in views:
		var v = views[k]
		if v is CardView and is_instance_valid(v) and not v.is_queued_for_deletion():
			out[k] = {"pose": _pose(v), "card_id": v.card_id, "inst": v.inst.duplicate(true), "hand": hand_uids.has(k)}
	return out

func _center_of(c: Control) -> Vector2:
	if c is LeaderView:
		return c.position + LeaderView.PC
	return _pose(c)["c"]

func _fly(v: Control, from: Dictionary, to: Dictionary, t0: float, dur: float, arc := 0.0, hide := false) -> Tween:
	_apply_pose(v, from)
	var tw := v.create_tween()
	if hide:
		v.visible = false
	if t0 > 0.0:
		tw.tween_interval(t0)
	if hide:
		tw.tween_callback(func(): v.visible = true)
	tw.tween_method(func(t: float):
		var c: Vector2 = from["c"].lerp(to["c"], t)
		c.y -= arc * 4.0 * t * (1.0 - t)
		_apply_pose(v, {"c": c, "rot": lerp_angle(from["rot"], to["rot"], t), "w": lerpf(from["w"], to["w"], t)}),
		0.0, 1.0, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return tw

## A drawn card leaves the top of the viewer's deck pile face down, flips
## face up halfway through the flight and lands in its hand slot.
func _draw_from_deck(v: CardView, to: Dictionary, t0: float) -> void:
	const FLIGHT_TIME := 0.5
	var leader_view = views.get(GameState.LEADER_UID[viewer])
	var deck_pose := {"c": Vector2(lane_cx, LEADER_Y_ME), "rot": 0.0, "w": LeaderView.deck_card_width()}
	if leader_view is LeaderView:
		deck_pose["c"] = leader_view.position + LeaderView.deck_top_center(leader_view.deck)
	_fly(v, deck_pose, to, t0, FLIGHT_TIME, 60.0, true)
	v.face_down = true
	var flip := v.create_tween()
	flip.tween_interval(t0 + FLIGHT_TIME * 0.45)
	flip.tween_callback(func():
		v.face_down = false
		v.queue_redraw())

## Timing of a milled card: it pops out of the deck face up, stays readable for a blink, then drops
## into the graveyard icon. Short on purpose: both graveyards can be opened at any time.
const MILL_RISE_TIME := 0.2
const MILL_HOLD_TIME := 0.2
const MILL_DROP_TIME := 0.24
const MILL_CARD_W := 140.0 ## on-screen width while the card is shown
const MILL_STAGGER := 0.1 ## delay between one milled card and the next (shrinks when many are milled)
const MILL_MAX_STAGGER_TOTAL := 0.4 ## the whole row of starts never takes longer than this

## The cards `card_ids` leave the top of `deck_owner`'s deck one after another and land in their
## graveyard. Starts at moment t; returns how long the animation queue should wait (the cards keep
## flying on their own after that, they overlap with whatever plays next).
func _mill_fx(deck_owner: int, card_ids: Array, t: float) -> float:
	var leader_view = views.get(GameState.LEADER_UID[deck_owner])
	if not (leader_view is LeaderView) or card_ids.is_empty():
		return 0.0
	var deck_pose := {"c": leader_view.position + LeaderView.deck_top_center(leader_view.deck), "rot": 0.0, "w": LeaderView.deck_card_width()}
	var grave_pose := {"c": leader_view.position + LeaderView.GRAVE_CENTER, "rot": 0.0, "w": LeaderView.deck_card_width() * 0.6}
	# the card is shown a bit toward the middle of the table, so the Leader's own frame doesn't hide it
	var middle_y := (_screen_top() + _screen_bottom()) / 2.0
	var shown_pose := {"c": deck_pose["c"] + Vector2(0, 170.0 * signf(middle_y - deck_pose["c"].y)), "rot": 0.0, "w": MILL_CARD_W}
	var stagger := minf(MILL_STAGGER, MILL_MAX_STAGGER_TOTAL / card_ids.size())
	var total_time := MILL_RISE_TIME + MILL_HOLD_TIME + MILL_DROP_TIME
	for i in card_ids.size():
		var ghost := _ghost(card_ids[i], {}, deck_pose, MILL_CARD_W / CardView.BASE.x) # built at its biggest size: only shrinks, never blurs
		ghost.z_index = 30
		ghost.visible = false
		var flight := ghost.create_tween()
		flight.tween_interval(t + i * stagger)
		flight.tween_callback(func(): ghost.visible = true)
		flight.tween_method(func(seconds: float):
			var pose: Dictionary
			if seconds < MILL_RISE_TIME:
				pose = _blend_pose(deck_pose, shown_pose, seconds / MILL_RISE_TIME)
			elif seconds < MILL_RISE_TIME + MILL_HOLD_TIME:
				pose = shown_pose
			else:
				var drop_progress := (seconds - MILL_RISE_TIME - MILL_HOLD_TIME) / MILL_DROP_TIME
				pose = _blend_pose(shown_pose, grave_pose, drop_progress)
				ghost.modulate.a = 1.0 - drop_progress * drop_progress
			_apply_pose(ghost, pose),
			0.0, total_time, total_time)
		flight.tween_callback(ghost.queue_free)
	return (card_ids.size() - 1) * stagger + 0.1

## A pose between two poses, eased (0 = `from`, 1 = `to`).
func _blend_pose(from: Dictionary, to: Dictionary, progress: float) -> Dictionary:
	var eased := ease(clampf(progress, 0.0, 1.0), -2.0) if progress < 1.0 else 1.0
	return {"c": from["c"].lerp(to["c"], eased), "rot": lerp_angle(from["rot"], to["rot"], eased), "w": lerpf(from["w"], to["w"], eased)}

func _ghost(card_id: String, inst: Dictionary, pose: Dictionary, size_scale := 1.15) -> CardView:
	var v := CardView.new().setup(card_id, inst, size_scale)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.pivot_offset = v.size / 2.0
	fx.add_child(v)
	_apply_pose(v, pose)
	return v

## Timing of an attack lunge: pull back, rush in, stay on the target a moment, walk back.
const LUNGE_WINDUP_TIME := 0.16
const LUNGE_STRIKE_TIME := 0.2
const LUNGE_HOLD_TIME := 0.08
const LUNGE_RETURN_TIME := 0.34
## When the attacker touches its target (where the hit lands), counted from the lunge start.
const LUNGE_IMPACT_TIME := LUNGE_WINDUP_TIME + LUNGE_STRIKE_TIME
const LUNGE_TOTAL_TIME := LUNGE_IMPACT_TIME + LUNGE_HOLD_TIME + LUNGE_RETURN_TIME
## A unit lying down (tap) or standing up (untap): a short pause after the action, then a slow turn.
const TAP_DELAY := 0.12
const TAP_TIME := 0.45

func _lunge(a: CardView, target: Control, t: float) -> void:
	var tw := a.create_tween()
	tw.tween_interval(t)
	# The direction is measured when the lunge starts, not now: the table was already redrawn in its
	# final state (the attacker lying tapped), but on screen the card still stands where it was until
	# the tap animation plays after the hit. "lunge" is drawn in the card's own space, so the offset
	# is turned back by the card's rotation and divided by its scale.
	tw.tween_callback(func():
		a.z_index = 20
		var offset_to_target: Vector2 = ((_center_of(target) - _center_of(a)) * 0.72 / a.scale.x).rotated(-a.rotation)
		var strike := a.create_tween()
		strike.tween_property(a, "lunge", -offset_to_target * 0.12, LUNGE_WINDUP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		strike.tween_property(a, "lunge", offset_to_target, LUNGE_STRIKE_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		strike.tween_interval(LUNGE_HOLD_TIME)
		strike.tween_property(a, "lunge", Vector2.ZERO, LUNGE_RETURN_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		strike.tween_callback(func(): a.z_index = 0))

## How long a transformation holds the animation queue.
const TRANSFORM_TIME := 0.75

## A card becomes another one (a unit with Transformar, a Bola de Neve in hand becoming Grande...).
## _render already drew the new card, so a ghost of the old one is laid over it and, at moment t,
## burns away in the new card's color: it reveals the new card beneath, which pops with a flash and a
## ring of light. The ghost is created now, so the old card stays on screen until the moment arrives.
func _transform_fx(uid: int, from_id: String, into_id: String, actors: Dictionary, old: Dictionary, t: float) -> void:
	var new_view: CardView = actors[uid]
	var old_instance: Dictionary = old[uid]["inst"] if old.has(uid) else {}
	var old_pose: Dictionary = old[uid]["pose"] if old.has(uid) else _pose(new_view)
	var old_card := _ghost(from_id, old_instance, old_pose)
	old_card.z_index = 20
	var color := _elem_color(into_id).lightened(0.35)
	old_card.dissolve(t, color, 0.45)
	var pop := new_view.create_tween()
	pop.tween_interval(t + 0.1)
	pop.tween_callback(func(): new_view.flash = 0.8)
	pop.tween_property(new_view, "proc", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(new_view, "proc", 0.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pop.parallel().tween_property(new_view, "flash", 0.0, 0.5)
	var ring := new_view.create_tween()
	ring.tween_interval(t + 0.14)
	ring.tween_property(new_view, "proc_wave", 1.0, 0.55).from(0.001)
	ring.tween_callback(func(): new_view.proc_wave = 0.0)
	_embers(_center_of(new_view), t + 0.1, color, 24)
	_impact(new_view, "Transformou!", color, t + 0.15, false)

## Câmara de Êxtase cancelling a killing blow: at the moment of impact the Chamber pulses and sends a
## ring of light to the Leader, "Anulado!" floats over the Leader (like a Spell Shield), the Leader
## takes no damage and does not flinch, then the spent Chamber holds a beat and dissolves slowly.
## `ward` is a ghost of the Chamber (it is already off the table), `leader` the Leader's view.
const WARD_FADE_DELAY := 0.55
const WARD_FADE_TIME := 1.1

func _ward_fx(leader: Control, ward: CardView, t: float, col: Color) -> void:
	if leader != null:
		_impact(leader, "Anulado!", col, t, false)
		_embers(_center_of(leader), t, col, 18)
		var ring := Line2D.new()
		var points := PackedVector2Array()
		for i in 33:
			points.append(Vector2.from_angle(TAU * i / 32.0) * 60.0)
		ring.points = points
		ring.width = 5.0
		ring.default_color = Color(col, 0.85)
		ring.position = _center_of(leader)
		ring.z_index = 58
		ring.scale = Vector2(0.3, 0.3)
		ring.modulate.a = 0.0
		fx.add_child(ring)
		var ring_tween := ring.create_tween()
		ring_tween.tween_interval(t)
		ring_tween.tween_property(ring, "modulate:a", 1.0, 0.05)
		ring_tween.tween_property(ring, "scale", Vector2.ONE * 2.2, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.5)
		ring_tween.tween_callback(ring.queue_free)
	if ward == null:
		return
	if leader != null:
		# a thread of light from the Chamber to the Leader just before the impact
		_streak(ward, leader, maxf(0.0, t - STREAK_T), col)
	var pulse := ward.create_tween()
	pulse.tween_interval(t)
	pulse.tween_callback(func(): ward.flash = 0.9)
	pulse.tween_property(ward, "proc", 1.0, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse.tween_property(ward, "proc", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.parallel().tween_property(ward, "flash", 0.0, 0.5)
	var wave := ward.create_tween()
	wave.tween_interval(t + 0.04)
	wave.tween_property(ward, "proc_wave", 1.0, 0.55).from(0.001)
	wave.tween_callback(func(): ward.proc_wave = 0.0)
	_embers(_center_of(ward), t + 0.05, col, 16)
	ward.dissolve(t + WARD_FADE_DELAY, col, WARD_FADE_TIME)

## Combat damage at or above this makes the whole screen react (see _crushing_blow_fx).
const CRUSHING_BLOW_DAMAGE := 7
const CRUSHING_BLOW_SHAKE_TIME := 1.2

## Heavy-hit feedback, kept cheap on purpose (no full-screen overlays, no scaling of the whole
## screen): a decaying trauma shake of the screen (strength = trauma squared, 1.2s) plus one
## shockwave ring and a few sparks at the impact point.
func _crushing_blow_fx(target: Control, amount: int, t: float) -> void:
	var center := _center_of(target)
	var power := clampf(float(amount - CRUSHING_BLOW_DAMAGE) / 8.0, 0.0, 1.0) # 7 dmg = base, 15+ = max
	var strength := 6.0 + 6.0 * power ## peak shake in pixels

	var rest_position := position
	var shake_driver := create_tween()
	shake_driver.tween_interval(t)
	shake_driver.tween_method(_apply_screen_trauma.bind(rest_position, strength), 0.0, 1.0, CRUSHING_BLOW_SHAKE_TIME)
	shake_driver.tween_callback(func(): position = rest_position)

	var ring := Line2D.new()
	var points := PackedVector2Array()
	for i in 33:
		points.append(Vector2.from_angle(TAU * i / 32.0) * 60.0)
	ring.points = points
	ring.width = 6.0
	ring.default_color = Color(1.0, 0.85, 0.6, 0.8)
	ring.position = center
	ring.z_index = 58
	ring.scale = Vector2(0.2, 0.2)
	ring.modulate.a = 0.0
	fx.add_child(ring)
	var ring_tween := ring.create_tween()
	ring_tween.tween_interval(t)
	ring_tween.tween_property(ring, "modulate:a", 1.0, 0.02)
	ring_tween.tween_property(ring, "scale", Vector2.ONE * (3.5 + 1.5 * power), 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	ring_tween.parallel().tween_property(ring, "modulate:a", 0.0, 0.45)
	ring_tween.tween_callback(ring.queue_free)
	_embers(center, t, Color(1.0, 0.6, 0.25), 14)

## One frame of the screen shake: trauma falls from 1 to 0 and the offset scales with trauma squared.
func _apply_screen_trauma(progress: float, rest_position: Vector2, strength: float) -> void:
	var trauma := 1.0 - progress
	var intensity := trauma * trauma * strength
	position = rest_position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * intensity

## Shake + red flash on the target and a floating number over it.
func _impact(target: Control, text: String, col: Color, t: float, hurt: bool) -> void:
	var tw := target.create_tween()
	tw.tween_interval(t)
	if hurt and target is CardView:
		var cv: CardView = target
		tw.tween_callback(func(): cv.flash = 1.0)
		tw.tween_method(func(k: float): cv.shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 7.0 * (1.0 - k), 0.0, 1.0, 0.32)
		tw.parallel().tween_property(cv, "flash", 0.0, 0.4)
		tw.tween_callback(func(): cv.shake = Vector2.ZERO)
	elif hurt and target is LeaderView:
		var base := target.position
		tw.tween_method(func(k: float): target.position = base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 9.0 * (1.0 - k), 0.0, 1.0, 0.32)
		tw.tween_callback(func(): target.position = base)
	var l := _label(text, 46, col, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.size = Vector2(160, 58)
	l.pivot_offset = l.size / 2.0
	l.position = _center_of(target) - l.size / 2.0 + Vector2(0, -16)
	l.scale = Vector2(0.4, 0.4)
	l.modulate.a = 0.0
	fx.add_child(l)
	var lt := l.create_tween()
	lt.tween_interval(t)
	lt.tween_property(l, "modulate:a", 1.0, 0.06)
	lt.parallel().tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lt.parallel().tween_property(l, "position:y", l.position.y - 46, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lt.tween_property(l, "modulate:a", 0.0, 0.25)
	lt.tween_callback(l.queue_free)

## A unit gets frozen. _render already drew it covered in ice, so the ice is wiped off now and, at
## moment t, it slams back on: a white-blue flash with two shockwaves, the ice growing over the card
## from nothing, a shiver and a burst of flying shards.
func _freeze_fx(target: Control, t: float) -> void:
	if not target is CardView:
		return
	var cv: CardView = target
	cv.frost_grow = 0.0
	var spread := cv.create_tween()
	spread.tween_interval(t)
	spread.tween_property(cv, "frost_grow", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var burst := cv.create_tween()
	burst.tween_interval(t)
	burst.tween_property(cv, "frost_burst", 1.0, 0.65).from(0.001)
	burst.tween_callback(func(): cv.frost_burst = 0.0)
	var shiver := cv.create_tween()
	shiver.tween_interval(t)
	shiver.tween_method(func(k: float): cv.shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 4.0 * (1.0 - k), 0.0, 1.0, 0.4)
	shiver.tween_callback(func(): cv.shake = Vector2.ZERO)
	_frost_shards(_center_of(cv), t, 30)

## Ice shards thrown outward from a point at moment t, falling a little as they fade.
func _frost_shards(c: Vector2, t: float, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = maxi(6, int(amount * _fx_scale))
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.position = c
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(45, 65)
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 220)
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 230.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(ICE, 0.0))
	p.color_ramp = ramp
	p.z_index = 30
	fx.add_child(p)
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.emitting = true)
	tw.tween_interval(1.4)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free())

## Condenada / Ceifada: violet wisps of dark smoke rising off a unit at moment t, plus a short shiver.
## `heavy` makes the sentence being carried out bigger and darker than the mark being placed.
func _doom_fx(target: Control, t: float, heavy: bool) -> void:
	if not target is CardView:
		return
	var cv: CardView = target
	var shiver := cv.create_tween()
	shiver.tween_interval(t)
	shiver.tween_method(func(k: float): cv.shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * (6.0 if heavy else 3.0) * (1.0 - k), 0.0, 1.0, 0.45)
	shiver.tween_callback(func(): cv.shake = Vector2.ZERO)
	var wisps := CPUParticles2D.new()
	wisps.emitting = false
	wisps.one_shot = true
	wisps.amount = maxi(8, int((46 if heavy else 24) * _fx_scale))
	wisps.lifetime = 1.1
	wisps.explosiveness = 0.8
	wisps.position = _center_of(cv)
	wisps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	wisps.emission_rect_extents = Vector2(40, 60)
	wisps.direction = Vector2(0, -1)
	wisps.spread = 40.0
	wisps.gravity = Vector2(0, -60)
	wisps.initial_velocity_min = 40.0
	wisps.initial_velocity_max = 150.0
	wisps.scale_amount_min = 5.0
	wisps.scale_amount_max = 11.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(CardView.DOOM_COL, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color("#160726", 0.0))
	wisps.color_ramp = ramp
	wisps.z_index = 30
	fx.add_child(wisps)
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func():
		if is_instance_valid(wisps):
			wisps.emitting = true)
	tw.tween_interval(1.5)
	tw.tween_callback(func():
		if is_instance_valid(wisps):
			wisps.queue_free())

## Effects budget of the current _animate batch: 1.0 for a lone hit, shrinking as more
## triggers/deaths pile up (a Diabrete chain would otherwise spawn dozens of emitters at once).
var _fx_scale := 1.0

## Draws the death shader, a particle burst and a gradient line once, invisibly, so the GPU
## compiles them at startup instead of freezing the first time a unit dies.
func _prewarm_fx() -> void:
	var holder := Control.new()
	holder.modulate.a = 0.01
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(holder)
	var r := ColorRect.new()
	r.size = Vector2(8, 8)
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/ui/shaders/dissolve.gdshader")
	m.set_shader_parameter("size", r.size)
	m.set_shader_parameter("edge_color", Color.ORANGE)
	m.set_shader_parameter("progress", 0.5)
	r.material = m
	holder.add_child(r)
	var r2 := ColorRect.new()
	r2.size = Vector2(8, 8)
	var m2 := ShaderMaterial.new()
	m2.shader = load("res://scripts/ui/shaders/banish.gdshader")
	m2.set_shader_parameter("size", r2.size)
	m2.set_shader_parameter("progress", 0.5)
	r2.material = m2
	holder.add_child(r2)
	var p := CPUParticles2D.new()
	p.amount = 4
	p.one_shot = true
	p.emitting = true
	p.color_ramp = Gradient.new()
	holder.add_child(p)
	var ln := Line2D.new()
	ln.points = PackedVector2Array([Vector2.ZERO, Vector2(8, 8)])
	ln.gradient = Gradient.new()
	holder.add_child(ln)
	# floating numbers / trigger tags: big outlined glyphs are rasterized on first use
	var num := _label("-0123456789+/!", 46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 10)
	num.size = Vector2(400, 58)
	holder.add_child(num)
	var tg := _label("Ao Morrer Aliado Morre Ao Entrar Escudo Maré Congelada", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 4)
	tg.position = Vector2(0, 60)
	holder.add_child(tg)
	get_tree().create_timer(0.5).timeout.connect(holder.queue_free)

func _embers(c: Vector2, t: float, col: Color, amount := 36) -> void:
	amount = maxi(4, int(amount * _fx_scale))
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = 1.0
	p.explosiveness = 0.85
	p.position = c
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(55, 75)
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.gravity = Vector2(0, -90)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.lightened(0.4), 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(col, 0.0))
	p.color_ramp = ramp
	fx.add_child(p)
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.emitting = true)
	tw.tween_interval(1.6)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free())

const BANISH_COL := Color(0.8, 0.7, 1.0)

## Banish flourish at a card's center: a pale ring contracting onto it while motes of light
## are pulled inward (the opposite of the death embers, which rise and scatter).
func _banish_fx(c: Vector2, w: float, t: float) -> void:
	var rad := w * 0.75
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(Vector2.from_angle(TAU * i / 32.0) * rad)
	ring.points = pts
	ring.width = 5.0
	ring.default_color = Color(BANISH_COL.lightened(0.4), 0.9)
	ring.position = c
	ring.z_index = 24
	ring.visible = false
	fx.add_child(ring)
	var rt := ring.create_tween()
	rt.tween_interval(t)
	rt.tween_callback(func(): ring.visible = true)
	rt.tween_property(ring, "scale", Vector2(0.05, 0.05), 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	rt.parallel().tween_property(ring, "modulate:a", 0.0, 0.8).set_delay(0.5)
	rt.tween_callback(ring.queue_free)
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = maxi(6, int(28 * _fx_scale))
	p.lifetime = 0.7
	p.explosiveness = 0.7
	p.position = c
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
	p.emission_sphere_radius = rad
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 10.0
	p.radial_accel_min = -(rad * 2.4)
	p.radial_accel_max = -(rad * 3.4)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(BANISH_COL.lightened(0.5), 0.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(BANISH_COL, 1.0))
	p.color_ramp = ramp
	p.z_index = 23
	fx.add_child(p)
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.emitting = true)
	tw.tween_interval(1.0)
	tw.tween_callback(func():
		if is_instance_valid(p):
			p.queue_free())

## A unit's trigger went off: the card pops with a hot rim light, a ring pulses out of it,
## light sweeps across it, sparks fly and a tag names the trigger, in the same orange as
## trigger names in the rules text, so what follows reads as coming from this card.
func _trigger_fx(v: Control, trigger: String, t: float) -> void:
	if v is CardView:
		var cv: CardView = v
		var tw := cv.create_tween()
		tw.tween_interval(t)
		tw.tween_callback(func(): cv.z_index = maxi(cv.z_index, 15))
		tw.tween_property(cv, "proc", 1.0, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(cv, "proc", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func(): cv.z_index = 0 if cv.z_index == 15 else cv.z_index)
		var wt := cv.create_tween()
		wt.tween_interval(t + 0.04)
		wt.tween_property(cv, "proc_wave", 1.0, 0.55).from(0.001)
		wt.tween_callback(func(): cv.proc_wave = 0.0)
	var c := _center_of(v)
	_embers(c, t + 0.05, CardView.TRIGGER_COL, 16)
	var trg: Dictionary = CardDB.data()["triggers"].get(trigger, {})
	if trg.is_empty():
		return
	var tag := _label(String(trg["name"]), 17, CardView.TRIGGER_COL.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER, "heavy", 4)
	tag.add_theme_stylebox_override("normal", UITheme.box(Color(0.05, 0.03, 0.02, 0.92), 12, Color(CardView.TRIGGER_COL, 0.95), 2, 10))
	tag.z_index = 25
	tag.modulate.a = 0.0
	fx.add_child(tag)
	tag.reset_size()
	tag.pivot_offset = tag.size / 2.0
	# sits on the card's top edge; pushed inside the screen near its borders
	var half_h: float = _pose(v)["w"] * CardView.BASE.y / CardView.BASE.x / 2.0 if v is CardView else 60.0
	var vw := get_viewport_rect().size.x
	var pos := Vector2(c.x - tag.size.x / 2.0, c.y - half_h - tag.size.y * 0.55)
	pos.x = clampf(pos.x, 8.0, vw - tag.size.x - 8.0)
	pos.y = maxf(pos.y, 6.0)
	tag.position = pos
	tag.scale = Vector2(0.55, 0.55)
	var lt := tag.create_tween()
	lt.tween_interval(t)
	lt.tween_property(tag, "modulate:a", 1.0, 0.08)
	lt.parallel().tween_property(tag, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lt.parallel().tween_property(tag, "position:y", pos.y - 10.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lt.tween_property(tag, "modulate:a", 0.0, 0.25)
	lt.tween_callback(tag.queue_free)

## Bolt of light from a trigger's source to what its effect hits, so the effect visibly comes
## from that card. Follows both ends if they move. Returns the travel time.
const STREAK_T := 0.2

func _streak(from: Control, to: Control, t: float, col: Color) -> float:
	var lines: Array[Line2D] = []
	for i in 2: # wide soft glow under a thin hot core
		if i == 0 and _fx_scale < 0.7:
			continue ## big chains: only the thin core, the soft glow is the costly overdraw
		var ln := Line2D.new()
		ln.width = 16.0 if i == 0 else 5.0
		ln.joint_mode = Line2D.LINE_JOINT_ROUND
		ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ln.end_cap_mode = Line2D.LINE_CAP_ROUND
		var gr := Gradient.new()
		var head := col.lightened(0.55) if i == 1 else col
		gr.set_color(0, Color(head, 0.0))
		gr.set_color(gr.get_point_count() - 1, Color(head, 0.35 if i == 0 else 1.0))
		ln.gradient = gr
		var wc := Curve.new()
		wc.add_point(Vector2(0, 0.15))
		wc.add_point(Vector2(1, 1))
		ln.width_curve = wc
		ln.z_index = 24
		ln.visible = false
		fx.add_child(ln)
		lines.append(ln)
	var bend := 1.0 if randf() < 0.5 else -1.0
	var wf: WeakRef = weakref(from) # either end may be freed mid-flight (re-render, dissolve)
	var wt: WeakRef = weakref(to)
	var paint := func(k: float, fade: float):
		var f: Control = wf.get_ref()
		var d: Control = wt.get_ref()
		if f == null or d == null:
			return
		var a := _center_of(f)
		var b := _center_of(d)
		var ctrl := (a + b) / 2.0 + (b - a).orthogonal().normalized() * minf(a.distance_to(b) * 0.18, 70.0) * bend
		var head := ease(k, -2.0)
		var tail := clampf(head - 0.45, 0.0, 1.0) + fade * (head - clampf(head - 0.45, 0.0, 1.0))
		var pts := PackedVector2Array()
		for j in 13:
			var u := lerpf(tail, head, j / 12.0)
			pts.append(a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u))
		for ln in lines:
			if is_instance_valid(ln):
				ln.visible = true
				ln.points = pts
	var tw := fx.create_tween()
	tw.tween_interval(t)
	tw.tween_method(func(k: float): paint.call(k, 0.0), 0.0, 1.0, STREAK_T)
	tw.tween_method(func(f: float): paint.call(1.0, f), 0.0, 1.0, 0.14)
	tw.tween_callback(func():
		for ln in lines:
			if is_instance_valid(ln):
				ln.queue_free())
	return STREAK_T

## How long a revealed spell/ability stays frozen mid-screen: long enough for the
## opponent to read it, short for your own plays (you already know what you cast).
## Hot-seat shares one screen between both players, so it gets a middle value.
const REVEAL_HOLD := 2.78
const REVEAL_HOLD_OWN := 0.8
const REVEAL_HOLD_HOTSEAT := 1.5
const REVEAL_W := 280.0 ## on-screen width of a revealed spell
const FATIGUE_W := 240.0

func _reveal_hold(p: int) -> float:
	if not online and not vs_ai:
		return REVEAL_HOLD_HOTSEAT
	return REVEAL_HOLD_OWN if p == viewer else REVEAL_HOLD

## A Leader ability has no card to show: a banner with its name and text instead.
func _ability_banner(p: int, t: float, hold: float, passive := false) -> void:
	var ab: Dictionary = CardDB.leader(g.players[p]["leader_id"])["ability"]
	var w := 440.0
	var box := PanelContainer.new()
	var sb := UITheme.box(Color(0.03, 0.03, 0.05, 0.94), 18, Color(UITheme.GOLD, 0.85), 2, 16)
	sb.set_content_margin_all(16)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(w, 0)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	col.add_child(_label("%s · %s do Líder" % [_pname(p), "Passiva" if passive else "Habilidade"], 15, Color(UITheme.TEXT, 0.6), HORIZONTAL_ALIGNMENT_CENTER, "body"))
	col.add_child(_label(String(ab["name"]), 30, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "bold", 4))
	var tx := _label(String(ab.get("text", "")), 18, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "body")
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.custom_minimum_size = Vector2(w - 32, 0)
	col.add_child(tx)
	box.z_index = 30
	box.modulate.a = 0.0
	fx.add_child(box)
	box.reset_size()
	box.position = Vector2(lane_cx - w / 2.0, 420 - box.size.y / 2.0)
	var tw := box.create_tween()
	tw.tween_interval(t)
	tw.tween_property(box, "modulate:a", 1.0, 0.2)
	tw.tween_interval(hold)
	tw.tween_property(box, "modulate:a", 0.0, 0.35)
	tw.tween_callback(box.queue_free)

## Cinematic band announcing who plays first: a dark strip across the board with a gold title.
func _first_banner(p: int) -> void:
	var mine: bool = p == viewer if (online or vs_ai) else true
	var title := "VOCÊ COMEÇA" if mine else "OPONENTE COMEÇA"
	if not online and not vs_ai:
		title = "%s COMEÇA" % _pname(p).to_upper()
	var tint: Color = UITheme.GOLD_LIGHT if mine else Color("#ff8a80")
	var band := Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.z_index = 40
	band.modulate.a = 0.0
	fx.add_child(band)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.size = Vector2(stage_w, 120)
	bg.position = Vector2(0, 360)
	band.add_child(bg)
	for y in [360.0, 478.0]:
		var line := ColorRect.new()
		line.color = Color(tint, 0.85)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.size = Vector2(stage_w, 2)
		line.position = Vector2(0, y)
		band.add_child(line)
	var sub := _label("PRIMEIRO TURNO", 16, Color(UITheme.TEXT, 0.65), HORIZONTAL_ALIGNMENT_CENTER, "body")
	sub.size = Vector2(stage_w, 24)
	sub.position = Vector2(0, 376)
	band.add_child(sub)
	var lb := _label(title, 46, tint, HORIZONTAL_ALIGNMENT_CENTER, "bold", 6)
	lb.size = Vector2(stage_w, 64)
	lb.position = Vector2(0, 404)
	band.add_child(lb)
	band.pivot_offset = Vector2(stage_w / 2.0, 420)
	band.scale = Vector2(1.12, 1.12)
	var tw := band.create_tween()
	tw.set_parallel(true)
	tw.tween_property(band, "modulate:a", 1.0, 0.3)
	tw.tween_property(band, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(1.3)
	tw.chain().tween_property(band, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(band.queue_free)

func _elem_color(card_id: String) -> Color:
	return Color(CardDB.essence(CardDB.essences_of(CardDB.card(card_id))[0]).get("color", "#ffffff"))

func _count_ghosts(old: Dictionary) -> int:
	var n := 0
	for k in old:
		if k is int and k > 0 and not views.has(k) and not old[k]["hand"] and old[k]["inst"].has("damage"):
			n += 1
	return n

## Plays the events out over the freshly rendered table: cards fly from where
## they were, attackers lunge, victims shake, numbers float, the dead dissolve.
## Returns the time (s) at which everything has settled.
func _animate(events: Array, old: Dictionary) -> float:
	if pending_pass or fx == null:
		return 0.0
	var bursts := 0
	for e in events:
		if e["type"] == "trigger":
			bursts += 1
	_fx_scale = 1.0 / maxf(1.0, (bursts + _count_ghosts(old)) / 3.0)
	var actors := views.duplicate()
	var ghosts: Array = []
	var exiled := {} ## uids banished by these events: they get the banish effect, not the death dissolve
	for e in events:
		if e["type"] == "banish":
			exiled[e["uid"]] = true
	var ghost_exiled: Array = [] ## parallel to ghosts
	for k in old:
		if k is int and k > 0 and not views.has(k) and not old[k]["hand"] and old[k]["inst"].has("damage"):
			var gh := _ghost(old[k]["card_id"], old[k]["inst"], old[k]["pose"])
			actors[k] = gh
			ghosts.append(gh)
			ghost_exiled.append(exiled.has(k))
	var cursor := 0.0
	var handled := {}
	var appear := {}
	var in_combat := false
	var last_src := 0
	var last_dst := 0
	var hit_t := 0.0
	var trig_src := 0 ## unit whose trigger caused the events that follow (0 = none)
	# Leader HP: _render drew the final value, so rewind it to what it was before these events
	# and step it down/up at each hit's moment instead of jumping straight to the end.
	var leader_hp := {}
	for e in events:
		if e["type"] in ["damage", "heal"] and e["uid"] < 0 and views.get(e["uid"]) is LeaderView:
			if not leader_hp.has(e["uid"]):
				leader_hp[e["uid"]] = views[e["uid"]].hp
			leader_hp[e["uid"]] += e["amount"] if e["type"] == "damage" else -e["amount"]
	for uid in leader_hp:
		views[uid].hp = leader_hp[uid]
	# Same for units on the board: rewind the damage counter shown on each card to what it was
	# before these events, then step it at each hit (so an AoE visibly ticks every card).
	var unit_damage := {}
	for e in events:
		if e["type"] in ["damage", "heal"] and e["uid"] > 0 and views.get(e["uid"]) is CardView and views[e["uid"]].inst.has("damage"):
			if not unit_damage.has(e["uid"]):
				unit_damage[e["uid"]] = views[e["uid"]].inst["damage"]
			unit_damage[e["uid"]] += -e["amount"] if e["type"] == "damage" else e["amount"]
	for uid in unit_damage:
		views[uid].inst["damage"] = unit_damage[uid]
		views[uid].queue_redraw()
	for e in events:
		var et: String = e["type"]
		if et in ["play", "ability", "passive", "resolve", "attack", "combat_damage", "start_turn", "end_turn"] \
				or (et in ["damage", "shield_break"] and e.get("src", 0) > 0):
			trig_src = 0
		# effects of a trigger fly out of their source as a bolt and land when it arrives
		if trig_src != 0 and et in ["damage", "heal", "shield_break", "buff", "dot", "freeze", "exhaust", "condemn", "tide_mark", "spell_shield_break", "summon"] \
				and e["uid"] != trig_src and actors.has(trig_src) and actors.has(e["uid"]):
			cursor += _streak(actors[trig_src], actors[e["uid"]], cursor, CardView.TRIGGER_COL) - 0.04
		match et:
			"trigger":
				if actors.has(e["uid"]):
					_trigger_fx(actors[e["uid"]], e["trigger"], cursor)
					trig_src = e["uid"]
					cursor += 0.3
			"buff":
				if actors.has(e["uid"]):
					var parts: Array = []
					if int(e["atk"]) != 0 or int(e["hp"]) != 0:
						parts.append("%+d/%+d" % [e["atk"], e["hp"]])
					for kw in e.get("keywords", []):
						parts.append(String(CardDB.data()["keywords"].get(kw, {}).get("name", kw)))
					if not parts.is_empty():
						_impact(actors[e["uid"]], " ".join(parts), Color("#a8ffa0"), cursor, false)
				cursor += 0.15
			"play":
				var uid: int = e["uid"]
				var cd := CardDB.card(e["card_id"])
				var origin: Dictionary = {"c": Vector2(lane_cx + EHAND_DX, 30), "rot": 0.0, "w": 96.0}
				if e.get("legendary", false) and old.has("cmd%d" % e["player"]):
					origin = old["cmd%d" % e["player"]]["pose"]
				elif e.get("requiem", false) and views.get(GameState.LEADER_UID[e["player"]]) is LeaderView:
					# a Réquiem spell rises from the graveyard icon of its caster
					origin = {"c": (views[GameState.LEADER_UID[e["player"]]] as LeaderView).position + LeaderView.GRAVE_CENTER, "rot": 0.0, "w": 96.0}
				elif e.has("source_uid") and old.has(e["source_uid"]):
					origin = old[e["source_uid"]]["pose"] # cast by a unit (Bola de Neve of Tempesfrost): it leaves that unit
				elif old.has(uid):
					origin = old[uid]["pose"]
				if cd["type"] == "unit" and views.has(uid):
					var v: CardView = views[uid]
					var to := _pose(v)
					handled[uid] = true
					v.z_index = 20
					var tw := _fly(v, origin, to, cursor, 0.42, 70.0, true)
					tw.tween_callback(func(): v.z_index = 0)
					var fs: Vector2 = Vector2.ONE * (to["w"] / v.size.x)
					tw.tween_property(v, "scale", fs * 1.1, 0.06)
					tw.tween_property(v, "scale", fs, 0.1)
					cursor += 0.45
				else:
					var gh := _ghost(e["card_id"], {}, origin, REVEAL_W / CardView.BASE.x) # built at its final size: scaling up would blur the text
					gh.z_index = 30
					var tw := _fly(gh, origin, {"c": Vector2(lane_cx, 420), "rot": 0.0, "w": REVEAL_W}, cursor, 0.35, 40.0, true)
					tw.tween_callback(func(): gh.z_index = 0)
					var hold := _reveal_hold(e["player"])
					gh.dissolve(cursor + 0.35 + hold, _elem_color(e["card_id"]).lightened(0.15), 0.6)
					cursor += 0.35 + hold - 0.15
			"fatigue":
				# shown like a played card, so the hit on the Leader that follows makes sense
				var fv := CardView.new().setup("", {}, FATIGUE_W / CardView.BASE.x)
				fv.fatigue = int(e["amount"])
				fv.mouse_filter = Control.MOUSE_FILTER_IGNORE
				fv.pivot_offset = fv.size / 2.0
				fv.z_index = 30
				fx.add_child(fv)
				var from_y := 860.0 + BOT if e["player"] == viewer else 30.0
				_fly(fv, {"c": Vector2(lane_cx + EHAND_DX, from_y), "rot": 0.0, "w": 96.0}, {"c": Vector2(lane_cx, 420), "rot": 0.0, "w": FATIGUE_W}, cursor, 0.35, 40.0, true)
				fv.dissolve(cursor + 0.35 + REVEAL_HOLD * 0.7, Color(0.75, 0.6, 1.0), 0.6)
				cursor += 0.35 + REVEAL_HOLD * 0.5
			"ability":
				var hold := _reveal_hold(e["player"])
				_ability_banner(e["player"], cursor, hold)
				cursor += 0.2 + hold - 0.15
			"passive":
				var hold := _reveal_hold(e["player"]) * 0.6
				_ability_banner(e["player"], cursor, hold, true)
				cursor += 0.2 + hold - 0.15
			"resolve":
				cursor += 0.15
			"fizzle":
				_toast("%s não teve alvo e foi anulado." % (_cname(e["card_id"]) if e["kind"] in ["card", "subito"] else "A habilidade"))
				cursor += 0.3
			"countered":
				_toast("%s foi anulado!" % ("A habilidade do Líder" if e["kind"] == "ability" else _cname(e["card_id"])))
				cursor += 0.4
			"spell_shield_break", "tide_mark", "tide_draw", "dot", "freeze", "exhaust", "condemn", "doom", "doom_resisted", "thaw", "dodge", "crit", "crit_negated", "critico_up":
				if actors.has(e["uid"]):
					var dot_name: String = {"queimadura": "Queimadura", "veneno": "Veneno", "sangramento": "Sangramento"}.get(String(e.get("dot", "")), "Marcador")
					var dot_label := "%s %d" % [dot_name, int(e.get("amount", 0))]
					if not e.get("cleared", false):
						dot_label = "%s +%d" % [dot_name, int(e.get("amount", 0))]
					var lbl: String = {"spell_shield_break": "Anulado!", "tide_mark": "Maré", "tide_draw": "+1 carta", "dot": dot_label, "freeze": "Congelada!", "exhaust": "Exausta!", "condemn": "Condenada!", "doom": "Ceifada!", "doom_resisted": "Resistiu!", "thaw": "Descongelou", "dodge": "Esquivou!", "crit": "Crítico!", "crit_negated": "Desdém!", "critico_up": "Crítico %d!" % int(e.get("level", 0))}[e["type"]]
					var col: Color = Color("#6fd0ff")
					if e["type"] == "spell_shield_break":
						col = Color("#c9a8ff")
					elif e["type"] in ["freeze", "thaw"]:
						col = ICE
					elif e["type"] in ["condemn", "doom", "doom_resisted"]:
						col = CardView.DOOM_COL
					elif e["type"] == "dot":
						col = CardView.dot_badge_color(String(e.get("dot", "")))
					elif e["type"] in ["crit", "crit_negated", "critico_up"]:
						col = Color("#ff9d6e") # same warm tone as the Crítico tag
					_impact(actors[e["uid"]], lbl, col, cursor, false)
					if e["type"] == "freeze":
						_freeze_fx(actors[e["uid"]], cursor)
					elif e["type"] == "thaw":
						_frost_shards(_center_of(actors[e["uid"]]), cursor, 16)
					elif e["type"] in ["condemn", "doom"]:
						_doom_fx(actors[e["uid"]], cursor, e["type"] == "doom")
				cursor += 0.2
			"transform":
				# a unit becomes another card in place (Transformar, transform_self)
				if actors.has(e["uid"]):
					_transform_fx(e["uid"], e["from"], e["card_id"], actors, old, cursor)
					cursor += TRANSFORM_TIME
			"snowball_evolve":
				# Bola de Neve cards turning into Grande Bola de Neve: the ones in hand are visible
				var evolved_in_view := false
				for evolved_uid in e.get("uids", []):
					if actors.has(evolved_uid) and old.has(evolved_uid):
						_transform_fx(evolved_uid, old[evolved_uid]["card_id"], actors[evolved_uid].card_id, actors, old, cursor)
						evolved_in_view = true
				if evolved_in_view:
					cursor += TRANSFORM_TIME
			"snowball_devolve":
				# Grande Bola de Neve cards going back to Bola de Neve when the level resets
				var devolved_in_view := false
				for devolved_uid in e.get("uids", []):
					if actors.has(devolved_uid) and old.has(devolved_uid):
						_transform_fx(devolved_uid, old[devolved_uid]["card_id"], actors[devolved_uid].card_id, actors, old, cursor)
						devolved_in_view = true
				if devolved_in_view:
					cursor += TRANSFORM_TIME
			"slots_frozen":
				if int(e["blocked"]) > 0:
					_toast("%s: %d espaço(s) vazio(s) congelado(s)!" % [_pname(e["player"]), e["blocked"]])
				cursor += 0.3
			"summon", "draw", "search_take":
				appear[e["uid"]] = cursor
				cursor += 0.1
				if e["type"] == "search_take" and int(e["player"]) != viewer:
					_toast("%s pegou %s do deck" % [_pname(e["player"]), _cname(e["card_id"])])
					cursor += 0.5
			"search_reveal", "look_top":
				cursor += 0.35
			"mill":
				cursor += _mill_fx(int(e["player"]), e["cards"], cursor)
			"combat_damage":
				in_combat = true
			"start_turn", "end_turn", "combat_end":
				in_combat = false
			"lethal_ward":
				# Câmara de Êxtase: the blow lands on the Leader, the Chamber answers and fades away
				var ward_leader: Control = actors.get(GameState.LEADER_UID[e["player"]])
				var ward_src: int = e.get("src", 0)
				var ward_t := cursor + 0.12
				if in_combat and ward_src > 0 and actors.has(ward_src) and ward_leader != null:
					if ward_src == last_src:
						ward_t = hit_t
					else:
						_lunge(actors[ward_src], ward_leader, cursor)
						hit_t = cursor + LUNGE_IMPACT_TIME
						ward_t = hit_t
						last_src = ward_src
						last_dst = GameState.LEADER_UID[e["player"]]
						cursor += LUNGE_TOTAL_TIME
				var ward_ghost: CardView = null
				if old.has(e["uid"]): # the Chamber is already gone from the table: a ghost stands in for it
					ward_ghost = _ghost(old[e["uid"]]["card_id"], old[e["uid"]]["inst"], old[e["uid"]]["pose"])
					ward_ghost.z_index = 20
				_ward_fx(ward_leader, ward_ghost, ward_t, _elem_color(e["card_id"]).lightened(0.3))
				cursor = maxf(cursor, ward_t + WARD_FADE_DELAY + WARD_FADE_TIME)
			"damage", "shield_break", "heal":
				var dst: int = e["uid"]
				var t := cursor
				if e["type"] in ["damage", "shield_break"] and in_combat and e.get("src", 0) > 0 and actors.has(e["src"]) and actors.has(dst):
					var src: int = e["src"]
					if src == last_src or (src == last_dst and dst == last_src):
						t = hit_t
					else:
						_lunge(actors[src], actors[dst], cursor)
						hit_t = cursor + LUNGE_IMPACT_TIME
						t = hit_t
						last_src = src
						last_dst = dst
						cursor += LUNGE_TOTAL_TIME
				else:
					cursor += 0.12
				if leader_hp.has(dst) and e["type"] in ["damage", "heal"]:
					leader_hp[dst] += -e["amount"] if e["type"] == "damage" else e["amount"]
					var lv: LeaderView = views[dst]
					var hp_change: int = -e["amount"] if e["type"] == "damage" else e["amount"]
					var ltw := lv.create_tween()
					ltw.tween_interval(t)
					_leader_ko_t = maxf(_leader_ko_t, t)
					# each hit adds its own change instead of writing a total: the hits are not always
					# shown in event order (a retaliation lands with the blow, a reflection after it),
					# and a total written late would overwrite the hits shown before it
					ltw.tween_callback(func():
						lv.hp += hp_change
						lv.queue_redraw())
				if unit_damage.has(dst) and e["type"] in ["damage", "heal"]:
					unit_damage[dst] += e["amount"] if e["type"] == "damage" else -e["amount"]
					var card_view: CardView = views[dst]
					var damage_change: int = e["amount"] if e["type"] == "damage" else -e["amount"]
					var card_tween := card_view.create_tween()
					card_tween.tween_interval(t)
					card_tween.tween_callback(func(): # adds its own change, same reason as the Leader above
						card_view.inst["damage"] += damage_change
						card_view.queue_redraw())
				if actors.has(dst):
					match e["type"]:
						"damage":
							_impact(actors[dst], "-%d" % e["amount"], Color("#ff5050"), t, true)
							if in_combat and int(e["amount"]) >= CRUSHING_BLOW_DAMAGE and e.get("src", 0) > 0:
								_crushing_blow_fx(actors[dst], int(e["amount"]), t)
								cursor = maxf(cursor, t + 0.35) # let the blow land before the next event
						"heal":
							_impact(actors[dst], "+%d" % e["amount"], Color("#5dff8a"), t, false)
						"shield_break":
							_impact(actors[dst], "Escudo!", Color("#9fe3ff"), t, false)
	var settle := cursor + 0.1
	var board_t := settle + (0.4 if not ghosts.is_empty() else 0.0)
	for i in ghosts.size():
		var gh: CardView = ghosts[i]
		if ghost_exiled[i]:
			gh.banish(settle + i * 0.06, BANISH_COL, 0.9)
			_banish_fx(_center_of(gh), _pose(gh)["w"], settle + i * 0.06)
			continue
		var col := _elem_color(gh.card_id)
		gh.dissolve(settle + i * 0.06, col.lightened(0.2), 0.75)
		_embers(_center_of(gh), settle + i * 0.06 + 0.1, col)
	var deck_n := 0
	var board_end := board_t + 0.3 ## when the last card has finished moving into place
	for k in views:
		var v = views[k]
		if handled.has(k) or not (v is CardView):
			continue
		var to := _pose(v)
		if old.has(k):
			var from: Dictionary = old[k]["pose"]
			var turns := absf(from["rot"] - to["rot"]) > 0.01 # tapping or untapping
			if turns:
				# lies down (or stands up) slowly, only after the hit is over and the card is back home
				_fly(v, from, to, board_t + TAP_DELAY, TAP_TIME)
				board_end = maxf(board_end, board_t + TAP_DELAY + TAP_TIME)
			elif from["c"].distance_to(to["c"]) > 1.0 or abs(from["w"] - to["w"]) > 1.0:
				_fly(v, from, to, 0.0 if hand_uids.has(k) else board_t, 0.28)
		elif hand_uids.has(k):
			_draw_from_deck(v, to, appear.get(k, 0.0) + 0.12 * deck_n)
			deck_n += 1
		else:
			var resting_scale: Vector2 = v.scale # a tapped unit rests smaller (see _render_board)
			v.scale = Vector2.ZERO
			var tw: Tween = v.create_tween()
			tw.tween_interval(appear.get(k, settle))
			tw.tween_property(v, "scale", resting_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return max(settle + 0.8, board_end)

# ---------------------------------------------------------------- log

var _toast_node: Label
var _toast_tw: Tween

## Short transient message (refused actions) instead of log spam.
func _toast(t: String) -> void:
	if _toast_node and is_instance_valid(_toast_node):
		_toast_node.queue_free()
	if _toast_tw:
		_toast_tw.kill()
	var l := _label(t, 24, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "bold", 4)
	l.add_theme_stylebox_override("normal", UITheme.box(Color(0.03, 0.03, 0.05, 0.92), 20, Color(UITheme.GOLD, 0.8), 2, 10))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(l)
	l.reset_size()
	l.position = Vector2(lane_cx - l.size.x / 2.0, 400)
	_toast_node = l
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.1)
	_toast_tw.tween_property(l, "modulate:a", 0.0, 0.4)
	_toast_tw.tween_callback(l.queue_free)

func _log(t: String) -> void:
	log_lines.append(t)

func _pname(p: int) -> String:
	if online:
		return "Você" if p == viewer else "Oponente"
	return "IA" if _is_ai(p) else "J%d" % (p + 1)

func _cname(id: String) -> String:
	return CardDB.card(id)["name"]

func _log_event(e: Dictionary) -> void:
	match e["type"]:
		"play":
			if e.get("subito", false):
				_log("%s invocou %s com Súbito" % [_pname(e["player"]), _cname(e["card_id"])])
			elif e.has("source_uid"):
				var caster_unit := g.find_unit(int(e["source_uid"]))
				_log("%s lançou %s%s" % [_pname(e["player"]), _cname(e["card_id"]), "" if caster_unit == null else " com " + _cname(caster_unit.card_id)])
			else:
				_log("%s jogou %s%s" % [_pname(e["player"]), _cname(e["card_id"]), " (Réquiem)" if e.get("requiem", false) else ""])
		"ability":
			_log("%s usou %s" % [_pname(e["player"]), CardDB.leader(g.players[e["player"]]["leader_id"])["ability"]["name"]])
		"transform":
			_log("%s transformou %s em %s" % [_pname(e["player"]), _cname(e["from"]), _cname(e["card_id"])])
		"passive":
			_log("%s ativou %s" % [_pname(e["player"]), CardDB.leader(g.players[e["player"]]["leader_id"])["ability"]["name"]])
		"trigger":
			var trg: Dictionary = CardDB.data()["triggers"].get(e["trigger"], {})
			_log("%s: %s" % [_cname(e["card_id"]), trg.get("name", e["trigger"])])
		"attack":
			var attacker := g.find_unit(e["attacker"])
			var attacker_name := "uma unidade" if attacker == null else _cname(attacker.card_id)
			if int(e["target"]) < 0:
				_log("%s atacou o Líder com %s" % [_pname(e["player"]), attacker_name])
			else:
				var challenged := g.find_unit(e["target"])
				_log("%s desafiou %s com %s" % [_pname(e["player"]), "uma unidade" if challenged == null else _cname(challenged.card_id), attacker_name])
		"enter_tapped":
			if e["tapped"]:
				var tapped_unit := g.find_unit(e["uid"])
				_log("%s entrou exaurida (Provocação)" % ("Uma unidade" if tapped_unit == null else _cname(tapped_unit.card_id)))
		"heal":
			if e.get("regeneration", false):
				var regenerated := g.find_unit(e["uid"])
				if regenerated != null:
					_log("%s regenerou %d" % [_cname(regenerated.card_id), e["amount"]])
		"death":
			pass
		"concede":
			conceded = e["player"]
			_log("%s desistiu da partida" % _pname(e["player"]))
		"fatigue":
			_log("%s: fadiga %d" % [_pname(e["player"]), e["amount"]])
		"start_turn":
			_log("— Turno %d: %s —" % [e["turn"], _pname(e["player"])])
			if int(e["turn"]) == 1:
				_first_banner(e["player"])
		"ban":
			_log("%s baniu uma carta da mão" % _pname(e["player"]))
		"search_reveal":
			if e.get("private", false):
				# the options of a deck search stay secret; only the card taken is announced (search_take)
				if int(e.get("looked", 0)) > 0:
					_log("%s olhou as %d cartas do topo do deck" % [_pname(e["player"]), int(e["looked"])])
				else:
					_log("%s procurou uma carta no deck" % _pname(e["player"]))
			else:
				var names: Array = []
				for c in e["cards"]:
					names.append(_cname(c["card_id"]))
				_log("%s revelou: %s" % [_pname(e["player"]), ", ".join(names)])
		"look_top":
			_log("%s olhou as %d cartas do topo do deck" % [_pname(e["player"]), e["cards"].size()])
		"look_bottom":
			_log("%s colocou as outras no fundo do deck" % _pname(e["player"]))
		"search_shuffle":
			_log("%s embaralhou o deck" % _pname(e["player"]))
		"mill":
			var milled: Array = []
			for cid in e["cards"]:
				milled.append(_cname(cid))
			_log("Do deck de %s ao cemitério: %s" % [_pname(e["player"]), ", ".join(milled)])
		"reflect":
			var mirror := g.find_unit(e["uid"])
			_log("%s refletiu %d de dano" % ["Uma unidade" if mirror == null else _cname(mirror.card_id), int(e["amount"])])
		"revive":
			_log("%s reviveu %s" % [_pname(e["player"]), _cname(e["card_id"])])
		"relic_enter":
			_log("%s colocou %s em campo" % [_pname(e["player"]), _cname(e["card_id"])])
		"relic_destroyed":
			_log("%s foi destruído" % _cname(e["card_id"]))
		"fuse":
			_log("%d fichas se fundiram em %s" % [int(e["count"]), _cname(e["card_id"])])
		"attach":
			_log("%s foi equipado em uma unidade" % _cname(e["card_id"]))
		"equipment_returned":
			_log("%s voltou para a mão (a unidade foi reequipada)" % _cname(e["card_id"]))
		"equipment_break":
			_log("%s foi ao cemitério com a unidade equipada" % _cname(e["card_id"]))
		"destroy":
			var destroyed := g.find_unit(e["uid"])
			_log("%s foi destruída" % ("Uma unidade" if destroyed == null else _cname(destroyed.card_id)))
		"banish":
			_log("%s foi banida" % _cname(e["card_id"]))
		"sacrifice":
			var sacrificed := g.find_unit(e["uid"])
			_log("%s sacrificou %s" % [_pname(e["player"]), "uma unidade" if sacrificed == null else _cname(sacrificed.card_id)])
		"freeze":
			var frozen := g.find_unit(e["uid"])
			_log("%s foi congelada" % ("Uma unidade" if frozen == null else _cname(frozen.card_id)))
		"dot":
			var dotted := g.find_unit(e["uid"])
			if not e.get("cleared", false):
				var dot_names := {"queimadura": "Queimadura", "veneno": "Veneno", "sangramento": "Sangramento"}
				var dotted_name := "Uma unidade" if dotted == null else _cname(dotted.card_id)
				if int(e["uid"]) < 0: # a Leader holds the markers
					dotted_name = "O Líder de %s" % _pname(GameState.LEADER_UID.find(int(e["uid"])))
				_log("%s recebeu %d marcador(es) de %s" % [dotted_name, int(e.get("amount", 0)), dot_names.get(String(e.get("dot", "")), "status")])
		"condemn":
			var condemned := g.find_unit(e["uid"])
			_log("%s foi condenada" % ("Uma unidade" if condemned == null else _cname(condemned.card_id)))
		"doom":
			var doomed := g.find_unit(e["uid"])
			_log("%s foi ceifada pela condenação" % ("Uma unidade" if doomed == null else _cname(doomed.card_id)))
		"doom_resisted":
			var resisted := g.find_unit(e["uid"])
			_log("%s resistiu à condenação" % ("Uma unidade" if resisted == null else _cname(resisted.card_id)))
		"exhaust":
			var exhausted_unit := g.find_unit(e["uid"])
			_log("%s ficou exausta" % ("Uma unidade" if exhausted_unit == null else _cname(exhausted_unit.card_id)))
		"card_created":
			_log("%s criou %s no %s" % [_pname(e["player"]), _cname(e["card_id"]), "topo do deck" if e["to"] == "deck_top" else "mão"])
		"slots_frozen":
			_log("%d espaços do campo de %s foram sorteados para congelar (%d vazios bloqueados)" % [e["positions"].size(), _pname(e["player"]), e["blocked"]])
		"slots_thaw":
			_log("Os espaços congelados de %s descongelaram" % _pname(e["player"]))
		"thaw":
			var thawed := g.find_unit(e["uid"])
			if thawed != null:
				_log("%s descongelou" % _cname(thawed.card_id))
		"legendary_retired":
			_log("%s foi para o fundo do deck como carta comum" % _cname(e["card_id"]))
		"enter_skip":
			_log("%s: Ao Entrar recusado" % _cname(e["card_id"]))
		"search_empty":
			_log("%s não encontrou uma carta que atendesse à busca" % _pname(e["player"]))
		"deck_summon":
			_log("%s saiu do deck e entrou em campo para %s" % [_cname(e["card_id"]), _pname(e["player"])])
		"search_take":
			_log("%s escolheu %s na busca" % [_pname(e["player"]), _cname(e["card_id"])])
		"fizzle":
			_log("%s foi anulado (alvo inválido)" % (_cname(e["card_id"]) if e["kind"] in ["card", "subito"] else "Habilidade"))
		"countered":
			_log("%s anulou %s" % [_pname(e["by"]), _cname(e["card_id"]) if e["kind"] in ["card", "subito"] else "a habilidade de " + _pname(e["player"])])
		"spell_shield_break":
			var shielded := g.find_unit(e["uid"])
			_log("Escudo de Feitiço anulou o efeito" + ("" if shielded == null else " em " + _cname(shielded.card_id)))
		"tide_draw":
			_log("%s: a maré retorna, compra 1" % _pname(e["player"]))
		"snowball":
			_log("%s: %s com %d de dano inicial" % [_pname(e["player"]), "Grande Bola de Neve" if e["grande"] else "Bola de Neve", int(e["amount"])])
		"snowball_evolve":
			_log("%s: a Bola de Neve chegou ao nível Grande, e %d carta(s) viraram Grande Bola de Neve" % [_pname(e["player"]), int(e["count"])])
		"snowball_devolve":
			_log("%s: o nível da Bola de Neve acabou, e %d carta(s) voltaram a ser Bola de Neve" % [_pname(e["player"]), int(e["count"])])
		"snowball_reset":
			_log("%s: a Bola de Neve volta ao nível %d" % [_pname(e["player"]), int(e["level"])])
		"snowball_level":
			_log("%s: o nível da Bola de Neve sobe para %d" % [_pname(e["player"]), int(e["level"])])
		"lethal_ward":
			_log("%s anulou %d de dano que mataria o Líder de %s" % [_cname(e["card_id"]), int(e["amount"]), _pname(e["player"])])
		"discard_pick":
			_log("%s escolhe uma carta da mão para descartar" % _pname(e["player"]))
		"hand_summon_pick":
			_log("%s escolhe um campeão da mão para entrar em campo de graça" % _pname(e["player"]))
		"hand_summon":
			_log("%s colocou %s em campo direto da mão (será banido no fim do turno)" % [_pname(e["player"]), _cname(e["card_id"])])
		"discard":
			_log("%s descartou %s" % [_pname(e["player"]), _cname(e["card_id"])])


# ---------------------------------------------------------------- widgets

func _label(t: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, kind := "", outline := 0) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = align
	if kind != "":
		l.add_theme_font_override("font", UITheme.font(kind))
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(t: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = t
	if primary:
		b.theme_type_variation = "PrimaryButton"
	b.pressed.connect(cb)
	return b

## An on/off button shown as a sliding switch instead of the words "LIGADO"/"desligado":
## gold track with the knob on the right when on, dark track with the knob on the left when off.
func _toggle_button(title: String, is_on: bool, on_press: Callable) -> Button:
	var button := Button.new()
	button.pressed.connect(on_press)
	var title_label := _label(title, 17, UITheme.TEXT if is_on else UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, "bold")
	title_label.position = Vector2(16, 0)
	title_label.size = Vector2(150, 48)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(title_label)
	var switch_size := Vector2(52, 26)
	var switch_area := Control.new()
	switch_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# anchored to the right edge and vertical middle of the button, so it stays put whatever size the button gets
	switch_area.anchor_left = 1.0
	switch_area.anchor_right = 1.0
	switch_area.anchor_top = 0.5
	switch_area.anchor_bottom = 0.5
	switch_area.offset_left = -switch_size.x - 16.0
	switch_area.offset_right = -16.0
	switch_area.offset_top = -switch_size.y / 2.0
	switch_area.offset_bottom = switch_size.y / 2.0
	# the title fills the button's height so it is centred vertically
	title_label.anchor_bottom = 1.0
	title_label.offset_bottom = 0.0
	switch_area.draw.connect(func():
		var track := UITheme.box(
			Color(UITheme.GOLD, 0.95) if is_on else Color(0.1, 0.09, 0.14, 0.95),
			13, UITheme.GOLD_LIGHT if is_on else Color(UITheme.TEXT, 0.35), 2)
		switch_area.draw_style_box(track, Rect2(Vector2.ZERO, switch_size))
		var knob_radius := switch_size.y / 2.0 - 5.0
		var knob_x := switch_size.x - switch_size.y / 2.0 if is_on else switch_size.y / 2.0
		switch_area.draw_circle(Vector2(knob_x, switch_size.y / 2.0), knob_radius,
			UITheme.INK if is_on else Color(UITheme.TEXT, 0.55)))
	button.add_child(switch_area)
	return button

## The "pass action" buttons (PASSAR, ENCERRAR TURNO, IR PARA O COMBATE...). Pressing one greys out
## all of them at once, so the press clearly counted and can't be sent twice; if an animation is still
## playing, the action waits for it and runs by itself as soon as the table settles.
func _action_button(text: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	if primary:
		button.theme_type_variation = "PrimaryButton"
	button.add_to_group("action_buttons")
	button.pressed.connect(func():
		for action_button: Button in get_tree().get_nodes_in_group("action_buttons"):
			action_button.disabled = true
		_run_or_queue_input(action))
	return button

## Crops a tall portrait to a wide window, anchored near the top so the face stays in frame
## (a centered crop shows the torso instead).
func _top_crop(tex: Texture2D, window: Vector2, focus := 0.06) -> Texture2D:
	if tex == null:
		return null
	var ts := tex.get_size()
	var ch := minf(ts.y, ts.x * window.y / window.x)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, (ts.y - ch) * focus, ts.x, ch)
	return at
