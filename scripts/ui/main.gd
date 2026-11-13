extends Control
## Table screen: menu, board rendering, input state machine, AI driver,
## hot-seat pass screen and the full-screen card summary overlay.

const ChronicleRowScript = preload("res://scripts/ui/chronicle_row.gd")
const ChronicleSceneScript = preload("res://scripts/ui/chronicle_scene.gd")
const FxLibraryScript = preload("res://scripts/ui/fx_library.gd")
const FxShotsScript = preload("res://scripts/ui/fx_shots.gd")
const FxCastsScript = preload("res://scripts/ui/fx_casts.gd")
const ChronicleLogScript = preload("res://scripts/ui/chronicle_log.gd")
const TableAnimatorScript = preload("res://scripts/ui/table_animator.gd")
const TableOverlaysScript = preload("res://scripts/ui/table_overlays.gd")
const MenuScreensScript = preload("res://scripts/ui/menu_screens.gd")
const DevToolsPanelScript = preload("res://scripts/ui/dev_tools_panel.gd")

const SEL := Color("#ffd23f")
const TARGET := Color("#ff5050")
const OK := Color("#4dff88")
const INK_BLUE := Color("#50cfff")
const ICE := FxLibraryScript.ICE
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
var _deck_watch_states := { } ## player -> watched-card state last render ("waiting"/"ready"/"blocked")
var deck_piles := { } ## player -> LeaderView.DeckPile: each deck, drawn by the right edge of the table (see _render_piles)
var graveyard_piles := { } ## player -> GraveyardPile: each graveyard, a face-up pile right beside its deck
var motes: CPUParticles2D

var g: GameState
var vs_ai := true
var viewer := 0 ## whose perspective is drawn
var pending_pass := false
var _over_from := -1 ## index in layer of the first game-over node (-1 = none this frame)
const KO_OVERLAY_DELAY := 0.7 ## the result screen shows this long after the Leader's last hit
var leader_ko_time := -1.0 ## time of the last Leader HP change in the current animation
var net: NetClient ## online match link (null offline)
var dev_mode_enabled := false
var dev_tools_panel: DevToolsPanel
var deck_builder: DeckBuilder ## the "MEUS DECKS" screen while it is open
var menu_screen_showing := false ## the title screen (entry or full menu) is what is on screen now
var online := false
var opp_online := true
var join_slots: Label ## the room-code display of the join screen; null on every other screen (the keyboard types into it)
var hub_stats_refresh_at := -30000
var hub_scroll: ScrollContainer ## the deck hub's scrolling gallery (null/freed outside the hub)
var _fps_counter: Label
var _fps_counter_visible := false
var _perf_diagnostics := false
var _fps_sample_seconds := 0.0
var _fps_sample_frames := 0

# input state
var picked: Array = [] ## mulligan/discard selection
var targeting := { } ## {"kind": hand|incarnation|ability|enter|attack, "uid": int, "spec": String}

var chronicle_log: ChronicleLog ## match history data: text lines and structured Chronicle entries
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
## A "choose one" window shown only on this client (nothing is sent to the server until an option is picked):
## {"title": String, "subtitle": String, "options": [{"title", "detail", "enabled", "reason", "callback"}]}
## Empty when closed. Built by _open_option_prompt and drawn by _render_option_prompt.
var option_prompt := { }
var grave_view: Control ## graveyard viewer (child of Main, outlives render_table)
var decklist_view: DecklistView ## a deck's card list, opened from the deck selection hub (child of Main)
var concede_view: Control ## "concede?" confirmation (child of Main, outlives render_table)
var conceded := -1 ## player who gave up this match (-1 = nobody); only used for the game-over text
var finger_press_position := Vector2.ZERO ## where the current touch began
var finger_is_swiping := false ## true once the current touch moved past SWIPE_START_DISTANCE
var views := { } ## uid (or "cmd<p>") -> Control on screen, for animations
var _unit_board_views := { } ## uid -> unit CardView from the last board render, kept for same-slot updates
var _unit_views_for_reuse := { } ## detached unit views being matched against the next board layout
var barricade_was_up := { } ## unit uid -> was a tapped, unfrozen Provocação up in the previous render?
var _locked_hand_uids := { } ## hand card uid -> true if it was chained (play restriction) in the previous render
const LOCK_STAGGER_SECONDS := 0.07 ## delay between the chain lock-ins of cards locked at the same moment
const MAX_LOCK_SOUNDS := 4 ## a full hand locking at once plays at most this many clanks
var hand_uids := { } ## viewer's hand cards in the current render
var reservoir_ink_glow: Panel ## blue pulse: a card can still be deposited this turn
var reservoir_drop_glow: Panel ## strong yellow: the card being dragged will be deposited if released here
var hint_text := "" ## the tip pill fades out after a few seconds and returns when the player seems lost
var hint_since := 0
var hint_until := 0
var last_input_ms := 0
var hint_pill: Control
var aim_arrow: AimArrow ## targeting arrow from the source to the pointer
var reaction_arrow: AimArrow ## locked dashed arrow showing the pending attack during a reaction
var reaction_attack: Dictionary = { } ## {"attacker": uid, "target": uid} from the latest reaction event
var aim_drag := false ## the press that started aiming is still held: releasing on a target fires
var aim_start := Vector2.ZERO
var aim_src := Vector2.ZERO ## global source point (leader gem, command card)
var _aim_drag_view: CardView
var fx: Control ## persistent layer above the table: ghosts, floats, embers
var fx_library: FxLibrary ## card flights, combat effects and glow primitives (moved out of this file)
var fx_shots: FxShots ## projectile / slash / boon shot pipeline, built on fx_library
var menu_screens: MenuScreens ## title menu, deck hub, online room screens and deck list (moved out of this file)
var table_overlays: TableOverlays ## card overlay, pause menu, graveyard viewer and search reveal (moved out of this file)
var table_animator: TableAnimator ## plays each batch of events on the table (moved out of this file)
var fx_leader_death: FxLeaderDeath ## what plays when a Leader dies, before the result screen
var fx_casts: FxCasts ## cast animations of spells and area triggers (a wall of fire, a flood...), built on fx_library
var ai_timer: Timer
## Animations are never cut short: while one is still playing, the next batch of events waits here
## (the engine has already applied it; only the showing is postponed) and plays when the table settles.
var _animation_busy_until_ms := 0
var _waiting_event_batches: Array = [] ## each entry is one Array of events, in the order they happened
var _waiting_events_timer: Timer
## While the table is busy (see _table_busy) the engine may already be ahead of what the screen shows,
## so redrawing would spoil the future (a unit that dies in the waiting batch would vanish before its
## fight is shown). render_table only takes note, and the redraw happens once the table settles.
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
func apply_light_mode(on: bool, save := false) -> void:
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT if on else Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if save:
		var cf := ConfigFile.new()
		cf.load("user://settings.cfg") # keep the other settings (sound, music, auto-pass) in the file
		cf.set_value("ui", "light", on)
		cf.save("user://settings.cfg")


## Phones default to light mode until the player picks one explicitly.
func is_light_mode_on() -> bool:
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
		if not is_ai(i):
			ev += g.set_auto_pass(i, on)
	if on and not ev.is_empty():
		for e in ev:
			chronicle_log.log_event(e)
		_show_events(ev)
	else:
		render_table()


func _is_phone() -> bool:
	return (
		OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
		or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())
	)


func _ready() -> void:
	dev_mode_enabled = DeckDB.development_mode_enabled()
	# Main covers the whole stage: with the default STOP filter it swallowed every press on empty
	# table, so `_unhandled_input` (tap outside / right click cancels an aim) never saw it
	mouse_filter = Control.MOUSE_FILTER_PASS
	fx_library = FxLibraryScript.new(self)
	fx_shots = FxShotsScript.new(self, fx_library)
	fx_casts = FxCastsScript.new(self, fx_library)
	fx_leader_death = FxLeaderDeath.new(self, fx_library)
	table_animator = TableAnimatorScript.new(self, fx_library, fx_shots, fx_casts)
	chronicle_log = ChronicleLogScript.new(self)
	table_overlays = TableOverlaysScript.new(self)
	menu_screens = MenuScreensScript.new(self)
	# the logical screen is as tall as the stage, so a 16:9 window shows all of it (not a cropped middle)
	get_window().content_scale_size = Vector2i(1600, int(STAGE_H))
	apply_light_mode(is_light_mode_on())
	dev_tools_panel = DevToolsPanelScript.new()
	dev_tools_panel.action_requested.connect(_on_dev_tool_action)
	dev_tools_panel.close_requested.connect(_close_dev_tools)
	# starts hidden: it only opens with F12 during a local match in development mode (modo_desenvolvimento.bat)
	dev_tools_panel.hide()
	add_child(dev_tools_panel)
	# phones: trim the purely decorative work (see GraphicsQuality)
	if _is_phone():
		GraphicsQuality.use_phone_settings()
	Engine.max_fps = GraphicsQuality.max_fps
	theme = UITheme.make()
	_perf_diagnostics = _performance_diagnostics_requested()
	if _perf_diagnostics:
		_toggle_fps_counter()
	bg_vp = SubViewport.new()
	bg_vp.size = Vector2i(int(GraphicsQuality.table_bake_height * 16.0 / 9.0), GraphicsQuality.table_bake_height)
	bg_vp.disable_3d = true
	bg_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(bg_vp)
	bg_rect = ColorRect.new()
	bg_rect.size = Vector2(bg_vp.size)
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
	fx_library.prewarm_fx.call_deferred()
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
	SupabaseAuth.state_changed.connect(menu_screens.on_supabase_auth_state_changed)
	menu_screens.show_menu()
	_load_scenario()


## Dev only: `-- --scenario=<name>` starts a match vs the AI set up by tests/scenarios/<name>.gd
## (static func setup(g)). The script may declare PLAYER_DECK / ENEMY_DECK; the default is Maré vs Fogo.
func _load_scenario() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--scenario="):
			continue
		var script: GDScript = load("res://tests/scenarios/%s.gd" % a.trim_prefix("--scenario="))
		var scenario_constants := script.get_script_constant_map()
		start_match(true, String(scenario_constants.get("PLAYER_DECK", "agua")), String(scenario_constants.get("ENEMY_DECK", "fogo")))
		script.setup(g)
		g.auto_pass[0] = _auto_pass_on()
		pending_pass = false
		chronicle_log.log_lines = ["Cenário de teste carregado."]
		chronicle_log.chronicle_entries.clear()
		render_table()


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
	if is_instance_valid(dev_tools_panel):
		dev_tools_panel.position = Vector2(stage_w - dev_tools_panel.size.x - 18.0, 18.0)
	bg.position = -position
	bg.size = vp
	var bake_height := GraphicsQuality.table_bake_height
	var bake_width := int(bake_height * vp.x / maxf(1.0, vp.y))
	bg_vp.size = Vector2i(bake_width, bake_height)
	bg_rect.size = Vector2(bake_width, bake_height)
	bg_mat.set_shader_parameter("aspect", vp.x / vp.y)
	bg_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if motes:
		motes.position = Vector2(w / 2.0, STAGE_H / 2.0)
		motes.emission_rect_extents = Vector2(w / 2.0 + 20.0, STAGE_H / 2.0)
	if changed and layer:
		if table.visible and g:
			render_table.call_deferred()
		elif not table.visible and not is_instance_valid(deck_builder):
			menu_screens.show_menu.call_deferred() # the deck builder stretches with the stage by itself


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


## Repaints the background. `marble_floor` = true only for a match: menus keep the plain dark slate
## so the marble battle table does not show behind the menu art.
func set_background_tints(top: Color, bottom: Color, intensity := 1.0, marble_floor := false) -> void:
	bg_mat.set_shader_parameter("marble_floor", marble_floor)
	bg_mat.set_shader_parameter("top_tint", top)
	bg_mat.set_shader_parameter("bottom_tint", bottom)
	bg_mat.set_shader_parameter("intensity", intensity)
	bg_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _leader_color(p: int) -> Color:
	return Color(CardDB.essence(CardDB.leader_essences(CardDB.leader(g.players[p]["leader_id"]))[0])["color"])

# ---------------------------------------------------------------- match start and online link


func start_match(ai: bool, deck_a: String, deck_b: String) -> void:
	if online:
		net.disconnect_server()
		online = false
	vs_ai = ai
	g = GameState.new(deck_a, deck_b)
	_queue_deck_arts([deck_a, deck_b])
	barricade_was_up.clear() # unit uids restart with every match
	_locked_hand_uids.clear()
	for i in 2:
		g.auto_pass[i] = _auto_pass_on() or is_ai(i)
	CardDB.reroll_flavor()
	Sfx.play("card_shuffle")
	Music.play_match()
	chronicle_log.log_lines = ["Partida iniciada. Escolha até 3 cartas para trocar."]
	chronicle_log.chronicle_entries.clear()
	conceded = -1
	viewer = 0
	pending_pass = not vs_ai
	_reset_input()
	reset_animation_state()
	render_table()


func _reset_input() -> void:
	picked.clear()
	targeting = { }


## Queues every art the two decks can show (cards, Leaders, Encarnações) to load in the background
## during the mulligan, so no card stalls the game the first time it is drawn.
## The deck at `own_seat` is queued first: its cards are the ones about to be drawn, and on a phone
## (where the art cache has a limit) the opponent's deck may be left to load on demand.
func _queue_deck_arts(deck_ids: Array, own_seat := 0) -> void:
	var art_files: Array = []
	var ordered_deck_ids: Array = deck_ids.duplicate()
	if own_seat == 1:
		ordered_deck_ids.reverse()
	for deck_id in ordered_deck_ids:
		if not DeckDB.has(String(deck_id)):
			continue
		var deck := DeckDB.get_deck(String(deck_id))
		var leader_data := CardDB.leader(deck["leader"])
		art_files.append(leader_data.get("art", ""))
		var card_ids: Array = deck["cards"].keys()
		card_ids.append(deck.get("incarnation_id", leader_data.get("incarnation", "")))
		for card_id in card_ids:
			if CardDB.data()["cards"].has(card_id):
				art_files.append(CardDB.card(card_id).get("art", ""))
	CardView.queue_art_preload(art_files)


func _on_link(up: bool) -> void:
	if not online or g == null:
		return
	if up:
		show_toast("Reconectado.")
	else:
		show_toast("Conexão perdida… reconectando.")


## An online match can use the players' own decks. The server sends their contents (already validated
## there) under "room:" ids, and both clients register them like any other deck.
func _register_room_decks(deck_data: Variant) -> void:
	if not deck_data is Dictionary:
		return
	for deck_id in deck_data:
		var deck: Variant = deck_data[deck_id]
		if String(deck_id).begins_with(DeckDB.ROOM_PREFIX) and deck is Dictionary:
			DeckDB.register_custom(
				String(deck_id),
				String(deck.get("name", "")),
				String(deck.get("description", "")),
				String(deck.get("leader", "")),
				deck.get("cards", { }),
				String(deck.get("incarnation_id", "")),
			)


func _on_net(m: Dictionary) -> void:
	if dev_mode_enabled:
		net.disconnect_server()
		online = false
		return
	match m.get("t", ""):
		"room":
			net.code = m["code"]
			net.token = m["token"]
			net.seat = m["seat"]
			net.want_resume = true
			net.remember()
			if m["seat"] == 0:
				menu_screens.show_wait("Aguardando o oponente entrar…", m["code"])
		"start":
			var d: Array = m["decks"]
			_register_room_decks(m.get("deck_data", { })) # the players' own decks, before anything looks them up
			var rs := RemoteState.new(d[0], d[1])
			_queue_deck_arts(d, int(m["seat"]))
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
			if chronicle_log.log_lines.is_empty() or m.get("snap", { }).get("turn", 0) == 0:
				chronicle_log.log_lines = ["Partida online iniciada."]
				chronicle_log.chronicle_entries.clear()
				conceded = -1
			_reset_input()
			reset_animation_state()
			render_table()
		"events":
			if not (g is RemoteState):
				return
			(g as RemoteState).apply_snapshot(m["snap"])
			if _pass_all_waiting_for_server and bool(g.skip_rest_of_turn[viewer]) == _pass_all_expected_state:
				_pass_all_waiting_for_server = false # the server confirmed the PASSAR TUDO switch
			_reset_input()
			for e in m["events"]:
				chronicle_log.log_event(e)
			_show_events(m["events"])
		"reject":
			show_toast("Ação inválida.")
			Sfx.play("ui_error")
			_stop_waiting_for_pass_all()
		"opponent":
			opp_online = m["connected"]
			show_toast("Oponente reconectou." if opp_online else "Oponente desconectou.")
		"stats_saved":
			hub_stats_refresh_at = Time.get_ticks_msec()
			SupabaseAuth.refresh_deck_stats()
		"stats_error":
			show_toast(String(m.get("msg", "Erro ao registrar estatísticas.")))
		"error":
			net.forget()
			online = false
			menu_screens.show_online(String(m.get("msg", "Erro.")))

# ---------------------------------------------------------------- actions


func handle_action_result(events: Array) -> void:
	if g is RemoteState:
		return ## the server answers with "events" (see _on_net)
	if events.is_empty():
		show_toast("Ação inválida.")
		Sfx.play("ui_error")
		render_table() # brings back the action button that greyed out when it was pressed
		return
	_reset_input()
	for e in events:
		chronicle_log.log_event(e)
	var d := g.decider()
	if not vs_ai and d != viewer and g.phase != "over":
		viewer = d
		pending_pass = true
	_show_events(events)


func _ai_step() -> void:
	if g == null or g.phase == "over" or (is_instance_valid(dev_tools_panel) and dev_tools_panel.visible) or not is_ai(g.decider()):
		return
	var ev := SimpleAI.step(g, g.decider())
	if ev.is_empty():
		return
	for e in ev:
		chronicle_log.log_event(e)
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
			reaction_attack = { "attacker": int(e["attacker"]), "target": int(e["target"]) }
		elif e["type"] in ["combat_damage", "combat_end"]:
			reaction_attack.clear()
	var old := fx_library.snapshot_views()
	leader_ko_time = -1.0
	_over_from = -1
	_render_now() # not render_table: other batches may still be waiting, and this one must be drawn now
	var end := table_animator.animate(events, old)
	_animation_busy_until_ms = Time.get_ticks_msec() + int(end * 1000.0)
	_settle_timer.start(maxf(end, 0.05))
	# the Victory/Defeat screen waits for the killing blow to land instead of spoiling it
	if g.phase == "over" and _waiting_event_batches.is_empty():
		# same moment as the Victory/Defeat screen (the last batch only, so a queue of batches does not announce it early)
		var jingle_delay := maxf(leader_ko_time + KO_OVERLAY_DELAY, end) if leader_ko_time >= 0.0 else end
		Sfx.play_in(_match_end_sound(), jingle_delay)
		# the music dies away just as the jingle starts, so the jingle is heard on its own
		get_tree().create_timer(jingle_delay).timeout.connect(Music.fade_out.bind(1.5))
	if g.phase == "over" and _over_from >= 0 and end > 0.0:
		var delay := maxf(leader_ko_time + KO_OVERLAY_DELAY, end) if leader_ko_time >= 0.0 else end
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


func is_ai(p: int) -> bool:
	return vs_ai and p == 1

# ---------------------------------------------------------------- render


func clear_table() -> void:
	# A state update can arrive while the full-screen card overlay is open (AI, online opponent,
	# animation batch...). Remove it before rebuilding the table, otherwise the old overlay survives
	# over the new layer for a frame and leaves duplicated/offset UI behind.
	table_overlays.close_overlay()
	menu_screens.close_decklist()
	join_slots = null
	_finish_unit_view_reuse()
	for unit_uid in _unit_board_views:
		var unit_view: CardView = _unit_board_views[unit_uid]
		if (
			is_instance_valid(unit_view) and not unit_view.is_queued_for_deletion() \
					and is_instance_valid(layer)
			and unit_view.get_parent() == layer
		):
			# Preserve the node briefly; _render_board will keep it only if this unit stays in the same slot.
			layer.remove_child(unit_view)
			_unit_views_for_reuse[unit_uid] = unit_view
		elif is_instance_valid(unit_view) and not unit_view.is_queued_for_deletion():
			unit_view.queue_free()
	_unit_board_views.clear()
	if layer:
		layer.queue_free()
	menu_screen_showing = false
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


func reset_animation_state() -> void:
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
func render_table() -> void:
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
func run_or_queue_input(input: Callable) -> void:
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
	clear_table()
	drag_gap_slot = -1 # fresh board views have no gap
	var me := viewer
	var op := g.opponent(me)
	set_background_tints(_leader_color(op), _leader_color(me), 1.0, true)
	table.enemy_color = _leader_color(op)
	table.my_color = _leader_color(me)
	table.sockets = [Rect2(SANCTUARY_X, SANCTUARY_Y_OP, SANCTUARY_W, 264), Rect2(SANCTUARY_X, SANCTUARY_Y_ME, SANCTUARY_W, 264)]
	table.visible = true
	table.queue_redraw()
	if g.phase == "over":
		table_overlays.close_concede()
	if pending_pass or g.phase in ["search", "over"]:
		table_overlays.close_graveyard()
	else:
		table_overlays.refresh_graveyard()
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
	_render_reservoir(op)
	_render_reservoir(me)
	_render_board(op, 172)
	_render_board(me, 460)
	_sync_enter_aim()
	_sync_effect_choice_prompt()
	_render_side()
	_render_hint()
	if g.phase == "search":
		table_overlays.render_search_reveal()
	_render_option_prompt()
	if g.phase == "over":
		_over_from = layer.get_child_count()
		_render_game_over()
	elif is_ai(g.decider()) and ai_timer.is_stopped():
		ai_timer.start() # not while it is already counting: every redraw would push the AI's move back
	_finish_unit_view_reuse()


## Full-screen veil over the table with a centered panel.
func make_veil(alpha := 0.72) -> PanelContainer:
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


func center_in_screen(pc: Control) -> void:
	pc.reset_size()
	pc.position = (size - pc.size) / 2.0


## Opens the generic "choose one" window. `options` is an Array of {"title", "detail", "enabled", "reason", "callback"};
## a disabled option is greyed out and its `reason` is shown in the subtitle. Future "Escolha um..." effects reuse it.
func _open_option_prompt(title: String, options: Array) -> void:
	option_prompt = { "title": title, "options": options }
	render_table()


func _choice_prompt_options(options: Array, available: Callable, select: Callable) -> Array:
	var result: Array = []
	for index in options.size():
		var option: Dictionary = options[index]
		result.append(
			{
				"title": String(option.get("title", "")),
				"detail": String(option.get("detail", "")),
				"enabled": bool(available.call(index)),
				"reason": String(option.get("reason", "não há alvo válido.")),
				"callback": select.bind(index),
			}
		)
	return result


func _close_option_prompt() -> void:
	if option_prompt.is_empty():
		return
	if option_prompt.get("mandatory", false):
		return
	option_prompt = { }
	render_table()


## Draws the "choose one" window: one big clickable block per option. Rebuilt on every render from option_prompt.
func _render_option_prompt() -> void:
	if option_prompt.is_empty():
		return
	if g == null or g.phase in ["search", "over"] or not viewer_can_act():
		option_prompt = { } # the game moved on (or it is no longer this player's turn to decide)
		return
	var options: Array = option_prompt["options"]
	var pc := make_veil(0.84)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	pc.add_child(box)
	box.add_child(make_label(String(option_prompt["title"]), 30, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6))
	# the reasons why some blocks are not clickable
	var reasons: Array = []
	for option: Dictionary in options:
		if not bool(option.get("enabled", true)) and String(option.get("reason", "")) != "":
			reasons.append("%s: %s" % [option["title"], option["reason"]])
	var subtitle_text := "Escolha uma das opções." if reasons.is_empty() else "\n".join(reasons)
	var subtitle := make_label(
		subtitle_text,
		18,
		UITheme.TEXT_DIM if not reasons.is_empty() else UITheme.TEXT,
		HORIZONTAL_ALIGNMENT_CENTER,
		"body",
	)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size = Vector2(minf(stage_w - 160.0, 720.0), 0)
	box.add_child(subtitle)
	var blocks := HBoxContainer.new()
	blocks.add_theme_constant_override("separation", 20)
	blocks.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(blocks)
	var block_width := clampf((minf(stage_w - 160.0, 720.0) - 20.0 * (options.size() - 1)) / options.size(), 200.0, 340.0)
	for option: Dictionary in options:
		var enabled: bool = bool(option.get("enabled", true))
		var callback: Callable = option["callback"]
		var block := Button.new()
		block.custom_minimum_size = Vector2(block_width, 230)
		block.disabled = not enabled
		block.text = "%s\n\n%s" % [option["title"], option.get("detail", "")]
		block.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.add_theme_font_size_override("font_size", 22)
		block.pressed.connect(Sfx.play.bind("ui_click"))
		block.pressed.connect(
			func():
				option_prompt = { }
				callback.call(),
		)
		blocks.add_child(block)
	if not option_prompt.get("mandatory", false):
		var cancel_button := make_button("CANCELAR", _close_option_prompt)
		cancel_button.custom_minimum_size = Vector2(360, 52)
		cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(cancel_button)
	center_in_screen.call_deferred(pc)


func _sync_effect_choice_prompt() -> void:
	if g.phase != "effect_choice" or not viewer_can_act():
		if option_prompt.get("effect_choice", false):
			option_prompt = { }
		return
	if not targeting.is_empty() or option_prompt.get("effect_choice", false):
		return
	var options := _choice_prompt_options(g.pending_effect_choice.get("options", []), g.effect_choice_available, _select_effect_option)
	option_prompt = { "title": "ESCOLHA UM EFEITO", "options": options, "mandatory": true, "effect_choice": true }


func _select_effect_option(index: int) -> void:
	if g.phase != "effect_choice" or not viewer_can_act() or not g.effect_choice_available(index):
		render_table()
		return
	var mode: Dictionary = g.pending_effect_choice["options"][index]
	var spec := g.target_spec(mode.get("effects", []))
	if spec == "":
		handle_action_result(g.choose_effect_option(viewer, index))
		return
	var uid := int(g.pending_effect_choice["uid"])
	targeting = { "kind": "effect_choice", "uid": uid, "spec": spec, "mode": index }
	if views.has(uid) and is_instance_valid(views[uid]):
		begin_aim(visual_rect_of(views[uid] as Control).get_center())
	render_table()


func open_activation_cost_prompt(ability_uid: int) -> void:
	# with a single way to pay (Cornélia: only sacrifice) asking "which cost?" is a pointless step: go straight to it
	if g.activation_cost_options(ability_uid).size() == 1:
		_select_activation_cost_option(0, ability_uid)
		return
	var options := _choice_prompt_options(
		g.activation_cost_options(ability_uid),
		func(index: int):
			return g.activation_cost_option_available(viewer, ability_uid, index),
		_select_activation_cost_option.bind(ability_uid),
	)
	_open_option_prompt("PAGUE O CUSTO ADICIONAL", options)


func _select_activation_cost_option(index: int, ability_uid: int) -> void:
	if (
		not viewer_can_act() or not g.can_activate(viewer, ability_uid)
		or not g.activation_cost_option_available(viewer, ability_uid, index)
	):
		render_table()
		return
	var option: Dictionary = g.activation_cost_options(ability_uid)[index]
	match option["pick"]:
		"hand_card":
			handle_action_result(g.begin_activation_discard(viewer, ability_uid))
		"other_ally_unit":
			targeting = { "kind": "unit_cost", "uid": ability_uid, "spec": "extra_cost_payer", "mode": index }
			if views.has(ability_uid) and is_instance_valid(views[ability_uid]):
				begin_aim(visual_rect_of(views[ability_uid] as Control).get_center())
			render_table()
		_:
			push_error("Unsupported activation cost choice: %s" % option["pick"])


func _render_pass() -> void:
	var p := viewer
	var pc := make_veil(0.55)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 16)
	pc.add_child(box)
	box.add_child(make_label("PASSE O DISPOSITIVO", 30, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6))
	box.add_child(
		make_label(
			"Jogador %d · %s" % [p + 1, CardDB.leader(g.players[p]["leader_id"])["name"]],
			20,
			UITheme.TEXT,
			HORIZONTAL_ALIGNMENT_CENTER,
			"bold",
		)
	)
	var b := make_button(
		"ESTOU PRONTO",
		func():
			pending_pass = false
			render_table(),
		true,
	)
	b.pressed.connect(
		func():
			b.disabled = true,
	) # answers at once even if the redraw waits for an animation
	b.custom_minimum_size = Vector2(460, 56)
	box.add_child(b)
	center_in_screen.call_deferred(pc)


func _render_leader(p: int, pos: Vector2, mom_pos: Vector2) -> void:
	var pl: Dictionary = g.players[p]
	var uid: int = GameState.LEADER_UID[p]
	var lv := LeaderView.new().setup(pl["leader_id"])
	lv.position = pos
	lv.hp = pl["leader_hp"]
	lv.top_destroyed = lv.hp <= 0
	lv.hp_max = pl["leader_max"]
	lv.deck = pl["deck"].size()
	lv.fatigue = g.fatigue_next(p)
	lv.shows_deck_pile = false # both decks and graveyards sit by the right edge of the table (see _render_piles)
	lv.shows_graveyard = false
	lv.grave = pl["graveyard"].size()
	lv.dot_markers = {
		"queimadura": g.leader_dot_markers(p, "queimadura"),
		"veneno": g.leader_dot_markers(p, "veneno"),
		"sangramento": g.leader_dot_markers(p, "sangramento"),
		"sem_cura": CardView.heal_block_turns_left(int(pl["leader_heal_blocked_until"]), g.turn),
		"congelar": g.leader_dot_markers(p, "congelar"), # TEMP pseudo 4th marker for the status-badge scenario
	}
	lv.ward_hits = g.leader_negations_left(p)
	lv.requiem = g.requiem_cards(p).size() if p == viewer and not is_ai(p) and g.phase in ["main", "combat"] else 0
	lv.ability_ready = p == viewer and g.can_use_ability(p, true) and not is_ai(p)
	# passives with a per-turn limit (Thálvaressa) show how many uses are spent; the engine wipes the count every turn start
	if CardDB.leader(pl["leader_id"])["ability"].has("max_per_turn"):
		lv.ability_uses = int(pl.get("passive_uses", 0))
	# an ability paid in Vida that grows with the player's own turns (Sengoku) tells its current price in the tooltip
	var leader_ability: Dictionary = CardDB.leader(pl["leader_id"])["ability"]
	if leader_ability.has("life_cost"):
		lv.ability_life_cost_now = g.ability_life_cost(p, leader_ability)
	lv.targetable = _is_target(uid)
	lv.target_selected = _is_first_target(uid)
	lv.active = g.active == p and g.phase != "mulligan"
	lv.ability_clicked.connect(
		func():
			_on_ability(p),
	)
	lv.portrait_clicked.connect(
		func():
			_on_leader_click(p),
	)
	lv.grave_clicked.connect(
		func():
			table_overlays.show_graveyard(p),
	)
	layer.add_child(lv)
	views[uid] = lv
	if lv.target_selected:
		_add_target_badges(lv, _target_selection_numbers(uid))
	var mb := MomentumBar.new()
	mb.position = mom_pos
	layer.add_child(mb)
	mb.setup(
		int(pl["momentum"]) - int(pl["momentum_float"]), pl["max_momentum"], int(pl.get("battery", 0)),
		g.momentum_cap(p), int(pl["momentum_float"]), g.battery_cap(p),
	)


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


func _reservoir_rect(p: int) -> Rect2:
	return Rect2(230.0, 700.0 if p == viewer else 24.0, 410.0, 112.0)


func _render_reservoir(p: int) -> void:
	var rect := _reservoir_rect(p)
	var can_ink := false
	if p == viewer and viewer_can_act():
		for hand_card: Card in g.players[p]["hand"]:
			if g.can_store_in_reservoir(p, hand_card.uid):
				can_ink = true
				break
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.04, 0.09, 0.88), 8, Color(UITheme.GOLD, 0.65), 2))
	layer.add_child(panel)
	var caption := make_label(
		"RESERVATÓRIO  •  %d disponíveis" % g.reservoir_ready(p),
		14, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "bold", 2,
	)
	caption.position = Vector2(8, 3)
	caption.size = Vector2(390, 19)
	panel.add_child(caption)
	if p == viewer:
		var instruction := make_label("ARRASTE DA MÃO PARA DEPOSITAR", 10, UITheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, "bold", 1)
		instruction.position = Vector2(175, 3)
		instruction.size = Vector2(225, 18)
		panel.add_child(instruction)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(5, 23)
	scroll.size = Vector2(400, 84)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(scroll)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	scroll.add_child(row)
	for card: Card in g.players[p]["reservoir"]:
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(64, 72)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cell)
		var visible_face := card.reservoir_revealed_turn == g.turn
		var view := CardView.new().setup(card.card_id if visible_face else "", {}, 0.36)
		view.face_down = not visible_face
		view.mouse_filter = Control.MOUSE_FILTER_STOP if visible_face else Control.MOUSE_FILTER_IGNORE
		view.pivot_offset = view.size / 2.0
		view.position = (cell.custom_minimum_size - view.size) / 2.0
		if card.exhausted:
			view.rotation = PI / 2.0
		if visible_face:
			view.left_clicked.connect(table_overlays.show_overlay)
			view.right_clicked.connect(table_overlays.show_overlay)
		cell.add_child(view)
	if p == viewer:
		panel.tooltip_text = "Arraste uma carta da mão para cá para depositá-la permanentemente."
	if p != viewer:
		return
	reservoir_ink_glow = null
	if can_ink:
		reservoir_ink_glow = _add_reservoir_glow(panel, rect.size, INK_BLUE, 2, 12)
		reservoir_ink_glow.modulate.a = 0.45
		var pulse := reservoir_ink_glow.create_tween().set_loops()
		pulse.tween_property(reservoir_ink_glow, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(reservoir_ink_glow, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	reservoir_drop_glow = _add_reservoir_glow(panel, rect.size, SEL, 4, 26)
	reservoir_drop_glow.visible = false


func _add_reservoir_glow(panel: Panel, panel_size: Vector2, color: Color, border_width: int, shadow_size: int) -> Panel:
	var glow := Panel.new()
	glow.size = panel_size
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.draw_center = false
	style.set_corner_radius_all(8)
	style.set_border_width_all(border_width)
	style.border_color = color
	style.shadow_color = Color(color.r, color.g, color.b, 0.85)
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2.ZERO
	style.anti_aliasing = true
	glow.add_theme_stylebox_override("panel", style)
	panel.add_child(glow)
	return glow


## While a dragged card would be deposited, the blue "can deposit" pulse gives way to the yellow glow.
func _show_reservoir_drop_glow(will_deposit: bool) -> void:
	if is_instance_valid(reservoir_drop_glow):
		reservoir_drop_glow.visible = will_deposit
	if is_instance_valid(reservoir_ink_glow):
		reservoir_ink_glow.visible = not will_deposit


func _render_command(p: int, pos: Vector2) -> void:
	var l: Dictionary = g.players[p]["incarnation"]
	if p == viewer:
		var cap := make_label("SANTUÁRIO", 13, Color(UITheme.GOLD, 0.7), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
		cap.position = pos + Vector2(-1, -20)
		cap.size = Vector2(SANCTUARY_W, 16)
		layer.add_child(cap)
	if not l["in_zone"]:
		var where := "EM CAMPO"
		if l.get("retired", false):
			where = "NO DECK"
		elif g.incarnation_in_hand(p):
			where = "NA MÃO"
		var empty := make_label(where, 12, Color(UITheme.TEXT, 0.35), HORIZONTAL_ALIGNMENT_CENTER, "title", 2)
		empty.position = pos + Vector2(-1, 115)
		empty.size = Vector2(SANCTUARY_W, 20)
		layer.add_child(empty)
		return
	var sanctuary_instance := { "permanent_buffs": l.get("permanent_buffs", { }) }
	var v := CardView.new().setup(l["card_id"], display_instance_for_id(l["card_id"], p, 0, sanctuary_instance), SANCTUARY_SCALE)
	v.pivot_offset = v.size / 2.0
	v.position = pos
	v.cost_override = g.incarnation_cost(p)
	v.text_suffix = table_overlays.scale_suffix(p, CardDB.card(l["card_id"]), l["card_id"])
	v.snowball_level = int(g.players[p]["snowball"])
	if p == viewer and g.can_cast_incarnation(p) and not is_ai(p):
		v.highlight = OK
	if p == viewer and (targeting.get("kind") == "incarnation" or (targeting.get("kind") == "room_banish" and targeting["uid"] == 0)):
		v.highlight = SEL
	v.left_clicked.connect(
		func(_v):
			_on_incarnation(p),
	)
	v.right_clicked.connect(table_overlays.show_overlay)
	layer.add_child(v)
	views["cmd%d" % p] = v


## Builds the instance data used by every card outside the board. Persistent upgrades are stored on
## the player's shared state rather than on the printed card JSON, so this keeps Santuário, hand,
## search, stack and graveyard views honest about what that player currently owns.
func display_instance_for_id(card_id: String, owner: int, uid := 0, base_instance: Dictionary = { }) -> Dictionary:
	var instance := base_instance.duplicate(true)
	if uid != 0:
		instance["uid"] = uid
	if g == null or owner < 0 or owner >= g.players.size() or card_id == "":
		return instance
	if not CardDB.data().get("cards", { }).has(card_id):
		return instance
	var cd := CardDB.card(card_id)
	if cd.get("critico_growth", false):
		var shared_critico := int(g.players[owner].get("critico_growth", { }).get(card_id, 0))
		if shared_critico > int(instance.get("critico", 0)):
			instance["critico"] = shared_critico
	return instance


func display_instance_for_card(card: Card) -> Dictionary:
	if card == null:
		return { }
	return display_instance_for_id(card.card_id, card.owner, card.uid, card.to_dict())


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
		var v := CardView.new().setup("", { }, ENEMY_HAND_SCALE)
		v.face_down = true
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.pivot_offset = v.size / 2.0
		v.rotation = PI - deg_to_rad(k * 4.0) # upside down, as if held facing the opponent
		v.position = Vector2(
			lane_cx + EHAND_DX + k * 30 - v.size.x / 2.0,
			_screen_top() - v.size.y * (1.0 - ENEMY_HAND_SHOWN) + k * k * 1.2,
		)
		layer.add_child(v)
	if n > 0:
		var cnt := make_label("%d" % n, 15, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 5)
		cnt.position = Vector2(lane_cx + EHAND_DX + (n - 1) / 2.0 * 30 + 52, _screen_top() + 18.0)
		cnt.size = Vector2(30, 20)
		layer.add_child(cnt)


## Horizontal cell of the unit at `index` in a lane holding `count` units: x = left edge, y = width.
## The lane is centered, so adding a unit shifts every cell (used to open a gap while dragging).
func board_cell(count: int, index: int) -> Vector2:
	var w: float = min(146.0, (TableView.ENEMY_LANE.size.x - 20.0) / max(1, count))
	var x0 := TableView.ENEMY_LANE.get_center().x - count * w / 2.0
	return Vector2(x0 + index * w, w)


func _render_board(p: int, y: float) -> void:
	var board: Array = g.players[p]["board"]
	# units first, then the free-standing artifacts, then the slots frozen by Rei Gelado
	var slots_taken: int = laid_out_slots(p)
	_render_relics(p, y, slots_taken)
	_render_frozen_slots(p, y, slots_taken)
	var barrier_gaps: Array = [] # where this side's Provocação barrier is open (see TableView.set_barrier)
	for i in board.size():
		var unit: Card = board[i]
		var unit_view_data := unit.to_dict()
		unit_view_data["armor_total"] = g.armor_of(unit) # includes Armadura given by adjacent allies
		unit_view_data["constant_sources"] = g.constant_sources_of(unit) # who gives each Constante bonus (card overlay)
		unit_view_data["heal_block_turns_left"] = CardView.heal_block_turns_left(unit.heal_blocked_until, g.turn)
		# summoning sickness is only worth showing while it really keeps the unit from attacking
		unit_view_data["summoning_sick"] = unit.sick and not g.has_kw(unit, "impeto") and not g.has_kw(unit, "rompante")
		# Condicional uses already spent THIS turn (Seymour's "(0/2)"): the stored count belongs to the turn it was spent in
		if int(unit.data().get("conditional_uses_per_turn", 0)) > 0:
			unit_view_data["conditional_uses_now"] = unit.conditional_uses if unit.conditional_uses_turn == g.turn else 0
		# live "N/2" counters of effects that fire every N events (Mali), so the player can track each count
		var event_counters := unit.event_counters()
		if not event_counters.is_empty():
			unit_view_data["event_counters"] = event_counters
		# Constantes that depend on the deck (Ottilia): whether the bonus is on right now
		var constant_conditions := g.constant_conditions_of(unit)
		if not constant_conditions.is_empty():
			unit_view_data["constant_conditions"] = constant_conditions
		var card_size := (CardView.BASE * 1.15).round()
		var cell := board_cell(slots_taken, i)
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
		var reuse_view := (
			is_instance_valid(v) and v.card_id == unit.card_id and v.size == card_size \
					and v.position.is_equal_approx(card_position)
			and is_equal_approx(v.rotation, card_rotation)
		) \
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
			v.right_clicked.connect(table_overlays.show_overlay)
			v.drag_started.connect(_unit_drag_start)
		v.text_suffix = table_overlays.scale_suffix(p, CardDB.card(unit.card_id), unit.card_id)
		v.pivot_offset = v.size / 2.0
		v.position = card_position
		v.rotation = card_rotation
		v.scale = card_scale
		_decorate_unit(v, unit, p)
		# on touch an attacker is also dragged to its target (on a mouse the press already starts the aim)
		v.draggable = CardView.touch_ui() and p == viewer and viewer_can_act() and targeting.is_empty() \
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
		if not unit.equipped_cards.is_empty():
			_render_equipment_preview(unit, p, v, y)
			_render_equipment_badge(unit, p, v, y, card_size)
	table.set_barrier(TableView.SIDE_MINE if p == viewer else TableView.SIDE_ENEMY, barrier_gaps)


func _render_equipment_preview(unit: Card, owner: int, unit_view: CardView, board_y: float) -> void:
	var preview_count := mini(2, unit.equipped_cards.size())
	for preview_index in preview_count:
		var worn_index := unit.equipped_cards.size() - preview_count + preview_index
		var worn: Card = unit.equipped_cards[worn_index]
		var equipment_data := { "uid": worn.uid }
		if worn.durability_left() >= 0:
			equipment_data["durability_left"] = worn.durability_left()
		var preview := CardView.new().setup(worn.card_id, equipment_data, 1.15)
		var peek := 6 + 6 * preview_index
		preview.position = Vector2(
			unit_view.position.x + 4 + 4 * preview_index,
			roundf(board_y + peek if owner == viewer else board_y - peek),
		)
		preview.right_clicked.connect(table_overlays.show_overlay)
		layer.add_child(preview)
		layer.move_child(preview, unit_view.get_index())
		views["eqpreview%d_%d" % [unit.uid, preview_index]] = preview


func _render_equipment_badge(unit: Card, owner: int, unit_view: CardView, board_y: float, card_size: Vector2) -> void:
	var equipment_count := unit.equipped_cards.size()
	var badge := Button.new()
	badge.text = "%d EQ." % equipment_count
	badge.custom_minimum_size = Vector2(78, 28)
	badge.size = badge.custom_minimum_size
	badge.add_theme_font_size_override("font_size", 13)
	badge.focus_mode = Control.FOCUS_NONE
	badge.z_index = 20
	var tooltip := "Clique para inspecionar os equipamentos:"
	for index in mini(4, equipment_count):
		var worn: Card = unit.equipped_cards[index]
		tooltip += "\n- " + String(CardDB.card(worn.card_id).get("name", worn.card_id))
	if equipment_count > 4:
		tooltip += "\n- e mais %d" % (equipment_count - 4)
	badge.tooltip_text = tooltip
	badge.pressed.connect(table_overlays.show_equipment_collection.bind(unit, owner))
	var x := roundf(unit_view.position.x + (unit_view.size.x - badge.size.x) / 2.0)
	var y := roundf(board_y + card_size.y + 14.0 if owner == viewer else board_y - badge.size.y - 14.0)
	badge.position = Vector2(x, y)
	layer.add_child(badge)
	views["eqbadge%d" % unit.uid] = badge


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
		var relic_view_data := { "uid": relic.uid }
		if relic.durability_left() >= 0:
			relic_view_data["durability_left"] = relic.durability_left() # every artifact shows how much Durabilidade it has left
		if relic.data().has("momentum_store"):
			relic_view_data["stored_momentum"] = relic.stored_momentum # Bateria de Segunda Mão shows how much it holds
		# Baluarte Santo is born protected: it needs the golden ring too (and loses ring and tag once it breaks)
		relic_view_data["supreme_shield"] = relic.supreme_shield
		var v := CardView.new().setup(relic.card_id, relic_view_data, 1.15)
		v.text_suffix = table_overlays.scale_suffix(p, CardDB.card(relic.card_id), relic.card_id)
		v.pivot_offset = v.size / 2.0
		var cell := board_cell(slots_taken, first_relic_slot + j)
		v.position = Vector2(cell.x + (cell.y - v.size.x) / 2.0, y)
		v.ability_ready = p == viewer and targeting.is_empty() and viewer_can_act() and g.can_activate(viewer, relic.uid, true)
		v.draggable = p == viewer and targeting.is_empty() and viewer_can_act() and not _input_must_wait() \
				and g.can_equip_from_field(viewer, relic.uid, true)
		var selected_numbers := _target_selection_numbers(relic.uid)
		if not selected_numbers.is_empty():
			v.highlight = SEL
			_add_target_badges(v, selected_numbers)
		elif _is_target(relic.uid):
			v.highlight = TARGET
		v.left_clicked.connect(_on_relic_click)
		v.right_clicked.connect(table_overlays.show_overlay)
		if v.draggable:
			v.drag_started.connect(_relic_drag_start)
		layer.add_child(v)
		views[relic.uid] = v


## How many cells the lane of player p is divided into: taken slots plus the ones frozen by Rei Gelado.
func laid_out_slots(p: int) -> int:
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
		var cell := board_cell(slots_taken, first_frozen_slot + j)
		tile.position = Vector2(cell.x + (cell.y - tile.size.x) / 2.0, y)
		layer.add_child(tile)
		_tag(tile, "CONGELADO", ICE)


func _on_relic_click(v: CardView) -> void:
	if viewer_can_act() and not targeting.is_empty() and _wait_for_table(_pick_target_when_settled.bind(v.uid)):
		return
	if viewer_can_act() and not targeting.is_empty() and _is_target(v.uid):
		_fire_target(v.uid)
	elif targeting.is_empty():
		table_overlays.show_overlay(v)


func _relic_drag_start(v: CardView) -> void:
	if not viewer_can_act() or not targeting.is_empty() or _input_must_wait() \
			or not g.can_equip_from_field(viewer, v.uid, true):
		return
	var artifact := g.find_relic(v.uid)
	if artifact == null:
		return
	var effects: Array = g.card_of(artifact).get("equip_from_field", { }).get("effects", [])
	var spec := g.target_spec(effects)
	if spec == "":
		return
	targeting = { "kind": "field_equip", "uid": v.uid, "spec": spec }
	aim_src = visual_rect_of(v).get_center()
	aim_start = Vector2.INF
	aim_drag = true
	_aim_drag_view = v
	v.highlight = SEL
	for uid in views:
		if uid is int and g.find_unit(uid) != null and views[uid] is CardView:
			(views[uid] as CardView).highlight = TARGET if _is_target(uid) else Color.TRANSPARENT


## A relic (or a spell on the stack) picked as a target during an animation: fires once the table
## settles, if it is still a valid target.
func _pick_target_when_settled(uid: int) -> void:
	if viewer_can_act() and not targeting.is_empty() and _is_target(uid):
		_fire_target(uid)


func _decorate_unit(v: CardView, unit: Card, p: int) -> void:
	# reminder for new players: "Ao Ativar" (and Transformar) can be used now, even the turn it is summoned
	v.ability_ready = (
		p == viewer and targeting.is_empty() and viewer_can_act()
		and (g.can_activate(viewer, unit.uid, true) or g.can_transform(viewer, unit.uid))
	)
	# during combat, a unit with effective Rapidez gets sparks (frozen or stunned units lose it)
	v.rapidez_sparks = (
		g.window != "" and CardView.rapidez_of_view(CardDB.card(unit.card_id), v.inst) > 0 \
				and not v.inst.has("frozen")
		and not v.inst.has("stun_markers")
	)
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
	if p == viewer and targeting.is_empty() and viewer_can_act() and g.combat_system().in_attacks_window(viewer) \
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
	pc.add_child(make_label(t, 11, col.lightened(0.4), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3))
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
		badge.add_child(make_label(str(numbers[i]), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 6))
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
	if picks.is_empty() and targeting.has("first") and not targeting.get("first_is_stack", false):
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
	var now_locked_uids := { } # hand card uid -> true, for every card chained in this render
	var newly_locked_count := 0 # cards that got chained since the previous render (for the ripple delay)
	var unlock_sound_played := false # one latch sound even when several cards are freed together
	for i in n:
		var hand_card: Card = hand[i]
		var v := CardView.new().setup(hand_card.card_id, display_instance_for_card(hand_card), sc)
		var card_data := CardDB.card(hand_card.card_id)
		if g.is_subito_play(p, card_data):
			v.cost_override = g.subito_cost(p, card_data, hand_card) # Súbito: summoned now at its Súbito cost
		elif g.cost_of(p, card_data, hand_card) != int(card_data["cost"]):
			v.cost_override = g.cost_of(p, card_data, hand_card)
		v.text_suffix = table_overlays.scale_suffix(p, card_data, hand_card.card_id)
		v.snowball_level = int(g.players[p]["snowball"])
		v.text_bonuses = g.live_text_bonuses(p, card_data) # amplified damage/draw (Ottilia) shows as "*N*" in the hand
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
		elif g.phase in ["main", "combat"] and g.can_play(p, hand_card.uid, true) and not is_ai(p):
			v.highlight = OK
		elif viewer_can_act() and g.can_store_in_reservoir(p, hand_card.uid):
			v.highlight = INK_BLUE
		v.position = pos
		v.rotation = rot
		v.left_clicked.connect(_on_hand_click)
		v.right_clicked.connect(table_overlays.show_overlay)
		v.draggable = (
			p == viewer and g.phase in ["main", "combat"] and targeting.is_empty()
			and viewer_can_act() and (g.can_play(p, hand_card.uid, true) or g.can_store_in_reservoir(p, hand_card.uid))
		)
		v.drag_started.connect(_hand_drag_start)
		v.drag_moved.connect(_hand_drag_move)
		v.drag_ended.connect(_hand_drag_end)
		var rest := { "pos": pos, "rot": rot, "idx": i, "rise": rise }
		v.set_meta("rest", rest) # where a dragged card flies back to when the table can't be redrawn yet
		v.mouse_entered.connect(_hand_hover.bind(v, true, rest))
		v.mouse_exited.connect(_hand_hover.bind(v, false, rest))
		# Chain lock (ChainLockFx): an effect forbids playing this card right now (Liam Tornagron's "custo 5 ou
		# mais", any restrict_play). The hand is rebuilt on every render, so only a card that was free in the
		# previous render plays the lock-in animation; one that was locked and is free again plays the unlock.
		var forbidden := p == viewer and not is_ai(p) and g.is_play_restricted(p, card_data)
		if forbidden:
			v.locked = true
			if not _locked_hand_uids.has(hand_card.uid):
				var lock_delay := newly_locked_count * LOCK_STAGGER_SECONDS # a quick ripple along the hand
				v.play_lock_in(lock_delay)
				if newly_locked_count < MAX_LOCK_SOUNDS:
					Sfx.play_in("chain_lock", lock_delay + ChainLockFx.SNAP_AT * ChainLockFx.LOCK_IN_SECONDS)
				newly_locked_count += 1
			now_locked_uids[hand_card.uid] = true
		elif _locked_hand_uids.has(hand_card.uid):
			v.locked = true # starts closed so the release can play
			v.play_unlock()
			if not unlock_sound_played:
				Sfx.play("chain_unlock")
				unlock_sound_played = true
		layer.add_child(v)
		views[hand_card.uid] = v
		hand_uids[hand_card.uid] = true
	_locked_hand_uids = now_locked_uids


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
## The line sits at the lower 20% of our Leader plate; the card counts as played when its top edge
## crosses the line, so the pointer does not need to reach it too.
const PLAY_LINE := LEADER_Y_ME + LeaderView.SIZE.y * 0.8 + 1.25
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
	var count: int = laid_out_slots(viewer)
	var slot := 0
	for i in g.players[viewer]["board"].size(): # artifacts always stay after the units
		var cell := board_cell(count, i)
		if x > cell.x + cell.y / 2.0:
			slot += 1
	return slot


## Hearthstone style: our units slide apart to leave a gap at `slot` (-1 = close it again).
func _show_drop_gap(slot: int) -> void:
	if slot == drag_gap_slot:
		return
	drag_gap_slot = slot
	var board: Array = g.players[viewer]["board"]
	var count: int = laid_out_slots(viewer) + (1 if slot >= 0 else 0)
	for relic: Card in g.players[viewer]["relics"]: # artifacts sit after the units, so they always slide right
		var relic_view: Control = views.get(relic.uid)
		if not is_instance_valid(relic_view):
			continue
		var relic_index: int = board.size() + g.players[viewer]["relics"].find(relic) + (1 if slot >= 0 else 0)
		var relic_cell := board_cell(count, relic_index)
		relic_view.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(
			relic_view,
			"position:x",
			relic_cell.x + (relic_cell.y - relic_view.size.x) / 2.0,
			0.12,
		)
	for i in board.size():
		var unit: Card = board[i]
		var unit_view: Control = views.get(unit.uid)
		if not is_instance_valid(unit_view):
			continue
		var cell := board_cell(count, i + (1 if slot >= 0 and i >= slot else 0))
		var new_x := cell.x + (cell.y - unit_view.size.x) / 2.0
		var shift := new_x - unit_view.position.x
		var tw := unit_view.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(unit_view, "position:x", new_x, 0.12)
		var equipment_badge: Control = views.get("eqbadge%d" % unit.uid)
		if is_instance_valid(equipment_badge):
			var badge_tw := equipment_badge.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			badge_tw.tween_property(equipment_badge, "position:x", equipment_badge.position.x + shift, 0.12)
		for preview_index in mini(2, unit.equipped_cards.size()):
			var equipment_preview: Control = views.get("eqpreview%d_%d" % [unit.uid, preview_index])
			if is_instance_valid(equipment_preview):
				var preview_tw := equipment_preview.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				preview_tw.tween_property(equipment_preview, "position:x", equipment_preview.position.x + shift, 0.12)


func _dragged_hand_card_is_over_play_line(v: CardView, pointer_position: Vector2) -> bool:
	return pointer_position.y - v.size.y * 0.75 < PLAY_LINE


func _hand_drag_move(v: CardView) -> void:
	var m := layer.get_global_transform().affine_inverse() * v.input_position
	var over_reservoir := _reservoir_rect(viewer).has_point(m)
	var will_deposit := over_reservoir and viewer_can_act() and g.can_store_in_reservoir(viewer, v.uid)
	_show_reservoir_drop_glow(will_deposit)
	_set_card_sinking_into_reservoir(v, will_deposit)
	var over_play_line := _dragged_hand_card_is_over_play_line(v, m)
	var is_unit: bool = CardDB.card(v.card_id)["type"] == "unit"
	# during an animation the board is left alone (the gap would fight the moving units) and no aim
	# starts: the card just follows the finger, and dropping it plays it once the animation ends
	var table_busy := _input_must_wait()
	if (
		is_unit and over_play_line and not over_reservoir and viewer_can_act()
		and not v.get_meta("aim", false) and not table_busy and g.can_play(viewer, v.uid, true)
	):
		_show_drop_gap(_drop_slot(m.x))
	elif not table_busy:
		_show_drop_gap(-1)
	if (
		v.get_meta("aim", false) and TableView.MY_LANE.has_point(m) and not over_reservoir
		and targeting.is_empty() and viewer_can_act() and not table_busy and g.can_play(viewer, v.uid, true)
	):
		# a targeted card crossing into the board turns into an aim: it goes back to the hand
		# (raised) and an arrow follows the finger; releasing on a target plays it there
		# (a unit with a sacrifice cost also remembers the slot it was dragged to)
		targeting = { "kind": "hand", "uid": v.uid, "card_id": v.card_id, "spec": _hand_spec(v), "slot": _drop_slot(m.x) }
		aim_drag = true
		_aim_drag_view = v
		aim_start = Vector2.INF
		render_table()
		return
	v.position = m - Vector2(v.size.x / 2.0, v.size.y * 0.75)
	if will_deposit:
		v.highlight = Color.TRANSPARENT
	else:
		v.highlight = SEL if over_play_line or over_reservoir else OK


## Over the Reservatório the dragged card shrinks, tilts and takes an ink-blue tint, as if already
## sinking in; leaving the area brings it back to its normal drag look.
func _set_card_sinking_into_reservoir(v: CardView, sinking: bool) -> void:
	if bool(v.get_meta("sinking", false)) == sinking:
		return
	v.set_meta("sinking", sinking)
	if v.has_meta("tw"):
		var old: Tween = v.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	var tw := v.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	v.set_meta("tw", tw)
	tw.tween_property(v, "zoom", 0.62 if sinking else 1.12, 0.16)
	tw.tween_property(v, "rotation", -0.12 if sinking else 0.0, 0.16)
	tw.tween_property(v, "modulate", Color(0.62, 0.82, 1.0, 0.9) if sinking else Color.WHITE, 0.16)


func _hand_drag_end(v: CardView) -> void:
	_show_reservoir_drop_glow(false)
	v.set_meta("sinking", false)
	v.modulate = Color.WHITE
	var m := layer.get_global_transform().affine_inverse() * v.input_position
	if _reservoir_rect(viewer).has_point(m):
		if _input_must_wait():
			_hand_card_back_to_rest(v)
			_queued_inputs.append(_store_hand_card_when_settled.bind(v.uid))
		elif viewer_can_act():
			handle_action_result(g.store_in_reservoir(viewer, v.uid))
		return
	var over_play_line := _dragged_hand_card_is_over_play_line(v, m)
	if _input_must_wait():
		# an animation is playing: the card flies back to the hand and, if it was dropped on the board,
		# is played from there as soon as the animation ends
		_hand_card_back_to_rest(v)
		if over_play_line and viewer_can_act():
			_queued_inputs.append(_play_hand_card_when_settled.bind(v.uid, _drop_slot(m.x)))
			v.highlight = SEL
		return
	drag_gap_slot = -1
	if over_play_line and viewer_can_act():
		_play_from_hand(v, _drop_slot(m.x))
	else:
		render_table()


func _store_hand_card_when_settled(uid: int) -> void:
	if viewer_can_act() and g.can_store_in_reservoir(viewer, uid):
		handle_action_result(g.store_in_reservoir(viewer, uid))
	else:
		show_toast("Não dá para depositar essa carta agora.")
		render_table()


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
	if viewer_can_act() and is_instance_valid(view) and view is CardView and hand_uids.has(uid):
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
	var title := make_label("CRÔNICA", 15, UITheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	title.position = Vector2(0, 7)
	title.size = Vector2(COL_W, 20)
	chronicle_panel.add_child(title)
	chronicle_panel.add_child(menu_screens.ornament(Vector2(COL_W / 2.0, 31), 92))

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

	var shown: Array = chronicle_log.chronicle_entries
	if shown.is_empty() and not chronicle_log.log_lines.is_empty():
		shown = [
			{ "text": chronicle_log.log_lines[-1], "kind": "info", "icon": "dot", "accent": UITheme.GOLD, "label": "EVENTO", "seq": 0 }
		]
	if shown.is_empty():
		var empty_note := make_label("Nada aconteceu ainda.", 14, Color(UITheme.TEXT, 0.4), HORIZONTAL_ALIGNMENT_CENTER, "body")
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
		row.card_clicked.connect(_show_chronicle_card_overlay)
		rows_box.add_child(row)
		newest_seq = maxi(newest_seq, seq)
	_chronicle_seen_seq = newest_seq
	scroll.call_deferred("set", "scroll_vertical", 999999)

	# the oldest rows fade out under the top edge of the list instead of being cut flat
	var top_fade := Control.new()
	top_fade.position = well.position
	top_fade.size = Vector2(list_size.x, 16)
	top_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_fade.draw.connect(
		func():
			for line in 16:
				top_fade.draw_line(
					Vector2(0, line + 0.5),
					Vector2(list_size.x, line + 0.5),
					Color(0.035, 0.03, 0.055, 0.9 * (1.0 - line / 16.0)),
					1.0,
				),
	)
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
		chronicle_scene.card_clicked.connect(_show_chronicle_card_overlay)
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


func _show_chronicle_card_overlay(card_id: String) -> void:
	if not CardDB.data().get("cards", { }).has(card_id):
		return
	table_overlays.show_overlay(CardView.new().setup(card_id))


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
	var phase_names := {
		"mulligan": "Mulligan",
		"main": "Fase Principal",
		"discard": "Banimento",
		"over": "Fim de jogo",
		"combat": "Combate · " + { "pre_combat": "Preparação", "attacks": "Ataques" }.get(g.window, ""),
		"search": "Busca",
		"enter_target": "Ao Entrar · alvo",
		"enter_tapped": "Provocação · entrada",
	}
	var mine := g.decider() == viewer and not is_ai(viewer)
	var my_turn := g.active == viewer
	if g.phase == "mulligan":
		my_turn = mine
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
	# no turn number on purpose: the global counter counts both players' turns, which confuses
	var tt := make_label(
		"SEU TURNO" if my_turn else "TURNO DO OPONENTE",
		24 if my_turn else 20,
		UITheme.GOLD_LIGHT,
		HORIZONTAL_ALIGNMENT_CENTER,
		"title_bold",
		4,
	)
	tt.position = Vector2(0, 4)
	tt.size = Vector2(COL_W, 30)
	tp.add_child(tt)
	var ph_t: String = phase_names.get(g.phase, g.phase)
	if not g.stack.is_empty():
		ph_t = "Resposta · pilha %d" % g.stack.size()
	elif g.summon_window:
		ph_t = "Resposta · invocação"
	var ph := make_label(ph_t, 17, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	ph.position = Vector2(0, 33)
	ph.size = Vector2(COL_W, 22)
	tp.add_child(ph)
	var d := g.decider()
	var who := ""
	if mine:
		who = "SUA VEZ" if my_turn else "SUA PRIORIDADE"
	elif is_ai(d):
		who = "VEZ DA IA"
	elif online:
		who = "VEZ DO OPONENTE"
	else:
		who = "VEZ DO JOGADOR %d" % (d + 1)
	var wl := make_label(who, 15, UITheme.GOLD if mine else Color(UITheme.TEXT, 0.5), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
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
		var wait := make_button(
			"TURNO DO OPONENTE",
			func():
				pass,
		)
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
	var ap := make_toggle_button(
		"AUTO-PASSE",
		ap_on,
		func():
			_set_auto_pass(not _auto_pass_on()),
	)
	ap.position = Vector2(col_x, 772.0 + BOT)
	ap.size = Vector2(COL_W, 48)
	ap.tooltip_text = "Pula sozinho as janelas em que você não tem nenhuma jogada válida."
	layer.add_child(ap)
	var half := (COL_W - 8.0) / 2.0
	# during the match "Menu" opens the pause menu (settings, concede, leave); once it is over there is nothing left to pause
	var menu := make_button("Menu", menu_screens.show_menu if g.phase == "over" else table_overlays.open_pause_menu)
	menu.position = Vector2(col_x, 832.0 + BOT)
	menu.size = Vector2(COL_W if g.phase == "over" else half, 52)
	menu.add_theme_font_size_override("font_size", 20)
	layer.add_child(menu)
	if g.phase != "over":
		var cc := make_button("Conceder", table_overlays.ask_concede)
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
	# a card that jumps into play from the deck (Rusco) is shown only to its owner: it is hidden information
	var watch := { }
	if player == viewer:
		var watches := g.deck_summon_watches(player)
		if not watches.is_empty():
			watch = watches[0]
	deck_pile.set_watch(watch)
	deck_pile.show_count(g.players[player]["deck"].size(), g.fatigue_next(player))
	deck_pile.watch_tapped.connect(
		func(card_id: String):
			table_overlays.show_overlay(CardView.new().setup(card_id, { }, 1.0)),
	)
	var watch_state := String(watch.get("state", ""))
	if watch_state == "ready" and _deck_watch_states.get(player, "") != "ready":
		deck_pile.ignite()
	_deck_watch_states[player] = watch_state
	deck_piles[player] = deck_pile
	var graveyard: Array = g.players[player]["graveyard"]
	var top_card_id := ""
	var top_instance := { }
	if not graveyard.is_empty():
		var top_card: Card = graveyard.back()
		top_card_id = top_card.card_id
		top_instance = display_instance_for_id(top_card_id, player, top_card.uid)
	# only the viewer can cast Réquiem spells from their own graveyard: no green glow on the opponent's
	var castable_requiem: int = table_overlays.requiem_uids(viewer).size() if player == viewer else 0
	var graveyard_pile := GraveyardPile.new().setup(graveyard.size(), top_card_id, top_instance, castable_requiem, PILE_CARD_SCALE)
	graveyard_pile.position = graveyard_position
	graveyard_pile.clicked.connect(
		func():
			table_overlays.show_graveyard(player),
	)
	layer.add_child(graveyard_pile)
	graveyard_piles[player] = graveyard_pile


## Where `player`'s graveyard is on the stage: milled cards land there, Réquiem spells rise from it.
func graveyard_pose(player: int) -> Dictionary:
	var graveyard_pile = graveyard_piles.get(player)
	if is_instance_valid(graveyard_pile):
		return { "c": graveyard_pile.position + graveyard_pile.top_center(), "rot": 0.0, "w": graveyard_pile.card_size_on_screen().x }
	var leader_view = views.get(GameState.LEADER_UID[player])
	if leader_view is LeaderView:
		return { "c": leader_view.position + LeaderView.GRAVE_CENTER, "rot": 0.0, "w": LeaderView.deck_card_width() * 0.6 }
	return { "c": Vector2(lane_cx, LEADER_Y_ME if player == viewer else 30.0), "rot": 0.0, "w": LeaderView.deck_card_width() * 0.6 }


## Where the top card of `player`'s deck is on the stage, and how wide it is there:
## cards drawn, milled or summoned from the deck start their flight from this pose.
func _deck_top_pose(player: int) -> Dictionary:
	var deck_size: int = g.players[player]["deck"].size()
	var deck_pile = deck_piles.get(player)
	if is_instance_valid(deck_pile):
		return { "c": deck_pile.position + deck_pile.top_center(deck_size), "rot": 0.0, "w": deck_pile.card_width() }
	var leader_view = views.get(GameState.LEADER_UID[player])
	if leader_view is LeaderView:
		return { "c": leader_view.position + LeaderView.deck_top_center(deck_size), "rot": 0.0, "w": LeaderView.deck_card_width() }
	return { "c": Vector2(lane_cx, LEADER_Y_ME if player == viewer else 30.0), "rot": 0.0, "w": LeaderView.deck_card_width() }


## The stack as a pile of full cards at the right edge of the table, oldest on top and the
## next one to resolve in front (Arena style). Tap/right-click/hold a card to read it; the
## front card draws an arrow to what it targets.
const STACK_SCALE := 1.3
const STACK_STEP := 80.0 ## vertical peek per card; shrinks when the pile would not fit
const STACK_MAX_H := 590.0
const STACK_MAX := 6
var _stack_seen := { } ## sid -> true for items already drawn once (only new ones animate in)


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
	var head := make_label("PILHA · %d" % g.stack.size(), 16, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	head.position = Vector2(px, py + 10)
	head.size = Vector2(pw, 22)
	layer.add_child(head)
	if hidden > 0:
		var more := make_label("+%d antigas" % hidden, 12, Color(UITheme.TEXT, 0.55), HORIZONTAL_ALIGNMENT_CENTER, "body")
		more.position = Vector2(px, py + 30)
		more.size = Vector2(pw, 14)
		layer.add_child(more)
	var cx := px + 16.0
	var y0 := py + 44.0
	var centers := { } ## sid -> center of that card, for arrows that point at a stack item
	var seen := { }
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
			var v := CardView.new().setup(
				stack_card_id,
				display_instance_for_id(stack_card_id, stack_owner, int(it.get("uid", 0))),
				STACK_SCALE,
			)
			v.snowball_level = int(g.players[stack_owner]["snowball"])
			v.text_bonuses = g.live_text_bonuses(stack_owner, CardDB.card(stack_card_id))
			v.text_suffix = table_overlays.scale_suffix(stack_owner, CardDB.card(stack_card_id), stack_card_id)
			v.left_clicked.connect(
				func(view: CardView):
					# a spell on the stack picked as a target during an animation waits for its turn
					if viewer_can_act() and not targeting.is_empty() and _wait_for_table(_pick_target_when_settled.bind(sid)):
						return
					if _is_target(sid):
						_fire_target(sid)
					else:
						table_overlays.show_overlay(view),
			)
			v.right_clicked.connect(table_overlays.show_overlay)
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
		if it["kind"] in ["unit_ability", "artifact_equip", "subito", "enter_trigger"]:
			var rb := _stack_pill(
				{ "unit_ability": "AO ATIVAR", "artifact_equip": "EQUIPAR", "subito": "SÚBITO", "enter_trigger": "AO ENTRAR" }[
					it["kind"]
				],
				UITheme.GOLD_LIGHT,
			)
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
	var sp: String = { "lento": "Lento", "rapido": "Rápido", "instantaneo": "Instantâneo" }.get(top["speed"], "")
	var cap := make_label(
		"%s · %s\nresolve primeiro" % [player_name(top["player"]), sp],
		13,
		Color(UITheme.TEXT, 0.7),
		HORIZONTAL_ALIGNMENT_CENTER,
		"body",
	)
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
		to = fx_library.pose_of(views[t])["c"]
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
	pc.add_child(make_label(t, 12, col, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
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
		pnl.gui_input.connect(
			func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_fire_target(sid),
		)
	else:
		pnl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pnl.add_theme_stylebox_override("panel", sb)
	var nm := make_label(String(lead["ability"]["name"]), 19, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	nm.position = Vector2(8, 8)
	nm.size = Vector2(sz.x - 16, 56)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pnl.add_child(nm)
	var sub := make_label(
		"Habilidade de Líder\n%s" % String(lead.get("name", "")),
		13,
		Color(UITheme.TEXT, 0.7),
		HORIZONTAL_ALIGNMENT_CENTER,
		"body",
	)
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
			var punishment := _stack_punishment(card_data, sid)
			if punishment >= 0:
				return "Dano: %d" % punishment # Represália Ardente: it punishes, it does not anular
			var extra := g.counter_extra(card_data, sid)
			return "Anular: %d" % (g.cost_of(viewer, card_data) + extra) + (" (+%d)" % extra if extra > 0 else "")
	return ""


## True for a spell that answers a stack item with damage instead of an anular (Represália Ardente).
func _punishes_stack(card_data: Dictionary) -> bool:
	for effect in card_data.get("effects", []):
		if effect.get("action") == "damage_leader_by_stack_cost":
			return true
	return false


## Damage a "punish by cost" spell (Represália Ardente) would deal to the Leader of whoever played stack item
## `sid`, or -1 when the card has no such effect.
func _stack_punishment(card_data: Dictionary, sid: int) -> int:
	if not _punishes_stack(card_data):
		return -1
	for effect in card_data["effects"]:
		for item in g.stack:
			if item["sid"] == sid:
				return mini(g.stack_cost(item), int(effect.get("max", 999)))
	return -1


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
	pc.add_child(make_label(t, 26, col, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	layer.add_child(pc)
	pc.reset_size()
	pc.position = Vector2(TableView.ENEMY_LANE.get_center().x - pc.size.x / 2.0, TableView.DIVIDER_Y + 18) # below the divider emblem
	var now := Time.get_ticks_msec()
	if t != hint_text:
		hint_text = t
		hint_since = now
	hint_pill = pc
	if not targeting.is_empty() or g.phase in ["search", "discard", "enter_tapped", "effect_choice"]:
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
	if not is_instance_valid(hint_pill) or hint_pill.modulate.a > 0.01 or not viewer_can_act():
		return
	hint_until = Time.get_ticks_msec() + 5000
	_hint_fade(hint_pill, 5.0)


func _process(dt: float) -> void:
	CardView.load_queued_arts()
	if is_instance_valid(hub_scroll) and not hub_scroll.is_queued_for_deletion() and hub_scroll.is_visible_in_tree():
		menu_screens.refresh_hub_stats_if_due()
	_update_aim()
	_sync_reaction_arrow()
	if _fps_counter_visible and is_instance_valid(_fps_counter):
		_fps_sample_seconds += dt
		_fps_sample_frames += 1
		if _fps_sample_seconds >= 0.5:
			var fps := roundi(_fps_sample_frames / _fps_sample_seconds)
			_fps_counter.text = _performance_summary(fps) if _perf_diagnostics else "FPS %d" % fps
			_fps_sample_seconds = 0.0
			_fps_sample_frames = 0
	if g and Time.get_ticks_msec() - last_input_ms > 15000:
		last_input_ms = Time.get_ticks_msec()
		_hint_nudge()


func _hint() -> String:
	if targeting.get("kind") == "effect_choice":
		return "Escolha um alvo para o efeito · botão direito/Esc volta às opções."
	if g.phase == "effect_choice":
		return "Escolha um efeito." if viewer_can_act() else "O oponente está escolhendo um efeito."
	if g.phase == "search":
		if g.pending_search.get("summon_from", false):
			return "Escolha uma carta para invocar de graça, ou não invoque nenhuma."
		if g.pending_search.get("hand_summon", false):
			return "Escolha um campeão da sua mão para entrar em campo de graça."
		if g.pending_search.get("own_hand_bottom", false):
			return "Escolha uma carta da sua mão para ir ao fundo do deck (e comprar %d), ou não escolha nenhuma." % int(
				g.pending_search.get("draw_after", 1)
			)
		if g.pending_search.get("hand_bottom", false):
			if int(g.pending_search.get("cost_increase", 0)) > 0:
				return "Escolha uma carta da mão do oponente para custar %d a mais, ou não escolha nenhuma." % int(
					g.pending_search["cost_increase"]
				)
			return "Escolha uma carta da mão do oponente para ir ao fundo do deck dele, ou não escolha nenhuma."
		if g.pending_search.get("sacrifice_pick", false):
			return "Escolha uma unidade sua para sacrificar."
		if g.pending_search.get("reservoir_pick", false):
			return "Escolha qual carta vai para o Reservatório: a do topo ou a do fundo do deck."
		if g.pending_search.get("grave_optional", false):
			return "Rebobinar: escolha uma carta do cemitério para levar à mão, ou não pegue nenhuma."
		if g.pending_search.get("discard_hand", false):
			return "Escolha uma carta da sua mão para descartar."
		return "Escolha uma das cartas reveladas."
	if targeting.get("kind") == "enter":
		var which := "segundo alvo" if g.pending_enter.has("first") else "alvo"
		return "Ao Entrar de %s: toque no %s ou pule o efeito." % [card_name(g.pending_enter.get("card_id", "")), which]
	if targeting.get("kind") == "room_banish":
		var banish_prompt := "Campo cheio: toque na unidade ou artefato seu que será banido para abrir espaço" if CardView.touch_ui() \
				else "Campo cheio: clique na unidade ou artefato seu que será banido para abrir espaço"
		return banish_prompt + " · toque fora cancela." if CardView.touch_ui() else banish_prompt + " · botão direito/Esc cancela."
	if targeting.get("kind") == "unit_cost":
		var cost_prompt := "Custo adicional: toque noutra unidade aliada para sacrificá-la" if CardView.touch_ui() \
				else "Custo adicional: clique noutra unidade aliada para sacrificá-la"
		return cost_prompt + " · toque fora cancela." if CardView.touch_ui() else cost_prompt + " · botão direito/Esc cancela."
	if targeting.get("kind") == "attack":
		# say why some targets don't glow: a Provocação forces the challenge, and a unit that
		# just came in with Ímpeto can only challenge
		var attacker := g.find_unit(targeting["uid"])
		var taunts: Array = g.combat_system().forced_taunts(attacker) if attacker != null else []
		if not taunts.is_empty():
			var taunt_names: Array = []
			for taunt_uid in taunts:
				taunt_names.append(card_name(g.find_unit(taunt_uid).card_id))
			return "Provocação: este ataque precisa desafiar %s." % " ou ".join(taunt_names)
		if attacker != null and g.combat_system().is_rompante_rush(attacker):
			return "Rompante: no turno em que entra, ela pode atacar o Líder (só uma Provocação a segura)."
		if attacker != null and attacker.sick:
			return "Ímpeto: no turno em que entra, ela só pode desafiar (o Líder fica para o próximo turno)."
		if CardView.touch_ui():
			return "Toque no alvo que brilha (Líder ou unidade exaurida) · toque fora cancela."
		return "Arraste até o alvo que brilha (Líder ou unidade exaurida) · botão direito/Esc cancela."
	if not targeting.is_empty():
		if targeting.get("first_is_stack", false):
			return "Escolha a unidade que paga o custo extra desta carta."
		if targeting.has("first"):
			var second_hint := (
				"1º alvo escolhido. Escolha o 2º alvo (pode ser o mesmo)."
				if CardDB.card(targeting["card_id"]).get("same_target_ok", false)
				else "1º alvo escolhido. Escolha o 2º alvo."
			)
			return second_hint
		var t := (
			"Arraste até o alvo (ou toque nele) · toque fora cancela."
			if CardView.touch_ui()
			else "Arraste até o alvo (ou clique nele) · botão direito/Esc cancela."
		)
		if targeting["spec"] == "enemy_stack":
			t = "Toque no feitiço/habilidade da pilha que quer anular."
			if targeting.has("card_id") and _punishes_stack(CardDB.card(targeting["card_id"])): # an Ao Ativar has no card_id
				t = "Toque no feitiço/habilidade da pilha que quer punir."
		return t
	if g.decider() != viewer or is_ai(viewer):
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
			return "%s tem Provocação: entrar exaurida obriga os inimigos a desafiá-la." % card_name(_pending_tap_card_id())
		"mulligan":
			return "Clique em até 3 cartas para trocar."
		"discard":
			return "Mão acima do limite: escolha %d para banir." % (g.players[viewer]["hand"].size() - GameState.HAND_LIMIT)
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
	return g.phase in ["main", "combat"] and g.active != viewer and not is_ai(viewer)


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
	var button := make_toggle_button(title, is_on, _on_pass_all_pressed)
	button.tooltip_text = (
		"Não pergunta mais por respostas até o turno do oponente acabar. "
		+ "Vale a partir da próxima jogada dele; só avisa se ela for matar o seu Líder."
	)
	return button


func _on_pass_all_pressed() -> void:
	if _pass_all_arming: # still inside the undo window: take it back here, nothing was sent
		_pass_all_arming = false
		render_table()
		return
	if _pass_all_waiting_for_server:
		return # the server has not answered the last press yet
	if g.skip_rest_of_turn[viewer]:
		_send_pass_all(false)
		return
	_pass_all_arming = true
	_pass_all_arming_id += 1
	var arming_id := _pass_all_arming_id
	get_tree().create_timer(PASS_ALL_UNDO_SECONDS).timeout.connect(
		func():
			if _pass_all_arming and arming_id == _pass_all_arming_id:
				_pass_all_arming = false
				_send_pass_all(true),
	)
	render_table()


## Sends the switch to the engine (or the server). Online, the switch keeps showing "…" until the snapshot echoes it.
func _send_pass_all(on: bool) -> void:
	if g == null or g.phase not in ["main", "combat"] or (on and g.active == viewer):
		render_table() # the turn changed while the press was waiting: nothing to switch any more
		return
	if g is RemoteState:
		_pass_all_waiting_for_server = true
		_pass_all_expected_state = on
		get_tree().create_timer(PASS_ALL_SERVER_TIMEOUT_SECONDS).timeout.connect(_stop_waiting_for_pass_all)
	run_or_queue_input(
		func():
			handle_action_result(g.pass_rest_of_turn(viewer) if on else g.cancel_pass_rest_of_turn(viewer)),
	)
	render_table()


## The server never answered (or refused): the switch goes back to showing the real state.
func _stop_waiting_for_pass_all() -> void:
	if _pass_all_waiting_for_server:
		_pass_all_waiting_for_server = false
		if g != null:
			render_table()


func _action_buttons() -> Array:
	var out: Array = []
	match g.phase:
		"mulligan":
			out.append(
				_action_button(
					"CONFIRMAR (%d)" % picked.size(),
					func():
						handle_action_result(g.mulligan(viewer, picked.duplicate())),
					true,
				)
			)
		"combat":
			if g.combat_system().in_attacks_window(viewer):
				out.append(
					_action_button(
						"ENCERRAR COMBATE",
						func():
							handle_action_result(g.end_combat(viewer)),
						true,
					)
				)
			else:
				out.append(
					_action_button(
						_pass_button_label(),
						func():
							handle_action_result(g.pass_priority(viewer)),
						true,
					)
				)
		"main":
			if not g.stack.is_empty() or g.summon_window:
				out.append(
					_action_button(
						_pass_button_label(),
						func():
							handle_action_result(g.pass_priority(viewer)),
						true,
					)
				)
			elif g.can_go_to_combat(viewer):
				out.append(
					_action_button(
						"IR PARA O COMBATE",
						func():
							handle_action_result(g.go_to_combat(viewer)),
						true,
					)
				)
				out.append(
					_action_button(
						"Encerrar turno",
						func():
							handle_action_result(g.end_turn(viewer)),
					)
				)
			else:
				out.append(
					_action_button(
						"ENCERRAR TURNO",
						func():
							handle_action_result(g.end_turn(viewer)),
						true,
					)
				)
		"enter_tapped":
			out.append(
				_action_button(
					"ENTRAR EXAURIDA",
					func():
						handle_action_result(g.choose_enter_tapped(viewer, true)),
					true,
				)
			)
			out.append(
				_action_button(
					"ENTRAR PRONTA",
					func():
						handle_action_result(g.choose_enter_tapped(viewer, false)),
					true,
				)
			)
		"enter_target":
			out.append(
				_action_button(
					"PULAR EFEITO",
					func():
						handle_action_result(g.choose_enter_target(viewer, 0)),
					true,
				)
			)
		"discard":
			var need: int = g.players[viewer]["hand"].size() - GameState.HAND_LIMIT
			var b := _action_button(
				"BANIR (%d/%d)" % [picked.size(), need],
				func():
					handle_action_result(g.discard(viewer, picked.duplicate())),
				true,
			)
			b.disabled = picked.size() != need
			out.append(b)
	return out


func _render_game_over() -> void:
	var pc := make_veil()
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
	var big := make_label(txt, 64 if txt.length() < 10 else 44, title_color, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 10)
	big.add_theme_color_override("font_shadow_color", Color(glow_color, 0.35))
	big.add_theme_constant_override("shadow_outline_size", 24)
	big.add_theme_constant_override("shadow_offset_x", 0)
	big.add_theme_constant_override("shadow_offset_y", 0)
	box.add_child(big)
	if g.winner < 2:
		var sub := "%s triunfa na arena" % CardDB.leader(g.players[g.winner]["leader_id"])["name"]
		if conceded >= 0:
			sub = "%s desistiu da partida" % ("Você" if (vs_ai and conceded == 0) else player_name(conceded))
		box.add_child(make_label(sub, 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	else:
		box.add_child(make_label("Os dois Líderes caíram juntos", 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var b := make_button("VOLTAR AO MENU", menu_screens.show_menu, true)
	b.custom_minimum_size = Vector2(520, 54)
	box.add_child(b)
	center_in_screen.call_deferred(pc)

# ---------------------------------------------------------------- input


## Window <-> full screen (F11 or the menu button). In a browser this is the page's full screen,
## which the browser only allows right after a key press or tap, which is what calls this.
func toggle_fullscreen() -> void:
	var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _toggle_fps_counter() -> void:
	_fps_counter_visible = not _fps_counter_visible
	if not is_instance_valid(_fps_counter):
		_fps_counter = make_label("FPS 0", 14 if _perf_diagnostics else 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, "bold", 4)
		_fps_counter.position = Vector2(14, 12)
		_fps_counter.size = Vector2(560, 126) if _perf_diagnostics else Vector2(150, 32)
		_fps_counter.z_index = 1000
		add_child(_fps_counter)
	_fps_sample_seconds = 0.0
	_fps_sample_frames = 0
	_fps_counter.visible = _fps_counter_visible
	_fps_counter.move_to_front()


func _performance_diagnostics_requested() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('perf') === '1'"))


func _performance_summary(fps: int) -> String:
	var mib := 1024.0 * 1024.0
	var memory_now := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var memory_peak := int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	var texture_memory := int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	var buffer_memory := int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var art_stats := CardView.texture_cache_stats()
	var photo_stats := CardPhotoStudio.cache_stats()
	var art_mib := float(art_stats["estimated_bytes"]) / mib
	var photo_mib := float(photo_stats["pixels"]) * 4.0 / mib
	return (
		"FPS %d · Godot %d/%d MB · nós %d\nGPU: texturas %d MB / buffers %d MB\n"
		+ "Artes: %d (%d carregadas, ~%.0f MB) · fila %d\nFotos: %d (~%.0f MB) · pedidos %d · pendentes %d"
	) % [
		fps,
		roundi(memory_now / mib),
		roundi(memory_peak / mib),
		node_count,
		roundi(texture_memory / mib),
		roundi(buffer_memory / mib),
		art_stats["entries"],
		art_stats["loaded"],
		art_mib,
		art_stats["preload_queue"],
		photo_stats["photos"],
		photo_mib,
		photo_stats["requests"],
		photo_stats["unfinished"],
	]


func _close_dev_tools() -> void:
	if not is_instance_valid(dev_tools_panel):
		return
	dev_tools_panel.hide()
	if g != null and g.phase != "over" and is_ai(g.decider()) and ai_timer.is_stopped():
		ai_timer.start(0.55)


func _toggle_dev_tools() -> void:
	if not dev_mode_enabled:
		return
	if dev_tools_panel.visible:
		_close_dev_tools()
		return
	if g == null or online or g is RemoteState or not table.visible or g.phase == "over":
		return
	dev_tools_panel.refresh(g, vs_ai, viewer)
	dev_tools_panel.show()
	ai_timer.stop()


func _on_dev_tool_action(action: String, parameters: Dictionary) -> void:
	if not dev_mode_enabled or g == null or online or g is RemoteState or g.phase == "over":
		dev_tools_panel.set_result("Ação disponível apenas em uma partida local ativa.", true)
		return
	var state := g as GameState
	var player := int(parameters.get("player", -1))
	var events: Array = []
	match action:
		"draw_cards":
			events = state.debug_draw_cards(player, int(parameters.get("amount", 1)))
		"draw_specific":
			var card_id := String(parameters.get("card_id", ""))
			var found := false
			for card: Card in state.players[player]["deck"] if player >= 0 and player < state.players.size() else []:
				if card.card_id == card_id:
					found = true
					break
			if not found:
				dev_tools_panel.set_result("Essa carta não está mais no deck selecionado.", true)
				return
			events = state.debug_draw_specific_card(player, card_id)
		"add_momentum":
			events = state.debug_add_momentum(player, int(parameters.get("amount", 1)))
		"refill_momentum":
			events = state.debug_refill_momentum(player)
		"refill_battery":
			events = state.debug_refill_battery(player)
		"raise_leader_max":
			events = state.debug_raise_leader_max(player, int(parameters.get("amount", 1)))
		"heal_leader":
			events = state.debug_heal_leader(player)
		"damage_leader":
			events = state.debug_damage_leader(player, int(parameters.get("amount", 1)))
		_:
			dev_tools_panel.set_result("Ferramenta de desenvolvimento desconhecida.", true)
			return
	dev_tools_panel.refresh(g, vs_ai, viewer)
	if events.is_empty():
		render_table()
		dev_tools_panel.set_result("Nenhuma mudança foi necessária.")
		return
	for event in events:
		chronicle_log.log_event(event)
	_show_events(events)
	dev_tools_panel.set_result("Ação aplicada.")


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F12 and dev_mode_enabled:
		_toggle_dev_tools()
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3:
		_toggle_fps_counter()
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F11:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	# here (not in _unhandled_input) so a button that kept the focus from a click does not swallow Space / Enter
	if e is InputEventKey and e.pressed and not e.echo:
		var key_used := false
		if join_slots != null:
			key_used = menu_screens.join_screen_key(e)
		elif e.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			key_used = menu_screens.press_main_action_with_keyboard()
		if key_used:
			get_viewport().set_input_as_handled()
			return
	if aim_drag and e is InputEventScreenTouch and not e.pressed:
		_aim_release(get_viewport().get_canvas_transform().affine_inverse() * e.position, true)
	elif _queued_attacker_dragging and e is InputEventScreenTouch and not e.pressed:
		_release_queued_attacker_drag(get_viewport().get_canvas_transform().affine_inverse() * e.position)
	elif aim_drag and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		_aim_release()
	elif _queued_attacker_dragging and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		_release_queued_attacker_drag()
	if e is InputEventMouseButton or e is InputEventScreenTouch or e is InputEventKey:
		last_input_ms = Time.get_ticks_msec()
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		CardView.touched = true
	if e is InputEventScreenTouch and e.pressed:
		finger_press_position = e.position
		finger_is_swiping = false
	# the Chronicle scene stays open while the pointer is on the list; moving or tapping elsewhere closes it
	if chronicle_scene and chronicle_scene.visible and (e is InputEventMouseMotion or (e is InputEventMouseButton and e.pressed)):
		var pointer := get_local_mouse_position()
		var scene_hover_rect := chronicle_scene.get_global_rect()
		scene_hover_rect.size.x = maxf(scene_hover_rect.end.x, _chronicle_list_rect.position.x) - scene_hover_rect.position.x
		if not _chronicle_list_rect.has_point(pointer) and not scene_hover_rect.has_point(pointer):
			_hide_chronicle_scene()
	if grave_view and table_overlays.grave_scroll_input(e):
		get_viewport().set_input_as_handled()
	elif table_overlays.search_scroll_input(e):
		get_viewport().set_input_as_handled()
	elif decklist_view == null and is_instance_valid(hub_scroll) and menu_screens.hub_scroll_input(e): # the deck list scrolls itself
		get_viewport().set_input_as_handled()


## Drag-aim released: on a target fires; barely moved (a plain click on the source) keeps
## click-targeting; anywhere else cancels, like dropping the card back.
func _aim_release(gp := Vector2.INF, from_touch := false) -> void:
	aim_drag = false
	var drag_view := _aim_drag_view
	_aim_drag_view = null
	if is_instance_valid(drag_view):
		drag_view.finish_pointer_interaction()
	if targeting.is_empty() or not viewer_can_act():
		return
	if gp == Vector2.INF:
		gp = get_global_mouse_position()
	if not from_touch:
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
	if (
		gp.distance_to(aim_start) < CardView.DRAG_PX * 2.0 or targeting.has("first")
		or targeting["spec"] == "enemy_stack" or targeting["kind"] == "enter"
	):
		return
	targeting = { }
	render_table()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and g and not overlay:
		_hint_nudge() # a click that hit nothing: the player may be lost
	if overlay and e is InputEventMouseButton and e.pressed:
		table_overlays.close_overlay()
		return
	if decklist_view and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if overlay:
			table_overlays.close_overlay() # Esc peels off the topmost window first: the card, then the list
		else:
			menu_screens.close_decklist()
		return
	if grave_view and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		table_overlays.close_graveyard()
		return
	if concede_view and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		table_overlays.close_concede() # Esc backs out of the pause menu and of the confirmations
		return
	if not option_prompt.is_empty() and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_close_option_prompt() # Esc backs out of the "choose one" window
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
		targeting = { }
		render_table()


func viewer_can_act() -> bool:
	return g.decider() == viewer and not is_ai(viewer) and not pending_pass


func _on_hand_click(v: CardView) -> void:
	if not viewer_can_act():
		return
	if targeting.get("kind") in ["hand", "room_banish"] and targeting["uid"] == v.uid:
		targeting = { }
		render_table()
		return
	match g.phase:
		"mulligan":
			_toggle_pick(v.uid, GameState.MULLIGAN_MAX)
		"discard":
			_toggle_pick(v.uid, g.players[viewer]["hand"].size() - GameState.HAND_LIMIT)
		"main", "combat":
			table_overlays.show_overlay(v) # a click/tap only inspects; playing is drag & drop (no misclicks)


## slot: where a unit enters our board (-1 = rightmost); only drag & drop picks one.
func _play_from_hand(v: CardView, slot := -1) -> void:
	if not g.can_play(viewer, v.uid, true):
		show_toast("Não dá para jogar essa carta agora.")
		render_table()
		return
	var spec := _hand_spec(v)
	if spec != "":
		targeting = { "kind": "hand", "uid": v.uid, "card_id": v.card_id, "spec": spec, "slot": slot }
		begin_aim(Vector2.ZERO)
		render_table()
	elif CardDB.card(v.card_id)["type"] != "unit" and g.is_dud(viewer, CardDB.card(v.card_id)):
		# allowed (it can bait a counter), but never by accident
		render_table()
		table_overlays.ask_confirm(
			"SEM EFEITO AGORA",
			"Não há nada para reviver no seu cemitério. Jogar mesmo assim?",
			"JOGAR MESMO ASSIM",
			"CANCELAR",
			_play_dud.bind(v.uid),
		)
	elif _needs_room_banish(v.card_id):
		_begin_room_banish(v.uid, v.card_id, slot)
	else:
		handle_action_result(g.play_card(viewer, v.uid, 0, 0, slot))


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
	targeting = {
		"kind": "room_banish",
		"uid": hand_uid,
		"card_id": card_id,
		"spec": "room_banish",
		"slot": slot,
		"target": target,
		"target2": target2,
	}
	var source_view = views.get(hand_uid) if hand_uid != 0 else views.get("cmd%d" % viewer)
	begin_aim(visual_rect_of(source_view).get_center() if is_instance_valid(source_view) else Vector2.ZERO)
	render_table()


## Casts a Réquiem spell from the graveyard through the same flow as a hand card (target aiming, dud confirm).
func cast_requiem(uid: int, card_id: String) -> void:
	var stand_in := CardView.new().setup(card_id, { "uid": uid }, 1.0) # only its uid/card_id are read
	_play_from_hand(stand_in)
	stand_in.free()


func _play_dud(uid: int) -> void:
	table_overlays.close_concede()
	if g != null and g.can_play(viewer, uid):
		handle_action_result(g.play_card(viewer, uid, 0))


## Target spec of a playable hand card that needs a target now ("" if it plays straight away).
func _hand_spec(v: CardView) -> String:
	var cd := CardDB.card(v.card_id)
	var spec := g.card_spec(cd)
	if spec != "" and (not g.card_targets(viewer, cd).is_empty() or g.targets_blocked_by_reach(viewer, spec)):
		return spec # blocked only by Inalcançável: aim anyway, aiming at that unit explains the refusal
	return ""


## Starts click-targeting from `src` (global; ZERO = the pointer). Card drags start their aim
## explicitly, so a touch that opened an action cannot be mistaken for a held mouse press.
func begin_aim(src: Vector2) -> void:
	aim_src = src if src != Vector2.ZERO else get_global_mouse_position()
	aim_start = get_global_mouse_position()
	aim_drag = false


## On-screen rectangle a card really covers. get_global_rect() ignores rotation, so for a tapped
## (sideways) card it points at the wrong area; this one turns the card's corners with it.
func visual_rect_of(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)


## Valid target (unit or leader) under a global point; 0 if none. Tapped cards may overlap their
## neighbours, so when two are under the point the one drawn on top wins.
func _target_at(gp: Vector2) -> int:
	var found_uid := 0
	var found_draw_order := -1
	for k in views:
		if k is int and k != 0 and _is_target(k) and not hand_uids.has(k):
			var c: Control = views[k]
			if is_instance_valid(c) and visual_rect_of(c).has_point(gp) and c.get_index() > found_draw_order:
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
		var waiting_rect := visual_rect_of(waiting_attacker_view)
		var arrow_space := fx.get_global_transform().affine_inverse()
		aim_arrow.from = arrow_space * Vector2(waiting_rect.get_center().x, waiting_rect.position.y + waiting_rect.size.y * 0.3)
		aim_arrow.to = arrow_space * get_global_mouse_position()
		aim_arrow.locked = false
		return
	var on: bool = (
		g != null and not targeting.is_empty() and targeting.get("spec") != "enemy_stack"
		and viewer_can_act() and g.phase in ["main", "combat", "enter_target", "effect_choice"]
	)
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
	if (
		targeting["kind"] in ["hand", "enter", "attack", "room_banish", "effect_choice"]
		and views.has(targeting["uid"]) and is_instance_valid(views[targeting["uid"]])
	):
		var r: Rect2 = visual_rect_of(views[targeting["uid"]] as Control)
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
	var source_rect := visual_rect_of(source)
	var target_rect := visual_rect_of(target)
	var inv := fx.get_global_transform().affine_inverse()
	reaction_arrow.from = inv * Vector2(source_rect.get_center().x, source_rect.position.y + source_rect.size.y * 0.3)
	reaction_arrow.to = inv * target_rect.get_center()
	reaction_arrow.locked = true


func _toggle_pick(uid: int, cap: int) -> void:
	if picked.has(uid):
		picked.erase(uid)
	elif picked.size() < cap:
		picked.append(uid)
	render_table()


func _on_incarnation(p: int) -> void:
	if p != viewer or not viewer_can_act():
		return
	if _wait_for_table(_on_incarnation.bind(p)):
		return
	if not g.can_cast_incarnation(p):
		return
	if not g.has_free_slot(p):
		_begin_room_banish(0, g.players[p]["incarnation"]["card_id"])
		return
	handle_action_result(g.cast_incarnation(p)) # its Ao Entrar target (if any) is picked once it is on the board


## While our Ao Entrar waits for a target, aim from the unit on the board; the choice is
## optional (the side button skips it), so it cannot be cancelled away.
func _sync_enter_aim() -> void:
	if g.phase != "enter_target" or not viewer_can_act():
		if targeting.get("kind") == "enter":
			targeting = { }
		return
	var uid := int(g.pending_enter["uid"])
	var first_pick := int(g.pending_enter.get("first", 0)) # set once the first of two picks is made
	if targeting.get("kind") != "enter" or targeting["uid"] != uid or int(targeting.get("first", 0)) != first_pick:
		var asked_spec: String = g.pending_enter["spec2"] if first_pick != 0 else g.pending_enter["spec"]
		targeting = { "kind": "enter", "uid": uid, "spec": asked_spec, "card_id": g.pending_enter["card_id"] }
		if first_pick != 0:
			targeting["first"] = first_pick
		aim_drag = false
		aim_start = Vector2.INF
	if views.has(uid) and is_instance_valid(views[uid]):
		(views[uid] as CardView).highlight = SEL


func _on_ability(p: int) -> void:
	if not viewer_can_act():
		return
	if _wait_for_table(_on_ability.bind(p)):
		return
	if not g.can_use_ability(p, true):
		return
	var spec := g.target_spec(CardDB.leader(g.players[p]["leader_id"])["ability"]["effects"])
	if spec != "":
		targeting = { "kind": "ability", "uid": 0, "spec": spec }
		var lv: Control = views.get(GameState.LEADER_UID[p])
		begin_aim(lv.get_global_transform() * LeaderView.AC if is_instance_valid(lv) else Vector2.ZERO)
		render_table()
	else:
		handle_action_result(g.use_ability(p, 0))


func on_search_choice(card_uid: int) -> void:
	if not viewer_can_act() or _wait_for_table(on_search_choice.bind(card_uid)):
		return
	if g.phase != "search":
		return
	handle_action_result(g.choose_search(viewer, card_uid))


func _is_target(uid: int) -> bool:
	if targeting.is_empty():
		return false
	if targeting["kind"] == "effect_choice":
		return g.effect_choice_targets(int(targeting["mode"])).has(uid)
	if targeting["spec"] == "enemy_stack":
		for hand_card: Card in g.players[viewer]["hand"]:
			if hand_card.uid == targeting["uid"]:
				return g.card_targets(viewer, CardDB.card(hand_card.card_id)).has(uid)
		if targeting["kind"] == "unit_ability": # an Ao Ativar that counters: same filters as the spell
			return g.valid_targets(viewer, "enemy_stack", int(targeting["uid"]), false, _aimed_effects()).has(uid)
		return false
	if targeting["kind"] == "unit_cost":
		return g.activation_cost_option_targets(viewer, int(targeting["uid"]), int(targeting["mode"])).has(uid)
	if targeting["kind"] == "room_banish":
		return g.room_banish_options(viewer).has(uid)
	if targeting["kind"] == "attack":
		var attacker := g.find_unit(targeting["uid"])
		return attacker != null and g.attack_targets(attacker).has(uid)
	if (
		targeting.has("first") and not targeting.get("first_is_stack", false)
		and uid == targeting["first"] and not CardDB.card(targeting["card_id"]).get("same_target_ok", false)
	):
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
				return g.card_of(activator).get("activated", { }).get("effects", [])
		"field_equip":
			var artifact := g.find_relic(targeting["uid"])
			if artifact != null:
				return g.card_of(artifact).get("equip_from_field", { }).get("effects", [])
	return []


## True when a multi-target effect has already committed this uid as its first pick.
## It stays separate from `_is_target`: Relâmpagos Gêmeos may legally pick it again,
## but it must remain visibly distinct from the still-available second targets.
func _is_first_target(uid: int) -> bool:
	return (
		not targeting.is_empty() and targeting.has("first")
		and not targeting.get("first_is_stack", false) and int(targeting["first"]) == uid
	)


func _fire_target(uid: int, confirmed := false) -> void:
	if targeting["kind"] == "room_banish" and not confirmed:
		# banishing is permanent and the click is easy to mis-aim (beginners, distracted players): always ask first
		var banished_name := _permanent_name(uid)
		table_overlays.ask_confirm(
			"BANIR %s?" % banished_name.to_upper(),
			"Para abrir espaço no campo, %s será banido(a) do jogo e não volta." % banished_name,
			"BANIR E JOGAR",
			"CANCELAR",
			_confirm_room_banish_target.bind(int(targeting["uid"]), uid),
		)
		return
	if targeting["kind"] in ["hand", "field_equip"] and not confirmed \
			and (targeting["kind"] == "field_equip" or CardDB.is_equipment(CardDB.card(targeting["card_id"]))):
		var unit := g.find_unit(uid)
		if unit != null and not unit.has_equipment_room():
			table_overlays.ask_confirm(
				"SUBSTITUIR EQUIPAMENTO?",
				"Esta unidade já tem um Equipamento. Se continuar, o mais antigo volta para a mão do dono.",
				"EQUIPAR ASSIM MESMO",
				"CANCELAR",
				_confirm_equipment_target.bind(int(targeting["uid"]), uid),
			)
			return
	match targeting["kind"]:
		"hand":
			var spec2 := g.second_spec(CardDB.card(targeting["card_id"]))
			if spec2 != "" and not targeting.has("first"):
				# second step: pick the damage target after the sacrifice
				targeting = {
					"kind": "hand",
					"uid": targeting["uid"],
					"card_id": targeting["card_id"],
					"spec": spec2,
					"first": uid,
					"first_is_stack": targeting["spec"] == "enemy_stack",
				}
				if targeting["first_is_stack"]:
					targeting["picks"] = [] # the first pick was a stack item, not a unit to number
				else:
					targeting["picks"] = [uid]
				render_table()
			elif _needs_room_banish(targeting["card_id"]):
				# the card's own target is chosen; the permanent to banish is the last pick
				var first_pick: int = targeting["first"] if targeting.has("first") else uid
				var second_pick: int = uid if targeting.has("first") else 0
				_begin_room_banish(targeting["uid"], targeting["card_id"], targeting.get("slot", -1), first_pick, second_pick)
			elif targeting.has("first"):
				handle_action_result(g.play_card(viewer, targeting["uid"], targeting["first"], uid))
			else:
				handle_action_result(g.play_card(viewer, targeting["uid"], uid, 0, targeting.get("slot", -1)))
		"room_banish":
			var hand_uid: int = targeting["uid"]
			var slot: int = targeting.get("slot", -1)
			if hand_uid == 0:
				handle_action_result(g.cast_incarnation(viewer, 0, slot, uid))
			else:
				handle_action_result(g.play_card(viewer, hand_uid, targeting["target"], targeting["target2"], slot, uid))
		"incarnation":
			handle_action_result(g.cast_incarnation(viewer, uid))
		"ability":
			handle_action_result(g.use_ability(viewer, uid))
		"unit_ability":
			handle_action_result(g.activate(viewer, targeting["uid"], uid, int(targeting.get("payer", 0))))
		"unit_cost":
			var paying_unit := g.find_unit(int(targeting["uid"]))
			var ability_spec := g.target_spec(paying_unit.data()["activated"]["effects"]) if paying_unit != null else ""
			if ability_spec == "":
				handle_action_result(g.activate(viewer, targeting["uid"], uid))
			else:
				# the sacrifice is chosen; the ability's own target comes next (Cornélia Aldrovane)
				targeting = { "kind": "unit_ability", "uid": paying_unit.uid, "spec": ability_spec, "payer": uid }
				if views.has(paying_unit.uid) and is_instance_valid(views[paying_unit.uid]):
					begin_aim(visual_rect_of(views[paying_unit.uid] as Control).get_center())
				render_table()
		"field_equip":
			handle_action_result(g.equip_from_field(viewer, targeting["uid"], uid))
		"enter":
			handle_action_result(g.choose_enter_target(viewer, uid))
		"attack":
			handle_action_result(g.attack_unit(viewer, targeting["uid"], uid))
		"effect_choice":
			handle_action_result(g.choose_effect_option(viewer, int(targeting["mode"]), uid))


## Name of the unit or artifact the player picked to banish.
func _permanent_name(uid: int) -> String:
	var permanent := g.find_unit(uid)
	if permanent == null:
		permanent = g.find_relic(uid)
	return String(CardDB.card(permanent.card_id)["name"]) if permanent != null else "a carta escolhida"


func _confirm_room_banish_target(hand_uid: int, target_uid: int) -> void:
	table_overlays.close_concede()
	if (
		g == null or not viewer_can_act() or targeting.get("kind") != "room_banish" \
				or int(targeting.get("uid", 0)) != hand_uid
		or not _is_target(target_uid)
	):
		targeting = { }
		render_table()
		return
	_fire_target(target_uid, true)


func _confirm_equipment_target(hand_uid: int, target_uid: int) -> void:
	table_overlays.close_concede()
	if (
		g == null or not viewer_can_act() or targeting.get("kind") not in ["hand", "field_equip"] \
				or int(targeting.get("uid", 0)) != hand_uid
		or not _is_target(target_uid)
	):
		targeting = { }
		render_table()
		return
	_fire_target(target_uid, true)


func _on_leader_click(p: int) -> void:
	if viewer_can_act() and _input_must_wait() and _aiming_or_waiting():
		_queue_card_click(GameState.LEADER_UID[p])
		return
	if viewer_can_act() and _is_target(GameState.LEADER_UID[p]):
		_fire_target(GameState.LEADER_UID[p])


## A click on a unit on the field does its job (fire a target, pick an attacker/blocker...);
## when it has nothing to do there it opens the card overlay instead, like a click in the hand.
## During an animation the click waits and runs when it ends (see _queued_inputs).
func _on_unit_click(v: CardView) -> void:
	if _input_must_wait() and _click_should_wait(v.uid):
		_queue_card_click(v.uid)
		return
	if not _unit_click_acted(v):
		table_overlays.show_overlay(v)


## Touch: a finger pressed on one of our units and moved past the drag threshold. That is the same
## as picking it as an attacker, except the finger is still down: the arrow follows it and lifting
## it over a target fires the attack (see _aim_release).
func _unit_drag_start(v: CardView) -> void:
	if _input_must_wait() and _click_should_wait(v.uid):
		_queue_card_click(v.uid) # picked during an animation: the release is handled by _input
		return
	if not viewer_can_act() or not targeting.is_empty():
		return
	if _unit_click_acted(v):
		aim_drag = true # the press is still held, so the release decides
		_aim_drag_view = v


## True while an aim is open or clicks are already waiting: the next click on a card is a target pick.
func _aiming_or_waiting() -> bool:
	return not targeting.is_empty() or _queued_attacker_uid != 0 or not _queued_inputs.is_empty()


## Should a click on this unit, given during an animation, wait for it to end? Yes when it is meant to
## act (pick a target, pick one of our attackers); a plain look at a card opens its overlay right away.
func _click_should_wait(uid: int) -> bool:
	if not viewer_can_act():
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
func _release_queued_attacker_drag(gp := Vector2.INF) -> void:
	_queued_attacker_dragging = false
	if gp == Vector2.INF:
		gp = get_global_mouse_position()
	var card_uid := _card_uid_at(gp)
	if card_uid != 0 and card_uid != _queued_attacker_uid:
		_queue_card_click(card_uid)


## Runs a click stored during an animation, now that the screen shows the real table. The card may be
## gone or no longer a legal target (a Provocação that died in the fight that was playing): then the
## aim is dropped and the attacker stays ready, instead of acting on something the player never saw.
func _click_card_when_settled(uid: int) -> void:
	if not viewer_can_act():
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
		show_toast("Esse alvo não está mais disponível.")
		_cancel_targeting()


## uid of the unit or Leader drawn under a global point, legal target or not (0 if none).
func _card_uid_at(gp: Vector2) -> int:
	var found_uid := 0
	var found_draw_order := -1
	for k in views:
		if k is int and k != 0 and not hand_uids.has(k):
			var c: Control = views[k]
			if is_instance_valid(c) and visual_rect_of(c).has_point(gp) and c.get_index() > found_draw_order:
				found_uid = k
				found_draw_order = c.get_index()
	return found_uid


## Runs the click's action and returns true, or returns false when the click had no action.
func _unit_click_acted(v: CardView) -> bool:
	if not viewer_can_act():
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
			show_toast("Essa unidade não pode atacar agora.")
			return true
		targeting = { "kind": "attack", "uid": unit.uid, "spec": "attack" }
		begin_aim(visual_rect_of(v).get_center())
		render_table()
		return true
	return false


## Aiming an effect at an enemy unit with Inalcançável: says why it is refused (true), the aim stays open.
func _warn_unreachable(uid: int) -> bool:
	if targeting.is_empty() or targeting["kind"] == "attack" or _is_target(uid):
		return false
	var unit := g.find_unit(uid)
	if unit == null or unit.owner == viewer or not g.has_kw(unit, "inalcancavel"):
		return false
	show_toast("Inalcançável: essa unidade não pode ser alvo.")
	return true


## card_id of the Provocação waiting for the "enter exhausted?" choice ("" if none).
func _pending_tap_card_id() -> String:
	if g.pending_tap.is_empty():
		return ""
	var unit := g.find_unit(int(g.pending_tap[0]))
	return unit.card_id if unit != null else ""

# ---------------------------------------------------------------- log

var _toast_node: Label
var _toast_tw: Tween


## Short transient message (refused actions) instead of log spam.
func show_toast(t: String) -> void:
	if _toast_node and is_instance_valid(_toast_node):
		_toast_node.queue_free()
	if _toast_tw:
		_toast_tw.kill()
	var l := make_label(t, 24, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "bold", 4)
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
	chronicle_log.add_line(t)


func player_name(p: int) -> String:
	if online:
		return "Você" if p == viewer else "Oponente"
	return "IA" if is_ai(p) else "J%d" % (p + 1)


func card_name(id: String) -> String:
	return CardDB.card(id)["name"]

# ---------------------------------------------------------------- widgets


func make_label(t: String, fs: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, kind := "", outline := 0) -> Label:
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


func make_button(t: String, cb: Callable, primary := false) -> Button:
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
		icon.draw_colored_polygon(
			PackedVector2Array([Vector2(-10, -4), Vector2(-5, -4), Vector2(1, -9), Vector2(1, 9), Vector2(-5, 4), Vector2(-10, 4)]),
			color,
		)
		if sound_on:
			icon.draw_arc(Vector2(1, 0), 6.0, -0.8, 0.8, 8, color, 2.0)
			icon.draw_arc(Vector2(1, 0), 11.0, -0.8, 0.8, 10, color, 2.0)
		else:
			icon.draw_line(Vector2(6, -5), Vector2(14, 5), UITheme.HP, 2.0)
			icon.draw_line(Vector2(6, 5), Vector2(14, -5), UITheme.HP, 2.0)
	icon.draw.connect(draw_speaker)
	button.add_child(icon)
	button.pressed.connect(
		func():
			Sfx.set_enabled(not Sfx.is_enabled())
			Sfx.play("ui_toggle") # heard only when it was just turned on
			icon.queue_redraw(),
	)
	return button


## A volume slider with a "VOLUME DOS EFEITOS 70%" title (menu): the sound effects, or the music when
## `for_music` is true (each has its own volume). Moving it changes the volume live and saves it;
## letting go plays a click so the new level can be heard right away.
func make_volume_slider(control_size: Vector2, for_music := false) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = control_size
	holder.size = control_size
	var title_label := make_label("", 15, UITheme.TEXT, HORIZONTAL_ALIGNMENT_LEFT, "bold")
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
	slider.value_changed.connect(
		func(percent: float):
			if for_music:
				Music.set_volume(percent / 100.0)
			else:
				Sfx.set_volume(percent / 100.0)
			refresh_title.call(percent),
	)
	slider.drag_ended.connect(
		func(_value_changed: bool):
			Sfx.play("ui_click"),
	)
	return holder


## An on/off button shown as a sliding switch instead of the words "LIGADO"/"desligado":
## gold track with the knob on the right when on, dark track with the knob on the left when off.
func make_toggle_button(title: String, is_on: bool, on_press: Callable) -> Button:
	var button := Button.new()
	button.pressed.connect(Sfx.play.bind("ui_toggle"))
	button.pressed.connect(on_press)
	var title_label := make_label(title, 17, UITheme.TEXT if is_on else UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, "bold")
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
	switch_area.draw.connect(
		func():
			var track := UITheme.box(
				Color(UITheme.GOLD, 0.95) if is_on else Color(0.1, 0.09, 0.14, 0.95),
				13,
				UITheme.GOLD_LIGHT if is_on else Color(UITheme.TEXT, 0.35),
				2,
			)
			switch_area.draw_style_box(track, Rect2(Vector2.ZERO, switch_size))
			var knob_radius := switch_size.y / 2.0 - 5.0
			var knob_x := switch_size.x - switch_size.y / 2.0 if is_on else switch_size.y / 2.0
			switch_area.draw_circle(
				Vector2(knob_x, switch_size.y / 2.0),
				knob_radius,
				UITheme.INK if is_on else Color(UITheme.TEXT, 0.55),
			),
	)
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
	button.pressed.connect(
		func():
			for action_button: Button in get_tree().get_nodes_in_group("action_buttons"):
				action_button.disabled = true
			run_or_queue_input(action),
	)
	return button


## Crops a tall portrait to a wide window, anchored near the top so the face stays in frame
## (a centered crop shows the torso instead).
func crop_portrait_to_top(tex: Texture2D, window: Vector2, focus := 0.06) -> Texture2D:
	if tex == null:
		return null
	var ts := tex.get_size()
	var ch := minf(ts.y, ts.x * window.y / window.x)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(0, (ts.y - ch) * focus, ts.x, ch)
	return at
