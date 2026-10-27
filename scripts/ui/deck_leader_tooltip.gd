class_name DeckLeaderTooltip
extends RefCounted
## Hover and touch-hold identification for deck tiles whose art is the primary Leader cue.

static func attach(tile: Control, leader_name: String) -> void:
	tile.tooltip_text = "Líder: %s" % leader_name
	var state := {"holding": false, "long": false, "press_id": 0}
	tile.gui_input.connect(func(event: InputEvent) -> void:
		var pressed := false
		var released := false
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			pressed = event.pressed
			released = not event.pressed
		elif event is InputEventScreenTouch:
			pressed = event.pressed
			released = not event.pressed
		if not CardView.touch_ui():
			return
		if pressed:
			state["holding"] = true
			state["long"] = false
			state["press_id"] = int(state["press_id"]) + 1
			var press_id: int = state["press_id"]
			tile.get_tree().create_timer(0.45).timeout.connect(func() -> void:
				if is_instance_valid(tile) and state["holding"] and int(state["press_id"]) == press_id:
					state["long"] = true
					tile.set_meta("leader_tooltip_consumed_tap", true)
					_show_touch_tooltip(tile, leader_name))
		elif released:
			state["holding"] = false)

static func consume_tap(tile: Control) -> bool:
	if not tile.has_meta("leader_tooltip_consumed_tap") or not bool(tile.get_meta("leader_tooltip_consumed_tap")):
		return false
	tile.set_meta("leader_tooltip_consumed_tap", false)
	return true

static func _show_touch_tooltip(tile: Control, leader_name: String) -> void:
	var root := tile.get_tree().root
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			if is_instance_valid(tile):
				tile.set_meta("leader_tooltip_consumed_tap", false)
			layer.queue_free()
		elif event is InputEventScreenTouch and event.pressed:
			if is_instance_valid(tile):
				tile.set_meta("leader_tooltip_consumed_tap", false)
			layer.queue_free())
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 70)
	panel.add_theme_stylebox_override("panel", UITheme.tooltip_box())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = "Líder: %s" % leader_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", UITheme.font("title_bold"))
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", UITheme.GOLD_LIGHT)
	panel.add_child(label)
	layer.add_child(panel)
	root.add_child(layer)
	var viewport_size := root.size
	var anchor := tile.get_global_rect()
	var position := anchor.position + Vector2((anchor.size.x - panel.custom_minimum_size.x) / 2.0, anchor.size.y + 8.0)
	panel.position = Vector2(clampf(position.x, 8, viewport_size.x - panel.custom_minimum_size.x - 8), clampf(position.y, 8, viewport_size.y - panel.custom_minimum_size.y - 8))
