class_name CardOverlay
extends RefCounted
## The content of the card detail overlay (the big card plus the full-text panel next to it).
## Main shows it when a card is clicked during a match; tools/view_card.gd shows the very same
## thing, so what you see there is exactly what the players see in game.

const BIG_CARD_SCALE := 4.18
const BIG_CARD_Y := 150.0
const TEXT_PANEL_Y := 160.0
const TEXT_PANEL_HEIGHT := 640.0
const StatModifiersPanel := preload("res://scripts/ui/stat_modifiers_panel.gd")
## The Modificadores column sits left of the big card, as tall as it. On a narrow stage the card shrinks a
## little so the column fits; its right edge stays put, so the rules text never moves.
const MODIFIERS_GAP := 14.0 ## between the column and the big card
const MODIFIERS_SCREEN_MARGIN := 16.0 ## between the column and the left edge of the screen
const MODIFIERS_MIN_WIDTH := 236.0
const MODIFIERS_MAX_WIDTH := 300.0

## Adds the big card and the text panel to `parent` (a Control as wide as the stage).
## Returns the x where the text panel starts, so Main can put its action buttons below it.
## `instance` is the live card state ({} for a card that is not on the table).
static func build(parent: Control, stage_width: float, card_id: String, instance: Dictionary = {},
		cost_override: int = -1, text_suffix: String = "", snowball_level: int = 0) -> float:
	var modifier_rows := StatModifiersPanel.rows_for(card_id, instance)
	var card_scale := big_card_scale(stage_width, not modifier_rows.is_empty())
	var big := CardView.new().setup(card_id, instance, card_scale)
	big.cost_override = cost_override
	big.text_suffix = text_suffix
	big.snowball_level = snowball_level
	big.position = big_card_position(stage_width, card_scale)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(big)
	var panel := RichTextLabel.new()
	panel.bbcode_enabled = true
	panel.text = describe(card_id, instance, cost_override, text_suffix, snowball_level)
	var panel_x := stage_width / 2.0 - 90.0 # card (4.18 * 120 = ~502 px) ends at stage_width/2 - 118
	var panel_width := stage_width - 40.0 - panel_x
	if not modifier_rows.is_empty():
		# Added before the text panel on purpose: Main finds the text panel as the overlay's last child.
		var column_width := minf(MODIFIERS_MAX_WIDTH, big.position.x - MODIFIERS_GAP - MODIFIERS_SCREEN_MARGIN)
		var column_x := big.position.x - MODIFIERS_GAP - column_width
		StatModifiersPanel.add_to(parent, Vector2(column_x, BIG_CARD_Y), column_width, CardView.BASE.y * card_scale, modifier_rows)
	panel.position = Vector2(panel_x, TEXT_PANEL_Y)
	panel.size = Vector2(panel_width, TEXT_PANEL_HEIGHT)
	panel.add_theme_font_size_override("normal_font_size", 28)
	panel.add_theme_font_size_override("bold_font_size", 28)
	panel.add_theme_font_size_override("italics_font_size", 24)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel_x

## How big the big card is drawn: the usual size, or a bit smaller when the Modificadores column
## needs room on its left and the stage is too narrow to give it.
static func big_card_scale(stage_width: float, has_modifiers: bool) -> float:
	if not has_modifiers:
		return BIG_CARD_SCALE
	var room_for_card := _big_card_right(stage_width) - MODIFIERS_SCREEN_MARGIN - MODIFIERS_MIN_WIDTH - MODIFIERS_GAP
	return minf(BIG_CARD_SCALE, room_for_card / CardView.BASE.x)

## Where the big card sits (its top-left corner) on a stage `stage_width` wide. A shrunk card keeps
## its right edge where the full-size card ends, so the text panel stays in place.
static func big_card_position(stage_width: float, card_scale: float = BIG_CARD_SCALE) -> Vector2:
	return Vector2(_big_card_right(stage_width) - CardView.BASE.x * card_scale, BIG_CARD_Y)

## The x where the full-size big card ends.
static func _big_card_right(stage_width: float) -> float:
	return stage_width / 2.0 - 620 + CardView.BASE.x * BIG_CARD_SCALE

## The card exactly as it was printed: no live instance, so no buffs, debuffs, markers, overrides or
## resets, and no cost, text or Bola de Neve adjustments. Sits right on top of the big card, hidden;
## the caller shows it while the "ver carta base" button is held. Returns it so the caller can toggle it.
static func build_base_card(parent: Control, stage_width: float, card_id: String,
		card_scale: float = BIG_CARD_SCALE) -> CardView:
	var base_card := CardView.new().setup(card_id, {}, card_scale)
	base_card.position = big_card_position(stage_width, card_scale)
	base_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_card.visible = false
	parent.add_child(base_card)
	return base_card

## Puts the live count ("(agora: 3)") at the end of the Constante paragraph it counts for, so a card
## with other abilities around it (Zulmira's Ao Ativar, Berengar's Ao Entrar) does not look like the
## count belongs to the last line. Cards without a Constante line (the Gigantes) get it at the very end.
static func with_live_count(body: String, text_suffix: String) -> String:
	if text_suffix == "":
		return body
	var lines := body.split("\n")
	for line_index in lines.size():
		if lines[line_index].begins_with("Constante:"):
			lines[line_index] += text_suffix
			return "\n".join(lines)
	return body + text_suffix

## The BBCode of the text panel: name, kind line, rules text, keyword glossary, Leader note, flavor.
static func describe(card_id: String, instance: Dictionary, cost_override: int, text_suffix: String,
		snowball_level: int) -> String:
	var cd := CardDB.card_for(card_id, instance)
	var txt := "[font_size=48][color=#e8c25a]%s[/color][/font_size]\n" % cd["name"]
	var rarity_names := {"legendary": "Lendário", "champion": "Campeão", "epic": "Unidade Épica", "common": "Unidade Comum"}
	var type_names := {"unit": rarity_names.get(cd["rarity"], "Unidade"), "spell": "Feitiço", "artifact": "Artefato"}
	var kind: String = type_names[cd["type"]]
	if CardDB.is_unit_artifact(cd):
		# a unit that is also an artifact: "Unidade-Artefato Comum" (champions and legendaries have no "Unidade" in their label)
		kind = kind.replace("Unidade", "Unidade-Artefato") if kind.begins_with("Unidade") else kind + " · Artefato"
	if CardDB.is_equipment(cd):
		kind += " · Equipamento"
	elif CardDB.is_local(cd):
		kind += " · Local"
	if CardDB.species_names(cd) != "":
		kind += " — " + CardDB.species_names(cd)
	var shown_cost: int = cost_override if cost_override >= 0 else int(cd["cost"])
	var element_label := ""
	if CardDB.element_names(cd) != "":
		element_label = " · Elemento: " + CardDB.element_names(cd) # the tag that card texts refer to ("feitiço de Gelo")
	txt += "[color=#aaaaaa]%s · %s%s · custo %d[/color]\n\n" % [kind, CardDB.essence_names(cd), element_label, shown_cost]
	if cd.get("text", "") != "":
		var body := with_live_count(CardView.fill_live_numbers(String(cd["text"]), snowball_level), text_suffix)
		# a Condicional with a per-turn limit (Seymour) shows how many uses are already spent, like the Leader power does
		if instance.has("conditional_uses_now"):
			var per_turn_limit := int(cd.get("conditional_uses_per_turn", 0))
			body = body.replace("(%dx por turno)" % per_turn_limit,
					"(%dx por turno — usadas %d/%d)" % [per_turn_limit, int(instance["conditional_uses_now"]), per_turn_limit])
		if instance.has("durability_left"):
			body += "

[b]Durabilidade: %d/%d[/b]" % [int(instance["durability_left"]), int(cd["durability"])]
		if instance.has("stored_momentum"):
			body += "

[b]Momentum guardado: %d/%d[/b]" % [int(instance["stored_momentum"]), int(cd["momentum_store"])]
		if instance.has("stun_markers"):
			body = "[color=#ffd36b][b]Atordoada (%d):[/b] fica exausta, não ataca e perde a Rapidez; cada marcador custa um desvirar (é removido no início do turno de quem a controla). Sua Provocação não obriga ataques. Revida normalmente.[/color]
" % int(instance["stun_markers"]) + body
		if instance.has("frozen"):
			body = "[color=#9fe8ff][b]Congelada:[/b] não ataca, não desvira e perde a Rapidez (suprimida) até o fim do próximo turno. Revida normalmente.[/color]\n" + body
		txt += "[font_size=32]%s[/font_size]\n\n" % CardView.colorize_rules(body, 32)
	if CardDB.is_equipment(cd):
		txt += "[font_size=32][b]Regra inata:[/b] Uma unidade só pode ter um Equipamento por vez. Se receber outro, o anterior volta para a mão do dono.[/font_size]\n\n"
	# Glossary: the card's own keywords first, then any keyword its text mentions ("conceda Voo").
	var glossary_keywords: Array = cd.get("keywords", []).duplicate()
	if CardView.armor_of_view(cd, instance) > 0 and not glossary_keywords.has("armadura"):
		glossary_keywords.append("armadura") # "armadura:N" leaves the keyword list (it is a stat), but the card shows it as a tag
	if maxi(int(instance.get("rapidez", cd.get("rapidez", 0))), int(instance.get("rapidez_until_next_turn", 0))) > 0 and not instance.has("frozen") and not instance.has("stun_markers"):
		glossary_keywords.append("rapidez") # shown as a tag on the card, so the glossary explains it
	if CardView.critico_of_view(cd, instance) > 0 and not glossary_keywords.has("critico"):
		glossary_keywords.append("critico") # also shown as a tag (it can grow during the match)
	if CardView.attacks_allowed_of_view(cd, instance) >= 2 and not glossary_keywords.has("ataque_duplo"):
		glossary_keywords.append("ataque_duplo") # earned in play (Vael at Crítico 4), shown as a tag too
	for dot_id in ["queimadura", "veneno", "sangramento"]:
		if CardView.dot_marker_count_of_view(instance, dot_id) > 0 and not glossary_keywords.has(dot_id):
			glossary_keywords.append(dot_id) # live marker: the enlarged view explains its timing and count
	if instance.has("condemned_turn") and not glossary_keywords.has("condenada"):
		glossary_keywords.append("condenada") # live marker: the enlarged view explains it
	if instance.get("shield", false) and not glossary_keywords.has("escudo"):
		glossary_keywords.append("escudo") # live protection: it is visible as a tag, so explain it in the overlay
	if instance.get("magic_shield", false) and not glossary_keywords.has("escudo_magico"):
		glossary_keywords.append("escudo_magico") # live protection: it is visible as a tag, so explain it in the overlay
	if instance.get("supreme_shield", false) and not glossary_keywords.has("escudo_supremo"):
		glossary_keywords.append("escudo_supremo") # live protection (can be granted for a while): explain it in the overlay
	for keyword_id in mentioned_keywords(String(cd.get("text", "")) + text_suffix):
		if not glossary_keywords.has(keyword_id):
			glossary_keywords.append(keyword_id)
	for keyword_id in glossary_keywords:
		var keyword := CardDB.keyword(keyword_id)
		var keyword_color := CardView.keyword_color(keyword_id).to_html(false)
		txt += "[color=#%s][b]%s[/b][/color] — %s\n" % [keyword_color, keyword["name"], CardView.colorize_rules(keyword_text(cd, keyword_id, keyword, instance))]
	if bool(instance.get("incarnation", false)):
		txt += "\n[color=#e8c25a]Encarnação do Líder:[/color] fica no Santuário. Cada nova conjuração custa mais que a anterior: +1, depois +2, +3, +4... Pode voltar para a mão (jogada de lá, custa o custo normal). Ao ir para o cemitério ou ser banida, volta para o Santuário; se a próxima conjuração passaria de %d, vai para o fundo do deck como carta comum, com o custo normal.\n" % [GameState.MOMENTUM_CAP]
	elif CardDB.is_leader_card(card_id):
		txt += "\n[color=#e8c25a]Elegível como Encarnação:[/color] pode ser escolhida no deck de um Líder com o mesmo nome. Se não for a cópia escolhida, é uma Campeã normal e pode ser jogada da mão.\n"
	if cd.get("token", false):
		txt += "\n[color=#9ad0c0]Ficha:[/color] não vai para o cemitério e nunca vai para a mão: se fosse, é apagada do jogo.\n"
	var flavor := CardDB.flavor_for(cd, true)
	if flavor != "":
		txt += "\n[i][color=#888888]%s[/color][/i]" % flavor
	return txt

## Glossary line of a keyword for this card: Esquiva explains the card's own rule (the default one,
## or "esquiva": {"max_rapidez": N}), every other keyword uses the shared text.
static func keyword_text(cd: Dictionary, kw: String, k: Dictionary, instance: Dictionary = {}) -> String:
	var rule: Dictionary = cd.get("esquiva", {})
	if kw == "esquiva" and rule.has("max_rapidez"):
		var level := int(rule["max_rapidez"])
		var speed_limit := "sem Rapidez" if level == 0 else "Rapidez %d ou menos" % level
		return "A primeira vez em cada turno que receberia dano de combate de uma unidade %s, o dano é evitado." % speed_limit
	if kw == "critico":
		# shared rule plus this unit's own live chance (temporary levels included), so nobody has to do the X * 25% math
		var critico_level := CardView.critico_of_view(cd, instance)
		var temporary_note := ""
		if int(instance.get("temp_critico", 0)) > 0:
			temporary_note = " (+%d até o fim do turno)" % int(instance["temp_critico"])
		return "%s Esta unidade: Crítico %d%s = %d%% de chance." % [k["text"], critico_level, temporary_note, CardView.critico_chance_percent(critico_level)]
	if kw == "ataque_duplo" and instance.has("damage"):
		# on the board: how many of the two attacks this turn are already spent
		return "%s Ataques neste turno: %d de 2." % [k["text"], int(instance.get("attacks_made", 0))]
	return k["text"]

## Keyword ids whose names appear in a rules text, in the order they appear (no repeats).
static func mentioned_keywords(text: String) -> Array:
	var mentions: Array[Dictionary] = []
	var keywords: Dictionary = CardDB.data()["keywords"]
	for span in CardView.keyword_ranges(text):
		var mentioned := text.substr(span[0], span[1] - span[0])
		for id in keywords:
			var keyword: Dictionary = keywords[id]
			var name := String(keyword["name"])
			# "Armadura 1" starts with "Armadura"; the others need an exact match
			# (so "Escudo Mágico" doesn't also count as "Escudo").
			var name_matches := mentioned.to_lower() == name.to_lower()
			var with_value: bool = keyword.get("has_value", false) and mentioned.to_lower().begins_with((name + " ").to_lower())
			for alias in keyword.get("aliases", []):
				name_matches = name_matches or mentioned.to_lower() == String(alias).to_lower()
				with_value = with_value or (keyword.get("has_value", false) and mentioned.to_lower().begins_with((String(alias) + " ").to_lower()))
			if name_matches or with_value:
				mentions.append({"id": id, "start": span[0]})
				break
	var freeze_aliases := RegEx.new()
	freeze_aliases.compile(r"(?i)(?<!\p{L})congel(?:ar|a|am|e|em|ado|ada|ados|adas|amento|amentos)(?!\p{L})")
	for match in freeze_aliases.search_all(text):
		mentions.append({"id": "congelar", "start": match.get_start()})
	mentions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["start"]) < int(b["start"]))
	var found: Array = []
	for mention in mentions:
		var id := String(mention["id"])
		if not found.has(id):
			found.append(id)
	return found
