class_name TableView
extends Control
## Static table furniture drawn over the shader background: the two battle
## lanes, the central divider with its emblem and the command-zone sockets.

static var ENEMY_LANE := Rect2(428, 150, 910, 240)
static var MY_LANE := Rect2(428, 424, 910, 250)
const DIVIDER_Y := 407.0

var enemy_color := Color.WHITE
var my_color := Color.WHITE
var sockets: Array = [] ## Rect2 of command-zone slots

## Lanes span from the command column to `right_edge` (the stage is wider on wide windows).
static func layout(right_edge: float) -> void:
	var w := right_edge - 428.0
	ENEMY_LANE = Rect2(428, 150, w, 240)
	MY_LANE = Rect2(428, 424, w, 250)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _draw() -> void:
	_lane(ENEMY_LANE, enemy_color)
	_lane(MY_LANE, my_color)
	# divider: tapered gold line with a central emblem
	var cx := ENEMY_LANE.get_center().x
	var half := ENEMY_LANE.size.x / 2.0
	for i in 24:
		var k := float(i) / 24.0
		var a := (1.0 - k) * 0.5
		var x0 := cx - half * (k + 1.0 / 24.0)
		var x1 := cx - half * k
		draw_line(Vector2(x0, DIVIDER_Y), Vector2(x1, DIVIDER_Y), Color(UITheme.GOLD, a), 1.5)
		draw_line(Vector2(2 * cx - x0, DIVIDER_Y), Vector2(2 * cx - x1, DIVIDER_Y), Color(UITheme.GOLD, a), 1.5)
	var c := Vector2(cx, DIVIDER_Y)
	draw_circle(c, 15, Color("#0d0b12"))
	draw_arc(c, 15, 0, TAU, 40, Color(UITheme.GOLD, 0.8), 1.5, true)
	var d := PackedVector2Array([c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)])
	draw_colored_polygon(d, Color(UITheme.GOLD, 0.85))
	draw_colored_polygon(PackedVector2Array([d[0], d[1], c, d[3]]), Color(UITheme.GOLD_LIGHT, 0.6))
	for r in sockets:
		_socket(r)

func _lane(r: Rect2, col: Color) -> void:
	var sb := UITheme.box(Color(0, 0, 0, 0.28), 16, Color(col, 0.22), 1)
	draw_style_box(sb, r)
	# inner glow line and corner flourishes
	draw_style_box(UITheme.box(Color.TRANSPARENT, 12, Color(1, 1, 1, 0.035), 1), r.grow(-5))
	var L := 22.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x < r.get_center().x else -1.0
		var sy := 1.0 if corner.y < r.get_center().y else -1.0
		var p: Vector2 = corner + Vector2(sx * 7, sy * 7)
		draw_polyline(PackedVector2Array([p + Vector2(0, sy * L), p, p + Vector2(sx * L, 0)]), Color(UITheme.GOLD, 0.55), 1.5, true)
		_pip(p, Color(UITheme.GOLD, 0.8))

func _socket(r: Rect2) -> void:
	draw_style_box(UITheme.box(Color(0, 0, 0, 0.4), 10, Color(UITheme.GOLD, 0.35), 1), r)
	draw_style_box(UITheme.box(Color.TRANSPARENT, 8, Color(UITheme.GOLD, 0.12), 1), r.grow(-4))

func _pip(c: Vector2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -3), c + Vector2(3, 0), c + Vector2(0, 3), c + Vector2(-3, 0)]), col)
