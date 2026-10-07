extends SceneTree
## Integration smoke test against a running match server:
##   godot --headless --path . -s scripts/net/match_server.gd -- 8061   (other terminal)
##   godot --headless --path . -s tests/net_smoke.gd -- 8061

var a := WebSocketPeer.new()
var b := WebSocketPeer.new()
var inbox := [[], []]
var failures := 0
var step := 0
var code := ""
var started := false
var t0 := Time.get_ticks_msec()

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)

func _initialize() -> void:
	var port := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "8061"
	a.connect_to_url("ws://127.0.0.1:" + port)
	b.connect_to_url("ws://127.0.0.1:" + port)

func _pump() -> void:
	for i in 2:
		var ws: WebSocketPeer = [a, b][i]
		ws.poll()
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			inbox[i].append(JSON.parse_string(ws.get_packet().get_string_from_utf8()))

func _take(i: int, type: String) -> Variant:
	for m in inbox[i]:
		if m["t"] == type:
			inbox[i].erase(m)
			return m
	return null

func _send(ws: WebSocketPeer, m: Dictionary) -> void:
	ws.send_text(JSON.stringify(m))

func _process(_d: float) -> bool:
	_pump()
	if Time.get_ticks_msec() - t0 > 8000:
		printerr("FAIL: timeout at step ", step)
		quit(1)
		return true
	if a.get_ready_state() != WebSocketPeer.STATE_OPEN or b.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	match step:
		0:
			_send(a, {"t": "create", "deck": "fogo"})
			step = 1
		1:
			var m = _take(0, "room")
			if m:
				code = m["code"]
				check(m["seat"] == 0, "host seat 0")
				_send(b, {"t": "join", "code": code, "deck": "agua"})
				step = 2
		2:
			var sa = _take(0, "start")
			var sb = _take(1, "start")
			if sa and sb:
				var snap_a: Dictionary = sa["snap"]
				var snap_b: Dictionary = sb["snap"]
				check(sa["seat"] == 0 and sb["seat"] == 1, "seats")
				check(snap_a["players"][0]["hand"][0]["card_id"] != "", "own hand visible")
				check(snap_a["players"][1]["hand"].size() == 7 and snap_a["players"][1]["hand"][0]["card_id"] == "", "opponent hand hidden (a)")
				check(snap_b["players"][0]["hand"][0]["card_id"] == "", "opponent hand hidden (b)")
				check(snap_a["players"][0]["deck"][0]["card_id"] == "", "deck hidden")
				_send(b, {"t": "act", "a": "end_turn"}) # not B's turn: must be rejected
				step = 3
		3:
			var m = _take(1, "reject")
			if m:
				_send(a, {"t": "act", "a": "mulligan", "uids": []})
				step = 4
		4:
			var ea = _take(0, "events")
			var eb = _take(1, "events")
			if ea and eb:
				_send(b, {"t": "act", "a": "mulligan", "uids": []})
				step = 5
		5:
			var ea = _take(0, "events")
			var eb = _take(1, "events")
			if ea and eb:
				check(ea["snap"]["phase"] == "main" and ea["snap"]["active"] == 0, "main phase, seat 0 active")
				_send(a, {"t": "act", "a": "end_turn"})
				step = 6
		6:
			var ea = _take(0, "events")
			if ea:
				check(ea["snap"]["active"] == 1, "turn passed")
				print("net smoke done, failures: ", failures)
				quit(failures)
				return true
	return false
