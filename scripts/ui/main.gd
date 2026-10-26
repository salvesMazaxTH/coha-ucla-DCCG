extends Control
## Table screen: menu, board rendering, input state machine, AI driver,
## hot-seat pass screen and the full-screen card summary overlay.

const ChronicleRowScript = preload("res://scripts/ui/chronicle_row.gd")
const ChronicleSceneScript = preload("res://scripts/ui/chronicle_scene.gd")

const SEL := Color("#ffd23f")
const TARGET := Color("#ff5050")
const OK := Color("#4dff88")
const ICE := Color("#bfefff")
## An exhausted (tapped) unit lies sideways on the table, like a tapped Magic card.
const TAPPED_TILT_DEGREES := 90.0
## A tapped card shrinks only a little: lying down it is wider than its cell, so on a crowded row
## it overlaps its neighbours a bit instead of turning tiny.
const TAPPED_MIN_SCALE := 0.85
## A tapped unit steps forward: its front edge sits this many pixels closer to the middle of the table
## than the front edge of the standing units, so "the cards in the front line" are the ones that can be attacked.
const TAPPED_FRONT_ADVANCE := 26.0
const COL_W := 232.0 ## right HUD column width
const STAGE_H := 1034.0
const BOT := 134.0 ## extra stage height under the boards: room for the Leader plate between the board and the hand
const STAGE_MAX_W := 2100.0
var stage_w := 1600.0 ## logical width: 1600 or wider, follows the window aspect
var col_x := 1352.0
var lane_cx := 882.0
var deck_piles := {} ## player -> LeaderView.DeckPile: each deck, drawn by the right edge of the table (see _render_piles)
var graveyard_piles := {} ## player -> GraveyardPile: each graveyard, a face-up pile right beside its deck
var motes: CPUParticles2D

var g: GameState
var vs_ai := true
var viewer := 0 ## whose perspective is drawn
var pending_pass := false
var _over_from := -1 ## index in layer of the first game-over node (-1 = none this frame)
var _leader_ko_t := -1.0 ## time of the last Leader HP change in the current animation
var net: NetClient ## online match link (null offline)
var account_button: Button
var deck_builder: DeckBuilder ## the "MEUS DECKS" screen while it is open
var _account_was_signed_in := false
var _session_was_checked := false
## The entry screen (Google / guest) comes before the mode buttons; this turns true once the player
## signed in or chose to play as a guest, and back to false when they sign out.
var _entered_menu := false
var _menu_screen_showing := false ## the title screen (entry or full menu) is what is on screen now
var _google_logo_texture: Texture2D
var online := false
var opp_online := true
var code_entry := ""
var join_slots: Label ## the room-code display of the join screen; null on every other screen (the keyboard types into it)
var sel_deck := "" ## deck picked in the hub (a prebuilt id, or a DeckDB.PLAYER_PREFIX id for one of the player's own)
var deck_store: DeckStore ## the player's saved decks (MEUS DECKS), listed in the hub; created on first use
var incomplete_player_decks := 0 ## saved decks that are not ready to play, so the hub leaves them out
var _hub_args: Array = [] ## the arguments of the last _show_hub call, to redraw it when the player's decks arrive
var hub_hotseat := false ## the deck hub's two-step flow is picking decks for hot-seat (player 1, then player 2) instead of AI
var hub_scroll: ScrollContainer ## the deck hub's scrolling gallery (null/freed outside the hub)
var hub_scroll_y := 0 ## how far the gallery was scrolled, kept across the hub's redraws
var hub_drag_distance := 0.0 ## how far the current press has dragged the gallery (a long drag isn't a tap)
const HUB_MARGIN := 40.0 ## space between the hub's panels and the stage sides
const HUB_TILE := Vector2(210, 236) ## every deck tile in the gallery has this size, however many decks exist
const HUB_TILE_GAP := 20.0
const HUB_TILE_PAD := 10.0 ## room around the gallery's tiles for the hover zoom
## The gallery's titled dividers, in order; a deck's "section" field picks one (default "essencia").
## "hint" is shown instead of tiles when the section has no deck (the others are left out when empty).
const HUB_SECTIONS := [
	{"id": DeckDB.SECTION_ESSENCE, "title": "DECKS DE ESSÊNCIA"},
	{"id": DeckDB.SECTION_SPECIAL, "title": "DECKS ESPECIAIS"},
	{"id": DeckDB.SECTION_MINE, "title": "MEUS DECKS", "hint": "Você ainda não tem nenhum deck pronto. Monte um em MEUS DECKS, no menu inicial: 44 cartas, a Encarnação do Líder e as regras do deck cumpridas."},
]
const HUB_EMPTY_HINT_H := 72.0 ## height of the hint that stands in for the tiles of an empty section
const HUB_SECTION_TITLE_H := 52.0 ## height of a divider's title row
const HUB_SECTION_GAP := 28.0 ## empty space between the end of one section and the next title
const HUB_DRAG_SLOP := 12.0 ## pixels a press may move and still count as a tap on a deck
var ai_deck := "" ## deck the AI plays, picked in the second step of the AI hub ("" = a random other deck)
var _fps_counter: Label
var _fps_counter_visible := false
var _fps_sample_seconds := 0.0
var _fps_sample_frames := 0

# input state
var picked: Array = [] ## mulligan/discard selection
var targeting := {} ## {"kind": hand|incarnation|ability|enter|attack, "uid": int, "spec": String}

var log_lines: Array = []
var chronicle_entries: Array = [] ## structured visual history; log_lines remains as a text fallback
var _chronicle_visual_context: Dictionary = {}
var _chronicle_next_seq := 1 ## every Chronicle entry gets a number, so a row can be found again after a redraw
var _chronicle_seen_seq := 0 ## entries up to this number were already drawn once (newer ones glow as they appear)
var _chronicle_list_rect := Rect2() ## where the Chronicle list is on the stage (empty when it is not drawn)
var chronicle_scene: ChronicleScene ## the big panel that replays a hovered Chronicle row beside the list
var _chronicle_rows_box: VBoxContainer ## holds the ChronicleRow nodes of the current screen
var bg: TextureRect ## table surface, baked once into bg_vp (the live shader was too heavy for weak phones)
var bg_vp: SubViewport
var bg_rect: ColorRect
var bg_mat: ShaderMaterial
var table: TableView
var layer: Control
var overlay: Control
var search_overlay: Control
## Hash of the pending search the player folded away to look at the table (-1 = none). Comparing the
## hash instead of a flag means the next search always opens expanded.
var search_minimized_signature := -1
var search_opened_signature := -1 ## the opponent's choice the player asked to see (those start folded)
var grave_view: Control ## graveyard viewer (child of Main, outlives _render)
var decklist_view: DecklistView ## a deck's card list, opened from the deck selection hub (child of Main)
var concede_view: Control ## "concede?" confirmation (child of Main, outlives _render)
var conceded := -1 ## player who gave up this match (-1 = nobody); only used for the game-over text
var grave_panel: PanelContainer
var grave_scroll: ScrollContainer
var grave_owner := 0
var grave_filter := "all"
var grave_drag_ms := -1000 ## last finger-drag in the viewer: taps right after it are not clicks
var views := {} ## uid (or "cmd<p>") -> Control on screen, for animations
var _unit_board_views := {} ## uid -> unit CardView from the last board render, kept for same-slot updates
var _unit_views_for_reuse := {} ## detached unit views being matched against the next board layout
var barricade_was_up := {} ## unit uid -> was it a tapped, unfrozen Provocação in the previous render? (to spot the moment it slams shut)
var hand_uids := {} ## viewer's hand cards in the current render
var hint_text := "" ## the tip pill fades out after a few seconds and returns when the player seems lost
var hint_since := 0
var hint_until := 0
var last_input_ms := 0
var hint_pill: Control
var aim_arrow: AimArrow ## targeting arrow from the source to the pointer
var reaction_arrow: AimArrow ## locked dashed arrow showing the pending attack during a reaction
var reaction_attack: Dictionary = {} ## {"attacker": uid, "target": uid} from the latest reaction event
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

## "PASSAR TUDO" is a switch. Turning it on waits PASS_ALL_UNDO_SECONDS on this screen first (a misclick is
## undone with no network and no race); turning it off, and the real turning on, are confirmed by the server.
const PASS_ALL_UNDO_SECONDS := 1.5
const PASS_ALL_SERVER_TIMEOUT_SECONDS := 4.0
var _pass_all_arming := false ## inside the undo window: nothing was sent yet
var _pass_all_arming_id := 0 ## tells an old undo timer from the current one
var _pass_all_waiting_for_server := false ## sent, but the snapshot has not shown the new state yet
var _pass_all_expected_state := false ## what the snapshot should show when the server has answered
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
		cf.load("user://settings.cfg") # keep the other settings (sound, music, auto-pass) in the file
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
	# phones: trim the purely decorative work (see GraphicsQuality)
	if _is_phone():
		GraphicsQuality.use_phone_settings()
	Engine.max_fps = GraphicsQuality.max_fps
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
	if GraphicsQuality.show_motes:
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
	SupabaseAuth.state_changed.connect(_on_supabase_auth_state_changed)
	_show_menu()
	_load_scenario()

## Dev only: `-- --scenario=<name>` starts a match vs the AI set up by tests/scenarios/<name>.gd
## (static func setup(g)). The script may declare PLAYER_DECK / ENEMY_DECK; the default is Maré vs Fogo.
func _load_scenario() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--scenario="):
			continue
		var script: GDScript = load("res://tests/scenarios/%s.gd" % a.trim_prefix("--scenario="))
		var scenario_constants := script.get_script_constant_map()
		_start(true, String(scenario_constants.get("PLAYER_DECK", "agua")), String(scenario_constants.get("ENEMY_DECK", "fogo")))
		script.setup(g)
		g.auto_pass[0] = _auto_pass_on()
		pending_pass = false
		log_lines = ["Cenário de teste carregado."]
		chronicle_entries.clear()
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
		elif not table.visible and not is_instance_valid(deck_builder):
			_show_menu.call_deferred() # the deck builder stretches with the stage by itself

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
	DeckDB.clear_custom(DeckDB.ROOM_PREFIX) # decks of a finished online match; "resume" sends them again
	g = null
	Music.stop()
	_close_concede()
	_clear_fx()
	_clear()
	table.visible = false
	_set_tints(Color("#3f7bd9"), Color("#e0572b"), 1.6)
	# the two Leaders of the slice, facing each other from the edges
	for side in [["furia/ronan.webp", 0.0, 1.0], ["fluxo/naelthos.webp", stage_w - 640.0, 0.0]]:
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
	_menu_screen_showing = true
	# a session restored from an earlier visit skips the entry screen
	if SupabaseAuth.is_signed_in():
		_entered_menu = true
	if _entered_menu:
		_add_menu_mode_buttons()
	else:
		_add_entry_buttons()
	var lt := _toggle_button("MODO LEVE", _light_on(), func():
		_apply_light(not _light_on(), true)
		_show_menu.call_deferred())
	lt.position = Vector2(stage_w - 300, 790.0 + BOT)
	lt.size = Vector2(280, 52)
	layer.add_child(lt)
	var sound_toggle := _toggle_button("SOM", Sfx.is_enabled(), func():
		Sfx.set_enabled(not Sfx.is_enabled())
		_show_menu.call_deferred())
	sound_toggle.position = Vector2(stage_w - 300, 662.0 + BOT)
	sound_toggle.size = Vector2(280, 52)
	layer.add_child(sound_toggle)
	var volume_control := _volume_slider(Vector2(280, 52))
	volume_control.position = Vector2(stage_w - 300, 598.0 + BOT)
	layer.add_child(volume_control)
	# the music has its own switch and volume, stacked above the sound effects ones
	var music_toggle := _toggle_button("MÚSICA", Music.is_enabled(), func():
		Music.set_enabled(not Music.is_enabled())
		_show_menu.call_deferred())
	music_toggle.position = Vector2(stage_w - 300, 534.0 + BOT)
	music_toggle.size = Vector2(280, 52)
	layer.add_child(music_toggle)
	var music_volume_control := _volume_slider(Vector2(280, 52), true)
	music_volume_control.position = Vector2(stage_w - 300, 470.0 + BOT)
	layer.add_child(music_volume_control)
	var fs := _button("Tela cheia (F11)", _toggle_fullscreen)
	fs.position = Vector2(stage_w - 300, 790.0 + BOT - 64.0)
	fs.size = Vector2(280, 52)
	layer.add_child(fs)
	var ver := _label("0.2.2 Alpha", 13, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, "body")
	ver.position = Vector2(stage_w - 300, 864.0 + BOT)
	ver.size = Vector2(280, 20)
	layer.add_child(ver)

## Entry screen: before the mode buttons, the player either signs in with Google or goes on as a guest.
func _add_entry_buttons() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.position = Vector2(stage_w / 2.0 - 210, 410)
	column.custom_minimum_size = Vector2(420, 0)
	layer.add_child(column)
	if not SupabaseAuth.is_session_checked():
		# still looking for a saved session: no buttons yet, so they don't flash and vanish
		column.add_child(_label("Verificando sua conta…", 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
		return
	column.add_child(_google_sign_in_button())
	column.add_child(_label("Salva seu perfil e seus decks na nuvem", 14, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var guest_button := _button("ENTRAR COMO CONVIDADO", func() -> void:
		_entered_menu = true
		_show_menu())
	guest_button.custom_minimum_size = Vector2(420, 58)
	column.add_child(guest_button)
	column.add_child(_label("Joga sem conta; nada fica salvo na nuvem", 14, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))

## The standard "Sign in with Google" button, following Google's branding rules: white background,
## thin grey border, the four-colour G on the left and dark grey text (Roboto Medium when the system
## has it). It is drawn bigger than Google's 40 px because the whole stage is scaled down on phones.
func _google_sign_in_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(420, 58)
	button.tooltip_text = "Entrar com a sua conta Google."
	var normal_style := UITheme.box(Color("#ffffff"), 6, Color("#747775"), 1)
	var hover_style := UITheme.box(Color("#f2f2f2"), 6, Color("#747775"), 1)
	var pressed_style := UITheme.box(Color("#e3e3e3"), 6, Color("#747775"), 1)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("hover_pressed", pressed_style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(Sfx.play.bind("ui_click"))
	button.pressed.connect(_start_google_sign_in)
	# logo and text side by side, centred inside the button
	var content_row := HBoxContainer.new()
	content_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content_row.add_theme_constant_override("separation", 14)
	content_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content_row)
	var logo := TextureRect.new()
	logo.texture = _google_logo()
	logo.custom_minimum_size = Vector2(26, 26)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_row.add_child(logo)
	var google_font := SystemFont.new()
	google_font.font_names = PackedStringArray(["Roboto", "Segoe UI", "Helvetica Neue", "Arial"])
	google_font.font_weight = 500
	google_font.fallbacks = [UITheme.font("bold")]
	var text_label := _label("Entrar com o Google", 20, Color("#1f1f1f"), HORIZONTAL_ALIGNMENT_LEFT)
	text_label.add_theme_font_override("font", google_font)
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content_row.add_child(text_label)
	return button

## Google's official four-colour "G", built from its SVG once and reused.
func _google_logo() -> Texture2D:
	if _google_logo_texture:
		return _google_logo_texture
	var svg_source := """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>"""
	var logo_image := Image.new()
	# drawn at 2x so it stays sharp when the stage is scaled up on big screens
	logo_image.load_svg_from_string(svg_source, 2.0)
	_google_logo_texture = ImageTexture.create_from_image(logo_image)
	return _google_logo_texture

## The deck builder takes over the whole stage; its way back is the title menu.
func _open_deck_builder() -> void:
	_clear()
	deck_builder = DeckBuilder.new()
	deck_builder.closed.connect(func() -> void:
		deck_builder = null
		_show_menu())
	layer.add_child(deck_builder)

## The full title menu, once the player is in: the three ways to play, the deck builder and the account button.
func _add_menu_mode_buttons() -> void:
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
			["ONLINE", "Jogar contra outra pessoa por código de sala", func() -> void: _show_hub(false), false],
			["MEUS DECKS", "Crie, edite e guarde seus próprios decks", _open_deck_builder, false]]:
		var b := _button(opt[0], opt[2], opt[3])
		b.custom_minimum_size = Vector2(420, 58)
		b.tooltip_text = opt[1]
		box.add_child(b)
		var sub := _label(opt[1], 14, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body")
		box.add_child(sub)
	# a guest can still link a Google account later from here
	account_button = _button("ENTRAR COM GOOGLE", _on_account_button_pressed)
	account_button.position = Vector2(24, 24)
	account_button.size = Vector2(300, 52)
	account_button.tooltip_text = "Vincule sua conta para salvar perfil e decks."
	layer.add_child(account_button)
	_update_account_button()

func _on_account_button_pressed() -> void:
	if SupabaseAuth.is_signed_in():
		SupabaseAuth.sign_out()
	else:
		_start_google_sign_in()

func _start_google_sign_in() -> void:
	SupabaseAuth.sign_in_with_google()
	# on the web the page itself goes to Google; the executable opens a separate browser window
	if not OS.has_feature("web"):
		_toast("Abrimos o navegador: entre com o Google lá e depois volte ao jogo.")

func _on_supabase_auth_state_changed(auth_state: Dictionary) -> void:
	_update_account_button()
	var signed_in_now := bool(auth_state.get("signed_in", false))
	var session_checked_now := bool(auth_state.get("session_checked", false))
	if _menu_screen_showing:
		if signed_in_now and not _entered_menu:
			# came back from Google (or a saved session was found): go into the full menu
			_entered_menu = true
			_show_menu.call_deferred()
		elif not signed_in_now and _account_was_signed_in:
			# signed out: back to the entry screen
			_entered_menu = false
			_show_menu.call_deferred()
		elif session_checked_now and not _session_was_checked and not _entered_menu:
			# the saved-session check finished with no session: show the entry buttons
			_show_menu.call_deferred()
	_session_was_checked = session_checked_now
	var error_message := String(auth_state.get("error", ""))
	if not error_message.is_empty():
		_toast(error_message)
	elif bool(auth_state.get("signed_in", false)) and not _account_was_signed_in:
		var profile: Dictionary = auth_state.get("profile", {})
		_toast("Conta Google conectada%s" % (": %s" % String(profile.get("username", "")) if not profile.is_empty() else "."))
	_account_was_signed_in = bool(auth_state.get("signed_in", false))

func _update_account_button() -> void:
	if not is_instance_valid(account_button):
		return
	if SupabaseAuth.is_signed_in():
		var profile: Dictionary = SupabaseAuth.state.get("profile", {})
		var username := String(profile.get("username", "CONTA CONECTADA"))
		account_button.text = "SAIR DA CONTA · %s" % username.to_upper()
		account_button.tooltip_text = "Sessão Google ativa. Toque para sair."
	else:
		account_button.text = "ENTRAR COM GOOGLE"
		account_button.tooltip_text = "Vincule sua conta para salvar perfil e decks."

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
	_queue_deck_arts([deck_a, deck_b])
	barricade_was_up.clear() # unit uids restart with every match
	for i in 2:
		g.auto_pass[i] = _auto_pass_on() or _is_ai(i)
	CardDB.reroll_flavor()
	Sfx.play("card_shuffle")
	Music.play_match()
	log_lines = ["Partida iniciada. Escolha até 3 cartas para trocar."]
	chronicle_entries.clear()
	conceded = -1
	viewer = 0
	pending_pass = not vs_ai
	_reset_input()
	_clear_fx()
	_render()

func _reset_input() -> void:
	picked.clear()
	targeting = {}

## Queues every art the two decks can show (cards, Leaders, Encarnações) to load in the background
## during the mulligan, so no card stalls the game the first time it is drawn.
func _queue_deck_arts(deck_ids: Array) -> void:
	var art_files: Array = []
	for deck_id in deck_ids:
		if not DeckDB.has(String(deck_id)):
			continue
		var deck := DeckDB.get_deck(String(deck_id))
		var leader_data := CardDB.leader(deck["leader"])
		art_files.append(leader_data.get("art", ""))
		var card_ids: Array = deck["cards"].keys()
		card_ids.append(leader_data.get("incarnation", ""))
		for card_id in card_ids:
			if CardDB.data()["cards"].has(card_id):
				art_files.append(CardDB.card(card_id).get("art", ""))
	CardView.queue_art_preload(art_files)

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
	_hub_args = [ai, msg, choosing_ai_deck]
	_refresh_player_decks()
	# prebuilt decks first, then the player's own (the third section), so the default pick is always a prebuilt deck
	var ids: Array[String] = DeckDB.ids()
	ids.append_array(DeckDB.custom_ids(DeckDB.PLAYER_PREFIX))
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
	# The gallery is split into titled sections (see DeckDB.section_of); a section with no deck is left out.
	var gallery_sections: Array = []
	var random_tile_placed := false
	for section in HUB_SECTIONS:
		var section_ids: Array = ids.filter(func(deck_id: String) -> bool: return DeckDB.section_of(deck_id) == section["id"])
		# the "random deck" tile comes first, in the first section
		if choosing_ai_deck and not random_tile_placed:
			section_ids.push_front("")
			random_tile_placed = true
		var section_title := String(section["title"])
		if section["id"] == DeckDB.SECTION_MINE and incomplete_player_decks > 0:
			section_title += "  ·  %d incompleto%s em MEUS DECKS" % [incomplete_player_decks, "" if incomplete_player_decks == 1 else "s"]
		if not section_ids.is_empty() or section.has("hint"):
			gallery_sections.append({"title": section_title, "ids": section_ids, "hint": section.get("hint", "")})
	var show_section_titles := gallery_sections.size() > 1
	var columns := maxi(1, int((gallery_w + HUB_TILE_GAP) / (HUB_TILE.x + HUB_TILE_GAP)))
	var content_h := 0.0
	for section in gallery_sections:
		if show_section_titles:
			content_h += HUB_SECTION_TITLE_H
		content_h += _hub_section_body_height(section, columns) + HUB_SECTION_GAP
	content_h -= HUB_SECTION_GAP
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
	var section_top := HUB_TILE_PAD
	for section in gallery_sections:
		if show_section_titles:
			_add_hub_section_title(content, String(section["title"]), Vector2(grid_x, section_top), grid_w)
			section_top += HUB_SECTION_TITLE_H
		var section_ids: Array = section["ids"]
		if section_ids.is_empty():
			var hint := _label(String(section["hint"]), 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, "body")
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.position = Vector2(grid_x, section_top)
			hint.size = Vector2(grid_w, HUB_EMPTY_HINT_H)
			content.add_child(hint)
		for i in section_ids.size():
			var id: String = section_ids[i]
			var is_selected := id == selected_id
			var t := _deck_tile(id, HUB_TILE, is_selected)
			t.position = Vector2(grid_x + (i % columns) * (HUB_TILE.x + HUB_TILE_GAP), section_top + (i / columns) * (HUB_TILE.y + HUB_TILE_GAP))
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
		section_top += _hub_section_body_height(section, columns) + HUB_SECTION_GAP
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

## Height of a gallery section below its title: its rows of tiles, or the hint of an empty one.
func _hub_section_body_height(section: Dictionary, columns: int) -> float:
	var tile_count: int = section["ids"].size()
	if tile_count == 0:
		return HUB_EMPTY_HINT_H
	var rows := ceili(float(tile_count) / float(columns))
	return rows * HUB_TILE.y + (rows - 1) * HUB_TILE_GAP

## Registers the player's saved decks (MEUS DECKS) in DeckDB so the hub, the match and the deck list treat
## them like prebuilt ones. Only decks that already pass every rule can be played; the rest are counted.
func _refresh_player_decks() -> void:
	if deck_store == null:
		_use_deck_store(DeckStore.new())
	DeckDB.clear_custom(DeckDB.PLAYER_PREFIX)
	incomplete_player_decks = 0
	for saved_deck in deck_store.list():
		var leader_id := String(saved_deck["leader"])
		if leader_id == "" or not DeckDB.validate_cards(leader_id, saved_deck["cards"]).is_empty():
			incomplete_player_decks += 1
			continue
		DeckDB.register_custom(DeckDB.PLAYER_PREFIX + String(saved_deck["id"]), String(saved_deck["name"]),
				String(saved_deck["description"]), leader_id, saved_deck["cards"])

func _use_deck_store(store: DeckStore) -> void:
	deck_store = store
	add_child(deck_store)
	deck_store.changed.connect(_on_player_decks_changed)

## The account's decks arrive (or change) after the hub was drawn: draw it again with them.
func _on_player_decks_changed() -> void:
	if is_instance_valid(hub_scroll) and hub_scroll.is_visible_in_tree() and _hub_args.size() == 3:
		hub_scroll_y = hub_scroll.scroll_vertical
		_show_hub.call_deferred(_hub_args[0], _hub_args[1], _hub_args[2])

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
	var footer := "%d cartas · Encarnação: %s" % [DeckDB.card_count(id), CardDB.card(ld["incarnation"])["name"]]
	_showcase_text(p, size, who, String(d["name"]), leader_line, col, String(d.get("description", "")), footer, art_h - 30.0)
	p.add_child(_decklist_button(id, size))
	return p

## A small "list" pill in the showcase's top right corner: opens the deck's card list (DecklistView).
func _decklist_button(id: String, showcase_size: Vector2) -> Button:
	var button_size := Vector2(176.0, 64.0)
	var button := Button.new()
	button.custom_minimum_size = button_size
	button.size = button_size
	button.position = Vector2(showcase_size.x - button_size.x - 18.0, 18.0)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Ver a lista de cartas do deck."
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(40.0, button_size.y / 2.0)
	icon.draw.connect(func():
		# the universal "list" icon: three lines, each with a bullet in front
		for line_y in [-14.0, 0.0, 14.0]:
			icon.draw_circle(Vector2(-18.0, line_y), 3.5, UITheme.GOLD_LIGHT)
			icon.draw_line(Vector2(-8.0, line_y), Vector2(20.0, line_y), UITheme.GOLD_LIGHT, 3.5))
	button.add_child(icon)
	var caption := _label("LISTA", 26, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "bold")
	caption.position = Vector2(80.0, 0.0)
	caption.size = Vector2(button_size.x - 88.0, button_size.y)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(caption)
	button.pressed.connect(Sfx.play.bind("ui_click"))
	button.pressed.connect(func(): _open_decklist(id))
	return button

# ---------------------------------------------------------------- deck list

## Opens the deck list window. A tap on one of its cards shows the match's own card overlay on top of it.
func _open_decklist(deck_id: String) -> void:
	_close_decklist()
	decklist_view = DecklistView.new().open(deck_id, Vector2(stage_w, STAGE_H))
	decklist_view.closed.connect(_close_decklist)
	decklist_view.card_chosen.connect(_show_decklist_card)
	add_child(decklist_view)

func _close_decklist() -> void:
	if decklist_view == null:
		return
	var old_view := decklist_view
	decklist_view = null
	if old_view.get_parent() != null:
		old_view.get_parent().remove_child(old_view)
	old_view.queue_free()

## The overlay needs a CardView to read from; a plain printed card (no match state) is enough here.
func _show_decklist_card(card_id: String) -> void:
	var printed_card := CardView.new().setup(card_id, {}, 1.0)
	_show_overlay(printed_card)
	printed_card.free()

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

## A section divider in the hub gallery: the title on the left and a thin gold line under it.
func _add_hub_section_title(content: Control, title_text: String, pos: Vector2, width: float) -> void:
	var title := _label(title_text, 22, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "title_bold", 4)
	title.position = pos + Vector2(4, 4)
	title.size = Vector2(width - 8, 30)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title)
	var line := ColorRect.new()
	line.color = Color(UITheme.GOLD, 0.55)
	line.position = pos + Vector2(0, 38)
	line.size = Vector2(width, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(line)

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
	join_slots = slots
	box.add_child(slots)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for ch in ROOM_CODE_LETTERS:
		var kb := _button(ch, _type_room_code_letter.bind(ch))
		kb.custom_minimum_size = Vector2(68, 60)
		kb.add_theme_font_size_override("font_size", 26)
		grid.add_child(kb)
	var back := _button("⌫", _erase_room_code_letter)
	back.custom_minimum_size = Vector2(68, 60)
	back.add_theme_font_size_override("font_size", 26)
	grid.add_child(back)
	var go := _button("ENTRAR NA SALA", _join_typed_room, true)
	go.custom_minimum_size = Vector2(600, 64)
	box.add_child(go)
	var bk := _button("Voltar", func() -> void: _show_online())
	bk.custom_minimum_size = Vector2(600, 52)
	box.add_child(bk)

func _code_text() -> String:
	return code_entry + "_".repeat(4 - code_entry.length())

## Letters a room code can use (no I, L or O: they look like 1 and 0).
const ROOM_CODE_LETTERS := "ABCDEFGHJKMNPQRSTUVWXYZ"

func _type_room_code_letter(letter: String) -> void:
	if code_entry.length() < 4:
		code_entry += letter
		join_slots.text = _code_text()

func _erase_room_code_letter() -> void:
	code_entry = code_entry.substr(0, code_entry.length() - 1)
	join_slots.text = _code_text()

func _join_typed_room() -> void:
	if code_entry.length() == 4:
		online = true
		net.join(code_entry, sel_deck)
		_show_wait("Entrando na sala…")

## The physical keyboard types into the join screen like its on-screen keypad does.
## Returns true when the key was used.
func _join_screen_key(key: InputEventKey) -> bool:
	if join_slots == null:
		return false
	if key.keycode == KEY_BACKSPACE:
		_erase_room_code_letter()
		return true
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_join_typed_room()
		return true
	var letter := char(key.unicode).to_upper()
	if key.unicode != 0 and ROOM_CODE_LETTERS.contains(letter):
		_type_room_code_letter(letter)
		return true
	return false

## Space / Enter during a game press the main action button on screen (PASSAR, RESOLVER, ENCERRAR
## TURNO, IR PARA O COMBATE...), the same as clicking it. Choices that need a deliberate answer
## (mulligan, enter tapped, discard...) are left to the mouse.
func _press_main_action_with_keyboard() -> bool:
	if g == null or g.phase not in ["main", "combat"] or overlay or grave_view or concede_view:
		return false
	for action_button: Button in get_tree().get_nodes_in_group("action_buttons"):
		if action_button.theme_type_variation == "PrimaryButton" and not action_button.disabled \
				and action_button.is_visible_in_tree() and not action_button.is_queued_for_deletion():
			action_button.pressed.emit()
			return true
	return false

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

## An online match can use the players' own decks. The server sends their contents (already validated
## there) under "room:" ids, and both clients register them like any other deck.
func _register_room_decks(deck_data: Variant) -> void:
	if not deck_data is Dictionary:
		return
	for deck_id in deck_data:
		var deck: Variant = deck_data[deck_id]
		if String(deck_id).begins_with(DeckDB.ROOM_PREFIX) and deck is Dictionary:
			DeckDB.register_custom(String(deck_id), String(deck.get("name", "")), String(deck.get("description", "")), String(deck.get("leader", "")), deck.get("cards", {}))

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
			_register_room_decks(m.get("deck_data", {})) # the players' own decks, before anything looks them up
			var rs := RemoteState.new(d[0], d[1])
			_queue_deck_arts(d)
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
			Music.play_match() # a reconnect in the middle of a match keeps the music going
			viewer = m["seat"]
			pending_pass = false
			opp_online = true
			if log_lines.is_empty() or m.get("snap", {}).get("turn", 0) == 0:
				log_lines = ["Partida online iniciada."]
				chronicle_entries.clear()
				conceded = -1
			_reset_input()
			_clear_fx()
			_render()
		"events":
			if not (g is RemoteState):
				return
			(g as RemoteState).apply_snapshot(m["snap"])
			if _pass_all_waiting_for_server and bool(g.skip_rest_of_turn[viewer]) == _pass_all_expected_state:
				_pass_all_waiting_for_server = false # the server confirmed the PASSAR TUDO switch
			_reset_input()
			for e in m["events"]:
				_log_event(e)
			_show_events(m["events"])
		"reject":
			_toast("Ação inválida.")
			Sfx.play("ui_error")
			_stop_waiting_for_pass_all()
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
		Sfx.play("ui_error")
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
	for e in events:
		if e["type"] == "reaction":
			reaction_attack = {"attacker": int(e["attacker"]), "target": int(e["target"])}
		elif e["type"] in ["combat_damage", "combat_end"]:
			reaction_attack.clear()
	var old := _snapshot()
	_leader_ko_t = -1.0
	_over_from = -1
	_render_now() # not _render: other batches may still be waiting, and this one must be drawn now
	var end := _animate(events, old)
	_animation_busy_until_ms = Time.get_ticks_msec() + int(end * 1000.0)
	_settle_timer.start(maxf(end, 0.05))
	# the Victory/Defeat screen waits for the killing blow to land instead of spoiling it
	if g.phase == "over" and _waiting_event_batches.is_empty():
		# same moment as the Victory/Defeat screen (the last batch only, so a queue of batches does not announce it early)
		var jingle_delay := maxf(_leader_ko_t + 0.7, end) if _leader_ko_t >= 0.0 else end
		Sfx.play_in(_match_end_sound(), jingle_delay)
		# the music dies away just as the jingle starts, so the jingle is heard on its own
		get_tree().create_timer(jingle_delay).timeout.connect(Music.fade_out.bind(1.5))
	if g.phase == "over" and _over_from >= 0 and end > 0.0:
		var delay := maxf(_leader_ko_t + 0.7, end) if _leader_ko_t >= 0.0 else end
		for n in layer.get_children().slice(_over_from):
			n.modulate.a = 0.0
			var otw: Tween = n.create_tween()
			otw.tween_interval(delay)
			otw.tween_property(n, "modulate:a", 1.0, 0.35)
	if not ai_timer.is_stopped():
		ai_timer.start(max(0.55, end + 0.2))

## The jingle for the end of the match: the fanfare for whoever won on this screen, the defeat sting for
## whoever lost (online each client gets its own), and a plain turn chime for a draw. Hot-seat is one
## device shared by both players, so it can only play one of them: the fanfare.
func _match_end_sound() -> String:
	if g.winner >= 2:
		return "turn_start"
	if online:
		return "victory" if g.winner == viewer else "defeat"
	if vs_ai:
		return "victory" if g.winner == 0 else "defeat"
	return "victory"

func _is_ai(p: int) -> bool:
	return vs_ai and p == 1


# ---------------------------------------------------------------- render

func _clear() -> void:
	# A state update can arrive while the full-screen card overlay is open (AI, online opponent,
	# animation batch...). Remove it before rebuilding the table, otherwise the old overlay survives
	# over the new layer for a frame and leaves duplicated/offset UI behind.
	_close_overlay()
	_close_decklist()
	join_slots = null
	_finish_unit_view_reuse()
	for unit_uid in _unit_board_views:
		var unit_view: CardView = _unit_board_views[unit_uid]
		if is_instance_valid(unit_view) and not unit_view.is_queued_for_deletion() \
			and is_instance_valid(layer) and unit_view.get_parent() == layer:
			# Preserve the node briefly; _render_board will keep it only if this unit stays in the same slot.
			layer.remove_child(unit_view)
			_unit_views_for_reuse[unit_uid] = unit_view
		elif is_instance_valid(unit_view) and not unit_view.is_queued_for_deletion():
			unit_view.queue_free()
	_unit_board_views.clear()
	if layer:
		layer.queue_free()
	_menu_screen_showing = false
	layer = Control.new()
	search_overlay = null
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	if fx:
		fx.move_to_front()
	if is_instance_valid(_fps_counter):
		_fps_counter.move_to_front()
	_chronicle_list_rect = Rect2()
	if chronicle_scene and chronicle_scene.visible:
		chronicle_scene.move_to_front()
		# if the next screen has no Chronicle (menu, game over...), the scene must not stay open
		call_deferred("_hide_chronicle_scene_without_list")
	views.clear()
	hand_uids.clear()

func _finish_unit_view_reuse() -> void:
	# Any old unit not found in the same board slot has moved or left the board; let its view go.
	for unit_uid in _unit_views_for_reuse:
		var unit_view: CardView = _unit_views_for_reuse[unit_uid]
		if is_instance_valid(unit_view):
			unit_view.queue_free()
	_unit_views_for_reuse.clear()

func _clear_fx() -> void:
	# a new screen or match: nothing from the previous one should still be waiting to play
	_waiting_event_batches.clear()
	_animation_busy_until_ms = 0
	_render_when_settled = false
	_queued_inputs.clear()
	reaction_attack.clear()
	reaction_arrow = null
	_pass_all_arming = false
	_pass_all_waiting_for_server = false
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
		_finish_unit_view_reuse()
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
	elif _is_ai(g.decider()) and ai_timer.is_stopped():
		ai_timer.start() # not while it is already counting: every redraw would push the AI's move back
	_finish_unit_view_reuse()

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
	lv.shows_deck_pile = false # both decks and graveyards sit by the right edge of the table (see _render_piles)
	lv.shows_graveyard = false
	lv.grave = pl["graveyard"].size()
	lv.poison = g.leader_dot_markers(p, "veneno")
	lv.ward_hits = g.leader_negations_left(p)
	lv.requiem = g.requiem_cards(p).size() if p == viewer and not _is_ai(p) and g.phase in ["main", "combat"] else 0
	lv.ability_ready = p == viewer and g.can_use_ability(p, true) and not _is_ai(p)
	# passives with a per-turn limit (Thálvaressa) show how many uses are spent; the engine wipes the count every turn start
	if CardDB.leader(pl["leader_id"])["ability"].has("max_per_turn"):
		lv.ability_uses = int(pl.get("passive_uses", 0))
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
	mb.setup(pl["momentum"], pl["max_momentum"], int(pl.get("reserve", 0)), g.momentum_cap(p))

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
	var l: Dictionary = g.players[p]["incarnation"]
	if p == viewer:
		var cap := _label("SANTUÁRIO", 13, Color(UITheme.GOLD, 0.7), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
		cap.position = pos + Vector2(-1, -20)
		cap.size = Vector2(SANCTUARY_W, 16)
		layer.add_child(cap)
	if not l["in_zone"]:
		var where := "EM CAMPO"
		if l.get("retired", false):
			where = "NO DECK"
		elif g.incarnation_in_hand(p):
			where = "NA MÃO"
		var empty := _label(where, 12, Color(UITheme.TEXT, 0.35), HORIZONTAL_ALIGNMENT_CENTER, "title", 2)
		empty.position = pos + Vector2(-1, 115)
		empty.size = Vector2(SANCTUARY_W, 20)
		layer.add_child(empty)
		return
	var v := CardView.new().setup(l["card_id"], _display_instance_for_id(l["card_id"], p), SANCTUARY_SCALE)
	v.pivot_offset = v.size / 2.0
	v.position = pos
	v.cost_override = g.incarnation_cost(p)
	v.text_suffix = _scale_suffix(p, CardDB.card(l["card_id"]))
	v.snowball_level = int(g.players[p]["snowball"])
	if p == viewer and g.can_cast_incarnation(p) and not _is_ai(p):
		v.highlight = OK
	if p == viewer and (targeting.get("kind") == "incarnation" or (targeting.get("kind") == "room_banish" and targeting["uid"] == 0)):
		v.highlight = SEL
	v.left_clicked.connect(func(_v): _on_incarnation(p))
	v.right_clicked.connect(_show_overlay)
	layer.add_child(v)
	views["cmd%d" % p] = v

## Builds the instance data used by every card outside the board. Persistent upgrades are stored on
## the player's shared state rather than on the printed card JSON, so this keeps Santuário, hand,
## search, stack and graveyard views honest about what that player currently owns.
func _display_instance_for_id(card_id: String, owner: int, uid := 0, base_instance: Dictionary = {}) -> Dictionary:
	var instance := base_instance.duplicate(true)
	if uid != 0:
		instance["uid"] = uid
	if g == null or owner < 0 or owner >= g.players.size() or card_id == "":
		return instance
	if not CardDB.data().get("cards", {}).has(card_id):
		return instance
	var cd := CardDB.card(card_id)
	if cd.get("critico_growth", false):
		var shared_critico := int(g.players[owner].get("critico_growth", {}).get(card_id, 0))
		if shared_critico > int(instance.get("critico", 0)):
			instance["critico"] = shared_critico
	return instance

func _display_instance_for_card(card: Card) -> Dictionary:
	if card == null:
		return {}
	return _display_instance_for_id(card.card_id, card.owner, card.uid, card.to_dict())

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
		# summoning sickness is only worth showing while it really keeps the unit from attacking
		unit_view_data["summoning_sick"] = unit.sick and not g.has_kw(unit, "impeto") and not g.has_kw(unit, "rompante")
		# Condicional uses already spent THIS turn (Seymour's "(0/2)"): the stored count belongs to the turn it was spent in
		if int(unit.data().get("conditional_uses_per_turn", 0)) > 0:
			unit_view_data["conditional_uses_now"] = unit.conditional_uses if unit.conditional_uses_turn == g.turn else 0
		var card_size := (CardView.BASE * 1.15).round()
		var cell := _board_cell(slots_taken, i)
		var card_position := Vector2(roundf(cell.x + (cell.y - card_size.x) / 2.0), roundf(y)) # whole pixels keep the card text crisp
		var card_rotation := 0.0
		var card_scale := Vector2.ONE
		# exhausted (tapped) units lie sideways: they already attacked or used an ability, and the
		# enemy can challenge them. Lying down, the card's height runs along the row, so it shrinks
		# toward its cell width — but never below TAPPED_MIN_SCALE: on a full row it just overlaps
		# the neighbours slightly, which looks more natural than a tiny card.
		if unit.exhausted:
			card_rotation = deg_to_rad(TAPPED_TILT_DEGREES)
			var fit_cell_scale := (cell.y - 6.0) / card_size.y
			card_scale = Vector2.ONE * clampf(fit_cell_scale, TAPPED_MIN_SCALE, 1.0)
			# Lying down, the card's width runs across the lane, so keeping its center would pull its front
			# edge BACK from the standing units. Instead we place that edge ahead of theirs, toward the divider.
			var lying_half_depth := card_size.x * card_scale.x / 2.0
			var standing_front_edge_y := y if p == viewer else y + card_size.y # the edge facing the divider
			var tapped_center_y: float
			if p == viewer:
				tapped_center_y = standing_front_edge_y - TAPPED_FRONT_ADVANCE + lying_half_depth
			else:
				tapped_center_y = standing_front_edge_y + TAPPED_FRONT_ADVANCE - lying_half_depth
			card_position.y = roundf(tapped_center_y - card_size.y / 2.0)
		var v: CardView = _unit_views_for_reuse.get(unit.uid)
		var reuse_view := is_instance_valid(v) and v.card_id == unit.card_id and v.size == card_size \
			and v.position.is_equal_approx(card_position) and is_equal_approx(v.rotation, card_rotation) \
			and v.scale.is_equal_approx(card_scale)
		if reuse_view:
			_unit_views_for_reuse.erase(unit.uid)
			v.update_card(unit.card_id, unit_view_data, 1.15)
		else:
			if is_instance_valid(v):
				v.queue_free()
			_unit_views_for_reuse.erase(unit.uid)
			v = CardView.new().setup(unit.card_id, unit_view_data, 1.15)
			v.left_clicked.connect(_on_unit_click)
			v.right_clicked.connect(_show_overlay)
			v.drag_started.connect(_unit_drag_start)
		v.pivot_offset = v.size / 2.0
		v.position = card_position
		v.rotation = card_rotation
		v.scale = card_scale
		_decorate_unit(v, unit, p)
		# on touch an attacker is also dragged to its target (on a mouse the press already starts the aim)
		v.draggable = CardView.touch_ui() and p == viewer and _my_input() and targeting.is_empty() \
			and g.combat_system().in_attacks_window(viewer)
		layer.add_child(v)
		views[unit.uid] = v
		_unit_board_views[unit.uid] = v
		var barrier_side: int = TableView.SIDE_MINE if p == viewer else TableView.SIDE_ENEMY
		var is_barring: bool = _slam_if_barricade_just_closed(unit, barrier_side, v.position.x + v.size.x / 2.0)
		if is_barring:
			# the opening is as wide as the tapped card lying down; it is the only way through the barrier
			barrier_gaps.append(Vector2(v.position.x + v.size.x / 2.0, v.size.y * v.scale.y + 6.0))
		if unit.is_frozen():
			_tag(v, "CONGELADA", ICE)
		if unit.is_stunned():
			_tag(v, "ATORDOADA", CardView.STUN_COL)
		if unit.equipment != null:
			# the equipment card sits under its unit, peeking out toward the middle of the table
			var eq := CardView.new().setup(unit.equipment.card_id, {"uid": unit.equipment.uid}, 1.15)
			# anchored to the unit's resting slot, so a tapped unit stepping forward does not drag it along
			eq.position = Vector2(v.position.x, roundf(y)) + Vector2(8, 22 if p == viewer else -22)
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
	var barring_now: bool = unit.exhausted and g.has_kw(unit, "provocacao") and not unit.is_frozen() and not unit.is_stunned()
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
		var relic_view_data := {"uid": relic.uid}
		if relic.charges_left() >= 0:
			relic_view_data["charges_left"] = relic.charges_left() # a limited-use artifact shows its remaining uses
		if relic.data().has("momentum_store"):
			relic_view_data["stored_momentum"] = relic.stored_momentum # Bateria de Segunda Mão shows how much it holds
		# Baluarte Santo is born protected: it needs the golden ring too (and loses ring and tag once it breaks)
		relic_view_data["supreme_shield"] = relic.supreme_shield
		var v := CardView.new().setup(relic.card_id, relic_view_data, 1.15)
		v.pivot_offset = v.size / 2.0
		var cell := _board_cell(slots_taken, first_relic_slot + j)
		v.position = Vector2(cell.x + (cell.y - v.size.x) / 2.0, y)
		v.ability_ready = p == viewer and targeting.is_empty() and _my_input() and g.can_activate(viewer, relic.uid, true)
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

## Slots frozen by Rei Gelado: tiles at the end of the lane covered in the same ice as a frozen unit
## (FrozenSlotView). Nothing can be played into them.
func _render_frozen_slots(p: int, y: float, slots_taken: int) -> void:
	var frozen_count: int = int(g.players[p]["frozen_slots"])
	var first_frozen_slot: int = g.slots_used(p)
	for j in frozen_count:
		var tile := FrozenSlotView.new()
		tile.owner_player = p
		tile.size = CardView.BASE * 1.15
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
	v.ability_ready = p == viewer and targeting.is_empty() and _my_input() and (g.can_activate(viewer, unit.uid, true) or g.can_transform(viewer, unit.uid))
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
		var v := CardView.new().setup(hand_card.card_id, _display_instance_for_card(hand_card), sc)
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
		elif targeting.get("uid", 0) == hand_card.uid and targeting.get("kind") in ["hand", "room_banish"]:
			pos.y -= rise + 20.0
			v.highlight = SEL
		elif g.phase in ["main", "combat"] and g.can_play(p, hand_card.uid, true) and not _is_ai(p):
			v.highlight = OK
		v.position = pos
		v.rotation = rot
		v.left_clicked.connect(_on_hand_click)
		v.right_clicked.connect(_show_overlay)
		v.draggable = p == viewer and g.phase in ["main", "combat"] and targeting.is_empty() and _my_input() and g.can_play(p, hand_card.uid, true)
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
		# the table may have been redrawn while the cursor was on the card: an old card is no longer in the layer
		if v.get_parent() == layer:
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

const CHRONICLE_PANEL_HEIGHT := 300.0
const CHRONICLE_LIST_TOP := 40.0 ## below the title, inside the panel
const CHRONICLE_ROWS_KEPT := 80

## The Chronicle: a scrolling list of event rows, newest at the bottom. Turns are separated by thin
## dividers. Pointing at (or tapping) a row opens the big ChronicleScene beside the column.
func _render_chronicle() -> void:
	var chronicle_panel := Panel.new()
	chronicle_panel.position = Vector2(col_x, 14)
	chronicle_panel.size = Vector2(COL_W, CHRONICLE_PANEL_HEIGHT)
	chronicle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := UITheme.box(Color(0.035, 0.03, 0.055, 0.92), 10, Color(UITheme.GOLD, 0.45), 1, 12)
	chronicle_panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(chronicle_panel)
	var title := _label("CRÔNICA", 15, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	title.position = Vector2(0, 7)
	title.size = Vector2(COL_W, 20)
	chronicle_panel.add_child(title)
	chronicle_panel.add_child(_ornament(Vector2(COL_W / 2.0, 31), 92))

	# the list sits in a darker well, so the rows read as one block
	var list_size := Vector2(COL_W - 12, CHRONICLE_PANEL_HEIGHT - CHRONICLE_LIST_TOP - 6)
	var well := Panel.new()
	well.position = Vector2(6, CHRONICLE_LIST_TOP)
	well.size = list_size
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", UITheme.box(Color(0, 0, 0, 0.35), 6))
	chronicle_panel.add_child(well)
	var scroll := ScrollContainer.new()
	scroll.position = well.position
	scroll.size = list_size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_thin_scrollbar(scroll.get_v_scroll_bar())
	chronicle_panel.add_child(scroll)
	var rows_box := VBoxContainer.new()
	rows_box.custom_minimum_size = Vector2(list_size.x - 6, 0)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override("separation", 2)
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(rows_box)
	_chronicle_rows_box = rows_box
	_chronicle_list_rect = Rect2(chronicle_panel.position + scroll.position, list_size)

	var shown: Array = chronicle_entries
	if shown.is_empty() and not log_lines.is_empty():
		shown = [{"text": log_lines[-1], "kind": "info", "icon": "·", "accent": UITheme.GOLD, "label": "EVENTO", "seq": 0}]
	if shown.is_empty():
		var empty_note := _label("Nada aconteceu ainda.", 14, Color(UITheme.TEXT, 0.4), HORIZONTAL_ALIGNMENT_CENTER, "body")
		empty_note.position = well.position + Vector2(0, list_size.y / 2.0 - 10)
		empty_note.size = Vector2(list_size.x, 20)
		chronicle_panel.add_child(empty_note)
	var open_seq: int = chronicle_scene.shown_seq() if chronicle_scene else -1
	var newest_seq := _chronicle_seen_seq
	for raw: Dictionary in shown.slice(maxi(0, shown.size() - CHRONICLE_ROWS_KEPT)):
		var seq := int(raw.get("seq", 0))
		var row := ChronicleRowScript.new().setup(raw, _chronicle_is_ally(raw), seq == open_seq, seq > _chronicle_seen_seq)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.focused.connect(_show_chronicle_scene)
		rows_box.add_child(row)
		newest_seq = maxi(newest_seq, seq)
	_chronicle_seen_seq = newest_seq
	scroll.call_deferred("set", "scroll_vertical", 999999)

	# the oldest rows fade out under the top edge of the list instead of being cut flat
	var top_fade := Control.new()
	top_fade.position = well.position
	top_fade.size = Vector2(list_size.x, 16)
	top_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_fade.draw.connect(func():
		for line in 16:
			top_fade.draw_line(Vector2(0, line + 0.5), Vector2(list_size.x, line + 0.5), Color(0.035, 0.03, 0.055, 0.9 * (1.0 - line / 16.0)), 1.0))
	chronicle_panel.add_child(top_fade)

## A slim gold scrollbar, so the list doesn't lose width to a chunky default one.
func _style_thin_scrollbar(bar: ScrollBar) -> void:
	var track := UITheme.box(Color(1, 1, 1, 0.04), 3)
	track.content_margin_left = 2
	track.content_margin_right = 2
	var grabber := UITheme.box(Color(UITheme.GOLD, 0.45), 3)
	var grabber_hover := UITheme.box(Color(UITheme.GOLD, 0.8), 3)
	bar.custom_minimum_size.x = 6
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", grabber_hover)
	bar.add_theme_stylebox_override("grabber_pressed", grabber_hover)

## True when the entry was done by the player looking at the screen.
func _chronicle_is_ally(chronicle_entry: Dictionary) -> bool:
	return int(chronicle_entry.get("actor", -1)) == viewer

## Opens (or moves) the big scene beside the Chronicle column for the row being pointed at.
func _show_chronicle_scene(row: ChronicleRow) -> void:
	if chronicle_scene == null:
		chronicle_scene = ChronicleSceneScript.new()
		add_child(chronicle_scene)
	var previous_seq := chronicle_scene.shown_seq()
	var top_left := Vector2(col_x - 18.0 - ChronicleScene.PANEL_SIZE.x, 14.0)
	var row_center_y := (get_global_transform().affine_inverse() * row.get_global_rect().get_center()).y
	chronicle_scene.show_entry(row.entry, row.is_ally, top_left, row_center_y)
	# only one row looks "open" at a time
	for sibling in row.get_parent().get_children():
		if sibling is ChronicleRow:
			sibling.set_active(sibling == row)
	if previous_seq != chronicle_scene.shown_seq():
		row.queue_redraw()

func _hide_chronicle_scene() -> void:
	if chronicle_scene == null or not chronicle_scene.visible:
		return
	chronicle_scene.hide_scene()
	if is_instance_valid(_chronicle_rows_box):
		for row in _chronicle_rows_box.get_children():
			row.set_active(false)

## Called after a redraw: the scene closes when the new screen has no Chronicle list.
func _hide_chronicle_scene_without_list() -> void:
	if _chronicle_list_rect.size == Vector2.ZERO:
		_hide_chronicle_scene()

func _render_side() -> void:
	_render_chronicle()

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
	var sound_button := _sound_icon_button(36.0)
	sound_button.position = Vector2(COL_W - 40.0, 4.0)
	tp.add_child(sound_button)

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
		y += 66.0
	if _pass_all_switch_available():
		var pass_all := _pass_all_switch()
		pass_all.position = Vector2(col_x, y)
		pass_all.size = Vector2(COL_W, 48)
		layer.add_child(pass_all)
	_render_piles(viewer)
	_render_piles(1 - viewer)
	_render_stack()
	var ap_on := _auto_pass_on()
	var ap := _toggle_button("AUTO-PASSE", ap_on, func(): _set_auto_pass(not _auto_pass_on()))
	ap.position = Vector2(col_x, 772.0 + BOT)
	ap.size = Vector2(COL_W, 48)
	ap.tooltip_text = "Pula sozinho as janelas em que você não tem nenhuma jogada válida."
	layer.add_child(ap)
	var half := (COL_W - 8.0) / 2.0
	# during the match "Menu" opens the pause menu (settings, concede, leave); once it is over there is nothing left to pause
	var menu := _button("Menu", _show_menu if g.phase == "over" else _open_pause_menu)
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

## Each player's deck and graveyard sit side by side, like the two piles of a real TCG table, far
## enough from the hand that a drawn card is seen leaving the deck and travelling to it.
## The viewer's piles are in the HUD column, just above AUTO-PASSE. The opponent's mirror them at the
## top, right beside the Chronicle (the column itself is taken there): graveyard first, then the deck
## nearest the column, so both decks are on the same side of the screen.
const PILE_CARD_SCALE := 0.7
const PILE_GAP := 24.0 ## space between a deck and its graveyard
const VIEWER_PILE_GAP_ABOVE_AUTO_PASS := 22.0 ## room for the count badges under the viewer's piles
const OPPONENT_PILE_TOP := 16.0 ## the opponent's piles fit between the top of the screen and their board
const OPPONENT_PILE_GAP_BEFORE_COLUMN := 18.0

func _render_piles(player: int) -> void:
	var card_size := CardView.BASE * PILE_CARD_SCALE
	var deck_position: Vector2
	var graveyard_position: Vector2
	if player == viewer:
		var piles_left := col_x + (COL_W - card_size.x * 2.0 - PILE_GAP) / 2.0
		var piles_top := 772.0 + BOT - VIEWER_PILE_GAP_ABOVE_AUTO_PASS - card_size.y
		deck_position = Vector2(piles_left, piles_top)
		graveyard_position = Vector2(piles_left + card_size.x + PILE_GAP, piles_top)
	else:
		deck_position = Vector2(col_x - OPPONENT_PILE_GAP_BEFORE_COLUMN - card_size.x, OPPONENT_PILE_TOP)
		graveyard_position = deck_position - Vector2(card_size.x + PILE_GAP, 0)
	var deck_pile := LeaderView.DeckPile.new()
	deck_pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deck_pile.card_scale = PILE_CARD_SCALE
	deck_pile.base_top_left = Vector2.ZERO
	deck_pile.position = deck_position
	layer.add_child(deck_pile)
	deck_pile.show_count(g.players[player]["deck"].size(), g.fatigue_next(player))
	deck_piles[player] = deck_pile
	var graveyard: Array = g.players[player]["graveyard"]
	var top_card_id := ""
	var top_instance := {}
	if not graveyard.is_empty():
		var top_card: Card = graveyard.back()
		top_card_id = top_card.card_id
		top_instance = _display_instance_for_id(top_card_id, player, top_card.uid)
	# only the viewer can cast Réquiem spells from their own graveyard: no green glow on the opponent's
	var castable_requiem: int = _requiem_uids(viewer).size() if player == viewer else 0
	var graveyard_pile := GraveyardPile.new().setup(graveyard.size(), top_card_id, top_instance, castable_requiem, PILE_CARD_SCALE)
	graveyard_pile.position = graveyard_position
	graveyard_pile.clicked.connect(func(): _show_graveyard(player))
	layer.add_child(graveyard_pile)
	graveyard_piles[player] = graveyard_pile

## Where `player`'s graveyard is on the stage: milled cards land there, Réquiem spells rise from it.
func _graveyard_pose(player: int) -> Dictionary:
	var graveyard_pile = graveyard_piles.get(player)
	if is_instance_valid(graveyard_pile):
		return {"c": graveyard_pile.position + graveyard_pile.top_center(), "rot": 0.0, "w": graveyard_pile.card_size_on_screen().x}
	var leader_view = views.get(GameState.LEADER_UID[player])
	if leader_view is LeaderView:
		return {"c": leader_view.position + LeaderView.GRAVE_CENTER, "rot": 0.0, "w": LeaderView.deck_card_width() * 0.6}
	return {"c": Vector2(lane_cx, LEADER_Y_ME if player == viewer else 30.0), "rot": 0.0, "w": LeaderView.deck_card_width() * 0.6}

## Where the top card of `player`'s deck is on the stage, and how wide it is there:
## cards drawn, milled or summoned from the deck start their flight from this pose.
func _deck_top_pose(player: int) -> Dictionary:
	var deck_size: int = g.players[player]["deck"].size()
	var deck_pile = deck_piles.get(player)
	if is_instance_valid(deck_pile):
		return {"c": deck_pile.position + deck_pile.top_center(deck_size), "rot": 0.0, "w": deck_pile.card_width()}
	var leader_view = views.get(GameState.LEADER_UID[player])
	if leader_view is LeaderView:
		return {"c": leader_view.position + LeaderView.deck_top_center(deck_size), "rot": 0.0, "w": LeaderView.deck_card_width()}
	return {"c": Vector2(lane_cx, LEADER_Y_ME if player == viewer else 30.0), "rot": 0.0, "w": LeaderView.deck_card_width()}

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
			var stack_owner := int(it.get("player", 0))
			var stack_card_id := String(it["card_id"])
			var v := CardView.new().setup(stack_card_id, _display_instance_for_id(stack_card_id, stack_owner, int(it.get("uid", 0))), STACK_SCALE)
			v.snowball_level = int(g.players[stack_owner]["snowball"])
			v.text_suffix = _scale_suffix(stack_owner, CardDB.card(stack_card_id))
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

func _process(dt: float) -> void:
	CardView.load_queued_arts()
	_update_aim()
	_sync_reaction_arrow()
	if _fps_counter_visible and is_instance_valid(_fps_counter):
		_fps_sample_seconds += dt
		_fps_sample_frames += 1
		if _fps_sample_seconds >= 0.5:
			_fps_counter.text = "FPS %d" % roundi(_fps_sample_frames / _fps_sample_seconds)
			_fps_sample_seconds = 0.0
			_fps_sample_frames = 0
	if g and Time.get_ticks_msec() - last_input_ms > 15000:
		last_input_ms = Time.get_ticks_msec()
		_hint_nudge()

func _hint() -> String:
	if g.phase == "search":
		if g.pending_search.get("summon_from", false):
			return "Escolha uma carta para invocar de graça, ou não invoque nenhuma."
		if g.pending_search.get("hand_summon", false):
			return "Escolha um campeão da sua mão para entrar em campo de graça."
		if g.pending_search.get("grave_optional", false):
			return "Rebobinar: escolha uma carta do cemitério para levar à mão, ou não pegue nenhuma."
		return "Escolha uma carta da sua mão para descartar." if g.pending_search.get("discard_hand", false) else "Escolha uma das cartas reveladas."
	if targeting.get("kind") == "enter":
		var which := "segundo alvo" if g.pending_enter.has("first") else "alvo"
		return "Ao Entrar de %s: toque no %s ou pule o efeito." % [_cname(g.pending_enter.get("card_id", "")), which]
	if targeting.get("kind") == "room_banish":
		var banish_prompt := "Campo cheio: toque na unidade ou artefato seu que será banido para abrir espaço" if CardView.touch_ui() \
			else "Campo cheio: clique na unidade ou artefato seu que será banido para abrir espaço"
		return banish_prompt + " · toque fora cancela." if CardView.touch_ui() else banish_prompt + " · botão direito/Esc cancela."
	if targeting.get("kind") == "attack":
		# say why some targets don't glow: a Provocação forces the challenge, and a unit that
		# just came in with Ímpeto can only challenge
		var attacker := g.find_unit(targeting["uid"])
		var taunts: Array = g.combat_system().forced_taunts(attacker) if attacker != null else []
		if not taunts.is_empty():
			var taunt_names: Array = []
			for taunt_uid in taunts:
				taunt_names.append(_cname(g.find_unit(taunt_uid).card_id))
			return "Provocação: este ataque precisa desafiar %s." % " ou ".join(taunt_names)
		if attacker != null and g.combat_system().is_rompante_rush(attacker):
			return "Rompante: no turno em que entra, ela pode atacar o Líder (só uma Provocação a segura)."
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
	if g.phase in ["main", "combat"] and g.skip_rest_of_turn[viewer] and g.active != viewer and not g.stack.is_empty():
		return "PASSAR TUDO está ligado, mas esta jogada mataria o seu Líder: responda com um Instantâneo ou passe."
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
					if viewer == g.active and g.combat_system().is_reacting(g.opponent(viewer)):
						return "Ataque declarado: o oponente pode reagir antes do dano..."
					if viewer == g.active:
						return "Arraste uma unidade até o alvo para atacar (ou jogue um Instantâneo) · ENCERRAR COMBATE quando acabar."
					if g.combat_system().is_reacting(viewer):
						return "Reagir? Jogue uma Instantânea antes do dano ou passe."
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

## The "PASSAR TUDO" switch only exists during the opponent's turn: on your own turn there is nothing to pass.
func _pass_all_switch_available() -> bool:
	return g.phase in ["main", "combat"] and g.active != viewer and not _is_ai(viewer)

## "PASSAR TUDO": from the opponent's next play on, you are not asked for responses until their turn ends.
## It shows what the server confirmed, "DESFAZER" during the local undo window and "…" while waiting for the server.
func _pass_all_switch() -> Button:
	var is_on: bool = g.skip_rest_of_turn[viewer]
	var title := "PASSAR TUDO"
	if _pass_all_arming:
		title = "DESFAZER"
		is_on = true
	elif _pass_all_waiting_for_server and is_on != _pass_all_expected_state:
		title = "…"
	var button := _toggle_button(title, is_on, _on_pass_all_pressed)
	button.tooltip_text = "Não pergunta mais por respostas até o turno do oponente acabar. Vale a partir da próxima jogada dele; só avisa se ela for matar o seu Líder."
	return button

func _on_pass_all_pressed() -> void:
	if _pass_all_arming: # still inside the undo window: take it back here, nothing was sent
		_pass_all_arming = false
		_render()
		return
	if _pass_all_waiting_for_server:
		return # the server has not answered the last press yet
	if g.skip_rest_of_turn[viewer]:
		_send_pass_all(false)
		return
	_pass_all_arming = true
	_pass_all_arming_id += 1
	var arming_id := _pass_all_arming_id
	get_tree().create_timer(PASS_ALL_UNDO_SECONDS).timeout.connect(func():
		if _pass_all_arming and arming_id == _pass_all_arming_id:
			_pass_all_arming = false
			_send_pass_all(true))
	_render()

## Sends the switch to the engine (or the server). Online, the switch keeps showing "…" until the snapshot echoes it.
func _send_pass_all(on: bool) -> void:
	if g == null or g.phase not in ["main", "combat"] or (on and g.active == viewer):
		_render() # the turn changed while the press was waiting: nothing to switch any more
		return
	if g is RemoteState:
		_pass_all_waiting_for_server = true
		_pass_all_expected_state = on
		get_tree().create_timer(PASS_ALL_SERVER_TIMEOUT_SECONDS).timeout.connect(_stop_waiting_for_pass_all)
	_run_or_queue_input(func(): _do(g.pass_rest_of_turn(viewer) if on else g.cancel_pass_rest_of_turn(viewer)))
	_render()

## The server never answered (or refused): the switch goes back to showing the real state.
func _stop_waiting_for_pass_all() -> void:
	if _pass_all_waiting_for_server:
		_pass_all_waiting_for_server = false
		if g != null:
			_render()

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
		"main":
			if not g.stack.is_empty() or g.summon_window:
				out.append(_action_button(_pass_button_label(), func(): _do(g.pass_priority(viewer)), true))
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
	# A draw is neither gold (victory) nor red (defeat): a calm silver, with the same size and glow
	var is_draw := g.winner == 2
	var title_color := UITheme.GOLD_LIGHT if won else Color("#e0a8a0")
	var glow_color := UITheme.GOLD if won else UITheme.HP
	if is_draw:
		title_color = Color("#dfe3ec")
		glow_color = Color("#9aa3b8")
	var big := _label(txt, 64 if txt.length() < 10 else 44, title_color, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 10)
	big.add_theme_color_override("font_shadow_color", Color(glow_color, 0.35))
	big.add_theme_constant_override("shadow_outline_size", 24)
	big.add_theme_constant_override("shadow_offset_x", 0)
	big.add_theme_constant_override("shadow_offset_y", 0)
	box.add_child(big)
	if g.winner < 2:
		var sub := "%s triunfa na arena" % CardDB.leader(g.players[g.winner]["leader_id"])["name"]
		if conceded >= 0:
			sub = "%s desistiu da partida" % ("Você" if (vs_ai and conceded == 0) else _pname(conceded))
		box.add_child(_label(sub, 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	else:
		box.add_child(_label("Os dois Líderes caíram juntos", 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
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

func _toggle_fps_counter() -> void:
	_fps_counter_visible = not _fps_counter_visible
	if not is_instance_valid(_fps_counter):
		_fps_counter = _label("FPS 0", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "bold", 4)
		_fps_counter.position = Vector2(14, 12)
		_fps_counter.size = Vector2(150, 32)
		_fps_counter.z_index = 1000
		add_child(_fps_counter)
	_fps_sample_seconds = 0.0
	_fps_sample_frames = 0
	_fps_counter.visible = _fps_counter_visible
	_fps_counter.move_to_front()

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3:
		_toggle_fps_counter()
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	# here (not in _unhandled_input) so a button that kept the focus from a click does not swallow Space / Enter
	if e is InputEventKey and e.pressed and not e.echo:
		var key_used := false
		if join_slots != null:
			key_used = _join_screen_key(e)
		elif e.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			key_used = _press_main_action_with_keyboard()
		if key_used:
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
	# the Chronicle scene stays open while the pointer is on the list; moving or tapping elsewhere closes it
	if chronicle_scene and chronicle_scene.visible and (e is InputEventMouseMotion or (e is InputEventMouseButton and e.pressed)):
		if not _chronicle_list_rect.has_point(get_local_mouse_position()):
			_hide_chronicle_scene()
	if grave_view and _grave_scroll_input(e):
		get_viewport().set_input_as_handled()
	elif decklist_view == null and is_instance_valid(hub_scroll) and _hub_scroll_input(e): # the deck list scrolls itself
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
	if _warn_unreachable(_card_uid_at(gp)):
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
	if decklist_view and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if overlay:
			_close_overlay() # Esc peels off the topmost window first: the card, then the list
		else:
			_close_decklist()
		return
	if grave_view and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_close_graveyard()
		return
	if concede_view and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_close_concede() # Esc backs out of the pause menu and of the confirmations
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
	if targeting.get("kind") in ["hand", "room_banish"] and targeting["uid"] == v.uid:
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
	if not g.can_play(viewer, v.uid, true):
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
	elif _needs_room_banish(v.card_id):
		_begin_room_banish(v.uid, v.card_id, slot)
	else:
		_do(g.play_card(viewer, v.uid, 0, 0, slot))

## True when playing this card takes a field slot and the field is full: the player must banish one of
## their own permanents to make room.
func _needs_room_banish(card_id: String) -> bool:
	if g.has_free_slot(viewer):
		return false
	var card_data := CardDB.card(card_id)
	return g.takes_field_slot(card_data, g.is_subito_play(viewer, card_data))

## Opens the "which permanent do you banish to make room?" pick. hand_uid is 0 for the Encarnação.
## target / target2 are the picks already made for the card's own effect (0 if it has none).
func _begin_room_banish(hand_uid: int, card_id: String, slot := -1, target := 0, target2 := 0) -> void:
	targeting = {"kind": "room_banish", "uid": hand_uid, "card_id": card_id, "spec": "room_banish",
		"slot": slot, "target": target, "target2": target2}
	var source_view = views.get(hand_uid) if hand_uid != 0 else views.get("cmd%d" % viewer)
	_begin_aim(_visual_rect(source_view).get_center() if is_instance_valid(source_view) else Vector2.ZERO)
	_render()

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
	if spec != "" and (not g.card_targets(viewer, cd).is_empty() or g.targets_blocked_by_reach(viewer, spec)):
		return spec # blocked only by Inalcançável: aim anyway, aiming at that unit explains the refusal
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
	if targeting["kind"] in ["hand", "enter", "attack", "room_banish"] and views.has(targeting["uid"]) and is_instance_valid(views[targeting["uid"]]):
		var r: Rect2 = _visual_rect(views[targeting["uid"]] as Control)
		src = Vector2(r.get_center().x, r.position.y + r.size.y * 0.3)
	var inv := fx.get_global_transform().affine_inverse()
	var gp := get_global_mouse_position()
	aim_arrow.from = inv * src
	aim_arrow.to = inv * gp
	aim_arrow.locked = _target_at(gp) != 0

## Keep the existing dashed targeting-arrow style on the declared target while its reaction is pending.
func _sync_reaction_arrow() -> void:
	if reaction_attack.is_empty() or fx == null:
		if is_instance_valid(reaction_arrow):
			reaction_arrow.visible = false
		return
	var source: Variant = views.get(int(reaction_attack["attacker"]))
	var target: Variant = views.get(int(reaction_attack["target"]))
	if not is_instance_valid(source) or not source is Control or not is_instance_valid(target) or not target is Control:
		if is_instance_valid(reaction_arrow):
			reaction_arrow.visible = false
		return
	if not is_instance_valid(reaction_arrow):
		reaction_arrow = AimArrow.new()
		fx.add_child(reaction_arrow)
	reaction_arrow.visible = true
	reaction_arrow.move_to_front()
	var source_rect := _visual_rect(source)
	var target_rect := _visual_rect(target)
	var inv := fx.get_global_transform().affine_inverse()
	reaction_arrow.from = inv * Vector2(source_rect.get_center().x, source_rect.position.y + source_rect.size.y * 0.3)
	reaction_arrow.to = inv * target_rect.get_center()
	reaction_arrow.locked = true

func _toggle_pick(uid: int, cap: int) -> void:
	if picked.has(uid):
		picked.erase(uid)
	elif picked.size() < cap:
		picked.append(uid)
	_render()

func _on_incarnation(p: int) -> void:
	if p != viewer or not _my_input():
		return
	if _wait_for_table(_on_incarnation.bind(p)):
		return
	if not g.can_cast_incarnation(p):
		return
	if not g.has_free_slot(p):
		_begin_room_banish(0, g.players[p]["incarnation"]["card_id"])
		return
	_do(g.cast_incarnation(p)) # its Ao Entrar target (if any) is picked once it is on the board

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
	if not g.can_use_ability(p, true):
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
	if targeting["kind"] == "room_banish":
		return g.room_banish_options(viewer).has(uid)
	if targeting["kind"] == "attack":
		var attacker := g.find_unit(targeting["uid"])
		return attacker != null and g.attack_targets(attacker).has(uid)
	if targeting.has("first") and uid == targeting["first"] and not CardDB.card(targeting["card_id"]).get("same_target_ok", false):
		return false # the sacrificed unit is already gone
	return g.valid_targets(viewer, targeting["spec"], targeting.get("uid", 0), false, _aimed_effects()).has(uid)

## The effects the current aim is choosing a target for, so targets that cannot satisfy their
## "requires_markers" (Ponto Final Sem Vírgula) are not highlighted nor accepted.
func _aimed_effects() -> Array:
	match targeting["kind"]:
		"hand", "enter":
			return CardDB.card(targeting["card_id"]).get("effects", [])
		"ability":
			return CardDB.leader(g.players[viewer]["leader_id"])["ability"]["effects"]
		"unit_ability":
			var activator := g.find_unit(targeting["uid"])
			if activator == null:
				activator = g.find_relic(targeting["uid"])
			if activator != null:
				return g.card_of(activator).get("activated", {}).get("effects", [])
	return []

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
			elif _needs_room_banish(targeting["card_id"]):
				# the card's own target is chosen; the permanent to banish is the last pick
				var first_pick: int = targeting["first"] if targeting.has("first") else uid
				var second_pick: int = uid if targeting.has("first") else 0
				_begin_room_banish(targeting["uid"], targeting["card_id"], targeting.get("slot", -1), first_pick, second_pick)
			elif targeting.has("first"):
				_do(g.play_card(viewer, targeting["uid"], targeting["first"], uid))
			else:
				_do(g.play_card(viewer, targeting["uid"], uid, 0, targeting.get("slot", -1)))
		"room_banish":
			var hand_uid: int = targeting["uid"]
			var slot: int = targeting.get("slot", -1)
			if hand_uid == 0:
				_do(g.cast_incarnation(viewer, 0, slot, uid))
			else:
				_do(g.play_card(viewer, hand_uid, targeting["target"], targeting["target2"], slot, uid))
		"incarnation":
			_do(g.cast_incarnation(viewer, uid))
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
		return _warn_unreachable(v.uid) # explained; the aim stays open
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

## Aiming an effect at an enemy unit with Inalcançável: says why it is refused (true), the aim stays open.
func _warn_unreachable(uid: int) -> bool:
	if targeting.is_empty() or targeting["kind"] == "attack" or _is_target(uid):
		return false
	var unit := g.find_unit(uid)
	if unit == null or unit.owner == viewer or not g.has_kw(unit, "inalcancavel"):
		return false
	_toast("Inalcançável: essa unidade não pode ser alvo.")
	return true

## card_id of the Provocação waiting for the "enter exhausted?" choice ("" if none).
func _pending_tap_card_id() -> String:
	if g.pending_tap.is_empty():
		return ""
	var unit := g.find_unit(int(g.pending_tap[0]))
	return unit.card_id if unit != null else ""

# ---------------------------------------------------------------- overlay

## " (agora: N)" for cards whose text counts something (Jeff: unit cards in the own graveyard), so the
## player can add it to the base stats; " (N/M)" for the Gigantes. Empty for the rest.
func _scale_suffix(p: int, cd: Dictionary) -> String:
	var progress := g.window_progress(p, cd)
	if not progress.is_empty():
		# cost reductions that ask for an amount over a window (Gigantes): how far along, e.g. "(3/8)"
		return " (%d/%d)" % [progress["have"], progress["need"]]
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
	_add_base_card_button(v.card_id)
	_add_full_art_button(String(cd.get("art", "")))
	if cd.has("activated") and g != null and _my_input() and g.can_activate(viewer, v.uid, true):
		var ab: Dictionary = cd["activated"]
		var ab_uid := v.uid
		var ab_btn := _button("Ativar (%d)" % int(ab["cost"]), func():
			_close_overlay()
			# during an animation the activation waits for it to end (and checks again that it is still allowed)
			_run_or_queue_input(func():
				if not _my_input() or not g.can_activate(viewer, ab_uid, true):
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

## An eye button above the big card in the overlay: while it is held, the card and its text are shown as
## printed (no buffs, debuffs, markers or resets); letting go brings the live card back.
func _add_base_card_button(card_id: String) -> void:
	# call right after CardOverlay.build: the text panel is the overlay's last child at this point
	var text_panel := overlay.get_child(overlay.get_child_count() - 1) as RichTextLabel
	var live_text := text_panel.text
	var printed_text := CardOverlay.describe(card_id, {}, -1, "", GameState.SNOWBALL_BASE_LEVEL)
	var base_card := CardOverlay.build_base_card(overlay, stage_w, card_id)
	var button_size := Vector2(CardView.BASE.x * CardOverlay.BIG_CARD_SCALE, 84.0)
	var button := Button.new()
	button.custom_minimum_size = button_size
	button.size = button_size
	button.position = Vector2(CardOverlay.big_card_position(stage_w).x, CardOverlay.BIG_CARD_Y - button_size.y - 16.0)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Segure para ver a carta como foi impressa."
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(56.0, button_size.y / 2.0)
	icon.draw.connect(func():
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
		icon.draw_circle(Vector2.ZERO, 8.0, UITheme.GOLD_LIGHT))
	button.add_child(icon)
	var caption := _label("Segure: ver carta base", 26, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "bold")
	caption.position = Vector2(104.0, 0.0)
	caption.size = Vector2(button_size.x - 120.0, button_size.y)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(caption)
	button.button_down.connect(func():
		base_card.visible = true
		text_panel.text = printed_text)
	button.button_up.connect(func():
		base_card.visible = false
		text_panel.text = live_text)
	overlay.add_child(button)

## A picture-icon button next to the "ver carta base" one: opens the card's art alone, full screen.
func _add_full_art_button(art_file: String) -> void:
	if art_file == "":
		return
	var button_size := Vector2(84.0, 84.0)
	var button := Button.new()
	button.custom_minimum_size = button_size
	button.size = button_size
	button.position = Vector2(CardOverlay.big_card_position(stage_w).x + CardView.BASE.x * CardOverlay.BIG_CARD_SCALE + 28.0,
			CardOverlay.BIG_CARD_Y - button_size.y - 16.0)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Ver a arte em tela cheia."
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = button_size / 2.0
	icon.draw.connect(func():
		# the universal "image" icon: a frame holding a sun and two mountains
		icon.draw_rect(Rect2(-28.0, -22.0, 56.0, 44.0), UITheme.GOLD_LIGHT, false, 3.0)
		icon.draw_circle(Vector2(-12.0, -8.0), 5.0, UITheme.GOLD_LIGHT)
		icon.draw_colored_polygon(PackedVector2Array([Vector2(-26.0, 20.0), Vector2(-6.0, -2.0), Vector2(6.0, 10.0),
				Vector2(14.0, 2.0), Vector2(26.0, 20.0)]), UITheme.GOLD_LIGHT))
	button.add_child(icon)
	button.pressed.connect(func(): _show_full_art(art_file))
	overlay.add_child(button)

## The raw art on a black screen covering the whole window (not just the stage), fitted whole with no crop,
## frame, badges or seals. A click, a tap or Esc closes it and goes back to the card overlay.
func _show_full_art(art_file: String) -> void:
	var viewer := ColorRect.new()
	viewer.color = Color.BLACK
	var window_size := get_viewport().get_visible_rect().size
	viewer.position = -position # Main sits centered inside the window; this puts the viewer at the window's corner
	viewer.size = window_size
	viewer.focus_mode = Control.FOCUS_ALL
	viewer.gui_input.connect(func(e):
		var clicked: bool = e is InputEventMouseButton and e.pressed
		var escaped: bool = e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE
		if clicked or escaped:
			viewer.accept_event()
			viewer.queue_free())
	var art := TextureRect.new()
	art.texture = CardView.raw_art_texture(art_file)
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewer.add_child(art)
	overlay.add_child(viewer)
	viewer.grab_focus()

func _close_overlay() -> void:
	if overlay == null:
		return
	var old_overlay := overlay
	overlay = null
	# Detach immediately; queue_free alone keeps the modal in the scene tree until the end of the
	# frame, which is exactly the visual glitch seen when a render happens during the overlay.
	if is_instance_valid(old_overlay) and old_overlay.get_parent() != null:
		old_overlay.get_parent().remove_child(old_overlay)
	old_overlay.queue_free()

# ---------------------------------------------------------------- concede

## Confirmation before giving up; a persistent child of Main so re-renders (AI/opponent moves) don't dismiss it.
func _ask_concede() -> void:
	_ask_confirm("CONCEDER A PARTIDA?", "O oponente vence na hora.", "CONCEDER", "CONTINUAR JOGANDO", _confirm_concede)

## Generic yes/no dialog (same persistent slot as the concede one).
func _ask_confirm(title: String, text: String, yes_label: String, no_label: String, on_yes: Callable) -> void:
	if g == null or g.phase == "over" or concede_view:
		return
	var box := _open_modal_box(title)
	box.add_child(_label(text, 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var yes := _button(yes_label, on_yes, true)
	yes.custom_minimum_size = Vector2(460, 54)
	box.add_child(yes)
	var no := _button(no_label, _close_concede)
	no.custom_minimum_size = Vector2(460, 48)
	box.add_child(no)
	_center_modal(box)

## Opens the dimmed full-screen modal in the persistent `concede_view` slot and returns the empty
## column (already holding the gold title) for the caller to fill; call `_center_modal(box)` when done.
func _open_modal_box(title: String) -> VBoxContainer:
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
	concede_view.add_child(pc)
	return box

func _center_modal(box: VBoxContainer) -> void:
	var pc: Control = box.get_parent()
	add_child(concede_view)
	pc.reset_size()
	pc.position = (Vector2(stage_w, STAGE_H) - pc.size) / 2.0
	_center.call_deferred(pc)

## The in-game menu: settings and the ways out, without leaving the match. Same persistent slot as the
## confirmations, so opponent moves and re-renders don't close it.
func _open_pause_menu() -> void:
	if g == null or concede_view:
		return
	var box := _open_modal_box("MENU")
	# the controls are rebuilt after a toggle so the switch is redrawn in its new position
	var reopen := func():
		_close_concede()
		_open_pause_menu.call_deferred()
	var volume_control := _volume_slider(Vector2(460, 52))
	box.add_child(volume_control)
	var sound_toggle := _toggle_button("SOM", Sfx.is_enabled(), func():
		Sfx.set_enabled(not Sfx.is_enabled())
		reopen.call())
	sound_toggle.custom_minimum_size = Vector2(460, 52)
	box.add_child(sound_toggle)
	# the music has its own volume and switch, apart from the sound effects
	var music_volume_control := _volume_slider(Vector2(460, 52), true)
	box.add_child(music_volume_control)
	var music_toggle := _toggle_button("MÚSICA", Music.is_enabled(), func():
		Music.set_enabled(not Music.is_enabled())
		reopen.call())
	music_toggle.custom_minimum_size = Vector2(460, 52)
	box.add_child(music_toggle)
	var fullscreen_button := _button("Tela cheia (F11)", _toggle_fullscreen)
	fullscreen_button.custom_minimum_size = Vector2(460, 48)
	box.add_child(fullscreen_button)
	var continue_button := _button("CONTINUAR JOGANDO", _close_concede, true)
	continue_button.custom_minimum_size = Vector2(460, 54)
	box.add_child(continue_button)
	var concede_button := _button("Conceder", func():
		_close_concede()
		_ask_concede())
	concede_button.custom_minimum_size = Vector2(460, 48)
	box.add_child(concede_button)
	var leave_button := _button("Sair para o menu principal", func():
		_close_concede()
		_ask_leave_match())
	leave_button.custom_minimum_size = Vector2(460, 48)
	box.add_child(leave_button)
	_center_modal(box)

## Confirmation before leaving the table for the main menu (the only way out that isn't a concede).
func _ask_leave_match() -> void:
	if g == null or g.phase == "over": # the match ended while the menu was open: nothing left to lose
		_show_menu()
		return
	var consequence := "A partida online continua salva: você pode retomá-la pelo lobby online." if online \
		else "Esta partida será perdida."
	_ask_confirm("SAIR PARA O MENU?", consequence, "SAIR PARA O MENU", "VOLTAR AO JOGO", _show_menu)

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
			var cv := CardView.new().setup(grave_card.card_id, _display_instance_for_card(grave_card), 1.1)
			cv.snowball_level = int(g.players[grave_owner]["snowball"])
			cv.text_suffix = _scale_suffix(grave_owner, CardDB.card(grave_card.card_id))
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

const SEARCH_MAX_COLUMNS := 7 ## cards per row in the search window
const SEARCH_MAX_CARD_SCALE := 1.835 ## few cards: they are shown at most this big (1.0 = a card on the table)
const SEARCH_SIDE_ROOM := 160.0 ## stage width kept free around the cards (panel margins and borders)
const SEARCH_VERTICAL_ROOM := 330.0 ## stage height kept free for title, texts and the minimize button

func _render_search_reveal() -> void:
	if g.pending_search.is_empty():
		return
	var owner: int = g.decider()
	var look: bool = g.pending_search.get("look", false)
	# a private look is face up only for its owner (online, the server already masks the cards)
	var discard_hand: bool = g.pending_search.get("discard_hand", false)
	var hand_summon: bool = g.pending_search.get("hand_summon", false)
	var hidden := (look or discard_hand or hand_summon) and not _my_input()
	# the options of a deck search are shown only to the searcher; the opponent just sees that a search is happening
	var deck_search: bool = g.pending_search.get("deck_search", false)
	var secret_search := deck_search and not _my_input()
	var summoning: bool = g.pending_search.get("summon_from", false) # "summon_from": a free summon from the deck, hand or graveyard
	var title := "INVOCAÇÃO GRATUITA" if summoning else "CAMPEÃO DA MÃO" if hand_summon else "DESCARTAR DA MÃO" if discard_hand else "CEMITÉRIO" if g.pending_search.get("grave", false) else (("FUNDO DO DECK" if g.pending_search.get("from_bottom", false) else "TOPO DO DECK") if look else "BUSCA NO DECK")
	var search_signature: int = g.pending_search.hash()
	# the opponent's choice starts folded: there is nothing to do in it, and the table is what matters
	var opponent_choice_is_folded := not _my_input() and search_opened_signature != search_signature
	if search_minimized_signature == search_signature or opponent_choice_is_folded:
		_render_search_minimized(title, not _my_input())
		return
	search_overlay = _veil(0.84)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	search_overlay.add_child(box)
	box.add_child(_label(title, 30, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6))
	var grave: bool = g.pending_search.get("grave", false)
	var sub := "%s está procurando uma carta no deck" % _pname(owner)
	if deck_search and _my_input():
		sub = "Você procurou no deck e encontrou estas cartas; as que brilham podem ser escolhidas"
		if g.pending_search.has("to_bottom"):
			sub = "Você olhou as %d cartas do topo do deck; as que brilham podem ser escolhidas" % int(g.pending_search["looked"])
	if secret_search and g.pending_search.has("to_bottom"):
		sub = "%s está olhando as %d cartas do topo do deck" % [_pname(owner), int(g.pending_search["looked"])]
	if hand_summon:
		sub = "%s escolhe um campeão da mão para entrar em campo (será banido no fim do turno)" % _pname(owner)
	elif discard_hand:
		sub = "%s escolhe uma carta da mão para descartar" % _pname(owner)
	elif look and g.pending_search.get("from_bottom", false):
		sub = "Você pode escolher uma destas cartas do fundo do deck; ela vai para a sua mão" if _my_input() else "%s está olhando cartas do fundo do deck" % _pname(owner)
	elif look:
		sub = "%s está olhando as %d cartas do topo do deck" % [_pname(owner), g.pending_search["cards"].size()]
	if summoning:
		sub = "Você pode invocar uma destas cartas de graça" if _my_input() else "%s está escolhendo uma carta para invocar de graça" % _pname(owner)
		if g.pending_search.has("looked_cards") and _my_input():
			sub = "Você revelou estas cartas do topo do deck, na ordem; a que brilha pode ser invocada de graça"
		elif g.pending_search.has("looked_cards"):
			sub = "%s está revelando as cartas do topo do deck" % _pname(owner)
	box.add_child(_label(sub, 20, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var grid := GridContainer.new()
	var shown_options: Array = [] if secret_search else g.pending_search["cards"]
	# a top-N look shows every card looked at: the eligible ones glow and can be picked, the others are dimmed
	var looked_cards: Array = g.pending_search.get("looked_cards", [])
	var eligible_uids: Dictionary = {}
	for option in shown_options:
		eligible_uids[int(option["uid"])] = true
	if not secret_search and not looked_cards.is_empty():
		shown_options = looked_cards
	# big enough to read the card text: as wide as the stage allows in one row of up to 7 cards, and
	# short enough that every row still fits on the screen
	const GRID_GAP := 12
	var grid_columns := maxi(1, mini(SEARCH_MAX_COLUMNS, shown_options.size()))
	var grid_rows := maxi(1, ceili(float(shown_options.size()) / grid_columns))
	var scale_that_fits_width := (stage_w - SEARCH_SIDE_ROOM - GRID_GAP * (grid_columns - 1)) / grid_columns / CardView.BASE.x
	var scale_that_fits_height := (STAGE_H + BOT - SEARCH_VERTICAL_ROOM - GRID_GAP * (grid_rows - 1)) / grid_rows / CardView.BASE.y
	var card_scale := minf(SEARCH_MAX_CARD_SCALE, minf(scale_that_fits_width, scale_that_fits_height))
	var grid_width := grid_columns * CardView.BASE.x * card_scale + GRID_GAP * (grid_columns - 1)
	box.custom_minimum_size = Vector2(maxf(1115.0, grid_width), 0)
	grid.columns = grid_columns
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(grid)
	for option in shown_options:
		var card_uid: int = option["uid"]
		var eligible: bool = eligible_uids.has(card_uid)
		var cv := CardView.new().setup(option["card_id"], _display_instance_for_id(String(option["card_id"]), owner, card_uid), card_scale)
		cv.face_down = hidden or String(option["card_id"]) == ""
		if not cv.face_down:
			cv.text_suffix = _scale_suffix(owner, CardDB.card(option["card_id"]))
			cv.snowball_level = int(g.players[owner]["snowball"])
		# every card can be inspected (right click / long press), picked or not: some rules texts
		# only make sense in the full-screen view. Only the eligible ones can be chosen.
		var can_pick: bool = eligible and _my_input()
		if can_pick:
			cv.highlight = OK # a glow marks what can be clicked, for every kind of choice
		elif not eligible:
			cv.modulate = Color(1, 1, 1, 0.4)
		cv.right_clicked.connect(_show_overlay)
		if can_pick:
			cv.left_clicked.connect(func(_v): _on_search_choice(card_uid))
		grid.add_child(cv)
	var summon_hint := "Clique na carta que brilha para invocá-la de graça, ou escolha não invocar nenhuma."
	if g.pending_search.has("looked_cards") and g.pending_search.get("leftover", "bottom") == "bottom":
		summon_hint += " As outras cartas reveladas vão para o fundo do deck."
	var grave_optional: bool = g.pending_search.get("grave_optional", false) # "grave_to_hand" (Rebobinar): the pick may be skipped
	var hint := summon_hint if summoning else "Clique em uma carta para levá-la à sua mão, ou escolha não pegar nenhuma; as outras ficam no cemitério." if grave_optional else "Clique em um campeão para colocá-lo em campo sem pagar o custo, ou escolha não colocar nenhum." if hand_summon else "Clique em uma carta para descartá-la (ela vai para o cemitério)." if discard_hand else "Clique em uma carta para adicioná-la à sua mão; as outras ficam no cemitério." if grave else ("Escolha 1 para a mão; as outras continuam onde estavam no fundo do deck." if g.pending_search.get("from_bottom", false) else "Escolha 1 para a mão; as outras vão para o fundo do deck.") if look else "Clique em uma carta que brilha para adicioná-la à sua mão, ou escolha não pegar nenhuma; as outras cartas olhadas vão para o fundo do deck." if g.pending_search.has("to_bottom") else "Clique em uma carta que brilha para adicioná-la à sua mão e embaralhar o deck, ou escolha não pegar nenhuma."
	var footer := _label(hint if _my_input() else "A escolha pertence ao oponente.", 18, SEL if _my_input() else UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body")
	box.add_child(footer)
	if not secret_search:
		box.add_child(_label("Botão direito (ou segurar o dedo) em uma carta abre ela em tela cheia.", 15, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	if (hand_summon or deck_search or summoning or grave_optional) and _my_input():
		# both picks are optional: uid 0 means "take no card" (Dona Gertrudes puts no champion in play)
		var skip_button := _button("NÃO INVOCAR NENHUMA" if summoning else "NÃO COLOCAR NENHUM" if hand_summon else "NÃO PEGAR NENHUMA", func(): _on_search_choice(0))
		skip_button.custom_minimum_size = Vector2(360, 52)
		skip_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(skip_button)
	var minimize_button := _button("▼  VER A MESA", func():
		search_minimized_signature = search_signature
		search_opened_signature = -1
		_render())
	minimize_button.custom_minimum_size = Vector2(360, 52)
	minimize_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(minimize_button)
	_center.call_deferred(search_overlay)

## The search folded into a small bar at the top of the screen, so the table can be seen (and cards on
## it inspected). The bar brings the full choice back.
func _render_search_minimized(title: String, opponents_choice := false) -> void:
	var bar := PanelContainer.new()
	var style := UITheme.panel(14)
	style.set_content_margin_all(10)
	style.border_color = Color(UITheme.GOLD, 0.6)
	style.shadow_size = 24
	bar.add_theme_stylebox_override("panel", style)
	layer.add_child(bar)
	var restore_text := "▲  VER A ESCOLHA DO OPONENTE · %s" if opponents_choice else "▲  VOLTAR À ESCOLHA · %s"
	var restore_button := _button(restore_text % title, func():
		search_minimized_signature = -1
		search_opened_signature = g.pending_search.hash()
		_render(), true)
	restore_button.custom_minimum_size = Vector2(520, 60)
	bar.add_child(restore_button)
	search_overlay = bar
	_place_at_top_center.call_deferred(bar)

func _place_at_top_center(control: Control) -> void:
	control.reset_size()
	control.position = Vector2((size.x - control.size.x) / 2.0, 8.0)


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

## A unit that enters the board straight from the deck: it leaves the top of its owner's pile face
## down, flips face up halfway (like a drawn card) and lands in its slot with the same small bounce
## and sound as a unit played from the hand. Returns how long it takes.
func _enter_from_deck(v: CardView, owner_player: int, t0: float) -> float:
	const FLIGHT_TIME := 0.5
	var deck_pose := _deck_top_pose(owner_player)
	var to := _pose(v)
	v.z_index = 20
	v.face_down = true
	var tw := _fly(v, deck_pose, to, t0, FLIGHT_TIME, 60.0, true)
	tw.tween_callback(func(): v.z_index = 0)
	var landing_scale: Vector2 = Vector2.ONE * (to["w"] / v.size.x)
	tw.tween_property(v, "scale", landing_scale * 1.1, 0.06)
	tw.tween_property(v, "scale", landing_scale, 0.1)
	var flip := v.create_tween()
	flip.tween_interval(t0 + FLIGHT_TIME * 0.45)
	flip.tween_callback(func():
		v.face_down = false
		v.queue_redraw())
	Sfx.play_in("card_place", t0 + FLIGHT_TIME - 0.04)
	return FLIGHT_TIME + 0.1

## A drawn card is a physical card: it slides off the top of the viewer's deck pile face down,
## lifts in a soft arc toward the hand while turning over (it narrows to its edge, the face
## shows, it widens again) and settles into its hand slot, slowing down as it arrives.
const DRAW_FLIGHT_TIME := 0.62
const DRAW_ARC_HEIGHT := 90.0 ## how high the card lifts above the straight line from deck to hand
const DRAW_TILT_DEGREES := -10.0 ## the card leans a little while it travels, like one tossed by hand

func _draw_from_deck(v: CardView, to: Dictionary, t0: float) -> void:
	var from := _deck_top_pose(viewer)
	_apply_pose(v, from)
	v.face_down = true
	v.visible = false
	v.z_index = 25
	var flight := v.create_tween()
	if t0 > 0.0:
		flight.tween_interval(t0)
	flight.tween_callback(func(): v.visible = true)
	flight.tween_method(func(progress: float):
		var eased := 1.0 - pow(1.0 - progress, 3.0) # quick start, gentle landing
		var center: Vector2 = from["c"].lerp(to["c"], eased)
		center.y -= DRAW_ARC_HEIGHT * 4.0 * eased * (1.0 - eased)
		var tilt := deg_to_rad(DRAW_TILT_DEGREES) * sin(PI * eased)
		_apply_pose(v, {"c": center, "rot": lerp_angle(from["rot"], to["rot"], eased) + tilt, "w": lerpf(from["w"], to["w"], eased)})
		# turning over: the card narrows to its edge around the middle of the flight, then shows its face
		var turn := clampf((eased - 0.25) / 0.5, 0.0, 1.0)
		if v.face_down and turn >= 0.5:
			v.face_down = false
			v.queue_redraw()
		v.scale.x *= maxf(0.04, absf(cos(PI * turn))),
		0.0, 1.0, DRAW_FLIGHT_TIME)
	flight.tween_callback(func(): v.z_index = 0)

## A unit sent back to the opponent's hand (a bounce) is not a death: the card lifts off its slot, turns
## face down while it travels (the viewer must not read the opponent's hand) and slides into the fan along
## the top edge, shrinking to the size of the cards there. `ghost` stands where the unit was on the table.
## Starts at moment t; returns how long the flight takes.
const BOUNCE_FLIGHT_TIME := 0.55
const BOUNCE_LIFT_HEIGHT := 30.0 ## how far the card rises before it heads for the hand
func _bounce_to_enemy_hand_fx(ghost: CardView, owner_player: int, t: float) -> float:
	var from := _pose(ghost)
	var hand_size: int = g.players[owner_player]["hand"].size()
	var card_size := CardView.BASE * ENEMY_HAND_SCALE
	# the last card of the fan: the bounced card is always added at the end of the hand
	var to := {
		"c": Vector2(lane_cx + EHAND_DX + (hand_size - 1) / 2.0 * 30.0, _screen_top() - card_size.y * (0.5 - ENEMY_HAND_SHOWN)),
		"rot": PI,
		"w": card_size.x,
	}
	ghost.z_index = 25
	var flight := ghost.create_tween()
	if t > 0.0:
		flight.tween_interval(t)
	flight.tween_method(func(progress: float):
		var eased := ease(progress, -1.6) # slow lift-off, quicker towards the hand
		var center: Vector2 = from["c"].lerp(to["c"], eased)
		center.y -= BOUNCE_LIFT_HEIGHT * 4.0 * eased * (1.0 - eased) * (1.0 - eased) # a small hop at the start
		_apply_pose(ghost, {"c": center, "rot": lerp_angle(from["rot"], to["rot"], eased), "w": lerpf(from["w"], to["w"], eased)})
		# turning over: it narrows to its edge around the middle of the flight, then shows its back
		var turn := clampf((progress - 0.2) / 0.5, 0.0, 1.0)
		if not ghost.face_down and turn >= 0.5:
			ghost.face_down = true
			ghost.queue_redraw()
		ghost.scale.x *= maxf(0.04, absf(cos(PI * turn)))
		ghost.modulate.a = 1.0 - clampf((progress - 0.85) / 0.15, 0.0, 1.0), # melts into the real card already in the fan
		0.0, 1.0, BOUNCE_FLIGHT_TIME)
	flight.tween_callback(ghost.queue_free)
	return BOUNCE_FLIGHT_TIME

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
	var deck_pose := _deck_top_pose(deck_owner)
	var grave_pose := _graveyard_pose(deck_owner)
	# the card is shown a bit toward the middle of the table, so the Leader's own frame doesn't hide it
	var middle_y := (_screen_top() + _screen_bottom()) / 2.0
	var shown_pose := {"c": deck_pose["c"] + Vector2(0, 170.0 * signf(middle_y - deck_pose["c"].y)), "rot": 0.0, "w": MILL_CARD_W}
	# a pile in the HUD column shows the card over the table instead, not over the buttons
	shown_pose["c"].x = minf(shown_pose["c"].x, col_x - 26.0 - MILL_CARD_W / 2.0)
	var stagger := minf(MILL_STAGGER, MILL_MAX_STAGGER_TOTAL / card_ids.size())
	var total_time := MILL_RISE_TIME + MILL_HOLD_TIME + MILL_DROP_TIME
	for i in card_ids.size():
		var ghost := _ghost(card_ids[i], _display_instance_for_id(String(card_ids[i]), deck_owner), deck_pose, MILL_CARD_W / CardView.BASE.x) # built at its biggest size: only shrinks, never blurs
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
const LUNGE_WINDUP_TIME := 0.1375
const LUNGE_STRIKE_TIME := 0.1375
const LUNGE_HOLD_TIME := 0.07
const LUNGE_RETURN_TIME := 0.23
## When the attacker touches its target (where the hit lands), counted from the lunge start.
const LUNGE_IMPACT_TIME := LUNGE_WINDUP_TIME + LUNGE_STRIKE_TIME
const LUNGE_TOTAL_TIME := LUNGE_IMPACT_TIME + LUNGE_HOLD_TIME + LUNGE_RETURN_TIME
## A unit lying down (tap) or standing up (untap): a short pause after the action, then a slow turn.
const TAP_DELAY := 0.12
## How long a stand-in summoned just to take a blow (Fantoche de Trapos) stays readable before the blow lands.
const SHORT_LIVED_ARRIVAL_TIME := 0.6
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
		strike.tween_property(a, "lunge", -offset_to_target * 0.22, LUNGE_WINDUP_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		strike.tween_property(a, "lunge", offset_to_target, LUNGE_STRIKE_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
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
## ring of light to the Leader, "Anulado!" floats over the Leader (like a Magic Shield), the Leader
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

## Execution (a card effect kills the Leader outright, e.g. Viprax): deliberately unlike a hit.
## The Leader trembles while a ring closes in on it (wind-up), then two slashes cross it, the screen
## takes the heaviest shake, "Execução" appears in the effect's color and the HP count drains to zero
## instead of dropping in one step. Returns the time at which the animation is over.
const EXECUTION_WINDUP_TIME := 0.55
const EXECUTION_DRAIN_TIME := 0.9

func _execution_fx(leader: LeaderView, hp_before: int, t: float, col: Color) -> float:
	var center := _center_of(leader)
	var strike_t := t + EXECUTION_WINDUP_TIME

	# wind-up: the Leader trembles harder and harder, a ring closes in on it
	var base := leader.position
	var tremble := leader.create_tween()
	tremble.tween_interval(t)
	tremble.tween_method(func(k: float): leader.position = base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 7.0 * k, 0.0, 1.0, EXECUTION_WINDUP_TIME)
	tremble.tween_callback(func(): leader.position = base)
	var ring := Line2D.new()
	var points := PackedVector2Array()
	for i in 33:
		points.append(Vector2.from_angle(TAU * i / 32.0) * 60.0)
	ring.points = points
	ring.width = 5.0
	ring.default_color = Color(col, 0.9)
	ring.position = center
	ring.z_index = 58
	ring.scale = Vector2.ONE * 3.2
	ring.modulate.a = 0.0
	fx.add_child(ring)
	var ring_tween := ring.create_tween()
	ring_tween.tween_interval(t)
	ring_tween.tween_property(ring, "modulate:a", 1.0, 0.15)
	ring_tween.parallel().tween_property(ring, "scale", Vector2.ONE * 0.9, EXECUTION_WINDUP_TIME).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	ring_tween.tween_callback(ring.queue_free)

	# strike: two crossing slashes, the heaviest screen shake and sparks in the effect's color
	_cross_slash_fx(center, Vector2(95, 75), col, strike_t)
	_crushing_blow_fx(leader, 15, strike_t)
	_embers(center, strike_t, col, 30)

	var title := _label("Execução", 52, col.lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER, "heavy", 12)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.size = Vector2(340, 66)
	title.pivot_offset = title.size / 2.0
	title.position = center - title.size / 2.0 + Vector2(0, -28)
	title.scale = Vector2(1.8, 1.8)
	title.modulate.a = 0.0
	fx.add_child(title)
	var title_tween := title.create_tween()
	title_tween.tween_interval(strike_t)
	title_tween.tween_property(title, "modulate:a", 1.0, 0.05)
	title_tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	title_tween.tween_interval(0.9)
	title_tween.tween_property(title, "modulate:a", 0.0, 0.3)
	title_tween.tween_callback(title.queue_free)

	# the HP count runs down to zero instead of dropping in one step
	var drain := leader.create_tween()
	drain.tween_interval(strike_t)
	drain.tween_method(func(shown_hp: float):
		leader.hp = roundi(shown_hp)
		leader.queue_redraw(), float(hp_before), 0.0, EXECUTION_DRAIN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drain.tween_callback(func():
		leader.hp = 0
		leader.queue_redraw())
	return strike_t + EXECUTION_DRAIN_TIME + 0.6

## A card yells its line (an effect's "shout", Barão Estrondoso). Unlike every other float it uses the
## racing font (UITheme "shout") and builds up: the screen dims, each word but the last slams in over
## the card, bigger and hotter than the one before, and gets knocked away by the next; after a beat
## the last word EXPLODES: white flash, a dark slanted band, red and cyan ghost copies that jitter
## and snap together, a color-cycling title, shockwave, shake and sparks.
## Returns the time at which the next animation may start (the finale is still fading out then).
const SHOUT_WORD_GAP := 0.17 ## seconds between two build-up words
const SHOUT_DRAMATIC_PAUSE := 0.3 ## extra beat before the last word explodes
const SHOUT_FINALE_HOLD := 1.0 ## how long the exploded word stays on screen
const SHOUT_BUILDUP_COLORS: Array[Color] = [Color("#ffe14a"), Color("#ffab2e"), Color("#ff6a1f"), Color("#ff2f4f")]
const SHOUT_FINALE_COLORS: Array[Color] = [Color("#fff6c8"), Color("#ffd23a"), Color("#ff7a1a"), Color("#ffffff")]

func _shout_fx(speaker: Control, text: String, t: float) -> float:
	var screen := get_viewport_rect().size
	var words := text.split(" ", false)
	if words.is_empty():
		return t
	var finale_word := words[words.size() - 1]
	var buildup_words := words.slice(0, words.size() - 1)
	# everything happens over the speaker, pushed inside the screen near its borders
	var anchor := _center_of(speaker)
	anchor.x = clampf(anchor.x, screen.x * 0.3, screen.x * 0.7)
	anchor.y = clampf(anchor.y, screen.y * 0.25, screen.y * 0.75)
	var boom_t := t + buildup_words.size() * SHOUT_WORD_GAP + SHOUT_DRAMATIC_PAUSE
	var end_t := boom_t + SHOUT_FINALE_HOLD

	# the whole screen dims while the card talks
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.04)
	dim.size = screen
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 60
	dim.modulate.a = 0.0
	fx.add_child(dim)
	var dim_tween := dim.create_tween()
	dim_tween.tween_interval(t)
	dim_tween.tween_property(dim, "modulate:a", 0.45, 0.15)
	dim_tween.tween_interval(end_t - t - 0.15)
	dim_tween.tween_property(dim, "modulate:a", 0.0, 0.3)
	dim_tween.tween_callback(dim.queue_free)

	# build-up: one word at a time, each bigger, hotter and tilted the other way
	for i in buildup_words.size():
		var appear_t := t + i * SHOUT_WORD_GAP
		var is_last_buildup_word := i == buildup_words.size() - 1
		var leave_t := boom_t if is_last_buildup_word else appear_t + SHOUT_WORD_GAP
		var tilt_side := -1.0 if i % 2 == 0 else 1.0
		var word_color: Color = SHOUT_BUILDUP_COLORS[mini(i, SHOUT_BUILDUP_COLORS.size() - 1)]
		var word := _shout_label(String(buildup_words[i]).to_upper(), 30 + 7 * i, word_color, screen.x * 0.9)
		word.position = anchor - word.size / 2.0 + Vector2(tilt_side * 18.0, -40.0 + 12.0 * i)
		word.rotation = deg_to_rad(7.0 * tilt_side)
		word.scale = Vector2.ONE * 2.4
		var word_tween := word.create_tween()
		word_tween.tween_interval(appear_t)
		word_tween.tween_property(word, "modulate:a", 1.0, 0.03)
		word_tween.parallel().tween_property(word, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var resting_position := word.position
		if is_last_buildup_word:
			# the dramatic beat: the last word shivers, as if holding its breath
			word_tween.tween_method(func(k: float): word.position = resting_position + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 4.0 * k, 0.0, 1.0, leave_t - appear_t - 0.12)
		else:
			word_tween.tween_interval(leave_t - appear_t - 0.12)
		# knocked away by the next word
		word_tween.tween_property(word, "position", resting_position + Vector2(tilt_side * -160.0, -110.0), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		word_tween.parallel().tween_property(word, "rotation", word.rotation - tilt_side * 0.6, 0.25)
		word_tween.parallel().tween_property(word, "modulate:a", 0.0, 0.25)
		word_tween.tween_callback(word.queue_free)

	# finale: a white flash...
	var flash := ColorRect.new()
	flash.color = Color.WHITE
	flash.size = screen
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 64
	flash.modulate.a = 0.0
	fx.add_child(flash)
	var flash_tween := flash.create_tween()
	flash_tween.tween_interval(boom_t)
	flash_tween.tween_property(flash, "modulate:a", 0.7, 0.03)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	flash_tween.tween_callback(flash.queue_free)

	# ...a dark slanted band with gold edges sweeps across, under the word...
	var band := Control.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.z_index = 61
	band.position = anchor
	band.rotation = deg_to_rad(-6.0)
	band.scale = Vector2(0.0, 1.0)
	fx.add_child(band)
	var band_width := screen.x * 1.6
	var band_height := 110.0
	## each stripe: [color, top edge, height]; the dark body and its two gold edges
	var stripes := [[Color(0.08, 0.0, 0.02, 0.88), -band_height / 2.0, band_height],
		[UITheme.GOLD, -band_height / 2.0 - 5.0, 4.0],
		[UITheme.GOLD, band_height / 2.0 + 1.0, 4.0]]
	for stripe in stripes:
		var stripe_rect := ColorRect.new()
		stripe_rect.color = stripe[0]
		stripe_rect.position = Vector2(-band_width / 2.0, stripe[1])
		stripe_rect.size = Vector2(band_width, stripe[2])
		stripe_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(stripe_rect)
	var band_tween := band.create_tween()
	band_tween.tween_interval(boom_t)
	band_tween.tween_property(band, "scale:x", 1.0, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	band_tween.tween_interval(SHOUT_FINALE_HOLD - 0.18)
	band_tween.tween_property(band, "scale:y", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	band_tween.tween_callback(band.queue_free)

	# ...red and cyan ghosts that jitter apart and snap together under the real word...
	var finale_text := finale_word.to_upper()
	for ghost_side in [-1.0, 1.0]:
		var ghost_color := Color(1.0, 0.1, 0.35, 0.8) if ghost_side < 0 else Color(0.1, 0.95, 1.0, 0.8)
		var ghost := _shout_label(finale_text, 76, ghost_color, screen.x - 32.0)
		ghost.position = anchor - ghost.size / 2.0
		ghost.rotation = deg_to_rad(-4.0)
		var ghost_rest := ghost.position
		var ghost_tween := ghost.create_tween()
		ghost_tween.tween_interval(boom_t)
		ghost_tween.tween_property(ghost, "modulate:a", 1.0, 0.02)
		ghost_tween.tween_method(func(k: float):
			var spread := (1.0 - k) * 16.0 + 3.0
			ghost.position = ghost_rest + Vector2(ghost_side * spread + randf_range(-3, 3), randf_range(-3, 3)), 0.0, 1.0, 0.6)
		ghost_tween.tween_interval(SHOUT_FINALE_HOLD - 0.62)
		ghost_tween.tween_property(ghost, "modulate:a", 0.0, 0.25)
		ghost_tween.tween_callback(ghost.queue_free)

	# ...and the word itself, slammed in from huge, its color cycling white-hot / gold / orange
	var title := _shout_label(finale_text, 76, SHOUT_FINALE_COLORS[0], screen.x - 32.0)
	title.z_index = 63
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.0, 0.02))
	title.position = anchor - title.size / 2.0
	title.rotation = deg_to_rad(-4.0)
	title.scale = Vector2.ONE * 3.2
	var title_tween := title.create_tween()
	title_tween.tween_interval(boom_t)
	title_tween.tween_property(title, "modulate:a", 1.0, 0.02)
	title_tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	title_tween.parallel().tween_method(func(k: float):
		var cycle := fmod(k * 6.0, float(SHOUT_FINALE_COLORS.size()))
		var from_index := int(cycle)
		var to_index := (from_index + 1) % SHOUT_FINALE_COLORS.size()
		title.add_theme_color_override("font_color", SHOUT_FINALE_COLORS[from_index].lerp(SHOUT_FINALE_COLORS[to_index], cycle - from_index)), 0.0, 1.0, SHOUT_FINALE_HOLD)
	title_tween.tween_property(title, "modulate:a", 0.0, 0.25)
	title_tween.parallel().tween_property(title, "scale", Vector2(1.6, 0.2), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	title_tween.tween_callback(title.queue_free)

	# BOOM, shockwave, screen shake and sparks
	Sfx.play_in("atomic_boom", boom_t)
	_crushing_blow_fx(speaker, 15, boom_t)
	_embers(anchor, boom_t, Color("#ff9a2a"), 40)
	_embers(anchor, boom_t + 0.08, Color("#7af4ff"), 18)
	return boom_t + 0.35

## A label in the shout font, hidden, already added to the fx layer, sized to its text and pivoting on
## its center. The font shrinks if needed so the text never gets wider than `max_width` (phones).
func _shout_label(text: String, font_size: int, color: Color, max_width: float) -> Label:
	var shout_font := UITheme.font("shout")
	var text_width := shout_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if text_width > max_width:
		font_size = int(font_size * max_width / text_width)
	var label := _label(text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, "shout", maxi(6, font_size / 7))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	label.z_index = 62
	label.modulate.a = 0.0
	fx.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size / 2.0
	return label

## The "X" of every destruction: two slashes that cross over `center`, the second 0.09s after the first.
## `half_extent` is how far each slash reaches from the center (half the width and height of the X).
const CROSS_SLASH_SECOND_DELAY := 0.09
const CROSS_SLASH_FORM_TIME := 0.12 ## how long one slash takes to be drawn
func _cross_slash_fx(center: Vector2, half_extent: Vector2, col: Color, t: float) -> void:
	_execution_slash(center, Vector2(-half_extent.x, -half_extent.y), half_extent, col, t)
	_execution_slash(center, Vector2(half_extent.x, -half_extent.y), Vector2(-half_extent.x, half_extent.y), col, t + CROSS_SLASH_SECOND_DELAY)

## One slash of the execution: a bright line drawn from `from_offset` to `to_offset` (relative to
## `center`) in a few frames, then fading out.
func _execution_slash(center: Vector2, from_offset: Vector2, to_offset: Vector2, col: Color, t: float) -> void:
	var slash := Line2D.new()
	slash.width = 10.0
	slash.default_color = col.lightened(0.6)
	slash.position = center
	slash.z_index = 59
	slash.points = PackedVector2Array([from_offset, from_offset])
	slash.modulate.a = 0.0
	fx.add_child(slash)
	var slash_tween := slash.create_tween()
	slash_tween.tween_interval(t)
	slash_tween.tween_property(slash, "modulate:a", 1.0, 0.01)
	slash_tween.tween_method(func(k: float): slash.points = PackedVector2Array([from_offset, from_offset.lerp(to_offset, k)]), 0.0, 1.0, 0.12)
	slash_tween.tween_property(slash, "modulate:a", 0.0, 0.4)
	slash_tween.tween_callback(slash.queue_free)

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
		tw.tween_method(func(k: float): cv.shake = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 11.0 * (1.0 - k), 0.0, 1.0, 0.32)
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

## Empty slots get frozen (Rei Gelado). _render already drew them covered in ice, so the ice is wiped
## off, and at moment t it slams back on like it does on a unit: flash, shockwaves, growing ice, shards.
func _freeze_slots_fx(frozen_player: int, t: float) -> void:
	for node in layer.get_children():
		if not node is FrozenSlotView or node.owner_player != frozen_player:
			continue
		var tile: FrozenSlotView = node
		tile.frost_grow = 0.0
		var spread := tile.create_tween()
		spread.tween_interval(t)
		spread.tween_property(tile, "frost_grow", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		var burst := tile.create_tween()
		burst.tween_interval(t)
		burst.tween_property(tile, "frost_burst", 1.0, 0.65).from(0.001)
		burst.tween_callback(func(): tile.frost_burst = 0.0)
		_frost_shards(tile.position + tile.size / 2.0, t, 24)

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

## Escudo Supremo: a gold-and-ivory burst, with layered rings and star-like rays.
func _supreme_shield_fx(target: Control, t: float) -> void:
	var burst := Node2D.new()
	burst.position = _center_of(target)
	burst.z_index = 55
	fx.add_child(burst)
	var outer := _ring_line(34.0, 4.0, Color("#ffd86b"))
	outer.modulate.a = 0.0
	burst.add_child(outer)
	var inner := _ring_line(22.0, 2.5, Color("#fff5cf"))
	inner.modulate.a = 0.0
	burst.add_child(inner)
	var flare := _glow_sprite(42.0, Color("#ffe9a3", 0.9))
	flare.modulate.a = 0.0
	burst.add_child(flare)
	var rays: Array[Line2D] = []
	for i in 8:
		var ray := Line2D.new()
		ray.points = PackedVector2Array([Vector2(0, -27), Vector2(0, -43 if i % 2 == 0 else -37)])
		ray.width = 2.5 if i % 2 == 0 else 1.5
		ray.default_color = Color("#fff5cf") if i % 2 == 0 else Color("#ffd86b")
		ray.rotation = TAU * float(i) / 8.0
		ray.scale = Vector2(0.35, 0.35)
		ray.modulate.a = 0.0
		burst.add_child(ray)
		rays.append(ray)
	var tw := burst.create_tween()
	tw.tween_interval(t)
	tw.tween_property(outer, "modulate:a", 1.0, 0.04)
	tw.parallel().tween_property(inner, "modulate:a", 1.0, 0.04)
	tw.parallel().tween_property(flare, "modulate:a", 1.0, 0.04)
	for ray in rays:
		tw.parallel().tween_property(ray, "modulate:a", 1.0, 0.04)
	tw.tween_property(outer, "scale", Vector2(2.0, 2.0), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(outer, "modulate:a", 0.0, 0.42)
	tw.parallel().tween_property(inner, "scale", Vector2(1.45, 1.45), 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(inner, "modulate:a", 0.0, 0.34)
	tw.parallel().tween_property(flare, "scale", Vector2(2.0, 2.0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(flare, "modulate:a", 0.0, 0.3)
	for ray in rays:
		tw.parallel().tween_property(ray, "scale", Vector2(1.4, 1.4), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(ray, "modulate:a", 0.0, 0.3)
	tw.tween_callback(burst.queue_free)


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
## Also scaled by GraphicsQuality.effect_detail, so phones always get lighter effects.
var _fx_scale := 1.0
## The chain part of _fx_scale alone (without the phone economy): sets how fast shots fly, so the
## game paces the same on every device.
var _fx_chain_scale := 1.0

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
	# effect bolts: additive glow sprites, lines and world-space sparks
	holder.add_child(_glow_sprite(8.0, Color.WHITE))
	var glow_line := _ring_line(8.0, 2.0, Color.WHITE)
	holder.add_child(glow_line)
	var trail := CPUParticles2D.new()
	trail.amount = 4
	trail.one_shot = true
	trail.local_coords = false
	trail.material = _additive()
	trail.color_ramp = Gradient.new()
	trail.emitting = true
	holder.add_child(trail)
	# thorn hit style: a polygon with per-vertex colors
	var thorn_spike := Polygon2D.new()
	thorn_spike.polygon = PackedVector2Array([Vector2.ZERO, Vector2(8, 0), Vector2(0, 8)])
	thorn_spike.vertex_colors = PackedColorArray([Color.WHITE, Color.RED, Color.GREEN])
	holder.add_child(thorn_spike)
	# floating numbers / trigger tags: big outlined glyphs are rasterized on first use
	var num := _label("-0123456789+/!", 46, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 10)
	num.size = Vector2(400, 58)
	holder.add_child(num)
	var tg := _label("Ao Morrer Aliado Morre Ao Entrar Escudo Maré Congelada", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 4)
	tg.position = Vector2(0, 60)
	holder.add_child(tg)
	var shout_glyphs := _label("SUPER HIPER ULTRA MEGA… ATÔMICA!", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "shout", 10)
	shout_glyphs.position = Vector2(0, 90)
	holder.add_child(shout_glyphs)
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

## How long each part of the default shot takes (see _effect_bolt). Only the first shot of a trigger
## winds up, so the eye finds the source; the ones after it leave at once, like a gun already firing.
## The flight is short: the shot is spat out hard, not lobbed.
const BOLT_CHARGE_FIRST := 0.12
const BOLT_CHARGE_NEXT := 0.0
const BOLT_FLIGHT := 0.15
## How long the comet's flame tail is, as a fraction of the whole path.
const BOLT_TAIL_LENGTH := 0.3
## Time between two shots of the same trigger landing (Eryon's blows, damage spread over enemies):
## short enough to feel like a burst of gunfire, long enough to still count each hit.
const VOLLEY_GAP := 0.11
## How long each part of the good-effect orb takes (see _boon_shot). It is slower than a shot on
## purpose: a heal or a buff is delivered, not fired. The first one of a trigger charges longer
## so the eye finds the source.
const BOON_CHARGE_FIRST := 0.16
const BOON_CHARGE_NEXT := 0.07
const BOON_FLIGHT := 0.32

## Shared by every glow sprite: additive blending, so overlapping light adds up and burns white.
var _additive_material: CanvasItemMaterial
## Soft round dot (white center fading to transparent), tinted by each sprite's modulate.
var _soft_dot_texture: GradientTexture2D

func _additive() -> CanvasItemMaterial:
	if _additive_material == null:
		_additive_material = CanvasItemMaterial.new()
		_additive_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive_material

## A glowing dot of light of the given radius and color (additive, so it glows over anything).
func _glow_sprite(radius: float, col: Color) -> Sprite2D:
	if _soft_dot_texture == null:
		var gr := Gradient.new()
		gr.set_color(0, Color.WHITE)
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.3, Color(1, 1, 1, 0.6))
		_soft_dot_texture = GradientTexture2D.new()
		_soft_dot_texture.gradient = gr
		_soft_dot_texture.fill = GradientTexture2D.FILL_RADIAL
		_soft_dot_texture.fill_from = Vector2(0.5, 0.5)
		_soft_dot_texture.fill_to = Vector2(1.0, 0.5)
		_soft_dot_texture.width = 64
		_soft_dot_texture.height = 64
	var s := Sprite2D.new()
	s.texture = _soft_dot_texture
	s.material = _additive()
	s.modulate = col
	s.scale = Vector2.ONE * radius / 32.0
	return s

## A thin circle outline of the given radius, centered on its own position.
func _ring_line(radius: float, width: float, col: Color) -> Line2D:
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 33:
		pts.append(Vector2.from_angle(TAU * i / 32.0) * radius)
	ring.points = pts
	ring.width = width
	ring.default_color = col
	ring.material = _additive()
	return ring

## Color of the bolt that carries an effect, by what the effect does: red-orange for damage,
## green for healing, ice for freezing, the marker's own color for poison/bleed and so on.
## A summon has its own fuchsia, so a card appearing never reads as a stat bonus (lime).
func _bolt_color(e: Dictionary) -> Color:
	match String(e["type"]):
		"damage", "shield_break", "magic_shield_break", "supreme_shield_break":
			return Color("#ff5a2e")
		"heal":
			return Color("#5dff8a")
		"buff":
			return Color("#b6ff7a")
		"summon":
			return Color("#ff6fe0")
		"freeze":
			return ICE
		"dot":
			return CardView.dot_badge_color(String(e["dot"]))
		"condemn":
			return CardView.DOOM_COL
		"stun":
			return CardView.STUN_COL
		"exhaust", "ready", "tide_mark":
			return Color("#6fd0ff")
	return CardView.TRIGGER_COL

## The path a shot travels from `from` to `to`, shared by every hit style. It is a curve that bows
## sideways (to a random side) by `arc` times the distance between the ends, at most `arc_cap` pixels.
## Returns:
##   "ends": {"a": source center, "b": target center}, the last known positions of both ends;
##   "refresh": a Callable that updates "ends" while the two controls still exist (call it every
##     frame: if one is freed mid-flight, by a re-render or the source dying, its last position is
##     kept, so the shot still finishes its path);
##   "point_at": a Callable(u) -> Vector2, the point at fraction u of the path (0 = source, 1 = target).
func _shot_path(from: Control, to: Control, arc: float, arc_cap: float) -> Dictionary:
	var bend := 1.0 if randf() < 0.5 else -1.0
	var ends := {"a": _center_of(from), "b": _center_of(to)}
	var source_ref: WeakRef = weakref(from)
	var target_ref: WeakRef = weakref(to)
	var refresh_ends := func():
		var source_view: Control = source_ref.get_ref()
		var target_view: Control = target_ref.get_ref()
		if source_view != null:
			ends["a"] = _center_of(source_view)
		if target_view != null:
			ends["b"] = _center_of(target_view)
	var point_at := func(u: float) -> Vector2:
		var a: Vector2 = ends["a"]
		var b: Vector2 = ends["b"]
		var ctrl := (a + b) / 2.0 + (b - a).orthogonal().normalized() * minf(a.distance_to(b) * arc, arc_cap) * bend
		return a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u)
	return {"ends": ends, "refresh": refresh_ends, "point_at": point_at}

## The hit style a card's effects fly with: its JSON's optional "hit_fx" field (for example
## "espinho" on the Flor Voraz). Leaders and cards without the field use the default bolt ("").
func _hit_style_of(source: Control) -> String:
	if source is CardView:
		return String(CardDB.card((source as CardView).card_id).get("hit_fx", ""))
	return ""

## Whether an event is good for the card it lands on: healing, a summon, or a buff that only adds
## (a buff with a negative number is a debuff, and that one is fired like any hit).
func _is_boon_event(e: Dictionary) -> bool:
	match String(e["type"]):
		"heal", "summon":
			return true
		"buff":
			return int(e.get("atk", 0)) >= 0 and int(e.get("hp", 0)) >= 0
	return false

## Timing of one shot in a hit style: {"charge": the wind-up on the source before it leaves,
## "flight": its time in the air}. Big chains fire faster, so a long chain does not drag.
func _shot_timing(style: String, first_shot: bool) -> Dictionary:
	var pace := 0.55 + 0.45 * _fx_chain_scale
	match style:
		"espinho":
			return {"charge": (THORN_CHARGE_FIRST if first_shot else THORN_CHARGE_NEXT) * pace, "flight": THORN_FLIGHT * pace}
		"corte":
			return {"charge": (SLASH_CHARGE_FIRST if first_shot else SLASH_CHARGE_NEXT) * pace, "flight": SLASH_DASH * pace}
		"boon":
			return {"charge": (BOON_CHARGE_FIRST if first_shot else BOON_CHARGE_NEXT) * pace, "flight": BOON_FLIGHT * pace}
	return {"charge": (BOLT_CHARGE_FIRST if first_shot else BOLT_CHARGE_NEXT) * pace, "flight": BOLT_FLIGHT * pace}

## Plays the shot of one effect, from the card whose trigger caused it to what it hits, in the
## source card's own hit style (see _hit_style_of). Returns the time from t until the shot lands,
## which is when the effect's number pops.
## To add a new style: write a function with the same parameters that returns the same time,
## add a line for it here, and put "hit_fx": "<style name>" in the cards that should use it.
func _effect_hit(style: String, from: Control, to: Control, t: float, col: Color, first_shot: bool) -> float:
	match style:
		"espinho":
			return _thorn_shot(from, to, t, first_shot)
		"corte":
			return _slash_shot(from, to, t, first_shot)
		"boon":
			return _boon_shot(from, to, t, col, first_shot)
	return _effect_bolt(from, to, t, col, first_shot)

## The default hit style: the effect is spat out of its source as a flaming comet that slams into
## its target (a hard, fast shot, not a floating orb):
## 1. wind-up (first shot of a trigger only): the source card pulls back while a hot spark swells on it;
## 2. launch: a muzzle flash and the source card kicks back, away from the target (every shot, like recoil);
## 3. flight: a blunt white-hot head on a nearly straight line, dragging a long flickering tail of
##    flame that sheds embers behind it;
## 4. impact: a sharp flash, spikes of light bursting out where it hits, a quick shockwave and
##    sparks thrown on in the travel direction.
## Follows both ends if they move. Returns the time from t until the comet lands.
func _effect_bolt(from: Control, to: Control, t: float, col: Color, first_shot: bool) -> float:
	var timing := _shot_timing("", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	var rich := _fx_scale >= 0.7 # big chains skip the costliest layers (wide glow, flame flicker)
	var hot := col.lightened(0.6)
	# almost straight, because it is shot hard; a slight random bend keeps a volley from being one line
	var path := _shot_path(from, to, 0.06, 28.0)
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# the lambdas below reach the comet's nodes through this dictionary instead of capturing them:
	# Godot reports an error when a lambda runs after a node it captured was freed (the head is
	# freed on landing, and a table reset frees everything mid-flight)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- the head: a fireball pointing along +x, round and white-hot at the front, tapering into the
	# tail at the back, inside a stretched glow
	var head := Node2D.new()
	head.z_index = 26
	head.visible = false
	if rich:
		var head_glow := _glow_sprite(30.0, Color(col, 0.6))
		head_glow.scale.x *= 1.6
		head.add_child(head_glow)
	var head_points := PackedVector2Array()
	var head_colors := PackedColorArray()
	for i in 9: # the round front: a half circle from the top to the bottom
		var angle := lerpf(-PI / 2.0, PI / 2.0, i / 8.0)
		head_points.append(Vector2.from_angle(angle) * 9.0 + Vector2(4, 0))
		head_colors.append(Color.WHITE if absf(angle) < 0.6 else hot)
	head_points.append(Vector2(-18, 0)) # the back narrows into the tail
	head_colors.append(Color(col, 0.0))
	var head_shape := Polygon2D.new()
	head_shape.polygon = head_points
	head_shape.vertex_colors = head_colors
	head_shape.material = _additive()
	head.add_child(head_shape)
	var head_core := _glow_sprite(10.0, Color.WHITE)
	head_core.position = Vector2(6, 0)
	head.add_child(head_core)
	fx.add_child(head)
	parts["head"] = head

	# --- 1. wind-up (first shot only): the source card pulls back while a spark swells on it
	if first_shot:
		var spark := _glow_sprite(26.0, Color(hot, 0.95))
		spark.z_index = 25
		spark.visible = false
		fx.add_child(spark)
		parts["spark"] = spark
		var st := fx.create_tween()
		st.tween_interval(t)
		st.tween_callback(func():
			var spark_node: Sprite2D = alive.call("spark")
			if spark_node == null:
				return # the table was reset mid-animation
			refresh_ends.call()
			spark_node.position = ends["a"]
			spark_node.visible = true)
		st.tween_property(spark, "scale", spark.scale, charge).from(Vector2.ZERO).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		st.tween_callback(spark.queue_free)
		if from is CardView:
			var windup_card: CardView = from
			var windup := windup_card.create_tween()
			windup.tween_interval(t)
			windup.tween_method(func(k: float):
				var away: Vector2 = (ends["a"] - ends["b"]).normalized()
				windup_card.shake = away * 7.0 * k, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# --- 2. launch: a quick muzzle flash a little in front of the source, and the card kicks back
	var muzzle := _glow_sprite(40.0, Color(hot, 0.95))
	muzzle.z_index = 25
	muzzle.visible = false
	fx.add_child(muzzle)
	parts["muzzle"] = muzzle
	var mt := fx.create_tween()
	mt.tween_interval(launch_t)
	mt.tween_callback(func():
		var muzzle_node: Sprite2D = alive.call("muzzle")
		if muzzle_node == null:
			return
		refresh_ends.call()
		muzzle_node.position = point_at.call(0.04)
		muzzle_node.visible = true)
	mt.tween_property(muzzle, "scale", muzzle.scale * 1.5, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	mt.parallel().tween_property(muzzle, "modulate:a", 0.0, 0.09)
	mt.tween_callback(muzzle.queue_free)
	if from is CardView:
		var source_card: CardView = from
		var kick := source_card.create_tween()
		kick.tween_interval(launch_t)
		kick.tween_method(func(k: float):
			var away: Vector2 = (ends["a"] - ends["b"]).normalized()
			source_card.shake = away * 9.0 * (1.0 - k), 0.0, 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		kick.tween_callback(func(): source_card.shake = Vector2.ZERO)

	# --- 3. flight: two layers of tail behind the head, a wide flickering flame and a thin hot core
	var flame := Line2D.new()
	flame.width = 30.0
	var flame_gradient := Gradient.new()
	flame_gradient.set_color(0, Color(col, 0.0))
	flame_gradient.set_color(1, Color(hot, 0.95))
	flame_gradient.add_point(0.55, Color(col, 0.6))
	flame.gradient = flame_gradient
	var core := Line2D.new()
	core.width = 9.0
	var core_gradient := Gradient.new()
	core_gradient.set_color(0, Color(hot, 0.0))
	core_gradient.set_color(1, Color.WHITE)
	core.gradient = core_gradient
	var tail_width := Curve.new() # a point at the back, as wide as the head at the front
	tail_width.add_point(Vector2(0, 0.0))
	tail_width.add_point(Vector2(0.7, 0.55))
	tail_width.add_point(Vector2(1, 1))
	var tails: Array[Line2D] = [flame, core]
	for tail in tails:
		tail.width_curve = tail_width
		tail.joint_mode = Line2D.LINE_JOINT_ROUND
		tail.end_cap_mode = Line2D.LINE_CAP_ROUND
		tail.material = _additive()
		tail.z_index = 25
		tail.visible = false
		fx.add_child(tail)
	var embers := CPUParticles2D.new()
	embers.emitting = false
	embers.local_coords = false # embers stay where they were dropped, drifting and fading
	embers.amount = maxi(8, int(26 * _fx_scale))
	embers.lifetime = 0.35
	embers.spread = 25.0
	embers.gravity = Vector2(0, 60)
	embers.initial_velocity_min = 40.0
	embers.initial_velocity_max = 150.0
	embers.scale_amount_min = 2.5
	embers.scale_amount_max = 5.5
	var ember_shrink := Curve.new() # embers shrink away instead of popping out
	ember_shrink.add_point(Vector2(0, 1))
	ember_shrink.add_point(Vector2(1, 0))
	embers.scale_amount_curve = ember_shrink
	var ember_ramp := Gradient.new()
	ember_ramp.set_color(0, Color(hot, 1.0))
	ember_ramp.set_color(1, Color(col, 0.0))
	embers.color_ramp = ember_ramp
	embers.material = _additive()
	embers.z_index = 25
	fx.add_child(embers)
	parts["embers"] = embers
	# `head_at` runs from 0 to 1 (fast out of the source, then holding its speed); the tail trails
	# BOLT_TAIL_LENGTH behind it, and after the impact (`collapse` going from 0 to 1) it is pulled in
	var paint := func(head_at: float, collapse: float):
		refresh_ends.call()
		var tail_start := lerpf(clampf(head_at - BOLT_TAIL_LENGTH, 0.0, 1.0), head_at, collapse)
		var tip: Vector2 = point_at.call(head_at)
		var heading: Vector2 = tip - point_at.call(maxf(head_at - 0.03, 0.0))
		var side := heading.orthogonal().normalized()
		var now := Time.get_ticks_msec() / 1000.0
		var core_points := PackedVector2Array()
		var flame_points := PackedVector2Array()
		for j in 16:
			var along := j / 15.0
			var point: Vector2 = point_at.call(lerpf(tail_start, head_at, along))
			core_points.append(point)
			# the flame licks from side to side, more at the back than near the head
			var lick := sin(j * 1.7 - now * 38.0) * 5.0 * (1.0 - along) if rich else 0.0
			flame_points.append(point + side * lick)
		for tail in tails:
			if is_instance_valid(tail):
				tail.visible = true
		if is_instance_valid(flame):
			flame.points = flame_points
		if is_instance_valid(core):
			core.points = core_points
		var head_node: Node2D = alive.call("head")
		if head_node != null:
			head_node.position = tip
			if heading.length() > 0.5:
				head_node.rotation = heading.angle()
		var embers_node: CPUParticles2D = alive.call("embers")
		if embers_node != null:
			embers_node.position = tip
			if heading.length() > 0.5:
				embers_node.direction = -heading.normalized() # thrown off backwards, like sparks off a flare
	var ft := fx.create_tween()
	ft.tween_interval(launch_t)
	ft.tween_callback(func():
		var head_node: Node2D = alive.call("head")
		if head_node != null:
			head_node.visible = true
		var embers_node: CPUParticles2D = alive.call("embers")
		if embers_node != null:
			embers_node.emitting = true)
	ft.tween_method(func(k: float):
		paint.call(ease(k, 0.7), 0.0)
		var head_node: Node2D = alive.call("head")
		if head_node != null:
			# stretched along its path, with a fast flicker like a living flame
			var flicker := 1.0 + 0.12 * sin(k * TAU * 6.0)
			head_node.scale = Vector2(1.5, 0.85) * flicker, 0.0, 1.0, flight)
	ft.tween_callback(func():
		var embers_node: CPUParticles2D = alive.call("embers")
		if embers_node != null:
			embers_node.emitting = false
		var head_node: Node2D = alive.call("head")
		if head_node != null:
			head_node.queue_free())
	ft.tween_method(func(c: float): paint.call(1.0, c), 0.0, 1.0, 0.08)
	ft.tween_callback(func():
		for tail in tails:
			if is_instance_valid(tail):
				tail.queue_free())
	ft.tween_interval(embers.lifetime)
	ft.tween_callback(embers.queue_free)

	# --- 4. impact: a sharp flash, spikes of light, a quick shockwave and sparks thrown on ahead
	var flare := Node2D.new()
	flare.z_index = 27
	flare.visible = false
	flare.add_child(_glow_sprite(58.0, Color(col, 0.9)))
	flare.add_child(_glow_sprite(24.0, Color.WHITE))
	fx.add_child(flare)
	# the spikes point along +x (the travel direction): most burst forward, a few go sideways and back
	var spikes := Node2D.new()
	spikes.z_index = 27
	spikes.visible = false
	for i in 9:
		var angle := randf_range(-1.2, 1.2) if i < 6 else randf_range(1.6, TAU - 1.6)
		var spike := Line2D.new()
		spike.points = PackedVector2Array([Vector2.from_angle(angle) * 10.0, Vector2.from_angle(angle) * randf_range(42.0, 78.0)])
		spike.width = randf_range(3.0, 6.0)
		var spike_width := Curve.new() # thick at the center, sharp at the end
		spike_width.add_point(Vector2(0, 1))
		spike_width.add_point(Vector2(1, 0))
		spike.width_curve = spike_width
		spike.default_color = Color(hot, 1.0)
		spike.material = _additive()
		spikes.add_child(spike)
	fx.add_child(spikes)
	var shock := _ring_line(46.0, 5.0, Color(hot, 0.95))
	shock.z_index = 27
	shock.visible = false
	fx.add_child(shock)
	var burst := CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = maxi(6, int(18 * _fx_scale))
	burst.lifetime = 0.4
	burst.spread = 50.0
	burst.gravity = Vector2(0, 520)
	burst.damping_min = 140.0
	burst.damping_max = 240.0
	burst.initial_velocity_min = 260.0
	burst.initial_velocity_max = 540.0
	burst.scale_amount_min = 2.5
	burst.scale_amount_max = 5.0
	var burst_ramp := Gradient.new()
	burst_ramp.set_color(0, Color.WHITE)
	burst_ramp.set_color(1, Color(col, 0.0))
	burst_ramp.add_point(0.35, Color(hot, 1.0))
	burst.color_ramp = burst_ramp
	burst.material = _additive()
	burst.z_index = 27
	fx.add_child(burst)
	parts["flare"] = flare
	parts["spikes"] = spikes
	parts["shock"] = shock
	parts["burst"] = burst
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var flare_node: Node2D = alive.call("flare")
		var spikes_node: Node2D = alive.call("spikes")
		var shock_node: Line2D = alive.call("shock")
		var burst_node: CPUParticles2D = alive.call("burst")
		if flare_node == null or spikes_node == null or shock_node == null or burst_node == null:
			return
		refresh_ends.call()
		var b: Vector2 = ends["b"]
		var travel: Vector2 = (b - point_at.call(0.85)).normalized()
		flare_node.position = b
		flare_node.scale = Vector2(0.3, 0.3)
		flare_node.visible = true
		spikes_node.position = b
		spikes_node.rotation = travel.angle()
		spikes_node.scale = Vector2(0.3, 0.3)
		spikes_node.visible = true
		shock_node.position = b
		shock_node.scale = Vector2(0.3, 0.3)
		shock_node.visible = true
		burst_node.position = b
		burst_node.direction = travel
		burst_node.emitting = true)
	it.tween_property(flare, "scale", Vector2(1.1, 1.1), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(spikes, "scale", Vector2(1.2, 1.2), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(spikes, "modulate:a", 0.0, 0.16).set_delay(0.04)
	it.parallel().tween_property(shock, "scale", Vector2(1.3, 1.3), 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(shock, "modulate:a", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	it.parallel().tween_property(flare, "modulate:a", 0.0, 0.18).set_delay(0.04)
	it.tween_interval(0.45)
	it.tween_callback(func():
		for key in ["flare", "spikes", "shock", "burst"]:
			var node: Node = alive.call(key)
			if node != null:
				node.queue_free())
	return charge + flight

## The hit style of good effects (heal, buff, summon): instead of being shot at its target, the
## effect is carried to it as a ball of light the eye can follow (a lobbed orb, not a projectile):
## 1. charge: light gathers on the source (a ring closing in on it, a growing orb);
## 2. launch: a soft flash, the source card kicks back, and a soft glow marks the target;
## 3. flight: the orb arcs to the target, stretched along its path, with a short comet tail and embers;
## 4. arrival: a flash, a ring and sparks thrown on in the travel direction.
## Follows both ends if they move. Returns the time from t until the orb lands.
func _boon_shot(from: Control, to: Control, t: float, col: Color, first_shot: bool) -> float:
	var timing := _shot_timing("boon", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var rich := _fx_scale >= 0.7 # big chains skip the costliest layers (wide glow, reticle)
	var hot := col.lightened(0.6)
	# a wide arc, like something lobbed (a straight line reads as a laser)
	var path := _shot_path(from, to, 0.32, 150.0)
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	var target_radius: float = _pose(to)["w"] * 0.6 if to is CardView else 70.0
	# the lambdas below reach the bolt's nodes through this dictionary instead of capturing them:
	# Godot reports an error when a lambda runs after a node it captured was freed (the orb is
	# freed on landing, and a table reset frees everything mid-flight)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- the orb: wide glow, colored body, white-hot core
	var orb := Node2D.new()
	orb.z_index = 26
	orb.visible = false
	if rich:
		orb.add_child(_glow_sprite(46.0, Color(col, 0.55)))
	orb.add_child(_glow_sprite(22.0, col))
	orb.add_child(_glow_sprite(10.0, Color(hot, 1.0)))
	fx.add_child(orb)
	parts["orb"] = orb

	# --- 1. charge: a ring closes in on the source while the orb swells there
	var charge_ring := _ring_line(_pose(from)["w"] * 0.55 if from is CardView else 70.0, 4.0, Color(hot, 0.9))
	charge_ring.z_index = 25
	charge_ring.visible = false
	fx.add_child(charge_ring)
	parts["charge_ring"] = charge_ring
	var ct := fx.create_tween()
	ct.tween_interval(t)
	ct.tween_callback(func():
		var orb_node: Node2D = alive.call("orb")
		var ring_node: Line2D = alive.call("charge_ring")
		if orb_node == null or ring_node == null:
			return # the table was reset mid-animation
		refresh_ends.call()
		ring_node.position = ends["a"]
		ring_node.visible = true
		orb_node.position = ends["a"]
		orb_node.scale = Vector2.ZERO
		orb_node.visible = true)
	ct.tween_property(charge_ring, "scale", Vector2(0.15, 0.15), charge).from(Vector2.ONE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ct.parallel().tween_property(charge_ring, "modulate:a", 1.0, charge * 0.6).from(0.0)
	ct.parallel().tween_property(orb, "scale", Vector2.ONE, charge).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ct.tween_callback(charge_ring.queue_free)

	# --- 2. launch: muzzle flash on the source and a kick back, away from the target
	var launch_t := t + charge
	var muzzle := _glow_sprite(60.0, Color(hot, 0.9))
	muzzle.z_index = 25
	muzzle.visible = false
	fx.add_child(muzzle)
	parts["muzzle"] = muzzle
	var mt := fx.create_tween()
	mt.tween_interval(launch_t)
	mt.tween_callback(func():
		var muzzle_node: Sprite2D = alive.call("muzzle")
		if muzzle_node == null:
			return
		muzzle_node.position = ends["a"]
		muzzle_node.visible = true)
	mt.tween_property(muzzle, "scale", muzzle.scale * 1.6, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	mt.parallel().tween_property(muzzle, "modulate:a", 0.0, 0.16)
	mt.tween_callback(muzzle.queue_free)
	if from is CardView:
		var cv: CardView = from
		var kick := cv.create_tween()
		kick.tween_interval(launch_t)
		kick.tween_method(func(k: float):
			var away: Vector2 = (ends["a"] - ends["b"]).normalized()
			cv.shake = away * 10.0 * (1.0 - k), 0.0, 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		kick.tween_callback(func(): cv.shake = Vector2.ZERO)

	# lock-on reticle: four brackets that close in on the target and spin while the orb is on its way
	# target mark: a soft glow with a thin ring that settles on the target while the orb is on its way
	var reticle: Node2D = null
	if rich:
		reticle = Node2D.new()
		reticle.z_index = 25
		reticle.visible = false
		reticle.modulate.a = 0.0
		reticle.add_child(_glow_sprite(target_radius, Color(col, 0.35)))
		reticle.add_child(_ring_line(target_radius * 0.85, 3.0, Color(hot, 0.7)))
		fx.add_child(reticle)
		parts["reticle"] = reticle
		var rt := fx.create_tween()
		rt.tween_interval(launch_t)
		rt.tween_callback(func():
			var reticle_node: Node2D = alive.call("reticle")
			if reticle_node == null:
				return
			reticle_node.position = ends["b"]
			reticle_node.visible = true)
		rt.tween_property(reticle, "modulate:a", 1.0, flight * 0.5)
		rt.parallel().tween_property(reticle, "scale", Vector2.ONE, flight).from(Vector2(1.4, 1.4)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# on impact the mark swells outward and vanishes
		rt.tween_property(reticle, "scale", Vector2(1.35, 1.35), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rt.parallel().tween_property(reticle, "modulate:a", 0.0, 0.16)
		rt.tween_callback(reticle.queue_free)

	# --- 3. flight: a short comet tail right behind the orb, plus embers it sheds along the way
	var tails: Array[Line2D] = []
	var tail := Line2D.new()
	tail.width = 18.0
	tail.joint_mode = Line2D.LINE_JOINT_ROUND
	tail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	tail.end_cap_mode = Line2D.LINE_CAP_ROUND
	var tail_gradient := Gradient.new()
	tail_gradient.set_color(0, Color(col, 0.0))
	tail_gradient.set_color(1, Color(hot, 0.9))
	tail.gradient = tail_gradient
	var tail_width := Curve.new() # pointed at the back, as wide as the orb at the front
	tail_width.add_point(Vector2(0, 0.0))
	tail_width.add_point(Vector2(1, 1))
	tail.width_curve = tail_width
	tail.material = _additive()
	tail.z_index = 25
	tail.visible = false
	fx.add_child(tail)
	tails.append(tail)
	var sparks := CPUParticles2D.new()
	sparks.emitting = false
	sparks.local_coords = false # embers stay where they were dropped, drifting and fading
	sparks.amount = maxi(10, int(40 * _fx_scale))
	sparks.lifetime = 0.5
	sparks.spread = 180.0
	sparks.gravity = Vector2(0, 40)
	sparks.initial_velocity_min = 15.0
	sparks.initial_velocity_max = 70.0
	sparks.scale_amount_min = 3.0
	sparks.scale_amount_max = 7.0
	var ember_shrink := Curve.new() # embers shrink away instead of popping out
	ember_shrink.add_point(Vector2(0, 1))
	ember_shrink.add_point(Vector2(1, 0))
	sparks.scale_amount_curve = ember_shrink
	var spark_ramp := Gradient.new()
	spark_ramp.set_color(0, Color(hot, 1.0))
	spark_ramp.set_color(1, Color(col, 0.0))
	sparks.color_ramp = spark_ramp
	sparks.material = _additive()
	sparks.z_index = 25
	fx.add_child(sparks)
	parts["sparks"] = sparks
	# `head` runs from 0 to 1, speeding up; the tail trails just 0.12 behind it (a long tail reads
	# as a beam), and after the impact (`collapse` going from 0 to 1) it is pulled into the target
	var paint := func(head: float, collapse: float):
		refresh_ends.call()
		var tail_start := clampf(head - 0.12, 0.0, 1.0)
		tail_start = lerpf(tail_start, head, collapse)
		var pts := PackedVector2Array()
		for j in 13:
			pts.append(point_at.call(lerpf(tail_start, head, j / 12.0)))
		for ln in tails:
			if is_instance_valid(ln):
				ln.visible = true
				ln.points = pts
		var tip: Vector2 = point_at.call(head)
		var orb_node: Node2D = alive.call("orb")
		if orb_node != null:
			orb_node.position = tip
			# turn the orb along its path, so its stretch points where it is going
			var heading: Vector2 = tip - point_at.call(maxf(head - 0.03, 0.0))
			if heading.length() > 0.5:
				orb_node.rotation = heading.angle()
		var sparks_node: CPUParticles2D = alive.call("sparks")
		if sparks_node != null:
			sparks_node.position = tip
		var reticle_node: Node2D = alive.call("reticle")
		if reticle_node != null:
			reticle_node.position = ends["b"]
	var ft := fx.create_tween()
	ft.tween_interval(launch_t)
	ft.tween_callback(func():
		var sparks_node: CPUParticles2D = alive.call("sparks")
		if sparks_node != null:
			sparks_node.emitting = true)
	ft.tween_method(func(k: float):
		paint.call(ease(k, 1.4), 0.0)
		var orb_node: Node2D = alive.call("orb")
		if orb_node != null:
			# stretched along the path (squash and stretch) with a quick flicker, like a living flame
			var flicker := 1.0 + 0.1 * sin(k * TAU * 5.0)
			orb_node.scale = Vector2(1.35, 0.8) * flicker, 0.0, 1.0, flight)
	ft.tween_callback(func():
		var sparks_node: CPUParticles2D = alive.call("sparks")
		if sparks_node != null:
			sparks_node.emitting = false
		var orb_node: Node2D = alive.call("orb")
		if orb_node != null:
			orb_node.queue_free())
	ft.tween_method(func(c: float): paint.call(1.0, c), 0.0, 1.0, 0.12)
	ft.tween_callback(func():
		for ln in tails:
			if is_instance_valid(ln):
				ln.queue_free())
	ft.tween_interval(sparks.lifetime)
	ft.tween_callback(sparks.queue_free)

	# --- 4. impact: a round flash, shockwave ring, sparks thrown on along the travel direction
	var impact_t := launch_t + flight
	var flare := Node2D.new()
	flare.z_index = 27
	flare.visible = false
	flare.add_child(_glow_sprite(70.0, Color(col, 0.9)))
	flare.add_child(_glow_sprite(30.0, Color(hot, 1.0)))
	fx.add_child(flare)
	var shock := _ring_line(64.0, 6.0, Color(hot, 0.95))
	shock.z_index = 27
	shock.visible = false
	fx.add_child(shock)
	var burst := CPUParticles2D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = maxi(8, int(22 * _fx_scale))
	burst.lifetime = 0.5
	burst.spread = 55.0
	burst.gravity = Vector2(0, 520)
	burst.damping_min = 120.0
	burst.damping_max = 220.0
	burst.initial_velocity_min = 220.0
	burst.initial_velocity_max = 480.0
	burst.scale_amount_min = 2.5
	burst.scale_amount_max = 5.0
	var burst_ramp := Gradient.new()
	burst_ramp.set_color(0, Color.WHITE)
	burst_ramp.set_color(1, Color(col, 0.0))
	burst_ramp.add_point(0.35, Color(hot, 1.0))
	burst.color_ramp = burst_ramp
	burst.material = _additive()
	burst.z_index = 27
	fx.add_child(burst)
	parts["flare"] = flare
	parts["shock"] = shock
	parts["burst"] = burst
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var flare_node: Node2D = alive.call("flare")
		var shock_node: Line2D = alive.call("shock")
		var burst_node: CPUParticles2D = alive.call("burst")
		if flare_node == null or shock_node == null or burst_node == null:
			return
		refresh_ends.call()
		var b: Vector2 = ends["b"]
		var travel: Vector2 = (b - point_at.call(0.85)).normalized()
		flare_node.position = b
		flare_node.rotation = travel.angle()
		flare_node.scale = Vector2(0.35, 0.35)
		flare_node.visible = true
		shock_node.position = b
		shock_node.scale = Vector2(0.25, 0.25)
		shock_node.visible = true
		burst_node.position = b
		burst_node.direction = travel
		burst_node.emitting = true)
	it.tween_property(flare, "scale", Vector2(1.25, 1.25), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(shock, "scale", Vector2(1.4, 1.4), 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(shock, "modulate:a", 0.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	it.parallel().tween_property(flare, "modulate:a", 0.0, 0.26).set_delay(0.06)
	it.tween_interval(0.5)
	it.tween_callback(func():
		for key in ["flare", "shock", "burst"]:
			var node: Node = alive.call(key)
			if node != null:
				node.queue_free())
	return charge + flight


## Timing of the "espinho" hit style (see _thorn_shot): the plant rears back a little longer on
## its first spit so the eye finds it, then fires the rest quickly; thorns fly faster than bolts.
const THORN_CHARGE_FIRST := 0.16
const THORN_CHARGE_NEXT := 0.06
const THORN_FLIGHT := 0.22
## How long a thorn stays stuck in its target (quivering, then still) before it drops off.
const THORN_STUCK_TIME := 0.55
## Colors of the Flor Voraz's thorns (taken from its art): crimson at the base, cream at the tip.
const THORN_BASE_COLOR := Color("#8e1b1f")
const THORN_TIP_COLOR := Color("#f4e6b0")
const THORN_OUTLINE_COLOR := Color("#2a0607")
const POLLEN_COLOR := Color("#e8f07a")
const SAP_COLOR := Color("#7fd04a")

## The "espinho" hit style: the source plant spits a thorn that sticks in its target.
## 1. rear back: the source card leans away from the target (anticipation);
## 2. spit: it snaps forward, throwing a puff of pollen toward the target;
## 3. flight: a crimson-and-cream thorn flies fast on a slight arc, pointing where it goes;
## 4. impact: the thorn sinks its tip in (a bit off-center, so a volley of thorns spreads over the
##    target instead of piling on one spot), quivers, splashes sap and drops off a moment later.
## Follows both ends if they move. Returns the time from t until the thorn lands.
func _thorn_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("espinho", first_shot)
	var charge: float = timing["charge"]
	var flight: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + flight
	# a thorn is thrown hard, so its arc is much flatter than a bolt's
	var path := _shot_path(from, to, 0.12, 60.0)
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	var point_at: Callable = path["point_at"]
	# where on the target this thorn sticks, relative to the target's center
	var stick_offset := Vector2(randf_range(-18.0, 18.0), randf_range(-18.0, 18.0))
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	# (same reason as in _effect_bolt: the nodes may be freed while a lambda is still scheduled)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- the thorn: a narrow spike pointing along +x, crimson base fading to a cream tip, with a
	# dark outline and a faint red glow behind it so it reads on a small phone screen
	var thorn := Node2D.new()
	thorn.z_index = 26
	thorn.visible = false
	thorn.scale = Vector2(1.25, 1.25)
	thorn.add_child(_glow_sprite(20.0, Color(THORN_BASE_COLOR.lightened(0.3), 0.45)))
	var spike_points := PackedVector2Array([Vector2(22, 0), Vector2(-12, -5.5), Vector2(-17, 0), Vector2(-12, 5.5)])
	var spike := Polygon2D.new()
	spike.polygon = spike_points
	spike.vertex_colors = PackedColorArray([THORN_TIP_COLOR, THORN_BASE_COLOR, THORN_BASE_COLOR.darkened(0.3), THORN_BASE_COLOR])
	thorn.add_child(spike)
	var outline := Line2D.new()
	outline.points = spike_points
	outline.closed = true
	outline.width = 1.6
	outline.default_color = THORN_OUTLINE_COLOR
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	thorn.add_child(outline)
	fx.add_child(thorn)
	parts["thorn"] = thorn
	# how far the thorn's center sits back from its tip (so the tip, not the middle, goes in)
	var tip_length := 22.0 * thorn.scale.x * 0.55

	# --- 1 and 2. rear back, then snap forward toward the target as the thorn leaves
	if from is CardView:
		var cv: CardView = from
		var lunge := cv.create_tween()
		lunge.tween_interval(t)
		lunge.tween_method(func(k: float):
			var away: Vector2 = (ends["a"] - ends["b"]).normalized()
			cv.shake = away * 9.0 * k, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_method(func(k: float):
			var toward: Vector2 = (ends["b"] - ends["a"]).normalized()
			cv.shake = toward * 12.0 * (1.0 - k), 0.0, 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_callback(func(): cv.shake = Vector2.ZERO)
	var pollen := CPUParticles2D.new()
	pollen.emitting = false
	pollen.one_shot = true
	pollen.explosiveness = 0.9
	pollen.local_coords = false
	pollen.amount = maxi(6, int(16 * _fx_scale))
	pollen.lifetime = 0.55
	pollen.spread = 35.0
	pollen.gravity = Vector2(0, 30)
	pollen.damping_min = 180.0
	pollen.damping_max = 260.0
	pollen.initial_velocity_min = 80.0
	pollen.initial_velocity_max = 230.0
	pollen.scale_amount_min = 3.0
	pollen.scale_amount_max = 6.5
	var pollen_ramp := Gradient.new()
	pollen_ramp.set_color(0, Color(POLLEN_COLOR, 0.95))
	pollen_ramp.set_color(1, Color(SAP_COLOR, 0.0))
	pollen.color_ramp = pollen_ramp
	pollen.z_index = 25
	fx.add_child(pollen)
	parts["pollen"] = pollen
	var pt := fx.create_tween()
	pt.tween_interval(launch_t)
	pt.tween_callback(func():
		var pollen_node: CPUParticles2D = alive.call("pollen")
		if pollen_node == null:
			return # the table was reset mid-animation
		refresh_ends.call()
		pollen_node.position = ends["a"]
		pollen_node.direction = (ends["b"] - ends["a"]).normalized()
		pollen_node.emitting = true)
	pt.tween_interval(pollen.lifetime + 0.1)
	pt.tween_callback(func():
		var pollen_node: Node = alive.call("pollen")
		if pollen_node != null:
			pollen_node.queue_free())

	# --- 3. flight: the thorn flies along the path, turned the way it is going, with a short streak
	var streak := Line2D.new()
	streak.width = 5.0
	var streak_gradient := Gradient.new()
	streak_gradient.set_color(0, Color(THORN_BASE_COLOR, 0.0))
	streak_gradient.set_color(1, Color(THORN_TIP_COLOR, 0.55))
	streak.gradient = streak_gradient
	var streak_width := Curve.new() # pointed at the back
	streak_width.add_point(Vector2(0, 0.0))
	streak_width.add_point(Vector2(1, 1))
	streak.width_curve = streak_width
	streak.z_index = 25
	streak.visible = false
	fx.add_child(streak)
	parts["streak"] = streak
	var ft := fx.create_tween()
	ft.tween_interval(launch_t)
	ft.tween_method(func(k: float):
		refresh_ends.call()
		var head := ease(k, 1.2) # speeds up a little, like a dart
		var thorn_node: Node2D = alive.call("thorn")
		if thorn_node == null:
			return
		var tip: Vector2 = point_at.call(head)
		var heading: Vector2 = tip - point_at.call(maxf(head - 0.03, 0.0))
		if heading.length() > 0.5:
			thorn_node.rotation = heading.angle()
		thorn_node.position = tip
		thorn_node.visible = true
		var streak_node: Line2D = alive.call("streak")
		if streak_node != null:
			var streak_points := PackedVector2Array()
			var streak_start := maxf(head - 0.08, 0.0)
			for j in 7:
				streak_points.append(point_at.call(lerpf(streak_start, head, j / 6.0)))
			streak_node.points = streak_points
			streak_node.visible = true, 0.0, 1.0, flight)
	ft.tween_callback(func():
		var streak_node: Node = alive.call("streak")
		if streak_node != null:
			streak_node.queue_free())

	# --- 4. impact: a small flash, sap splashing back out, and the thorn stuck in and quivering
	var flash := _glow_sprite(34.0, Color(THORN_TIP_COLOR, 0.85))
	flash.z_index = 27
	flash.visible = false
	fx.add_child(flash)
	parts["flash"] = flash
	var sap := CPUParticles2D.new()
	sap.emitting = false
	sap.one_shot = true
	sap.explosiveness = 1.0
	sap.local_coords = false
	sap.amount = maxi(6, int(14 * _fx_scale))
	sap.lifetime = 0.5
	sap.spread = 60.0
	sap.gravity = Vector2(0, 620)
	sap.damping_min = 60.0
	sap.damping_max = 120.0
	sap.initial_velocity_min = 120.0
	sap.initial_velocity_max = 300.0
	sap.scale_amount_min = 2.5
	sap.scale_amount_max = 5.5
	# each droplet is either green sap or (less often) a red bit of the thorn, never a mix of both
	var droplet_colors := Gradient.new()
	droplet_colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	droplet_colors.set_color(0, SAP_COLOR)
	droplet_colors.set_color(1, THORN_BASE_COLOR.lightened(0.15))
	droplet_colors.set_offset(1, 0.7)
	sap.color_initial_ramp = droplet_colors
	var sap_fade := Gradient.new()
	sap_fade.set_color(0, Color.WHITE)
	sap_fade.set_color(1, Color(1, 1, 1, 0))
	sap.color_ramp = sap_fade
	sap.z_index = 27
	fx.add_child(sap)
	parts["sap"] = sap
	# where the thorn is stuck right now (it follows the target if the target moves)
	var stuck_spot := func() -> Vector2:
		return ends["b"] + stick_offset
	# the angle the thorn went in at, set on impact (a dictionary so the lambdas can change it)
	var stuck_angle := {"value": 0.0}
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var flash_node: Sprite2D = alive.call("flash")
		var sap_node: CPUParticles2D = alive.call("sap")
		if flash_node == null or sap_node == null:
			return
		refresh_ends.call()
		var hit_point: Vector2 = stuck_spot.call()
		var travel: Vector2 = (ends["b"] - point_at.call(0.85)).normalized()
		flash_node.position = hit_point
		flash_node.scale *= 0.4
		flash_node.visible = true
		sap_node.position = hit_point
		sap_node.direction = -travel # sap squirts back out the way the thorn came in
		sap_node.emitting = true
		stuck_angle["value"] = travel.angle()
		var thorn_node: Node2D = alive.call("thorn")
		if thorn_node != null:
			thorn_node.rotation = travel.angle()
			thorn_node.position = hit_point - travel * tip_length)
	it.tween_property(flash, "scale", flash.scale * 1.1, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	it.parallel().tween_property(flash, "modulate:a", 0.0, 0.18).set_delay(0.04)
	# stuck: the thorn quivers (fast at first, dying down) and stays on the target if it moves
	it.parallel().tween_method(func(k: float):
		refresh_ends.call()
		var thorn_node: Node2D = alive.call("thorn")
		if thorn_node == null:
			return
		var quiver := deg_to_rad(9.0) * sin(k * TAU * 4.0) * pow(1.0 - k, 2.0)
		thorn_node.rotation = stuck_angle["value"] + quiver
		thorn_node.position = stuck_spot.call() - Vector2.from_angle(stuck_angle["value"]) * tip_length, 0.0, 1.0, THORN_STUCK_TIME)
	# then it drops off: falls, tips over and fades
	it.tween_method(func(k: float):
		var thorn_node: Node2D = alive.call("thorn")
		if thorn_node == null:
			return
		var resting: Vector2 = stuck_spot.call() - Vector2.from_angle(stuck_angle["value"]) * tip_length
		thorn_node.position = resting + Vector2(0, 46.0 * k * k)
		thorn_node.rotation = stuck_angle["value"] + 0.9 * k
		thorn_node.modulate.a = 1.0 - k, 0.0, 1.0, 0.35)
	it.tween_callback(func():
		for key in ["thorn", "flash", "sap"]:
			var node: Node = alive.call(key)
			if node != null:
				node.queue_free())
	return charge + flight

## Timing of the "corte" hit style (see _slash_shot): the blade-wielder gathers herself a little before
## her first strike, then cuts one target after another without pausing; the dash to the target is
## almost instant, because a blow with a sword has no projectile to follow.
const SLASH_CHARGE_FIRST := 0.14
const SLASH_CHARGE_NEXT := 0.0
const SLASH_DASH := 0.05
## How long one cut takes to be drawn across its target, and how long it takes to fade afterwards.
const SLASH_SWEEP_TIME := 0.07
const SLASH_FADE_TIME := 0.3
## Colors of the cuts: a white-hot core, steel-blue edges and warm sparks flying off the blade.
const SLASH_CORE_COLOR := Color("#ffffff")
const SLASH_EDGE_COLOR := Color("#8fc4ff")
const SLASH_SPARK_COLOR := Color("#ffe8b0")

## The "corte" hit style, for sword fighters (no magic, so nothing flies out of them):
## 1. gather (first strike of a trigger only): the source card pulls back while a steel glint swells on it;
## 2. dash: the card snaps toward its target and a thin, fast trail of air links the two;
## 3. impact: two crossing cuts are drawn across the target (an X, a different angle every time, so a
##    volley over several targets never repeats itself), with a flash and sparks thrown along the blade.
## Follows both ends if they move. Returns the time from t until the cut lands.
func _slash_shot(from: Control, to: Control, t: float, first_shot: bool) -> float:
	var timing := _shot_timing("corte", first_shot)
	var charge: float = timing["charge"]
	var dash: float = timing["flight"]
	var launch_t := t + charge
	var impact_t := launch_t + dash
	var rich := _fx_scale >= 0.7 # big chains skip the costliest layers (wide glow, second cut)
	var path := _shot_path(from, to, 0.0, 0.0) # a straight line: the dash does not bow
	var ends: Dictionary = path["ends"]
	var refresh_ends: Callable = path["refresh"]
	# a cut is about as long as the target is big, and lands a little off-center so cuts do not pile up
	var target_extent := to.size * to.scale
	var cut_length := clampf(maxf(target_extent.x, target_extent.y) * 0.9, 120.0, 240.0)
	var cut_offset := Vector2(randf_range(-10.0, 10.0), randf_range(-10.0, 10.0))
	# the lambdas below reach the shot's nodes through this dictionary instead of capturing them
	# (same reason as in _effect_bolt: the nodes may be freed while a lambda is still scheduled)
	var parts := {}
	var alive := func(key: String) -> Node:
		var node = parts.get(key)
		return node if is_instance_valid(node) else null

	# --- 1. gather: the source leans away from the target while a steel glint swells on it
	if first_shot:
		var glint := _glow_sprite(24.0, Color(SLASH_EDGE_COLOR.lightened(0.5), 0.95))
		glint.z_index = 25
		glint.visible = false
		fx.add_child(glint)
		parts["glint"] = glint
		var gt := fx.create_tween()
		gt.tween_interval(t)
		gt.tween_callback(func():
			var glint_node: Sprite2D = alive.call("glint")
			if glint_node == null:
				return # the table was reset mid-animation
			refresh_ends.call()
			glint_node.position = ends["a"]
			glint_node.visible = true)
		gt.tween_property(glint, "scale", glint.scale, charge).from(Vector2.ZERO).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		gt.tween_callback(glint.queue_free)

	# --- 2. dash: the source card snaps toward the target
	if from is CardView:
		var source_card: CardView = from
		var lunge := source_card.create_tween()
		lunge.tween_interval(t)
		if first_shot:
			lunge.tween_method(func(k: float):
				var away: Vector2 = (ends["a"] - ends["b"]).normalized()
				source_card.shake = away * 8.0 * k, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_method(func(k: float):
			var toward: Vector2 = (ends["b"] - ends["a"]).normalized()
			source_card.shake = toward * 16.0 * (1.0 - k), 0.0, 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_callback(func(): source_card.shake = Vector2.ZERO)
	var trail := Line2D.new()
	trail.width = 3.0
	trail.material = _additive()
	var trail_gradient := Gradient.new()
	trail_gradient.set_color(0, Color(SLASH_EDGE_COLOR, 0.0))
	trail_gradient.set_color(1, Color(SLASH_CORE_COLOR, 0.7))
	trail.gradient = trail_gradient
	trail.z_index = 25
	trail.visible = false
	fx.add_child(trail)
	parts["trail"] = trail
	var trail_tween := fx.create_tween()
	trail_tween.tween_interval(launch_t)
	trail_tween.tween_callback(func():
		var trail_node: Line2D = alive.call("trail")
		if trail_node == null:
			return
		refresh_ends.call()
		trail_node.points = PackedVector2Array([ends["a"], ends["b"]])
		trail_node.visible = true)
	trail_tween.tween_property(trail, "modulate:a", 0.0, dash + 0.12).from(1.0)
	trail_tween.tween_callback(func():
		var trail_node: Node = alive.call("trail")
		if trail_node != null:
			trail_node.queue_free())

	# --- 3. impact: the cuts, the flash and the sparks all live in one holder, freed together
	var cuts_holder := Node2D.new()
	cuts_holder.z_index = 27
	fx.add_child(cuts_holder)
	parts["cuts"] = cuts_holder
	var it := fx.create_tween()
	it.tween_interval(impact_t)
	it.tween_callback(func():
		var holder: Node2D = alive.call("cuts")
		if holder == null:
			return
		refresh_ends.call()
		var center: Vector2 = ends["b"] + cut_offset
		# a diagonal stroke, tilted a different amount (and leaning either way) on every blow
		var first_direction := Vector2.from_angle(deg_to_rad(randf_range(25.0, 60.0)))
		if randf() < 0.5:
			first_direction.x = -first_direction.x
		_add_slash_cut(holder, center, first_direction, cut_length, 0.0, rich)
		if rich:
			# the second cut crosses the first one, a little shorter and a moment later
			var second_direction := Vector2(-first_direction.x, first_direction.y).rotated(deg_to_rad(randf_range(-12.0, 12.0)))
			_add_slash_cut(holder, center, second_direction, cut_length * 0.8, 0.05, rich)
		var flash := _glow_sprite(46.0, Color(SLASH_CORE_COLOR, 0.8))
		flash.position = center
		holder.add_child(flash)
		var flash_tween := flash.create_tween()
		flash_tween.tween_property(flash, "scale", flash.scale * 1.1, 0.09).from(flash.scale * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		flash_tween.parallel().tween_property(flash, "modulate:a", 0.0, 0.2).set_delay(0.04)
		var sparks := CPUParticles2D.new()
		sparks.emitting = false
		sparks.one_shot = true
		sparks.explosiveness = 1.0
		sparks.local_coords = false
		sparks.amount = maxi(5, int(12 * _fx_scale))
		sparks.lifetime = 0.4
		sparks.direction = first_direction
		sparks.spread = 70.0
		sparks.gravity = Vector2(0, 400)
		sparks.damping_min = 80.0
		sparks.damping_max = 160.0
		sparks.initial_velocity_min = 140.0
		sparks.initial_velocity_max = 380.0
		sparks.scale_amount_min = 2.0
		sparks.scale_amount_max = 4.0
		var spark_ramp := Gradient.new()
		spark_ramp.set_color(0, Color(SLASH_SPARK_COLOR, 0.95))
		spark_ramp.set_color(1, Color(SLASH_EDGE_COLOR, 0.0))
		sparks.color_ramp = spark_ramp
		sparks.position = center
		holder.add_child(sparks)
		sparks.emitting = true
		# everything of this blow is gone once the last cut has faded and the sparks have fallen
		var cleanup := holder.create_tween()
		cleanup.tween_interval(0.05 + SLASH_SWEEP_TIME + SLASH_FADE_TIME + 0.3)
		cleanup.tween_callback(holder.queue_free))
	return charge + dash

## One cut of the "corte" hit style, drawn across a target after `delay` seconds: a stroke that is
## swept from one end to the other in a blink, pointed at both ends, then thins out and fades.
## `direction` is the way the blade travels, `center` the middle of the stroke.
func _add_slash_cut(holder: Node2D, center: Vector2, direction: Vector2, length: float, delay: float, rich: bool) -> void:
	var start := center - direction * length / 2.0
	var finish := center + direction * length / 2.0
	# the blade swings in a slight arc, bowed to a random side
	var bowed_middle := center + direction.orthogonal() * length * 0.12 * (1.0 if randf() < 0.5 else -1.0)
	var point_on_cut := func(u: float) -> Vector2:
		return start.lerp(bowed_middle, u).lerp(bowed_middle.lerp(finish, u), u)
	var pointed_ends := Curve.new()
	pointed_ends.add_point(Vector2(0.0, 0.05))
	pointed_ends.add_point(Vector2(0.5, 1.0))
	pointed_ends.add_point(Vector2(1.0, 0.05))
	var cut := Node2D.new()
	cut.visible = false
	holder.add_child(cut)
	var edge: Line2D = null
	if rich:
		edge = Line2D.new()
		edge.width = 16.0
		edge.default_color = Color(SLASH_EDGE_COLOR, 0.55)
		edge.width_curve = pointed_ends
		edge.material = _additive()
		cut.add_child(edge)
	var core := Line2D.new()
	core.width = 6.0
	core.default_color = SLASH_CORE_COLOR
	core.width_curve = pointed_ends
	core.material = _additive()
	cut.add_child(core)
	# these lambdas only touch nodes that are children of `cut`, which also owns the tween: both end together
	var cut_tween := cut.create_tween()
	cut_tween.tween_interval(delay)
	cut_tween.tween_callback(func(): cut.visible = true)
	cut_tween.tween_method(func(k: float):
		var head := ease(k, 0.4) # the stroke starts fast and slows into the end of the swing
		var points := PackedVector2Array()
		for step in 9:
			points.append(point_on_cut.call(head * step / 8.0))
		core.points = points
		if edge != null:
			edge.points = points, 0.0, 1.0, SLASH_SWEEP_TIME)
	cut_tween.tween_property(cut, "modulate:a", 0.0, SLASH_FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	cut_tween.parallel().tween_property(core, "width", 1.0, SLASH_FADE_TIME)
	if edge != null:
		cut_tween.parallel().tween_property(edge, "width", 3.0, SLASH_FADE_TIME)

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
	_fx_chain_scale = 1.0 / maxf(1.0, (bursts + _count_ghosts(old)) / 3.0)
	_fx_scale = _fx_chain_scale * GraphicsQuality.effect_detail
	var actors := views.duplicate()
	var ghosts: Array = []
	var exiled := {} ## uids banished by these events: they get the banish effect, not the death dissolve
	var special_relic_exit_uids := {} ## relics whose dedicated event already animates their exit
	for e in events:
		if e["type"] == "banish":
			exiled[e["uid"]] = true
		elif e["type"] == "lethal_ward":
			special_relic_exit_uids[int(e["uid"])] = true
		elif e["type"] == "death_prevented":
			special_relic_exit_uids[int(e["ward_uid"])] = true
	var ghost_exiled: Array = [] ## parallel to ghosts
	for k in old:
		if k is int and k > 0 and not views.has(k) and not old[k]["hand"] and old[k]["inst"].has("damage"):
			var gh := _ghost(old[k]["card_id"], old[k]["inst"], old[k]["pose"])
			actors[k] = gh
			ghosts.append(gh)
			ghost_exiled.append(exiled.has(k))
	# A unit summoned and killed inside the same batch (the Fantoche de Trapos taking a blow in Hikari's
	# place) is neither in `old` nor on the re-rendered table, so nothing would show it. Give it a ghost
	# standing in the next free cell of its owner's lane: it pops in at its "summon" event, takes the
	# hit like any unit, and dissolves at its "death" event.
	var died_uids := {}
	for e in events:
		if e["type"] == "death":
			died_uids[e["uid"]] = true
	var short_lived := {} ## uid -> ghost of a unit that lives and dies inside this batch
	var short_lived_per_player := {}
	var dissolved_early := {} ## ghosts already dissolved at their death (the settle loop skips them)
	for e in events:
		if e["type"] != "summon" or not died_uids.has(e["uid"]) or views.has(e["uid"]) or old.has(e["uid"]) or short_lived.has(e["uid"]):
			continue
		var owner_player: int = e["player"]
		var lane_index: int = _laid_out_slots(owner_player) + int(short_lived_per_player.get(owner_player, 0))
		short_lived_per_player[owner_player] = int(short_lived_per_player.get(owner_player, 0)) + 1
		var lane_cell := _board_cell(lane_index + 1, lane_index)
		var lane_y := 460.0 if owner_player == viewer else 172.0
		var short_ghost := _ghost(e["card_id"], {}, {"c": Vector2.ZERO, "rot": 0.0, "w": 1.0})
		_apply_pose(short_ghost, {"c": Vector2(roundf(lane_cell.x + lane_cell.y / 2.0), roundf(lane_y) + short_ghost.size.y / 2.0), "rot": 0.0, "w": short_ghost.size.x})
		short_ghost.scale = Vector2.ZERO # hidden until its summon event pops it in
		short_ghost.z_index = 20
		actors[e["uid"]] = short_ghost
		short_lived[e["uid"]] = short_ghost
		ghosts.append(short_ghost)
		ghost_exiled.append(false)
	var cursor := 0.0
	var handled := {}
	var appear := {}
	var placed_uids := {} ## units whose "card placed" sound already played with their "play" event
	var in_combat := false
	var last_src := 0
	var last_dst := 0
	var hit_t := 0.0
	var trig_src := 0 ## unit whose trigger caused the events that follow (0 = none)
	var trig_shots := 0 ## bolts that trigger already fired (only the first one charges up slowly)
	var volley_land_t := 0.0 ## when the trigger's last shot lands (the next one follows VOLLEY_GAP later)
	var fatigue_pending := false ## a Fadiga was just announced: the Leader hit that follows is the game's rule, not a card's effect
	# Leader HP: _render drew the final value, so rewind it to what it was before these events
	# and step it down/up at each hit's moment instead of jumping straight to the end.
	var leader_hp := {}
	for e in events:
		if e["type"] == "leader_executed" and views.get(e["uid"]) is LeaderView:
			# the execution animation drains the HP itself, so only rewind it to the value before the kill
			if not leader_hp.has(e["uid"]):
				leader_hp[e["uid"]] = views[e["uid"]].hp
			leader_hp[e["uid"]] += int(e["hp_before"])
		elif e["type"] in ["damage", "heal"] and e["uid"] < 0 and views.get(e["uid"]) is LeaderView:
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
		# a new action or a blow from some other unit ends the trigger's chain of effects
		# (damage the trigger's own unit deals outside combat still belongs to the trigger)
		if et in ["play", "ability", "passive", "resolve", "attack", "combat_damage", "start_turn", "end_turn"] \
				or (et in ["damage", "shield_break"] and e.get("src", 0) > 0 and (in_combat or e["src"] != trig_src)):
			trig_src = 0
		# Fadiga damage has no source card even when a trigger's draw caused it, so no bolt flies for it.
		# Only the hit right after the "fatigue" event counts (a Leader guard may come between them).
		var is_fatigue_hit := fatigue_pending and et == "damage"
		if et == "fatigue":
			fatigue_pending = true
		elif et != "leader_guard":
			fatigue_pending = false
		# effects of a trigger fly out of their source as a bolt and land when it arrives
		if trig_src != 0 and not is_fatigue_hit and et in ["damage", "heal", "shield_break", "buff", "dot", "freeze", "exhaust", "stun", "condemn", "tide_mark", "magic_shield_break", "supreme_shield_break", "summon"] \
				and e["uid"] != trig_src and actors.has(trig_src) and actors.has(e["uid"]):
			# good effects are carried over as an orb; everything else is fired in the source's own style
			var hit_style := "boon" if _is_boon_event(e) else _hit_style_of(actors[trig_src])
			var first_shot := trig_shots == 0
			var timing := _shot_timing(hit_style, first_shot)
			var shot_time: float = timing["charge"] + timing["flight"]
			var land_t := cursor + shot_time
			if hit_style == "boon":
				land_t -= 0.02 # orbs go one after the other, never in a burst like the shots
			elif not first_shot:
				# rapid fire: this shot lands VOLLEY_GAP after the previous one, so it is already in the
				# air while that one hits. Only something slower than a plain hit in between (each hit
				# moves the cursor 0.12 on) holds it back.
				land_t = maxf(volley_land_t + VOLLEY_GAP, cursor - 0.12)
			_effect_hit(hit_style, actors[trig_src], actors[e["uid"]], land_t - shot_time, _bolt_color(e), first_shot)
			volley_land_t = land_t
			cursor = land_t
			trig_shots += 1
		# Sound: most events play theirs right here, at the moment their animation starts. The ones
		# below time their own: hits and heals land at `t` (after the lunge), deaths and banishes play
		# with the dissolve at the end, and a played card makes its sound when it lands.
		# both players mulligan at the start; the card-fan sound plays once, for the player who goes first
		if not et in ["play", "damage", "shield_break", "heal", "death", "banish", "leader_hit_negated"] \
				and not (et == "summon" and placed_uids.has(e["uid"])) \
				and not (et == "enter_from_deck" and views.get(e["uid"]) is CardView) \
				and not (et == "mulligan" and int(e["player"]) != g.first):
			Sfx.play_event(e, cursor, in_combat)
		match et:
			"trigger":
				if actors.has(e["uid"]):
					_trigger_fx(actors[e["uid"]], e["trigger"], cursor)
					trig_src = e["uid"]
					trig_shots = 0
					cursor += 0.3
			"trigger_end":
				trig_src = 0 # the effects that follow have no card to fly out of
			"shout":
				if actors.has(e["uid"]):
					cursor = _shout_fx(actors[e["uid"]], String(e["text"]), cursor)
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
				if e.get("incarnation", false) and old.has("cmd%d" % e["player"]):
					origin = old["cmd%d" % e["player"]]["pose"]
				elif e.get("requiem", false):
					# a Réquiem spell rises from its caster's graveyard
					origin = {"c": _graveyard_pose(int(e["player"]))["c"], "rot": 0.0, "w": 96.0}
				elif e.has("source_uid") and old.has(e["source_uid"]):
					origin = old[e["source_uid"]]["pose"] # cast by a unit (Bola de Neve of Tempesfrost): it leaves that unit
				elif old.has(uid):
					origin = old[uid]["pose"]
				if cd["type"] == "unit" and views.has(uid):
					var v: CardView = views[uid]
					var to := _pose(v)
					handled[uid] = true
					# the card is heard when it lands on the board (the Encarnação also gets its bell as it leaves the Santuário)
					placed_uids[uid] = true
					if e.get("incarnation", false):
						Sfx.play_in("incarnation", cursor)
					Sfx.play_in("card_place", cursor + 0.38)
					v.z_index = 20
					var tw := _fly(v, origin, to, cursor, 0.42, 70.0, true)
					tw.tween_callback(func(): v.z_index = 0)
					var fs: Vector2 = Vector2.ONE * (to["w"] / v.size.x)
					tw.tween_property(v, "scale", fs * 1.1, 0.06)
					tw.tween_property(v, "scale", fs, 0.1)
					cursor += 0.45
				else:
					Sfx.play_event(e, cursor, false)
					var gh := _ghost(e["card_id"], {}, origin, REVEAL_W / CardView.BASE.x) # built at its final size: scaling up would blur the text
					gh.z_index = 30
					var tw := _fly(gh, origin, {"c": Vector2(lane_cx, 420), "rot": 0.0, "w": REVEAL_W}, cursor, 0.35, 40.0, true)
					tw.tween_callback(func(): gh.z_index = 0)
					var hold := _reveal_hold(e["player"])
					gh.dissolve(cursor + 0.35 + hold, _elem_color(e["card_id"]).lightened(0.15), 0.6)
					cursor += 0.35 + hold - 0.15
			"enter_from_deck":
				# any card that enters straight from the deck (a deck_effects "summon_self") flies out of its owner's pile instead of popping in from nowhere
				var uid: int = e["uid"]
				if views.get(uid) is CardView:
					handled[uid] = true
					placed_uids[uid] = true
					cursor += _enter_from_deck(views[uid], int(e["player"]), cursor)
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
			"magic_shield_break", "supreme_shield_break", "tide_mark", "tide_draw", "dot", "dot_immune", "freeze", "exhaust", "ready", "stun", "stun_tick", "shrink", "condemn", "doom", "doom_resisted", "thaw", "dodge", "crit", "crit_negated", "critico_up":
				if actors.has(e["uid"]):
					var dot_name: String = {"queimadura": "Queimadura", "veneno": "Veneno", "sangramento": "Sangramento"}.get(String(e.get("dot", "")), "Marcador")
					var dot_label := "%s %d" % [dot_name, int(e.get("amount", 0))]
					if not e.get("cleared", false):
						dot_label = "%s +%d" % [dot_name, int(e.get("amount", 0))]
					var lbl: String = {"magic_shield_break": "Anulado!", "supreme_shield_break": "Absorvido!", "tide_mark": "Maré", "tide_draw": "+1 carta", "dot": dot_label, "dot_immune": "Imune!", "freeze": "Congelada!", "exhaust": "Exausta!", "ready": "Desvirou!", "stun": "Atordoada!", "stun_tick": "Recuperando…", "shrink": "Encolhida!", "condemn": "Condenada!", "doom": "Ceifada!", "doom_resisted": "Resistiu!", "thaw": "Descongelou", "dodge": "Esquivou!", "crit": "Crítico!", "crit_negated": "Desdém!", "critico_up": "Crítico %d!" % int(e.get("level", 0))}[e["type"]]
					var col: Color = Color("#6fd0ff")
					if e["type"] == "magic_shield_break":
						col = Color("#c9a8ff")
					elif e["type"] == "supreme_shield_break":
						col = Color("#ffd86b")
					elif e["type"] in ["freeze", "thaw"]:
						col = ICE
					elif e["type"] in ["stun", "stun_tick"]:
						col = CardView.STUN_COL
					elif e["type"] == "shrink":
						col = Color("#ffb347")
					elif e["type"] in ["condemn", "doom", "doom_resisted"]:
						col = CardView.DOOM_COL
					elif e["type"] in ["dot", "dot_immune"]:
						col = CardView.dot_badge_color(String(e.get("dot", "")))
					elif e["type"] in ["crit", "crit_negated", "critico_up"]:
						col = Color("#ff9d6e") # same warm tone as the Crítico tag
					_impact(actors[e["uid"]], lbl, col, cursor, false)
					if e["type"] == "freeze":
						_freeze_fx(actors[e["uid"]], cursor)
					elif e["type"] == "thaw":
						_frost_shards(_center_of(actors[e["uid"]]), cursor, 16)
					elif e["type"] == "supreme_shield_break":
						_supreme_shield_fx(actors[e["uid"]], cursor)
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
				_freeze_slots_fx(int(e["player"]), cursor)
				cursor += 0.5
			"summon", "draw", "search_take":
				appear[e["uid"]] = cursor
				cursor += 0.1
				if short_lived.has(e["uid"]):
					# pops in with a flash and stays a moment, so the player sees it arrive before the blow lands
					var arriving: CardView = short_lived[e["uid"]]
					var pop := arriving.create_tween()
					pop.tween_interval(cursor)
					pop.tween_property(arriving, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					_embers(_center_of(arriving), cursor, _elem_color(arriving.card_id).lightened(0.3), 20)
					cursor += SHORT_LIVED_ARRIVAL_TIME
				if e["type"] == "search_take" and int(e["player"]) != viewer:
					_toast("%s pegou %s do deck" % [_pname(e["player"]), _cname(e["card_id"])])
					cursor += 0.5
			"search_reveal", "look_top":
				cursor += 0.35
			"mill":
				cursor += _mill_fx(int(e["player"]), e["cards"], cursor)
			"destroy":
				# a "destroy" effect (from any card): the same X as the Leader's execution forms and crosses
				# over the unit, and only then does it die the usual way (the dissolve)
				var destroyed_view = actors.get(e["uid"])
				if destroyed_view is CardView:
					var cross_half_extent: Vector2 = destroyed_view.size * destroyed_view.scale * 0.55
					_cross_slash_fx(_center_of(destroyed_view), cross_half_extent, Color("#ff4040"), cursor)
					cursor += CROSS_SLASH_SECOND_DELAY + CROSS_SLASH_FORM_TIME + 0.12
					# a table ghost does not wait for the end of the batch: it dissolves right after the X.
					# (a stand-in summoned and killed in this batch dissolves at its own "death" event)
					if ghosts.has(destroyed_view) and not short_lived.has(e["uid"]) and not dissolved_early.has(destroyed_view):
						var destroyed_color := _elem_color(destroyed_view.card_id)
						destroyed_view.dissolve(cursor, destroyed_color.lightened(0.2), 0.75)
						_embers(_center_of(destroyed_view), cursor + 0.1, destroyed_color)
						Sfx.play_in("death", cursor)
						dissolved_early[destroyed_view] = true
						cursor += 0.2
			"banish":
				# a free-standing artifact banished to make room; banished units go through the ghost path
				var banished_relic_uid: int = int(e["uid"])
				if e.get("relic", false) and old.has(banished_relic_uid):
					var banished_relic_ghost := _ghost(String(e["card_id"]), old[banished_relic_uid]["inst"], old[banished_relic_uid]["pose"])
					banished_relic_ghost.z_index = 20
					banished_relic_ghost.banish(cursor, BANISH_COL, 0.9)
					_banish_fx(_center_of(banished_relic_ghost), _pose(banished_relic_ghost)["w"], cursor)
					Sfx.play_in("banish", cursor)
			"relic_destroyed":
				# Relics do not use the unit ghost path (they have no damage field), so give every
				# ordinary artifact removal a readable dissolve. Dedicated wards keep their own _ward_fx.
				var relic_uid: int = int(e["uid"])
				if not special_relic_exit_uids.has(relic_uid) and old.has(relic_uid):
					var relic_color := _elem_color(String(e["card_id"]))
					var relic_ghost := _ghost(String(e["card_id"]), old[relic_uid]["inst"], old[relic_uid]["pose"])
					relic_ghost.z_index = 20
					relic_ghost.dissolve(cursor, relic_color.lightened(0.2), 0.75)
					_embers(_center_of(relic_ghost), cursor + 0.1, relic_color)
					Sfx.play_in("death", cursor)
			"return_to_hand":
				# an opponent's unit going back to their hand has no card on the table to fly (its hand is
				# face down), so its ghost makes the trip instead of dissolving as if it had died.
				# A token is deleted rather than returned: it keeps the plain dissolve.
				var bounced_ghost = actors.get(e["uid"])
				if bounced_ghost is CardView and ghosts.has(bounced_ghost) and not dissolved_early.has(bounced_ghost) \
						and int(e["player"]) != viewer and not CardDB.card(e["card_id"]).get("token", false):
					_bounce_to_enemy_hand_fx(bounced_ghost, int(e["player"]), cursor)
					dissolved_early[bounced_ghost] = true # the settle loop must not dissolve it too
					cursor += 0.25
			"death":
				if short_lived.has(e["uid"]):
					# the stand-in falls right after taking the blow, not at the end of the whole batch
					var fallen: CardView = short_lived[e["uid"]]
					var fall_t := maxf(cursor, hit_t) + 0.1
					var fall_col := _elem_color(fallen.card_id)
					fallen.dissolve(fall_t, fall_col.lightened(0.2), 0.6)
					_embers(_center_of(fallen), fall_t + 0.1, fall_col)
					dissolved_early[fallen] = true
					Sfx.play_in("death", fall_t)
					cursor = maxf(cursor, fall_t + 0.3)
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
				if ward_leader is LeaderView:
					ward_leader.play_ward_forge(ward_t + 0.3, int(e.get("hits", 3)))
				cursor = maxf(cursor, ward_t + WARD_FADE_DELAY + WARD_FADE_TIME)
			"leader_hit_negated":
				# Câmara de Êxtase aftermath: the hit lands, the outermost shell shatters and the Leader takes nothing
				var negated_leader: Control = actors.get(e["uid"])
				var negated_src: int = e.get("src", 0)
				var negated_t := cursor + 0.12
				if in_combat and negated_src > 0 and actors.has(negated_src) and negated_leader != null:
					if negated_src == last_src:
						negated_t = hit_t
					else:
						_lunge(actors[negated_src], negated_leader, cursor)
						hit_t = cursor + LUNGE_IMPACT_TIME
						negated_t = hit_t
						last_src = negated_src
						last_dst = e["uid"]
						cursor += LUNGE_TOTAL_TIME
				else:
					cursor += 0.12
				Sfx.play_event(e, negated_t, in_combat)
				if negated_leader is LeaderView:
					negated_leader.play_ward_break(negated_t, int(e["left"]))
					_impact(negated_leader, "Anulado!", LeaderView.WARD_COL, negated_t, false)
					_embers(_center_of(negated_leader), negated_t, LeaderView.WARD_COL, 10)
				cursor = maxf(cursor, negated_t + 0.3)
			"death_prevented":
				# Baluarte Santo: same beat as the Câmara — the blow lands on the unit, the Baluarte answers and fades away
				var saved_unit_view: Control = actors.get(e["uid"])
				var saved_src: int = e.get("src", 0)
				var saved_t := cursor + 0.12
				if in_combat and saved_src > 0 and actors.has(saved_src) and saved_unit_view != null:
					if saved_src == last_src:
						saved_t = hit_t
					else:
						_lunge(actors[saved_src], saved_unit_view, cursor)
						hit_t = cursor + LUNGE_IMPACT_TIME
						saved_t = hit_t
						last_src = saved_src
						last_dst = e["uid"]
						cursor += LUNGE_TOTAL_TIME
				var baluarte_ghost: CardView = null
				if old.has(e["ward_uid"]): # the Baluarte is already gone from the table: a ghost stands in for it
					baluarte_ghost = _ghost(old[e["ward_uid"]]["card_id"], old[e["ward_uid"]]["inst"], old[e["ward_uid"]]["pose"])
					baluarte_ghost.z_index = 20
				_ward_fx(saved_unit_view, baluarte_ghost, saved_t, _elem_color(e["ward_card_id"]).lightened(0.3))
				cursor = maxf(cursor, saved_t + WARD_FADE_DELAY + WARD_FADE_TIME)
			"leader_executed":
				# a card effect killed the Leader outright: not a hit, so it gets its own animation
				var doomed_leader = views.get(e["uid"])
				if doomed_leader is LeaderView:
					var execution_color := Color("#ff4040")
					if e.has("dot"):
						execution_color = CardView.dot_badge_color(String(e["dot"]))
					var execution_end := _execution_fx(doomed_leader, int(e["hp_before"]), cursor, execution_color)
					_leader_ko_t = maxf(_leader_ko_t, execution_end - 0.5)
					cursor = execution_end
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
				Sfx.play_event(e, t, in_combat)
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
		if dissolved_early.has(gh):
			continue
		if ghost_exiled[i]:
			gh.banish(settle + i * 0.06, BANISH_COL, 0.9)
			_banish_fx(_center_of(gh), _pose(gh)["w"], settle + i * 0.06)
			Sfx.play_in("banish", settle + i * 0.06)
			continue
		var col := _elem_color(gh.card_id)
		gh.dissolve(settle + i * 0.06, col.lightened(0.2), 0.75)
		_embers(_center_of(gh), settle + i * 0.06 + 0.1, col)
		Sfx.play_in("death", settle + i * 0.06)
	var deck_n := 0
	var board_end := board_t + 0.3 ## when the last card has finished moving into place
	# A lane that gains a unit in this batch (and loses none) slides its cards apart right away, so the
	# newcomer never lands on top of a card still standing in its slot. A lane that lost a unit waits
	# for the dissolve before closing the gap, as before.
	var lanes_with_newcomer := {}
	var lanes_with_ghost := {}
	for k in views:
		var lane_view = views[k]
		if lane_view is CardView and not hand_uids.has(k) and lane_view.inst.has("owner") and (not old.has(k) or old[k]["hand"]):
			lanes_with_newcomer[int(lane_view.inst["owner"])] = true
	for gh: CardView in ghosts:
		if gh.inst.has("owner"):
			lanes_with_ghost[int(gh.inst["owner"])] = true
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
				var lane_owner := int(v.inst.get("owner", -1))
				var makes_room := lanes_with_newcomer.has(lane_owner) and not lanes_with_ghost.has(lane_owner)
				_fly(v, from, to, 0.0 if hand_uids.has(k) or makes_room else board_t, 0.28)
		elif hand_uids.has(k):
			_draw_from_deck(v, to, appear.get(k, 0.0) + 0.18 * deck_n)
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
	var entry := _chronicle_visual_context.duplicate(true)
	entry["text"] = t
	if not entry.has("kind"):
		entry["kind"] = "info"
	if not entry.has("icon"):
		entry["icon"] = "·"
	if not entry.has("accent"):
		entry["accent"] = UITheme.GOLD
	if not entry.has("label"):
		entry["label"] = "EVENTO"
	if not entry.has("turn") and g != null:
		entry["turn"] = g.turn
	entry["seq"] = _chronicle_next_seq
	_chronicle_next_seq += 1
	chronicle_entries.append(entry)
	if chronicle_entries.size() > 120:
		chronicle_entries.pop_front()

func _pname(p: int) -> String:
	if online:
		return "Você" if p == viewer else "Oponente"
	return "IA" if _is_ai(p) else "J%d" % (p + 1)

func _cname(id: String) -> String:
	return CardDB.card(id)["name"]

func _chronicle_card_id_for_uid(uid: int) -> String:
	if g == null or uid == 0:
		return ""
	if uid < 0:
		return _chronicle_leader_card_id(GameState.LEADER_UID.find(uid))
	var unit := g.find_unit(uid)
	return "" if unit == null else unit.card_id

## The Leader is not a card of the database (and not its Incarnation either): the Chronicle names it
## "leader:<id>", and the row and the scene draw the Leader's own art for it.
func _chronicle_leader_card_id(player: int) -> String:
	if g == null or player < 0 or player >= g.players.size():
		return ""
	return ChronicleRow.LEADER_ID_PREFIX + String(g.players[player]["leader_id"])

func _chronicle_name_for_uid(uid: int) -> String:
	if uid < 0:
		return "O Líder de %s" % _pname(GameState.LEADER_UID.find(uid))
	var unit := g.find_unit(uid)
	return "uma unidade" if unit == null else _cname(unit.card_id)

func _chronicle_add_target(out: Dictionary, uid: int) -> void:
	if uid == 0:
		return
	var card_id := _chronicle_card_id_for_uid(uid)
	if card_id != "":
		out["target_card_ids"].append(card_id)

func _chronicle_accent(kind: String, dot_id := "") -> Color:
	if kind == "dot":
		return CardView.dot_badge_color(dot_id)
	return {
		"play": Color("#f3c969"), "resolve": Color("#d9b7ff"), "ability": Color("#c07bff"),
		"passive": Color("#c07bff"), "trigger": Color("#ff9a4a"), "attack": Color("#ffb45c"),
		"damage": Color("#ff5d5d"), "heal": Color("#62e58d"), "death": Color("#b8aabf"),
		"destroy": Color("#b8aabf"), "death_ward_armed": Color("#72e7ff"), "death_prevented": Color("#72e7ff"),
		"countered": Color("#c9a8ff"), "fizzle": Color("#c9a8ff"),
		"start_turn": Color("#d9b86d"), "transform": Color("#74d7ff")
	}.get(kind, Color("#8d849c"))

## The short title a Chronicle row shows above its sentence.
func _chronicle_label(kind: String) -> String:
	return {
		"play": "JOGADA", "resolve": "RESOLUÇÃO", "ability": "HABILIDADE", "passive": "PASSIVA",
		"trigger": "GATILHO", "attack": "ATAQUE", "damage": "DANO", "heal": "CURA", "death": "MORTE",
		"destroy": "DESTRUIÇÃO", "dot": "STATUS", "countered": "ANULADA", "fizzle": "SEM EFEITO",
		"start_turn": "TURNO", "transform": "TRANSFORMAÇÃO", "summon": "INVOCAÇÃO", "enter_from_deck": "INVOCAÇÃO",
		"relic_enter": "RELÍQUIA", "revive": "RETORNO", "return_to_hand": "DE VOLTA À MÃO",
		"card_created": "CRIAÇÃO", "search_take": "BUSCA", "leader_executed": "EXECUÇÃO",
		"shield_break": "ESCUDO", "magic_shield_break": "ESCUDO", "supreme_shield_break": "ESCUDO", "freeze": "CONGELADA", "thaw": "DEGELO",
		"exhaust": "EXAUSTÃO", "stun": "ATORDOADA", "stun_tick": "ATORDOADA", "shrink": "ENCOLHIMENTO", "dodge": "ESQUIVA", "reflect": "REFLEXO", "condemn": "CONDENADA",
		"doom": "SENTENÇA", "doom_resisted": "RESISTIU", "fatigue": "FADIGA", "ban": "BANIMENTO",
		"concede": "DESISTÊNCIA", "enter_tapped": "PROVOCAÇÃO", "death_ward_armed": "BALUARTE",
		"death_prevented": "BALUARTE"
	}.get(kind, "EVENTO")

## Which player did the event (-1 when it can't be told): the event says it, or the card behind it belongs to someone.
func _chronicle_actor(e: Dictionary) -> int:
	if e.has("player"):
		return int(e["player"])
	# damage, healing, statuses: whoever caused it (the hit card's owner is not the one acting)
	var uid_keys := ["src"] if e.has("src") else ["attacker", "uid"]
	for uid_key in uid_keys:
		var uid := int(e.get(uid_key, 0))
		if uid < 0:
			return GameState.LEADER_UID.find(uid)
		if uid > 0 and g != null:
			var unit := g.find_unit(uid)
			if unit != null:
				return unit.owner
	return -1

func _chronicle_icon(kind: String) -> String:
	return {
		"play": "▶", "resolve": "✦", "ability": "✦", "passive": "✦", "trigger": "⚡",
		"attack": "⚔", "damage": "−", "heal": "+", "death": "×", "destroy": "×",
		"dot": "•", "start_turn": "◷", "transform": "↻", "countered": "⊘", "fizzle": "⊘",
		"death_ward_armed": "◇", "death_prevented": "◇"
	}.get(kind, "·")

## Converts a raw engine event into the visual relationship shown by ChronicleRow.
## The event still supplies the prose through _log_event; this only supplies its art and direction.
func _chronicle_visual_for_event(e: Dictionary) -> Dictionary:
	var kind := String(e.get("type", "info"))
	var out := {"kind": kind, "icon": _chronicle_icon(kind), "accent": _chronicle_accent(kind, String(e.get("dot", ""))),
		"label": _chronicle_label(kind), "source_card_id": "", "target_card_ids": [], "amount": 0,
		"turn": int(e.get("turn", g.turn if g != null else 0))}
	var actor := _chronicle_actor(e)
	out["actor"] = actor
	out["actor_name"] = _pname(actor) if actor >= 0 else ""
	if kind == "damage" or kind == "fatigue":
		out["amount"] = -int(e.get("amount", 0))
	elif kind == "heal":
		out["amount"] = int(e.get("amount", 0))
	elif kind == "dot" and e.has("damage"):
		out["amount"] = -int(e["damage"])
	# how much life the target was left with after this damage / healing (shown beside the amount)
	if (kind == "damage" or kind == "heal") and e.has("hp_after"):
		out["hp_after"] = maxi(0, int(e["hp_after"]))
	match kind:
		"play", "resolve", "fizzle", "countered":
			out["source_card_id"] = String(e.get("card_id", ""))
			_chronicle_add_target(out, int(e.get("target", 0)))
			_chronicle_add_target(out, int(e.get("target2", 0)))
		"ability", "passive":
			out["source_card_id"] = _chronicle_leader_card_id(int(e.get("player", 0)))
			_chronicle_add_target(out, int(e.get("target", 0)))
		"trigger":
			out["source_card_id"] = String(e.get("card_id", ""))
			_chronicle_add_target(out, int(e.get("target", 0)))
		"attack":
			out["source_card_id"] = String(e.get("attacker_card_id", ""))
			if out["source_card_id"] == "":
				out["source_card_id"] = _chronicle_card_id_for_uid(int(e.get("attacker", 0)))
			# an attack on the Leader: the event carries the Incarnation's id, but the target is the Leader
			if int(e.get("target", 0)) < 0:
				_chronicle_add_target(out, int(e["target"]))
			elif String(e.get("target_card_id", "")) != "":
				out["target_card_ids"].append(String(e["target_card_id"]))
			else:
				_chronicle_add_target(out, int(e.get("target", 0)))
		"damage", "heal", "shield_break", "magic_shield_break", "supreme_shield_break", "freeze", "exhaust", "dodge", "dot", "destroy", "death", "condemn", "doom", "doom_resisted", "thaw":
			out["source_card_id"] = _chronicle_card_id_for_uid(int(e.get("src", 0)))
			if kind in ["death", "destroy"] and String(e.get("card_id", "")) != "":
				out["target_card_ids"].append(String(e["card_id"]))
			else:
				_chronicle_add_target(out, int(e.get("uid", 0)))
		"reflect":
			out["source_card_id"] = _chronicle_card_id_for_uid(int(e.get("uid", 0)))
			_chronicle_add_target(out, int(e.get("target", 0)))
		"transform":
			out["source_card_id"] = String(e.get("from", ""))
			if String(e.get("card_id", "")) != "":
				out["target_card_ids"].append(String(e["card_id"]))
		"leader_executed":
			_chronicle_add_target(out, GameState.LEADER_UID[int(e.get("player", 0))])
		"death_ward_armed":
			out["source_card_id"] = String(e.get("card_id", ""))
			_chronicle_add_target(out, int(e.get("uid", 0)))
		"death_prevented":
			out["source_card_id"] = String(e.get("ward_card_id", ""))
			if String(e.get("card_id", "")) != "":
				out["target_card_ids"].append(String(e["card_id"]))
		"summon", "relic_enter", "enter_from_deck", "revive", "return_to_hand", "card_created", "search_take":
			out["source_card_id"] = String(e.get("card_id", ""))
	return out

func _log_event(e: Dictionary) -> void:
	_chronicle_visual_context = _chronicle_visual_for_event(e)
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
		"shout":
			_log("%s: “%s”" % [_cname(e["card_id"]), e["text"]])
		"trigger":
			var trg: Dictionary = CardDB.data()["triggers"].get(e["trigger"], {})
			_log("%s: %s" % [_cname(e["card_id"]), trg.get("name", e["trigger"])])
		"resolve":
			var resolved_name := _cname(String(e.get("card_id", ""))) if String(e.get("card_id", "")) != "" else "a habilidade do Líder"
			_log("%s resolveu" % resolved_name)
		"attack":
			var attacker := g.find_unit(e["attacker"])
			var attacker_name := _cname(String(e["attacker_card_id"])) if attacker == null and e.get("attacker_card_id", "") != "" else ("uma unidade" if attacker == null else _cname(attacker.card_id))
			if int(e["target"]) < 0:
				_log("%s atacou o Líder com %s" % [_pname(e["player"]), attacker_name])
			else:
				var challenged := g.find_unit(e["target"])
				var target_name := _cname(String(e["target_card_id"])) if challenged == null and e.get("target_card_id", "") != "" else ("uma unidade" if challenged == null else _cname(challenged.card_id))
				_log("%s desafiou %s com %s" % [_pname(e["player"]), target_name, attacker_name])
		"enter_tapped":
			if e["tapped"]:
				var tapped_unit := g.find_unit(e["uid"])
				_log("%s entrou exaurida (Provocação)" % ("Uma unidade" if tapped_unit == null else _cname(tapped_unit.card_id)))
		"heal":
			if e.get("regeneration", false):
				var regenerated := g.find_unit(e["uid"])
				if regenerated != null:
					_log("%s regenerou %d" % [_cname(regenerated.card_id), e["amount"]])
			else:
				_log("%s recuperou %d de Vida" % [_chronicle_name_for_uid(int(e["uid"])), int(e["amount"])])
		"damage":
			_log("%s sofreu %d de dano" % [_chronicle_name_for_uid(int(e["uid"])), int(e["amount"])])
		"death":
			_log("%s morreu" % (_cname(String(e["card_id"])) if e.get("card_id", "") != "" else _chronicle_name_for_uid(int(e.get("uid", 0)))))
		"leader_executed":
			_log("O Líder de %s foi executado!" % _pname(e["player"]))
		"concede":
			conceded = e["player"]
			_log("%s desistiu da partida" % _pname(e["player"]))
		"fatigue":
			_log("%s: fadiga %d" % [_pname(e["player"]), e["amount"]])
		"start_turn":
			_log("— Turno %d: %s —" % [e["turn"], _pname(e["player"])])
			if int(e["turn"]) == 1:
				_first_banner(e["player"])
		"extra_turn_promised":
			_log("%s vai jogar um turno extra!" % _pname(e["player"]))
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
			if e.get("from_bottom", false):
				_log("%s olhou %d cartas do fundo do deck" % [_pname(e["player"]), e["cards"].size()])
			else:
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
		"return_to_hand":
			_log("%s voltou para a mão de %s" % [_cname(e["card_id"]), _pname(e["player"])])
		"relic_enter":
			_log("%s colocou %s em campo" % [_pname(e["player"]), _cname(e["card_id"])])
		"summon":
			_log("%s invocou %s" % [_pname(e["player"]), _cname(e["card_id"])])
		"relic_destroyed":
			_log("%s foi destruído" % _cname(e["card_id"]))
		"charge_spent":
			_log("%s gastou um uso (restam %d)" % [_cname(e["card_id"]), int(e["left"])])
		"death_ward_armed":
			_log("%s foi armado: a próxima morte de uma unidade será negada" % _cname(e["card_id"]))
		"death_prevented":
			_log("%s foi destruído para impedir a morte de %s" % [_cname(e["ward_card_id"]), _cname(e["card_id"])])
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
		"stun":
			_log("%s foi atordoada" % _chronicle_name_for_uid(int(e["uid"])))
		"stun_tick":
			_log("%s se recupera do atordoamento (%d marcador(es) restante(s))" % [_chronicle_name_for_uid(int(e["uid"])), int(e["markers"])])
		"shrink":
			_log("%s foi encolhida (-%d Ataque, -%d Vida)" % [_chronicle_name_for_uid(int(e["uid"])), int(e["atk"]), int(e["hp"])])
		"shield_break":
			_log("%s perdeu o Escudo" % _chronicle_name_for_uid(int(e["uid"])))
		"dodge":
			_log("%s esquivou do ataque" % _chronicle_name_for_uid(int(e["uid"])))
		"dot":
			var dotted := g.find_unit(e["uid"])
			var dot_names := {"queimadura": "Queimadura", "veneno": "Veneno", "sangramento": "Sangramento"}
			var dotted_name := "Uma unidade" if dotted == null else _cname(dotted.card_id)
			if int(e["uid"]) < 0: # a Leader holds the markers
				dotted_name = "O Líder de %s" % _pname(GameState.LEADER_UID.find(int(e["uid"])))
			if e.get("cleared", false):
				_log("%s sofreu %d de %s%s" % [dotted_name, int(e.get("damage", e.get("amount", 0))), dot_names.get(String(e.get("dot", "")), "status"), " (marcadores mantidos)" if e.get("held", false) else ""])
			else:
				_log("%s recebeu %d marcador(es) de %s" % [dotted_name, int(e.get("amount", 0)), dot_names.get(String(e.get("dot", "")), "status")])
		"dot_immune":
			var immune_unit := g.find_unit(e["uid"])
			var immune_name := "Uma unidade" if immune_unit == null else _cname(immune_unit.card_id)
			if int(e["uid"]) < 0:
				immune_name = "O Líder de %s" % _pname(GameState.LEADER_UID.find(int(e["uid"])))
			_log("%s é imune a %s" % [immune_name, {"queimadura": "Queimadura", "veneno": "Veneno", "sangramento": "Sangramento", "congelar": "Congelamento"}.get(String(e.get("dot", "")), "esse status")])
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
		"ready":
			var readied_unit := g.find_unit(e["uid"])
			_log("%s desvirou" % ("Uma unidade" if readied_unit == null else _cname(readied_unit.card_id)))
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
		"incarnation_retired":
			_log("%s foi para o fundo do deck como carta comum" % _cname(e["card_id"]))
		"enter_skip":
			_log("%s: Ao Entrar recusado" % _cname(e["card_id"]))
		"search_empty":
			_log("%s não encontrou uma carta que atendesse à busca" % _pname(e["player"]))
		"enter_from_deck":
			_log("%s saiu do deck e entrou em campo para %s" % [_cname(e["card_id"]), _pname(e["player"])])
		"search_take":
			_log("%s escolheu %s na busca" % [_pname(e["player"]), _cname(e["card_id"])])
		"fizzle":
			_log("%s foi anulado (alvo inválido)" % (_cname(e["card_id"]) if e["kind"] in ["card", "subito"] else "Habilidade"))
		"countered":
			_log("%s anulou %s" % [_pname(e["by"]), _cname(e["card_id"]) if e["kind"] in ["card", "subito"] else "a habilidade de " + _pname(e["player"])])
		"magic_shield_break":
			var shielded := g.find_unit(e["uid"])
			_log("Escudo Mágico anulou o efeito" + ("" if shielded == null else " em " + _cname(shielded.card_id)))
		"supreme_shield_break":
			var supreme_holder: Card = g.find_unit(e["uid"])
			if supreme_holder == null:
				supreme_holder = g.find_relic(e["uid"]) # a free-standing artifact (Baluarte Santo) can hold it too
			_log("Escudo Supremo absorveu" + ("" if supreme_holder == null else " em " + _cname(supreme_holder.card_id)))
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
		"relic_redirect":
			var saved_unit := g.find_unit(e["saved"])
			_log("%s foi destruído no lugar de %s" % [_cname(e["card_id"]), "uma unidade" if saved_unit == null else _cname(saved_unit.card_id)])
		"lethal_ward":
			_log("%s anulou %d de dano que mataria o Líder de %s" % [_cname(e["card_id"]), int(e["amount"]), _pname(e["player"])])
		"leader_hit_negated":
			_log("O Líder de %s anulou um golpe de %d (restam %d)" % [_pname(e["player"]), int(e["amount"]), int(e["left"])])
		"discard_pick":
			_log("%s escolhe uma carta da mão para descartar" % _pname(e["player"]))
		"hand_summon_pick":
			_log("%s escolhe um campeão da mão para entrar em campo de graça" % _pname(e["player"]))
		"hand_summon":
			_log("%s colocou %s em campo direto da mão (será banido no fim do turno)" % [_pname(e["player"]), _cname(e["card_id"])])
		"search_decline":
			_log("%s preferiu não pegar nenhuma das cartas encontradas" % _pname(e["player"]))
		"hand_summon_skip":
			_log("%s preferiu não colocar nenhum campeão em campo" % _pname(e["player"]))
		"discard":
			_log("%s descartou %s" % [_pname(e["player"]), _cname(e["card_id"])])
	_chronicle_visual_context = {}


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
	b.pressed.connect(Sfx.play.bind("ui_click"))
	b.pressed.connect(cb)
	return b

## A small round-corner button with a speaker drawn on it (no font needed): sound waves when the sound
## effects are on, a cross when they are off. Pressing it flips the setting (saved by Sfx).
func _sound_icon_button(button_size: float) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(button_size, button_size)
	button.size = Vector2(button_size, button_size)
	button.tooltip_text = "Liga/desliga os efeitos sonoros."
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(button_size / 2.0, button_size / 2.0)
	var draw_speaker := func():
		var sound_on := Sfx.is_enabled()
		var color: Color = UITheme.GOLD_LIGHT if sound_on else Color(UITheme.TEXT, 0.5)
		icon.draw_colored_polygon(PackedVector2Array([Vector2(-10, -4), Vector2(-5, -4), Vector2(1, -9), Vector2(1, 9), Vector2(-5, 4), Vector2(-10, 4)]), color)
		if sound_on:
			icon.draw_arc(Vector2(1, 0), 6.0, -0.8, 0.8, 8, color, 2.0)
			icon.draw_arc(Vector2(1, 0), 11.0, -0.8, 0.8, 10, color, 2.0)
		else:
			icon.draw_line(Vector2(6, -5), Vector2(14, 5), UITheme.HP, 2.0)
			icon.draw_line(Vector2(6, 5), Vector2(14, -5), UITheme.HP, 2.0)
	icon.draw.connect(draw_speaker)
	button.add_child(icon)
	button.pressed.connect(func():
		Sfx.set_enabled(not Sfx.is_enabled())
		Sfx.play("ui_toggle") # heard only when it was just turned on
		icon.queue_redraw())
	return button

## A volume slider with a "VOLUME DOS EFEITOS 70%" title (menu): the sound effects, or the music when
## `for_music` is true (each has its own volume). Moving it changes the volume live and saves it;
## letting go plays a click so the new level can be heard right away.
func _volume_slider(control_size: Vector2, for_music := false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = control_size
	holder.size = control_size
	var title_label := _label("", 15, UITheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "bold")
	title_label.position = Vector2(4, 0)
	title_label.size = Vector2(control_size.x, 22)
	holder.add_child(title_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	slider.value = roundf((Music.get_volume() if for_music else Sfx.get_volume()) * 100.0)
	slider.position = Vector2(0, 24)
	slider.size = Vector2(control_size.x, control_size.y - 24.0)
	holder.add_child(slider)
	var title_text := "VOLUME DA MÚSICA  %d%%" if for_music else "VOLUME DOS EFEITOS  %d%%"
	var refresh_title := func(percent: float):
		title_label.text = title_text % int(percent)
	refresh_title.call(slider.value)
	slider.value_changed.connect(func(percent: float):
		if for_music:
			Music.set_volume(percent / 100.0)
		else:
			Sfx.set_volume(percent / 100.0)
		refresh_title.call(percent))
	slider.drag_ended.connect(func(_value_changed: bool): Sfx.play("ui_click"))
	return holder

## An on/off button shown as a sliding switch instead of the words "LIGADO"/"desligado":
## gold track with the knob on the right when on, dark track with the knob on the left when off.
func _toggle_button(title: String, is_on: bool, on_press: Callable) -> Button:
	var button := Button.new()
	button.pressed.connect(Sfx.play.bind("ui_toggle"))
	button.pressed.connect(on_press)
	var title_label :=_label(title, 17, UITheme.TEXT if is_on else UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, "bold")
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
	button.pressed.connect(Sfx.play.bind("ui_click"))
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
