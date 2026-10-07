class_name UITheme
extends RefCounted
## Shared look: fonts, palette and the Theme applied to the whole table.

const GOLD := Color("#e8c25a")
const GOLD_LIGHT := Color("#fff0b8")
const GOLD_DARK := Color("#8a6a24")
const INK := Color("#0b0a10")
const PANEL := Color(0.06, 0.055, 0.085, 0.86)
const TEXT := Color("#ece6d6")
const TEXT_DIM := Color(0.93, 0.9, 0.84, 0.55)
const HP := Color("#e8484a")
const MOMENTUM := Color("#f5c518")

static var _fonts := {}

## kind: "title" (Cinzel, engraved caps), "body", "bold", "heavy" (Alegreya Sans)
static func font(kind := "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font
	match kind:
		"title", "title_bold":
			var v := FontVariation.new()
			v.base_font = load("res://assets/fonts/Cinzel.ttf")
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800 if kind == "title_bold" else 600}
			v.spacing_glyph = 1
			f = v
		"bold":
			f = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
		"heavy":
			f = load("res://assets/fonts/AlegreyaSans-ExtraBold.ttf")
		_:
			f = load("res://assets/fonts/AlegreyaSans-Regular.ttf")
	_fonts[kind] = f
	return f

static func box(bg: Color, radius := 8, border := Color.TRANSPARENT, border_w := 1, shadow := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	if border.a > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = Color(0, 0, 0, 0.55)
		sb.shadow_offset = Vector2(0, shadow * 0.4)
	return sb

## Glassy dark panel with a thin gold rim, used by every HUD block.
static func panel(radius := 10) -> StyleBoxFlat:
	var sb := box(PANEL, radius, Color(GOLD, 0.35), 1, 10)
	sb.set_content_margin_all(12)
	return sb

static func make() -> Theme:
	var t := Theme.new()
	t.default_font = font("bold")
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)

	# Button: dark lacquer with a gold rim
	_button_styles(t, "Button",
		Color("#1d1a26"), Color(GOLD, 0.55), Color("#2a2536"), GOLD, Color("#141219"), TEXT, GOLD_LIGHT)
	# PrimaryButton: polished gold, dark ink text (end turn, confirm, menu choices)
	t.set_type_variation("PrimaryButton", "Button")
	_button_styles(t, "PrimaryButton",
		Color("#c99a3a"), GOLD_LIGHT, Color("#e2b453"), Color.WHITE, Color("#9c7428"), Color("#1a1206"), Color("#1a1206"))
	t.set_font("font", "PrimaryButton", font("title_bold"))
	t.set_font_size("font_size", "PrimaryButton", 17)

	t.set_stylebox("panel", "Panel", panel())
	t.set_stylebox("panel", "PanelContainer", panel())
	var tip := box(Color("#14121b"), 6, Color(GOLD, 0.5), 1, 6)
	tip.set_content_margin_all(10)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", font("body"))
	t.set_font_size("font_size", "TooltipLabel", 15)
	t.set_font("normal_font", "RichTextLabel", font("body"))
	t.set_font("bold_font", "RichTextLabel", font("heavy"))
	t.set_color("default_color", "RichTextLabel", TEXT)
	return t

static func _button_styles(t: Theme, type: String, bg: Color, rim: Color, bg_hover: Color, rim_hover: Color, bg_press: Color, fg: Color, fg_hover: Color) -> void:
	var normal := box(bg, 7, rim, 2, 6)
	var hover := box(bg_hover, 7, rim_hover, 2, 10)
	hover.shadow_color = Color(GOLD, 0.35)
	var press := box(bg_press, 7, rim, 2, 2)
	var off := box(Color(bg.darkened(0.5), 0.75), 7, Color(0.5, 0.5, 0.5, 0.25), 2, 0)
	for sb in [normal, hover, press, off]:
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, press)
	t.set_stylebox("disabled", type, off)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg_hover)
	t.set_color("font_pressed_color", type, fg)
	t.set_color("font_focus_color", type, fg)
	t.set_color("font_disabled_color", type, Color(0.6, 0.6, 0.6, 0.45))
