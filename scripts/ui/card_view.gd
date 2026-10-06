class_name CardView
extends Control
## A card drawn entirely in code: element-colored frame, cropped portrait
## (or placeholder), cost gem, Ataque/Vida gems, name banner, keyword tags.

signal left_clicked(view: CardView)
signal right_clicked(view: CardView)

const BASE := Vector2(120, 170)

var card_id := ""
var inst: Dictionary = {} ## creature on board (live stats) or hand instance
var uid := 0
var face_down := false
var highlight := Color.TRANSPARENT ## outline for selection/targets
var dim := false
var cost_override := -1

static var _tex_cache := {}

func setup(id: String, instance: Dictionary = {}, size_scale := 1.0) -> CardView:
	card_id = id
	inst = instance
	uid = instance.get("uid", 0)
	custom_minimum_size = BASE * size_scale
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			left_clicked.emit(self)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit(self)
		accept_event()

static func texture(file: String) -> Texture2D:
	if file == "":
		return null
	if not _tex_cache.has(file):
		var path := "res://assets/portraits/" + file
		_tex_cache[file] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[file]

func _draw() -> void:
	var s := size.x / BASE.x
	var font := ThemeDB.fallback_font
	var r := Rect2(Vector2.ZERO, size)
	if face_down:
		_round(r, Color("#2a2340"), 8 * s)
		_round(r.grow(-6 * s), Color("#3d3260"), 6 * s)
		_text(font, "CSA", r.get_center() + Vector2(0, 8 * s), 22 * s, Color("#bfa8ff"))
		return
	var cd := CardDB.card(card_id)
	var el := CardDB.element(cd["element"])
	var col := Color(el["color"])
	var frame := col.lightened(0.15) if cd["rarity"] != "legendary" else Color("#e8c25a")
	_round(r, frame, 9 * s)
	var inner := r.grow(-4 * s)
	_round(inner, Color("#15131c"), 7 * s)
	# art
	var art_rect := Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.72))
	var tex := texture(cd.get("art", ""))
	if tex:
		var ts := tex.get_size()
		var k: float = max(art_rect.size.x / ts.x, art_rect.size.y / ts.y)
		var src_size := art_rect.size / k
		var src := Rect2(Vector2((ts.x - src_size.x) / 2, 0), src_size)
		draw_texture_rect_region(tex, art_rect, src)
	else:
		draw_rect(art_rect, col.darkened(0.45))
		draw_rect(Rect2(art_rect.position, Vector2(art_rect.size.x, art_rect.size.y * 0.5)), col.darkened(0.25))
		var glyph := "✦" if cd["type"] == "spell" else ("⚔" if cd["type"] == "equipment" else String(cd["name"]).substr(0, 1))
		_text(font, glyph, art_rect.get_center() + Vector2(0, 14 * s), 40 * s, col.lightened(0.5))
	# name banner
	var banner := Rect2(Vector2(inner.position.x, art_rect.end.y), Vector2(inner.size.x, inner.size.y - art_rect.size.y))
	draw_rect(banner, col.darkened(0.55))
	_text(font, cd["name"], Vector2(banner.get_center().x, banner.position.y + 15 * s), _fit(font, cd["name"], 12 * s, banner.size.x - 8 * s), Color.WHITE)
	var type_txt: String = {"creature": "", "spell": "Feitiço", "equipment": "Equipamento"}[cd["type"]]
	if type_txt != "":
		_text(font, type_txt, Vector2(banner.get_center().x, banner.position.y + 30 * s), 9 * s, Color(1, 1, 1, 0.7))
	# keyword tags (board shows live keywords)
	var kws: Array = inst.get("keywords", cd.get("keywords", [])).duplicate()
	if inst.has("shield"):
		kws.erase("escudo")
		if inst["shield"]:
			kws.push_front("escudo")
	var y := art_rect.position.y + 4 * s
	for kw in kws:
		var kw_name: String = CardDB.keyword(kw)["name"]
		var fs := 8.5 * s
		var w := font.get_string_size(kw_name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x + 6 * s
		var tag := Rect2(Vector2(inner.end.x - w - 2 * s, y), Vector2(w, 12 * s))
		_round(tag, Color(0, 0, 0, 0.7), 3 * s)
		draw_string(font, tag.position + Vector2(3 * s, 9.5 * s), kw_name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), Color("#ffe9a8") if kw != "escudo" else Color("#9fe3ff"))
		y += 14 * s
	# cost
	var cost: int = cost_override if cost_override >= 0 else int(cd["cost"])
	_gem(font, Vector2(14, 14) * s, 13 * s, Color("#2f6fe0"), str(cost), Color.WHITE)
	if cd["type"] == "creature":
		var atk: int = int(cd["atk"])
		var hp: int = int(cd["hp"])
		var atk_col := Color.WHITE
		var hp_col := Color.WHITE
		if inst.has("damage"):
			var live_atk: int = max(0, inst["atk"] + inst["temp_atk"])
			atk_col = Color("#8dff8d") if live_atk > atk else Color.WHITE
			atk = live_atk
			var live_hp: int = inst["hp"] - inst["damage"]
			hp_col = Color("#ff7070") if inst["damage"] > 0 else (Color("#8dff8d") if inst["hp"] > hp else Color.WHITE)
			hp = live_hp
		_gem(font, Vector2(14 * s, art_rect.end.y - 4 * s), 12 * s, Color("#c0392b"), str(atk), atk_col)
		_gem(font, Vector2(size.x - 14 * s, art_rect.end.y - 4 * s), 12 * s, Color("#27ae60"), str(hp), hp_col)
	if dim:
		_round(r, Color(0, 0, 0, 0.45), 9 * s)
	if highlight.a > 0:
		draw_rect(r.grow(2), highlight, false, 3.0)

func _fit(font: Font, t: String, fs: float, max_w: float) -> float:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	return fs if w <= max_w else max(7.0, fs * max_w / w)

func _text(font: Font, t: String, center: Vector2, fs: float, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	draw_string_outline(font, Vector2(center.x - w / 2, center.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), max(2, int(fs / 5)), Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(center.x - w / 2, center.y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), col)

func _gem(font: Font, c: Vector2, rad: float, col: Color, t: String, tcol: Color) -> void:
	draw_circle(c, rad + 1.5, Color(0, 0, 0, 0.8))
	draw_circle(c, rad, col)
	_text(font, t, c + Vector2(0, rad * 0.45), rad * 1.3, tcol)

func _round(r: Rect2, col: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	draw_style_box(sb, r)
