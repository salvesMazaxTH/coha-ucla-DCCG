extends SceneTree

func _init() -> void:
	var original := OS.get_environment("MATCH_STATS_QUEUE_PATH")
	var path := "user://stats_test_%s.json" % Crypto.new().generate_random_bytes(8).hex_encode()
	OS.set_environment("MATCH_STATS_QUEUE_PATH", path)
	var script := load("res://scripts/net/match_stats_server.gd")
	var stats: Node = script.new()
	stats.set_process(false)
	root.add_child(stats)
	await process_frame
	var identities := [
		{"user_id": "11111111-1111-4111-8111-111111111111", "deck_key": "fogo"},
		{"user_id": "22222222-2222-4222-8222-222222222222", "deck_key": "mine:example"},
	]
	var ok: bool = stats.enqueue("test-draw", identities, 2)
	ok = stats.enqueue("test-guest", [{}, {}], 0) and ok
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not ok or not saved is Array or saved.size() != 1 or saved[0].results.size() != 2:
		push_error("A fila não preservou o empate ou gravou partida de convidados")
		quit(1)
		return
	if saved[0].results[0].result != "draw" or saved[0].results[1].result != "draw":
		push_error("Resultado de empate incorreto")
		quit(1)
		return
	var restarted: Node = script.new()
	restarted.set_process(false)
	root.add_child(restarted)
	await process_frame
	if restarted.pending.size() != 1 or restarted.pending[0].match_id != "test-draw":
		push_error("A fila pendente não foi recuperada após reiniciar")
		quit(1)
		return
	stats.queue_free()
	restarted.queue_free()
	OS.set_environment("MATCH_STATS_QUEUE_PATH", original)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("deck stats queue passed")
	quit()
