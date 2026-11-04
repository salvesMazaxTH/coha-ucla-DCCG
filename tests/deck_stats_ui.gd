extends SceneTree

func _init() -> void:
	await process_frame
	var auth := root.get_node("SupabaseAuth")
	auth.set_process(false)
	auth.state = {"signed_in": true, "stats_status": "ready", "deck_stats": [
		{"deck_key": "fogo", "games": 5, "wins": 3, "losses": 1, "draws": 1}
	]}
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var tile: Control = main._deck_tile("fogo", Vector2(210, 236), false)
	main.add_child(tile)
	var box: Control = tile.get_node("DeckStats")
	var texts: Array[String] = []
	for child in box.get_children():
		if child is Label:
			texts.append(child.text)
	if not texts.has("5 J  ·  3 V  ·  1 D") or not texts.has("60% VITÓRIAS · 1 E"):
		push_error("Estatísticas incorretas: %s" % [texts])
		quit(1)
		return
	if not tile.tooltip_text.contains("1 empate") or box.modulate.a != 0.0:
		push_error("Estado inicial ou tooltip das estatísticas incorreto")
		quit(1)
		return
	var bar: ColorRect = box.get_node("ResultsBar")
	var wins: ColorRect = bar.get_node("Wins")
	var losses: ColorRect = bar.get_node("Losses")
	if not is_equal_approx(wins.size.x, bar.size.x * 0.6) or not is_equal_approx(losses.size.x, bar.size.x * 0.2) or not is_equal_approx(losses.position.x, wins.size.x):
		push_error("Proporções da barra de vitórias, derrotas e empates incorretas")
		quit(1)
		return
	await create_timer(4.2).timeout
	if box.modulate.a < 0.95:
		push_error("Animação não revelou as estatísticas")
		quit(1)
		return
	await create_timer(4.0).timeout
	if box.modulate.a > 0.05:
		push_error("Animação não voltou ao nome do deck")
		quit(1)
		return
	auth.state = {"signed_in": false, "stats_status": "guest", "deck_stats": []}
	var guest_tile: Control = main._deck_tile("fogo", Vector2(210, 236), false)
	main.add_child(guest_tile)
	var guest_label: Label = guest_tile.get_node("DeckStats").get_child(0)
	if guest_label.text != "ENTRE NA CONTA":
		push_error("Convidado recebeu estatísticas de conta")
		quit(1)
		return
	auth.state = {"signed_in": true, "stats_status": "ready", "deck_stats": []}
	var empty_tile: Control = main._deck_tile("agua", Vector2(210, 236), false)
	main.add_child(empty_tile)
	var empty_box: Control = empty_tile.get_node("DeckStats")
	if empty_box.get_child(1).text != "SEM PARTIDAS" or empty_box.get_node("ResultsBar/Wins").size.x != 0:
		push_error("Deck sem partidas não deve mostrar porcentagem nem vitórias")
		quit(1)
		return
	print("deck stats UI passed")
	quit()
