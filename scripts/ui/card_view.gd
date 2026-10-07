class_name CardView
extends Control
## A card drawn entirely in code: ornate essence frame (gold foil for the
## Legendary), art window, name plate, keyword panel, embossed cost /
## Ataque / Vida gems, drop shadow, hover glow and the hooks used by the
## table animations (shake, flash, dissolve).

signal left_clicked(view: CardView)
signal right_clicked(view: CardView)

const BASE := Vector2(120, 170)

## Frame palette per essence: gradient top/bottom, metal trim, glow.
const STYLES := {
	"ignea": {"top": "#cf4a20", "bot": "#4a120a", "trim": "#e0a862", "glow": "#ff8a3c"},
	"aquatica": {"top": "#2d7cc4", "bot": "#0b2448", "trim": "#c4dcec", "glow": "#5cc8ff"},
	"glacial": {"top": "#5fb8d8", "bot": "#12384e", "trim": "#e0f2fa", "glow": "#9fe8ff"},
	"vegetal": {"top": "#4a9a3c", "bot": "#12301a", "trim": "#c9d89a", "glow": "#8cf06a"},
	"rochosa": {"top": "#8a6b45", "bot": "#2e2216", "trim": "#d2bc94", "glow": "#d6a868"},
	"metalica": {"top": "#8e9aab", "bot": "#262c36", "trim": "#dfe6ee", "glow": "#c8d8ee"},
	"eletrica": {"top": "#d9b81f", "bot": "#4a3a0a", "trim": "#fff1a0", "glow": "#fff04a"},
	"obscura": {"top": "#6a3fa5", "bot": "#1a0e30", "trim": "#c0a0e0", "glow": "#b07aff"},
	"sagrada": {"top": "#e8d28a", "bot": "#6a5a2a", "trim": "#fff8d8", "glow": "#fff2b0"},
	"neutra": {"top": "#868a92", "bot": "#2a2c32", "trim": "#b4ab9e", "glow": "#dfe4ec"},
	"legendary": {"top": "#f6d887", "bot": "#6e4810", "trim": "#fff0b8", "glow": "#ffd35a"},
	"back": {"top": "#2e2658", "bot": "#100c22", "trim": "#c9a24e", "glow": "#9d86ff"},
}
const COST_COL := UITheme.MOMENTUM
const ATK_COL := Color("#c8402e")
const HP_COL := Color("#2f9e58")

var card_id := ""
var inst: Dictionary = {} ## creature on board (live stats) or hand instance
var uid := 0
var face_down := false
var highlight := Color.TRANSPARENT ## outline for selection/targets
var dim := false
var cost_override := -1
var hovered := false
var hit_pad := 0.0 ## extra hit area below the card (lifted hand cards)
## Animation hooks, driven by tweens: draw offsets (hit tremor, attack
## lunge) and a red hit flash 0..1.
var shake := Vector2.ZERO:
	set(v):
		shake = v
		queue_redraw()
var lunge := Vector2.ZERO:
	set(v):
		lunge = v
		queue_redraw()
var flash := 0.0:
	set(v):
		flash = v
		queue_redraw()
var shadow := true

var _t := 0.0
static var _tex_cache := {}
static var _dissolve: Shader

func setup(id: String, instance: Dictionary = {}, size_scale := 1.0) -> CardView:
	card_id = id
	inst = instance
	uid = instance.get("uid", 0)
	custom_minimum_size = BASE * size_scale
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_t = randf() * 10.0
	mouse_entered.connect(func():
		hovered = true
		queue_redraw())
	mouse_exited.connect(func():
		hovered = false
		queue_redraw())
	return self

func _has_point(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size + Vector2(0, hit_pad)).has_point(p)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			left_clicked.emit(self)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(self)
		accept_event()

func _process(delta: float) -> void:
	if highlight.a > 0 or hovered or _legendary():
		_t += delta
		queue_redraw()

static func texture(file: String) -> Texture2D:
	if file == "":
		return null
	if not _tex_cache.has(file):
		var path := "res://assets/portraits/" + file
		_tex_cache[file] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[file]

## Burns the card away (death / spent spell). The node frees itself.
func dissolve(delay := 0.0, edge := Color(1.0, 0.55, 0.15), dur := 0.75) -> void:
	if _dissolve == null:
		_dissolve = load("res://scripts/ui/shaders/dissolve.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _dissolve
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("progress", 0.0)
	material = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(m, "shader_parameter/progress", 1.0, dur).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

func _legendary() -> bool:
	return not face_down and card_id != "" and CardDB.card(card_id)["rarity"] == "legendary"

# ---------------------------------------------------------------- drawing

func _draw() -> void:
	draw_set_transform(shake + lunge)
	var s := size.x / BASE.x
	var r := Rect2(Vector2.ZERO, size)
	var rad := 10.0 * s
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var cd: Dictionary = {} if face_down else CardDB.card_for(card_id, inst)
	var st: Dictionary = STYLES["back"] if face_down else STYLES[_style_key(cd)]
	var trim := Color(st["trim"])
	var glow := Color(st["glow"])

	# drop shadow, deeper when the card is lifted
	if shadow:
		var depth := (12.0 if hovered else 4.0) * s
		for i in 5:
			var g := r.grow((i * 2.2 + 1) * s)
			g.position.y += depth
			_rrect_fill(g, rad + i * 2 * s, Color(0, 0, 0, 0.11))
	# legendary halo
	if not face_down and cd["rarity"] == "legendary":
		for i in 4:
			_rrect_line(r.grow((2 + i * 2.5) * s), rad + i * 2 * s, Color(glow, (0.22 - i * 0.05) * (0.6 + 0.4 * pulse)), 2.5 * s)
	# selection / target glow
	if highlight.a > 0:
		for i in 4:
			_rrect_line(r.grow((2 + i * 2.2) * s), rad + i * 2 * s, Color(highlight, (0.9 - i * 0.22) * (0.65 + 0.35 * pulse)), 2.2 * s)
	elif hovered:
		for i in 3:
			_rrect_line(r.grow((1.5 + i * 2) * s), rad + i * 2 * s, Color(glow, 0.5 - i * 0.15), 2 * s)

	# frame: gradient body, dark outer edge, metal trim with bevel
	_rrect_grad(r, rad, Color(st["top"]), Color(st["bot"]))
	_rrect_line(r.grow(-0.5 * s), rad, Color("#07060a"), 1.6 * s)
	_rrect_line(r.grow(-2.6 * s), rad - 2 * s, Color(trim, 0.85), 1.1 * s)
	draw_line(Vector2(rad, 1.6 * s), Vector2(size.x - rad, 1.6 * s), Color(1, 1, 1, 0.3), 1.0 * s)

	if face_down:
		_draw_back(r, s, trim)
		_finish(r, rad, s)
		return

	var font := UITheme.font("heavy")
	var col := Color(CardDB.essence(cd["essence"])["color"])
	# art window
	var art := Rect2(Vector2(7, 8) * s, Vector2(BASE.x - 14, 98) * s)
	draw_rect(art.grow(1.5 * s), Color("#07060a"))
	var tex := texture(cd.get("art", ""))
	if tex:
		var ts := tex.get_size()
		var k: float = max(art.size.x / ts.x, art.size.y / ts.y)
		var src_size := art.size / k
		draw_texture_rect_region(tex, art, Rect2(Vector2((ts.x - src_size.x) / 2, 0), src_size))
	else:
		_placeholder(art, cd, col, s)
	# inner shading at the top and bottom of the window
	_vgrad(Rect2(art.position, Vector2(art.size.x, 14 * s)), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0))
	_vgrad(Rect2(art.position + Vector2(0, art.size.y - 22 * s), Vector2(art.size.x, 22 * s)), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55))
	draw_rect(art.grow(0.5 * s), Color(trim, 0.9), false, 1.2 * s)
	for c in [art.position, Vector2(art.end.x, art.position.y)]:
		_diamond(c, 3.2 * s, trim)
	# divine shield bubble
	if inst.get("shield", false):
		var sc := art.get_center()
		for i in 3:
			draw_arc(sc, art.size.x * 0.46 - i * 3 * s, 0, TAU, 48, Color("#9fe3ff", 0.55 - i * 0.15), 2 * s, true)
		draw_rect(art, Color("#9fe3ff", 0.12))

	# name plate (pointed banner overlapping the art)
	var py := 102.0 * s
	var ph := 20.0 * s
	var plate := PackedVector2Array([Vector2(3 * s, py + ph / 2), Vector2(10 * s, py), Vector2(size.x - 10 * s, py),
		Vector2(size.x - 3 * s, py + ph / 2), Vector2(size.x - 10 * s, py + ph), Vector2(10 * s, py + ph)])
	draw_colored_polygon(plate, Color("#15121b"))
	draw_colored_polygon(PackedVector2Array([plate[1], plate[2], plate[3], plate[0]]), Color(1, 1, 1, 0.05))
	draw_polyline(plate + PackedVector2Array([plate[0]]), trim, 1.2 * s, true)
	var nf := UITheme.font("title_bold")
	var name_s: String = cd["name"]
	_text(nf, name_s, Vector2(size.x / 2, py + ph / 2 + 4 * s), _fit(nf, name_s, 10.5 * s, size.x - 30 * s), Color("#fff4dc"))

	# lower panel: keywords (creatures) or card type
	var panel := Rect2(Vector2(10, 126) * s, Vector2(BASE.x - 20, 34) * s)
	_rrect_fill(panel, 4 * s, Color(0, 0, 0, 0.38))
	_rrect_line(panel, 4 * s, Color(trim, 0.25), 1 * s)
	var lines := _panel_lines(cd)
	var bf := UITheme.font("bold")
	var ly := panel.get_center().y + 3.5 * s - (lines.size() - 1) * 5.5 * s
	for ln in lines:
		var fs := _fit(bf, ln[0], 9.5 * s, panel.size.x - 34 * s)
		_text(bf, ln[0], Vector2(size.x / 2, ly), fs, ln[1])
		ly += 11 * s

	# essence seal on the bottom edge, crest on the top edge
	_seal(Vector2(size.x / 2, size.y - 3 * s), 5.5 * s, cd["essence"], col, trim)
	_diamond(Vector2(size.x / 2, 2.5 * s), 3.5 * s, trim)

	# gems
	var cost: int = cost_override if cost_override >= 0 else int(cd["cost"])
	_gem("orb", Vector2(14, 14) * s, 13 * s, COST_COL, str(cost), Color("#2a1c00"), s)
	if cd["type"] == "creature":
		var atk: int = int(cd["atk"])
		var hp: int = int(cd["hp"])
		var atk_col := Color.WHITE
		var hp_col := Color.WHITE
		if inst.has("damage"):
			var live_atk: int = max(0, inst["atk"] + inst["temp_atk"])
			atk_col = Color("#a8ffa0") if live_atk > atk else Color.WHITE
			atk = live_atk
			hp_col = Color("#ff8a80") if inst["damage"] > 0 else (Color("#a8ffa0") if inst["hp"] > hp else Color.WHITE)
			hp = max(0, inst["hp"] - inst["damage"])
		_gem("diamond", Vector2(14 * s, size.y - 15 * s), 13.5 * s, ATK_COL, str(atk), atk_col, s)
		_gem("shield", Vector2(size.x - 14 * s, size.y - 15 * s), 12.5 * s, HP_COL, str(hp), hp_col, s)
	_finish(r, rad, s)

## Overlays shared by both faces: foil shimmer, hit flash, dim veil.
func _finish(r: Rect2, rad: float, s: float) -> void:
	if _legendary():
		var x := fmod(_t * 0.45, 1.6) * (size.x + size.y) - size.y
		var band := PackedVector2Array([Vector2(x, size.y), Vector2(x + 26 * s, size.y), Vector2(x + 26 * s + size.y, 0), Vector2(x + size.y, 0)])
		for poly in Geometry2D.intersect_polygons(band, _rrect_pts(r, rad)):
			draw_colored_polygon(poly, Color(1, 0.96, 0.8, 0.16))
	if flash > 0:
		_rrect_fill(r, rad, Color(1, 0.2, 0.15, 0.45 * flash))
	if dim:
		_rrect_fill(r, rad, Color(0, 0, 0, 0.5))

func _style_key(cd: Dictionary) -> String:
	if cd["rarity"] == "legendary":
		return "legendary"
	return cd["essence"] if STYLES.has(cd["essence"]) else "neutra"

func _panel_lines(cd: Dictionary) -> Array:
	var kws: Array = inst.get("keywords", cd.get("keywords", [])).duplicate()
	if inst.has("shield"):
		kws.erase("escudo")
		if inst["shield"]:
			kws.push_front("escudo")
	var out := []
	if cd["type"] != "creature":
		out.append([{"spell": "FEITIÇO", "equipment": "EQUIPAMENTO"}[cd["type"]], Color(UITheme.TEXT, 0.6)])
	var names: Array = []
	for kw in kws:
		names.append(CardDB.keyword(kw)["name"])
	if names.size() > 0:
		if names.size() <= 2 and out.is_empty():
			for n in names:
				out.append([n, Color("#9fe3ff") if n == CardDB.keyword("escudo")["name"] else Color("#ffe7a0")])
		else:
			out.append([" · ".join(names), Color("#ffe7a0")])
	if out.is_empty():
		var rar := {"legendary": "CAMPEÃO LENDÁRIO", "champion": "CAMPEÃO", "common": "UNIDADE"}
		out.append([rar.get(cd["rarity"], ""), Color(UITheme.TEXT, 0.45)])
	return out

func _draw_back(r: Rect2, s: float, trim: Color) -> void:
	var inner := r.grow(-7 * s)
	_rrect_fill(inner, 5 * s, Color("#17122e"))
	# diamond lattice
	var step := 11.0 * s
	var row := 0
	var y := inner.position.y + step / 2
	while y < inner.end.y:
		var x := inner.position.x + (step / 2 if row % 2 == 0 else step)
		while x < inner.end.x - 2 * s:
			_diamond(Vector2(x, y), 1.8 * s, Color(trim, 0.16))
			x += step
		y += step / 2
		row += 1
	_rrect_line(inner, 5 * s, Color(trim, 0.6), 1.2 * s)
	# central medallion
	var c := r.get_center()
	for i in 6:
		draw_circle(c, (34 - i * 3) * s, Color("#9d86ff", 0.025))
	draw_circle(c, 25 * s, Color("#100c22"))
	draw_arc(c, 25 * s, 0, TAU, 48, trim, 2 * s, true)
	draw_arc(c, 20 * s, 0, TAU, 48, Color(trim, 0.5), 1 * s, true)
	var star := PackedVector2Array()
	for i in 16:
		var a := i * TAU / 16 - PI / 2
		star.append(c + Vector2(cos(a), sin(a)) * (17 if i % 2 == 0 else 7) * s)
	draw_colored_polygon(star, Color(trim, 0.85))
	_diamond(c, 4 * s, UITheme.GOLD_LIGHT)
	for c2 in [Vector2(c.x, inner.position.y + 14 * s), Vector2(c.x, inner.end.y - 14 * s)]:
		_diamond(c2, 4 * s, Color(trim, 0.7))

## Art stand-in for cards without a portrait: gradient, glow, essence sigil.
func _placeholder(art: Rect2, cd: Dictionary, col: Color, s: float) -> void:
	_vgrad(art, col.darkened(0.15), col.darkened(0.75))
	var c := art.get_center() + Vector2(0, 2 * s)
	for i in 8:
		draw_circle(c, (46 - i * 5) * s, Color(col.lightened(0.4), 0.05))
	var kind: String = cd["type"] if cd["type"] != "creature" else cd["essence"]
	var pts := _sigil(kind, c, 26 * s)
	draw_colored_polygon(_grow(pts, c, 1.12), Color(0, 0, 0, 0.35))
	draw_colored_polygon(pts, col.lightened(0.55))
	draw_colored_polygon(_grow(pts, c + Vector2(0, 6 * s), 0.55), Color(1, 1, 1, 0.45))
	var f := UITheme.font("title_bold")
	var initial := String(cd["name"]).substr(0, 1)
	_text(f, initial, Vector2(art.end.x - 12 * s, art.end.y - 6 * s), 13 * s, Color(1, 1, 1, 0.35))

func _sigil(kind: String, c: Vector2, r: float) -> PackedVector2Array:
	var n: Array
	match kind:
		"ignea":
			n = [[0, -1], [0.22, -0.5], [0.48, -0.72], [0.62, -0.05], [0.52, 0.5], [0, 0.82], [-0.52, 0.5], [-0.62, 0.02], [-0.42, -0.4], [-0.24, -0.15]]
		"aquatica":
			var out := PackedVector2Array([c + Vector2(0, -r)])
			for i in 13:
				var a := deg_to_rad(-30 + i * 20)
				out.append(c + Vector2(0, r * 0.25) + Vector2(cos(a), sin(a)) * r * 0.62)
			return out
		"spell":
			var out := PackedVector2Array()
			for i in 16:
				var a := i * TAU / 16 - PI / 2
				out.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if i % 2 == 0 else 0.38))
			return out
		"equipment":
			n = [[0, -1], [0.14, -0.82], [0.14, 0.3], [0.5, 0.3], [0.5, 0.44], [0.1, 0.44], [0.1, 0.9], [-0.1, 0.9], [-0.1, 0.44], [-0.5, 0.44], [-0.5, 0.3], [-0.14, 0.3], [-0.14, -0.82]]
		_:
			n = [[0, -1], [0.22, -0.22], [1, 0], [0.22, 0.22], [0, 1], [-0.22, 0.22], [-1, 0], [-0.22, -0.22]]
	var pts := PackedVector2Array()
	for p in n:
		pts.append(c + Vector2(p[0], p[1]) * r)
	return pts

func _seal(c: Vector2, r: float, essence: String, col: Color, trim: Color) -> void:
	draw_circle(c, r + 1.5, Color("#07060a"))
	draw_circle(c, r, col.darkened(0.35))
	draw_arc(c, r, 0, TAU, 24, trim, 1.0, true)
	draw_colored_polygon(_sigil(essence, c, r * 0.62), col.lightened(0.5))

## Embossed gem: drop shadow, metal bezel, body, glossy highlight, specular.
func _gem(kind: String, c: Vector2, r: float, col: Color, t: String, tcol: Color, s: float) -> void:
	var pts := _shape(kind, c, r)
	var shadow_pts := _grow(pts, c, 1.18)
	for i in shadow_pts.size():
		shadow_pts[i] += Vector2(0, 2 * s)
	draw_colored_polygon(shadow_pts, Color(0, 0, 0, 0.55))
	draw_colored_polygon(_grow(pts, c, 1.16), UITheme.GOLD_DARK.darkened(0.3))
	draw_colored_polygon(_grow(pts, c, 1.1), UITheme.GOLD)
	draw_colored_polygon(pts, col.darkened(0.35))
	draw_colored_polygon(_grow(pts, c - Vector2(0, r * 0.1), 0.86), col)
	draw_colored_polygon(_grow(pts, c - Vector2(0, r * 0.55), 0.5), Color(col.lightened(0.5), 0.45))
	draw_circle(c + Vector2(-r * 0.32, -r * 0.42), r * 0.14, Color(1, 1, 1, 0.55))
	var rim := _grow(pts, c, 1.1)
	draw_polyline(rim + PackedVector2Array([rim[0]]), Color(UITheme.GOLD_LIGHT, 0.7), 0.9 * s, true)
	var f := UITheme.font("heavy")
	var fs := r * 1.3
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	var pos := Vector2(c.x - w / 2, c.y + fs * 0.34 - (r * 0.1 if kind == "shield" else 0.0))
	draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), max(3, int(fs / 4)), Color(0, 0, 0, 0.9))
	draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), tcol)

func _shape(kind: String, c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match kind:
		"diamond":
			for p in [[0, -1.08], [1.0, 0], [0, 1.08], [-1.0, 0]]:
				pts.append(c + Vector2(p[0], p[1]) * r)
		"shield":
			for p in [[-0.9, -0.88], [0.9, -0.88], [0.92, 0.08], [0, 1.02], [-0.92, 0.08]]:
				pts.append(c + Vector2(p[0], p[1]) * r)
		_:
			for i in 28:
				var a := i * TAU / 28
				pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts

# ---------------------------------------------------------------- helpers

func _rrect_pts(r: Rect2, rad: float) -> PackedVector2Array:
	rad = min(rad, min(r.size.x, r.size.y) / 2)
	var pts := PackedVector2Array()
	var corners := [[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5]]
	for cn in corners:
		for i in 6:
			var a: float = cn[1] + PI / 2 * i / 5.0
			pts.append(cn[0] + Vector2(cos(a), sin(a)) * rad)
	return pts

func _rrect_fill(r: Rect2, rad: float, col: Color) -> void:
	draw_colored_polygon(_rrect_pts(r, rad), col)

func _rrect_line(r: Rect2, rad: float, col: Color, w: float) -> void:
	var pts := _rrect_pts(r, rad)
	pts.append(pts[0])
	draw_polyline(pts, col, w, true)

func _rrect_grad(r: Rect2, rad: float, top: Color, bot: Color) -> void:
	var pts := _rrect_pts(r, rad)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bot, clamp((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	draw_polygon(pts, cols)

func _vgrad(r: Rect2, top: Color, bot: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bot, bot]))

func _diamond(c: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)]), col)

func _grow(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k)
	return out

func _fit(font: Font, t: String, fs: float, max_w: float) -> float:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	return fs if w <= max_w else max(7.0, fs * max_w / w)

func _text(font: Font, t: String, center: Vector2, fs: float, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	draw_string_outline(font, Vector2(center.x - w / 2, center.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), max(2, int(fs / 5)), Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(center.x - w / 2, center.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), col)
