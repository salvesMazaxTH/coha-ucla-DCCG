class_name AimArrow
extends Control
## Targeting arrow: a curved chain of glowing dashes flowing from the source (card, leader
## gem) to the pointer, ending in an arrowhead; over a valid target it turns red with a
## reticle. Main updates `from`, `to` and `locked` every frame while aiming.

var from := Vector2.ZERO
var to := Vector2.ZERO
var locked := false ## pointer is over a valid target
var _t := 0.0

const IDLE := Color("#ffd23f")
const LOCK := Color("#ff5050")

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 60

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _point(t: float, ctrl: Vector2) -> Vector2:
	return from.lerp(ctrl, t).lerp(ctrl.lerp(to, t), t)

func _draw() -> void:
	var d := to - from
	var len := d.length()
	if len < 24.0:
		return
	var col := LOCK if locked else IDLE
	# control point bowed upward so the arc reads as a throw, not a ruler line
	var ctrl := (from + to) / 2.0 + Vector2(0, -minf(160.0, len * 0.35))
	var head := 26.0
	var step := 26.0
	var n := int(len / step)
	var flow := fmod(_t * 2.2, 1.0) # dashes stream toward the target
	for i in n:
		var a := (i + flow) / float(n)
		var b := minf(1.0, a + 0.45 / n)
		if a > 1.0 - head / len:
			break
		var p1 := _point(a, ctrl)
		var p2 := _point(b, ctrl)
		var w := lerpf(5.0, 9.0, a)
		draw_line(p1, p2, Color(0, 0, 0, 0.55), w + 5.0, true)
		draw_line(p1, p2, Color(col, 0.35), w + 6.0, true)
		draw_line(p1, p2, col, w, true)
		draw_line(p1, p2, Color(1, 1, 1, 0.7), maxf(1.5, w * 0.3), true)
	# arrowhead aligned with the curve's last tangent
	var tip := to
	var dir := (to - _point(0.94, ctrl)).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var base := tip - dir * head
	var pts := PackedVector2Array([tip, base + nrm * head * 0.62, base - dir * 4.0, base - nrm * head * 0.62])
	var outline := PackedVector2Array([tip + dir * 3.0, base + nrm * (head * 0.62 + 4.0), base - dir * 8.0, base - nrm * (head * 0.62 + 4.0)])
	draw_colored_polygon(outline, Color(0, 0, 0, 0.6))
	draw_colored_polygon(pts, col)
	if locked:
		var r := 34.0 + sin(_t * 8.0) * 3.0
		draw_arc(to, r, 0, TAU, 48, Color(col, 0.9), 3.0, true)
		draw_arc(to, r + 8.0, 0, TAU, 48, Color(col, 0.35), 2.0, true)
		for k in 4:
			var ang := k * PI / 2.0 + _t
			var v := Vector2.from_angle(ang)
			draw_line(to + v * (r - 10.0), to + v * (r + 12.0), col, 3.0, true)
