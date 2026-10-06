class_name LeaderView
extends Control
## Leader plate: round portrait in a gold + element frame, HP gem, name
## ribbon, the ability gem (clickable) and deck/graveyard counters.

signal portrait_clicked
signal ability_clicked

const SIZE := Vector2(240, 176)
const PC := Vector2(76, 70) ## portrait center
const PR := 58.0 ## portrait radius
const AC := Vector2(192, 52) ## ability gem center
const AR := 27.0

static var _portrait_shader: Shader

var leader_id := ""
var hp := 0
var hp_max := 0
var deck := 0
var grave := 0
var ability_ready := false
var ability_cost := 0
var targetable := false
var active := false ## whose turn it is
var elem_color := Color.WHITE
var _hover_ability := false
var _t := 0.0

func setup(id: String) -> LeaderView:
	leader_id = id
	var ld := CardDB.leader(id)
	elem_color = Color(CardDB.element(ld["elements"][0])["color"])
	ability_cost = int(ld["ability"]["cost"])
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_portrait(ld)
	var gem := Control.new() # hover area so the tooltip only covers the ability gem
	gem.position = AC - Vector2(AR, AR)
	gem.size = Vector2(AR, AR) * 2
	gem.mouse_filter = Control.MOUSE_FILTER_PASS
	gem.tooltip_text = "%s (%d Momentum)\n%s" % [ld["ability"]["name"], ability_cost, ld["ability"]["text"]]
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
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if e.position.distance_to(AC) <= AR + 2:
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
	# frame: dark bed, element ring, gold bevel
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
	_text(f_title, String(ld["name"]).to_upper(), Vector2(86, ry + 19), 15, UITheme.GOLD_LIGHT)

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
	var usable := ability_ready
	var ring := UITheme.GOLD if usable else Color(0.45, 0.42, 0.4)
	if usable:
		for i in 5:
			draw_circle(AC, AR + 4 + i * 2.5, Color(elem_color, 0.07 * (1.0 - i / 5.0) * (0.6 + 0.4 * pulse)))
	draw_circle(AC + Vector2(0, 3), AR + 3, Color(0, 0, 0, 0.5))
	draw_circle(AC, AR, elem_color.darkened(0.55 if usable else 0.8))
	draw_circle(AC + Vector2(0, -AR * 0.3), AR * 0.62, Color(elem_color.lightened(0.3), 0.22 if usable else 0.06))
	draw_arc(AC, AR, 0, TAU, 48, ring.lightened(0.2) if _hover_ability and usable else ring, 2.5, true)
	_text(f_title, String(ld["ability"]["name"]).substr(0, 1), AC + Vector2(0, 8), 24, Color.WHITE if usable else Color(1, 1, 1, 0.35))
	# its cost, a small Momentum gem
	var cc := AC + Vector2(AR * 0.75, -AR * 0.75)
	_diamond(cc, 11, UITheme.MOMENTUM.darkened(0.2) if usable else Color(0.3, 0.3, 0.35), Color(1, 1, 1, 0.8))
	_text(f_num, str(ability_cost), cc + Vector2(0, 5), 14, Color.WHITE)
	_text(UITheme.font("bold"), "HABILIDADE", AC + Vector2(0, AR + 15), 11, Color(UITheme.TEXT, 0.55))

	# deck / graveyard counters
	_counter(Vector2(170, 104), false, deck)
	_counter(Vector2(210, 104), true, grave)

## Small plate with a drawn icon (card stack or tombstone) and a count.
func _counter(pos: Vector2, tomb: bool, n: int) -> void:
	var r := Rect2(pos - Vector2(18, 0), Vector2(36, 24))
	draw_style_box(UITheme.box(Color(0, 0, 0, 0.45), 5, Color(UITheme.GOLD, 0.25)), r)
	var ic := r.position + Vector2(9, 12)
	var ink := Color(UITheme.TEXT, 0.75)
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
	draw_string_outline(f, r.position + Vector2(17, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.8))
	draw_string(f, r.position + Vector2(17, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT)

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
