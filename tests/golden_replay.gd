extends SceneTree
## Golden replay: seeded AI vs AI games whose full event log (plus each seat's final snapshot)
## must stay identical across engine refactors. Recording overwrites tests/golden/*.json:
##   godot --headless --path . -s tests/golden_replay.gd
## run_tests.gd calls compare() and fails on the first divergent line of each game.

const DIR := "res://tests/golden/"
const SEEDS := [1, 2]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var n := 0
	for pair in pairs():
		var games := {}
		for s in SEEDS:
			games[str(s)] = play(pair[0], pair[1], s)
		var f := FileAccess.open(_path(pair), FileAccess.WRITE)
		f.store_string(JSON.stringify(games, "\t"))
		n += SEEDS.size()
	print("golden: %d partidas gravadas" % n)
	quit()

static func pairs() -> Array:
	var out: Array = []
	for a in DeckDB.ids():
		for b in DeckDB.ids():
			if a != b:
				out.append([a, b])
	return out

static func _path(pair: Array) -> String:
	return DIR + "%s__%s.json" % pair

## One line per AI step (its events, keys sorted), then the final snapshot of each seat.
static func play(a: String, b: String, s: int) -> Array:
	var g := GameState.new(a, b, s, s % 2)
	var lines: Array = []
	var guard := 0
	while g.phase != "over" and guard < 5000:
		guard += 1
		var ev := SimpleAI.step(g, g.decider())
		if ev.is_empty():
			break
		lines.append(JSON.stringify(ev, "", true))
	for seat in 2:
		lines.append(JSON.stringify(StateView.snapshot(g, seat), "", true))
	return lines

## Empty when every recorded game replays identically; otherwise one message per divergent game.
static func compare() -> Array[String]:
	var errs: Array[String] = []
	for pair in pairs():
		if not FileAccess.file_exists(_path(pair)):
			errs.append("golden faltando: %s (rode tests/golden_replay.gd)" % _path(pair))
			continue
		var games: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_path(pair)))
		for s in SEEDS:
			var want: Array = games[str(s)]
			var got := play(pair[0], pair[1], s)
			for i in maxi(want.size(), got.size()):
				var w: String = want[i] if i < want.size() else "<fim>"
				var h: String = got[i] if i < got.size() else "<fim>"
				if w != h:
					errs.append("golden %s x %s seed %d, linha %d:\n  esperado: %s\n  obtido:   %s" % [pair[0], pair[1], s, i, w.left(400), h.left(400)])
					break
	return errs
