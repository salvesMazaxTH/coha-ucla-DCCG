extends RefCounted
## The "Modificadores" box of the card overlay: every change to a unit's stats (Ataque, Vida, Armadura,
## Crítico, Rapidez), which card caused it and how long it lasts. The very same change from the very same
## card is stacked into one row with a "×N" badge, so three copies of one blessing read as one line.
##
## Where the rows come from (all inside the unit's instance dictionary, see Card.to_dict):
##   "equipment"        -> what each worn equipment gave ("grant"), lasts while it is worn
##   "stat_sources"     -> the engine's record of buffs and debuffs (Card.record_stat_change)
##   "constant_sources" -> auras and other Constante bonuses, worked out live (GameState.constant_sources_of)
## Whatever the records can't explain (an older effect that doesn't record its source yet) still shows,
## as "Outros efeitos", so the rows always add up to the numbers printed on the card.

const STATS := ["atk", "hp", "armor", "critico", "rapidez"]
const STAT_SHORT_NAMES := {"atk": "ATQ", "hp": "VIDA", "armor": "ARM", "critico": "CRÍT", "rapidez": "RAP"}
const STAT_COLORS := {"atk": Color("#e0644f"), "hp": Color("#48c27a"), "armor": Color("#9fb4c8"),
		"critico": Color("#f0a640"), "rapidez": Color("#7fd3f0")}

## How long a change lasts, in the order the rows are listed (the longest-lasting first).
const DURATION_ORDER := ["equipment", "", "constant", "next_turn", "end_turn"]
const DURATION_LABELS := {"equipment": "Equipamento", "": "Permanente", "constant": "Constante",
		"next_turn": "Até seu turno", "end_turn": "Fim do turno"}
const DURATION_COLORS := {"equipment": Color("#c9d3dd"), "": Color("#e8c25a"), "constant": Color("#c79bff"),
		"next_turn": Color("#7fc8ff"), "end_turn": Color("#ffb066")}

const BUFF_COLOR := Color("#a8ffa0")
const DEBUFF_COLOR := Color("#ff8a80")
const UNKNOWN_SOURCE := "?" ## source of the leftover row that no record explains
const NODE_NAME := "StatModifiersPanel" ## Main looks the panel up by this name (to hide it with the base card)

const ROW_HEIGHT := 60.0
const ROW_GAP := 6.0
const NAME_FONT_SIZE := 19
const CHIP_FONT_SIZE := 16
const DURATION_FONT_SIZE := 14

## The unit's modifier rows (identical changes stacked), or [] when it has none or is not a board unit.
static func rows_for(card_id: String, instance: Dictionary) -> Array:
	if not instance.has("atk"): # not a unit on the board: nothing can have changed it
		return []
	return group_rows(collect_changes(card_id, instance))

## Adds the rows as one column to `parent`, top-left corner at `top_left`, `width` wide, never taller than
## `max_height` (rows that don't fit fold into one "+N outras fontes" line). Returns the column.
static func add_to(parent: Control, top_left: Vector2, width: float, max_height: float, rows: Array) -> Control:
	var rows_that_fit := maxi(1, int(floor((max_height + ROW_GAP) / (ROW_HEIGHT + ROW_GAP))))
	if rows.size() > rows_that_fit:
		rows = _fold_extra_rows(rows, rows_that_fit)
	var column := Control.new()
	column.name = NODE_NAME
	column.position = top_left
	column.size = Vector2(width, rows.size() * (ROW_HEIGHT + ROW_GAP) - ROW_GAP)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(column)
	var row_y := 0.0
	for row in rows:
		column.add_child(_row(Vector2(0, row_y), width, row))
		row_y += ROW_HEIGHT + ROW_GAP
	return column

## Every stat change on the unit as {"source", "until", "changes": {stat: amount}}, one per effect.
static func collect_changes(card_id: String, instance: Dictionary) -> Array:
	var changes_list: Array = []
	var recorded := {} # duration -> {stat: total the records explain}
	for duration in DURATION_ORDER:
		recorded[duration] = {}

	for worn in instance.get("equipment", []):
		_add_record(changes_list, recorded, String(worn["card_id"]), "equipment", worn.get("grant", {}))
	for record in instance.get("stat_sources", []):
		_add_record(changes_list, recorded, String(record.get("source", "")), String(record.get("until", "")), record)
	for record in instance.get("constant_sources", []):
		_add_record(changes_list, recorded, String(record.get("source", "")), "constant", record)

	# what the unit's numbers really are, per duration, to find what the records leave unexplained
	var printed := CardDB.card_for(card_id, instance)
	var equipment_total: Dictionary = recorded["equipment"]
	var actual := {
		"": {
			"atk": int(instance.get("atk", 0)) - int(printed.get("atk", 0)) - int(equipment_total.get("atk", 0)),
			"hp": int(instance.get("hp", 0)) - int(printed.get("hp", 0)) - int(equipment_total.get("hp", 0)),
			"armor": int(instance.get("armor", 0)) - int(printed.get("armor", 0)) - int(equipment_total.get("armor", 0)),
			"critico": int(instance.get("critico", 0)) - int(printed.get("critico", 0)) - int(equipment_total.get("critico", 0)),
			"rapidez": int(instance.get("rapidez", 0)) - int(printed.get("rapidez", 0)) - int(equipment_total.get("rapidez", 0)),
		},
		"end_turn": {
			"atk": int(instance.get("temp_atk", 0)), "hp": int(instance.get("temp_hp", 0)),
			"armor": int(instance.get("turn_armor", 0)), "critico": int(instance.get("temp_critico", 0)),
		},
		"next_turn": {
			"atk": int(instance.get("temp_atk_until_next_turn", 0)), "hp": int(instance.get("temp_hp_until_next_turn", 0)),
			"armor": int(instance.get("temp_armor", 0)),
		},
		"constant": {"atk": int(instance.get("bonus_atk", 0)), "hp": int(instance.get("bonus_hp", 0))},
	}
	if instance.has("armor_total"): # Armadura from auras, the graveyard and neighbours is only in the live total
		actual["constant"]["armor"] = int(instance["armor_total"]) - int(instance.get("armor", 0)) \
				- int(instance.get("temp_armor", 0)) - int(instance.get("turn_armor", 0))
	for duration in actual:
		var leftover := {}
		for stat in actual[duration]:
			var unexplained: int = int(actual[duration][stat]) - int(recorded[duration].get(stat, 0))
			if unexplained != 0:
				leftover[stat] = unexplained
		if not leftover.is_empty():
			changes_list.append({"source": UNKNOWN_SOURCE, "until": duration, "changes": leftover})
	return changes_list

## Adds one record (any dictionary holding stat amounts) to the list and to the per-duration totals.
static func _add_record(changes_list: Array, recorded: Dictionary, source: String, duration: String, record: Dictionary) -> void:
	if not recorded.has(duration):
		recorded[duration] = {}
	var changes := {}
	for stat in STATS:
		var amount := int(record.get(stat, 0))
		if amount != 0:
			changes[stat] = amount
			recorded[duration][stat] = int(recorded[duration].get(stat, 0)) + amount
	if not changes.is_empty():
		changes_list.append({"source": source, "until": duration, "changes": changes})

## Stacks identical changes (same card, same duration, same amounts) into one row with a count,
## and sorts the rows by duration, longest-lasting first.
static func group_rows(changes_list: Array) -> Array:
	var rows_by_key := {}
	var rows: Array = []
	for change in changes_list:
		var key := "%s|%s|%s" % [change["source"], change["until"], str(change["changes"])]
		if rows_by_key.has(key):
			rows_by_key[key]["count"] += 1
			continue
		var row := {"source": change["source"], "until": change["until"], "changes": change["changes"], "count": 1}
		rows_by_key[key] = row
		rows.append(row)
	rows.sort_custom(func(a, b): return _duration_rank(a["until"]) < _duration_rank(b["until"]))
	return rows

static func _duration_rank(duration: String) -> int:
	var rank := DURATION_ORDER.find(duration)
	return rank if rank >= 0 else DURATION_ORDER.size()

## Keeps the first rows and sums the rest into one closing row, so the column never grows past the card.
static func _fold_extra_rows(rows: Array, row_limit: int) -> Array:
	var kept := rows.slice(0, row_limit - 1)
	var folded_changes := {}
	var folded_sources := 0
	for row in rows.slice(row_limit - 1):
		folded_sources += 1
		for stat in row["changes"]:
			folded_changes[stat] = int(folded_changes.get(stat, 0)) + int(row["changes"][stat]) * int(row["count"])
	kept.append({"source": "", "until": "folded", "changes": folded_changes, "count": 1,
			"label": "+%d outras fontes" % folded_sources})
	return kept

## One row, two lines: the source card's name (and "×N" when the same change stacks) on top; below it the
## stat changes as green (buff) / red (debuff) chips and how long they last. The coloured stripe on the
## left repeats the duration, so the column reads at a glance.
static func _row(top_left: Vector2, width: float, row: Dictionary) -> Control:
	var duration: String = row["until"]
	var duration_color: Color = DURATION_COLORS.get(duration, UITheme.TEXT_DIM)
	var background := Panel.new()
	background.position = top_left
	background.size = Vector2(width, ROW_HEIGHT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row_style := UITheme.box(Color("#15111c", 0.92), 8)
	row_style.border_width_left = 4
	row_style.border_color = Color(duration_color, 0.9)
	background.add_theme_stylebox_override("panel", row_style)
	var inner_left := 12.0
	var inner_width := width - inner_left - 8.0

	var name_line := HBoxContainer.new()
	name_line.position = Vector2(inner_left, 3)
	name_line.size = Vector2(inner_width, 27)
	name_line.add_theme_constant_override("separation", 6)
	name_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(name_line)
	var source_name := _label(row.get("label", source_label(String(row["source"]))), UITheme.font("bold"), NAME_FONT_SIZE,
			UITheme.TEXT if row["source"] != UNKNOWN_SOURCE else UITheme.TEXT_DIM)
	source_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	source_name.clip_text = true
	source_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_line.add_child(source_name)
	if int(row["count"]) > 1:
		var badge := _chip(Color(UITheme.GOLD, 0.22), UITheme.GOLD)
		badge.add_child(_label("×%d" % int(row["count"]), UITheme.font("heavy"), CHIP_FONT_SIZE, UITheme.GOLD_LIGHT))
		name_line.add_child(badge)

	var change_line := HBoxContainer.new()
	change_line.position = Vector2(inner_left, 31)
	change_line.size = Vector2(inner_width, 25)
	change_line.add_theme_constant_override("separation", 5)
	change_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(change_line)
	for stat in STATS:
		if not row["changes"].has(stat):
			continue
		var amount := int(row["changes"][stat])
		var sign_color := BUFF_COLOR if amount > 0 else DEBUFF_COLOR
		var chip := _chip(Color(sign_color, 0.13), Color(sign_color, 0.5))
		chip.add_child(_label("%s%d %s" % ["+" if amount > 0 else "−", absi(amount), STAT_SHORT_NAMES[stat]],
				UITheme.font("heavy"), CHIP_FONT_SIZE, sign_color))
		change_line.add_child(chip)
	if DURATION_LABELS.has(duration):
		# takes whatever room the chips leave; on a very narrow column it is cut short, the stripe still tells it
		var duration_label := _label(DURATION_LABELS[duration], UITheme.font("body"), DURATION_FONT_SIZE, duration_color)
		duration_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		duration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		duration_label.clip_text = true
		duration_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		change_line.add_child(duration_label)
	return background

## The name shown for a source: the card's name, "Poder do Líder" for a Leader ability.
static func source_label(source: String) -> String:
	if source == UNKNOWN_SOURCE:
		return "Outros efeitos"
	if source == "":
		return "Poder do Líder"
	if CardDB.data()["cards"].has(source):
		return String(CardDB.card(source)["name"])
	return source

static func _label(text: String, font: Font, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## A small rounded pill that holds one label (stat change or ×N badge).
static func _chip(background_color: Color, border_color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var style := UITheme.box(background_color, 7, border_color, 1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", style)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip
