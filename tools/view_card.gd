extends SceneTree
## Shows a single card exactly as the game draws it (the same CardView as the big card view),
## either in a window or saved as a PNG. Needs a GPU (do not pass --headless).
##
## Window (Left/Right arrows switch card, Esc closes):
##   Godot --path . -s tools/view_card.gd -- dona_gertrudes_fura_fila
##   Godot --path . -s tools/view_card.gd -- myrra vael --scale=3
##   Godot --path . -s tools/view_card.gd -- --all
##
## PNG (one file per card, transparent background, saved in card_renders/ unless --out is given):
##   Godot --path . -s tools/view_card.gd -- myrra --png
##   Godot --path . -s tools/view_card.gd -- --all --png --out=C:/some/folder
##
## Options: --scale=N  card size (default 4.18, the size of the in-game big card view)
##          --png      save images instead of opening the window
##          --out=DIR  folder for --png (default: card_renders/ inside the project)

const DEFAULT_SCALE := 4.18 ## same scale Main uses for the big card view
const PNG_MARGIN := 40 ## transparent room around the card so its drop shadow is not cut off

var scale_factor := DEFAULT_SCALE
var card_ids: Array[String] = []
var save_png := false
var output_folder := ""

var viewer_background: ColorRect
var viewer_card_holder: Control
var viewer_title: Label
var viewer_index := 0

func _init() -> void:
	_read_arguments()
	if card_ids.is_empty():
		print("Usage: -- <card_id> [more ids] | --all   [--png] [--scale=4.18] [--out=DIR]")
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

# ---------------------------------------------------------------- PNG mode

func _save_all_pngs() -> void:
	if output_folder == "":
		output_folder = ProjectSettings.globalize_path("res://card_renders")
	DirAccess.make_dir_recursive_absolute(output_folder)
	for card_id in card_ids:
		var card := _build_card(card_id)
		var viewport := SubViewport.new()
		viewport.transparent_bg = true
		viewport.size = Vector2i(card.size) + Vector2i(PNG_MARGIN * 2, PNG_MARGIN * 2)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		card.position = Vector2(PNG_MARGIN, PNG_MARGIN)
		viewport.add_child(card)
		root.add_child(viewport)
		# Two frames so the card has drawn once and its art texture has loaded.
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var file_path := "%s/%s.png" % [output_folder, card_id]
		viewport.get_texture().get_image().save_png(file_path)
		print("saved ", file_path)
		viewport.queue_free()
	quit()

# ------------------------------------------------------------- Window mode

func _open_viewer() -> void:
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
	var card := _build_card(card_id)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var window_size := Vector2(root.size)
	card.position = ((window_size - card.size) / 2.0).round()
	viewer_card_holder.add_child(card)
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
