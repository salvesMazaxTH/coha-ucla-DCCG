class_name MenuScreens
extends RefCounted
## The screens around a match: title menu, Google sign-in, deck hub (AI, hot-seat and online),
## room code entry, waiting room and the deck list. Main (`host`) owns the stage they are drawn on.

const HubGlyphIconScript = preload("res://scripts/ui/hub_glyph_icon.gd")
const DomainIconRowScript = preload("res://scripts/ui/domain_icon_row.gd")
const DeckLeaderTooltipScript = preload("res://scripts/ui/deck_leader_tooltip.gd")
const BannedRibbonScript = preload("res://scripts/ui/banned_ribbon.gd")
var account_button: Button
var _account_was_signed_in := false
var _session_was_checked := false
## The entry screen (Google / guest) comes before the mode buttons; this turns true once the player
## signed in or chose to play as a guest, and back to false when they sign out.
var _entered_menu := false
var _google_logo_texture: Texture2D
var code_entry := ""
var sel_deck := "" ## deck picked in the hub (a prebuilt id, or a DeckDB.PLAYER_PREFIX id for one of the player's own)
var deck_store: DeckStore ## the player's saved decks (MEUS DECKS), listed in the hub; created on first use
var incomplete_player_decks := 0 ## saved decks that are not ready to play, so the hub leaves them out
var _hub_args: Array = [] ## the arguments of the last show_hub call, to redraw it when the player's decks arrive
var hub_hotseat := false ## the deck hub's two-step flow is picking decks for hot-seat (player 1, then player 2) instead of AI
var hub_scroll_y := 0 ## how far the gallery was scrolled, kept across the hub's redraws
var hub_drag_distance := 0.0 ## how far the current press has dragged the gallery (a long drag isn't a tap)
var hub_collapsed := { } ## collapsed macro-sections and prebuilt subsections, preserved across redraws
const MENU_SUBTITLE_FONT_SIZE := 18 ## the small hint under each title-menu button
const MENU_SUBTITLE_COLOR := Color(0.93, 0.9, 0.84, 0.85) ## near-opaque cream so the hint reads on the busy art
const DECK_TILE_NAME_FONT_SIZES := [21, 19, 17, 15, 13] ## tried in order until the deck name fits its zone on the tile
const HUB_MARGIN := 40.0 ## space between the hub's panels and the stage sides
const HUB_TILE := Vector2(210, 236) ## original chip height, with the Leader line replaced by domain seals
const HUB_TILE_GAP := 20.0
const HUB_TILE_PAD := 10.0 ## room around the gallery's tiles for the hover zoom
## The gallery's two macro-sections. Prebuilt decks are grouped below by the set of their Leader's incarnation.
const HUB_SECTIONS := [
	{ "id": DeckDB.SECTION_LEADERS, "title": "DECKS PRÉ-PRONTOS DOS LÍDERES" },
	{
		"id": DeckDB.SECTION_MINE,
		"title": "MEUS DECKS",
		"hint": (
			"Você ainda não tem nenhum deck pronto. Monte um em MEUS DECKS, no menu inicial: "
			+ "59 cartas, a Encarnação do Líder e as regras do deck cumpridas."
		),
	},
]
const HUB_EMPTY_HINT_H := 72.0 ## height of the hint that stands in for the tiles of an empty section
const HUB_SECTION_TITLE_H := 48.0 ## height of a macro-section's collapsible title row
const HUB_SUBSECTION_TITLE_H := 40.0 ## height of a prebuilt subsection's collapsible title row
const HUB_SUBSECTION_INDENT := 22.0
const HUB_SECTION_GAP := 28.0 ## empty space between the end of one section and the next title
const HUB_SUBSECTION_GAP := 16.0
const HUB_DRAG_SLOP := 12.0 ## pixels a press may move and still count as a tap on a deck
var ai_deck := "" ## deck the AI plays, picked in the second step of the AI hub ("" = a random other deck)

var host


func _init(host_node) -> void:
	host = host_node


func show_menu() -> void:
	if host.online:
		host.net.disconnect_server() ## the saved session stays: RETOMAR PARTIDA in the lobby
		host.online = false
	DeckDB.clear_custom(DeckDB.ROOM_PREFIX) # decks of a finished online match; "resume" sends them again
	host.g = null
	Music.stop()
	host.table_overlays.close_concede()
	host._clear_fx()
	host._clear()
	host.table.visible = false
	host._set_tints(Color("#3f7bd9"), Color("#e0572b"), 1.6)
	# the two Leaders of the slice, facing each other from the edges
	for side in [["furia/ronan.webp", 0.0, 1.0], ["fluxo/naelthos.webp", host.stage_w - 640.0, 0.0]]:
		var tex := CardView.texture(side[0])
		if tex == null:
			continue
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(side[1], 0)
		tr.size = Vector2(640, host.STAGE_H)
		tr.flip_h = side[2] == 0.0
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sm := ShaderMaterial.new()
		sm.shader = load("res://scripts/ui/shaders/art_fade.gdshader")
		sm.set_shader_parameter("fade_from_right", side[2])
		sm.set_shader_parameter("strength", 0.55)
		tr.material = sm
		host.layer.add_child(tr)
	var title: Label = host._label("UCLA", 120, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 14)
	title.add_theme_color_override("font_shadow_color", Color(UITheme.GOLD, 0.35))
	title.add_theme_constant_override("shadow_outline_size", 22)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.position = Vector2(0, 140)
	title.size = Vector2(host.stage_w, 140)
	host.layer.add_child(title)
	# the acronym alone says nothing to a new player, so the full name sits right under it
	var full_name: Label = host._label(
		"ULTIMATE CLASH OF LEGENDS OF ATECRA",
		24,
		Color(UITheme.GOLD, 0.85),
		HORIZONTAL_ALIGNMENT_CENTER,
		"title",
		6,
	)
	full_name.position = Vector2(0, 284)
	full_name.size = Vector2(host.stage_w, 34)
	host.layer.add_child(full_name)
	host.layer.add_child(ornament(Vector2(host.stage_w / 2.0, 340), 260))
	host._menu_screen_showing = true
	# a session restored from an earlier visit skips the entry screen
	if SupabaseAuth.is_signed_in():
		_entered_menu = true
	if _entered_menu:
		_add_menu_mode_buttons()
	else:
		_add_entry_buttons()
	var lt: Button = host._toggle_button(
		"MODO LEVE",
		host._light_on(),
		func():
			host._apply_light(not host._light_on(), true)
			show_menu.call_deferred(),
	)
	lt.position = Vector2(host.stage_w - 300, 790.0 + host.BOT)
	lt.size = Vector2(280, 52)
	host.layer.add_child(lt)
	var sound_toggle: Button = host._toggle_button(
		"SOM",
		Sfx.is_enabled(),
		func():
			Sfx.set_enabled(not Sfx.is_enabled())
			show_menu.call_deferred(),
	)
	sound_toggle.position = Vector2(host.stage_w - 300, 662.0 + host.BOT)
	sound_toggle.size = Vector2(280, 52)
	host.layer.add_child(sound_toggle)
	var volume_control: Control = host._volume_slider(Vector2(280, 52))
	volume_control.position = Vector2(host.stage_w - 300, 598.0 + host.BOT)
	host.layer.add_child(volume_control)
	# the music has its own switch and volume, stacked above the sound effects ones
	var music_toggle: Button = host._toggle_button(
		"MÚSICA",
		Music.is_enabled(),
		func():
			Music.set_enabled(not Music.is_enabled())
			show_menu.call_deferred(),
	)
	music_toggle.position = Vector2(host.stage_w - 300, 534.0 + host.BOT)
	music_toggle.size = Vector2(280, 52)
	host.layer.add_child(music_toggle)
	var music_volume_control: Control = host._volume_slider(Vector2(280, 52), true)
	music_volume_control.position = Vector2(host.stage_w - 300, 470.0 + host.BOT)
	host.layer.add_child(music_volume_control)
	var fs: Button = host._button("Tela cheia (F11)", host._toggle_fullscreen)
	fs.position = Vector2(host.stage_w - 300, 790.0 + host.BOT - 64.0)
	fs.size = Vector2(280, 52)
	host.layer.add_child(fs)
	var ver: Label = host._label("0.2.2 Alpha", 13, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_RIGHT, "body")
	ver.position = Vector2(host.stage_w - 300, 864.0 + host.BOT)
	ver.size = Vector2(280, 20)
	host.layer.add_child(ver)


## Entry screen: before the mode buttons, the player either signs in with Google or goes on as a guest.
func _add_entry_buttons() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.position = Vector2(host.stage_w / 2.0 - 210, 410)
	column.custom_minimum_size = Vector2(420, 0)
	host.layer.add_child(column)
	if not SupabaseAuth.is_session_checked():
		# still looking for a saved session: no buttons yet, so they don't flash and vanish
		column.add_child(host._label("Verificando sua conta…", 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
		return
	column.add_child(_google_sign_in_button())
	column.add_child(host._label("Salva seu perfil e seus decks na nuvem", 14, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body"))
	var guest_button: Button = host._button(
		"ENTRAR COMO CONVIDADO",
		func() -> void:
			_entered_menu = true
			show_menu(),
	)
	guest_button.custom_minimum_size = Vector2(420, 58)
	column.add_child(guest_button)
	column.add_child(
		host._label("Joga sem conta; nada fica salvo na nuvem", 14, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "body")
	)


## The standard "Sign in with Google" button, following Google's branding rules: white background,
## thin grey border, the four-colour G on the left and dark grey text (Roboto Medium when the system
## has it). It is drawn bigger than Google's 40 px because the whole stage is scaled down on phones.
func _google_sign_in_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(420, 58)
	button.tooltip_text = "Entrar com a sua conta Google."
	var normal_style := UITheme.box(Color("#ffffff"), 6, Color("#747775"), 1)
	var hover_style := UITheme.box(Color("#f2f2f2"), 6, Color("#747775"), 1)
	var pressed_style := UITheme.box(Color("#e3e3e3"), 6, Color("#747775"), 1)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("hover_pressed", pressed_style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(Sfx.play.bind("ui_click"))
	button.pressed.connect(_start_google_sign_in)
	# logo and text side by side, centred inside the button
	var content_row := HBoxContainer.new()
	content_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content_row.add_theme_constant_override("separation", 14)
	content_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content_row)
	var logo := TextureRect.new()
	logo.texture = _google_logo()
	logo.custom_minimum_size = Vector2(26, 26)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_row.add_child(logo)
	var google_font := SystemFont.new()
	google_font.font_names = PackedStringArray(["Roboto", "Segoe UI", "Helvetica Neue", "Arial"])
	google_font.font_weight = 500
	google_font.fallbacks = [UITheme.font("bold")]
	var text_label: Label = host._label("Entrar com o Google", 20, Color("#1f1f1f"), HORIZONTAL_ALIGNMENT_LEFT)
	text_label.add_theme_font_override("font", google_font)
	text_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content_row.add_child(text_label)
	return button


## Google's official four-colour "G", built from its SVG once and reused.
func _google_logo() -> Texture2D:
	if _google_logo_texture:
		return _google_logo_texture
	var svg_source := """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>"""
	var logo_image := Image.new()
	# drawn at 2x so it stays sharp when the stage is scaled up on big screens
	logo_image.load_svg_from_string(svg_source, 2.0)
	_google_logo_texture = ImageTexture.create_from_image(logo_image)
	return _google_logo_texture


## The deck builder takes over the whole stage; its way back is the title menu.
func open_deck_builder() -> void:
	host._clear()
	host.deck_builder = DeckBuilder.new()
	host.deck_builder.closed.connect(
		func() -> void:
			host.deck_builder = null
			show_menu(),
	)
	host.layer.add_child(host.deck_builder)


## The full title menu, once the player is in: the three ways to play, the deck builder and the account button.
func _add_menu_mode_buttons() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.position = Vector2(host.stage_w / 2.0 - 210, 390)
	box.custom_minimum_size = Vector2(420, 0)
	host.layer.add_child(box)
	var mode_options: Array = [
		[
			"JOGAR CONTRA A IA",
			"Escolha o seu deck e o da IA",
			func() -> void:
				hub_hotseat = false
				show_hub(true),
			true,
		],
		[
			"HOT-SEAT",
			"Dois jogadores no mesmo aparelho, cada um com o deck que quiser",
			func() -> void:
				hub_hotseat = true
				show_hub(true),
			false,
		],
	]
	if not host.dev_mode_enabled:
		mode_options.append(
			[
				"ONLINE",
				"Jogar contra outra pessoa por código de sala",
				func() -> void:
					show_hub(false),
				false,
			]
		)
	mode_options.append(["MEUS DECKS", "Crie, edite e guarde seus próprios decks", open_deck_builder, false])
	for opt in mode_options:
		var b: Button = host._button(opt[0], opt[2], opt[3])
		b.custom_minimum_size = Vector2(420, 58)
		b.tooltip_text = opt[1]
		box.add_child(b)
		var sub: Label = host._label(opt[1], MENU_SUBTITLE_FONT_SIZE, MENU_SUBTITLE_COLOR, HORIZONTAL_ALIGNMENT_CENTER, "body")
		# the longer hint (hot-seat) wraps instead of pushing the column wider than the buttons
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(sub)
	# a guest can still link a Google account later from here
	account_button = host._button("ENTRAR COM GOOGLE", _on_account_button_pressed)
	account_button.position = Vector2(24, 24)
	account_button.size = Vector2(300, 52)
	account_button.tooltip_text = "Vincule sua conta para salvar perfil e decks."
	host.layer.add_child(account_button)
	_update_account_button()


func _on_account_button_pressed() -> void:
	if SupabaseAuth.is_signed_in():
		SupabaseAuth.sign_out()
	else:
		_start_google_sign_in()


func _start_google_sign_in() -> void:
	SupabaseAuth.sign_in_with_google()
	# on the web the page itself goes to Google; the executable opens a separate browser window
	if not OS.has_feature("web"):
		host._toast("Abrimos o navegador: entre com o Google lá e depois volte ao jogo.")


func on_supabase_auth_state_changed(auth_state: Dictionary) -> void:
	_update_account_button()
	var signed_in_now := bool(auth_state.get("signed_in", false))
	var session_checked_now := bool(auth_state.get("session_checked", false))
	if host._menu_screen_showing:
		if signed_in_now and not _entered_menu:
			# came back from Google (or a saved session was found): go into the full menu
			_entered_menu = true
			show_menu.call_deferred()
		elif not signed_in_now and _account_was_signed_in:
			# signed out: back to the entry screen
			_entered_menu = false
			show_menu.call_deferred()
		elif session_checked_now and not _session_was_checked and not _entered_menu:
			# the saved-session check finished with no session: show the entry buttons
			show_menu.call_deferred()
	_session_was_checked = session_checked_now
	var error_message := String(auth_state.get("error", ""))
	if not error_message.is_empty():
		host._toast(error_message)
	elif bool(auth_state.get("signed_in", false)) and not _account_was_signed_in:
		var profile: Dictionary = auth_state.get("profile", { })
		host._toast("Conta Google conectada%s" % (": %s" % String(profile.get("username", "")) if not profile.is_empty() else "."))
	_account_was_signed_in = bool(auth_state.get("signed_in", false))


func _update_account_button() -> void:
	if not is_instance_valid(account_button):
		return
	if SupabaseAuth.is_signed_in():
		var profile: Dictionary = SupabaseAuth.state.get("profile", { })
		var username := String(profile.get("username", "CONTA CONECTADA"))
		account_button.text = "SAIR DA CONTA · %s" % username.to_upper()
		account_button.tooltip_text = "Sessão Google ativa. Toque para sair."
	else:
		account_button.text = "ENTRAR COM GOOGLE"
		account_button.tooltip_text = "Vincule sua conta para salvar perfil e decks."


## A thin gold rule with a diamond in the middle, for headings.
func ornament(center: Vector2, half: float) -> Control:
	var o := Control.new()
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	o.position = center
	o.draw.connect(
		func():
			for i in 20:
				var k := float(i) / 20.0
				var a := (1.0 - k) * 0.8
				var x0 := 10 + (half - 10) * k
				var x1 := 10 + (half - 10) * (k + 0.05)
				o.draw_line(Vector2(-x0, 0), Vector2(-x1, 0), Color(UITheme.GOLD, a), 1.5)
				o.draw_line(Vector2(x0, 0), Vector2(x1, 0), Color(UITheme.GOLD, a), 1.5)
			o.draw_colored_polygon(PackedVector2Array([Vector2(0, -6), Vector2(6, 0), Vector2(0, 6), Vector2(-6, 0)]), UITheme.GOLD),
	)
	return o

# ---------------------------------------------------------------- online


func show_online(msg := "") -> void:
	show_hub(false, msg)


## Deck hub, shared by both modes: pick a prebuilt deck from the grid, then either go on to pick the
## AI's deck (ai = true) or create a room / go on to join one by code (online).
## `choosing_ai_deck` is the AI mode's second step: the same grid, but the pick is the AI's deck.
func show_hub(ai: bool, msg := "", choosing_ai_deck := false) -> void:
	if host.dev_mode_enabled and not ai:
		host._toast("Modo de desenvolvimento: partidas online desativadas.")
		return
	host._clear_fx()
	host._clear()
	host.table.visible = false
	host._set_tints(Color("#3f7bd9"), Color("#e0572b"), 1.6)
	_hub_args = [ai, msg, choosing_ai_deck]
	refresh_hub_stats_if_due()
	_refresh_player_decks()
	# Prebuilt decks stay first so the default pick remains a prebuilt deck.
	var ids: Array[String] = DeckDB.available_ids()
	for deck_id in DeckDB.custom_ids(DeckDB.PLAYER_PREFIX):
		if DeckDB.is_deck_visible(deck_id):
			ids.append(deck_id)
	if ids.is_empty():
		host._toast("Nenhum deck disponível neste modo.")
		show_menu()
		return
	# banned decks stay in the gallery (marked BANIDO) but can never be the chosen one
	var playable_ids: Array[String] = ids.filter(
		func(deck_id: String) -> bool:
			return not DeckDB.is_deck_banned(deck_id),
	)
	if playable_ids.is_empty():
		host._toast("Nenhum deck disponível neste modo.")
		show_menu()
		return
	if not playable_ids.has(sel_deck):
		sel_deck = playable_ids[0]
	if ai_deck != "" and not playable_ids.has(ai_deck):
		ai_deck = ""
	var title: Label = host._label(
		("HOT-SEAT" if hub_hotseat else "CONTRA A IA") if ai else "ONLINE",
		56,
		UITheme.GOLD_LIGHT,
		HORIZONTAL_ALIGNMENT_CENTER,
		"title_bold",
		8,
	)
	title.position = Vector2(0, 24)
	title.size = Vector2(host.stage_w, 72)
	host.layer.add_child(title)
	host.layer.add_child(ornament(Vector2(host.stage_w / 2.0, 108), 240))
	var subtitle := "Jogador 1: escolha o seu deck" if hub_hotseat else "Escolha o seu deck"
	if choosing_ai_deck:
		subtitle = "Jogador 2: escolha o seu deck" if hub_hotseat else "Escolha o deck da IA (ou deixe no aleatório)"
	# A message (e.g. the server refused the room) must be impossible to miss: the screen snaps back to
	# this hub, so a small grey line was easy to overlook and looked like "the button does nothing".
	var sub: Label
	if msg != "":
		sub = host._label(msg, 28, Color("#ff9d7a"), HORIZONTAL_ALIGNMENT_CENTER, "bold", 4)
	else:
		sub = host._label(subtitle, 22, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold")
	sub.position = Vector2(0, 120)
	sub.size = Vector2(host.stage_w, 40)
	host.layer.add_child(sub)

	# Layout: the chosen deck in a big showcase on the left (full description, never cut), and every
	# deck as a fixed-size tile in a gallery on the right. More decks only make the gallery taller,
	# and it scrolls (wheel or finger), so the tiles never shrink however many decks there are.
	var body_top := 172.0
	var body_bottom: float = host.STAGE_H - 112.0
	var body_h := body_bottom - body_top
	var showcase_w := 560.0
	var selected_id := ai_deck if choosing_ai_deck else sel_deck
	var showcase := _deck_showcase(selected_id, Vector2(showcase_w, body_h), choosing_ai_deck)
	showcase.position = Vector2(HUB_MARGIN, body_top)
	host.layer.add_child(showcase)

	var gallery_x := HUB_MARGIN + showcase_w + 32.0
	var gallery_w: float = host.stage_w - gallery_x - HUB_MARGIN
	var prebuilt_ids: Array[String] = []
	var player_ids: Array[String] = []
	for deck_id in ids:
		if DeckDB.section_of(deck_id) == DeckDB.SECTION_MINE:
			player_ids.append(deck_id)
		else:
			prebuilt_ids.append(deck_id)
	var prebuilt_subsections := _hub_prebuilt_subsections(prebuilt_ids)
	if choosing_ai_deck:
		if prebuilt_subsections.is_empty():
			prebuilt_subsections.append({ "id": "classic", "title": "ESSENCIAIS CLÁSSICOS", "ids": [] })
		prebuilt_subsections[0]["ids"].push_front("")

	var gallery_sections: Array = []
	for section in HUB_SECTIONS:
		var section_id := String(section["id"])
		var section_title := String(section["title"])
		if section_id == DeckDB.SECTION_MINE and incomplete_player_decks > 0:
			section_title += "  ·  %d incompleto%s em MEUS DECKS" % [
				incomplete_player_decks,
				"" if incomplete_player_decks == 1 else "s",
			]
		if section_id == DeckDB.SECTION_LEADERS:
			gallery_sections.append(
				{
					"id": section_id,
					"title": section_title,
					"subsections": prebuilt_subsections,
					"hint": "Nenhum deck pré-pronto está disponível." if prebuilt_subsections.is_empty() else "",
				}
			)
		else:
			gallery_sections.append({ "id": section_id, "title": section_title, "ids": player_ids, "hint": section.get("hint", "") })
	var columns := maxi(1, int((gallery_w + HUB_TILE_GAP) / (HUB_TILE.x + HUB_TILE_GAP)))
	var content_h := 2.0 * HUB_TILE_PAD
	for i in gallery_sections.size():
		var section: Dictionary = gallery_sections[i]
		content_h += HUB_SECTION_TITLE_H
		if not _hub_section_collapsed(_hub_macro_key(String(section["id"]))):
			content_h += _hub_macro_body_height(section, columns)
		if i < gallery_sections.size() - 1:
			content_h += HUB_SECTION_GAP
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(gallery_x, body_top)
	scroll.size = Vector2(gallery_w, body_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# the gallery scrolls by finger or wheel (see hub_scroll_input), so the bar would only add clutter
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	host.layer.add_child(scroll)
	host.hub_scroll = scroll
	var content := Control.new()
	# a few pixels of room around the tiles so the hover zoom and the gold border aren't clipped
	content.custom_minimum_size = Vector2(gallery_w, content_h)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(content)
	var grid_w := columns * HUB_TILE.x + (columns - 1) * HUB_TILE_GAP
	var grid_x := (gallery_w - grid_w) / 2.0
	var selected_tile: Control = null
	var section_top := HUB_TILE_PAD
	for section_index in gallery_sections.size():
		var section: Dictionary = gallery_sections[section_index]
		var section_id := String(section["id"])
		var macro_key := _hub_macro_key(section_id)
		var macro_collapsed := _hub_section_collapsed(macro_key)
		_add_hub_section_title(
			content,
			String(section["title"]),
			Vector2(grid_x, section_top),
			grid_w,
			macro_key,
			section_id,
			macro_collapsed,
			true,
			scroll,
			ai,
			msg,
			choosing_ai_deck,
		)
		section_top += HUB_SECTION_TITLE_H
		if not macro_collapsed:
			if section.has("subsections"):
				var subsections: Array = section["subsections"]
				if subsections.is_empty():
					_add_hub_section_body(
						content,
						section,
						grid_x,
						section_top,
						grid_w,
						columns,
						selected_id,
						choosing_ai_deck,
						ai,
						msg,
						scroll,
					)
					section_top += _hub_section_body_height(section, columns)
				else:
					for subsection_index in subsections.size():
						var subsection: Dictionary = subsections[subsection_index]
						var subsection_id := String(subsection["id"])
						var subsection_key := _hub_subsection_key(subsection_id)
						var subsection_collapsed := _hub_section_collapsed(subsection_key)
						_add_hub_section_title(
							content,
							String(subsection["title"]),
							Vector2(grid_x + HUB_SUBSECTION_INDENT, section_top),
							grid_w - HUB_SUBSECTION_INDENT,
							subsection_key,
							subsection_id,
							subsection_collapsed,
							false,
							scroll,
							ai,
							msg,
							choosing_ai_deck,
						)
						section_top += HUB_SUBSECTION_TITLE_H
						if not subsection_collapsed:
							var subsection_tile := _add_hub_section_body(
								content,
								subsection,
								grid_x,
								section_top,
								grid_w,
								columns,
								selected_id,
								choosing_ai_deck,
								ai,
								msg,
								scroll,
							)
							if subsection_tile != null:
								selected_tile = subsection_tile
							section_top += _hub_section_body_height(subsection, columns)
						if subsection_index < subsections.size() - 1:
							section_top += HUB_SUBSECTION_GAP
			else:
				var section_tile := _add_hub_section_body(
					content,
					section,
					grid_x,
					section_top,
					grid_w,
					columns,
					selected_id,
					choosing_ai_deck,
					ai,
					msg,
					scroll,
				)
				if section_tile != null:
					selected_tile = section_tile
				section_top += _hub_section_body_height(section, columns)
		if section_index < gallery_sections.size() - 1:
			section_top += HUB_SECTION_GAP
	# edge fades: a hint that there are more decks above or below
	if content_h > body_h:
		for at_top in [true, false]:
			var edge := _hub_edge_fade(at_top)
			edge.position = Vector2(gallery_x, body_top if at_top else body_bottom - 48.0)
			edge.size = Vector2(gallery_w, 48)
			host.layer.add_child(edge)
			scroll.get_v_scroll_bar().value_changed.connect(
				func(_v: float) -> void:
					_update_hub_edge(edge, scroll, at_top),
			)
			_update_hub_edge.call_deferred(edge, scroll, at_top)
	_restore_hub_scroll.call_deferred(scroll, hub_scroll_y, selected_tile)
	var y := body_bottom + 20.0

	var actions: Array = []
	if ai and not choosing_ai_deck:
		actions.append(
			[
				"PRÓXIMO: DECK DO JOGADOR 2" if hub_hotseat else "PRÓXIMO: DECK DA IA",
				func() -> void:
					hub_scroll_y = 0
					show_hub.call_deferred(true, "", true),
				true,
			]
		)
	elif ai:
		actions.append(
			[
				"JOGAR",
				func() -> void:
					var opponent_deck := ai_deck
					if opponent_deck == "":
						var others := playable_ids.filter(
							func(d: String) -> bool:
								return d != sel_deck,
						)
						opponent_deck = String(others.pick_random()) if not others.is_empty() else sel_deck
					host._start(not hub_hotseat, sel_deck, opponent_deck),
				true,
			]
		)
	elif host.net.load_session():
		actions.append(
			[
				"RETOMAR PARTIDA (%s)" % host.net.code,
				func() -> void:
					host.online = true
					host.net.resume(),
				true,
			]
		)
	if not ai:
		actions.append(
			[
				"CRIAR SALA",
				func() -> void:
					host.online = true
					host.net.create(sel_deck)
					show_wait("Criando sala…"),
				true,
			]
		)
		actions.append(
			[
				"ENTRAR COM CÓDIGO",
				func() -> void:
					code_entry = ""
					_show_join(),
				false,
			]
		)
	# one row: Voltar on the left, then the actions
	var bw := 400.0
	var back_w := 240.0
	var row_w := back_w + actions.size() * (bw + 24.0)
	var bx: float = (host.stage_w - row_w) / 2.0
	# from the AI-deck step, Voltar goes back to picking your own deck
	var back_action: Callable = show_menu
	if choosing_ai_deck:
		back_action = func() -> void:
			hub_scroll_y = 0
			show_hub.call_deferred(true)
	var bk: Button = host._button("Voltar", back_action)
	bk.position = Vector2(bx, y)
	bk.size = Vector2(back_w, 72)
	host.layer.add_child(bk)
	for i in actions.size():
		var b: Button = host._button(actions[i][0], actions[i][1], actions[i][2])
		b.position = Vector2(bx + back_w + 24.0 + i * (bw + 24.0), y)
		b.size = Vector2(bw, 72)
		host.layer.add_child(b)


## Height of the deck tiles below a section title, or of its empty-state hint.
func _hub_section_body_height(section: Dictionary, columns: int) -> float:
	var tile_count: int = section.get("ids", []).size()
	if tile_count == 0:
		return HUB_EMPTY_HINT_H if String(section.get("hint", "")) != "" else 0.0
	var rows := ceili(float(tile_count) / float(columns))
	return rows * HUB_TILE.y + (rows - 1) * HUB_TILE_GAP


func _hub_macro_body_height(section: Dictionary, columns: int) -> float:
	if not section.has("subsections"):
		return _hub_section_body_height(section, columns)
	var subsections: Array = section["subsections"]
	if subsections.is_empty():
		return _hub_section_body_height(section, columns)
	var height := 0.0
	for i in subsections.size():
		var subsection: Dictionary = subsections[i]
		height += HUB_SUBSECTION_TITLE_H
		if not _hub_section_collapsed(_hub_subsection_key(String(subsection["id"]))):
			height += _hub_section_body_height(subsection, columns)
		if i < subsections.size() - 1:
			height += HUB_SUBSECTION_GAP
	return height


## Set 1's prebuilt decks are the classic essentials; later sets use their registered full names.
func _hub_prebuilt_subsections(deck_ids: Array[String]) -> Array:
	var classic_ids: Array[String] = []
	var set_groups := { }
	for deck_id in deck_ids:
		var deck := DeckDB.get_deck(deck_id)
		var leader_id := String(deck["leader"])
		var incarnation_id := String(CardDB.leader(leader_id)["incarnation"])
		var set_number := CardDB.set_number_of(CardDB.card(incarnation_id))
		if set_number <= 1:
			classic_ids.append(deck_id)
			continue
		if not set_groups.has(set_number):
			set_groups[set_number] = []
		var group_ids: Array = set_groups[set_number]
		group_ids.append(deck_id)
	var subsections: Array = []
	if not classic_ids.is_empty():
		subsections.append({ "id": "classic", "title": "ESSENCIAIS CLÁSSICOS", "ids": classic_ids })
	for set_number in CardDB.set_numbers():
		if int(set_number) <= 1 or not set_groups.has(int(set_number)):
			continue
		subsections.append(
			{ "id": "set_%d" % int(set_number), "title": CardDB.set_full_name(int(set_number)), "ids": set_groups[int(set_number)] }
		)
	return subsections


func _hub_macro_key(section_id: String) -> String:
	return "macro:" + section_id


func _hub_subsection_key(subsection_id: String) -> String:
	return "subsection:" + subsection_id


func _hub_section_collapsed(key: String) -> bool:
	return bool(hub_collapsed.get(key, false))


func _toggle_hub_section(key: String, scroll: ScrollContainer, ai: bool, msg: String, choosing_ai_deck: bool) -> void:
	hub_collapsed[key] = not _hub_section_collapsed(key)
	if is_instance_valid(scroll):
		hub_scroll_y = scroll.scroll_vertical
	show_hub.call_deferred(ai, msg, choosing_ai_deck)


func _add_hub_section_body(
	content: Control,
	section: Dictionary,
	grid_x: float,
	y: float,
	grid_w: float,
	columns: int,
	selected_id: String,
	choosing_ai_deck: bool,
	ai: bool,
	msg: String,
	scroll: ScrollContainer,
) -> Control:
	var section_ids: Array = section.get("ids", [])
	if section_ids.is_empty():
		var hint_text := String(section.get("hint", ""))
		if hint_text != "":
			var hint: Label = host._label(hint_text, 18, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, "body")
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.position = Vector2(grid_x, y)
			hint.size = Vector2(grid_w, HUB_EMPTY_HINT_H)
			content.add_child(hint)
		return null
	var selected_tile: Control = null
	for i in section_ids.size():
		var id: String = section_ids[i]
		var tile := deck_tile(id, HUB_TILE, id == selected_id)
		tile.position = Vector2(grid_x + (i % columns) * (HUB_TILE.x + HUB_TILE_GAP), y + (i / columns) * (HUB_TILE.y + HUB_TILE_GAP))
		if id == selected_id:
			selected_tile = tile
		tile.gui_input.connect(_on_hub_tile_input.bind(tile, id, choosing_ai_deck, ai, msg, scroll))
		content.add_child(tile)
	return selected_tile


func _on_hub_tile_input(
	ev: InputEvent,
	tile: Control,
	id: String,
	choosing_ai_deck: bool,
	ai: bool,
	msg: String,
	scroll: ScrollContainer,
) -> void:
	# picks on release, and not at the end of a scroll drag
	var mb := ev as InputEventMouseButton
	if mb == null or mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or hub_drag_distance > HUB_DRAG_SLOP:
		return
	if DeckLeaderTooltipScript.consume_tap(tile):
		return
	if id != "" and DeckDB.is_deck_banned(id):
		Sfx.play("ui_click")
		host._toast("Este Líder está BANIDO: só pode ser usado no modo de desenvolvimento.")
		return
	if choosing_ai_deck:
		ai_deck = id
	elif sel_deck != id:
		sel_deck = id
	else:
		return
	hub_scroll_y = scroll.scroll_vertical
	show_hub.call_deferred(ai, msg, choosing_ai_deck)


## Registers the player's saved decks (MEUS DECKS) in DeckDB so the hub, the match and the deck list treat
## them like prebuilt ones. Only decks that already pass every rule can be played; the rest are counted.
func _refresh_player_decks() -> void:
	if deck_store == null:
		use_deck_store(DeckStore.new())
	DeckDB.clear_custom(DeckDB.PLAYER_PREFIX)
	incomplete_player_decks = 0
	for saved_deck in deck_store.list():
		var leader_id := String(saved_deck["leader"])
		if leader_id == "" or not DeckDB.validate_cards(leader_id, saved_deck["cards"], String(saved_deck.get("incarnation_id", ""))).is_empty():
			incomplete_player_decks += 1
			continue
		DeckDB.register_custom(
			DeckDB.PLAYER_PREFIX + String(saved_deck["id"]),
			String(saved_deck["name"]),
			String(saved_deck["description"]),
			leader_id,
			saved_deck["cards"],
			String(saved_deck.get("incarnation_id", "")),
		)


func use_deck_store(store: DeckStore) -> void:
	deck_store = store
	host.add_child(deck_store)
	deck_store.changed.connect(_on_player_decks_changed)


## The account's decks arrive (or change) after the hub was drawn: draw it again with them.
func _on_player_decks_changed() -> void:
	if is_instance_valid(host.hub_scroll) and host.hub_scroll.is_visible_in_tree() and _hub_args.size() == 3:
		hub_scroll_y = host.hub_scroll.scroll_vertical
		show_hub.call_deferred(_hub_args[0], _hub_args[1], _hub_args[2])


func refresh_hub_stats_if_due() -> void:
	if SupabaseAuth.is_signed_in() and Time.get_ticks_msec() - host._hub_stats_refresh_at >= 30000:
		host._hub_stats_refresh_at = Time.get_ticks_msec()
		SupabaseAuth.refresh_deck_stats()


## Puts the deck gallery back where it was scrolled before the redraw, then makes sure the chosen
## deck's tile is in view (e.g. when coming back to the hub with a deck far down the list).
func _restore_hub_scroll(scroll: ScrollContainer, scroll_y: int, selected_tile: Control) -> void:
	if not is_instance_valid(scroll):
		return
	scroll.scroll_vertical = scroll_y
	if selected_tile != null and is_instance_valid(selected_tile):
		scroll.ensure_control_visible(selected_tile)


## A strip that fades the gallery's top or bottom edge into the background.
func _hub_edge_fade(at_top: bool) -> TextureRect:
	var fade := GradientTexture2D.new()
	var grad := Gradient.new()
	var dark := Color(0.02, 0.02, 0.035)
	grad.colors = PackedColorArray([Color(dark, 0.9), Color(dark, 0.0)] if at_top else [Color(dark, 0.0), Color(dark, 0.9)])
	fade.gradient = grad
	fade.fill_from = Vector2(0, 0)
	fade.fill_to = Vector2(0, 1)
	var edge := TextureRect.new()
	edge.texture = fade
	edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return edge


## Shows an edge fade only while there is more gallery hidden past that edge.
func _update_hub_edge(edge: Control, scroll: ScrollContainer, at_top: bool) -> void:
	if not is_instance_valid(edge) or not is_instance_valid(scroll):
		return
	var bar := scroll.get_v_scroll_bar()
	var hidden_past_edge := bar.value > 1.0 if at_top else bar.value < bar.max_value - bar.page - 1.0
	edge.modulate.a = 1.0 if hidden_past_edge else 0.0


## Wheel and finger-drag scrolling of the deck gallery (the tiles swallow those events before the
## ScrollContainer sees them). Also measures how far a press has moved, so a drag doesn't pick a deck.
func hub_scroll_input(e: InputEvent) -> bool:
	if not is_instance_valid(host.hub_scroll) or not host.hub_scroll.is_visible_in_tree():
		return false
	var xf: Transform2D = host.hub_scroll.get_global_transform_with_canvas()
	var local: Vector2 = xf.affine_inverse() * e.position if "position" in e else Vector2(-1, -1)
	var inside := Rect2(Vector2.ZERO, host.hub_scroll.size).has_point(local)
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
		hub_drag_distance = 0.0 # a new press: nothing dragged yet
		return false
	if not inside:
		return false
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		host.hub_scroll.scroll_vertical += (-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1) * 120
		return true
	var drag_y := 0.0
	if e is InputEventScreenDrag:
		drag_y = e.relative.y
	elif e is InputEventMouseMotion and not CardView.touched and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		drag_y = e.relative.y # mouse drag on desktop (on phones the finger already came as a ScreenDrag)
	else:
		return false
	hub_drag_distance += absf(drag_y)
	if hub_drag_distance > HUB_DRAG_SLOP:
		host.hub_scroll.scroll_vertical -= int(drag_y / xf.get_scale().y)
	return true


## The big panel on the left of the hub: the chosen deck's Leader art, name, Leader line, Encarnação,
## full description and size. `id` "" is the AI's "random deck" choice.
func _deck_showcase(id: String, size: Vector2, choosing_ai_deck: bool) -> Control:
	var bg := Color(0.06, 0.055, 0.085, 0.96)
	var p := Panel.new()
	p.size = size
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var who := ("DECK DO JOGADOR 2" if hub_hotseat else "DECK DA IA") if choosing_ai_deck else (
		"JOGADOR 1" if hub_hotseat else "SEU DECK"
	)
	if id == "":
		p.add_theme_stylebox_override("panel", UITheme.box(bg, 16, UITheme.GOLD, 3, 20))
		var mark: Label = host._label("?", 220, Color(UITheme.GOLD_LIGHT, 0.5), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 8)
		mark.position = Vector2(0, size.y * 0.12)
		mark.size = Vector2(size.x, 300)
		p.add_child(mark)
		_showcase_text(
			p,
			size,
			who,
			"Deck Aleatório",
			"",
			UITheme.GOLD_LIGHT,
			"A IA joga com um dos outros decks, sorteado na hora de começar.",
			"",
			size.y * 0.5,
		)
		return p
	var d := DeckDB.get_deck(id)
	var ld := CardDB.leader(d["leader"])
	var col := Color(String(CardDB.essence(CardDB.leader_essences(ld)[0]).get("color", "#8a8f98")))
	p.add_theme_stylebox_override("panel", UITheme.box(bg, 16, Color(col, 0.85), 3, 20))
	var art_h := size.y * 0.5
	var art := TextureRect.new()
	art.texture = host._top_crop(
		CardView.texture(String(ld.get("art", ""))),
		Vector2(size.x - 8, art_h),
		float(ld.get("art_focus", 0.06)),
	)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.position = Vector2(4, 4)
	art.size = Vector2(size.x - 8, art_h)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(art)
	p.add_child(_art_fade(bg, Vector2(4, 4 + art_h * 0.45), Vector2(size.x - 8, art_h * 0.55 + 1)))
	var leader_line := "%s · %d de vida · %s" % [ld["name"], int(ld["hp"]), CardDB.leader_essence_names(ld)]
	var incarnation_id := DeckDB.resolved_incarnation_id(String(d["leader"]), String(d.get("incarnation_id", "")))
	var footer := "%d cartas · Encarnação: %s" % [DeckDB.card_count(id), CardDB.card(incarnation_id)["name"]]
	_showcase_text(p, size, who, String(d["name"]), leader_line, col, String(d.get("description", "")), footer, art_h - 30.0)
	p.add_child(_decklist_button(id, size))
	return p


## A small "list" pill in the showcase's top right corner: opens the deck's card list (DecklistView).
func _decklist_button(id: String, showcase_size: Vector2) -> Button:
	var button_size := Vector2(176.0, 64.0)
	var button := Button.new()
	button.custom_minimum_size = button_size
	button.size = button_size
	button.position = Vector2(showcase_size.x - button_size.x - 18.0, 18.0)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Ver a lista de cartas do deck."
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(40.0, button_size.y / 2.0)
	icon.draw.connect(
		func():
			# the universal "list" icon: three lines, each with a bullet in front
			for line_y in [-14.0, 0.0, 14.0]:
				icon.draw_circle(Vector2(-18.0, line_y), 3.5, UITheme.GOLD_LIGHT)
				icon.draw_line(Vector2(-8.0, line_y), Vector2(20.0, line_y), UITheme.GOLD_LIGHT, 3.5),
	)
	button.add_child(icon)
	var caption: Label = host._label("LISTA", 26, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, "bold")
	caption.position = Vector2(80.0, 0.0)
	caption.size = Vector2(button_size.x - 88.0, button_size.y)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(caption)
	button.pressed.connect(Sfx.play.bind("ui_click"))
	button.pressed.connect(
		func():
			_open_decklist(id),
	)
	return button

# ---------------------------------------------------------------- deck list


## Opens the deck list window. A tap on one of its cards shows the match's own card overlay on top of it.
func _open_decklist(deck_id: String) -> void:
	close_decklist()
	host.decklist_view = DecklistView.new().open(deck_id, Vector2(host.stage_w, host.STAGE_H))
	host.decklist_view.closed.connect(close_decklist)
	host.decklist_view.card_chosen.connect(_show_decklist_card)
	host.add_child(host.decklist_view)


func close_decklist() -> void:
	if host.decklist_view == null:
		return
	var old_view: DecklistView = host.decklist_view
	host.decklist_view = null
	if old_view.get_parent() != null:
		old_view.get_parent().remove_child(old_view)
	old_view.queue_free()


## The overlay needs a CardView to read from; a plain printed card (no match state) is enough here.
func _show_decklist_card(card_id: String) -> void:
	var printed_card := CardView.new().setup(card_id, { }, 1.0)
	host.table_overlays.show_overlay(printed_card)
	printed_card.free()


## The showcase's text block, from `top` down: a small "SEU DECK" tag, the deck name, the Leader line,
## the full description (wrapped, and smaller only if it would not fit) and a footer.
func _showcase_text(
	p: Control,
	size: Vector2,
	who: String,
	deck_name: String,
	leader_line: String,
	col: Color,
	description: String,
	footer: String,
	top: float,
) -> void:
	var tag: Label = host._label(who, 15, Color(UITheme.GOLD, 0.9), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 3)
	tag.position = Vector2(20, top - 26.0)
	tag.size = Vector2(size.x - 40, 22)
	p.add_child(tag)
	var nm: Label = host._label(deck_name, 40, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 8)
	nm.position = Vector2(20, top - 6.0)
	nm.size = Vector2(size.x - 40, 52)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	p.add_child(nm)
	var y := top + 50.0
	if leader_line != "":
		var lead: Label = host._label(leader_line, 19, col.lightened(0.35), HORIZONTAL_ALIGNMENT_CENTER, "bold", 3)
		lead.position = Vector2(20, y)
		lead.size = Vector2(size.x - 40, 26)
		lead.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		p.add_child(lead)
		y += 32.0
	p.add_child(ornament(Vector2(size.x / 2.0, y + 8.0), 140))
	y += 26.0
	var footer_h := 40.0 if footer != "" else 0.0
	var room := size.y - y - footer_h - 16.0
	var blurb: Label = host._label(description, 23, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "body", 3)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.position = Vector2(32, y)
	blurb.size = Vector2(size.x - 64, room)
	# a very long description steps the font down until it fits, instead of being cut off
	for font_size in [23, 21, 19, 17]:
		blurb.add_theme_font_size_override("font_size", font_size)
		if blurb.get_line_count() * blurb.get_line_height() <= room:
			break
	p.add_child(blurb)
	if footer != "":
		var foot: Label = host._label(footer, 17, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold", 3)
		foot.position = Vector2(20, size.y - footer_h)
		foot.size = Vector2(size.x - 40, 24)
		foot.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		p.add_child(foot)


## A gradient that melts the bottom of a portrait into the panel color.
func _art_fade(bg: Color, pos: Vector2, size: Vector2) -> TextureRect:
	var fade := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(bg, 0.0), Color(bg, 1.0)])
	fade.gradient = grad
	fade.fill_from = Vector2(0, 0)
	fade.fill_to = Vector2(0, 1)
	var veil := TextureRect.new()
	veil.texture = fade
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.position = pos
	veil.size = size
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return veil


## One deck in the hub gallery: Leader art, deck name and domain seals. Always the same size (the full
## description lives in the showcase). `id` "" is the AI's "random deck" tile.
func deck_tile(id: String, size: Vector2, selected: bool) -> Control:
	var bg := Color(0.06, 0.055, 0.085, 0.94)
	var col := UITheme.GOLD_LIGHT
	var p := Panel.new()
	p.size = size
	p.pivot_offset = size / 2.0
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var art_h := size.y * 0.6
	var deck_name := "Aleatório"
	var leader_name := "sorteado ao jogar"
	if id == "":
		var mark: Label = host._label("?", 96, Color(UITheme.GOLD_LIGHT, 0.55), HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6)
		mark.position = Vector2(0, art_h * 0.12)
		mark.size = Vector2(size.x, art_h)
		p.add_child(mark)
	else:
		var d := DeckDB.get_deck(id)
		var ld := CardDB.leader(d["leader"])
		col = Color(String(CardDB.essence(CardDB.leader_essences(ld)[0]).get("color", "#8a8f98")))
		deck_name = String(d["name"])
		leader_name = String(ld["name"])
		var art := TextureRect.new()
		art.texture = host._top_crop(
			CardView.texture(String(ld.get("art", ""))),
			Vector2(size.x - 8, art_h),
			float(ld.get("art_focus", 0.06)),
		)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.position = Vector2(4, 4)
		art.size = Vector2(size.x - 8, art_h)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(art)
		p.add_child(_art_fade(bg, Vector2(4, 4 + art_h * 0.5), Vector2(size.x - 8, art_h * 0.5 + 1)))
	p.add_theme_stylebox_override(
		"panel",
		UITheme.box(bg, 12, UITheme.GOLD if selected else Color(col, 0.55), 4 if selected else 2, 12 if selected else 6),
	)
	# the name gets the zone between the art and domain seals, and never grows past it: it shrinks
	# step by step until it fits in two lines, and only a name too long even for the smallest step is cut with "…"
	var nm: Label = host._label(
		deck_name,
		DECK_TILE_NAME_FONT_SIZES[0],
		UITheme.GOLD_LIGHT,
		HORIZONTAL_ALIGNMENT_CENTER,
		"title_bold",
		5,
	)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	nm.position = Vector2(8, art_h - 14.0)
	nm.size = Vector2(size.x - 16, size.y - 34.0 - nm.position.y)
	for font_size in DECK_TILE_NAME_FONT_SIZES:
		nm.add_theme_font_size_override("font_size", font_size)
		if nm.get_line_count() <= 2 and nm.get_line_count() * nm.get_line_height() <= nm.size.y:
			break
	nm.max_lines_visible = 2
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	p.tooltip_text = deck_name
	p.add_child(nm)
	if id != "":
		var domain_deck := DeckDB.get_deck(id)
		var incarnation_id := DeckDB.resolved_incarnation_id(
			String(domain_deck["leader"]),
			String(domain_deck.get("incarnation_id", "")),
		)
		var domains := DeckDB.domains_in(String(domain_deck["leader"]), domain_deck.get("cards", { }), incarnation_id)
		DeckLeaderTooltipScript.attach(p, leader_name)
		_add_deck_tile_stats(p, nm, id)
		var domain_row := DomainIconRowScript.new().setup(domains, 24.5, 2)
		domain_row.position = Vector2(8, size.y - 31.0)
		domain_row.size = Vector2(size.x - 16, 28)
		p.add_child(domain_row)
	if id != "" and DeckDB.is_deck_banned(id):
		BannedRibbonScript.attach(p)
	if selected:
		# drawn with shapes: the "✔" character is missing from the web font and showed as a broken square on phones
		var check := HubGlyphIconScript.make(HubGlyphIconScript.Kind.CHECK, 18.0, UITheme.GOLD_LIGHT)
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", UITheme.box(Color(UITheme.GOLD.darkened(0.6), 0.95), 15, UITheme.GOLD, 2))
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.custom_minimum_size = Vector2(32, 32)
		badge.add_child(check)
		badge.position = Vector2(size.x - 42, 10)
		p.add_child(badge)
	# hover (mouse only): a gentle lift so the gallery feels alive on desktop
	p.mouse_entered.connect(
		func() -> void:
			if not CardView.touched:
				p.create_tween().tween_property(p, "scale", Vector2.ONE * 1.04, 0.12),
	)
	p.mouse_exited.connect(
		func() -> void:
			p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.12),
	)
	return p


## Alternate the name with this account's online record without moving the domain seals.
func _add_deck_tile_stats(tile: Control, name_label: Label, deck_id: String) -> void:
	var stats_box := Control.new()
	stats_box.name = "DeckStats"
	stats_box.position = name_label.position
	stats_box.size = name_label.size
	stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_box.modulate.a = 0.0
	tile.add_child(stats_box)
	var status := String(SupabaseAuth.state.get("stats_status", "guest"))
	if not SupabaseAuth.is_signed_in():
		status = "guest"
	if status != "ready":
		var message := "ENTRE NA CONTA" if status == "guest" else ("CARREGANDO…" if status == "loading" else "INDISPONÍVEL")
		var hint: Label = host._label(message, 16, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold")
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.size = stats_box.size
		stats_box.add_child(hint)
	else:
		var record := { }
		for row in SupabaseAuth.state.get("deck_stats", []):
			if row is Dictionary and String(row.get("deck_key", "")) == deck_id:
				record = row
				break
		var games := int(record.get("games", 0))
		var wins := int(record.get("wins", 0))
		var losses := int(record.get("losses", 0))
		var draws := int(record.get("draws", 0))
		tile.tooltip_text = "%s\n%d partidas · %d vitórias · %d derrotas · %d empate%s" % [
			tile.tooltip_text,
			games,
			wins,
			losses,
			draws,
			"" if draws == 1 else "s",
		]
		var parts := [
			{ "name": "Games", "text": "%d J" % games, "color": UITheme.TEXT },
			{ "name": "Separator1", "text": "·", "color": UITheme.TEXT },
			{ "name": "Wins", "text": "%d V" % wins, "color": Color("#58c77d") },
			{ "name": "Separator2", "text": "·", "color": UITheme.TEXT },
			{ "name": "Losses", "text": "%d D" % losses, "color": Color("#dc5b5b") },
		]
		var totals_size := 17
		var font := UITheme.font("bold")
		while totals_size > 7:
			var total_width := 16.0
			for part in parts:
				total_width += font.get_string_size(part.text, HORIZONTAL_ALIGNMENT_LEFT, -1, totals_size).x
			if total_width <= stats_box.size.x:
				break
			totals_size -= 1
		var totals := HBoxContainer.new()
		totals.name = "Totals"
		totals.alignment = BoxContainer.ALIGNMENT_CENTER
		totals.add_theme_constant_override("separation", 4)
		totals.size = Vector2(stats_box.size.x, 24)
		totals.mouse_filter = Control.MOUSE_FILTER_IGNORE
		totals.clip_contents = true
		stats_box.add_child(totals)
		for part in parts:
			var label: Label = host._label(part.text, totals_size, part.color, HORIZONTAL_ALIGNMENT_CENTER, "bold")
			label.name = part.name
			totals.add_child(label)
		var rate_text := "%d%% VITÓRIAS" % roundi(100.0 * wins / games) if games > 0 else "SEM PARTIDAS"
		if draws > 0:
			rate_text += " · %d E" % draws
		var rate_size := 16
		while rate_size > 7 and font.get_string_size(rate_text, HORIZONTAL_ALIGNMENT_LEFT, -1, rate_size).x > stats_box.size.x:
			rate_size -= 1
		var rate: Label = host._label(rate_text, rate_size, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "bold")
		rate.name = "WinRate"
		rate.position = Vector2(0, 24)
		rate.size = Vector2(stats_box.size.x, 22)
		rate.clip_text = true
		stats_box.add_child(rate)
		var bar := ColorRect.new()
		bar.name = "ResultsBar"
		bar.position = Vector2(4, stats_box.size.y - 10)
		bar.size = Vector2(stats_box.size.x - 8, 7)
		bar.color = Color("#35343b")
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats_box.add_child(bar)
		var win_width := bar.size.x * float(wins) / games if games > 0 else 0.0
		var loss_width := bar.size.x * float(losses) / games if games > 0 else 0.0
		for segment in [
			{ "name": "Wins", "x": 0.0, "width": win_width, "color": Color("#58c77d") },
			{ "name": "Losses", "x": win_width, "width": loss_width, "color": Color("#dc5b5b") },
		]:
			var rect := ColorRect.new()
			rect.name = segment.name
			rect.position.x = segment.x
			rect.size = Vector2(segment.width, bar.size.y)
			rect.color = segment.color
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.add_child(rect)
	tile.tree_entered.connect(
		func() -> void:
			var tween := tile.create_tween().set_loops()
			tween.tween_interval(3.5)
			tween.tween_property(name_label, "modulate:a", 0.0, 0.45)
			tween.parallel().tween_property(stats_box, "modulate:a", 1.0, 0.45)
			tween.tween_interval(3.5)
			tween.tween_property(name_label, "modulate:a", 1.0, 0.45)
			tween.parallel().tween_property(stats_box, "modulate:a", 0.0, 0.45),
	)


## A full-width button gives each gallery level a clear, independently collapsible header.
func _add_hub_section_title(
	content: Control,
	title_text: String,
	pos: Vector2,
	width: float,
	key: String,
	node_name: String,
	collapsed: bool,
	macro: bool,
	scroll: ScrollContainer,
	ai: bool,
	msg: String,
	choosing_ai_deck: bool,
) -> void:
	var button := Button.new()
	button.name = ("HubMacro_" if macro else "HubSubsection_") + node_name
	button.text = title_text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.position = pos
	button.size = Vector2(width, HUB_SECTION_TITLE_H if macro else HUB_SUBSECTION_TITLE_H)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", UITheme.font("title_bold" if macro else "bold"))
	button.add_theme_font_size_override("font_size", 22 if macro else 18)
	button.add_theme_color_override("font_color", UITheme.GOLD_LIGHT if macro else UITheme.TEXT)
	button.add_theme_color_override("font_hover_color", UITheme.GOLD_LIGHT)
	var normal := UITheme.box(Color("#171a27") if macro else Color("#1a222f"), 6, Color(UITheme.GOLD, 0.55 if macro else 0.3), 1)
	normal.set_border_width_all(0)
	if macro:
		normal.border_width_bottom = 2
	else:
		normal.border_width_left = 3
	normal.set_content_margin_all(10)
	# room on the left for the arrow icon (drawn with shapes: the "▸" and "▾" characters are missing
	# from the web font and showed as broken squares on phones)
	var arrow_size := 16.0 if macro else 14.0
	normal.content_margin_left = 10.0 + arrow_size + 10.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#292538" if macro else "#252f3d")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(Sfx.play.bind("ui_click"))
	button.pressed.connect(_toggle_hub_section.bind(key, scroll, ai, msg, choosing_ai_deck))
	var arrow_kind = HubGlyphIconScript.Kind.ARROW_RIGHT if collapsed else HubGlyphIconScript.Kind.ARROW_DOWN
	var arrow := HubGlyphIconScript.make(arrow_kind, arrow_size, UITheme.GOLD_LIGHT if macro else UITheme.TEXT)
	arrow.position = Vector2(10.0, (button.size.y - arrow_size) * 0.5)
	button.add_child(arrow)
	content.add_child(button)


## Join screen: 4-letter room code keypad, entering with the deck picked in the hub.
func _show_join(msg := "") -> void:
	host._clear_fx()
	host._clear()
	host.table.visible = false
	host._set_tints(Color("#3f7bd9"), Color("#e0572b"), 1.6)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.position = Vector2(host.stage_w / 2.0 - 300, 90)
	box.custom_minimum_size = Vector2(600, 0)
	host.layer.add_child(box)
	box.add_child(host._label("ENTRAR NA SALA", 48, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 8))
	box.add_child(
		host._label(
			msg if msg != "" else "Deck: %s" % DeckDB.get_deck(sel_deck)["name"],
			22,
			UITheme.TEXT,
			HORIZONTAL_ALIGNMENT_CENTER,
			"bold",
		)
	)
	var slots: Label = host._label(_code_text(), 64, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 6)
	host.join_slots = slots
	box.add_child(slots)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for ch in ROOM_CODE_LETTERS:
		var kb: Button = host._button(ch, _type_room_code_letter.bind(ch))
		kb.custom_minimum_size = Vector2(68, 60)
		kb.add_theme_font_size_override("font_size", 26)
		grid.add_child(kb)
	var back: Button = host._button("⌫", _erase_room_code_letter)
	back.custom_minimum_size = Vector2(68, 60)
	back.add_theme_font_size_override("font_size", 26)
	grid.add_child(back)
	var go: Button = host._button("ENTRAR NA SALA", _join_typed_room, true)
	go.custom_minimum_size = Vector2(600, 64)
	box.add_child(go)
	var bk: Button = host._button(
		"Voltar",
		func() -> void:
			show_online(),
	)
	bk.custom_minimum_size = Vector2(600, 52)
	box.add_child(bk)


func _code_text() -> String:
	return code_entry + "_".repeat(4 - code_entry.length())


## Letters a room code can use (no I, L or O: they look like 1 and 0).
const ROOM_CODE_LETTERS := "ABCDEFGHJKMNPQRSTUVWXYZ"


func _type_room_code_letter(letter: String) -> void:
	if code_entry.length() < 4:
		code_entry += letter
		host.join_slots.text = _code_text()


func _erase_room_code_letter() -> void:
	code_entry = code_entry.substr(0, code_entry.length() - 1)
	host.join_slots.text = _code_text()


func _join_typed_room() -> void:
	if code_entry.length() == 4:
		host.online = true
		host.net.join(code_entry, sel_deck)
		show_wait("Entrando na sala…")


## The physical keyboard types into the join screen like its on-screen keypad does.
## Returns true when the key was used.
func join_screen_key(key: InputEventKey) -> bool:
	if host.join_slots == null:
		return false
	if key.keycode == KEY_BACKSPACE:
		_erase_room_code_letter()
		return true
	if key.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_join_typed_room()
		return true
	var letter := char(key.unicode).to_upper()
	if key.unicode != 0 and ROOM_CODE_LETTERS.contains(letter):
		_type_room_code_letter(letter)
		return true
	return false


## Space / Enter during a game press the main action button on screen (PASSAR, RESOLVER, ENCERRAR
## TURNO, IR PARA O COMBATE...), the same as clicking it. Choices that need a deliberate answer
## (mulligan, enter tapped, discard...) are left to the mouse.
func press_main_action_with_keyboard() -> bool:
	if host.g == null or host.g.phase not in ["main", "combat"] or host.overlay or host.grave_view or host.concede_view:
		return false
	for action_button: Button in host.get_tree().get_nodes_in_group("action_buttons"):
		if (
				action_button.theme_type_variation == "PrimaryButton" and not action_button.disabled \
					and action_button.is_visible_in_tree()
			and not action_button.is_queued_for_deletion()
		):
			action_button.pressed.emit()
			return true
	return false


func show_wait(text: String, show_code := "") -> void:
	host._clear_fx()
	host._clear()
	host.table.visible = false
	host._set_tints(Color("#3f7bd9"), Color("#e0572b"), 1.6)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	box.position = Vector2(host.stage_w / 2.0 - 300, 260)
	box.custom_minimum_size = Vector2(600, 0)
	host.layer.add_child(box)
	if show_code != "":
		box.add_child(host._label("CÓDIGO DA SALA", 26, UITheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
		box.add_child(host._label(show_code, 120, UITheme.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, "title_bold", 12))
	box.add_child(host._label(text, 28, UITheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER, "bold"))
	var c: Button = host._button(
		"Cancelar",
		func():
			host.net.forget()
			host.net.disconnect_server()
			host.online = false
			show_menu(),
	)
	c.custom_minimum_size = Vector2(600, 56)
	box.add_child(c)
