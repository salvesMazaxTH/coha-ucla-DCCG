class_name LeaderView
extends Control
## Leader plate: a card-like frame in the Leader's essence colors with the art
## in a window, a name banner, the HP gem hanging off the bottom-right corner,
## the ability gem (clickable) beside it, the deck as a physical pile of
## card backs and the graveyard counter.
## The control is wider than the plate: the margins hold the ability gem (left)
## and the deck pile + graveyard counter (right), and `_has_point` keeps them from eating clicks
## meant for the hand or the board around it.

signal portrait_clicked
signal ability_clicked
signal grave_clicked

const PLATE := Rect2(52, 0, 140, 128) ## the card itself, in local coordinates
const SIZE := Vector2(258, 146) ## plate + side margins + the HP gem hanging below
const CX := 122.0 ## x of the plate's center: place the control at (center - CX)
const PC := Vector2(122, 50) ## art center, anchor for hit effects and flying text
const AC := Vector2(26, 50) ## ability gem center
const AR := 23.0
const READY_GLOW := Color("#4dff88") ## same as Main.OK, the playable-card glow
const GRAVE_RECT := Rect2(Vector2(203, 94), Vector2(55, 38)) ## graveyard counter + touch padding
const GRAVE_CENTER := Vector2(230, 113) ## where cards leave the graveyard from (Réquiem)
const DECK_CARD_SCALE := 0.42 ## size of each card in the deck pile
const DECK_BASE_TOP_LEFT := Vector2(206, 17) ## bottom card of the pile (the "table"); the pile grows upward from it
## Pile thickness in pixels (one pixel = one visible card edge) by deck size:
## [minimum cards, thickness]. The pile drops to the next step as the deck runs low.
const DECK_THICKNESS_CHECKPOINTS := [[26, 14], [18, 11], [10, 8], [4, 5], [1, 2]]
const HP_C := Vector2(180, 118) ## HP gem center
const RAD := 10.0
const ART := Rect2(58, 7, 128, 84)
const BANNER := Rect2(58, 96, 128, 24)

var leader_id := ""
var hp := 0
var hp_max := 0
var deck := 0
var fatigue := 0 ## damage of the next draw with the deck empty, shown in place of the 0
var grave := 0
var poison := 0 ## Veneno markers on this Leader (permanent; 12 kills it), drawn as a green badge on the art
var requiem := 0 ## Réquiem spells castable from the graveyard right now (glow + badge on the counter)
var ability_ready := false
var ability_cost := 0
var passive := false # passive ability: fires on its own trigger, no cost, not clickable
var targetable := false
var target_selected := false ## already chosen as the first target of a multi-target effect
var active := false ## whose turn it is
var elem_color := Color.WHITE
var _style: Dictionary
var _tex: Texture2D
var _hover_ability := false
var _hover_grave := false
var _t := 0.0
var _holding := false
var _long := false
var _press_id := 0
var _deck_pile: DeckPile

func setup(id: String) -> LeaderView:
	leader_id = id
	var ld := CardDB.leader(id)
	var ess: String = ld["essences"][0]
	elem_color = Color(CardDB.essence(ess)["color"])
	_style = CardView.STYLES.get(ess, CardView.STYLES["neutra"])
	_tex = CardView.texture(ld["art"])
	ability_cost = int(ld["ability"]["cost"])
	passive = bool(ld["ability"].get("passive", false))
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func():
		if _hover_grave:
			_hover_grave = false
			queue_redraw())
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
	_deck_pile = DeckPile.new()
	_deck_pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_deck_pile)
	return self

## Center of the pile's top card, in this control's coordinates: drawn cards fly out from here.
static func deck_top_center(count: int) -> Vector2:
	return deck_top_left(count) + CardView.BASE * DECK_CARD_SCALE / 2.0

## Top-left of the pile's top card: the higher the pile, the higher the top card.
static func deck_top_left(count: int) -> Vector2:
	return DECK_BASE_TOP_LEFT - Vector2(0, deck_thickness(count))

## Width of one card in the pile (a drawn card starts the flight at this size).
static func deck_card_width() -> float:
	return CardView.BASE.x * DECK_CARD_SCALE

## How thick (in pixels) the pile is for a deck of `count` cards.
static func deck_thickness(count: int) -> int:
	for checkpoint in DECK_THICKNESS_CHECKPOINTS:
		if count >= checkpoint[0]:
			return checkpoint[1]
	return 0

## Only the plate, the HP gem, the ability gem and the graveyard counter take input.
func _has_point(pt: Vector2) -> bool:
	return PLATE.has_point(pt) or GRAVE_RECT.has_point(pt) or pt.distance_to(AC) <= AR + 4 or pt.distance_to(HP_C) <= 22

func _process(delta: float) -> void:
	if targetable or target_selected or ability_ready or active or requiem > 0:
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
		else:
			portrait_clicked.emit()
		accept_event()

func _draw() -> void:
	var f_title := UITheme.font("title_bold")
	var f_num := UITheme.font("heavy")
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var ld := CardDB.leader(leader_id)
	var trim := CardView.GOLD_TRIM
	var P := PLATE

	# drop shadow, turn glow and target glow around the plate
	for i in 5:
		var g := P.grow(i * 2.2 + 1)
		g.position.y += 4
		_rrect_fill(g, RAD + i * 2, Color(0, 0, 0, 0.11))
	if active:
		for i in 6:
			_rrect_line(P.grow(3 + i * 3), RAD + i * 3, Color(UITheme.GOLD, 0.16 * (1.0 - i / 6.0) * (0.6 + 0.4 * pulse)), 3.2)
	if targetable and not target_selected:
		for i in 7:
			_rrect_line(P.grow(3 + i * 3), RAD + i * 3, Color(1, 0.25, 0.2, 0.28 * (1.0 - i / 7.0) * (0.5 + 0.5 * pulse)), 3.2)
	elif target_selected:
		for i in 7:
			_rrect_line(P.grow(3 + i * 3), RAD + i * 3, Color(UITheme.GOLD, 0.28 * (1.0 - i / 7.0) * (0.5 + 0.5 * pulse)), 3.2)

	# frame: essence gradient body, dark outer edge, gold trim with a top highlight
	_rrect_grad(P, RAD, Color(_style["top"]), Color(_style["bot"]))
	_rrect_line(P.grow(-0.5), RAD, Color("#07060a"), 1.6)
	_rrect_line(P.grow(-2.6), RAD - 2, Color(trim, 0.85), 1.1)
	draw_line(Vector2(P.position.x + RAD, 1.6), Vector2(P.end.x - RAD, 1.6), Color(1, 1, 1, 0.3), 1.0)

	# art window
	draw_rect(ART.grow(1.5), Color("#07060a"))
	if _tex:
		var ts := _tex.get_size()
		var k: float = max(ART.size.x / ts.x, ART.size.y / ts.y)
		var src := ART.size / k
		# the face sits near the top of the (tall) portrait
		draw_texture_rect_region(_tex, ART, Rect2(Vector2((ts.x - src.x) / 2, clampf(ts.y * 0.02, 0.0, ts.y - src.y)), src))
	else:
		draw_rect(ART, elem_color.darkened(0.6))
	_vgrad(Rect2(ART.position, Vector2(ART.size.x, 12)), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0))
	_vgrad(Rect2(ART.position + Vector2(0, ART.size.y - 20), Vector2(ART.size.x, 20)), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55))
	draw_rect(ART.grow(0.5), Color(trim, 0.9), false, 1.2)
	for c in [ART.position, Vector2(ART.end.x, ART.position.y)]:
		_diamond(c, 5, trim, UITheme.GOLD_LIGHT)
	if targetable and not target_selected:
		_rrect_line(P.grow(1), RAD, Color(1, 0.35, 0.3, 0.6 + 0.4 * pulse), 3)
	elif target_selected:
		_rrect_line(P.grow(1), RAD, Color(UITheme.GOLD_LIGHT, 0.75 + 0.25 * pulse), 3)

	# name banner, kept clear of the HP gem on its right
	_rrect_fill(BANNER, 5, Color("#16131c"))
	_rrect_line(BANNER, 5, Color(UITheme.GOLD, 0.7), 1.5)
	var nm := String(ld["name"]).to_upper()
	var fs := 17
	while fs > 9 and f_title.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 100:
		fs -= 1
	_text(f_title, nm, Vector2(BANNER.position.x + 50, BANNER.position.y + 18), fs, UITheme.GOLD_LIGHT)

	# HP gem (shield shape) hanging off the bottom-right corner
	var hc := HP_C
	var low := hp <= 8
	var sh := PackedVector2Array([hc + Vector2(-20, -20), hc + Vector2(20, -20), hc + Vector2(20, 2), hc + Vector2(0, 24), hc + Vector2(-20, 2)])
	draw_colored_polygon(_grow(sh, hc, 1.18), Color(0, 0, 0, 0.6))
	draw_colored_polygon(sh, UITheme.HP.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([sh[0], sh[1], hc + Vector2(16, -6), hc + Vector2(-16, -6)]), Color(1, 1, 1, 0.12))
	draw_polyline(sh + PackedVector2Array([sh[0]]), UITheme.GOLD if not low else Color(1, 0.5, 0.4, 0.6 + 0.4 * pulse), 2, true)
	_text(f_num, str(hp), hc + Vector2(0, 9), 26, Color.WHITE)

	# Veneno markers: green badge on the top-right corner of the art
	if poison > 0:
		var badge_center := Vector2(ART.end.x - 14, ART.position.y + 14)
		var danger := poison >= GameState.LEADER_POISON_LETHAL - 3
		draw_circle(badge_center, 13, Color(0, 0, 0, 0.6))
		draw_circle(badge_center, 11, Color("#3f6b1c"))
		draw_arc(badge_center, 11, 0, TAU, 24, Color(1, 0.5, 0.4, 0.6 + 0.4 * pulse) if danger else Color("#b8e86b"), 2, true)
		_text(f_num, str(poison), badge_center + Vector2(0, 6), 16, Color.WHITE)

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
	_text(f_title, String(ld["ability"]["name"]).substr(0, 1), AC + Vector2(0, 8), 22, Color.WHITE if usable else Color(1, 1, 1, 0.35))
	# its cost, a small Momentum gem
	if not passive:
		var cc := AC + Vector2(AR * 0.75, -AR * 0.75)
		_diamond(cc, 11, UITheme.MOMENTUM.darkened(0.2) if usable else Color(0.3, 0.3, 0.35), Color(1, 1, 1, 0.8))
		_text(f_num, str(ability_cost), cc + Vector2(0, 5), 14, Color.WHITE)
	_text(UITheme.font("bold"), "PASSIVA" if passive else "HABILIDADE", AC + Vector2(0, AR + 16), 12, Color(UITheme.TEXT, 0.7))

	# deck pile (its own child node, rebuilt here) and graveyard counter
	_deck_pile.show_count(deck, fatigue)
	_counter(Vector2(230, 98), true, grave, true)

## Small plate with a drawn icon (tombstone) and a count.
func _counter(pos: Vector2, tomb: bool, n: int, clickable := false) -> void:
	var r := Rect2(pos - Vector2(25, 0), Vector2(50, 30))
	var hot := clickable and _hover_grave
	var glowing := tomb and requiem > 0
	if glowing:
		# same "playable" green as the hand cards: a Réquiem spell can be cast from in here
		var glow_pulse := 0.5 + 0.5 * sin(_t * 4.0)
		for i in 4:
			draw_style_box(UITheme.box(Color(0, 0, 0, 0), 5 + i * 2, Color(READY_GLOW, (0.85 - i * 0.2) * (0.65 + 0.35 * glow_pulse)), 2), r.grow(1.0 + i * 2.0))
	var rim := Color(UITheme.GOLD, 0.9 if hot else (0.5 if clickable else 0.25))
	draw_style_box(UITheme.box(Color(UITheme.GOLD_DARK, 0.35) if hot else Color(0, 0, 0, 0.45), 5, rim, 2 if clickable else 1), r)
	var ic := r.position + Vector2(10, 15)
	var ink := Color(UITheme.GOLD_LIGHT, 0.95) if hot else Color(UITheme.TEXT, 0.75)
	if tomb:
		_draw_tombstone_icon(ic, ink)
	var f := UITheme.font("heavy")
	var t := str(n)
	draw_string_outline(f, r.position + Vector2(20, 22), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.8))
	draw_string(f, r.position + Vector2(20, 22), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UITheme.TEXT)
	if glowing:
		# badge on the top-right corner: how many Réquiem spells are castable
		var badge := r.position + Vector2(r.size.x - 2, 2)
		draw_circle(badge, 11, Color(0, 0, 0, 0.85))
		draw_circle(badge, 9, READY_GLOW.darkened(0.35))
		draw_arc(badge, 9, 0, TAU, 24, READY_GLOW.lightened(0.3), 1.5, true)
		draw_string(f, badge + Vector2(-5, 6), str(requiem), HORIZONTAL_ALIGNMENT_LEFT, 10, 15, Color.WHITE)

# Graveyard icon: a rounded-top headstone with an engraved cross, sitting on a little mound of dirt.
# (Not a skull on purpose: the skull is already the Obscura element symbol.)
func _draw_tombstone_icon(center: Vector2, ink: Color) -> void:
	var stone_half_width := 5.5
	var arch_center := center + Vector2(0, -3)
	var stone_bottom := center.y + 6.0
	var stone_outline := PackedVector2Array()
	for step in 11:
		var angle := PI + PI * step / 10.0
		stone_outline.append(arch_center + Vector2(cos(angle), sin(angle)) * stone_half_width)
	stone_outline.append(Vector2(center.x + stone_half_width, stone_bottom))
	stone_outline.append(Vector2(center.x - stone_half_width, stone_bottom))
	draw_colored_polygon(stone_outline, ink)
	# engraved cross, cut into the stone with a dark color
	var engraving := Color(0, 0, 0, 0.7)
	draw_rect(Rect2(center + Vector2(-0.8, -5.5), Vector2(1.6, 7.5)), engraving)
	draw_rect(Rect2(center + Vector2(-2.8, -3.5), Vector2(5.6, 1.6)), engraving)
	# mound of dirt at the base, a bit wider than the stone
	var mound := PackedVector2Array()
	for step in 9:
		var angle := PI + PI * step / 8.0
		mound.append(Vector2(center.x, stone_bottom + 1.5) + Vector2(cos(angle) * 8.5, sin(angle) * 2.5))
	draw_colored_polygon(mound, ink.darkened(0.45))

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

func _rrect_pts(r: Rect2, rad: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [[Vector2(r.end.x - rad, r.position.y + rad), -PI / 2], [Vector2(r.end.x - rad, r.end.y - rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI / 2], [Vector2(r.position.x + rad, r.position.y + rad), PI]]
	for c in corners:
		for i in 7:
			var a: float = c[1] + (PI / 2) * i / 6.0
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
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
		cols.append(top.lerp(bot, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	draw_polygon(pts, cols)

func _vgrad(r: Rect2, top: Color, bot: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bot, bot]))

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
	elif ab.get("once_per_cycle", false):
		chips.add_child(_chip("1× ATÉ SEU PRÓXIMO TURNO", UITheme.TEXT))
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
	rt.text = CardView.colorize_rules(body, 21)
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

## The deck as a physical pile seen slightly from the front: a soft shadow on the
## table, the side of the stack with every card edge visible (it gets thinner at
## each checkpoint as the deck runs low), a slightly crooked card peeking out under
## the top one, the top card back and a round count badge at the front.
## Empty deck: a faint outline of where the pile was and the next Fadiga damage.
class DeckPile extends Control:
	const EDGE_DARK := Color("#1d1736")
	const EDGE_LIGHT := Color("#3a2f63")
	const CORNER := 4
	var _shown_count := -1
	var _shown_fatigue := -1

	func show_count(count: int, fatigue: int) -> void:
		if count == _shown_count and fatigue == _shown_fatigue:
			return
		_shown_count = count
		_shown_fatigue = fatigue
		for child in get_children():
			child.queue_free()
		var top_left := LeaderView.deck_top_left(count)
		if count >= 2:
			# a card a bit out of line under the top one, so the pile looks handled, not printed
			var crooked := _card_back(top_left + Vector2(2, 1), deg_to_rad(5.0))
			crooked.modulate = Color(0.7, 0.7, 0.75)
		if count >= 1:
			_card_back(top_left, deg_to_rad(-1.5))
		var badge := CountBadge.new()
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.count = count
		badge.fatigue = fatigue
		var card_size := CardView.BASE * LeaderView.DECK_CARD_SCALE
		badge.center = LeaderView.DECK_BASE_TOP_LEFT + Vector2(card_size.x / 2.0, card_size.y - 2)
		add_child(badge)
		queue_redraw()

	func _card_back(top_left: Vector2, tilt: float) -> CardView:
		var back := CardView.new().setup("", {}, LeaderView.DECK_CARD_SCALE)
		back.face_down = true
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.pivot_offset = back.size / 2.0
		back.position = top_left
		back.rotation = tilt
		add_child(back)
		return back

	func _draw() -> void:
		var card_size := CardView.BASE * LeaderView.DECK_CARD_SCALE
		var base := Rect2(LeaderView.DECK_BASE_TOP_LEFT, card_size)
		if _shown_count <= 0:
			draw_style_box(UITheme.box(Color(0, 0, 0, 0.35), CORNER, Color(UITheme.TEXT, 0.22), 1), base)
			return
		# soft shadow cast on the table, longer toward the bottom-right
		for i in 6:
			var shadow := base.grow(1.0 + i * 1.6)
			shadow.position += Vector2(2.5, 3.5)
			draw_style_box(UITheme.box(Color(0, 0, 0, 0.09), CORNER + i * 2, Color(0, 0, 0, 0), 0), shadow)
		# side of the stack: one rounded card per pixel of thickness, bottom first,
		# alternating tones with a tiny sideways jitter so the edges read as separate cards
		var thickness := LeaderView.deck_thickness(_shown_count)
		for layer in thickness:
			var jitter := sin(layer * 12.9898) * 0.9
			var card := Rect2(base.position + Vector2(jitter, -layer), card_size)
			var depth := 1.0 - float(layer) / maxf(1.0, thickness) # 1 at the bottom, near 0 at the top
			var tone := EDGE_LIGHT if layer % 2 == 0 else EDGE_DARK
			draw_style_box(UITheme.box(tone.darkened(0.35 * depth), CORNER, Color(0, 0, 0, 0), 0), card)
			if layer % 3 == 1:
				# thin gold line: the trim of the card backs, seen from the side
				var y := card.end.y - 0.5
				draw_line(Vector2(card.position.x + CORNER, y), Vector2(card.end.x - CORNER, y), Color(UITheme.GOLD, 0.35 - 0.2 * depth), 1.0)
		# light catching the front-bottom edge of the whole stack
		draw_line(Vector2(base.position.x + CORNER, base.end.y - 0.5), Vector2(base.end.x - CORNER, base.end.y - 0.5), Color(1, 1, 1, 0.12), 1.0)

	## Round count plate at the front of the pile: gold rim, dark face, the number
	## (or the next Fadiga damage in red when the deck is empty).
	class CountBadge extends Control:
		var count := 0
		var fatigue := 0
		var center := Vector2.ZERO

		func _draw() -> void:
			var radius := 13.0
			draw_circle(center + Vector2(0, 2), radius + 2, Color(0, 0, 0, 0.55))
			draw_circle(center, radius + 1.5, UITheme.GOLD_DARK)
			draw_circle(center, radius, Color("#120e22"))
			draw_arc(center, radius + 1, -PI * 0.95, -PI * 0.05, 16, Color(UITheme.GOLD_LIGHT, 0.8), 1.2, true)
			var text := str(count)
			var color := UITheme.TEXT
			var font_size := 15 if count < 100 else 12
			if count == 0 and fatigue > 0:
				text = "-%d" % fatigue
				color = Color(1.0, 0.45, 0.4)
				font_size = 13
			var font := UITheme.font("heavy")
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var at := center + Vector2(-width / 2.0, font_size * 0.36)
			draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0, 0, 0, 0.9))
			draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
