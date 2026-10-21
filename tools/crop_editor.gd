extends SceneTree
## Visual editor for the art crop of cards ("art_crop" in a card's JSON): moves and zooms the art inside the
## card window while you look at the card at its real size. The image files are never touched; only one
## line, `"art_crop": {"x": ..., "y": ..., "zoom": ...}`, is written under the card's "art" line.
## Needs a GPU (do not pass --headless).
##
##   Godot --path . -s tools/crop_editor.gd -- myrra yuki          (these cards)
##   Godot --path . -s tools/crop_editor.gd -- --rarity=common,epic --type=unit
##   Godot --path . -s tools/crop_editor.gd -- --all --missing      (only cards without an art_crop yet)
##
## Options: --all             every card that has art
##          --rarity=a,b      only these rarities (common, epic, legendary, champion)
##          --type=unit       only this card type
##          --missing         skip cards that already have an art_crop
##
## Keys:  arrows        move the picture inside the card (Shift = fine)
##        + / -         zoom in / out (Shift = fine)
##        R             back to the default crop (removes the art_crop line when saved)
##        Enter or S    save this card
##        Tab / Shift+Tab  (or N / P)  next / previous card
##        Esc           quit

const CARD_SCALE := 4.18 ## same scale Main uses for the big card view
const WINDOW_SIZE := Vector2i(1180, 800)
const CARD_POSITION := Vector2(30, 45)
const PREVIEW_POSITION := Vector2(580, 45)
const PREVIEW_AREA := Vector2(560, 700)
const MOVE_STEP := 0.02
const FINE_MOVE_STEP := 0.005
const ZOOM_STEP := 0.05
const FINE_ZOOM_STEP := 0.01
const MAX_ZOOM := 4.0
const BACKGROUND_COLOR := Color("#14161c")
const SOURCE_OUTLINE_COLOR := Color("#ffd24a")
const HELP_TEXT := "setas: mover a arte   +/-: zoom   Shift: ajuste fino   R: padrão   Enter/S: salvar   Tab/Shift+Tab: próxima/anterior   Esc: sair"

## The whole art file with the part the card shows outlined, so you see what is being cut off.
class SourcePreview extends Control:
	var art_texture: Texture2D
	var shown_part := Rect2() ## in texture pixels

	func _draw() -> void:
		if art_texture == null:
			return
		var texture_size := art_texture.get_size()
		var fit := minf(size.x / texture_size.x, size.y / texture_size.y)
		var drawn_size := texture_size * fit
		draw_texture_rect(art_texture, Rect2(Vector2.ZERO, drawn_size), false)
		var shown := Rect2(shown_part.position * fit, shown_part.size * fit)
		var shade := Color(0, 0, 0, 0.6)
		draw_rect(Rect2(0, 0, drawn_size.x, shown.position.y), shade)
		draw_rect(Rect2(0, shown.end.y, drawn_size.x, drawn_size.y - shown.end.y), shade)
		draw_rect(Rect2(0, shown.position.y, shown.position.x, shown.size.y), shade)
		draw_rect(Rect2(shown.end.x, shown.position.y, drawn_size.x - shown.end.x, shown.size.y), shade)
		draw_rect(shown, SOURCE_OUTLINE_COLOR, false, 2.0)

var card_ids: Array[String] = []
var wanted_rarities: Array[String] = []
var wanted_type := ""
var only_missing := false
var use_all := false
var explicit_ids: Array[String] = []

var current_index := 0
var unsaved_ids: Dictionary = {} ## card id -> true, edited but not written to its JSON yet

var card_holder: Control
var source_preview: SourcePreview
var title_label: Label

func _init() -> void:
	_read_arguments()
	_collect_card_ids()
	if card_ids.is_empty():
		print("Usage: -- <card_id> [more ids] | --all | --rarity=common,epic | --type=unit   [--missing]")
		quit(1)
		return
	_open_window.call_deferred()

func _read_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--all":
			use_all = true
		elif argument == "--missing":
			only_missing = true
		elif argument.begins_with("--rarity="):
			for rarity in argument.trim_prefix("--rarity=").split(","):
				wanted_rarities.append(rarity)
		elif argument.begins_with("--type="):
			wanted_type = argument.trim_prefix("--type=")
		elif CardDB.data()["cards"].has(argument):
			explicit_ids.append(argument)
		else:
			push_error("Unknown card id or option: %s" % argument)

## Cards that can be cropped (they have an art file), narrowed by the options.
func _collect_card_ids() -> void:
	var every_card_id: Array = CardDB.data()["cards"].keys()
	every_card_id.sort()
	for card_id in every_card_id:
		var card_data: Dictionary = CardDB.card(card_id)
		if CardView.texture(card_data.get("art", "")) == null:
			continue
		if only_missing and card_data.has("art_crop"):
			continue
		if explicit_ids.has(card_id):
			card_ids.append(card_id)
			continue
		var filtered := not wanted_rarities.is_empty() or wanted_type != ""
		if not use_all and not filtered:
			continue
		if not wanted_rarities.is_empty() and not wanted_rarities.has(card_data.get("rarity", "")):
			continue
		if wanted_type != "" and card_data.get("type", "") != wanted_type:
			continue
		card_ids.append(card_id)

# ------------------------------------------------------------------ Window

func _open_window() -> void:
	root.size = WINDOW_SIZE
	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	card_holder = Control.new()
	card_holder.position = CARD_POSITION
	background.add_child(card_holder)
	source_preview = SourcePreview.new()
	source_preview.position = PREVIEW_POSITION
	source_preview.size = PREVIEW_AREA
	background.add_child(source_preview)
	title_label = Label.new()
	title_label.position = Vector2(16, 8)
	title_label.modulate = Color(1, 1, 1, 0.75)
	background.add_child(title_label)
	var help_label := Label.new()
	help_label.text = HELP_TEXT
	help_label.position = Vector2(16, WINDOW_SIZE.y - 30)
	help_label.modulate = Color(1, 1, 1, 0.5)
	background.add_child(help_label)
	# The window has no node of its own to receive keys, so listen on the root window.
	root.window_input.connect(_on_window_input)
	_show_current_card()

func _show_current_card() -> void:
	for old_card in card_holder.get_children():
		old_card.queue_free()
	var card_id := card_ids[current_index]
	var card_data: Dictionary = CardDB.card(card_id)
	var card := CardView.new().setup(card_id, {}, CARD_SCALE)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_holder.add_child(card)
	var art_texture := CardView.texture(card_data.get("art", ""))
	source_preview.art_texture = art_texture
	source_preview.shown_part = _shown_part_of_art(card_id, art_texture)
	source_preview.queue_redraw()
	var crop: Dictionary = card_data.get("art_crop", {})
	var unsaved_mark := "   (não salvo)" if unsaved_ids.has(card_id) else ""
	title_label.text = "%s   (%d/%d)   x=%.3f  y=%.3f  zoom=%.2f%s" % [card_id, current_index + 1, card_ids.size(),
		float(crop.get("x", 0.5)), float(crop.get("y", 0.0)), float(crop.get("zoom", 1.0)), unsaved_mark]

## The part of the art file that the card window shows, same math the card itself uses.
func _shown_part_of_art(card_id: String, art_texture: Texture2D) -> Rect2:
	var window_size := Vector2(CardView.BASE.x - 14, 98)
	if CardDB.card(card_id).get("rarity", "") == "champion" and CardDB.card(card_id).get("type", "") == "unit":
		window_size = CardView.BASE - Vector2(2, 2) * CardView.FULL_ART_BORDER # full-art champions: nearly the whole card
	return CardView.art_source_rect(art_texture.get_size(), window_size, CardDB.card(card_id).get("art_crop", {}))

# ----------------------------------------------------------------- Editing

func _on_window_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var fine: bool = event.shift_pressed
	var move_step := FINE_MOVE_STEP if fine else MOVE_STEP
	var zoom_step := FINE_ZOOM_STEP if fine else ZOOM_STEP
	match event.keycode:
		KEY_ESCAPE:
			if not unsaved_ids.is_empty():
				print("Quitting with unsaved cards: ", unsaved_ids.keys())
			quit()
		# arrows drag the picture, so the crop window moves the opposite way
		KEY_LEFT:
			_adjust_crop(move_step, 0.0, 0.0)
		KEY_RIGHT:
			_adjust_crop(-move_step, 0.0, 0.0)
		KEY_UP:
			_adjust_crop(0.0, move_step, 0.0)
		KEY_DOWN:
			_adjust_crop(0.0, -move_step, 0.0)
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			_adjust_crop(0.0, 0.0, zoom_step)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_adjust_crop(0.0, 0.0, -zoom_step)
		KEY_R:
			_set_crop(card_ids[current_index], {})
		KEY_ENTER, KEY_KP_ENTER, KEY_S:
			_save_card(card_ids[current_index])
		KEY_TAB:
			_step_card(-1 if fine else 1)
		KEY_N:
			_step_card(1)
		KEY_P:
			_step_card(-1)

func _step_card(direction: int) -> void:
	current_index = (current_index + direction + card_ids.size()) % card_ids.size()
	_show_current_card()

func _adjust_crop(delta_x: float, delta_y: float, delta_zoom: float) -> void:
	var card_id := card_ids[current_index]
	var crop: Dictionary = CardDB.card(card_id).get("art_crop", {})
	_set_crop(card_id, {
		"x": snappedf(clampf(float(crop.get("x", 0.5)) + delta_x, 0.0, 1.0), 0.001),
		"y": snappedf(clampf(float(crop.get("y", 0.0)) + delta_y, 0.0, 1.0), 0.001),
		"zoom": snappedf(clampf(float(crop.get("zoom", 1.0)) + delta_zoom, 1.0, MAX_ZOOM), 0.01),
	})

## Changes the crop in memory (the card redraws at once); an empty `crop` removes it.
func _set_crop(card_id: String, crop: Dictionary) -> void:
	if crop.is_empty():
		CardDB.card(card_id).erase("art_crop")
	else:
		CardDB.card(card_id)["art_crop"] = crop
	unsaved_ids[card_id] = true
	_show_current_card()

# ------------------------------------------------------------------ Saving

func _save_card(card_id: String) -> void:
	var file_path := _json_path_of(card_id)
	if file_path == "":
		push_error("Could not find the JSON file of %s" % card_id)
		return
	var rewritten := _rewrite_card_json(FileAccess.get_file_as_string(file_path), CardDB.card(card_id).get("art_crop", {}))
	if rewritten == "":
		return
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(rewritten)
	file.close()
	unsaved_ids.erase(card_id)
	print("saved ", file_path)
	_show_current_card()

func _json_path_of(card_id: String) -> String:
	for essence_id in CardDB.data()["essences"]:
		var file_path := "res://data/cards/%s/%s.json" % [essence_id, card_id]
		if FileAccess.file_exists(file_path):
			return file_path
	return ""

## The card's JSON text with its one-line "art_crop" replaced (or removed when `crop` is empty), changing
## nothing else in the file. Returns "" when the file has an art_crop written over several lines.
func _rewrite_card_json(text: String, crop: Dictionary) -> String:
	var line_break := "\r\n" if text.contains("\r\n") else "\n"
	var kept: PackedStringArray = []
	for line in text.replace("\r\n", "\n").split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("\"art_crop\""):
			if trimmed.contains("{") and not trimmed.contains("}"):
				push_error("art_crop is written over several lines in this file; fix it by hand first")
				return ""
			# the old line was the last key: the line before it must lose its comma
			if not trimmed.ends_with(",") and not kept.is_empty():
				kept[kept.size() - 1] = kept[kept.size() - 1].trim_suffix(",")
			continue
		kept.append(line)
	if not crop.is_empty():
		for index in kept.size():
			if not kept[index].strip_edges().begins_with("\"art\":"):
				continue
			var indent := kept[index].substr(0, kept[index].length() - kept[index].strip_edges(true, false).length())
			var crop_line := indent + "\"art_crop\": {\"x\": %s, \"y\": %s, \"zoom\": %s}" % [
				str(snappedf(float(crop.get("x", 0.5)), 0.001)), str(snappedf(float(crop.get("y", 0.0)), 0.001)),
				str(snappedf(float(crop.get("zoom", 1.0)), 0.01))]
			if kept[index].ends_with(","):
				crop_line += ","
			else:
				kept[index] += "," # "art" was the last key, so it now has a key after it
			kept.insert(index + 1, crop_line)
			break
	return line_break.join(kept)
