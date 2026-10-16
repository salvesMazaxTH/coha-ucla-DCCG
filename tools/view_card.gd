extends SceneTree
## Shows a card exactly as the game shows it when you click it in a match: the big card plus the
## full text panel (rules, keyword glossary, flavor), built by the same CardOverlay code Main uses.
## Either in a window or saved as a PNG. Needs a GPU (do not pass --headless).
## With --card-only it shows just the card art (the same CardView), without the text panel.
##
## Window (Left/Right arrows switch card, Esc closes):
##   Godot --path . -s tools/view_card.gd -- dona_gertrudes_fura_fila
##   Godot --path . -s tools/view_card.gd -- myrra vael --scale=3
##   Godot --path . -s tools/view_card.gd -- --all
##
## PNG (one file per card, saved in card_renders/ unless --out is given;
## <id>_overlay.png for the overlay, <id>.png with a transparent background for --card-only):
##   Godot --path . -s tools/view_card.gd -- myrra --png
##   Godot --path . -s tools/view_card.gd -- --all --png --out=C:/some/folder
##
## Options: --card-only  just the card, no overlay and no text panel
##          --scale=N    card size, only with --card-only (default 4.18, the in-game big card size)
##          --png        save images instead of opening the window
##          --out=DIR    folder for --png (default: card_renders/ inside the project)

const DEFAULT_SCALE := 4.18 ## same scale Main uses for the big card view
const PNG_MARGIN := 40 ## transparent room around the card so its drop shadow is not cut off (--card-only)
const STAGE_SIZE := Vector2(1600, 1034) ## the logical size Main's stage has on a 16:10 screen
const OVERLAY_DIM := Color(0, 0, 0, 0.82) ## same dim Main puts behind the overlay
const TABLE_COLOR := Color("#14161c") ## stands in for the table that shows through the dim

var scale_factor := DEFAULT_SCALE
var card_ids: Array[String] = []
var save_png := false
var card_only := false
var output_folder := ""

var viewer_background: ColorRect
var viewer_card_holder: Control
var viewer_title: Label
var viewer_index := 0

func _init() -> void:
	_read_arguments()
	if card_ids.is_empty():
		print("Usage: -- <card_id> [more ids] | --all   [--png] [--card-only] [--scale=4.18] [--out=DIR]")
		quit(1)
		return
	if save_png:
		_save_all_pngs.call_deferred()
	else:
		_open_viewer.call_deferred()

## Reads the arguments after the "--" separator: card ids and the --options.
func _read_arguments() -> void:
	var every_card_id: Array = CardDB.data()["cards"].keys()
	every_card_id.sort()
	for argument in OS.get_cmdline_user_args():
		if argument == "--all":
			for each_id in every_card_id:
				card_ids.append(each_id)
		elif argument == "--png":
			save_png = true
		elif argument == "--card-only":
			card_only = true
		elif argument.begins_with("--scale="):
			scale_factor = float(argument.trim_prefix("--scale="))
		elif argument.begins_with("--out="):
			output_folder = argument.trim_prefix("--out=")
		elif every_card_id.has(argument):
			card_ids.append(argument)
		else:
			push_error("Unknown card id or option: %s" % argument)

func _build_card(card_id: String) -> CardView:
	return CardView.new().setup(card_id, {}, scale_factor)

## The card overlay as in a match: table color, dim, big card and text panel, on a stage-sized Control.
func _build_overlay_stage(card_id: String) -> Control:
	var stage := Control.new()
	stage.size = STAGE_SIZE
	stage.theme = UITheme.make() # the same theme Main sets, so fonts and rich text look identical
	var table := ColorRect.new()
	table.color = TABLE_COLOR
	table.size = STAGE_SIZE
	stage.add_child(table)
	var dim := ColorRect.new()
	dim.color = OVERLAY_DIM
	dim.size = STAGE_SIZE
	stage.add_child(dim)
	CardOverlay.build(dim, STAGE_SIZE.x, card_id)
	# In game the text panel is 640 tall and scrolls with the wheel; here it grows to the bottom
	# of the stage so long cards (Leaders with their note) show everything at once.
	var text_panel := dim.get_child(dim.get_child_count() - 1) as RichTextLabel
	text_panel.size.y = STAGE_SIZE.y - text_panel.position.y - 20.0
	return stage

# ---------------------------------------------------------------- PNG mode

func _save_all_pngs() -> void:
	if output_folder == "":
		output_folder = ProjectSettings.globalize_path("res://card_renders")
	DirAccess.make_dir_recursive_absolute(output_folder)
	for card_id in card_ids:
		var viewport := SubViewport.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var file_name := card_id
		if card_only:
			var card := _build_card(card_id)
			viewport.transparent_bg = true
			viewport.size = Vector2i(card.size) + Vector2i(PNG_MARGIN * 2, PNG_MARGIN * 2)
			card.position = Vector2(PNG_MARGIN, PNG_MARGIN)
			viewport.add_child(card)
		else:
			viewport.size = Vector2i(STAGE_SIZE)
			viewport.add_child(_build_overlay_stage(card_id))
			file_name += "_overlay"
		root.add_child(viewport)
		# Two frames so the card has drawn once and its art texture has loaded.
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var file_path := "%s/%s.png" % [output_folder, file_name]
		viewport.get_texture().get_image().save_png(file_path)
		print("saved ", file_path)
		viewport.queue_free()
	quit()

# ------------------------------------------------------------- Window mode

func _open_viewer() -> void:
	if not card_only:
		# Same trick as the game: a fixed logical stage that scales to fit whatever the window size is.
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(STAGE_SIZE)
		root.size = Vector2i(1280, 826)
	viewer_background = ColorRect.new()
	viewer_background.color = Color("#14161c")
	viewer_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(viewer_background)
	viewer_card_holder = Control.new()
	viewer_card_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewer_background.add_child(viewer_card_holder)
	viewer_title = Label.new()
	viewer_title.position = Vector2(16, 8)
	viewer_title.modulate = Color(1, 1, 1, 0.55)
	viewer_background.add_child(viewer_title)
	# The window has no node of its own to receive keys, so listen on the root window.
	root.window_input.connect(_on_window_input)
	_show_current_card()

func _show_current_card() -> void:
	for old_card in viewer_card_holder.get_children():
		old_card.queue_free()
	var card_id := card_ids[viewer_index]
	if card_only:
		var card := _build_card(card_id)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var window_size := Vector2(root.size)
		card.position = ((window_size - card.size) / 2.0).round()
		viewer_card_holder.add_child(card)
	else:
		var stage := _build_overlay_stage(card_id)
		stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewer_card_holder.add_child(stage)
	viewer_title.text = "%s   (%d/%d)" % [card_id, viewer_index + 1, card_ids.size()]

func _on_window_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match event.keycode:
		KEY_ESCAPE:
			quit()
		KEY_RIGHT:
			viewer_index = (viewer_index + 1) % card_ids.size()
			_show_current_card()
		KEY_LEFT:
			viewer_index = (viewer_index - 1 + card_ids.size()) % card_ids.size()
			_show_current_card()
