class_name ChronicleRow
extends Control
## Compact visual event row for the in-game Chronicle. A row keeps the prose short, but the
## source/target art thumbnails make the action legible at a glance.

const ROW_H := 54.0
const HOVER_H := 142.0
const SOURCE_RECT := Rect2(6, 8, 32, 38)
const TARGET_RECT := Rect2(0, 8, 32, 38)
const HOVER_SOURCE_RECT := Rect2(8, 22, 72, 96)
const HOVER_TARGET_RECT := Rect2(0, 22, 72, 96)

var entry: Dictionary = {}
var _hovered := false

func setup(data: Dictionary) -> ChronicleRow:
	entry = data.duplicate(true)
	custom_minimum_size = Vector2(0, ROW_H)
	size.y = ROW_H
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	queue_redraw()
	return self

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	_hovered = true
	custom_minimum_size.y = HOVER_H
	size.y = HOVER_H
	queue_redraw()

func _on_mouse_exited() -> void:
	_hovered = false
	custom_minimum_size.y = ROW_H
	size.y = ROW_H
	queue_redraw()

func _draw() -> void:
	if _hovered:
		_draw_hovered()
	else:
		_draw_compact()

func _draw_compact() -> void:
	var accent: Color = entry.get("accent", Color("#8d849c"))
	var rect := Rect2(0, 1, maxf(1.0, size.x - 2), ROW_H - 3)
	var bg := Color("#0d0b15")
	if entry.get("kind", "") == "start_turn":
		bg = Color("#171226")
	draw_rect(rect, bg)
	draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), accent)
	draw_line(Vector2(rect.position.x + 3, rect.end.y), Vector2(rect.end.x, rect.end.y), Color(accent, 0.32), 1.0)

	var source_id := String(entry.get("source_card_id", ""))
	var target_ids: Array = entry.get("target_card_ids", [])
	if source_id != "":
		_draw_thumb(source_id, SOURCE_RECT, accent)
	else:
		_draw_glyph(SOURCE_RECT, String(entry.get("icon", "·")), accent)

	if not target_ids.is_empty():
		var target_x := size.x - 38
		var target_rect := Rect2(target_x, TARGET_RECT.position.y, TARGET_RECT.size.x, TARGET_RECT.size.y)
		if target_ids.size() == 1:
			_draw_thumb(String(target_ids[0]), target_rect, accent)
		else:
			var shown := mini(2, target_ids.size())
			for i in shown:
				var small := Rect2(target_x + i * 10, 10 - i * 2, 24, 30)
				_draw_thumb(String(target_ids[i]), small, accent)
			if target_ids.size() > 2:
				_draw_count_pill(Vector2(target_x + 25, 41), "+%d" % (target_ids.size() - 2), accent)
		_draw_arrow(Vector2(42, 27), Vector2(target_x - 4, 27), accent)
	else:
		_draw_glyph(Rect2(size.x - 38, 8, 32, 38), String(entry.get("target_icon", "·")), Color(accent, 0.68))

	var text_rect := Rect2(43, 8, maxf(20.0, size.x - 84), 38)
	var font := UITheme.font("body")
	var fs := 12
	var text := _fit_text(String(entry.get("text", "")), font, fs, text_rect.size.x)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var ty := text_rect.position.y + 23
	draw_string_outline(font, Vector2(text_rect.position.x, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(text_rect.position.x, ty), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#eee8dc"))

func _draw_hovered() -> void:
	var accent: Color = entry.get("accent", Color("#8d849c"))
	var rect := Rect2(0, 1, maxf(1.0, size.x - 2), HOVER_H - 3)
	var bg := Color("#171326")
	draw_rect(rect, bg)
	draw_rect(Rect2(rect.position, Vector2(4, rect.size.y)), accent)
	draw_rect(rect, Color(accent, 0.82), false, 1.5)
	draw_line(Vector2(4, 20), Vector2(rect.end.x, 20), Color(accent, 0.24), 1.0)

	var source_id := String(entry.get("source_card_id", ""))
	var target_ids: Array = entry.get("target_card_ids", [])
	var label_font := UITheme.font("heavy")
	draw_string(label_font, Vector2(10, 15), "CENA", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(accent, 0.9))

	if source_id != "":
		_draw_thumb(source_id, HOVER_SOURCE_RECT, accent)
	else:
		_draw_glyph(HOVER_SOURCE_RECT, String(entry.get("icon", "·")), accent, 32)

	var target_x := size.x - 84
	if not target_ids.is_empty():
		if target_ids.size() == 1:
			_draw_thumb(String(target_ids[0]), Rect2(target_x, HOVER_TARGET_RECT.position.y, HOVER_TARGET_RECT.size.x, HOVER_TARGET_RECT.size.y), accent)
		else:
			var shown := mini(2, target_ids.size())
			for i in shown:
				var large_small := Rect2(target_x + i * 18, 28 - i * 8, 58, 78)
				_draw_thumb(String(target_ids[i]), large_small, accent)
			if target_ids.size() > 2:
				_draw_count_pill(Vector2(target_x + 60, 109), "+%d" % (target_ids.size() - 2), accent)
		_draw_arrow(Vector2(88, 70), Vector2(target_x - 10, 70), accent)
	else:
		_draw_glyph(Rect2(target_x, HOVER_TARGET_RECT.position.y, HOVER_TARGET_RECT.size.x, HOVER_TARGET_RECT.size.y), String(entry.get("target_icon", "·")), Color(accent, 0.68), 32)

	var text_x := 92.0
	var text_width := maxf(80.0, target_x - text_x - 12.0)
	var text_font := UITheme.font("body")
	var text := _fit_text(String(entry.get("text", "")), text_font, 15, text_width)
	var text_y := 76.0
	draw_string_outline(text_font, Vector2(text_x, text_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.95))
	draw_string(text_font, Vector2(text_x, text_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#fff7e9"))
	var hint := "Passe o cursor para recolher"
	draw_string(text_font, Vector2(text_x, 104), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(accent, 0.62))

func _draw_thumb(card_id: String, rect: Rect2, accent: Color) -> void:
	var tex: Texture2D = null
	if card_id != "" and CardDB.data().get("cards", {}).has(card_id):
		var art := String(CardDB.card(card_id).get("art", ""))
		if art != "":
			tex = CardView.texture(art)
	if tex != null:
		var ts := tex.get_size()
		var scale := maxf(rect.size.x / ts.x, rect.size.y / ts.y)
		var src := rect.size / scale
		var origin := Vector2((ts.x - src.x) / 2.0, (ts.y - src.y) / 2.0)
		draw_texture_rect_region(tex, rect, Rect2(origin, src))
	else:
		draw_rect(rect, Color(accent, 0.16))
	draw_rect(rect, Color(accent, 0.82), false, 1.0)

func _draw_glyph(rect: Rect2, glyph: String, accent: Color, font_size := 18) -> void:
	draw_rect(rect, Color(accent, 0.1))
	draw_rect(rect, Color(accent, 0.55), false, 1.0)
	var font := UITheme.font("heavy")
	var fs := font_size
	var w := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(rect.get_center().x - w / 2.0, rect.get_center().y + 6), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent)

func _draw_count_pill(center: Vector2, text: String, accent: Color) -> void:
	draw_circle(center, 9, Color("#090811"))
	draw_arc(center, 9, 0, TAU, 20, accent, 1.0, true)
	var font := UITheme.font("heavy")
	var fs := 9
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, center + Vector2(-w / 2.0, 3), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _draw_arrow(from: Vector2, to: Vector2, accent: Color) -> void:
	if to.x <= from.x:
		return
	draw_line(from, to, Color(accent, 0.32), 1.0)
	draw_colored_polygon(PackedVector2Array([to, to + Vector2(-5, -3), to + Vector2(-5, 3)]), Color(accent, 0.72))

func _fit_text(text: String, font: Font, fs: int, max_width: float) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= max_width:
		return text
	var clipped := text
	while clipped.length() > 2 and font.get_string_size(clipped + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_width:
		clipped = clipped.left(clipped.length() - 1)
	return clipped + "…"
