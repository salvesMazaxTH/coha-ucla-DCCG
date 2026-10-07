extends Control
## Table screen: menu, board rendering, input state machine, AI driver,
## hot-seat pass screen and the full-screen card summary overlay.

const SEL := Color("#ffd23f")
const TARGET := Color("#ff5050")
const OK := Color("#4dff88")
const COL_W := 232.0 ## right HUD column width
const STAGE_H := 900.0
const STAGE_MAX_W := 2100.0
var stage_w := 1600.0 ## logical width: 1600 or wider, follows the window aspect
var col_x := 1352.0
var lane_cx := 882.0
var motes: CPUParticles2D

var g: GameState
var vs_ai := true
var viewer := 0 ## whose perspective is drawn
var pending_pass := false

# input state
var picked: Array = [] ## mulligan/discard selection
var attack_sel: Dictionary = {} ## attacker uid -> provoked uid
var provoking := 0 ## attacker currently choosing a provoke target
var block_sel: Dictionary = {} ## attacker uid -> blocker uid
var blocker_pick := 0
var targeting := {} ## {"kind": hand|legendary|ability, "uid": int, "spec": String}

var log_lines: Array = []
var bg: ColorRect
var table: TableView
var layer: Control
var overlay: Control
var search_overlay: Control
var views := {} ## uid (or "cmd<p>") -> Control on screen, for animations
var hand_uids := {} ## viewer's hand cards in the current render
var fx: Control ## persistent layer above the table: ghosts, floats, embers
var ai_timer: Timer

var _hand_base := 0 ## child index of the first hand card in layer

const DECK_POSE := {"c": Vector2(186, 776), "rot": 0.0, "w": 24.0}

func _ready() -> void:
	theme = UITheme.make()
	bg = ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/ui/shaders/table.gdshader")
	m.set_shader_parameter("aspect", 1600.0 / 900.0)
	m.set_shader_parameter("divider_y", TableView.DIVIDER_Y / 900.0)
	bg.material = m
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
	ai_timer = Timer.new()
	ai_timer.one_shot = true
	ai_timer.wait_time = 0.55
	ai_timer.timeout.connect(_ai_step)
	add_child(ai_timer)
	_show_menu()

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
	(bg.material as ShaderMaterial).set_shader_parameter("aspect", vp.x / vp.y)
	if motes:
		motes.position = Vector2(w / 2.0, 470)
		motes.emission_rect_extents = Vector2(w / 2.0 + 20.0, 470)
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
	var m: ShaderMaterial = bg.material
	m.set_shader_parameter("top_tint", top)
	m.set_shader_parameter("bottom_tint", bottom)
	m.set_shader_parameter("intensity", intensity)

func _leader_color(p: int) -> Color:
	return Color(CardDB.essence(CardDB.leader(g.players[p]["leader_id"])["essences"][0])["color"])

# ---------------------------------------------------------------- menu

func _show_menu() -> void:
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
		tr.size = Vector2(640, 900)
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
	for opt in [["JOGAR COMO RONAN", "Fogo contra a IA de Naelthos (Água)", true, "fogo", "agua", true],
			["JOGAR COMO NAELTHOS", "Água contra a IA de Ronan (Fogo)", true, "agua", "fogo", false],
			["HOT-SEAT", "Dois jogadores no mesmo computador", false, "fogo", "agua", false]]:
		var b := _button(opt[0], func(): _start(opt[2], opt[3], opt[4]), opt[5])
		b.custom_minimum_size = Vector2(420, 58)
		b.tooltip_text = opt[1]
		box.add_child(b)
		var sub := _label(opt[1], 14, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body")
		box.add_child(sub)
	var ver := _label("alpha 0.1", 13, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, "body")
	ver.position = Vector2(stage_w - 300, 864)
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
	vs_ai = ai
	g = GameState.new(deck_a, deck_b)
	log_lines = ["Partida iniciada. Escolha até 3 cartas para trocar."]
	viewer = 0
	pending_pass = not vs_ai
	_reset_input()
	_clear_fx()
	_render()

func _reset_input() -> void:
	picked.clear()
	attack_sel.clear()
	block_sel.clear()
	provoking = 0
	blocker_pick = 0
	targeting = {}

# ---------------------------------------------------------------- actions

func _do(events: Array) -> void:
	if events.is_empty():
		_toast("Ação inválida.")
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
	var old := _snapshot()
	_render()
	var end := _animate(events, old)
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
	if fx:
		for c in fx.get_children():
			c.queue_free()

func _render() -> void:
	_clear()
	var me := viewer
	var op := g.opponent(me)
	_set_tints(_leader_color(op), _leader_color(me))
	table.enemy_color = _leader_color(op)
	table.my_color = _leader_color(me)
	table.sockets = [Rect2(268, 8, 150, 208), Rect2(268, 684, 150, 208)]
	table.visible = true
	table.queue_redraw()
	if pending_pass:
		_render_pass()
		return
	_render_leader(op, Vector2(16, 14), Vector2(20, 192))
	_render_leader(me, Vector2(16, 660), Vector2(20, 840))
	_render_command(op, Vector2(274, 14))
	_render_command(me, Vector2(274, 690))
	_render_enemy_hand(op)
	_render_board(op, 172)
	_render_board(me, 460)
	_render_hand(me)
	_render_side()
	_render_hint()
	if g.phase == "search":
		_render_search_reveal()
	if g.phase == "over":
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
	lv.grave = pl["graveyard"].size()
	lv.ability_ready = p == viewer and g.can_use_ability(p) and not _is_ai(p)
	lv.targetable = _is_target(uid)
	lv.active = g.active == p and g.phase != "mulligan"
	lv.ability_clicked.connect(func(): _on_ability(p))
	lv.portrait_clicked.connect(func(): _on_leader_click(p))
	layer.add_child(lv)
	views[uid] = lv
	var mb := MomentumBar.new()
	mb.position = mom_pos
	layer.add_child(mb)
	mb.setup(pl["momentum"], pl["max_momentum"])

func _render_command(p: int, pos: Vector2) -> void:
	var l: Dictionary = g.players[p]["legendary"]
	if p == viewer:
		var cap := _label("COMANDO", 11, Color(UITheme.GOLD, 0.7), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
		cap.position = pos + Vector2(-6, -20)
		cap.size = Vector2(150, 16)
		layer.add_child(cap)
	if not l["in_zone"]:
		var empty := _label("EM CAMPO", 12, Color(UITheme.TEXT, 0.35), HORIZONTAL_ALIGNMENT_CENTER, "title", 2)
		empty.position = pos + Vector2(-6, 88)
		empty.size = Vector2(150, 20)
		layer.add_child(empty)
		return
	var v := CardView.new().setup(l["card_id"], {}, 1.15)
	v.pivot_offset = v.size / 2.0
	v.position = pos
	v.cost_override = g.legendary_cost(p)
	if p == viewer and g.can_cast_legendary(p) and not _is_ai(p):
		v.highlight = OK
	if targeting.get("kind") == "legendary" and p == viewer:
		v.highlight = SEL
	v.left_clicked.connect(func(_v): _on_legendary(p))
	v.right_clicked.connect(_show_overlay)
	layer.add_child(v)
	views["cmd%d" % p] = v

## Opponent's hand: face-down cards fanned along the top edge.
func _render_enemy_hand(p: int) -> void:
	var n: int = g.players[p]["hand"].size()
	for i in n:
		var k := float(i) - (n - 1) / 2.0
		var v := CardView.new().setup("", {}, 0.5)
		v.face_down = true
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.pivot_offset = v.size / 2.0
		v.rotation = deg_to_rad(-k * 4.0)
		v.position = Vector2(lane_cx - 68 + k * 30 - v.size.x / 2.0, -38 + k * k * 1.2)
		layer.add_child(v)
	if n > 0:
		var cnt := _label("%d" % n, 15, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "heavy", 5)
		cnt.position = Vector2(lane_cx - 68 + (n - 1) / 2.0 * 30 + 30, 18)
		cnt.size = Vector2(30, 20)
		layer.add_child(cnt)

func _render_board(p: int, y: float) -> void:
	var board: Array = g.players[p]["board"]
	var w: float = min(146.0, (TableView.ENEMY_LANE.size.x - 20.0) / max(1, board.size()))
	var x0 := TableView.ENEMY_LANE.get_center().x - board.size() * w / 2.0
	for i in board.size():
		var c: Dictionary = board[i]
		var v := CardView.new().setup(c["card_id"], c, 1.15)
		v.pivot_offset = v.size / 2.0
		v.position = Vector2(x0 + i * w + (w - v.size.x) / 2.0, y)
		if c["exhausted"] and g.phase != "blocks":
			v.dim = true
		_decorate_creature(v, c, p)
		v.left_clicked.connect(_on_creature_click)
		v.right_clicked.connect(_show_overlay)
		layer.add_child(v)
		views[c["uid"]] = v
		if attack_sel.has(c["uid"]) or g.attackers.has(c["uid"]):
			v.position.y += -24 if p == viewer else 24
			var prov: int = attack_sel.get(c["uid"], g.attackers.get(c["uid"], 0))
			_tag(v, "PROVOCA" if prov != 0 else "ATACA", TARGET if prov != 0 else SEL)
		if block_sel.values().has(c["uid"]):
			_tag(v, "BLOQUEIA", OK)

func _decorate_creature(v: CardView, c: Dictionary, p: int) -> void:
	if _is_target(c["uid"]):
		v.highlight = TARGET
		return
	if g.phase == "main" and p == viewer and g.active == viewer:
		if attack_sel.has(c["uid"]):
			v.highlight = SEL if provoking != c["uid"] else TARGET
		elif not g.players[viewer]["attacked"] and g.can_attack(c) and targeting.is_empty():
			v.highlight = OK
	elif g.phase == "main" and provoking != 0 and p != viewer and not attack_sel.values().has(c["uid"]):
		v.highlight = TARGET
	if g.phase == "blocks" and viewer == g.decider():
		if p == viewer and (c["uid"] == blocker_pick):
			v.highlight = SEL
		elif p == viewer and not block_sel.values().has(c["uid"]) and not g.attackers.values().has(c["uid"]):
			v.highlight = OK
		elif p != viewer and g.attackers.has(c["uid"]):
			v.highlight = TARGET if blocker_pick != 0 and g.can_block(g.find_creature(blocker_pick), c) else SEL
	if provoking != 0 and p != viewer and g.phase == "main":
		v.highlight = TARGET

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
	v.add_child(pc)
	pc.reset_size()
	pc.position = Vector2((v.size.x - pc.size.x) / 2.0, -22)

func _render_hand(p: int) -> void:
	var hand: Array = g.players[p]["hand"]
	var n := hand.size()
	_hand_base = layer.get_child_count()
	var step: float = min(122.0, (TableView.ENEMY_LANE.size.x - 110.0) / max(1, n))
	var ang: float = min(5.0, 36.0 / max(1, n))
	for i in n:
		var c: Dictionary = hand[i]
		var v := CardView.new().setup(c["card_id"], c, 1.2)
		var k := i - (n - 1) / 2.0
		v.pivot_offset = Vector2(v.size.x / 2.0, v.size.y)
		var pos := Vector2(lane_cx + k * step - v.size.x / 2.0, 676 + k * k * 1.4)
		var rot := deg_to_rad(k * ang)
		if picked.has(c["uid"]):
			pos.y -= 34
			v.highlight = TARGET if g.phase == "discard" else SEL
		elif targeting.get("uid", 0) == c["uid"] and targeting.get("kind") == "hand":
			pos.y -= 34
			v.highlight = SEL
		elif g.phase == "main" and g.can_play(p, c["uid"]) and not _is_ai(p):
			v.highlight = OK
		v.position = pos
		v.rotation = rot
		v.left_clicked.connect(_on_hand_click)
		v.right_clicked.connect(_show_overlay)
		var rest := {"pos": pos, "rot": rot, "idx": i}
		v.mouse_entered.connect(_hand_hover.bind(v, true, rest))
		v.mouse_exited.connect(_hand_hover.bind(v, false, rest))
		layer.add_child(v)
		views[c["uid"]] = v
		hand_uids[c["uid"]] = true

## Fan card lifts, straightens and grows under the cursor, and sits above its
## neighbours (GUI picking follows tree order) until the cursor leaves.
func _hand_hover(v: CardView, on: bool, rest: Dictionary) -> void:
	if not is_instance_valid(v) or v.is_queued_for_deletion() or CardView.touch_ui():
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
		tw.tween_property(v, "position", rest["pos"] + Vector2(0, -38), 0.14)
		tw.tween_property(v, "rotation", 0.0, 0.14)
		tw.tween_property(v, "scale", Vector2.ONE * 1.28, 0.14)
	else:
		layer.move_child(v, min(layer.get_child_count() - 1, rest["idx"] + _hand_base))
		v.hit_pad = 0.0
		tw.tween_property(v, "position", rest["pos"], 0.14)
		tw.tween_property(v, "rotation", rest["rot"], 0.14)
		tw.tween_property(v, "scale", Vector2.ONE, 0.14)

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
	var phase_names := {"mulligan": "Mulligan", "main": "Fase Principal", "blocks": "Bloqueios", "discard": "Descarte", "over": "Fim de jogo"}
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
	var ph := _label(phase_names.get(g.phase, g.phase), 17, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	ph.position = Vector2(0, 33)
	ph.size = Vector2(COL_W, 22)
	tp.add_child(ph)
	var d := g.decider()
	var who := "SUA VEZ" if mine else ("VEZ DA IA" if _is_ai(d) else "VEZ DO JOGADOR %d" % (d + 1))
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
	var menu := _button("Menu", _show_menu)
	menu.position = Vector2(col_x + COL_W - 130, 832)
	menu.size = Vector2(130, 52)
	menu.add_theme_font_size_override("font_size", 20)
	layer.add_child(menu)

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
	var col := SEL if not targeting.is_empty() or provoking != 0 else UITheme.TEXT
	pc.add_child(_label(t, 26, col, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	layer.add_child(pc)
	pc.reset_size()
	pc.position = Vector2(TableView.ENEMY_LANE.get_center().x - pc.size.x / 2.0, TableView.DIVIDER_Y + 18) # below the divider emblem

func _hint() -> String:
	if g.phase == "search":
		return "Escolha uma das cartas reveladas."
	if not targeting.is_empty():
		return ("Escolha um alvo (toque fora cancela)." if CardView.touch_ui() else "Escolha um alvo (botão direito/Esc cancela).")
	if g.decider() != viewer or _is_ai(viewer):
		return ""
	match g.phase:
		"mulligan":
			return "Clique em até 3 cartas para trocar."
		"blocks":
			return "Clique numa criatura sua e depois no atacante que ela bloqueia."
		"discard":
			return "Mão acima de 10: escolha %d para descartar." % (g.players[viewer]["hand"].size() - GameState.HAND_LIMIT)
		"main":
			if provoking != 0:
				return "Provocação: escolha a criatura inimiga que será obrigada a bloquear."
			return "Jogue cartas e clique nas suas criaturas para atacar · " + ("segure: ver carta" if CardView.touch_ui() else "botão direito: ver carta")
	return ""

func _action_buttons() -> Array:
	var out: Array = []
	match g.phase:
		"mulligan":
			out.append(_button("CONFIRMAR (%d)" % picked.size(), func(): _do(g.mulligan(viewer, picked.duplicate())), true))
		"main":
			if not attack_sel.is_empty():
				out.append(_button("ATACAR (%d)" % attack_sel.size(), func(): _do(g.declare_attack(viewer, attack_sel.duplicate())), true))
				out.append(_button("Cancelar ataque", func():
					_reset_input()
					_render()))
				out.append(_button("Encerrar turno", func(): _do(g.end_turn(viewer))))
			else:
				out.append(_button("ENCERRAR TURNO", func(): _do(g.end_turn(viewer)), true))
		"blocks":
			out.append(_button("CONFIRMAR BLOQUEIOS", func(): _do(g.declare_blocks(viewer, block_sel.duplicate())), true))
		"discard":
			var need: int = g.players[viewer]["hand"].size() - GameState.HAND_LIMIT
			var b := _button("DESCARTAR (%d/%d)" % [picked.size(), need], func(): _do(g.discard(viewer, picked.duplicate())), true)
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
	if vs_ai and g.winner < 2:
		won = g.winner == 0
		txt = "VITÓRIA" if won else "DERROTA"
	var big := _label(txt, 64 if txt.length() < 10 else 44, UITheme.GOLD_LIGHT if won else Color("#e0a8a0"), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 10)
	big.add_theme_color_override("font_shadow_color", Color(UITheme.GOLD if won else UITheme.HP, 0.35))
	big.add_theme_constant_override("shadow_outline_size", 24)
	big.add_theme_constant_override("shadow_offset_x", 0)
	big.add_theme_constant_override("shadow_offset_y", 0)
	box.add_child(big)
	if g.winner < 2:
		box.add_child(_label("%s triunfa na arena" % CardDB.leader(g.players[g.winner]["leader_id"])["name"], 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	box.add_child(_label("Turno %d" % g.turn, 14, Color(UITheme.TEXT, 0.4), HORIZONTAL_ALIGNMENT_CENTER, "title"))
	var b := _button("VOLTAR AO MENU", _show_menu, true)
	b.custom_minimum_size = Vector2(520, 54)
	box.add_child(b)
	_center.call_deferred(pc)

# ---------------------------------------------------------------- input

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		CardView.touched = true

func _unhandled_input(e: InputEvent) -> void:
	if overlay and e is InputEventMouseButton and e.pressed:
		_close_overlay()
		return
	var cancel: bool = (e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE) \
		or (e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_RIGHT or CardView.touch_ui()))
	if cancel and g and (not targeting.is_empty() or provoking != 0 or blocker_pick != 0):
		targeting = {}
		provoking = 0
		blocker_pick = 0
		_render()

func _my_input() -> bool:
	return g.decider() == viewer and not _is_ai(viewer) and not pending_pass

func _on_hand_click(v: CardView) -> void:
	if not _my_input():
		return
	match g.phase:
		"mulligan":
			_toggle_pick(v.uid, GameState.MULLIGAN_MAX)
		"discard":
			_toggle_pick(v.uid, g.players[viewer]["hand"].size() - GameState.HAND_LIMIT)
		"main":
			if not g.can_play(viewer, v.uid):
				_toast("Não dá para jogar essa carta agora.")
				_render()
				return
			var cd := CardDB.card(v.card_id)
			var spec := g.target_spec(cd["effects"])
			if spec != "" and not g.valid_targets(viewer, spec).is_empty():
				targeting = {"kind": "hand", "uid": v.uid, "spec": spec}
				attack_sel.clear()
				_render()
			else:
				_do(g.play_card(viewer, v.uid, 0))

func _toggle_pick(uid: int, cap: int) -> void:
	if picked.has(uid):
		picked.erase(uid)
	elif picked.size() < cap:
		picked.append(uid)
	_render()

func _on_legendary(p: int) -> void:
	if p != viewer or not _my_input() or not g.can_cast_legendary(p):
		return
	var spec := g.target_spec(CardDB.card(g.players[p]["legendary"]["card_id"])["effects"])
	if spec != "" and not g.valid_targets(p, spec).is_empty():
		targeting = {"kind": "legendary", "uid": 0, "spec": spec}
		_render()
	else:
		_do(g.cast_legendary(p, 0))

func _on_ability(p: int) -> void:
	if not _my_input():
		return
	var spec := g.target_spec(CardDB.leader(g.players[p]["leader_id"])["ability"]["effects"])
	if spec != "":
		targeting = {"kind": "ability", "uid": 0, "spec": spec}
		_render()
	else:
		_do(g.use_ability(p, 0))

func _on_search_choice(card_uid: int) -> void:
	if g.phase != "search" or not _my_input():
		return
	_do(g.choose_search(viewer, card_uid))

func _is_target(uid: int) -> bool:
	return not targeting.is_empty() and g.valid_targets(viewer, targeting["spec"], targeting.get("uid", 0)).has(uid)

func _fire_target(uid: int) -> void:
	match targeting["kind"]:
		"hand":
			_do(g.play_card(viewer, targeting["uid"], uid))
		"legendary":
			_do(g.cast_legendary(viewer, uid))
		"ability":
			_do(g.use_ability(viewer, uid))

func _on_leader_click(p: int) -> void:
	if _my_input() and _is_target(GameState.LEADER_UID[p]):
		_fire_target(GameState.LEADER_UID[p])

func _on_creature_click(v: CardView) -> void:
	if not _my_input():
		return
	var c := g.find_creature(v.uid)
	if c.is_empty():
		return
	if not targeting.is_empty():
		if _is_target(v.uid):
			_fire_target(v.uid)
		return
	match g.phase:
		"main":
			if provoking != 0:
				if c["owner"] != viewer and not attack_sel.values().has(v.uid):
					attack_sel[provoking] = v.uid
					provoking = 0
				_render()
				return
			if c["owner"] != viewer or g.players[viewer]["attacked"] or not g.can_attack(c):
				return
			if attack_sel.has(v.uid):
				attack_sel.erase(v.uid)
			else:
				attack_sel[v.uid] = 0
				if g.has_kw(c, "provocacao") and not g.players[g.opponent(viewer)]["board"].is_empty():
					provoking = v.uid
			_render()
		"blocks":
			if c["owner"] == viewer:
				if g.attackers.values().has(v.uid):
					return # already forced to block a provoker
				for a in block_sel.keys():
					if block_sel[a] == v.uid:
						block_sel.erase(a)
				blocker_pick = v.uid if blocker_pick != v.uid else 0
				_render()
			elif blocker_pick != 0 and g.attackers.has(v.uid) and g.attackers[v.uid] == 0:
				if g.can_block(g.find_creature(blocker_pick), c):
					block_sel[v.uid] = blocker_pick
					blocker_pick = 0
				else:
					_toast("Essa criatura não pode bloquear esse atacante (Voo/Furtivo).")
				_render()

# ---------------------------------------------------------------- overlay

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
	var big := CardView.new().setup(v.card_id, v.inst, 3.0)
	big.cost_override = v.cost_override
	big.position = Vector2(stage_w / 2.0 - 620, 150)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(big)
	var txt := "[font_size=48][color=#e8c25a]%s[/color][/font_size]\n" % cd["name"]
	var rar := {"legendary": "Campeão Lendário", "champion": "Campeão", "epic": "Unidade Épica", "common": "Unidade"}
	var typ := {"creature": rar[cd["rarity"]], "spell": "Feitiço", "equipment": "Equipamento"}
	txt += "[color=#aaaaaa]%s · %s · custo %d[/color]\n\n" % [typ[cd["type"]], CardDB.essence(cd["essence"]).get("name", cd["essence"]), cd["cost"]]
	if cd.get("text", "") != "":
		txt += "[font_size=32]%s[/font_size]\n\n" % cd["text"]
	for kw in cd.get("keywords", []):
		var k := CardDB.keyword(kw)
		txt += "[color=#ffe9a8][b]%s[/b][/color] — %s\n" % [k["name"], k["text"]]
	if cd["rarity"] == "legendary":
		txt += "\n[color=#e8c25a]Lendário:[/color] fica na Zona de Comando. Cada nova conjuração custa +%d. Ao morrer, volta para a Zona de Comando.\n" % GameState.COMMANDER_TAX
	if cd.get("flavor", "") != "":
		txt += "\n[i][color=#888888]%s[/color][/i]" % cd["flavor"]
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.text = txt
	rt.position = Vector2(stage_w / 2.0 - 190, 160)
	rt.size = Vector2(830, 640)
	rt.add_theme_font_size_override("normal_font_size", 28)
	rt.add_theme_font_size_override("bold_font_size", 28)
	rt.add_theme_font_size_override("italics_font_size", 24)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(rt)

func _close_overlay() -> void:
	if overlay:
		overlay.queue_free()
		overlay = null

func _render_search_reveal() -> void:
	if g.pending_search.is_empty():
		return
	var owner: int = g.decider()
	search_overlay = _veil(0.84)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(1120, 0)
	box.add_theme_constant_override("separation", 12)
	search_overlay.add_child(box)
	box.add_child(_label("REVELAÇÃO DO DECK", 30, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6))
	box.add_child(_label("%s revelou opções de Água de custo 2 ou menos" % _pname(owner), 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var grid := GridContainer.new()
	grid.columns = min(7, g.pending_search["cards"].size())
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	for option in g.pending_search["cards"]:
		var card_uid: int = option["uid"]
		var cv := CardView.new().setup(option["card_id"], {"uid": card_uid}, 1.05)
		cv.mouse_filter = Control.MOUSE_FILTER_STOP if _my_input() else Control.MOUSE_FILTER_IGNORE
		if _my_input():
			cv.left_clicked.connect(func(_v): _on_search_choice(card_uid))
		grid.add_child(cv)
	var footer := _label("Clique em uma carta para adicioná-la à sua mão e embaralhar o deck." if _my_input() else "A escolha pertence ao oponente.", 16, SEL if _my_input() else UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body")
	box.add_child(footer)
	_center.call_deferred(search_overlay)


# ---------------------------------------------------------------- feedback

## Pose of a Control as its visual center, rotation and on-screen width.
func _pose(v: Control) -> Dictionary:
	var s := v.scale.x
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

func _ghost(card_id: String, inst: Dictionary, pose: Dictionary) -> CardView:
	var v := CardView.new().setup(card_id, inst, 1.15)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.pivot_offset = v.size / 2.0
	fx.add_child(v)
	_apply_pose(v, pose)
	return v

func _lunge(a: CardView, target: Control, t: float) -> void:
	var d: Vector2 = (_center_of(target) - _center_of(a)) * 0.72 / a.scale.x
	var tw := a.create_tween()
	tw.tween_interval(t)
	tw.tween_callback(func(): a.z_index = 20)
	tw.tween_property(a, "lunge", -d * 0.1, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(a, "lunge", d, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(a, "lunge", Vector2.ZERO, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): a.z_index = 0)

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

func _embers(c: Vector2, t: float, col: Color) -> void:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 36
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

func _elem_color(card_id: String) -> Color:
	return Color(CardDB.essence(CardDB.card(card_id)["essence"]).get("color", "#ffffff"))

## Plays the events out over the freshly rendered table: cards fly from where
## they were, attackers lunge, victims shake, numbers float, the dead dissolve.
## Returns the time (s) at which everything has settled.
func _animate(events: Array, old: Dictionary) -> float:
	if pending_pass or fx == null:
		return 0.0
	var actors := views.duplicate()
	var ghosts: Array = []
	for k in old:
		if k is int and k > 0 and not views.has(k) and not old[k]["hand"] and old[k]["inst"].has("damage"):
			var gh := _ghost(old[k]["card_id"], old[k]["inst"], old[k]["pose"])
			actors[k] = gh
			ghosts.append(gh)
	var cursor := 0.0
	var handled := {}
	var appear := {}
	var in_combat := false
	var last_src := 0
	var last_dst := 0
	var hit_t := 0.0
	for e in events:
		match e["type"]:
			"play":
				var uid: int = e["uid"]
				var cd := CardDB.card(e["card_id"])
				var origin: Dictionary = {"c": Vector2(lane_cx - 68, 30), "rot": 0.0, "w": 60.0}
				if e.get("legendary", false) and old.has("cmd%d" % e["player"]):
					origin = old["cmd%d" % e["player"]]["pose"]
				elif old.has(uid):
					origin = old[uid]["pose"]
				if cd["type"] == "creature" and views.has(uid):
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
					var gh := _ghost(e["card_id"], {}, origin)
					gh.z_index = 30
					var tw := _fly(gh, origin, {"c": Vector2(lane_cx, 420), "rot": 0.0, "w": 170.0}, cursor, 0.35, 40.0, true)
					tw.tween_callback(func(): gh.z_index = 0)
					gh.dissolve(cursor + 0.95, _elem_color(e["card_id"]).lightened(0.15), 0.6)
					cursor += 0.5
			"ability":
				cursor += 0.25
			"summon", "draw", "search_take":
				appear[e["uid"]] = cursor
				cursor += 0.1
			"search_reveal":
				cursor += 0.35
			"blocks":
				in_combat = true
			"start_turn", "end_turn":
				in_combat = false
			"damage", "shield_break", "heal":
				var dst: int = e["uid"]
				var t := cursor
				if e["type"] == "damage" and in_combat and e.get("src", 0) > 0 and actors.has(e["src"]) and actors.has(dst):
					var src: int = e["src"]
					if src == last_src or (src == last_dst and dst == last_src):
						t = hit_t
					else:
						_lunge(actors[src], actors[dst], cursor)
						hit_t = cursor + 0.2
						t = hit_t
						last_src = src
						last_dst = dst
						cursor += 0.42
				else:
					cursor += 0.12
				if actors.has(dst):
					match e["type"]:
						"damage":
							_impact(actors[dst], "-%d" % e["amount"], Color("#ff5050"), t, true)
						"heal":
							_impact(actors[dst], "+%d" % e["amount"], Color("#5dff8a"), t, false)
						"shield_break":
							_impact(actors[dst], "Escudo!", Color("#9fe3ff"), t, false)
	var settle := cursor + 0.1
	var board_t := settle + (0.4 if not ghosts.is_empty() else 0.0)
	for i in ghosts.size():
		var gh: CardView = ghosts[i]
		var col := _elem_color(gh.card_id)
		gh.dissolve(settle + i * 0.06, col.lightened(0.2), 0.75)
		_embers(_center_of(gh), settle + i * 0.06 + 0.1, col)
	var deck_n := 0
	for k in views:
		var v = views[k]
		if handled.has(k) or not (v is CardView):
			continue
		var to := _pose(v)
		if old.has(k):
			var from: Dictionary = old[k]["pose"]
			if from["c"].distance_to(to["c"]) > 1.0 or abs(from["w"] - to["w"]) > 1.0 or abs(from["rot"] - to["rot"]) > 0.01:
				_fly(v, from, to, 0.0 if hand_uids.has(k) else board_t, 0.28)
		elif hand_uids.has(k):
			_fly(v, DECK_POSE, to, appear.get(k, 0.0) + 0.12 * deck_n, 0.4, 30.0, true)
			deck_n += 1
		else:
			v.scale = Vector2.ZERO
			var tw: Tween = v.create_tween()
			tw.tween_interval(appear.get(k, settle))
			tw.tween_property(v, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return max(settle + 0.8, board_t + 0.3)

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
	return "IA" if _is_ai(p) else "J%d" % (p + 1)

func _cname(id: String) -> String:
	return CardDB.card(id)["name"]

func _log_event(e: Dictionary) -> void:
	match e["type"]:
		"play":
			_log("%s jogou %s" % [_pname(e["player"]), _cname(e["card_id"])])
		"ability":
			_log("%s usou %s" % [_pname(e["player"]), CardDB.leader(g.players[e["player"]]["leader_id"])["ability"]["name"]])
		"attack":
			_log("%s atacou com %d" % [_pname(e["player"]), e["attackers"].size()])
		"death":
			pass
		"fatigue":
			_log("%s: fadiga %d" % [_pname(e["player"]), e["amount"]])
		"start_turn":
			_log("— Turno %d: %s —" % [e["turn"], _pname(e["player"])])
		"discard":
			_log("%s descartou uma carta" % _pname(e["player"]))
		"search_reveal":
			var names: Array = []
			for c in e["cards"]:
				names.append(_cname(c["card_id"]))
			_log("%s revelou: %s" % [_pname(e["player"]), ", ".join(names)])
		"search_empty":
			_log("%s não encontrou uma carta que atendesse à busca" % _pname(e["player"]))
		"search_take":
			_log("%s escolheu %s na busca" % [_pname(e["player"]), _cname(e["card_id"])])


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
