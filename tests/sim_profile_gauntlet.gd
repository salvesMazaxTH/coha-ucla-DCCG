extends SceneTree
## Plays one deck under a forced AI profile against every other prebuilt (each in its own profile).
##   godot --headless --path . -s tests/sim_profile_gauntlet.gd -- deck profile games_per_matchup


func _init() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var tested: String = args[0]
	var forced_profile: String = args[1]
	var games: int = int(args[2]) if args.size() > 2 else 40
	var by_opponent_profile := { "aggro": [0, 0], "midrange": [0, 0], "control": [0, 0] }
	var started := Time.get_ticks_msec()
	for opponent: String in DeckDB.ids():
		if opponent == tested or opponent.begins_with("mine:"):
			continue
		var opponent_profile := String(DeckDB.get_deck(opponent).get("ai_profile", AIProfile.DEFAULT))
		var wins := 0
		var played := 0
		for s in range(1, games + 1):
			var first := s % 2
			var g := GameState.new(tested, opponent, s, first)
			g.players[0]["ai_profile_override"] = forced_profile
			var guard := 0
			while g.phase != "over" and guard < 5000:
				guard += 1
				if SimpleAI.step(g, g.decider()).is_empty():
					break
			if g.phase != "over":
				continue
			played += 1
			if g.winner == 0:
				wins += 1
		by_opponent_profile[opponent_profile][0] += wins
		by_opponent_profile[opponent_profile][1] += played
		print("RESULT %s %s vs %s (%s): %d/%d" % [tested, forced_profile, opponent, opponent_profile, wins, played])
	var total_wins := 0
	var total_played := 0
	for key: String in by_opponent_profile:
		var row: Array = by_opponent_profile[key]
		total_wins += row[0]
		total_played += row[1]
		print("SUMMARY %s %s vs %s: %d/%d (%.1f%%)" % [tested, forced_profile, key, row[0], row[1], 100.0 * row[0] / max(1, row[1])])
	print(
		"SUMMARY %s %s total: %d/%d (%.1f%%) em %ds"
		% [
			tested,
			forced_profile,
			total_wins,
			total_played,
			100.0 * total_wins / max(1, total_played),
			(Time.get_ticks_msec() - started) / 1000,
		]
	)
	quit()
