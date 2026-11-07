extends SceneTree

func _init() -> void:
	await process_frame
	var builder = load("res://scripts/ui/deck_builder.gd").new()
	builder.local_deck_path = "user://deck_builder_type_counts_test.json"
	root.add_child(builder)
	await process_frame
	var template: Dictionary = DeckDB.get_deck("obscura_lento")
	builder._open_editor({"id": "", "name": "Teste", "leader": template["leader"], "cards": {}})
	await process_frame
	await process_frame
	for card_type in ["unit", "spell", "artifact"]:
		var type_label: Label = builder._type_labels[card_type]["label"]
		if type_label.size.x < type_label.get_combined_minimum_size().x:
			push_error("Contagem de %s não cabe no painel" % card_type)
			quit(1)
			return
	if builder._list_box.get_parent().size.y <= 0:
		push_error("Lista de cartas ficou sem espaço no painel")
		quit(1)
		return
	var ids := {}
	for id in CardDB.data()["cards"]:
		var card_type := String(CardDB.card(String(id)).get("type", ""))
		if card_type in ["unit", "spell", "artifact"] and not ids.has(card_type) and String(id) != builder._incarnation_id and DeckDB.is_deckable(String(id), builder._leader) and DeckDB.copy_limit(String(id)) >= 2:
			ids[card_type] = String(id)
	if ids.size() != 3:
		push_error("Catálogo precisa de unidade, feitiço e artefato com ao menos duas cópias")
		quit(1)
		return
	if not _check_counts(builder, [0, 0, 0]):
		return
	for card_type in ["unit", "spell", "artifact"]:
		builder._add_card(ids[card_type])
	builder._add_card(ids["spell"])
	if not _check_counts(builder, [1, 2, 1]):
		return
	builder._remove_card(ids["spell"])
	if not _check_counts(builder, [1, 1, 1]):
		return
	builder._cards = {builder._incarnation_id: 1}
	builder._refresh_deck_panel()
	if not _check_counts(builder, [0, 0, 0]):
		return
	builder._cards[builder._incarnation_id] = 2
	builder._refresh_deck_panel()
	var expected := [0, 0, 0]
	var incarnation_type := String(CardDB.card(builder._incarnation_id).get("type", ""))
	var index := ["unit", "spell", "artifact"].find(incarnation_type)
	if index >= 0:
		expected[index] = 1
	if not _check_counts(builder, expected):
		return
	builder._cards = {builder._incarnation_id: 1}
	builder._autofill_deck()
	var filled_counts := [0, 0, 0]
	var types := ["unit", "spell", "artifact"]
	for id in builder._cards:
		var type_index := types.find(String(CardDB.card(String(id)).get("type", "")))
		if type_index >= 0:
			filled_counts[type_index] += int(builder._cards[id]) - (1 if String(id) == builder._incarnation_id else 0)
	if filled_counts[0] + filled_counts[1] + filled_counts[2] != DeckDB.DECK_SIZE or not _check_counts(builder, filled_counts):
		push_error("Contagens incorretas após completar o deck")
		quit(1)
		return
	builder._ask_clear()
	var confirm: Button = builder._modal.get_child(1).get_child(0).get_child(0).get_child(2).get_child(1)
	confirm.pressed.emit()
	if not _check_counts(builder, [0, 0, 0]):
		return
	print("deck builder type counts passed")
	quit()

func _check_counts(builder, expected: Array) -> bool:
	var types := ["unit", "spell", "artifact"]
	var titles := ["Unidades", "Feitiços", "Artefatos"]
	for i in types.size():
		var label: Label = builder._type_labels[types[i]]["label"]
		if label.text != "%s: %d" % [titles[i], expected[i]]:
			push_error("Contagem incorreta: %s, esperado %s: %d" % [label.text, titles[i], expected[i]])
			quit(1)
			return false
	return true
