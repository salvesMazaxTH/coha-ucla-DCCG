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
	"metalica": {"top": "#9db3d1", "bot": "#1a2840", "trim": "#eef4ff", "glow": "#bcd6ff"}, ## blue steel, bright chrome trim (Neutra is the warm dark grey)
	"eletrica": {"top": "#ffe81a", "bot": "#5a3d00", "trim": "#e6f7ff", "glow": "#6fe8ff"}, ## lemon yellow with a cold white trim and cyan spark, so it never reads as the warm legendary gold
	"obscura": {"top": "#34343a", "bot": "#030304", "trim": "#7c7c85", "glow": "#8a8a96"}, ## near-black gradient, dark-grey trim
	"sagrada": {"top": "#fffaee", "bot": "#b8a676", "trim": "#e6c25a", "glow": "#fff6c8"}, ## pearl white over champagne, gold trim: the only light frame (Elétrica and legendary are saturated gold)
	"neutra": {"top": "#7b7a78", "bot": "#1f1f20", "trim": "#b49b72", "glow": "#dcd8d0"}, ## colourless dark grey with a bronze trim
	# Reserved for a future Vento essence (keep this hue free): periwinkle lilac, the only violet frame
	# "vento": {"top": "#c4bdf2", "bot": "#37336a", "trim": "#f2f0ff", "glow": "#cfc8ff"},
	"venenosa": {"top": "#8a3fb8", "bot": "#240a38", "trim": "#c8e86a", "glow": "#b6ff4a"}, ## deep saturated purple with an acid-lime trim (a future Vento stays the pale lilac)
	"legendary": {"top": "#f8c565", "bot": "#74400c", "trim": "#ffe8b0", "glow": "#ffb23a"}, ## amber gold leaning toward the orange rarity gem, but only slightly: it must not read as Ígnea to new players
	"back": {"top": "#2e2658", "bot": "#100c22", "trim": "#c9a24e", "glow": "#9d86ff"},
}
const TRIGGER_COL := Color("#ff9a4a") ## trigger tags: same weight as keywords, orange to read as another category
const KEYWORD_COL := Color("#ffe9a8") ## keyword names wherever they appear inside rules text
const GOLD_TRIM := Color("#f3d27a")
const COST_COL := UITheme.MOMENTUM
const ATK_COL := Color("#c8402e")
const HP_COL := Color("#2f9e58")
const FROST := Color("#cfefff")
const FROST_DEEP := Color("#4fc3ff") ## saturated ice blue: what makes a Congelada card readable from across the table
const STUN_COL := Color("#ffc233") ## Atordoamento: dizzy amber-gold, distinct from frost blue and doom violet
const BURN_COL := Color("#ff7043") ## Queimadura: hot orange-red, distinct from damage red and frost blue
const POISON_COL := Color("#b8e86b") ## Veneno: acid-lime drop over a deep violet medallion
const BLEED_COL := Color("#e85d75") ## Sangramento: reserved by the same shared badge for the future keyword
const DOT_BADGE_ENLARGEMENT := 1.75 ## size of the marker medallion (Queimadura/Veneno) vs. the other card badges; big enough to read the count on Leaders, which have no overlay
const DOOM_COL := Color("#b57bff") ## Condenada: sickly violet, always paired with a skull so it is not confused with the spell-shield lilac
const DEATH_WARD_COL := Color("#72e7ff") ## Baluarte armado: bright cyan so it reads as a persistent ready state
## Ice spikes of a frozen card, as [x across the card 0..1, length in base px, half width in base px].
const FROST_ICICLES := [[0.24, 11.0, 2.6], [0.34, 19.0, 3.2], [0.45, 9.0, 2.2], [0.56, 24.0, 3.6], [0.67, 13.0, 2.6], [0.77, 20.0, 3.2], [0.88, 10.0, 2.4]] ## hang from the top edge
const FROST_CRYSTALS := [[0.08, 16.0, 4.0], [0.21, 28.0, 5.0], [0.34, 13.0, 3.6], [0.5, 34.0, 5.6], [0.64, 17.0, 4.0], [0.78, 26.0, 5.0], [0.92, 15.0, 3.8]] ## stand on the bottom edge of the art
const FROST_GLINTS := [Vector2(0.3, 0.2), Vector2(0.74, 0.3), Vector2(0.52, 0.58), Vector2(0.18, 0.5), Vector2(0.84, 0.12), Vector2(0.62, 0.8)] ## twinkling stars

var card_id := ""
var inst: Dictionary = {} ## unit on board (live stats) or hand instance
var uid := 0
var face_down := false
var highlight := Color.TRANSPARENT ## outline for selection/targets
var ability_ready := false ## an "Ao Ativar" ability or a Transformar can be used right now: violet glow, distinct from the green attack glow
const ABILITY_GLOW := Color("#c07bff")
var dim := false
var cost_override := -1
var text_suffix := "" ## live count appended to the rules text in the big view (e.g. "(agora: 3)")
var snowball_level := GameState.SNOWBALL_BASE_LEVEL ## the owner's Bola de Neve level, shown where the card text says "{nivel}"

## Fills the live numbers of a rules text: "Cause {nivel} de dano" reads "Cause 5 de dano" once the
## owner's Bola de Neve has grown to 5. Without an owner (collection, deck builder) the level stays
## at its starting value, 1. Static so the big view in Main fills the text the same way.
static func fill_live_numbers(rules: String, level: int) -> String:
	return rules.replace("{nivel}", str(level))
var hovered := false
var hit_pad := 0.0 ## extra hit area below the card (lifted hand cards)
## Hover / drag zoom. Unlike the node's `scale`, which stretches the already drawn card (and blurs
## its text), the card is redrawn at the bigger size, so every glyph stays sharp.
var zoom := 1.0:
	set(value):
		zoom = value
		queue_redraw()
var _face_size := Vector2.ZERO ## the size the card face is drawn at: size * zoom, in whole pixels
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
## Congelada: how far the ice has grown over the card (0 = none yet, 1 = fully frozen). It is 1 by
## default; Main sets it to 0 and tweens it up at the moment of the freeze, so the ice spreads over the card.
var frost_grow := 1.0:
	set(v):
		frost_grow = v
		queue_redraw()
## The instant of freezing (0 = off, 1 = finished): a white-blue flash and two shockwaves of ice.
var frost_burst := 0.0:
	set(v):
		frost_burst = v
		queue_redraw()
var shadow := true
var fatigue := 0## > 0: not a real card but the Fadiga pseudo-card, showing this much damage

## Frame silhouette of the card being drawn: artifacts get cut (chamfered) corners instead of round ones,
## so a non-unit permanent reads differently from a unit at a glance. Only the big frame corners are cut.
var _chamfer_frame := false
const FRAME_CORNER_MIN := 5.0 ## corner radius (in base px) from which _chamfer_frame applies; small panels stay rounded
const TOKEN_CORNER_BOOST := 1.8 ## fichas: slightly rounder corners than regular cards
const ARCH_HEIGHT := 0.42 ## artifacts: how far down the art window (fraction of its height) the arch reaches
var _art_window := PackedVector2Array() ## outline of the art window of the card being drawn (see _art_window_pts)
const TOKEN_VEIL :=Color(0.78, 0.9, 1.0, 0.11) ## fichas: cool spectral tint over the frame, "conjured" look
const FULL_ART_BORDER := 3.0 ## champion units: width (in base px) of the essence-colored border left around the full-card art

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
static var _banish: Shader
static var _stealth_shader: Shader

## Keywords that change who can challenge or target whom get an icon medallion on the art (MTG Arena style),
## in this order down the left edge; glyph tint per keyword.
const BADGES := {
	"provocacao": Color("#ffc66b"),
	"voo": Color("#bfe6ff"),
	"longo_alcance": Color("#d6efaa"),
	"furtividade": Color("#cdb6ff"),
	"vigilancia": Color("#ffe39a"),
	"obsessao": Color("#ff7f6e"),
	"prudencia": Color("#9fd0ff"),
	"intimidacao": Color("#ffa24d"),
	"inalcancavel": Color("#9ff0d0"),
	"eterea": Color("#e6d9ff"),
	"vulneravel": Color("#ff9f91"),
	"inerte": Color("#b5c0c8"),
	"regeneracao": Color("#8df0a0"),
	"roubo_de_vida": Color("#ff6f8f"),
	"toque_letal": Color("#d4e866"),
}

func setup(id: String, instance: Dictionary = {}, size_scale := 1.0) -> CardView:
	card_id = id
	inst = instance
	uid = instance.get("uid", 0)
	custom_minimum_size = (BASE * size_scale).round() # whole pixels, so the text on the card stays crisp
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
	var zoom_shift := pivot_offset * (1.0 - zoom)
	return Rect2(zoom_shift, size * zoom + Vector2(0, hit_pad)).has_point(p)

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
	if highlight.a > 0 or hovered or _legendary() or inst.has("frozen") or inst.has("stun_markers") or inst.has("condemned_turn") or inst.get("summoning_sick", false):
		_t += delta
		_redraw_acc += delta
		if _redraw_acc >= 0.033 or highlight.a > 0 or hovered: ## shimmer at ~30 fps is plenty
			_redraw_acc = 0.0
			queue_redraw()

## Rules text as BBCode: trigger names in bold orange, and every keyword name in the text (Voo,
## Escudo de Feitiço, "Armadura 1"...) in bold yellow, so a card that grants or mentions a keyword
## shows it exactly like the keyword tags do. Use this for any rules text shown in a RichTextLabel.
static func colorize_rules(body: String, line_px := 28) -> String:
	body = _colorize_triggers(body, line_px)
	var ranges := keyword_ranges(body)
	for i in range(ranges.size() - 1, -1, -1):
		var span: Array = ranges[i]
		var word := body.substr(span[0], span[1] - span[0])
		body = body.substr(0, span[0]) + "[b][color=#%s]%s[/color][/b]" % [KEYWORD_COL.to_html(false), word] + body.substr(span[1])
	return body

static var _keyword_regex: RegEx
static var _keyword_names_with_value := {}

## [start, end) character ranges of keyword names in `text`. Longest names win ("Escudo de Feitiço"
## before "Escudo"), and a keyword with a value ("has_value" in cards.json, e.g. Armadura) swallows
## the number that follows it ("Armadura 1", "Armadura X").
static func keyword_ranges(text: String) -> Array:
	if _keyword_regex == null:
		var names: Array = []
		for kw in CardDB.data()["keywords"].values():
			names.append(String(kw["name"]))
			if kw.get("has_value", false):
				_keyword_names_with_value[String(kw["name"])] = true
		names.sort_custom(func(a, b): return a.length() > b.length())
		_keyword_regex = RegEx.create_from_string(r"(?<!\p{L})(" + "|".join(names) + r")((?: \d+| X(?!\p{L}))?)(?!\p{L})")
	var out := []
	for m in _keyword_regex.search_all(text):
		var end := m.get_end(1)
		if _keyword_names_with_value.has(m.get_string(1)):
			end = m.get_end(2)
		out.append([m.get_start(1), end])
	return out

## Trigger names (and an optional "(...)" qualifier before the colon, e.g. "Aliado Morre (uma vez por
## turno):") in bold orange. "Name (cost) {speed} (limits):" -> bold orange, with "{speed}"
## (lento/rapido/instantaneo) drawn as the spell speed seal (assets/ui/speed_<speed>.png, see
## tools/render_speed_badges.gd).
static func _colorize_triggers(body: String, line_px: int) -> String:
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

## Banished from the field: the card drains pale, spins and shrinks while a hole closes over
## it, instead of burning away like a death. The node frees itself.
func banish(delay := 0.0, edge := Color(0.8, 0.7, 1.0), dur := 0.9) -> void:
	if _banish == null:
		_banish = load("res://scripts/ui/shaders/banish.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _banish
	m.set_shader_parameter("size", size)
	m.set_shader_parameter("edge_color", edge)
	m.set_shader_parameter("progress", 0.0)
	material = m
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(m, "shader_parameter/progress", 1.0, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)
	var st := create_tween()
	st.tween_interval(delay)
	st.tween_property(self, "scale", scale * 0.55, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	st.parallel().tween_property(self, "rotation", rotation + 0.5, dur).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

func _legendary() -> bool:
	return not face_down and card_id != "" and CardDB.card(card_id)["rarity"] in ["champion", "legendary"]

# ---------------------------------------------------------------- drawing

var badge_only := "" ## tools/render_speed_badges.gd: draw just this speed seal, centered

func _draw() -> void:
	if badge_only != "":
		_speed_badge(size / 2.0, badge_only, size.y / SPEED_PILL_HEIGHT)
		return
	# a zoomed card is drawn at its final size (never stretched), growing around its pivot
	_face_size = (size * zoom).round()
	var zoom_shift := (pivot_offset * (1.0 - zoom)).round()
	var pop := 1.0 + 0.08 * proc ## scales around the center
	draw_set_transform(zoom_shift + shake + lunge + _face_size / 2.0 * (1.0 - pop), 0.0, Vector2(pop, pop))
	var s := _face_size.x / BASE.x
	var r := Rect2(Vector2.ZERO, _face_size)
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
	var is_token: bool = not face_down and cd.get("token", false)
	var is_artifact: bool = not face_down and cd["type"] != "unit" and cd["type"] != "spell"
	var death_ward_active: bool = not face_down and cd.get("death_ward", false)
	_chamfer_frame = is_artifact
	if is_token:
		rad *= TOKEN_CORNER_BOOST
	# Champion units: the art fills the whole card and only a thin border in the essence color(s) is left.
	# (A champion whose art file is missing keeps the classic layout, with its placeholder.)
	var full_art: bool = not face_down and cd.get("rarity", "") == "champion" and cd["type"] == "unit" and not is_token \
		and texture(cd.get("art", "")) != null
	if full_art:
		trim = Color(st["trim"]).lerp(Color(st2["trim"]), 0.5) ## no gold finish: the border shows the essence itself

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
	# usable ability: violet rings; pushed outward when another highlight (e.g. can attack) already uses the inner rings
	if ability_ready:
		var first_ring := 4 if highlight.a > 0 else 0
		for i in 4:
			_rrect_line(r.grow((2 + (first_ring + i) * 2.2) * s), rad + (first_ring + i) * 2 * s, Color(ABILITY_GLOW, (0.9 - i * 0.22) * (0.65 + 0.35 * pulse)), 2.2 * s)
	# The Baluarte's automatic protection is always active while it remains on the field.
	if death_ward_active:
		var ward_pulse := 0.7 + 0.3 * pulse
		for i in 3:
			_rrect_line(r.grow((2.5 + i * 2.6) * s), rad + i * 2 * s,
				Color(DEATH_WARD_COL, (0.9 - i * 0.22) * ward_pulse), 2.4 * s)
	# Congelada: a cold blue aura breathing around the whole frame
	if inst.has("frozen"):
		var breathing := 0.75 + 0.25 * sin(_t * 2.5)
		for i in 5:
			_rrect_line(r.grow((1.5 + i * 2.6) * s), rad + i * 2 * s, Color(FROST_DEEP, (0.95 - i * 0.17) * breathing * frost_grow), 2.8 * s)
	# Atordoada: an amber aura flickering unevenly, like a head still ringing
	if inst.has("stun_markers"):
		var ringing := 0.7 + 0.3 * sin(_t * 5.0) * sin(_t * 1.7)
		for i in 4:
			_rrect_line(r.grow((1.5 + i * 2.4) * s), rad + i * 2 * s, Color(STUN_COL, (0.95 - i * 0.2) * ringing), 2.6 * s)
	# Condenada: a violet aura pulsing slowly around the frame, like a heartbeat counting down
	if inst.has("condemned_turn"):
		var heartbeat := 0.6 + 0.4 * sin(_t * 3.2)
		for i in 4:
			_rrect_line(r.grow((1.5 + i * 2.4) * s), rad + i * 2 * s, Color(DOOM_COL, (0.9 - i * 0.2) * heartbeat), 2.6 * s)
	# trigger proc: hot rim light, plus a ring pulsing out of the frame
	if proc > 0:
		for i in 5:
			_rrect_line(r.grow((1.5 + i * 2.4) * s), rad + i * 2 * s, Color(TRIGGER_COL.lightened(0.25 - i * 0.05), (0.95 - i * 0.18) * proc), 2.6 * s)
	if proc_wave > 0 and proc_wave < 1:
		var k := 1.0 - pow(1.0 - proc_wave, 3.0)
		_rrect_line(r.grow((3 + 30 * k) * s), rad + 12 * k * s, Color(TRIGGER_COL.lightened(0.35), 0.85 * pow(1.0 - proc_wave, 1.5)), (3.2 - 2.2 * k) * s)

	# frame: gradient body, dark outer edge, metal trim with bevel
	var frame_style := _bright_border_style(st) if full_art else st
	var frame_style2 := _bright_border_style(st2) if full_art else st2
	if keys.size() < 2:
		_rrect_grad(r, rad, Color(frame_style["top"]), Color(frame_style["bot"]))
	else:
		_rrect_grad_split(r, rad, frame_style, frame_style2, s)
	_rrect_line(r.grow(-0.5 * s), rad, Color("#07060a"), 1.6 * s)
	if is_token:
		# ficha: dashed trim and a cool veil instead of the solid metal line
		_dashed_rrect_line(r.grow(-2.6 * s), rad - 2 * s, trim.lightened(0.65), 2.4 * s, 6.0 * s, 3.5 * s)
		_rrect_fill(r, rad, TOKEN_VEIL)
	elif not full_art: # (a full-art card has no room for the inner metal line: the art starts right inside the border)
		_rrect_line(r.grow(-2.6 * s), rad - 2 * s, Color(trim, 0.85), 1.1 * s)
	if is_artifact:
		# artifact: a second engraved line inside the trim, like a plate
		_rrect_line(r.grow(-5.0 * s), rad - 4 * s, Color(trim, 0.4), 0.8 * s)
	draw_line(Vector2(rad, 1.6 * s), Vector2(_face_size.x - rad, 1.6 * s), Color(1, 1, 1, 0.3), 1.0 * s)

	if face_down:
		_draw_back(r, s, trim)
		_finish(r, rad, s)
		return

	var font := UITheme.font("heavy")
	var col := Color(CardDB.essence(CardDB.essences_of(cd)[0])["color"])
	# art window: its shape tells the card kinds apart (rectangle = unit/spell, arch = artifact, medallion = ficha)
	var art := r.grow(-FULL_ART_BORDER * s) if full_art else Rect2(Vector2(7, 8) * s, Vector2(BASE.x - 14, 98) * s)
	var window_kind := "full" if full_art else ("medallion" if is_token else ("arch" if is_artifact else "rect"))
	_art_window = _art_window_pts(art, window_kind)
	if window_kind == "rect":
		draw_rect(art.grow(1.5 * s), Color("#07060a"))
	elif window_kind != "full":
		draw_colored_polygon(Geometry2D.offset_polygon(_art_window, 1.5 * s)[0], Color("#07060a"))
	var tex := texture(cd.get("art", ""))
	if tex:
		var ts := tex.get_size()
		var k: float = max(art.size.x / ts.x, art.size.y / ts.y)
		var src_size := art.size / k
		var src_origin := Vector2((ts.x - src_size.x) / 2, 0)
		if window_kind == "rect":
			draw_texture_rect_region(tex, art, Rect2(src_origin, src_size))
		else:
			# the art is cut to the window shape: every corner of the polygon picks its spot in the texture
			var uvs := PackedVector2Array()
			for p in _art_window:
				uvs.append((src_origin + (p - art.position) / k) / ts)
			draw_polygon(_art_window, PackedColorArray([Color.WHITE]), uvs, tex)
	else:
		_placeholder(art, cd, col, s)
	# inner shading at the top and bottom of the window
	if full_art:
		_draw_full_art_shading(art, s)
	else:
		_window_vgrad(Rect2(art.position, Vector2(art.size.x, 14 * s)), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0))
		_window_vgrad(Rect2(art.position + Vector2(0, art.size.y - 22 * s), Vector2(art.size.x, 22 * s)), Color(0, 0, 0, 0), Color(0, 0, 0, 0.55))
	if window_kind == "rect":
		draw_rect(art.grow(0.5 * s), Color(trim, 0.9), false, 1.2 * s)
		for c in [art.position, Vector2(art.end.x, art.position.y)]:
			_diamond(c, 3.2 * s, trim)
	else:
		var outline := Geometry2D.offset_polygon(_art_window, 0.5 * s)[0]
		draw_polyline(outline + PackedVector2Array([outline[0]]), Color(trim, 0.9), 1.2 * s, true)
	# divine shield bubble
	if inst.get("shield", false):
		var sc := art.get_center()
		for i in 3:
			draw_arc(sc, art.size.x * 0.46 - i * 3 * s, 0, TAU, 48, Color("#9fe3ff", (0.55 - i * 0.15) * 1.25), 2.5 * s, true) ## ~25% more visible
		draw_colored_polygon(_art_window, Color("#9fe3ff", 0.15))
	# spell shield: violet runic ring
	if inst.get("spell_shield", false):
		var sc := art.get_center()
		var rr := art.size.x * 0.4
		for i in 3: ## same weight as the divine shield bubble, only the color differs
			draw_arc(sc, rr - i * 3 * s, 0, TAU, 48, Color("#c9a8ff", (0.55 - i * 0.15) * 1.25), 2.5 * s, true)
		draw_colored_polygon(_art_window, Color("#c9a8ff", 0.15))
		for i in 6:
			var a := _t * 0.6 + i * TAU / 6.0
			_diamond(sc + Vector2(cos(a), sin(a)) * rr, 2.6 * s, Color("#e3d2ff"))
	if inst.has("frozen"):
		_draw_frost(art, s)
	if inst.has("stun_markers"):
		_draw_stun(art, s)
	if inst.get("summoning_sick", false):
		_draw_summoning_sickness(art, s)
	if inst.get("tide_mark", false):
		draw_arc(art.get_center() + Vector2(0, art.size.y * 0.32), art.size.x * 0.3, PI * 1.15, PI * 1.85, 24, Color("#6fd0ff", 0.85), 2 * s, true)
	_draw_dot_badges(art, s, pulse)
	if inst.has("condemned_turn"):
		# a dark violet veil over the art, then the skull medallion on the upper-right corner
		draw_colored_polygon(_art_window, Color("#2a0a4a", 0.28 + 0.08 * sin(_t * 3.2)))
		_doom_badge(Vector2(art.end.x - 11 * s, art.position.y + 11 * s), 10 * s, s)
	_kw_badges(art, cd, s)

	# species strip on the bottom edge of the art, right above the name plate
	var sp_s := CardDB.species_names(cd).to_upper()
	if sp_s != "":
		var spf := UITheme.font("bold")
		var sp_fs := _fit(spf, sp_s, 8.0 * s, art.size.x - 16 * s)
		var sp_w := spf.get_string_size(sp_s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(sp_fs)).x + 10 * s
		var strip := Rect2(Vector2((_face_size.x - sp_w) / 2, (92.5 if full_art else 90.5) * s), Vector2(sp_w, 11 * s))
		if not full_art: # over a full-card art the species is just lettering on the shaded art, no pill
			_rrect_fill(strip, 3 * s, Color(0, 0, 0, 0.62))
			_rrect_line(strip, 3 * s, Color(trim, 0.45), 0.8 * s)
		_text(spf, sp_s, Vector2(_face_size.x / 2, strip.get_center().y + sp_fs * 0.36), sp_fs, Color("#e9dcc0"))

	if full_art:
		_draw_full_art_name(cd["name"], s, trim)
	else:
		# name plate (pointed banner overlapping the art)
		var py := 102.0 * s
		var ph := 20.0 * s
		var plate := PackedVector2Array([Vector2(3 * s, py + ph / 2), Vector2(10 * s, py), Vector2(_face_size.x - 10 * s, py),
			Vector2(_face_size.x - 3 * s, py + ph / 2), Vector2(_face_size.x - 10 * s, py + ph), Vector2(10 * s, py + ph)])
		draw_colored_polygon(plate, Color("#15121b"))
		draw_colored_polygon(PackedVector2Array([plate[1], plate[2], plate[3], plate[0]]), Color(1, 1, 1, 0.05))
		draw_polyline(plate + PackedVector2Array([plate[0]]), trim, 1.2 * s, true)
		var nf := UITheme.font("title_bold")
		var name_s: String = cd["name"]
		_text(nf, name_s, Vector2(_face_size.x / 2, py + ph / 2 + 4 * s), _fit(nf, name_s, 12 * s, _face_size.x - 18 * s), Color("#fff4dc"))

	# lower panel: keywords (units), card type (artifacts) or the rules text (spells)
	if cd["type"] == "spell":
		# no gems at the bottom corners of a spell, so its panel is wider and taller to fit the text
		# (a long text can give a shorter "face_text" for this panel; the big view shows the full "text")
		var tp := Rect2(Vector2(8, 124.5) * s, Vector2(BASE.x - 16, 36.5) * s)
		_rrect_fill(tp, 4 * s, Color(0, 0, 0, 0.5))
		_rrect_line(tp, 4 * s, Color(trim, 0.25), 1 * s)
		_wrapped_text(UITheme.font("bold"), fill_live_numbers(str(cd.get("face_text", cd.get("text", ""))), snowball_level), tp.grow_individual(-3 * s, -1 * s, -3 * s, -1 * s), 11.0 * s, 6.0 * s, Color("#f1e8d4"))
		_speed_badge(Vector2(_face_size.x / 2, 17 * s), str(cd.get("speed", "lento")), s)
	else:
		var panel := Rect2(Vector2(10, 126) * s, Vector2(BASE.x - 20, 34) * s)
		if not full_art: # on a full-art card the keyword tags sit straight on the shaded art
			_rrect_fill(panel, 4 * s, Color(0, 0, 0, 0.38))
			_rrect_line(panel, 4 * s, Color(trim, 0.25), 1 * s)
		var lines := _panel_lines(cd)
		var bf := UITheme.font("bold")
		# keyword / trigger tags: as big as the panel allows (a bigger size beats perfect proportions on a phone)
		var tag_font_size := 13.0 * s
		var tag_line_height := 13.5 * s
		var ly := panel.get_center().y + 4.0 * s - (lines.size() - 1) * tag_line_height / 2.0
		for ln in lines:
			var room := panel.size.x - 12 * s
			if cd["type"] == "unit" and ly > 142 * s:
				room = _face_size.x - 2 * 29 * s # lines low in the panel sit between the atk/hp gems
			_text_segments(bf, ln, Vector2(_face_size.x / 2, ly), tag_font_size, room)
			ly += tag_line_height

	# essence seal on the bottom edge, crest on the top edge
	if is_token:
		_token_seal(Vector2(_face_size.x / 2, _face_size.y - 3 * s), 5.5 * s, trim) # fichas have no rarity
	else:
		_rarity_gem(Vector2(_face_size.x / 2, _face_size.y - 3 * s), 5.5 * s, cd["rarity"], trim)
	_diamond(Vector2(_face_size.x / 2, 2.5 * s), 3.5 * s, trim)

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
			var live_atk: int = max(0, inst["atk"] + inst["temp_atk"] + int(inst.get("temp_atk_until_next_turn", 0)) + int(inst.get("bonus_atk", 0)))
			atk_col = Color("#a8ffa0") if live_atk > atk else Color.WHITE
			atk = live_atk
			var live_max_hp: int = inst["hp"] + int(inst.get("bonus_hp", 0)) + int(inst.get("temp_hp", 0)) + int(inst.get("temp_hp_until_next_turn", 0))
			hp_col = Color("#ff8a80") if inst["damage"] > 0 else (Color("#a8ffa0") if live_max_hp > hp else Color.WHITE)
			hp = max(0, live_max_hp - inst["damage"])
		_gem("diamond", Vector2(14 * s, _face_size.y - 15 * s), 13.5 * s, ATK_COL, str(atk), atk_col, s)
		_gem("shield", Vector2(_face_size.x - 14 * s, _face_size.y - 15 * s), 12.5 * s, HP_COL, str(hp), hp_col, s)
	_finish(r, rad, s)

## Border of a full-art champion: the essence gradient, kept bright all the way down (the normal frame fades to
## near-black at the bottom, which would read as a black border instead of the essence color).
func _bright_border_style(style: Dictionary) -> Dictionary:
	var top := Color(style["top"])
	return {"top": top, "bot": top.lerp(Color(style["bot"]), 0.4)}

## Shading that keeps the lettering readable over a full-card art: a light veil at the top (cost and
## essence gems), and a long smooth fade to dark from the middle of the card down, where the name,
## species and keyword tags are written.
func _draw_full_art_shading(art: Rect2, s: float) -> void:
	var shade := Color(0.02, 0.015, 0.03)
	_window_vgrad(Rect2(art.position, Vector2(art.size.x, 30 * s)), Color(shade, 0.5), Color(shade, 0))
	_window_vgrad(Rect2(Vector2(art.position.x, 62 * s), Vector2(art.size.x, 50 * s)), Color(shade, 0), Color(shade, 0.6))
	_window_vgrad(Rect2(Vector2(art.position.x, 112 * s), Vector2(art.size.x, art.end.y - 112 * s)), Color(shade, 0.6), Color(shade, 0.9))

## The name of a full-art champion: big Cinzel lettering with a drop shadow and a thick dark outline over
## the art, and a thin golden rule fading out on both sides underneath it.
func _draw_full_art_name(card_name: String, s: float, trim: Color) -> void:
	var name_font := UITheme.font("title_bold")
	var font_size := _fit(name_font, card_name, 15.0 * s, _face_size.x - 14 * s)
	var center_x := _face_size.x / 2
	_text(name_font, card_name, Vector2(center_x, 117.0 * s + 1.8 * s), font_size, Color(0, 0, 0, 0.6)) # drop shadow
	_text(name_font, card_name, Vector2(center_x, 117.0 * s), font_size, Color("#fff4dc"))
	var rule_y := 122.0 * s
	var half_length := 36.0 * s
	var thickness := 0.5 * s
	var rule_color := Color(trim.lightened(0.3), 0.9)
	var faded := Color(rule_color, 0.0)
	for direction in [-1.0, 1.0]:
		var outer_x: float = center_x + direction * half_length
		draw_polygon(PackedVector2Array([Vector2(outer_x, rule_y - thickness), Vector2(center_x, rule_y - thickness),
			Vector2(center_x, rule_y + thickness), Vector2(outer_x, rule_y + thickness)]), PackedColorArray([faded, rule_color, rule_color, faded]))
	_diamond(Vector2(center_x, rule_y), 2.2 * s, rule_color)

## Overlays shared by both faces: foil shimmer, hit flash, dim veil.
func _finish(r: Rect2, rad: float, s: float) -> void:
	if _legendary():
		var x := fmod(_t * 0.45, 1.6) * (_face_size.x + _face_size.y) - _face_size.y
		var band := PackedVector2Array([Vector2(x, _face_size.y), Vector2(x + 26 * s, _face_size.y), Vector2(x + 26 * s + _face_size.y, 0), Vector2(x + _face_size.y, 0)])
		for poly in Geometry2D.intersect_polygons(band, _rrect_pts(r, rad)):
			draw_colored_polygon(poly, Color(1, 0.96, 0.8, 0.16))
	if inst.has("frozen"):
		_draw_frost_shell(r, rad, s)
	if proc_wave > 0 and proc_wave < 1:
		# a bright band of light sweeping across the card
		var bx := lerpf(-_face_size.y * 0.6, _face_size.x + 10 * s, proc_wave)
		var bw := 30 * s
		var sweep := PackedVector2Array([Vector2(bx - _face_size.y * 0.4, _face_size.y), Vector2(bx - _face_size.y * 0.4 + bw, _face_size.y), Vector2(bx + _face_size.y * 0.6 + bw, 0), Vector2(bx + _face_size.y * 0.6, 0)])
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
	var plate := PackedVector2Array([Vector2(3 * s, py + ph / 2), Vector2(10 * s, py), Vector2(_face_size.x - 10 * s, py),
		Vector2(_face_size.x - 3 * s, py + ph / 2), Vector2(_face_size.x - 10 * s, py + ph), Vector2(10 * s, py + ph)])
	draw_colored_polygon(plate, Color("#15121b"))
	draw_polyline(plate + PackedVector2Array([plate[0]]), trim, 1.2 * s, true)
	_text(UITheme.font("title_bold"), "Fadiga", Vector2(_face_size.x / 2, py + ph / 2 + 4.5 * s), 14 * s, Color("#fff4dc"))
	# rules text
	var panel := Rect2(Vector2(10, 126) * s, Vector2(BASE.x - 20, 36) * s)
	_rrect_fill(panel, 4 * s, Color(0, 0, 0, 0.38))
	_rrect_line(panel, 4 * s, Color(trim, 0.25), 1 * s)
	var bf := UITheme.font("bold")
	_text(bf, "Sem cartas!", Vector2(_face_size.x / 2, panel.position.y + 15 * s), 12 * s, Color("#e9dcc0"))
	var dmg := "Tome %d de dano." % fatigue
	_text(bf, dmg, Vector2(_face_size.x / 2, panel.position.y + 30 * s), _fit(bf, dmg, 12 * s, panel.size.x - 8 * s), Color("#ff8a80"))
	_diamond(Vector2(_face_size.x / 2, 2.5 * s), 3.5 * s, trim)
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

## A tower with a shut portcullis: Provocação's symbol on the keyword medallion.
func _taunt_gate_glyph(c: Vector2, g: float, tint: Color, alpha: float, s: float) -> void:
	draw_colored_polygon(_unit_pts(c, g, [[-0.55, 0.7], [-0.55, -0.7], [-0.33, -0.7], [-0.33, -0.45], [-0.11, -0.45],
		[-0.11, -0.7], [0.11, -0.7], [0.11, -0.45], [0.33, -0.45], [0.33, -0.7], [0.55, -0.7], [0.55, 0.7]]), Color(tint, alpha))
	var gate := PackedVector2Array()
	for i in 9:
		var a := PI + PI * i / 8.0
		gate.append(c + Vector2(cos(a) * 0.22, 0.2 + sin(a) * 0.25) * g)
	gate.append(c + Vector2(0.22, 0.7) * g)
	gate.append(c + Vector2(-0.22, 0.7) * g)
	draw_colored_polygon(gate, Color(0.03, 0.02, 0.04, minf(1.0, alpha * 6.0)))
	var bar_color := Color(tint, minf(1.0, alpha * 5.0))
	for bar_x in [-0.1, 0.1]:
		draw_line(c + Vector2(bar_x, -0.02) * g, c + Vector2(bar_x, 0.7) * g, bar_color, 0.8 * s, true)
	draw_line(c + Vector2(-0.22, 0.34) * g, c + Vector2(0.22, 0.34) * g, bar_color, 0.8 * s, true)

## The art of a frozen unit sealed in ice: a deep blue veil, rime on top, ice piling up at the bottom
## with crystals standing on it, and a big slowly turning snowflake in the middle.
func _draw_frost(art: Rect2, s: float) -> void:
	var grow := frost_grow
	draw_colored_polygon(_art_window, Color(FROST_DEEP, 0.42 * grow))
	_window_vgrad(Rect2(art.position, Vector2(art.size.x, art.size.y * 0.4)), Color(1, 1, 1, 0.5 * grow), Color(1, 1, 1, 0))
	var pile_top := art.end.y - art.size.y * 0.45
	_window_vgrad(Rect2(Vector2(art.position.x, pile_top), Vector2(art.size.x, art.end.y - pile_top)), Color(0.85, 0.96, 1, 0), Color(0.85, 0.96, 1, 0.6 * grow))
	# crystals growing up from the bottom edge of the art (clipped to the art window)
	for crystal in FROST_CRYSTALS:
		var base := Vector2(art.position.x + art.size.x * crystal[0], art.end.y + 1 * s)
		var half_width: float = crystal[2] * s
		var tip := base + Vector2(0, -crystal[1] * s * grow)
		_window_polygon(PackedVector2Array([base + Vector2(-half_width, 0), tip, base + Vector2(half_width, 0)]), Color(0.7, 0.92, 1.0, 0.92 * grow))
		_window_polygon(PackedVector2Array([base, tip, base + Vector2(half_width, 0)]), Color(1, 1, 1, 0.85 * grow)) ## the lit facet
	_draw_snowflake(art.get_center(), art.size.x * 0.3 * (0.4 + 0.6 * grow), s, Color(1, 1, 1, 0.78 * grow))
	draw_polyline(_art_window + PackedVector2Array([_art_window[0]]), Color(1, 1, 1, 0.95 * grow), 2.2 * s, true)

## The art of a stunned unit: a dull amber veil, stars circling over its head and a medallion with the
## number of stun markers it still has (each one costs the unit an untap).
func _draw_stun(art: Rect2, s: float) -> void:
	draw_colored_polygon(_art_window, Color("#3a2a00", 0.34))
	var orbit_center := Vector2(art.get_center().x, art.position.y + art.size.y * 0.22)
	for star_index in 5:
		var angle := _t * 2.4 + star_index * TAU / 5.0
		var star_position := orbit_center + Vector2(cos(angle) * art.size.x * 0.32, sin(angle) * art.size.y * 0.07)
		var in_front := 0.6 + 0.4 * sin(angle) # stars on the near side of the orbit read bigger and brighter
		_draw_glint(star_position, (4.0 + 4.0 * in_front) * s, Color(1.0, 0.9, 0.45, 0.55 + 0.45 * in_front))
	var badge_radius := 11 * s
	var badge_center := Vector2(art.end.x - badge_radius - 2 * s, art.end.y - badge_radius - 2 * s)
	draw_circle(badge_center + Vector2(0, 1.4 * s), badge_radius * 1.2, Color(0, 0, 0, 0.6))
	draw_circle(badge_center, badge_radius * 1.14, Color("#4a3200"))
	draw_circle(badge_center, badge_radius * 1.06, STUN_COL)
	draw_circle(badge_center, badge_radius, Color("#241800"))
	_text(UITheme.font("heavy"), str(int(inst.get("stun_markers", 1))), badge_center + Vector2(0, badge_radius * 0.36), badge_radius * 1.15, STUN_COL.lightened(0.3))

## A unit that just arrived and cannot attack yet (Enjoo de Invocação): the art dims to a calm
## slate-blue, and three small "z" rise from its upper-right corner, one after the other, each
## growing a little and fading out. Deliberately quiet: no ring, no badge, no bright color.
func _draw_summoning_sickness(art: Rect2, s: float) -> void:
	draw_colored_polygon(_art_window, Color("#141b2e", 0.3 + 0.06 * sin(_t * 1.6)))
	var drowsy_col := Color("#c3cdee")
	var rise_seconds := 3.0 # one "z" takes this long to drift up and vanish
	var z_font := UITheme.font("heavy")
	for z_index in 3:
		var progress := fposmod(_t / rise_seconds + z_index / 3.0, 1.0) # 0 = just appeared, 1 = gone
		var fade := sin(progress * PI) # in and out, brightest halfway up
		var start := Vector2(art.end.x - 18 * s, art.position.y + art.size.y * 0.5)
		var z_position := start + Vector2(sin(progress * TAU) * 3 * s, -progress * art.size.y * 0.3)
		_text(z_font, "z", z_position, (14.0 + 10.0 * progress) * s, Color(drowsy_col, 0.95 * fade))

## Ice over the whole card, drawn on top of everything: a cold tint, a white crust on the frame,
## icicles hanging from the top edge, twinkling glints, and the flash and shockwaves of the freezing moment.
func _draw_frost_shell(r: Rect2, rad: float, s: float) -> void:
	var grow := frost_grow
	_rrect_fill(r, rad, Color(0.45, 0.8, 1.0, 0.2 * grow))
	_rrect_line(r.grow(-1.0 * s), rad, Color(1, 1, 1, 0.95 * grow), 2.6 * s)
	_rrect_line(r.grow(-3.6 * s), maxf(rad - 2 * s, 0.0), Color(FROST_DEEP, 0.7 * grow), 1.6 * s)
	for icicle in FROST_ICICLES:
		var base := Vector2(_face_size.x * icicle[0], 1 * s)
		var half_width: float = icicle[2] * s
		var tip := base + Vector2(0, icicle[1] * s * grow)
		draw_colored_polygon(PackedVector2Array([base + Vector2(-half_width, 0), tip, base + Vector2(half_width, 0)]), Color(0.72, 0.93, 1.0, 0.95 * grow))
		draw_colored_polygon(PackedVector2Array([base, tip, base + Vector2(-half_width, 0)]), Color(1, 1, 1, 0.9 * grow))
		draw_polyline(PackedVector2Array([base + Vector2(-half_width, 0), tip, base + Vector2(half_width, 0)]), Color(FROST_DEEP.darkened(0.2), 0.8 * grow), 0.8 * s, true)
	for glint_index in FROST_GLINTS.size():
		var twinkle := maxf(0.0, sin(_t * 2.2 + glint_index * 1.9))
		if twinkle > 0.05:
			_draw_glint(FROST_GLINTS[glint_index] * _face_size, (3.0 + 6.0 * twinkle) * s, Color(1, 1, 1, twinkle * grow))
	if frost_burst > 0 and frost_burst < 1:
		var reach := 1.0 - pow(1.0 - frost_burst, 3.0)
		var fade := 1.0 - frost_burst
		_rrect_fill(r, rad, Color(0.85, 0.97, 1.0, 0.75 * fade * fade))
		_rrect_line(r.grow((4 + 44 * reach) * s), rad + 16 * reach * s, Color(1, 1, 1, 0.95 * pow(fade, 1.4)), (6.0 - 4.0 * reach) * s)
		var late_reach := 1.0 - pow(1.0 - clampf(frost_burst * 1.3 - 0.15, 0.0, 1.0), 3.0)
		_rrect_line(r.grow((4 + 30 * late_reach) * s), rad + 10 * late_reach * s, Color(FROST_DEEP, 0.8 * pow(fade, 1.4)), (5.0 - 3.0 * late_reach) * s)

## A six-armed snowflake with side branches, slowly turning.
func _draw_snowflake(c: Vector2, arm: float, s: float, col: Color) -> void:
	for i in 6:
		var direction := Vector2.from_angle(_t * 0.15 + i * TAU / 6.0)
		draw_line(c, c + direction * arm, col, 2.0 * s, true)
		for branch_at in [0.55, 0.8]:
			var branch_base: Vector2 = c + direction * arm * branch_at
			for side in [-1.0, 1.0]:
				draw_line(branch_base, branch_base + direction.rotated(side * 0.9) * arm * 0.28, col, 1.5 * s, true)
	_diamond(c, arm * 0.14, Color(1, 1, 1, col.a))

## A four-pointed star of light.
func _draw_glint(c: Vector2, radius: float, col: Color) -> void:
	var inner := radius * 0.18
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -radius), c + Vector2(inner, -inner), c + Vector2(radius, 0), c + Vector2(inner, inner),
		c + Vector2(0, radius), c + Vector2(-inner, inner), c + Vector2(-radius, 0), c + Vector2(-inner, -inner)]), col)

## Fills a polygon, keeping only the part that falls inside the art window.
func _window_polygon(polygon: PackedVector2Array, col: Color) -> void:
	for piece in Geometry2D.intersect_polygons(polygon, _art_window):
		draw_colored_polygon(piece, col)

## Armadura shown for a unit: the live total on the board (own + temporary + from adjacent allies,
## put in the view data by Main as "armor_total"), the printed value everywhere else.
static func armor_of_view(cd: Dictionary, instance: Dictionary) -> int:
	if instance.has("armor_total"):
		return int(instance["armor_total"])
	if instance.has("damage"):
		return int(instance.get("armor", 0)) + int(instance.get("temp_armor", 0)) + int(instance.get("turn_armor", 0))
	return int(cd.get("armor", 0))

## The number after the keyword "Crítico" (1-4): the live level on the board (it can grow in play, and
## effects add temporary levels until end of turn), the printed one everywhere else. 0 = no Crítico, so no tag.
static func critico_of_view(cd: Dictionary, instance: Dictionary) -> int:
	var permanent_level := int(instance["critico"]) if instance.has("critico") else int(cd.get("critico", 0))
	return clampi(permanent_level + int(instance.get("temp_critico", 0)), 0, 4)

## The tag text of a Tóxico card: "Tóxico" (level 1), "Tóxico 2", or for the Ataque-based kind
## the live number on the board ("Tóxico 5") and "Tóxico X" everywhere else. Mirrors GameState.toxico_markers.
static func toxico_tag_of_view(cd: Dictionary, instance: Dictionary) -> String:
	var keyword_name: String = CardDB.keyword("toxico")["name"]
	if cd.get("toxico_equals_attack", false):
		if not instance.has("damage"):
			return keyword_name + " X"
		var live_attack: int = int(instance["atk"]) + int(instance["temp_atk"]) + int(instance.get("temp_atk_until_next_turn", 0)) + int(instance.get("bonus_atk", 0))
		return "%s %d" % [keyword_name, maxi(1, live_attack)]
	var level := int(cd.get("toxico_level", 1))
	return keyword_name if level <= 1 else "%s %d" % [keyword_name, level]

## Attacks per turn this card can make: 2 with Ataque Duplo, which a card can also earn by reaching
## Crítico 4 ("critico_maximo": {"ataque_duplo": true}, Vael); otherwise 1. Mirrors GameState.attacks_allowed.
static func attacks_allowed_of_view(cd: Dictionary, instance: Dictionary) -> int:
	var keywords: Array = instance.get("keywords", cd.get("keywords", []))
	if keywords.has("ataque_duplo"):
		return 2
	if critico_of_view(cd, instance) >= 4 and cd.get("critico_maximo", {}).get("ataque_duplo", false):
		return 2
	return 1

## Crítico X rolls a crit with X * 25% chance (level 4 = always).
static func critico_chance_percent(critico_level: int) -> int:
	return mini(100, critico_level * 25)

## Live keywords on the board, printed ones elsewhere.
func _keywords(cd: Dictionary) -> Array:
	return inst.get("keywords", cd.get("keywords", []))

## Live periodic marker count. The old `burn` field is accepted for cards from an older network
## snapshot, while all new state uses the generic dot_markers dictionary.
static func dot_marker_count_of_view(instance: Dictionary, dot_id: String) -> int:
	var markers: Dictionary = instance.get("dot_markers", {})
	if markers.has(dot_id):
		return int(markers[dot_id])
	if dot_id == "queimadura":
		return int(instance.get("burn", 0))
	return 0

## Shared live-marker palette. Keeping this here makes the exact same badge readable on cards and Leaders.
static func dot_badge_color(dot_id: String) -> Color:
	return {"queimadura": BURN_COL, "veneno": POISON_COL, "sangramento": BLEED_COL}.get(dot_id, Color("#d8d2c4"))

## Shared live-marker badge used by unit cards and LeaderView. The icon and count deliberately sit in
## the same medallion, so a marker never becomes invisible just because the target is a unit or Leader.
static func draw_dot_badge(target: CanvasItem, center: Vector2, radius: float, scale: float, dot_id: String, amount: int, pulse := 0.5, text_scale := 1.0) -> void:
	if target == null or amount <= 0:
		return
	var col := dot_badge_color(dot_id)
	var deep := Color("#241332") if dot_id == "veneno" else (Color("#5d1723") if dot_id == "sangramento" else Color("#7d2114"))
	var danger := dot_id == "veneno" and amount >= 6
	var pulse_alpha := 0.6 + 0.4 * clampf(float(pulse), 0.0, 1.0)
	target.draw_circle(center + Vector2(0, 1.4 * scale), radius * 1.2, Color(0, 0, 0, 0.62))
	target.draw_circle(center, radius * 1.16, deep)
	target.draw_circle(center, radius * 1.08, Color("#ffb04d") if dot_id == "queimadura" else col)
	target.draw_circle(center, radius, col.darkened(0.58))
	var rim := Color("#ff8f86", pulse_alpha) if danger else Color(col.lightened(0.32), 0.9)
	target.draw_arc(center, radius * 1.07, 0, TAU, 28, rim, 1.4 * scale, true)

	var icon := PackedVector2Array()
	if dot_id == "veneno":
		# acid drop: a pointed top with a rounded lower body
		icon = PackedVector2Array([
			center + Vector2(0, -0.78 * radius), center + Vector2(0.42 * radius, -0.2 * radius),
			center + Vector2(0.44 * radius, 0.27 * radius), center + Vector2(0.24 * radius, 0.58 * radius),
			center + Vector2(-0.24 * radius, 0.58 * radius), center + Vector2(-0.44 * radius, 0.27 * radius),
			center + Vector2(-0.42 * radius, -0.2 * radius)])
	elif dot_id == "sangramento":
		# a compact blade/slash silhouette, ready for the future Sangramento badge
		icon = PackedVector2Array([
			center + Vector2(-0.48 * radius, 0.5 * radius), center + Vector2(0.28 * radius, -0.56 * radius),
			center + Vector2(0.5 * radius, -0.56 * radius), center + Vector2(-0.25 * radius, 0.5 * radius)])
	else:
		icon = PackedVector2Array([
			center + Vector2(0, -0.86 * radius), center + Vector2(0.38 * radius, -0.25 * radius),
			center + Vector2(0.16 * radius, 0.0), center + Vector2(0.52 * radius, 0.46 * radius),
			center + Vector2(0, 0.72 * radius), center + Vector2(-0.48 * radius, 0.46 * radius),
			center + Vector2(-0.16 * radius, 0.0), center + Vector2(-0.38 * radius, -0.25 * radius)])
	target.draw_colored_polygon(icon, col.lightened(0.2))
	target.draw_polyline(icon + PackedVector2Array([icon[0]]), Color(1, 1, 1, 0.35), 0.65 * scale, true)
	var font := UITheme.font("heavy")
	var label := str(amount)
	var font_size := maxi(1, int(radius * (1.12 if amount < 10 else 0.88) * text_scale))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := center + Vector2(-width / 2.0, radius * 0.46)
	# Near-black digits with a pale halo: the icon behind them is light, so white text washed out.
	target.draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, maxi(2, int(radius * 0.28)), Color(col.lightened(0.7), 0.95))
	target.draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#120a18"))

## Draw every live periodic marker on the card. They stack vertically instead of replacing one another,
## so simultaneous Queimadura/Veneno/Sangramento remains unambiguous.
func _draw_dot_badges(art: Rect2, s: float, pulse: float) -> void:
	var active_dots: Array = []
	for dot_id in ["queimadura", "veneno", "sangramento"]:
		if dot_marker_count_of_view(inst, dot_id) > 0:
			active_dots.append(dot_id)
	if active_dots.is_empty():
		return
	# One marker gets the big medallion so the count is readable at a glance; with more markers
	# each one shrinks so the stack still fits inside the art window.
	var enlargement: float = DOT_BADGE_ENLARGEMENT if active_dots.size() == 1 else (1.35 if active_dots.size() == 2 else 1.0)
	var radius := 10 * s * enlargement
	var shadow_radius := radius * 1.2 # the medallion's drop shadow is its widest part
	# right edge of the art, just below the essence/doom corner (which ends ~22 px into the art)
	var center := Vector2(art.end.x - shadow_radius - 1 * s, art.position.y + 22 * s + shadow_radius)
	for dot_id in active_dots:
		CardView.draw_dot_badge(self, center, radius, s, dot_id, dot_marker_count_of_view(inst, dot_id), pulse)
		center.y += shadow_radius * 2.0 + 1 * s

## Round medallions down the left edge of the art, under the cost gem.
func _kw_badges(art: Rect2, cd: Dictionary, s: float) -> void:
	var kws := _keywords(cd)
	# Leave a little more clearance below the cost orb. Full-art Champion cards start their art
	# closer to the top edge, so their first medallion otherwise tucks under the orb drawn later.
	var c := Vector2(art.position.x + 11 * s, art.position.y + 40 * s)
	for kw in BADGES:
		if kws.has(kw):
			_kw_badge(kw, c, 10 * s, s)
			c.y += 23 * s
	var armor_value := armor_of_view(cd, inst)
	if armor_value > 0:
		_armor_badge(c, 10 * s, s, armor_value)
		c.y += 23 * s
	# an Ao Ativar that exhausts the unit: lit while it can still be used, dark once spent.
	# Shown on both turns, since the dim veil only means "can't attack" on the owner's turn.
	if inst.has("damage") and cd.get("activated", {}).get("exhaust", false):
		_use_badge(c, 10 * s, s, not inst.get("exhausted", false))

## Armadura medallion: a steel shield with the amount written on it.
func _armor_badge(c: Vector2, r: float, s: float, amount: int) -> void:
	var steel := Color("#b8c4d2")
	draw_circle(c + Vector2(0, 1.4 * s), r * 1.18, Color(0, 0, 0, 0.5))
	draw_circle(c, r * 1.14, UITheme.GOLD_DARK.darkened(0.3))
	draw_circle(c, r * 1.07, UITheme.GOLD)
	draw_circle(c, r, steel.darkened(0.82))
	draw_arc(c, r * 1.07, 0, TAU, 24, Color(UITheme.GOLD_LIGHT, 0.7), 0.8 * s, true)
	draw_colored_polygon(_shape("shield", c, r * 0.82), steel.darkened(0.15))
	draw_colored_polygon(_shape("shield", c, r * 0.64), steel.darkened(0.55))
	_text(UITheme.font("heavy"), str(amount), c + Vector2(0, r * 0.32), r * 1.05, Color.WHITE)

## Live Condenada marker: a dark medallion with a violet skull (cranium, jaw, eye sockets, nose).
func _doom_badge(c: Vector2, r: float, s: float) -> void:
	draw_circle(c + Vector2(0, 1.4 * s), r * 1.2, Color(0, 0, 0, 0.62))
	draw_circle(c, r * 1.16, Color("#2a0a4a"))
	draw_circle(c, r * 1.08, DOOM_COL)
	draw_circle(c, r, Color("#160726"))
	var bone := Color("#eadcff")
	draw_circle(c + Vector2(0, -r * 0.14), r * 0.52, bone) # cranium
	draw_rect(Rect2(c + Vector2(-r * 0.27, r * 0.2), Vector2(r * 0.54, r * 0.4)), bone) # jaw
	var socket := Color("#160726")
	draw_circle(c + Vector2(-r * 0.2, -r * 0.1), r * 0.15, socket) # eye sockets
	draw_circle(c + Vector2(r * 0.2, -r * 0.1), r * 0.15, socket)
	draw_colored_polygon(_unit_pts(c, r, [[0.0, 0.04], [-0.08, 0.24], [0.08, 0.24]]), socket) # nose
	for i in 2: # teeth gaps
		draw_line(c + Vector2((-0.09 + i * 0.18) * r, 0.42 * r), c + Vector2((-0.09 + i * 0.18) * r, 0.6 * r), socket, 0.9 * s)

func _use_badge(c: Vector2, r: float, s: float, ready: bool) -> void:
	var col := TRIGGER_COL if ready else Color("#6f6a78")
	draw_circle(c + Vector2(0, 1.4 * s), r * 1.18, Color(0, 0, 0, 0.5))
	draw_circle(c, r * 1.14, UITheme.GOLD_DARK.darkened(0.3 if ready else 0.6))
	draw_circle(c, r * 1.07, UITheme.GOLD if ready else UITheme.GOLD_DARK)
	draw_circle(c, r, col.darkened(0.82))
	if ready:
		draw_circle(c - Vector2(0, r * 0.35), r * 0.62, Color(col, 0.18))
	var bolt := _unit_pts(c, r * 0.8, [[0.2, -0.85], [-0.5, 0.1], [-0.05, 0.1], [-0.22, 0.85], [0.5, -0.15], [0.05, -0.15]])
	draw_colored_polygon(bolt, col.lightened(0.15) if ready else Color(col, 0.55))
	if not ready:
		draw_line(c + Vector2(-0.7, 0.7) * r, c + Vector2(0.7, -0.7) * r, Color("#1a171f"), 1.6 * s, true)

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
		"provocacao": # a tower with a shut portcullis: the way is barred
			_taunt_gate_glyph(c + Vector2(0, 0.05 * g), g * 1.08, lit, 1.0, s)
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
		"intimidacao": # a glaring pair of eyes under angry brows
			for sx in [-1.0, 1.0]:
				draw_colored_polygon(_unit_pts(c, g, [[sx * 0.88, -0.38], [sx * 0.08, 0.02], [sx * 0.2, 0.46], [sx * 0.8, 0.3]]), lit)
				draw_circle(c + Vector2(sx * 0.36, 0.2) * g, 0.1 * g + 0.3 * s, col.darkened(0.85))
		"obsessao": # a crown inside a target: it only hunts the enemy Leader
			draw_arc(c, g * 0.86, 0, TAU, 28, col, 1.3 * s, true)
			draw_colored_polygon(_unit_pts(c, g, [[-0.5, 0.36], [-0.56, -0.3], [-0.26, -0.02], [0, -0.46],
				[0.26, -0.02], [0.56, -0.3], [0.5, 0.36]]), lit)
		"prudencia": # a raised shield inside a ring: it only answers challenges, never walks up to the Leader
			draw_arc(c, g * 0.86, 0, TAU, 28, col, 1.3 * s, true)
			draw_colored_polygon(_unit_pts(c, g, [[-0.48, -0.42], [0.48, -0.42], [0.48, 0.0], [0, 0.5], [-0.48, 0.0]]), lit)
			draw_line(c + Vector2(0, -0.3) * g, c + Vector2(0, 0.3) * g, col.darkened(0.85), 1.3 * s, true)
		"inalcancavel": # a crosshair crossed out: it can't be aimed at
			draw_arc(c, g * 0.55, 0, TAU, 24, lit, 1.2 * s, true)
			for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(c + dir * g * 0.3, c + dir * g * 0.85, lit, 1.2 * s, true)
			draw_line(c + Vector2(-0.7, 0.7) * g, c + Vector2(0.7, -0.7) * g, Color("#ff7f6e"), 1.6 * s, true)
		"eterea": # a little ghost with a wavy hem
			var ghost := PackedVector2Array()
			for i in 13:
				var a := PI + PI * i / 12.0
				ghost.append(c + Vector2(cos(a) * 0.5, -0.1 + sin(a) * 0.6) * g)
			ghost.append_array(_unit_pts(c, g, [[0.5, 0.62], [0.25, 0.42], [0, 0.62], [-0.25, 0.42], [-0.5, 0.62]]))
			draw_colored_polygon(ghost, Color(lit, 0.85))
			for x in [-0.18, 0.18]:
				draw_circle(c + Vector2(x, -0.12) * g, 0.09 * g + 0.3 * s, col.darkened(0.85))
		"vulneravel": # an open shield with a split down its center
			draw_colored_polygon(_unit_pts(c, g, [[-0.62, -0.62], [0.62, -0.62], [0.52, 0.18], [0, 0.78], [-0.52, 0.18]]), lit)
			draw_line(c + Vector2(0.12, -0.45) * g, c + Vector2(-0.08, -0.02) * g, col.darkened(0.82), 1.4 * s, true)
			draw_line(c + Vector2(-0.08, -0.02) * g, c + Vector2(0.12, 0.05) * g, col.darkened(0.82), 1.4 * s, true)
			for sx in [-0.8, 0.8]:
				draw_line(c + Vector2(sx * 0.4, -0.15) * g, c + Vector2(sx * 0.9, -0.45) * g, lit, 1.2 * s, true)
		"inerte": # a crossed-out spark: this unit cannot act or turn
			draw_arc(c, g * 0.62, 0, TAU, 24, lit, 1.2 * s, true)
			draw_line(c + Vector2(-0.65, 0.65) * g, c + Vector2(0.65, -0.65) * g, lit, 1.6 * s, true)
		"roubo_de_vida": # a heart with a dark highlight: the damage dealt flows back into the Leader's life
			for sx in [-1.0, 1.0]:
				draw_circle(c + Vector2(sx * 0.28, -0.2) * g, 0.34 * g, lit)
			draw_colored_polygon(_unit_pts(c, g, [[-0.6, -0.06], [0.6, -0.06], [0, 0.7]]), lit)
			draw_arc(c + Vector2(-0.28, -0.2) * g, 0.2 * g, PI * 0.9, PI * 1.5, 8, col.darkened(0.8), 1.1 * s, true)
		"toque_letal": # an open hand with a skull floating above the palm: whatever it touches dies
			var bone := Color("#f4eedb")
			var socket := col.darkened(0.88)
			draw_circle(c + Vector2(0, -0.38) * g, 0.62 * g, Color(col, 0.16)) # the glow around the skull
			draw_circle(c + Vector2(0, -0.42) * g, 0.4 * g, bone) # cranium
			draw_colored_polygon(_unit_pts(c, g, [[-0.22, -0.2], [0.22, -0.2], [0.18, 0.1], [-0.18, 0.1]]), bone) # jaw
			for sx in [-1.0, 1.0]: # eye sockets
				draw_circle(c + Vector2(sx * 0.15, -0.44) * g, 0.1 * g + 0.2 * s, socket)
			draw_colored_polygon(_unit_pts(c, g, [[0, -0.3], [-0.05, -0.18], [0.05, -0.18]]), socket) # nose
			for sx in [-0.07, 0.07]: # teeth gaps
				draw_line(c + Vector2(sx, -0.02) * g, c + Vector2(sx, 0.09) * g, socket, 0.7 * s)
			for sx in [-0.34, 0.0, 0.34]: # sparks of power between the skull and the hand
				draw_circle(c + Vector2(sx, 0.2 + absf(sx) * 0.15) * g, 0.045 * g + 0.2 * s, Color(lit, 0.85))
			# the hand, palm up: four fingers rising and a thumb on the side
			var finger_tops := [[-0.46, 0.42], [-0.16, 0.34], [0.14, 0.34], [0.44, 0.42]]
			for finger in finger_tops:
				var base := c + Vector2(finger[0], 0.62) * g
				var tip := c + Vector2(finger[0], finger[1]) * g
				draw_line(base, tip, lit, 0.24 * g, true)
				draw_circle(tip, 0.12 * g, lit)
			draw_line(c + Vector2(0.48, 0.74) * g, c + Vector2(0.78, 0.5) * g, lit, 0.24 * g, true) # thumb
			draw_circle(c + Vector2(0.78, 0.5) * g, 0.12 * g, lit)
			draw_colored_polygon(_unit_pts(c, g, [[-0.58, 0.58], [0.58, 0.58], [0.5, 0.86], [-0.5, 0.86]]), lit) # palm
		"regeneracao": # a healing cross inside a ring: the damage closes up again
			draw_arc(c, g * 0.86, 0, TAU, 28, col, 1.2 * s, true)
			draw_colored_polygon(_unit_pts(c, g, [[-0.14, -0.58], [0.14, -0.58], [0.14, -0.14], [0.58, -0.14], [0.58, 0.14],
				[0.14, 0.14], [0.14, 0.58], [-0.14, 0.58], [-0.14, 0.14], [-0.58, 0.14], [-0.58, -0.14], [-0.14, -0.14]]), lit)

func _unit_pts(c: Vector2, r: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + Vector2(p[0], p[1]) * r)
	return out

## True when the card has a static rule: a cost reduction, a "scale" effect or adjacent Armadura.
static func _has_always_on_rule(cd: Dictionary) -> bool:
	if cd.has("adjacent_armor"):
		return true
	for e in cd.get("effects", []):
		if not e.has("trigger") and not e.has("listen") and ["cost_reduction", "scale"].has(e.get("action", "")):
			return true
	return false

## True when the card has an automatic effect that waits for a condition (see the Condicional tag).
static func _has_conditional_rule(cd: Dictionary) -> bool:
	if cd.has("lethal_ward") or cd.has("death_ward") or cd.has("spell_discount"):
		return true
	for e in cd.get("effects", []):
		if e.has("listen"):
			return true
	return false

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
		elif CardDB.is_local(cd):
			kind += " · LOCAL"
		var spd: String = {"rapido": " · RÁPIDO", "instantaneo": " · INSTANTÂNEO"}.get(cd.get("speed", "lento"), "")
		out.append([[kind + spd, Color("#ffd27a") if spd != "" else Color(UITheme.TEXT, 0.6)]])
	# tags: keywords first, then trigger names (full text lives in the overlay)
	var tags: Array = []
	for dot_id in ["queimadura", "veneno", "sangramento"]:
		var dot_amount := dot_marker_count_of_view(inst, dot_id)
		if dot_amount > 0:
			tags.append(["%s %d" % [CardDB.keyword(dot_id)["name"], dot_amount], dot_badge_color(dot_id).lightened(0.18)])
	if inst.has("condemned_turn"):
		tags.append([CardDB.keyword("condenada")["name"], DOOM_COL.lightened(0.15)])
	if inst.has("frozen"):
		tags.append(["Congelada", FROST])
	if inst.has("stun_markers"):
		tags.append(["%s %d" % ["Atordoada", int(inst["stun_markers"])], STUN_COL.lightened(0.2)])
	if inst.get("spell_shield", false):
		tags.append([CardDB.keyword("escudo_feitico")["name"], Color("#c9a8ff")])
	for kw in kws:
		if kw == "ataque_duplo":
			continue # drawn below with its attack counter
		var tag_name: String = toxico_tag_of_view(cd, inst) if kw == "toxico" else CardDB.keyword(kw)["name"]
		tags.append([tag_name, Color("#9fe3ff") if kw == "escudo" else Color("#ffe7a0")])
	var armor_value := armor_of_view(cd, inst)
	if armor_value > 0:
		tags.append(["%s %d" % [CardDB.keyword("armadura")["name"], armor_value], Color("#c9d6e6")])
	# Rapidez keyword: Rapidez 0 goes unmentioned and 1-3 read as "Rapidez 1-3"
	# (a frozen unit has its Rapidez suppressed, so the tag is hidden until it thaws)
	var rapidez_level := int(inst.get("rapidez", cd.get("rapidez", 0)))
	if rapidez_level > 0 and not inst.has("frozen") and not inst.has("stun_markers"):
		tags.append(["%s %d" % [CardDB.keyword("rapidez")["name"], rapidez_level], Color("#ffd27a")])
	# Crítico X: the level reads on the tag ("Crítico 2"); the glossary in the overlay gives the chance
	var critico_level := critico_of_view(cd, inst)
	if critico_level > 0:
		tags.append(["%s %d" % [CardDB.keyword("critico")["name"], critico_level], Color("#ff9d6e")])
	# Ataque Duplo: printed, or earned in play (Vael at Crítico 4). On the board it counts the attacks
	# already made this turn ("Ataque Duplo 1/2"), so a tapped unit still showing it has one more swing
	if attacks_allowed_of_view(cd, inst) >= 2:
		var double_attack_name: String = CardDB.keyword("ataque_duplo")["name"]
		if inst.has("damage"):
			double_attack_name += " %d/2" % int(inst.get("attacks_made", 0))
		tags.append([double_attack_name, Color("#ff9d6e")])
	# Súbito (N): N is the full cost of summoning it at Rápido speed
	if cd.has("subito"):
		tags.append(["%s (%d)" % [CardDB.keyword("subito")["name"], int(cd["subito"])], Color("#ffd27a")])
	var seen := {}
	for e in cd.get("effects", []):
		var trg: String = e.get("trigger", "")
		if trg == "" or trg == "on_play" or seen.has(trg):
			continue
		# A trigger tied to one specific card (Luto de Vael: only Myrra dying) is too specific for
		# the generic tag "Aliado Morre"; the card text explains it instead
		if e.has("dying_card"):
			continue
		seen[trg] = true
		tags.append([CardDB.data()["triggers"][trg]["name"], TRIGGER_COL])
	# Constante: a rule that is always on (cost reductions, scaling, adjacent Armadura) and has no trigger of its own
	if not seen.has("constante") and _has_always_on_rule(cd):
		tags.append([CardDB.data()["triggers"]["constante"]["name"], TRIGGER_COL])
	# Condicional: the effect waits for a situation and fires by itself when it happens. Shown for any
	# "listen" effect and for artifacts whose rule lives only in the text (Câmara de Êxtase), so the
	# box on the card is not left empty
	if _has_conditional_rule(cd):
		var conditional_name: String = CardDB.data()["triggers"]["condicional"]["name"]
		# cards that limit their Condicional per turn (Seymour) show "(usados/limite)", live on the board
		if inst.has("conditional_uses_now"):
			conditional_name += " (%d/%d)" % [int(inst["conditional_uses_now"]), int(cd["conditional_uses_per_turn"])]
		tags.append([conditional_name, TRIGGER_COL])
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
	if out.is_empty() and cd.get("token", false):
		out.append([["FICHA", Color(UITheme.TEXT, 0.6)]])
	if out.is_empty():
		var rar :={"legendary": "LENDÁRIO", "champion": "CAMPEÃO", "epic": "UNIDADE ÉPICA", "common": "UNIDADE COMUM"}
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
	_window_vgrad(art,col.darkened(0.15), col.darkened(0.75))
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

## Snowflake outline with radius 1 around (0, 0): six arms, each with a pair of side branches. The branches
## of neighbouring arms overlap, and Godot cannot fill a polygon that crosses itself (it draws nothing), so
## every arm is its own simple polygon and they are merged into one clean outline. Built once, then reused.
static var _snowflake_cache := PackedVector2Array()

static func _snowflake_outline() -> PackedVector2Array:
	if not _snowflake_cache.is_empty():
		return _snowflake_cache
	# one arm pointing up, as (across, along) offsets from the centre: the left side going out, then the
	# mirrored right side coming back in. It starts at the centre so the six arms overlap there and merge.
	var half_width := 0.1
	var left_side := [
		Vector2(-half_width, 0.0), Vector2(-half_width, 0.30), Vector2(-0.34, 0.58), Vector2(-0.26, 0.68),
		Vector2(-half_width, 0.52), Vector2(-half_width, 0.84)]
	var arm_outline: Array = left_side.duplicate()
	arm_outline.append(Vector2(0, 1.0))
	for side_index in range(left_side.size() - 1, -1, -1):
		arm_outline.append(Vector2(-left_side[side_index].x, left_side[side_index].y))
	var outline := PackedVector2Array()
	for arm in 6:
		var arm_polygon := PackedVector2Array()
		for offset: Vector2 in arm_outline:
			arm_polygon.append(Vector2(offset.x, -offset.y).rotated(arm * TAU / 6))
		if outline.is_empty():
			outline = arm_polygon
			continue
		# merging can also return holes (clockwise); the outer outline is the piece that is not a hole
		for piece: PackedVector2Array in Geometry2D.merge_polygons(outline, arm_polygon):
			if not Geometry2D.is_polygon_clockwise(piece):
				outline = piece
				break
	_snowflake_cache = outline
	return _snowflake_cache

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
		"glacial": # snowflake: the unit outline (radius 1) scaled and moved to the requested spot
			var out := PackedVector2Array()
			for unit_point in _snowflake_outline():
				out.append(c + unit_point * r)
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
		"venenosa": # poison drop
			n = [[0, -1], [0.3, -0.45], [0.62, 0.05], [0.7, 0.4], [0.5, 0.8], [0.2, 0.98], [-0.2, 0.98], [-0.5, 0.8], [-0.7, 0.4], [-0.62, 0.05], [-0.3, -0.45]]
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

## Rarity gem on the bottom edge: white (common), amethyst (epic), orange (legendary),
## and the animated prismatic gem for champions (the rarest, see _champion_gem).
func _rarity_gem(c: Vector2, r: float, rarity: String, trim: Color) -> void:
	if rarity == "champion":
		_champion_gem(c, r, trim)
		return
	var col := Color("#f2f2f2")
	if rarity == "epic":
		col = Color("#9b4fd6")
	elif rarity == "legendary":
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

## Champion gem, rarer than the legendary one: only slightly bigger (it must not cover the card text), eight-sided (the other gems are hexagons),
## every facet cycles through the rainbow, a white glint sweeps across it every few seconds and
## little stars twinkle around it. Moves with `_t`, which keeps running on champion cards.
func _champion_gem(c: Vector2, r: float, trim: Color) -> void:
	c.y += r * 0.35 # sits lower on the frame so it stays clear of the card text
	r *= 1.2
	var outline := PackedVector2Array()
	for p in [[0, -1.15], [0.6, -0.7], [1.0, 0], [0.6, 0.7], [0, 1.15], [-0.6, 0.7], [-1.0, 0], [-0.6, -0.7]]:
		outline.append(c + Vector2(p[0], p[1]) * r)
	# soft pulsing aura behind the gem
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(c, r * (1.9 + 0.2 * pulse), Color(1, 1, 1, 0.10 + 0.08 * pulse))
	draw_colored_polygon(_grow(outline, c, 1.25), Color("#07060a"))
	# one triangle per side, each with its own hue that slowly rotates around the colour wheel;
	# the facets facing up-left are lighter, the ones facing down-right darker
	for i in outline.size():
		var hue := fposmod(_t * 0.2 + i / float(outline.size()) * 0.6, 1.0)
		var facing_light := 0.5 + 0.5 * cos((float(i) - 6.5) / outline.size() * TAU)
		var facet_color := Color.from_hsv(hue, 0.8, 0.6 + 0.4 * facing_light)
		draw_colored_polygon(PackedVector2Array([outline[i], outline[(i + 1) % outline.size()], c]), facet_color)
	draw_polyline(outline + PackedVector2Array([outline[0]]), trim, 1.0, true)
	# white glint sweeping left to right once every 2.8 s (the rest of the cycle it rests)
	var sweep := fposmod(_t, 2.8) / 0.9
	if sweep < 1.0:
		var band_x := lerpf(-1.4, 1.4, sweep) * r
		var band := PackedVector2Array([c + Vector2(band_x - 0.35 * r, -1.3 * r), c + Vector2(band_x + 0.1 * r, -1.3 * r),
			c + Vector2(band_x - 0.1 * r, 1.3 * r), c + Vector2(band_x - 0.55 * r, 1.3 * r)])
		_fill_clipped(band, outline, Color(1, 1, 1, 0.75))
	draw_circle(c + Vector2(-r * 0.3, -r * 0.45), r * 0.14, Color(1, 1, 1, 0.9))
	# twinkling four-point stars, each on its own rhythm
	for star in [[Vector2(-1.5, -0.8), 0.0], [Vector2(1.5, -1.1), 2.1], [Vector2(0.9, -1.9), 4.2]]:
		var twinkle := maxf(0.0, sin(_t * 4.0 + float(star[1])))
		if twinkle > 0.05:
			_sparkle(c + Vector2(star[0]) * r, r * 0.55 * twinkle, Color(1, 1, 1, 0.5 + 0.5 * twinkle))

## Four-pointed star (a "glint"), `radius` from the center to each tip.
func _sparkle(c: Vector2, radius: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var angle := i * TAU / 8.0 - PI / 2.0
		pts.append(c + Vector2(cos(angle), sin(angle)) * (radius if i % 2 == 0 else radius * 0.25))
	draw_colored_polygon(pts, col)

## Stand-in for the rarity gem on a ficha: a hollow, translucent diamond outline (nothing solid, nothing colored).
func _token_seal(c: Vector2, r: float, trim: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.8, 0), c + Vector2(0, r), c + Vector2(-r * 0.8, 0)])
	draw_colored_polygon(_grow(pts, c, 1.3), Color("#07060a"))
	draw_colored_polygon(pts, Color(0.85, 0.95, 1.0, 0.25))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(trim, 0.9), 1.0, true)

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
	if _chamfer_frame and rad >= FRAME_CORNER_MIN * _face_size.x / BASE.x:
		# never cut past the middle of a side, or the outline crosses itself
		var cut := minf(rad * 2.0, min(r.size.x, r.size.y) / 2)
		pts.append_array([Vector2(r.position.x + cut, r.position.y), Vector2(r.end.x - cut, r.position.y),
			Vector2(r.end.x, r.position.y + cut), Vector2(r.end.x, r.end.y - cut),
			Vector2(r.end.x - cut, r.end.y), Vector2(r.position.x + cut, r.end.y),
			Vector2(r.position.x, r.end.y - cut), Vector2(r.position.x, r.position.y + cut)])
		return pts
	var corners := [[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5],
		[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5]]
	for cn in corners:
		for i in 6:
			var a: float = cn[1] + PI / 2 * i / 5.0
			var point: Vector2 = cn[0] + Vector2(cos(a), sin(a)) * rad
			# a fully rounded pill makes neighbouring corners meet at the same point; repeated
			# points make the polygon impossible to fill (triangulation fails), so skip them
			if pts.is_empty() or not point.is_equal_approx(pts[pts.size() - 1]):
				pts.append(point)
	if pts.size() > 1 and pts[0].is_equal_approx(pts[pts.size() - 1]):
		pts.remove_at(pts.size() - 1)
	return pts

func _rrect_fill(r: Rect2, rad: float, col: Color) -> void:
	draw_colored_polygon(_rrect_pts(r, rad), col)

func _rrect_line(r: Rect2, rad: float, col: Color, w: float) -> void:
	var pts := _rrect_pts(r, rad)
	pts.append(pts[0])
	draw_polyline(pts, col, w, true)

## Same outline as _rrect_line but broken into dashes (dash / gap lengths in px), walked along the perimeter.
## `march` slides the dashes along the outline (px), so they can crawl around the card.
func _dashed_rrect_line(r: Rect2, rad: float, col: Color, w: float, dash: float, gap: float, march := 0.0) -> void:
	var pts := _rrect_pts(r, rad)
	pts.append(pts[0])
	var march_in_cycle := fposmod(march, dash + gap)
	var pen_down := march_in_cycle < dash
	var left_in_phase := dash - march_in_cycle if pen_down else dash + gap - march_in_cycle
	for i in pts.size() - 1:
		var from := pts[i]
		var to := pts[i + 1]
		var remaining := from.distance_to(to)
		while remaining > 0.0:
			var step: float = min(remaining, left_in_phase)
			var next := from.move_toward(to, step)
			if pen_down:
				draw_line(from, next, col, w, true)
			from = next
			remaining -= step
			left_in_phase -= step
			if left_in_phase <= 0.0:
				pen_down = not pen_down
				left_in_phase = dash if pen_down else gap

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

## Shape of the art window: a plain rectangle for units and spells, an arch (relic / stained-glass window)
## for artifacts, a round medallion (like a coin) for fichas. All of them fit inside the same rectangle,
## so the card takes the same room on the board whatever its kind.
func _art_window_pts(art: Rect2, kind: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match kind:
		"arch":
			var arch_height := art.size.y * ARCH_HEIGHT
			var half_width := art.size.x / 2
			var center_x := art.get_center().x
			var spring_y := art.position.y + arch_height # where the straight sides turn into the curve
			pts.append(Vector2(art.position.x, art.end.y))
			for i in 25:
				var angle := PI - PI * i / 24.0 # from the left side, over the top, down to the right side
				pts.append(Vector2(center_x + cos(angle) * half_width, spring_y - sin(angle) * arch_height))
			pts.append(art.end)
		"full": # champion units: the art fills the card inside its border, with the corners rounded to match the frame
			pts = _rrect_pts(art, (10.0 - FULL_ART_BORDER) * _face_size.x / BASE.x)
		"medallion":
			var radius := art.size.y / 2
			var center := art.get_center()
			for i in 48:
				var angle := TAU * i / 48.0
				pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
		_:
			pts = PackedVector2Array([art.position, Vector2(art.end.x, art.position.y), art.end, Vector2(art.position.x, art.end.y)])
	return pts

## Like _vgrad, but only the part of the band that falls inside the art window gets painted.
func _window_vgrad(band: Rect2, top: Color, bot: Color) -> void:
	var band_pts := PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)])
	for poly in Geometry2D.intersect_polygons(band_pts, _art_window):
		var cols := PackedColorArray()
		for p in poly:
			cols.append(top.lerp(bot, clamp((p.y - band.position.y) / band.size.y, 0.0, 1.0)))
		draw_polygon(poly, cols)

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

## Largest whole font size (up to `fs`) at which `t` fits in `max_w`. Whole sizes only: a fractional size
## is cut to an int when drawing, so the text would silently come out smaller than what was measured.
## Each step is measured for real (not scaled linearly) so a text is never shrunk more than needed.
func _fit(font: Font, t: String, fs: float, max_w: float) -> float:
	var fit_size := int(fs)
	while fit_size > 7 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fit_size).x > max_w:
		fit_size -= 1
	return float(fit_size)

## Text is placed on whole pixels: a glyph that lands between two pixels is smeared over both (blurry).
func _snap(p: Vector2) -> Vector2:
	return p.round()

## One panel line made of [text, color] segments joined by " · ", centered and shrunk to fit.
func _text_segments(font: Font, segs: Array, center: Vector2, fs: float, max_w: float) -> void:
	var sep := " · "
	fs = _fit(font, sep.join(segs.map(func(g): return g[0])), fs, max_w)
	var x := roundf(center.x - font.get_string_size(sep.join(segs.map(func(g): return g[0])), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x / 2)
	var ol: int = max(2, int(fs / 5))
	for i in segs.size():
		var parts := [[sep, Color(UITheme.TEXT, 0.5)]] if i > 0 else []
		parts.append(segs[i])
		for g in parts:
			var p := _snap(Vector2(x, center.y))
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
		# the block is one font size tall plus one leading per extra line (the last line needs no gap below)
		var block_height := fs + (lines.size() - 1) * fs * 1.08
		if block_height <= box.size.y and widest <= box.size.x:
			break
		fs -= 1
		lines = _wrap_words(font, t, fs, box.size.x)
	var lh := fs * 1.08
	var y := box.get_center().y - (lines.size() - 1) * lh / 2.0 + fs * 0.34
	# keyword names are found in the whole text (so "Escudo de Feitiço" split across two lines is
	# still found), then cut per line; if the wrap changed the spacing, search each line on its own
	var whole_ranges := keyword_ranges(t)
	var wrap_kept_text := " ".join(lines) == t
	var line_start := 0
	for ln in lines:
		var ranges: Array = []
		if wrap_kept_text:
			for span in whole_ranges:
				if span[1] > line_start and span[0] < line_start + ln.length():
					ranges.append([maxi(span[0] - line_start, 0), mini(span[1] - line_start, ln.length())])
		else:
			ranges = keyword_ranges(ln)
		_text_with_keywords(font, ln, ranges, Vector2(box.get_center().x, y), fs, col)
		line_start += ln.length() + 1
		y += lh

## Spell speed seal on the top edge of the art, between the cost orb and the essence badge:
## steel hourglass (lento), gold bolt (rápido) or cyan double bolt (instantâneo).
const SPEED_PILL_HEIGHT := 15.0 ## seal height at card scale 1 (was 12.4: the label read too small on phones)

func _speed_badge(c: Vector2, speed: String, s: float) -> void:
	var info: Array = {
		"lento": ["LENTO", Color("#a9b6c8")],
		"rapido": ["RÁPIDO", Color("#ffd27a")],
		"instantaneo": ["INSTANTÂNEO", Color("#7fe8ff")],
	}.get(speed, ["LENTO", Color("#a9b6c8")])
	var label: String = info[0]
	var col: Color = info[1]
	var f := UITheme.font("heavy")
	var icon_w := (13.0 if speed == "instantaneo" else 8.5) * s
	var pad := 4.0 * s
	var gap := 2.5 * s
	var fs := _fit(f, label, 9.5 * s, 68 * s - 2 * pad - icon_w - gap)
	var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	var w := 2 * pad + icon_w + gap + tw
	var pill := Rect2(c - Vector2(w / 2, SPEED_PILL_HEIGHT / 2 * s), Vector2(w, SPEED_PILL_HEIGHT * s))
	_rrect_fill(Rect2(pill.position + Vector2(0, 1.4 * s), pill.size), 7.5 * s, Color(0, 0, 0, 0.45))
	_rrect_fill(pill, 7.5 * s, Color("#0d0b12", 0.9))
	_rrect_line(pill, 7.5 * s, Color(col, 0.95), 1.1 * s)
	var ic := Vector2(pill.position.x + pad + icon_w / 2, c.y)
	var u := 5.6 * s # half-height of the icon
	match speed:
		"rapido":
			draw_colored_polygon(_unit_pts(ic, u, [[0.3, -1], [-0.6, 0.15], [-0.05, 0.15], [-0.3, 1], [0.6, -0.2], [0.05, -0.2]]), col)
		"instantaneo":
			for dx in [-0.5, 0.5]:
				draw_colored_polygon(_unit_pts(ic + Vector2(dx * 5.2 * s, 0), u, [[0.3, -1], [-0.6, 0.15], [-0.05, 0.15], [-0.3, 1], [0.6, -0.2], [0.05, -0.2]]), col)
		_:
			draw_colored_polygon(_unit_pts(ic, u, [[-0.65, -1], [0.65, -1], [0, 0]]), Color(col, 0.55))
			draw_colored_polygon(_unit_pts(ic, u, [[0, 0], [0.65, 1], [-0.65, 1]]), col)
			draw_line(ic + Vector2(-0.8, -1) * u, ic + Vector2(0.8, -1) * u, col, 1.0 * s)
			draw_line(ic + Vector2(-0.8, 1) * u, ic + Vector2(0.8, 1) * u, col, 1.0 * s)
	_text(f, label, Vector2(pill.position.x + pad + icon_w + gap + tw / 2, c.y + fs * 0.36), fs, col.lightened(0.25))

## Like _text, but the character ranges in `keyword_spans` are drawn in KEYWORD_COL.
func _text_with_keywords(font: Font, t: String, keyword_spans: Array, center: Vector2, fs: float, col: Color) -> void:
	var pieces: Array = [] ## [text, color]
	var cursor := 0
	for span in keyword_spans:
		if span[0] > cursor:
			pieces.append([t.substr(cursor, span[0] - cursor), col])
		pieces.append([t.substr(span[0], span[1] - span[0]), KEYWORD_COL])
		cursor = span[1]
	if cursor < t.length():
		pieces.append([t.substr(cursor), col])
	var total_width := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	var x := roundf(center.x - total_width / 2)
	for piece in pieces:
		var pos := _snap(Vector2(x, center.y))
		# thin outline: the rules panel is already dark, and a thick one smears small letters together
		draw_string_outline(font, pos, piece[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), max(1, int(fs / 7)), Color(0, 0, 0, 0.7))
		draw_string(font, pos, piece[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), piece[1])
		x += font.get_string_size(piece[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x

func _text(font: Font, t: String, center: Vector2, fs: float, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs)).x
	var pos := _snap(Vector2(center.x - w / 2, center.y))
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), max(2, int(fs / 5)), Color(0, 0, 0, 0.85))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), col)
