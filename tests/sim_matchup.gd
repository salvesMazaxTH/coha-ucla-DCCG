extends SceneTree
## AI vs AI between two decks (default Ronan/fogo vs Naelthos/agua), alternating who goes first.
##   godot --headless --path . -s tests/sim_matchup.gd -- 300 [deck_a] [deck_b]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 300
	var decks: Array = [args[1] if args.size() > 1 else "fogo", args[2] if args.size() > 2 else "agua"]
	# [seat][went first? 1 : 0] -> [wins, games]
	var stats := [[[0, 0], [0, 0]], [[0, 0], [0, 0]]]
	var draws := 0
	var stuck := 0
	var turns := 0
	for s in range(1, n + 1):
		var f := s % 2
		var g := GameState.new(decks[0], decks[1], s, f)
		var guard := 0
		while g.phase != "over" and guard < 5000:
			guard += 1
			if SimpleAI.step(g, g.decider()).is_empty():
				break
		if g.phase != "over":
			stuck += 1
			continue
		turns += g.turn
		for p in 2:
			var row: Array = stats[p][1 if p == f else 0]
			row[1] += 1
			if g.winner == p:
				row[0] += 1
		if g.winner < 0 or g.winner > 1:
			draws += 1
	var played := n - stuck
	print("partidas: %d (travadas: %d, empates: %d, turnos médios: %.1f)" % [played, stuck, draws, float(turns) / max(1, played)])
	var first_w := 0
	for d in 2:
		var name := "%s (assento %d)" % [CardDB.leader(GameState.new(decks[0], decks[1], 1).players[d]["leader_id"])["name"], d]
		var a: Array = stats[d]
		var w: int = a[0][0] + a[1][0]
		var t: int = a[0][1] + a[1][1]
		first_w += a[1][0]
		print("%s: %d vitórias (%.1f%%) | 1º: %d/%d (%.1f%%) | 2º: %d/%d (%.1f%%)" % [name, w, 100.0 * w / max(1, t),
			a[1][0], a[1][1], 100.0 * a[1][0] / max(1, a[1][1]), a[0][0], a[0][1], 100.0 * a[0][0] / max(1, a[0][1])])
	print("quem joga primeiro: %d/%d (%.1f%%) | segundo: %d/%d (%.1f%%)" % [first_w, played, 100.0 * first_w / max(1, played),
		played - draws - first_w, played, 100.0 * (played - draws - first_w) / max(1, played)])
	quit()
