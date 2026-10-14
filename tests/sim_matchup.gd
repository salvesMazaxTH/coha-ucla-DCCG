extends SceneTree
## AI vs AI between two decks (default Ronan/fogo vs Naelthos/agua), alternating who goes first.
##   godot --headless --path . -s tests/sim_matchup.gd -- 300 [deck_a] [deck_b] [piloto]
## With "piloto", seat 0 (deck_a, meant to be glacial_combo) is played by the scripted ComboPilot.

const ComboPilot = preload("res://tests/combo_pilot.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 300
	var use_pilot := args.size() > 3 and args[3] == "piloto"
	var decks: Array = [args[1] if args.size() > 1 else "fogo", args[2] if args.size() > 2 else "agua"]
	# [seat][went first? 1 : 0] -> [wins, games]
	var stats := [[[0, 0], [0, 0]], [[0, 0], [0, 0]]]
	var draws := 0
	var stuck := 0
	var turns := 0
	var seat_zero_win_rounds := {} # the winner's own turn number -> how many of seat 0's wins ended then
	for s in range(1, n + 1):
		var f := s % 2
		var g := GameState.new(decks[0], decks[1], s, f)
		var guard := 0
		while g.phase != "over" and guard < 5000:
			guard += 1
			var decider: int = g.decider()
			var events: Array = ComboPilot.step(g, decider) if use_pilot and decider == 0 else SimpleAI.step(g, decider)
			if events.is_empty():
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
		if g.winner == 0:
			# g.turn counts both players' turns; the winner's own turn number is half of it, rounded up if they went first
			var own_turn: int = (g.turn + 1) / 2 if f == 0 else g.turn / 2
			seat_zero_win_rounds[own_turn] = int(seat_zero_win_rounds.get(own_turn, 0)) + 1
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
	var cumulative := 0
	var seat_zero_wins: int = stats[0][0][0] + stats[0][1][0]
	var cumulative_text := ""
	for own_turn in range(1, 31):
		cumulative += int(seat_zero_win_rounds.get(own_turn, 0))
		if own_turn in [5, 6, 7, 8, 9, 10, 12, 15, 20]:
			cumulative_text += " até T%d: %.0f%%" % [own_turn, 100.0 * cumulative / max(1, seat_zero_wins)]
	print("vitórias do assento 0 por turno próprio (acumulado):" + cumulative_text)
	if use_pilot:
		for own_turn in range(5, 13):
			var samples: Array = ComboPilot.potential_by_turn.get(own_turn, [])
			if samples.is_empty():
				continue
			var total := 0
			var best := 0
			var with_combo := 0
			for damage: int in samples:
				total += damage
				best = maxi(best, damage)
				if damage > 0:
					with_combo += 1
			print("dano do melhor combo disponível no T%d: média %.1f | máx %d | com combo montável: %d/%d" % [own_turn, float(total) / samples.size(), best, with_combo, samples.size()])
		print("maior dano previsto ao Líder num combo disparado pelo piloto: %d" % ComboPilot.biggest_fired_prediction)
	quit()
