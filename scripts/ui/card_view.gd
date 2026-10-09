class_name CardView
extends Control
## A card drawn entirely in code: ornate essence frame (gold foil for the
## Legendary), art window, name plate, keyword panel, embossed cost /
## Ataque / Vida gems, drop shadow, hover glow and the hooks used by the
## table animations (shake, flash, dissolve).

signal left_clicked(view: CardView)
signal right_clicked(view: CardView)
signal drag_started(view: CardView)
signal drag_moved(view: CardView)
signal drag_ended(view: CardView)

const DRAG_PX := 14.0

const BASE := Vector2(120, 170)

## Frame palette per essence: gradient top/bottom, metal trim, glow.
const STYLES := {
	"ignea": {"top": "#cf4a20", "bot": "#4a120a", "trim": "#e0a862", "glow": "#ff8a3c"},
	"aquatica": {"top": "#2d7cc4", "bot": "#0b2448", "trim": "#c4dcec", "glow": "#5cc8ff"},
	"glacial": {"top": "#a9e4f5", "bot": "#1c4a63", "trim": "#f2fbff", "glow": "#c8f4ff"}, ## frost: pale ice over deep teal
	"vegetal": {"top": "#4a9a3c", "bot": "#12301a", "trim": "#c9d89a", "glow": "#8cf06a"},
	"rochosa": {"top": "#8a6b45", "bot": "#2e2216", "trim": "#d2bc94", "glow": "#d6a868"},
	"metalica": {"top": "#8e9aab", "bot": "#262c36", "trim": "#dfe6ee", "glow": "#c8d8ee"},
	"eletrica": {"top": "#d9b81f", "bot": "#4a3a0a", "trim": "#fff1a0", "glow": "#fff04a"},
	"obscura": {"top": "#34343a", "bot": "#030304", "trim": "#7c7c85", "glow": "#8a8a96"}, ## near-black gradient, dark-grey trim
	"sagrada": {"top": "#e8d28a", "bot": "#6a5a2a", "trim": "#fff8d8", "glow": "#fff2b0"},
	"neutra": {"top": "#868a92", "bot": "#2a2c32", "trim": "#b4ab9e", "glow": "#dfe4ec"},
	"legendary": {"top": "#f6d887", "bot": "#6e4810", "trim": "#fff0b8", "glow": "#ffd35a"},
	"back": {"top": "#2e2658", "bot": "#100c22", "trim": "#c9a24e", "glow": "#9d86ff"},
}
const TRIGGER_COL := Color("#ff9a4a") ## trigger tags: same weight as keywords, orange to read as another category
const GOLD_TRIM := Color("#f3d27a")
const COST_COL := UITheme.MOMENTUM
const ATK_COL := Color("#c8402e")
const HP_COL := Color("#2f9e58")
const FROST := Color("#cfefff")

var card_id := ""
var inst: Dictionary = {} ## unit on board (live stats) or hand instance
var uid := 0
var face_down := false
var highlight := Color.TRANSPARENT ## outline for selection/targets
var dim := false
var cost_override := -1
var stat_bonus := Vector2i.ZERO ## live "constante" scaling for cards off the board (hand, command zone)
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
## Trigger going off: proc 0..1 is the pop + rim light, proc_wave 0..1 the ring pulsing out
## and the light sweeping across the card (0 = off).
var proc := 0.0:
	set(v):
		proc = v
		queue_redraw()
var proc_wave := 0.0:
	set(v):
		proc_wave = v
		queue_redraw()
var shadow := true
var fatigue := 0 ## > 0: not a real card but the Fadiga pseudo-card, showing this much damage

var _t := 0.0
var _redraw_acc := 0.0
var _holding := false
var _long := false
var _press_id := 0
var _press_pos := Vector2.ZERO
var draggable := false ## set by Main: hand cards that can be played are dragged onto the board
var dragging := false
static var _tex_cache := {}
static var _dissolve: Shader
static var _stealth_shader: Shader

## Keywords that change who can block whom get an icon medallion on the art (MTG Arena style),
## in this order down the left edge; glyph tint per keyword.
const BADGES := {
	"voo": Color("#bfe6ff"),
	"longo_alcance": Color("#d6efaa"),
	"furtividade": Color("#cdb6ff"),
	"vigilancia": Color("#ffe39a"),
	"nao_bloqueia": Color("#ff7f6e"),
}

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
	if inst.has("damage") and _keywords(CardDB.card_for(id, inst)).has("furtividade"):
		_stealth()
	return self

## Furtividade on the board: half see-through card under a drifting fog (shader, no redraws).
func _stealth() -> void:
	if _stealth_shader == null:
		_stealth_shader = load("res://scripts/ui/shaders/stealth.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _stealth_shader
	m.set_shader_parameter("size", size)
	material = m

func _has_point(p: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size + Vector2(0, hit_pad)).has_point(p)

## Phones/tablets: no hover and no right button, so tap = click and long-press = overlay.
static var touched := false ## set by Main on any real touch event; cleared by a real mouse

static func touch_ui() -> bool:
	return touched or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") 		or DisplayServer.is_touchscreen_available()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and _holding and draggable:
		if not dragging and e.global_position.distance_to(_press_pos) > DRAG_PX:
			dragging = true
			drag_started.emit(self)
		if dragging:
			drag_moved.emit(self)
		accept_event()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and (touch_ui() or draggable):
		if e.pressed:
			_holding = true
			_long = false
			dragging = false
			_press_pos = e.global_position
			var id := Time.get_ticks_msec()
			_press_id = id
			if touch_ui():
				get_tree().create_timer(0.4).timeout.connect(func():
					if is_instance_valid(self) and _holding and _press_id == id and not dragging:
						_long = true
						right_clicked.emit(self))
		else:
			_holding = false
			if dragging:
				dragging = false
				drag_ended.emit(self)
			elif not _long:
				left_clicked.emit(self)
		accept_event()
		return
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			left_clicked.emit(self)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(self)
		accept_event()

func _process(delta: float) -> void:
	if highlight.a > 0 or hovered or _legendary():
		_t += delta
		_redraw_acc += delta
		if _redraw_acc >= 0.033 or highlight.a > 0 or hovered: ## shimmer at ~30 fps is plenty
			_redraw_acc = 0.0
			queue_redraw()

## Rules text as BBCode with trigger names (and an optional "(...)" qualifier
## before the colon, e.g. "Aliado Morre (uma vez por turno):") in bold orange.
## "Name (cost) {speed} (limits):" -> bold orange, with "{speed}" (lento/rapido/instantaneo)
## drawn as the spell speed seal (assets/ui/speed_<speed>.png, see tools/render_speed_badges.gd).
static func colorize_triggers(body: String, line_px := 28) -> String:
	var open := "[b][color=#%s]" % TRIGGER_COL.to_html(false)
	for tid in CardDB.data()["triggers"]:
		var tn: String = CardDB.data()["triggers"][tid]["name"]
		var re := RegEx.create_from_string(r"(%s(?: \([^)]*\))?)(?: \{(lento|rapido|instantaneo)\})?((?: \([^)]*\))?):" % tn)
		for m in re.search_all(body):
			var out := open + m.get_string(1) + "[/color][/b]"
			if m.get_string(2) != "":
				out += " [img height=%d]res://assets/ui/speed_%s.png[/img]" % [int(line_px * 0.95), m.get_string(2)]
			out += open + m.get_string(3) + ":[/color][/b]"
			body = body.replace(m.get_string(0), out)
	return body

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
	return not face_down and card_id != "" and CardDB.card(card_id)["rarity"] in ["champion", "legendary"]

# ---------------------------------------------------------------- drawing

var badge_only := "" ## tools/render_speed_badges.gd: draw just this speed seal, centered

func _draw() -> void:
	if badge_only != "":
		_speed_badge(size / 2.0, badge_only, size.y / 12.4)
		return
	var pop := 1.0 + 0.08 * proc ## scales around the center
	draw_set_transform(shake + lunge + size / 2.0 * (1.0 - pop), 0.0, Vector2(pop, pop))
	var s := size.x / BASE.x
	var r := Rect2(Vector2.ZERO, size)
	var rad := 10.0 * s
	if fatigue > 0:
		_draw_fatigue(r, s, rad)
		return
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var cd: Dictionary = {} if face_down else CardDB.card_for(card_id, inst)
	var keys: Array = ["back"] if face_down else _style_keys(cd)
	var st: Dictionary = STYLES[keys[0]]
	var st2: Dictionary = STYLES[keys[1]] if keys.size() > 1 else st ## dual essence: half/half frame
	var trim := Color(st["trim"]).lerp(Color(st2["trim"]), 0.5)
	if cd.get("rarity", "") == "champion":
		trim = GOLD_TRIM ## champions keep their essence frame, finished in gold
	var glow := Color(st["glow"]).lerp(Color(st2["glow"]), 0.5)

	# drop shadow, deeper when the card is lifted
	if shadow:
		var depth := (12.0 if hovered else 4.0) * s
		for i in 5:
			var g := r.grow((i * 2.2 + 1) * s)
			g.position.y += depth
			_rrect_fill(g, rad + i * 2 * s, Color(0, 0, 0, 0.11))
	# legendary halo
	if not face_down and cd["rarity"] in ["champion", "legendary"]:
		for i in 4:
			_rrect_line(r.grow((2 + i * 2.5) * s), rad + i * 2 * s, Color(glow, (0.22 - i * 0.05) * (0.6 + 0.4 * pulse)), 2.5 * s)
	# selection / target glow
	if highlight.a > 0:
		for i in 4:
			_rrect_line(r.grow((2 + i * 2.2) * s), rad + i * 2 * s, Color(highlight, (0.9 - i * 0.22) * (0.65 + 0.35 * pulse)), 2.2 * s)
	elif hovered:
		for i in 3:
			_rrect_line(r.grow((1.5 + i * 2) * s), rad + i * 2 * s, Color(glow, 0.5 - i * 0.15), 2 * s)
	# trigger proc: hot rim light, plus a ring pulsing out of the frame
	if proc > 0:
		for i in 5:
			_rrect_line(r.grow((1.5 + i * 2.4) * s), rad + i * 2 * s, Color(TRIGGER_COL.lightened(0.25 - i * 0.05), (0.95 - i * 0.18) * proc), 2.6 * s)
	if proc_wave > 0 and proc_wave < 1:
		var k := 1.0 - pow(1.0 - proc_wave, 3.0)
		_rrect_line(r.grow((3 + 30 * k) * s), rad + 12 * k * s, Color(TRIGGER_COL.lightened(0.35), 0.85 * pow(1.0 - proc_wave, 1.5)), (3.2 - 2.2 * k) * s)

	# frame: gradient body, dark outer edge, metal trim with bevel
	if keys.size() < 2:
		_rrect_grad(r, rad, Color(st["top"]), Color(st["bot"]))
	else:
		_rrect_grad_split(r, rad, st, st2, s)
	_rrect_line(r.grow(-0.5 * s), rad, Color("#07060a"), 1.6 * s)
	_rrect_line(r.grow(-2.6 * s), rad - 2 * s, Color(trim, 0.85), 1.1 * s)
	draw_line(Vector2(rad, 1.6 * s), Vector2(size.x - rad, 1.6 * s), Color(1, 1, 1, 0.3), 1.0 * s)

	if face_down:
		_draw_back(r, s, trim)
		_finish(r, rad, s)
		return

	var font := UITheme.font("heavy")
	var col := Color(CardDB.essence(CardDB.essences_of(cd)[0])["color"])
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
			draw_arc(sc, art.size.x * 0.46 - i * 3 * s, 0, TAU, 48, Color("#9fe3ff", (0.55 - i * 0.15) * 1.25), 2.5 * s, true) ## ~25% more visible
		draw_rect(art, Color("#9fe3ff", 0.15))
	# spell shield: violet runic ring
	if inst.get("spell_shield", false):
		var sc := art.get_center()
		var rr := art.size.x * 0.4
		for i in 3: ## same weight as the divine shield bubble, only the color differs
			draw_arc(sc, rr - i * 3 * s, 0, TAU, 48, Color("#c9a8ff", (0.55 - i * 0.15) * 1.25), 2.5 * s, true)
		draw_rect(art, Color("#c9a8ff", 0.15))
		for i in 6:
			var a := _t * 0.6 + i * TAU / 6.0
			_diamond(sc + Vector2(cos(a), sin(a)) * rr, 2.6 * s, Color("#e3d2ff"))
	if inst.has("frozen"):
		_draw_frost(art, s)
	if inst.get("tide_mark", false):
		draw_arc(art.get_center() + Vector2(0, art.size.y * 0.32), art.size.x * 0.3, PI * 1.15, PI * 1.85, 24, Color("#6fd0ff", 0.85), 2 * s, true)
	_kw_badges(art, cd, s)

	# species strip on the bottom edge of the art, right above the name plate
	var sp_s := CardDB.species_names(cd).to_upper()
	if sp_s != "":
		var spf := UITheme.font("bold")
		var sp_fs := _fit(spf, sp_s, 8.0 * s, art.size.x - 16 * s)
		var sp_w := spf.get_string_size(sp_s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(sp_fs)).x + 10 * s
		var strip := Rect2(Vector2((size.x - sp_w) / 2, 90.5 * s), Vector2(sp_w, 11 * s))
		_rrect_fill(strip, 3 * s, Color(0, 0, 0, 0.62))
		_rrect_line(strip, 3 * s, Color(trim, 0.45), 0.8 * s)
		_text(spf, sp_s, Vector2(size.x / 2, strip.get_center().y + sp_fs * 0.36), sp_fs, Color("#e9dcc0"))

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
	_text(nf, name_s, Vector2(size.x / 2, py + ph / 2 + 4 * s), _fit(nf, name_s, 11.5 * s, size.x - 24 * s), Color("#fff4dc"))

	# lower panel: keywords (units), card type (artifacts) or the rules text (spells)
	if cd["type"] == "spell":
		# no gems at the bottom corners of a spell, so its panel is wider and taller to fit the text
		var tp := Rect2(Vector2(8, 124.5) * s, Vector2(BASE.x - 16, 36.5) * s)
		_rrect_fill(tp, 4 * s, Color(0, 0, 0, 0.5))
		_rrect_line(tp, 4 * s, Color(trim, 0.25), 1 * s)
		_wrapped_text(UITheme.font("bold"), str(cd.get("text", "")), tp.grow_individual(-4 * s, -1.5 * s, -4 * s, -1.5 * s), 10.0 * s, 6.0 * s, Color("#f1e8d4"))
		_speed_badge(Vector2(size.x / 2, 17 * s), str(cd.get("speed", "lento")), s)
	else:
		var panel := Rect2(Vector2(10, 126) * s, Vector2(BASE.x - 20, 34) * s)
		_rrect_fill(panel, 4 * s, Color(0, 0, 0, 0.38))
		_rrect_line(panel, 4 * s, Color(trim, 0.25), 1 * s)
		var lines := _panel_lines(cd)
		var bf := UITheme.font("bold")
		var ly := panel.get_center().y + 3.5 * s - (lines.size() - 1) * 6.25 * s
		for ln in lines:
			var room := panel.size.x - 24 * s
			if cd["type"] == "unit" and ly > 142 * s:
				room = size.x - 2 * 31 * s # lines low in the panel sit between the atk/hp gems
			_text_segments(bf, ln, Vector2(size.x / 2, ly), 11.5 * s, room)
			ly += 12.5 * s

	# essence seal on the bottom edge, crest on the top edge
	_rarity_gem(Vector2(size.x / 2, size.y - 3 * s), 5.5 * s, cd["rarity"], trim)
	_diamond(Vector2(size.x / 2, 2.5 * s), 3.5 * s, trim)

	# gems
	var cost: int = cost_override if cost_override >= 0 else int(cd["cost"])
	var cost_col := Color.WHITE
	if cost < int(cd["cost"]):
		cost_col = Color("#a8ffa0")
	elif cost > int(cd["cost"]):
		cost_col = Color("#ff8a80")
	_gem("orb", Vector2(14, 14) * s, 13 * s, COST_COL, str(cost), cost_col, s)
	_essence_badge(Vector2(BASE.x - 14, 14) * s, 10.5 * s, cd, s)
	if cd["type"] == "unit":
		var atk: int = int(cd["atk"])
		var hp: int = int(cd["hp"])
		var atk_col := Color.WHITE
		var hp_col := Color.WHITE
		if inst.has("damage"):
			var live_atk: int = max(0, inst["atk"] + inst["temp_atk"] + int(inst.get("bonus_atk", 0)))
			atk_col = Color("#a8ffa0") if live_atk > atk else Color.WHITE
			atk = live_atk
			hp_col = Color("#ff8a80") if inst["damage"] > 0 else (Color("#a8ffa0") if inst["hp"] + int(inst.get("bonus_hp", 0)) > hp else Color.WHITE)
			hp = max(0, inst["hp"] + int(inst.get("bonus_hp", 0)) - inst["damage"])
		elif stat_bonus != Vector2i.ZERO:
			atk_col = Color("#a8ffa0") if stat_bonus.x > 0 else Color.WHITE
			hp_col = Color("#a8ffa0") if stat_bonus.y > 0 else Color.WHITE
			atk = max(0, atk + stat_bonus.x)
			hp = max(0, hp + stat_bonus.y)
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
	if proc_wave > 0 and proc_wave < 1:
		# a bright band of light sweeping across the card
		var bx := lerpf(-size.y * 0.6, size.x + 10 * s, proc_wave)
		var bw := 30 * s
		var sweep := PackedVector2Array([Vector2(bx - size.y * 0.4, size.y), Vector2(bx - size.y * 0.4 + bw, size.y), Vector2(bx + size.y * 0.6 + bw, 0), Vector2(bx + size.y * 0.6, 0)])
		for poly in Geometry2D.intersect_polygons(sweep, _rrect_pts(r, rad)):
			draw_colored_polygon(poly, Color(1, 0.93, 0.8, 0.32 * (1.0 - proc_wave * 0.6)))
	if proc > 0:
		_rrect_fill(r, rad, Color(TRIGGER_COL.lightened(0.5), 0.22 * proc))
	if flash > 0:
		_rrect_fill(r, rad, Color(1, 0.2, 0.15, 0.45 * flash))
	if dim:
		_rrect_fill(r, rad, Color(0, 0, 0, 0.5))

## Fadiga (drawing from an empty deck) shown as if a card had been played: Obscura frame,
## a hooded skull with ember eyes and the damage spelled out.
func _draw_fatigue(r: Rect2, s: float, rad: float) -> void:
	var st: Dictionary = STYLES["obscura"]
	var trim := Color(st["trim"])
	if shadow:
		for i in 5:
			var g := r.grow((i * 2.2 + 1) * s)
			g.position.y += 4.0 * s
			_rrect_fill(g, rad + i * 2 * s, Color(0, 0, 0, 0.11))
	_rrect_grad(r, rad, Color(st["top"]), Color(st["bot"]))
	_rrect_line(r.grow(-0.5 * s), rad, Color("#07060a"), 1.6 * s)
	_rrect_line(r.grow(-2.6 * s), rad - 2 * s, Color(trim, 0.85), 1.1 * s)
	# art: a cowl in the dark, the skull peering out of it
	var art := Rect2(Vector2(7, 8) * s, Vector2(BASE.x - 14, 98) * s)
	draw_rect(art.grow(1.5 * s), Color("#07060a"))
	_vgrad(art, Color("#2a2338"), Color("#070609"))
	var c := art.get_center() + Vector2(0, 6 * s)
	for i in 6:
		draw_circle(c + Vector2(0, -4 * s), (44 - i * 6) * s, Color(0.55, 0.45, 0.75, 0.04))
	var hood := PackedVector2Array()
	for i in 21: # rounded top, flaring down to the bottom of the window
		var a := PI + i * PI / 20.0
		hood.append(c + Vector2(cos(a) * 30, -6 + sin(a) * 34) * s)
	hood.append(Vector2(c.x + 44 * s, art.end.y))
	hood.append(Vector2(c.x - 44 * s, art.end.y))
	draw_colored_polygon(hood, Color("#141119"))
	draw_polyline(hood, Color(0.6, 0.55, 0.75, 0.35), 1.2 * s, true)
	draw_circle(c + Vector2(0, -2 * s), 20 * s, Color("#030304"))
	var bone := Color("#bdb5a6")
	var k := c
	draw_circle(k + Vector2(0, -6 * s), 14 * s, bone)
	draw_rect(Rect2(k + Vector2(-8, 2) * s, Vector2(16, 11) * s), bone)
	for i in 3:
		var tx := k.x + (-4 + i * 4) * s
		draw_line(Vector2(tx, k.y + 8 * s), Vector2(tx, k.y + 13 * s), Color("#4a4540"), 1.0 * s)
	for sx in [-1.0, 1.0]:
		var eye := k + Vector2(sx * 6, -5) * s
		draw_circle(eye, 4.4 * s, Color("#050506"))
		draw_circle(eye, 2.6 * s, Color(1.0, 0.35, 0.15, 0.35))
		draw_circle(eye, 1.3 * s, Color("#ff7a3a"))
	draw_colored_polygon(PackedVector2Array([k + Vector2(0, 0), k + Vector2(-2, 4) * s, k + Vector2(2, 4) * s]), Color("#050506"))
	_vgrad(Rect2(art.position + Vector2(0, art.size.y - 22 * s), Vector2(art.size.x, 22 * s)), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55))
	draw_rect(art.grow(0.5 * s), Color(trim, 0.9), false, 1.2 * s)
	# name plate
	var py := 102.0 * s
	var ph := 20.0 * s
	var plate := PackedVector2Array([Vector2(3 * s, py + ph / 2), Vector2(10 * s, py), Vector2(size.x - 10 * s, py),
		Vector2(size.x - 3 * s, py + ph / 2), Vector2(size.x - 10 * s, py + ph), Vector2(10 * s, py + ph)])
	draw_colored_polygon(plate, Color("#15121b"))
	draw_polyline(plate + PackedVector2Array([plate[0]]), trim, 1.2 * s, true)
	_text(UITheme.font("title_bold"), "Fadiga", Vector2(size.x / 2, py + ph / 2 + 4.5 * s), 14 * s, Color("#fff4dc"))
	# rules text
	var panel := Rect2(Vector2(10, 126) * s, Vector2(BASE.x - 20, 36) * s)
	_rrect_fill(panel, 4 * s, Color(0, 0, 0, 0.38))
	_rrect_line(panel, 4 * s, Color(trim, 0.25), 1 * s)
	var bf := UITheme.font("bold")
	_text(bf, "Sem cartas!", Vector2(size.x / 2, panel.position.y + 15 * s), 12 * s, Color("#e9dcc0"))
	var dmg := "Tome %d de dano." % fatigue
	_text(bf, dmg, Vector2(size.x / 2, panel.position.y + 30 * s), _fit(bf, dmg, 12 * s, panel.size.x - 8 * s), Color("#ff8a80"))
	_diamond(Vector2(size.x / 2, 2.5 * s), 3.5 * s, trim)
	_finish(r, rad, s)

## Frame styles in essence order: one for mono cards, two for dual-essence cards.
func _style_keys(cd: Dictionary) -> Array:
	if cd["rarity"] == "legendary":
		return ["legendary"]
	var out: Array = []
	for e in CardDB.essences_of(cd):
		if STYLES.has(e) and not out.has(e):
			out.append(e)
	return out.slice(0, 2) if not out.is_empty() else ["neutra"]

## Icy veil and frost crystals over the art of a frozen unit.
func _draw_frost(art: Rect2, s: float) -> void:
	draw_rect(art, Color(FROST, 0.26))
	_vgrad(Rect2(art.position, Vector2(art.size.x, art.size.y * 0.35)), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0))
	var mid := art.get_center()
	for c in [art.position + Vector2(10, 10) * s, Vector2(art.end.x - 12 * s, art.position.y + 16 * s),
			Vector2(art.position.x + 16 * s, art.end.y - 14 * s), art.end - Vector2(10, 10) * s, mid]:
		var rr: float = (9.0 if c == mid else 6.0) * s
		for i in 3:
			var a := i * PI / 3.0
			var d := Vector2(cos(a), sin(a)) * rr
			draw_line(c - d, c + d, Color(1, 1, 1, 0.75), 1.1 * s, true)
		_diamond(c, rr * 0.3, Color(1, 1, 1, 0.85))
	draw_rect(art.grow(-0.5 * s), Color(FROST, 0.8), false, 1.4 * s)

## Live keywords on the board, printed ones elsewhere.
func _keywords(cd: Dictionary) -> Array:
	return inst.get("keywords", cd.get("keywords", []))

## Round medallions down the left edge of the art, under the cost gem.
func _kw_badges(art: Rect2, cd: Dictionary, s: float) -> void:
	var kws := _keywords(cd)
	var c := Vector2(art.position.x + 11 * s, art.position.y + 33 * s)
	for kw in BADGES:
		if kws.has(kw):
			_kw_badge(kw, c, 10 * s, s)
			c.y += 23 * s

func _kw_badge(kw: String, c: Vector2, r: float, s: float) -> void:
	var col: Color = BADGES[kw]
	# bezel and body, same metal as the gems
	draw_circle(c + Vector2(0, 1.4 * s), r * 1.18, Color(0, 0, 0, 0.5))
	draw_circle(c, r * 1.14, UITheme.GOLD_DARK.darkened(0.3))
	draw_circle(c, r * 1.07, UITheme.GOLD)
	draw_circle(c, r, col.darkened(0.82))
	draw_circle(c - Vector2(0, r * 0.35), r * 0.62, Color(col, 0.1))
	draw_arc(c, r * 1.07, 0, TAU, 24, Color(UITheme.GOLD_LIGHT, 0.7), 0.8 * s, true)
	var g := r * 0.8 # glyph radius
	var lit := col.lightened(0.15)
	match kw:
		"voo": # a wing, feathers trailing down-left
			var wing := _unit_pts(c, g, [[-0.66, 0.52], [-0.62, 0.05], [-0.42, -0.32], [-0.06, -0.58], [0.38, -0.72],
				[0.74, -0.7], [0.44, -0.42], [0.66, -0.36], [0.32, -0.1], [0.52, -0.02], [0.16, 0.18], [0.34, 0.28],
				[-0.04, 0.42], [-0.32, 0.52]])
			draw_colored_polygon(wing, lit)
			draw_polyline(_unit_pts(c, g, [[-0.48, 0.34], [-0.3, -0.1], [0.05, -0.38], [0.5, -0.56]]), Color(col.darkened(0.6), 0.8), 0.8 * s, true)
		"longo_alcance": # an arrow in flight
			var tail := c + Vector2(-0.62, 0.62) * g
			draw_line(tail, c + Vector2(0.36, -0.36) * g, lit, 1.3 * s, true)
			draw_colored_polygon(_unit_pts(c, g, [[0.74, -0.74], [0.52, -0.16], [0.16, -0.52]]), lit)
			for k in [0.0, 0.2]:
				var b := tail + Vector2(k, -k) * g
				draw_line(b, b + Vector2(-0.3, -0.06) * g, lit, 1.1 * s, true)
				draw_line(b, b + Vector2(0.06, 0.3) * g, lit, 1.1 * s, true)
		"vigilancia": # an open eye
			var eye := PackedVector2Array()
			for i in 13:
				eye.append(c + Vector2(-0.8 + 1.6 * i / 12.0, -0.5 * sin(PI * i / 12.0)) * g)
			for i in range(11, 0, -1):
				eye.append(c + Vector2(-0.8 + 1.6 * i / 12.0, 0.5 * sin(PI * i / 12.0)) * g)
			draw_colored_polygon(eye, lit)
			draw_circle(c, 0.34 * g, col.darkened(0.82))
			draw_circle(c, 0.16 * g, lit)
		"furtividade": # a hood with two eyes glinting in the dark
			draw_colored_polygon(_unit_pts(c, g, [[0, -0.86], [0.44, -0.5], [0.64, 0.05], [0.66, 0.72], [-0.66, 0.72],
				[-0.64, 0.05], [-0.44, -0.5]]), lit)
			var face := PackedVector2Array()
			for i in 20:
				var a := i * TAU / 20
				face.append(c + Vector2(cos(a) * 0.36, 0.18 + sin(a) * 0.42) * g)
			draw_colored_polygon(face, col.darkened(0.85))
			for x in [-0.15, 0.15]:
				draw_circle(c + Vector2(x, 0.12) * g, 0.075 * g + 0.3 * s, Color.WHITE)
		"nao_bloqueia": # a shield under a "no" sign
			draw_colored_polygon(_shape("shield", c, g * 0.58), Color("#e9e0cf"))
			draw_arc(c, g * 0.86, 0, TAU, 28, col, 1.5 * s, true)
			draw_line(c + Vector2(-0.6, -0.6) * g, c + Vector2(0.6, 0.6) * g, col, 1.5 * s, true)

func _unit_pts(c: Vector2, r: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + Vector2(p[0], p[1]) * r)
	return out

func _panel_lines(cd: Dictionary) -> Array:
	var kws: Array = _keywords(cd).duplicate()
	if inst.has("shield"):
		kws.erase("escudo")
		if inst["shield"]:
			kws.push_front("escudo")
	var out := []
	if cd["type"] != "unit":
		# spells never get here: they print their rules text and carry the speed badge instead
		var kind := "ARTEFATO"
		if CardDB.is_equipment(cd):
			kind += " · EQUIPAMENTO"
		var spd: String = {"rapido": " · RÁPIDO", "instantaneo": " · INSTANTÂNEO"}.get(cd.get("speed", "lento"), "")
		out.append([[kind + spd, Color("#ffd27a") if spd != "" else Color(UITheme.TEXT, 0.6)]])
	# tags: keywords first, then trigger names (full text lives in the overlay)
	var tags: Array = []
	if inst.has("frozen"):
		tags.append(["Congelada", FROST])
	if inst.get("spell_shield", false):
		tags.append([CardDB.keyword("escudo_feitico")["name"], Color("#c9a8ff")])
	for kw in kws:
		tags.append([CardDB.keyword(kw)["name"], Color("#9fe3ff") if kw == "escudo" else Color("#ffe7a0")])
	var seen := {}
	for e in cd.get("effects", []):
		var trg: String = e.get("trigger", "")
		if trg == "" or trg == "on_play" or seen.has(trg):
			continue
		seen[trg] = true
		tags.append([CardDB.data()["triggers"][trg]["name"], TRIGGER_COL])
	if cd.has("activated"):
		tags.append([CardDB.data()["triggers"]["on_activate"]["name"], TRIGGER_COL])
	if cd.has("transform"):
		tags.append([CardDB.data()["triggers"]["transform"]["name"], TRIGGER_COL])
	if tags.size() <= 2 and out.is_empty():
		for tg in tags:
			out.append([tg])
	elif tags.size() > 0:
		var half := (tags.size() + 1) / 2
		out.append(tags.slice(0, half))
		if tags.size() > half:
			out.append(tags.slice(half))
	if out.is_empty():
		var rar := {"legendary": "LENDÁRIO", "champion": "CAMPEÃO", "epic": "UNIDADE ÉPICA", "common": "UNIDADE COMUM"}
		out.append([[rar.get(cd["rarity"], ""), Color(UITheme.TEXT, 0.45)]])
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
	var kind: String = String(CardDB.essences_of(cd)[0]) if cd["type"] == "unit" else ("equipment" if CardDB.is_equipment(cd) else cd["type"])
	if kind == "obscura":
		_skull(c, 26 * s)
		var fo := UITheme.font("title_bold")
		_text(fo, String(cd["name"]).substr(0, 1), Vector2(art.end.x - 12 * s, art.end.y - 6 * s), 13 * s, Color(1, 1, 1, 0.35))
		return
	var pts := _sigil(kind, c, 26 * s)
	draw_colored_polygon(_grow(pts, c, 1.12), Color(0, 0, 0, 0.35))
	draw_colored_polygon(pts, col.lightened(0.55))
	draw_colored_polygon(_grow(pts, c + Vector2(0, 6 * s), 0.55), Color(1, 1, 1, 0.45))
	var f := UITheme.font("title_bold")
	var initial := String(cd["name"]).substr(0, 1)
	_text(f, initial, Vector2(art.end.x - 12 * s, art.end.y - 6 * s), 13 * s, Color(1, 1, 1, 0.35))

## Obscura sigil: a dark-grey skull (cranium, jaw, black sockets and nose).
func _skull(c: Vector2, r: float) -> void:
	var bone := Color("#55555e")
	var shade := Color("#3a3a42")
	draw_circle(c + Vector2(0, -r * 0.2), r * 0.66, Color(0, 0, 0, 0.4))
	draw_circle(c + Vector2(0, -r * 0.22), r * 0.62, bone)
	draw_rect(Rect2(c + Vector2(-r * 0.34, r * 0.18), Vector2(r * 0.68, r * 0.52)), bone)
	draw_rect(Rect2(c + Vector2(-r * 0.34, r * 0.18), Vector2(r * 0.12, r * 0.52)), shade)
	for i in 3: # teeth gaps
		var tx := c.x - r * 0.12 + i * r * 0.12
		draw_line(Vector2(tx, c.y + r * 0.46), Vector2(tx, c.y + r * 0.7), shade, maxf(r * 0.05, 1.0))
	for sx in [-1.0, 1.0]:
		draw_circle(c + Vector2(sx * r * 0.27, -r * 0.14), r * 0.19, Color("#050506"))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, r * 0.02), c + Vector2(-r * 0.08, r * 0.2), c + Vector2(r * 0.08, r * 0.2)]), Color("#050506"))

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
		"glacial": # six-point snow crystal
			var out := PackedVector2Array()
			for i in 12:
				var a := i * TAU / 12 - PI / 2
				out.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if i % 2 == 0 else 0.42))
			return out
		"spell":
			var out := PackedVector2Array()
			for i in 16:
				var a := i * TAU / 16 - PI / 2
				out.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if i % 2 == 0 else 0.38))
			return out
		"eletrica": # lightning bolt
			n = [[0.2, -1], [-0.55, 0.12], [-0.05, 0.12], [-0.25, 1], [0.6, -0.2], [0.08, -0.2], [0.5, -1]]
		"vegetal": # leaf
			n = [[0, -1], [0.55, -0.45], [0.7, 0.15], [0.3, 0.7], [0.04, 0.58], [0.04, 1], [-0.04, 1], [-0.04, 0.58], [-0.3, 0.7], [-0.7, 0.15], [-0.55, -0.45]]
		"rochosa": # faceted boulder
			n = [[-0.3, -0.85], [0.35, -0.9], [0.9, -0.2], [0.75, 0.6], [0.1, 0.9], [-0.7, 0.65], [-0.95, -0.15]]
		"metalica": # hex nut
			n = [[0, -1], [0.87, -0.5], [0.87, 0.5], [0, 1], [-0.87, 0.5], [-0.87, -0.5]]
		"sagrada": # four-point radiant star
			n = [[0, -1], [0.18, -0.38], [0.7, -0.7], [0.38, -0.18], [1, 0], [0.38, 0.18], [0.7, 0.7], [0.18, 0.38], [0, 1], [-0.18, 0.38], [-0.7, 0.7], [-0.38, 0.18], [-1, 0], [-0.38, -0.18], [-0.7, -0.7], [-0.18, -0.38]]
		"equipment":
			n = [[0, -1], [0.14, -0.82], [0.14, 0.3], [0.5, 0.3], [0.5, 0.44], [0.1, 0.44], [0.1, 0.9], [-0.1, 0.9], [-0.1, 0.44], [-0.5, 0.44], [-0.5, 0.3], [-0.14, 0.3], [-0.14, -0.82]]
		_:
			n = [[0, -1], [0.22, -0.22], [1, 0], [0.22, 0.22], [0, 1], [-0.22, 0.22], [-1, 0], [-0.22, -0.22]]
	var pts := PackedVector2Array()
	for p in n:
		pts.append(c + Vector2(p[0], p[1]) * r)
	return pts

## Essence badge in the top-right corner, mirroring the cost orb: metal bezel,
## body in the essence colour (split on a diagonal for dual essences) and the
## essence sigil. It names the essence even on cards that have a portrait.
func _essence_badge(c: Vector2, r: float, cd: Dictionary, s: float) -> void:
	var ess: Array = CardDB.essences_of(cd).slice(0, 2)
	var disc := _shape("circle", c, r)
	var shadow := _grow(disc, c, 1.18)
	for i in shadow.size():
		shadow[i] += Vector2(0, 2 * s)
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.55))
	draw_colored_polygon(_grow(disc, c, 1.16), UITheme.GOLD_DARK.darkened(0.3))
	draw_colored_polygon(_grow(disc, c, 1.1), UITheme.GOLD)
	var halves: Array = [PackedVector2Array()]
	if ess.size() > 1:
		halves = [
			PackedVector2Array([c + Vector2(-2, -2) * r, c + Vector2(0.7, -2) * r, c + Vector2(-0.7, 2) * r, c + Vector2(-2, 2) * r]),
			PackedVector2Array([c + Vector2(0.7, -2) * r, c + Vector2(2, -2) * r, c + Vector2(2, 2) * r, c + Vector2(-0.7, 2) * r])]
	for k in ess.size():
		var kind: String = ess[k]
		var col := Color("#232328") if kind == "obscura" else Color(CardDB.essence(kind)["color"])
		_fill_clipped(disc, halves[k], col.darkened(0.35))
		_fill_clipped(_grow(disc, c - Vector2(0, r * 0.1), 0.86), halves[k], col)
		_fill_clipped(_grow(disc, c - Vector2(0, r * 0.5), 0.5), halves[k], Color(col.lightened(0.5), 0.35))
		var sc := c if ess.size() == 1 else c + Vector2(-0.38 if k == 0 else 0.38, 0) * r
		var sr := r * (0.62 if ess.size() == 1 else 0.4)
		if kind == "obscura":
			_skull(sc, sr * 1.15)
		else:
			var pts := _sigil(kind, sc, sr)
			draw_colored_polygon(_grow(pts, sc, 1.15), Color(0, 0, 0, 0.4))
			draw_colored_polygon(pts, col.lightened(0.6))
	if ess.size() > 1:
		draw_line(c + Vector2(0.35, -1) * r, c + Vector2(-0.35, 1) * r, Color(UITheme.GOLD_LIGHT, 0.8), 1.0 * s, true)
	var rim := _grow(disc, c, 1.1)
	draw_polyline(rim + PackedVector2Array([rim[0]]), Color(UITheme.GOLD_LIGHT, 0.7), 0.9 * s, true)

func _fill_clipped(poly: PackedVector2Array, clip: PackedVector2Array, col: Color) -> void:
	if clip.is_empty():
		draw_colored_polygon(poly, col)
		return
	for piece in Geometry2D.intersect_polygons(poly, clip):
		draw_colored_polygon(piece, col)

## Rarity gem on the bottom edge: white (common), amethyst (epic), orange
## (champion / legendary).
func _rarity_gem(c: Vector2, r: float, rarity: String, trim: Color) -> void:
	var col := Color("#f2f2f2")
	if rarity == "epic":
		col = Color("#9b4fd6")
	elif rarity == "champion" or rarity == "legendary":
		col = Color("#ff8a1c")
	var pts := PackedVector2Array()
	for p in [[0, -1.0], [0.85, -0.3], [0.85, 0.3], [0, 1.0], [-0.85, 0.3], [-0.85, -0.3]]:
		pts.append(c + Vector2(p[0], p[1]) * r)
	draw_colored_polygon(_grow(pts, c, 1.3), Color("#07060a"))
	draw_colored_polygon(pts, col.darkened(0.4))
	# facets
	draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c, pts[5]]), col.lightened(0.25))
	draw_colored_polygon(PackedVector2Array([pts[1], pts[2], pts[3], c]), col)
	draw_colored_polygon(PackedVector2Array([pts[5], c, pts[3], pts[4]]), col.darkened(0.2))
	draw_polyline(pts + PackedVector2Array([pts[0]]), trim, 1.0, true)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.4), r * 0.16, Color(1, 1, 1, 0.8))

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

## Dual-essence frame: the body is cut on a diagonal, each half with its own
## essence gradient, joined by a thin light seam.
func _rrect_grad_split(r: Rect2, rad: float, a: Dictionary, b: Dictionary, s: float) -> void:
	var pts := _rrect_pts(r, rad)
	var x0 := r.position.x + r.size.x * 0.62
	var x1 := r.position.x + r.size.x * 0.38
	var big := 10.0 * r.size.x
	var left := PackedVector2Array([Vector2(r.position.x - big, r.position.y - 2), Vector2(x0, r.position.y - 2),
		Vector2(x1, r.end.y + 2), Vector2(r.position.x - big, r.end.y + 2)])
	var right := PackedVector2Array([Vector2(x0, r.position.y - 2), Vector2(r.end.x + big, r.position.y - 2),
		Vector2(r.end.x + big, r.end.y + 2), Vector2(x1, r.end.y + 2)])
	for half in [[left, a], [right, b]]:
		var top := Color(half[1]["top"])
		var bot := Color(half[1]["bot"])
		for poly in Geometry2D.intersect_polygons(pts, half[0]):
			var cols := PackedColorArray()
			for p in poly:
				cols.append(top.lerp(bot, clamp((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
			draw_polygon(poly, cols)
	draw_line(Vector2(x0, r.position.y + 1.5 * s), Vector2(x1, r.end.y - 1.5 * s), Color(1, 1, 1, 0.35), 1.2 * s, true)

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

## One panel line made of [text, color] segments joined by " · ", centered and shrunk to fit.
func _text_segments(font: Font, segs: Array, center: Vector2, fs: float, max_w: float) -> void:
	var sep := " · "
	fs = _fit(font, sep.join(segs.map(func(g): return g[0])), fs, max_w)
	var x := center.x - font.get_string_size(sep.join(segs.map(func(g): return g[0])), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x / 2
	var ol: int = max(2, int(fs / 5))
	for i in segs.size():
		var parts := [[sep, Color(UITheme.TEXT, 0.5)]] if i > 0 else []
		parts.append(segs[i])
		for g in parts:
			var p := Vector2(x, center.y)
			draw_string_outline(font, p, g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), ol, Color(0, 0, 0, 0.85))
			draw_string(font, p, g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), g[1])
			x += font.get_string_size(g[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x

## Greedy word wrap of `t` at font size `fs` (pixels) into lines no wider than `max_w`.
func _wrap_words(font: Font, t: String, fs: int, max_w: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var cur := ""
	for w in t.split(" ", false):
		var trial: String = w if cur == "" else cur + " " + w
		if cur != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w:
			lines.append(cur)
			cur = w
		else:
			cur = trial
	if cur != "":
		lines.append(cur)
	return lines

## Rules text wrapped and centered inside `box`, at the largest size (max_fs down to min_fs) that fits.
func _wrapped_text(font: Font, t: String, box: Rect2, max_fs: float, min_fs: float, col: Color) -> void:
	var fs := int(max_fs)
	var lines := _wrap_words(font, t, fs, box.size.x)
	while fs > int(min_fs):
		var widest := 0.0
		for ln in lines:
			widest = max(widest, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if lines.size() * fs * 1.12 <= box.size.y and widest <= box.size.x:
			break
		fs -= 1
		lines = _wrap_words(font, t, fs, box.size.x)
	var lh := fs * 1.12
	var y := box.get_center().y - (lines.size() - 1) * lh / 2.0 + fs * 0.34
	for ln in lines:
		_text(font, ln, Vector2(box.get_center().x, y), fs, col)
		y += lh

## Spell speed seal on the top edge of the art, between the cost orb and the essence badge:
## steel hourglass (lento), gold bolt (rápido) or cyan double bolt (instantâneo).
func _speed_badge(c: Vector2, speed: String, s: float) -> void:
	var info: Array = {
		"lento": ["LENTO", Color("#a9b6c8")],
		"rapido": ["RÁPIDO", Color("#ffd27a")],
		"instantaneo": ["INSTANTÂNEO", Color("#7fe8ff")],
	}.get(speed, ["LENTO", Color("#a9b6c8")])
	var label: String = info[0]
	var col: Color = info[1]
	var f := UITheme.font("heavy")
	var icon_w := (11.0 if speed == "instantaneo" else 7.0) * s
	var pad := 4.0 * s
	var gap := 2.5 * s
	var fs := _fit(f, label, 7.5 * s, 62 * s - 2 * pad - icon_w - gap)
	var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	var w := 2 * pad + icon_w + gap + tw
	var pill := Rect2(c - Vector2(w / 2, 6.2 * s), Vector2(w, 12.4 * s))
	_rrect_fill(Rect2(pill.position + Vector2(0, 1.4 * s), pill.size), 6 * s, Color(0, 0, 0, 0.45))
	_rrect_fill(pill, 6 * s, Color("#0d0b12", 0.9))
	_rrect_line(pill, 6 * s, Color(col, 0.95), 1.1 * s)
	var ic := Vector2(pill.position.x + pad + icon_w / 2, c.y)
	var u := 4.6 * s # half-height of the icon
	match speed:
		"rapido":
			draw_colored_polygon(_unit_pts(ic, u, [[0.3, -1], [-0.6, 0.15], [-0.05, 0.15], [-0.3, 1], [0.6, -0.2], [0.05, -0.2]]), col)
		"instantaneo":
			for dx in [-0.5, 0.5]:
				draw_colored_polygon(_unit_pts(ic + Vector2(dx * 4.2 * s, 0), u, [[0.3, -1], [-0.6, 0.15], [-0.05, 0.15], [-0.3, 1], [0.6, -0.2], [0.05, -0.2]]), col)
		_:
			draw_colored_polygon(_unit_pts(ic, u, [[-0.65, -1], [0.65, -1], [0, 0]]), Color(col, 0.55))
			draw_colored_polygon(_unit_pts(ic, u, [[0, 0], [0.65, 1], [-0.65, 1]]), col)
			draw_line(ic + Vector2(-0.8, -1) * u, ic + Vector2(0.8, -1) * u, col, 1.0 * s)
			draw_line(ic + Vector2(-0.8, 1) * u, ic + Vector2(0.8, 1) * u, col, 1.0 * s)
	_text(f, label, Vector2(pill.position.x + pad + icon_w + gap + tw / 2, c.y + fs * 0.36), fs, col.lightened(0.25))

func _text(font: Font, t: String, center: Vector2, fs: float, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	draw_string_outline(font, Vector2(center.x - w / 2, center.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), max(2, int(fs / 5)), Color(0, 0, 0, 0.85))
	draw_string(font, Vector2(center.x - w / 2, center.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), col)
