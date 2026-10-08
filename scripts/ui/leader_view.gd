class_name LeaderView
extends Control
## Leader plate: round portrait in a gold + essence frame, HP gem, name
## ribbon, the ability gem (clickable) and deck/graveyard counters.

signal portrait_clicked
signal ability_clicked
signal grave_clicked

const SIZE := Vector2(240, 176)
const PC := Vector2(76, 70) ## portrait center
const PR := 58.0 ## portrait radius
const AC := Vector2(192, 52) ## ability gem center
const AR := 27.0
const READY_GLOW := Color("#4dff88") ## same as Main.OK, the playable-card glow
const GRAVE_RECT := Rect2(Vector2(183, 96), Vector2(62, 42)) ## graveyard counter + touch padding

static var _portrait_shader: Shader

var leader_id := ""
var hp := 0
var hp_max := 0
var deck := 0
var grave := 0
var ability_ready := false
var ability_cost := 0
var passive := false # passive ability: fires on its own trigger, no cost, not clickable
var targetable := false
var active := false ## whose turn it is
var elem_color := Color.WHITE
var _hover_ability := false
var _hover_grave := false
var _t := 0.0
var _holding := false
var _long := false
var _press_id := 0

func setup(id: String) -> LeaderView:
	leader_id = id
	var ld := CardDB.leader(id)
	elem_color = Color(CardDB.essence(ld["essences"][0])["color"])
	ability_cost = int(ld["ability"]["cost"])
	passive = bool(ld["ability"].get("passive", false))
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		if _hover_grave:
			_hover_grave = false
			queue_redraw())
	_build_portrait(ld)
	var gem := AbilityGem.new() # hover area so the tooltip only covers the ability gem
	gem.ability = ld["ability"]
	gem.elem_color = elem_color
	gem.position = AC - Vector2(AR, AR)
	gem.size = Vector2(AR, AR) * 2
	gem.mouse_filter = Control.MOUSE_FILTER_PASS
	gem.tooltip_text = ld["ability"]["name"] # non-empty so Godot asks for the custom tooltip
	gem.mouse_entered.connect(func():
		_hover_ability = true
		queue_redraw())
	gem.mouse_exited.connect(func():
		_hover_ability = false
		queue_redraw())
	add_child(gem)
	return self

func _build_portrait(ld: Dictionary) -> void:
	var tex := CardView.texture(ld["art"])
	if tex == null:
		return
	if _portrait_shader == null:
		_portrait_shader = load("res://scripts/ui/shaders/portrait.gdshader")
	# crop a square from the upper part of the (tall) portrait, where the face is
	var ts := tex.get_size()
	var side: float = min(ts.x, ts.y)
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2((ts.x - side) / 2, min(ts.y - side, ts.y * 0.04), side, side)
	var tr := TextureRect.new()
	tr.texture = at
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.position = PC - Vector2(PR, PR)
	tr.size = Vector2(PR, PR) * 2
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.show_behind_parent = true # frame and HP gem are drawn over it
	var m := ShaderMaterial.new()
	m.shader = _portrait_shader
	m.set_shader_parameter("size", tr.size)
	tr.material = m
	tr.name = "Portrait"
	add_child(tr)
	move_child(tr, 0)

func _process(delta: float) -> void:
	if targetable or ability_ready or active:
		_t += delta
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	# touch: dragging off the gem starts aiming right away (the finger stays down)
	if e is InputEventMouseMotion and _holding and not _long and not passive 			and e.position.distance_to(AC) > AR + 12:
		_long = true
		ability_clicked.emit()
		return
	if e is InputEventMouseMotion:
		var over := GRAVE_RECT.has_point(e.position)
		if over != _hover_grave:
			_hover_grave = over
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over else Control.CURSOR_ARROW
			queue_redraw()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and GRAVE_RECT.has_point(e.position):
		if e.pressed:
			grave_clicked.emit()
		accept_event()
		return
	# touch has no hover: long-press the gem (or tap a passive one) to read the ability
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and CardView.touch_ui() \
			and e.position.distance_to(AC) <= AR + 2:
		if e.pressed:
			_holding = true
			_long = false
			var id := Time.get_ticks_msec()
			_press_id = id
			get_tree().create_timer(0.4).timeout.connect(func():
				if _holding and _press_id == id and is_instance_valid(self):
					_long = true
					_show_ability_popup())
		else:
			_holding = false
			if not _long:
				if passive:
					_show_ability_popup()
				else:
					ability_clicked.emit()
		accept_event()
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if e.position.distance_to(AC) <= AR + 2:
			if not passive:
				ability_clicked.emit()
		elif e.position.distance_to(PC) <= PR + 8:
			portrait_clicked.emit()
		accept_event()

func _draw() -> void:
	var f_title := UITheme.font("title_bold")
	var f_num := UITheme.font("heavy")
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)

	# soft drop shadow + turn glow behind the portrait
	# (rings only: the portrait sits behind this drawing)
	draw_arc(PC + Vector2(0, 6), PR + 9, 0, TAU, 72, Color(0, 0, 0, 0.45), 12, true)
	if active:
		for i in 6:
			draw_arc(PC, PR + 13 + i * 3, 0, TAU, 72, Color(UITheme.GOLD, 0.12 * (1.0 - i / 6.0) * (0.6 + 0.4 * pulse)), 3.2, true)
	if targetable:
		for i in 7:
			draw_arc(PC, PR + 13 + i * 3, 0, TAU, 72, Color(1, 0.25, 0.2, 0.2 * (1.0 - i / 7.0) * (0.5 + 0.5 * pulse)), 3.2, true)
	# frame: dark bed, essence ring, gold bevel
	draw_arc(PC, PR + 5.5, 0, TAU, 72, Color("#120f16"), 11, true)
	draw_arc(PC, PR + 7, 0, TAU, 72, UITheme.GOLD_DARK, 7, true)
	draw_arc(PC, PR + 8.5, PI * 1.05, PI * 1.95, 40, UITheme.GOLD_LIGHT, 2, true) # top highlight
	draw_arc(PC, PR + 7, 0, TAU, 72, Color(UITheme.GOLD, 0.9), 2.5, true)
	draw_arc(PC, PR + 2, 0, TAU, 72, elem_color.darkened(0.1), 3, true)
	# four studs on the frame
	for k in 4:
		var a := k * PI / 2 + PI / 4
		_diamond(PC + Vector2(cos(a), sin(a)) * (PR + 7), 6, UITheme.GOLD, UITheme.GOLD_LIGHT)
	if targetable:
		draw_arc(PC, PR + 7, 0, TAU, 72, Color(1, 0.35, 0.3, 0.6 + 0.4 * pulse), 3, true)

	# name ribbon under the portrait
	var ld := CardDB.leader(leader_id)
	var ry := 142.0
	var rib := PackedVector2Array([Vector2(4, ry), Vector2(160, ry), Vector2(168, ry + 13), Vector2(160, ry + 26), Vector2(4, ry + 26), Vector2(12, ry + 13)])
	draw_colored_polygon(rib, Color("#16131c"))
	draw_polyline(rib + PackedVector2Array([rib[0]]), Color(UITheme.GOLD, 0.7), 1.5, true)
	_text(f_title, String(ld["name"]).to_upper(), Vector2(86, ry + 21), 19, UITheme.GOLD_LIGHT)

	# HP gem (shield shape) overlapping the portrait, bottom right
	var hc := PC + Vector2(PR * 0.78, PR * 0.62)
	var low := hp <= 8
	var sh := PackedVector2Array([hc + Vector2(-20, -20), hc + Vector2(20, -20), hc + Vector2(20, 2), hc + Vector2(0, 24), hc + Vector2(-20, 2)])
	draw_colored_polygon(_grow(sh, hc, 1.18), Color(0, 0, 0, 0.6))
	draw_colored_polygon(sh, UITheme.HP.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([sh[0], sh[1], hc + Vector2(16, -6), hc + Vector2(-16, -6)]), Color(1, 1, 1, 0.12))
	draw_polyline(sh + PackedVector2Array([sh[0]]), UITheme.GOLD if not low else Color(1, 0.5, 0.4, 0.6 + 0.4 * pulse), 2, true)
	_text(f_num, str(hp), hc + Vector2(0, 9), 26, Color.WHITE)

	# ability gem
	var usable := ability_ready or passive
	var ring := UITheme.GOLD if usable else Color(0.45, 0.42, 0.4)
	if usable:
		for i in 5:
			draw_circle(AC, AR + 4 + i * 2.5, Color(elem_color, 0.07 * (1.0 - i / 5.0) * (0.6 + 0.4 * pulse)))
	if ability_ready and not passive:
		# same "playable" green as the hand cards, ~8% hotter since the gem is small and easy to forget
		for i in 4:
			draw_arc(AC, AR + 2 + i * 2.4, 0, TAU, 48, Color(READY_GLOW, minf(1.0, (0.9 - i * 0.22) * 1.08) * (0.65 + 0.35 * pulse)), 2.4, true)
	draw_circle(AC + Vector2(0, 3), AR + 3, Color(0, 0, 0, 0.5))
	draw_circle(AC, AR, elem_color.darkened(0.55 if usable else 0.8))
	draw_circle(AC + Vector2(0, -AR * 0.3), AR * 0.62, Color(elem_color.lightened(0.3), 0.22 if usable else 0.06))
	draw_arc(AC, AR, 0, TAU, 48, ring.lightened(0.2) if _hover_ability and usable else ring, 2.5, true)
	_text(f_title, String(ld["ability"]["name"]).substr(0, 1), AC + Vector2(0, 8), 24, Color.WHITE if usable else Color(1, 1, 1, 0.35))
	# its cost, a small Momentum gem
	if not passive:
		var cc := AC + Vector2(AR * 0.75, -AR * 0.75)
		_diamond(cc, 11, UITheme.MOMENTUM.darkened(0.2) if usable else Color(0.3, 0.3, 0.35), Color(1, 1, 1, 0.8))
		_text(f_num, str(ability_cost), cc + Vector2(0, 5), 14, Color.WHITE)
	_text(UITheme.font("bold"), "PASSIVA" if passive else "HABILIDADE", AC + Vector2(0, AR + 17), 14, Color(UITheme.TEXT, 0.55))

	# deck / graveyard counters
	_counter(Vector2(160, 102), false, deck)
	_counter(Vector2(214, 102), true, grave, true)

## Small plate with a drawn icon (card stack or tombstone) and a count.
func _counter(pos: Vector2, tomb: bool, n: int, clickable := false) -> void:
	var r := Rect2(pos - Vector2(25, 0), Vector2(50, 30))
	var hot := clickable and _hover_grave
	var rim := Color(UITheme.GOLD, 0.9 if hot else (0.5 if clickable else 0.25))
	draw_style_box(UITheme.box(Color(UITheme.GOLD_DARK, 0.35) if hot else Color(0, 0, 0, 0.45), 5, rim, 2 if clickable else 1), r)
	var ic := r.position + Vector2(10, 15)
	var ink := Color(UITheme.GOLD_LIGHT, 0.95) if hot else Color(UITheme.TEXT, 0.75)
	if tomb:
		var pts := PackedVector2Array()
		for i in 9:
			var a := PI + PI * i / 8.0
			pts.append(ic + Vector2(cos(a) * 4.5, -1.5 + sin(a) * 4.5))
		pts.append(ic + Vector2(4.5, 6))
		pts.append(ic + Vector2(-4.5, 6))
		draw_colored_polygon(pts, ink)
	else:
		draw_rect(Rect2(ic + Vector2(-2.5, -6.5), Vector2(8, 11)), Color(ink, 0.45))
		draw_rect(Rect2(ic + Vector2(-5, -5), Vector2(8, 11)), ink)
	var f := UITheme.font("heavy")
	var t := str(n)
	draw_string_outline(f, r.position + Vector2(20, 22), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.8))
	draw_string(f, r.position + Vector2(20, 22), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.TEXT)

func _diamond(c: Vector2, r: float, col: Color, rim: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
	draw_colored_polygon(pts, col)
	draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c, pts[3]]), Color(1, 1, 1, 0.18))
	draw_polyline(pts + PackedVector2Array([pts[0]]), rim, 1.2, true)

func _grow(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k)
	return out

func _text(font: Font, t: String, center: Vector2, fs: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(center.x - w / 2, center.y)
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

## Touch: the ability panel on a dimmed layer; any tap closes it.
func _show_ability_popup() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			layer.queue_free())
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.tooltip_box())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(ability_panel(CardDB.leader(leader_id)["ability"], elem_color))
	layer.add_child(p)
	get_tree().root.add_child(layer)
	await get_tree().process_frame # let the wrapped text settle its height
	if not is_instance_valid(p):
		return
	var vp := layer.size
	var want := global_position + AC + Vector2(AR + 12, -AR)
	p.position = Vector2(clamp(want.x, 8, vp.x - p.size.x - 8), clamp(want.y, 8, vp.y - p.size.y - 8))

const SPEED_NAMES := {"rapido": "Rápida", "instantaneo": "Instantânea"}

## Ability card body: gold title, cost/speed chips, rules text that wraps.
## The chips already say speed, cost and "1× por turno", so the matching
## lead-in of the text is dropped.
static func ability_panel(ab: Dictionary, col: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := Label.new()
	title.text = ab["name"]
	title.add_theme_font_override("font", UITheme.font("title_bold"))
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UITheme.GOLD_LIGHT)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	box.add_child(title)

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	var passive := bool(ab.get("passive", false))
	if passive:
		chips.add_child(_chip("PASSIVA", col.lightened(0.25)))
	else:
		chips.add_child(_chip("◆ %d MOMENTUM" % int(ab["cost"]), UITheme.MOMENTUM))
	if SPEED_NAMES.has(ab.get("speed", "")):
		chips.add_child(_chip(SPEED_NAMES[ab["speed"]].to_upper(), Color("#9fd8ff")))
	if ab.get("once_per_turn", false):
		chips.add_child(_chip("1× POR TURNO", UITheme.TEXT))
	box.add_child(chips)

	var rule := ColorRect.new()
	rule.color = Color(UITheme.GOLD, 0.3)
	rule.custom_minimum_size = Vector2(0, 1)
	box.add_child(rule)

	var body: String = ab["text"]
	for lead in [r"^(Rápida|Instantânea|Passiva)\.\s*", r"^\d+ Momentum, uma vez por turno:\s*", r"^\d+ Momentum:\s*"]:
		body = RegEx.create_from_string(lead).sub(body, "")
	if body != "":
		body = body.substr(0, 1).to_upper() + body.substr(1)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(420, 0)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_size_override("normal_font_size", 21)
	rt.add_theme_font_size_override("bold_font_size", 21)
	rt.add_theme_constant_override("line_separation", 3)
	rt.text = CardView.colorize_triggers(body)
	box.add_child(rt)
	return box

static func _chip(t: String, col: Color) -> Control:
	var c := PanelContainer.new()
	var sb := UITheme.box(Color(col.darkened(0.75), 0.9), 5, Color(col, 0.55), 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	c.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", UITheme.font("heavy"))
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	c.add_child(l)
	return c

## Hover target over the ability gem; desktop hover shows the ability panel.
class AbilityGem extends Control:
	var ability: Dictionary
	var elem_color := Color.WHITE

	func _make_custom_tooltip(_for_text: String) -> Object:
		return LeaderView.ability_panel(ability, elem_color)
