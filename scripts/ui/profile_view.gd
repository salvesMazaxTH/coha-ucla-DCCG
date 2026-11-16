class_name ProfileView
extends Control
## The signed-in player's profile as a full-screen window, opened from the main menu. It loads the
## account's online match history (SupabaseAuth.load_match_history) and shows what ProfileStats makes of
## it: the total of matches, favorite deck and Leader, favorite cards, domains and the latest matches.
## It never shows the account's overall wins, losses, win rate or streaks (on purpose, see ProfileStats).
## Tapping a favorite card asks Main to open the card overlay (signal `card_chosen`).

signal card_chosen(card_id: String)
signal closed

const WINDOW_MAX_WIDTH := 1300.0
const WINDOW_HEIGHT := 980.0
const WINDOW_MARGIN := 32.0
const SECTION_GAP := 30.0
const DOMAIN_BADGE_SIZE := 44.0
const PLAYS_TRACKED_SINCE := "15/11/2026"

const FONT_SECTION := 22
const FONT_VALUE := 36
const FONT_CAPTION := 20
const FONT_LINE := 24
const FONT_NAME := 48
const FONT_NOTE := 18

const PANEL_COLOR := Color("#1a1724", 0.95)
const RESULT_NAMES := {"win": "Vitória", "loss": "Derrota", "draw": "Empate"}
const RESULT_COLORS := {"win": Color("#7fd68a"), "loss": Color("#e2787a"), "draw": Color("#c9c3b0")}

var content: VBoxContainer
var shown_history_status := ""
var shown_decks_signature := ""

func open(stage_size: Vector2) -> ProfileView:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event: InputEvent):
		# a click on the dark area around the window closes it
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			closed.emit())
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var window := PanelContainer.new()
	var window_box := UITheme.box(Color("#0e0c14", 0.98), 14, Color(UITheme.GOLD, 0.7), 2, 40)
	window_box.set_content_margin_all(WINDOW_MARGIN)
	window.add_theme_stylebox_override("panel", window_box)
	window.mouse_filter = Control.MOUSE_FILTER_STOP # clicks inside the window must not close it
	window.size = Vector2(minf(stage_size.x - 60.0, WINDOW_MAX_WIDTH), minf(stage_size.y - 60.0, WINDOW_HEIGHT))
	window.position = (stage_size - window.size) / 2.0
	add_child(window)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	window.add_child(column)
	column.add_child(_header())
	column.add_child(_divider())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", SECTION_GAP)
	scroll.add_child(content)

	var close_button := _close_button()
	close_button.position = window.position + Vector2(window.size.x - close_button.size.x - 16.0, 16.0)
	add_child(close_button)

	SupabaseAuth.state_changed.connect(_on_auth_state_changed)
	SupabaseAuth.load_match_history()
	SupabaseAuth.refresh_account_data() # fresh saved decks, so old matches find their deck
	_rebuild_content()
	return self

## Old matches only know their deck through the account's saved decks, which may arrive after the
## history: the profile is computed again when either one changes.
func _on_auth_state_changed(_auth_state: Dictionary) -> void:
	if String(SupabaseAuth.state.get("history_status", "idle")) != shown_history_status or _decks_signature() != shown_decks_signature:
		_rebuild_content()

func _decks_signature() -> String:
	return JSON.stringify(SupabaseAuth.state.get("decks", []))

func _header() -> Control:
	var profile: Dictionary = SupabaseAuth.state.get("profile", {})
	var player_name := String(profile.get("username", ""))
	if player_name.is_empty():
		player_name = String(profile.get("display_name", "Jogador"))
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	texts.add_child(_text("PERFIL", FONT_CAPTION, Color(UITheme.GOLD, 0.9), "title_bold"))
	texts.add_child(_text(player_name, FONT_NAME, UITheme.GOLD_LIGHT, "title_bold"))
	return texts

func _rebuild_content() -> void:
	shown_history_status = String(SupabaseAuth.state.get("history_status", "idle"))
	shown_decks_signature = _decks_signature()
	for child in content.get_children():
		child.queue_free()
	match shown_history_status:
		"ready":
			var stats := ProfileStats.compute(SupabaseAuth.state.get("match_history", []), SupabaseAuth.state.get("decks", []))
			if stats.games == 0:
				_add_message("Nenhuma partida online ainda. Jogue partidas online com esta conta para ver suas estatísticas aqui.")
			else:
				_add_sections(stats)
		"error":
			_add_message("Não foi possível carregar suas partidas. Tente abrir o perfil de novo.")
		_:
			_add_message("Carregando suas partidas...")

func _add_sections(stats: Dictionary) -> void:
	_add_summary(stats)
	_add_favorites(stats)
	_add_favorite_cards(stats)
	_add_domains(stats)
	_add_recent_matches(stats)
	var note := "Partidas online desta conta. Neutra não entra nos domínios. "
	note += "Entradas em campo contam a partir de %s" % PLAYS_TRACKED_SINCE
	note += " (%d de %d partidas)." % [stats.tracked_play_games, stats.games]
	if stats.known_deck_games < stats.games:
		note += " Domínios, cartas e líderes só contam as %d de %d partidas" % [stats.known_deck_games, stats.games]
		note += " cujo deck ainda existe ou foi registrado na partida."
	var note_label := _text(note, FONT_NOTE, UITheme.TEXT_DIM, "body")
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note_label)

func _add_summary(stats: Dictionary) -> void:
	var section := _section("RESUMO")
	var tiles := _tile_row()
	tiles.add_child(_tile(str(stats.games), "Partidas", UITheme.GOLD_LIGHT))
	section.add_child(tiles)

func _add_favorites(stats: Dictionary) -> void:
	var tiles := _tile_row()
	var deck: Dictionary = stats.favorite_deck
	if not deck.is_empty():
		tiles.add_child(_tile(_deck_name(deck.key, ""), "Deck favorito · " + _games_line(deck), UITheme.GOLD_LIGHT))
	var leader: Dictionary = stats.favorite_leader
	if not leader.is_empty() and CardDB.data()["leaders"].has(leader.key):
		var leader_data := CardDB.leader(leader.key)
		var leader_domains: Array = CardDB.leader_essences(leader_data)
		tiles.add_child(_tile(String(leader_data["name"]), "Líder favorito · " + _games_line(leader),
				_domain_color(String(leader_domains[0])), leader_domains))
	var most_played: Dictionary = stats.get("most_played_card", {})
	if not most_played.is_empty():
		var card_name := String(CardDB.card(most_played.card_id)["name"])
		tiles.add_child(_tile(card_name, "Mais jogada · %d vezes em campo" % most_played.plays, UITheme.TEXT))
	if tiles.get_child_count() == 0:
		tiles.queue_free()
		return
	var section := _section("FAVORITOS")
	section.add_child(tiles)

## The top 3 cards as real cards on a small podium: the first one bigger.
func _add_favorite_cards(stats: Dictionary) -> void:
	if stats.favorite_cards.is_empty():
		return
	var section := _section("CARTAS FAVORITAS")
	var podium := HBoxContainer.new()
	podium.alignment = BoxContainer.ALIGNMENT_CENTER
	podium.add_theme_constant_override("separation", 48)
	section.add_child(podium)
	for place in stats.favorite_cards.size():
		podium.add_child(_podium_entry(place, stats.favorite_cards[place], stats.tracked_play_games > 0))

func _podium_entry(place: int, entry: Dictionary, plays_are_tracked: bool) -> Control:
	var card_scale := 1.8 if place == 0 else 1.45
	var card_size := CardView.BASE * card_scale
	var column := VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_SHRINK_END
	column.add_theme_constant_override("separation", 8)
	var place_label := _untrimmed_text("%dº" % (place + 1), FONT_VALUE, UITheme.GOLD_LIGHT, "title_bold")
	place_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(place_label)
	var holder := Control.new()
	holder.custom_minimum_size = card_size.round()
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var card := CardView.new().setup(String(entry.card_id), {}, card_scale)
	card.set_process(false)
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.left_clicked.connect(func(_view: CardView): card_chosen.emit(String(entry.card_id)))
	holder.add_child(card)
	column.add_child(holder)
	var lines: Array = ["%d %s no deck" % [entry.copies, "cópia" if entry.copies == 1 else "cópias"]]
	if plays_are_tracked:
		lines.append("%d vezes em campo" % entry.plays)
	if entry.games > 0:
		lines.append("%s de vitórias" % _percent(ProfileStats.winrate(entry.wins, entry.games)))
	for line in lines:
		var label := _untrimmed_text(String(line), FONT_CAPTION, UITheme.TEXT_DIM, "bold")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
	return column

func _add_domains(stats: Dictionary) -> void:
	if stats.favorite_domains.is_empty():
		return
	var section := _section("DOMÍNIOS")
	section.add_child(_domain_line("Mais jogados", stats.favorite_domains, false))
	section.add_child(_domain_line("Maior taxa de vitória", stats.best_domains, true))
	if not stats.worst_domain.is_empty():
		section.add_child(_domain_line("Menor taxa de vitória", [stats.worst_domain], true))

## A caption followed by one chip per domain: the domain's badge, then the numbers.
func _domain_line(title: String, domains: Array, show_winrate: bool) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 20)
	var title_label := _untrimmed_text(title, FONT_LINE, UITheme.TEXT_DIM, "bold")
	title_label.custom_minimum_size = Vector2(320, 0)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(title_label)
	for domain in domains:
		line.add_child(_domain_chip(domain, show_winrate))
	return line

func _domain_chip(domain: Dictionary, show_winrate: bool) -> Control:
	var chip := PanelContainer.new()
	var box := UITheme.box(PANEL_COLOR, 10, Color(UITheme.GOLD, 0.3), 1, 0)
	box.set_content_margin_all(12)
	chip.add_theme_stylebox_override("panel", box)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = String(CardDB.essence(domain.domain_id).get("name", domain.domain_id))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_child(DomainIconRow.new().setup([domain.domain_id], DOMAIN_BADGE_SIZE))
	var numbers := VBoxContainer.new()
	numbers.add_theme_constant_override("separation", 0)
	var games_text := "%d %s" % [domain.games, "partida" if domain.games == 1 else "partidas"]
	var domain_color := _domain_color(domain.domain_id)
	if show_winrate:
		var rate_text := _percent(ProfileStats.winrate(domain.wins, domain.games))
		numbers.add_child(_untrimmed_text(rate_text, FONT_LINE + 4, domain_color, "title_bold"))
		numbers.add_child(_untrimmed_text(games_text, FONT_NOTE, UITheme.TEXT_DIM, "bold"))
	else:
		numbers.add_child(_untrimmed_text(games_text, FONT_LINE, domain_color, "title_bold"))
	line.add_child(numbers)
	chip.add_child(line)
	return chip

func _add_recent_matches(stats: Dictionary) -> void:
	var section := _section("ÚLTIMAS PARTIDAS")
	for match_info in stats.recent:
		section.add_child(_match_row(match_info))

func _match_row(match_info: Dictionary) -> Control:
	var result_color: Color = RESULT_COLORS[match_info.result]
	var row := PanelContainer.new()
	var box := UITheme.box(PANEL_COLOR, 8, Color(result_color, 0.9), 0, 0)
	box.border_width_left = 8
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	row.add_theme_stylebox_override("panel", box)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 20)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	var result_label := _untrimmed_text(RESULT_NAMES[match_info.result], FONT_LINE, result_color, "title_bold")
	result_label.custom_minimum_size = Vector2(150, 0)
	line.add_child(result_label)
	var leader_domains: Array = []
	if CardDB.data()["leaders"].has(match_info.leader_id):
		leader_domains = CardDB.leader_essences(CardDB.leader(match_info.leader_id))
	line.add_child(DomainIconRow.new().setup(leader_domains, DOMAIN_BADGE_SIZE - 8.0))
	var deck_label := _text(_deck_name(match_info.deck_key, match_info.leader_id), FONT_LINE, UITheme.TEXT, "bold")
	deck_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(deck_label)
	line.add_child(_untrimmed_text(_date_text(match_info.created_at), FONT_CAPTION, UITheme.TEXT_DIM, "bold"))
	row.add_child(line)
	return row

## A titled block added to the content, the title followed by a thin gold line; the caller fills it.
func _section(title: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 14)
	var title_line := HBoxContainer.new()
	title_line.add_theme_constant_override("separation", 16)
	title_line.add_child(_untrimmed_text(title, FONT_SECTION, UITheme.GOLD_LIGHT, "title_bold"))
	var rule := ColorRect.new()
	rule.color = Color(UITheme.GOLD, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_line.add_child(rule)
	section.add_child(title_line)
	content.add_child(section)
	return section

## A row whose tiles share its width evenly.
func _tile_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	return row

## A box with a big value on top and a dim caption below it; `domains` adds their badges beside the value.
func _tile(value: String, caption: String, value_color: Color, domains: Array = []) -> Control:
	var tile := PanelContainer.new()
	var box := UITheme.box(PANEL_COLOR, 12, Color(UITheme.GOLD, 0.35), 1, 0)
	box.set_content_margin_all(18)
	tile.add_theme_stylebox_override("panel", box)
	tile.custom_minimum_size = Vector2(200, 0)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 4)
	var value_line := HBoxContainer.new()
	value_line.add_theme_constant_override("separation", 10)
	var value_label := _text(value, FONT_VALUE, value_color, "title_bold")
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.tooltip_text = value
	value_label.mouse_filter = Control.MOUSE_FILTER_PASS
	value_line.add_child(value_label)
	if not domains.is_empty():
		value_line.add_child(DomainIconRow.new().setup(domains, DOMAIN_BADGE_SIZE - 6.0))
	texts.add_child(value_line)
	var caption_label := _untrimmed_text(caption, FONT_CAPTION, UITheme.TEXT_DIM, "bold")
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(caption_label)
	tile.add_child(texts)
	return tile

func _add_message(message: String) -> void:
	var label := _text(message, FONT_LINE, UITheme.TEXT, "bold")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)

## A deck's name today. A deleted deck has none: it is named after its Leader when that is known.
func _deck_name(deck_key: String, leader_id: String) -> String:
	if DeckDB.has(deck_key):
		return String(DeckDB.get_deck(deck_key).get("name", deck_key))
	var saved_id := deck_key.trim_prefix(DeckDB.PLAYER_PREFIX)
	for saved_deck in SupabaseAuth.state.get("decks", []):
		if saved_deck is Dictionary and String(saved_deck.get("id", "")) == saved_id:
			return String(saved_deck.get("name", "Deck"))
	if CardDB.data()["leaders"].has(leader_id):
		return "Deck de " + String(CardDB.leader(leader_id)["name"])
	return "Deck apagado"

func _games_line(entry: Dictionary) -> String:
	return "%d %s · %s de vitórias" % [entry.games, "partida" if entry.games == 1 else "partidas",_percent(ProfileStats.winrate(entry.wins, entry.games))]

func _percent(rate: float) -> String:
	return "%d%%" % roundi(rate * 100.0)

## "2026-11-15T21:04:33+00:00" -> "15/11 18:04" in the player's local time.
func _date_text(created_at: String) -> String:
	if created_at.length() < 19:
		return ""
	var utc_seconds := Time.get_unix_time_from_datetime_string(created_at.substr(0, 19))
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	var local_seconds := utc_seconds + bias_minutes * 60
	var date := Time.get_datetime_dict_from_unix_time(local_seconds)
	return "%02d/%02d %02d:%02d" % [date.day, date.month, date.hour, date.minute]

func _domain_color(domain_id: String) -> Color:
	var essence_color := Color(String(CardDB.essence(domain_id).get("color", "#8a8f98")))
	return DecklistRow.essence_text_color(essence_color)

func _divider() -> Control:
	var line := ColorRect.new()
	line.color = Color(UITheme.GOLD, 0.45)
	line.custom_minimum_size = Vector2(0, 2)
	return line

## An X in the window's top right corner.
func _close_button() -> Button:
	var button_size := Vector2(64, 64)
	var button := Button.new()
	button.custom_minimum_size = button_size
	button.size = button_size
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Fechar o perfil."
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = button_size / 2.0
	icon.draw.connect(func():
		icon.draw_line(Vector2(-12, -12), Vector2(12, 12), UITheme.GOLD_LIGHT, 4.0, true)
		icon.draw_line(Vector2(12, -12), Vector2(-12, 12), UITheme.GOLD_LIGHT, 4.0, true))
	button.add_child(icon)
	button.pressed.connect(func(): closed.emit())
	return button

func _untrimmed_text(text: String, font_size: int, color: Color, font_kind: String) -> Label:
	var label := _text(text, font_size, color, font_kind)
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return label

func _text(text: String, font_size: int, color: Color, font_kind: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.font(font_kind))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
