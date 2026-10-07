extends SceneTree
## NetClient + RemoteState against a running match server (see net_smoke.gd for how to start it).
##   godot --headless --path . -s tests/net_client_smoke.gd

var c: Array = []
var states: Array = [null, null]
var step := 0
var failures := 0
var t0 := Time.get_ticks_msec()
var code := ""
var got := [0, 0]

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	for i in 2:
		var n := NetClient.new()
		root.add_child(n)
		n.message.connect(_on_msg.bind(i))
		c.append(n)
	c[0].create("fogo")

func _on_msg(m: Dictionary, i: int) -> void:
	match m["t"]:
		"room":
			if i == 0 and step == 0:
				code = m["code"]
				check(m["seat"] == 0, "seat 0")
				c[1].join(code, "agua")
				step = 1
		"start":
			var d: Array = m["decks"]
			var rs := RemoteState.new(d[0], d[1])
			rs.send = c[i].send
			rs.apply_snapshot(m["snap"])
			states[i] = rs
			check(rs.players[i]["hand"][0]["uid"] is int, "uid is int")
			check(rs.players[i]["hand"][0]["card_id"] != "", "own hand visible")
			check(rs.decider() == 0, "seat 0 decides mulligan")
			if i == 1:
				step = 2
				(states[0] as RemoteState).mulligan(0, [])
		"events":
			(states[i] as RemoteState).apply_snapshot(m["snap"])
			got[i] += 1
			if step == 2 and got[0] == 1 and got[1] == 1:
				step = 3
				(states[1] as RemoteState).mulligan(1, [])
			elif step == 3 and got[0] == 2 and got[1] == 2:
				var g0: RemoteState = states[0]
				check(g0.phase == "main" and g0.decider() == 0, "main phase")
				var playable := 0
				for card in g0.players[0]["hand"]:
					if g0.can_play(0, card["uid"]):
						playable += 1
				print("playable cards for seat 0: ", playable)
				print("net client smoke done, failures: ", failures)
				quit(failures)

func _process(_d: float) -> bool:
	if Time.get_ticks_msec() - t0 > 8000:
		printerr("FAIL: timeout at step ", step)
		quit(1)
	return false
