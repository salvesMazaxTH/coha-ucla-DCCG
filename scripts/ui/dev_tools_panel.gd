class_name DevToolsPanel
extends PanelContainer
## Local-only controls for testing match state without changing the regular game flow.

signal action_requested(action: String, parameters: Dictionary)
signal close_requested

var player_selector: OptionButton
var card_selector: OptionButton
var draw_amount: SpinBox
var momentum_amount: SpinBox
var life_amount: SpinBox
var damage_amount: SpinBox
var result_label: Label
var _target_player := 0
var _has_selected_player := false
var _current_game: GameState

func _ready() -> void:
	custom_minimum_size = Vector2(430, 0)
	size = Vector2(430, 820)
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UITheme.panel())

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 790)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

	var heading := HBoxContainer.new()
	content.add_child(heading)
	var title := Label.new()
	title.text = "FERRAMENTAS DE DESENVOLVIMENTO"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", UITheme.GOLD_LIGHT)
	title.add_theme_font_size_override("font_size", 18)
	heading.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(36, 34)
	close.pressed.connect(func() -> void: close_requested.emit())
	heading.add_child(close)

	var hint := Label.new()
	hint.text = "Partida local · F12 fecha · a IA pausa enquanto o painel está aberto"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	content.add_child(hint)

	content.add_child(_section_title("Jogador afetado"))
	player_selector = OptionButton.new()
	player_selector.item_selected.connect(_on_player_selected)
	content.add_child(player_selector)

	content.add_child(_section_title("Cartas"))
	var draw_row := HBoxContainer.new()
	content.add_child(draw_row)
	draw_amount = _spin_box(1, 10, 1)
	draw_row.add_child(draw_amount)
	var draw_button := Button.new()
	draw_button.text = "Comprar do topo"
	draw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draw_button.pressed.connect(func() -> void:
		_request("draw_cards", {"amount": int(draw_amount.value)}))
	draw_row.add_child(draw_button)
	card_selector = OptionButton.new()
	card_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(card_selector)
	var specific_button := Button.new()
	specific_button.text = "Comprar carta selecionada"
	specific_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	specific_button.pressed.connect(_draw_selected_card)
	content.add_child(specific_button)

	content.add_child(_section_title("Momentum"))
	var momentum_row := HBoxContainer.new()
	content.add_child(momentum_row)
	momentum_amount = _spin_box(1, GameState.MOMENTUM_OVERFLOW_CAP, 1)
	momentum_row.add_child(momentum_amount)
	var add_momentum_button := Button.new()
	add_momentum_button.text = "Adicionar Momentum"
	add_momentum_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_momentum_button.pressed.connect(func() -> void:
		_request("add_momentum", {"amount": int(momentum_amount.value)}))
	momentum_row.add_child(add_momentum_button)
	var resource_row := HBoxContainer.new()
	content.add_child(resource_row)
	var refill_momentum_button := Button.new()
	refill_momentum_button.text = "Reencher Momentum"
	refill_momentum_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refill_momentum_button.pressed.connect(func() -> void: _request("refill_momentum"))
	resource_row.add_child(refill_momentum_button)
	var refill_battery_button := Button.new()
	refill_battery_button.text = "Reencher a Bateria"
	refill_battery_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refill_battery_button.pressed.connect(func() -> void: _request("refill_battery"))
	resource_row.add_child(refill_battery_button)

	content.add_child(_section_title("Líder"))
	var life_row := HBoxContainer.new()
	content.add_child(life_row)
	life_amount = _spin_box(1, 100, 5)
	life_row.add_child(life_amount)
	var raise_life_button := Button.new()
	raise_life_button.text = "Aumentar Vida máxima"
	raise_life_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	raise_life_button.pressed.connect(func() -> void:
		_request("raise_leader_max", {"amount": int(life_amount.value)}))
	life_row.add_child(raise_life_button)
	var leader_row := HBoxContainer.new()
	content.add_child(leader_row)
	var heal_button := Button.new()
	heal_button.text = "Curar totalmente"
	heal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal_button.pressed.connect(func() -> void: _request("heal_leader"))
	leader_row.add_child(heal_button)
	damage_amount = _spin_box(1, 100, 1)
	leader_row.add_child(damage_amount)
	var damage_button := Button.new()
	damage_button.text = "Causar dano"
	damage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	damage_button.pressed.connect(func() -> void:
		_request("damage_leader", {"amount": int(damage_amount.value)}))
	leader_row.add_child(damage_button)

	result_label = Label.new()
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	content.add_child(result_label)

func refresh(game: GameState, vs_ai: bool, viewer: int) -> void:
	if not is_instance_valid(player_selector):
		return
	var previous_player := _target_player
	_current_game = game
	player_selector.clear()
	for p in 2:
		var label := "Você" if vs_ai and p == 0 else ("IA" if vs_ai else "Jogador %d" % (p + 1))
		player_selector.add_item(label, p)
	if not _has_selected_player or previous_player not in [0, 1]:
		_target_player = viewer
	_has_selected_player = true
	player_selector.select(_target_player)
	_refresh_card_options(game)

func set_result(message: String, is_error := false) -> void:
	if not is_instance_valid(result_label):
		return
	result_label.text = message
	result_label.add_theme_color_override("font_color", Color("#ff8b79") if is_error else UITheme.TEXT_DIM)

func _refresh_card_options(game: GameState) -> void:
	card_selector.clear()
	var counts := {}
	for card: Card in game.players[_target_player]["deck"]:
		counts[card.card_id] = int(counts.get(card.card_id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort()
	for card_id in ids:
		var id := String(card_id)
		var card_data := CardDB.card(id)
		var card_name := String(card_data.get("name", id))
		card_selector.add_item("%s × %d" % [card_name, counts[id]])
		card_selector.set_item_metadata(card_selector.item_count - 1, id)
	if card_selector.item_count > 0:
		card_selector.select(0)

func _on_player_selected(index: int) -> void:
	_target_player = player_selector.get_item_id(index)
	if is_instance_valid(_current_game):
		_refresh_card_options(_current_game)
	set_result("")

func _draw_selected_card() -> void:
	if card_selector.item_count == 0 or card_selector.selected < 0:
		set_result("O deck selecionado não tem cartas para comprar.", true)
		return
	_request("draw_specific", {"card_id": String(card_selector.get_item_metadata(card_selector.selected))})

func _request(action: String, parameters: Dictionary = {}) -> void:
	var payload := parameters.duplicate()
	payload["player"] = _target_player
	action_requested.emit(action, payload)

func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", UITheme.GOLD)
	label.add_theme_font_size_override("font_size", 17)
	return label

func _spin_box(minimum: int, maximum: int, initial: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1
	spin.value = initial
	spin.custom_minimum_size = Vector2(86, 34)
	return spin
