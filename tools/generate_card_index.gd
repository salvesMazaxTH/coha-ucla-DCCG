extends SceneTree
## Writes docs/INDICE_CARTAS.md: every card of the game grouped by set and then by domain, so a card can be
## found without digging through data/cards/. Run it after creating or renaming cards:
## Godot --headless --path . -s tools/generate_card_index.gd

const OUTPUT_PATH := "res://docs/INDICE_CARTAS.md"
const RARITY_LABELS := {"common": "Comum", "epic": "Épica", "champion": "Campeã", "legendary": "Lendária"}
const TYPE_LABELS := {"unit": "Unidade", "spell": "Feitiço", "artifact": "Artefato"}

func _init() -> void:
	var catalog: Dictionary = CardDB.data()
	var lines: PackedStringArray = []
	lines.append("# Índice de cartas")
	lines.append("")
	lines.append("Gerado por `tools/generate_card_index.gd`: não edite à mão. Cada carta está em `data/cards/<set>/<domínio>/<id>.json`.")
	lines.append("")
	for set_number in CardDB.set_numbers():
		var cards_of_set := _card_ids_of_set(catalog["cards"], set_number)
		lines.append("## Set %d: %s (%d cartas)" % [set_number, CardDB.set_full_name(set_number), cards_of_set.size()])
		lines.append("")
		if cards_of_set.is_empty():
			lines.append("Nenhuma carta ainda.")
			lines.append("")
			continue
		for essence_id in catalog["essences"]:
			var cards_of_domain := cards_of_set.filter(func(card_id: String): return _folder_essence_of(catalog["cards"][card_id]) == essence_id)
			if cards_of_domain.is_empty():
				continue
			lines.append("### %s (%d)" % [catalog["essences"][essence_id]["name"], cards_of_domain.size()])
			lines.append("")
			lines.append("| ID | Nome | Raridade | Tipo | Custo |")
			lines.append("|---|---|---|---|---|")
			for card_id in cards_of_domain:
				var card: Dictionary = catalog["cards"][card_id]
				lines.append("| `%s` | %s | %s | %s | %s |" % [card_id, card["name"], RARITY_LABELS.get(card.get("rarity", ""), card.get("rarity", "")), TYPE_LABELS.get(card["type"], card["type"]), str(int(card["cost"]))])
			lines.append("")
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	file.store_string("\n".join(lines))
	file.close()
	print("índice escrito em ", OUTPUT_PATH, " (", catalog["cards"].size(), " cartas)")
	quit()

## The ids of the cards whose "set" is `set_number`, sorted by name.
func _card_ids_of_set(cards: Dictionary, set_number: int) -> Array:
	var ids := cards.keys().filter(func(card_id: String): return CardDB.set_number_of(cards[card_id]) == set_number)
	ids.sort_custom(func(first: String, second: String): return String(cards[first]["name"]).naturalnocasecmp_to(String(cards[second]["name"])) < 0)
	return ids

## The domain a card is filed under: its first essence ("neutra" when it has none).
func _folder_essence_of(card: Dictionary) -> String:
	var essence: Variant = card.get("essence", "neutra")
	return String(essence[0]) if essence is Array else String(essence)
