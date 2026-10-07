extends SceneTree
## Authoritative match server. GameState lives only here; clients send actions and
## receive events plus a per-seat snapshot (StateView), so the opponent's hand never leaves the server.
## Run: godot --headless --path . -s scripts/net/match_server.gd -- [port]
## Plain ws:// on localhost; tools/serve_web.js proxies wss://<host>:8060/ws to it.
##
## client -> server (JSON):
##   {t:"create", deck:"fogo"|"agua"}        -> {t:"room", code, seat, token}
##   {t:"join", code}                        -> {t:"room", code, seat, token}
##   {t:"resume", code, token}               -> {t:"start", ...} again (reconnect)
##   {t:"act", a:<action>, ...args}          -> broadcast {t:"events"} or {t:"reject"} to the sender
## actions: mulligan{uids} play{uid,target} legendary{target} ability{target} attack{attacks}
##          blocks{blocks} end_turn pass discard{uids} search{uid}
## server -> client: room, start{seat,snap}, events{events,snap}, reject{a}, opponent{connected}, error{msg}

const DECKS := ["fogo", "agua"]
const ROOM_TTL := 1800.0 ## seconds an empty room is kept

var server := TCPServer.new()
var pending: Array = [] ## peers that have not identified yet
var rooms: Dictionary = {} ## code -> room

func _initialize() -> void:
	var port := 8061
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and String(args[0]).is_valid_int():
		port = int(args[0])
	var err := server.listen(port, "127.0.0.1")
	if err != OK:
		printerr("match_server: cannot listen on %d (%s)" % [port, error_string(err)])
		quit(1)
		return
	print("match_server listening on ws://127.0.0.1:%d" % port)

func _process(_delta: float) -> bool:
	while server.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(server.take_connection())
		pending.append({"ws": ws, "t": Time.get_ticks_msec()})
	for p in pending.duplicate():
		var ws: WebSocketPeer = p["ws"]
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			pending.erase(p)
			continue
		_drain_lobby(ws)
		if pending.has(p) and Time.get_ticks_msec() - p["t"] > 15000:
			ws.close()
			pending.erase(p)
	for code in rooms.keys():
		var r: Dictionary = rooms[code]
		for seat in 2:
			var ws: WebSocketPeer = r["peers"][seat]
			if ws == null:
				continue
			ws.poll()
			if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
				r["peers"][seat] = null
				r["idle"] = Time.get_ticks_msec()
				_send(r["peers"][1 - seat], {"t": "opponent", "connected": false})
				continue
			while r["peers"][seat] == ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
				var msg = JSON.parse_string(ws.get_packet().get_string_from_utf8())
				if typeof(msg) == TYPE_DICTIONARY:
					_handle_room(r, seat, msg)
		if r["peers"][0] == null and r["peers"][1] == null and Time.get_ticks_msec() - r["idle"] > ROOM_TTL * 1000.0:
			rooms.erase(code)
	return false

func _drain_lobby(ws: WebSocketPeer) -> void:
	while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
		var msg = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		_handle_lobby(ws, msg)
		if not pending.any(func(p): return p["ws"] == ws):
			return # seated: the room loop owns this peer now

# ---------------------------------------------------------------- lobby

func _code() -> String:
	var letters := "ABCDEFGHJKMNPQRSTUVWXYZ" # no I/L/O
	while true:
		var c := ""
		for i in 4:
			c += letters[randi() % letters.length()]
		if not rooms.has(c):
			return c
	return ""

func _handle_lobby(ws: WebSocketPeer, m: Dictionary) -> void:
	match m.get("t", ""):
		"create":
			var deck: String = m.get("deck", "fogo")
			if not DECKS.has(deck):
				_send(ws, {"t": "error", "msg": "Deck inválido."})
				return
			var code := _code()
			var token := _token()
			rooms[code] = {"g": null, "decks": [deck, DECKS[1 - DECKS.find(deck)]], "peers": [ws, null],
				"tokens": [token, ""], "idle": Time.get_ticks_msec()}
			_unpend(ws)
			_send(ws, {"t": "room", "code": code, "seat": 0, "token": token, "deck": deck})
		"join":
			var code := String(m.get("code", "")).to_upper()
			var r = rooms.get(code)
			if r == null:
				_send(ws, {"t": "error", "msg": "Sala não encontrada."})
				return
			if r["tokens"][1] != "":
				_send(ws, {"t": "error", "msg": "Sala cheia."})
				return
			var token := _token()
			r["tokens"][1] = token
			r["peers"][1] = ws
			_unpend(ws)
			_send(ws, {"t": "room", "code": code, "seat": 1, "token": token, "deck": r["decks"][1]})
			r["g"] = GameState.new(r["decks"][0], r["decks"][1])
			for s in 2:
				_send_start(r, s)
		"resume":
			var code := String(m.get("code", "")).to_upper()
			var r = rooms.get(code)
			var token := String(m.get("token", ""))
			var seat := -1
			if r != null and token != "":
				seat = r["tokens"].find(token)
			if seat < 0:
				_send(ws, {"t": "error", "msg": "Sala expirada."})
				return
			var old: WebSocketPeer = r["peers"][seat]
			if old != null:
				old.close()
			r["peers"][seat] = ws
			_unpend(ws)
			_send(ws, {"t": "room", "code": code, "seat": seat, "token": token, "deck": r["decks"][seat]})
			if r["g"] != null:
				_send_start(r, seat)
				_send(r["peers"][1 - seat], {"t": "opponent", "connected": true})

func _unpend(ws: WebSocketPeer) -> void:
	for p in pending.duplicate():
		if p["ws"] == ws:
			pending.erase(p)

func _token() -> String:
	return "%08x%08x" % [randi(), randi()]

# ---------------------------------------------------------------- match

func _send_start(r: Dictionary, seat: int) -> void:
	_send(r["peers"][seat], {"t": "start", "seat": seat, "decks": r["decks"], "snap": StateView.snapshot(r["g"], seat)})

func _handle_room(r: Dictionary, seat: int, m: Dictionary) -> void:
	r["idle"] = Time.get_ticks_msec()
	if m.get("t", "") != "act" or r["g"] == null:
		return
	var g: GameState = r["g"]
	var events := _apply(g, seat, m)
	if events.is_empty():
		_send(r["peers"][seat], {"t": "reject", "a": m.get("a", "")})
		return
	for s in 2:
		_send(r["peers"][s], {"t": "events", "events": StateView.filter_events(events, s), "snap": StateView.snapshot(g, s)})

## JSON objects arrive with string keys; the engine wants int uids.
func _intmap(d) -> Dictionary:
	var out := {}
	if typeof(d) == TYPE_DICTIONARY:
		for k in d:
			out[int(k)] = int(d[k])
	return out

func _ints(a) -> Array:
	var out: Array = []
	if typeof(a) == TYPE_ARRAY:
		for v in a:
			out.append(int(v))
	return out

func _apply(g: GameState, p: int, m: Dictionary) -> Array:
	if g.phase == "over" or g.decider() != p:
		return []
	match m.get("a", ""):
		"mulligan": return g.mulligan(p, _ints(m.get("uids")))
		"play": return g.play_card(p, int(m.get("uid", 0)), int(m.get("target", 0)))
		"legendary": return g.cast_legendary(p, int(m.get("target", 0)))
		"ability": return g.use_ability(p, int(m.get("target", 0)))
		"attack": return g.declare_attack(p, _intmap(m.get("attacks")))
		"blocks": return g.declare_blocks(p, _intmap(m.get("blocks")))
		"end_turn": return g.end_turn(p)
		"pass": return g.pass_priority(p)
		"discard": return g.discard(p, _ints(m.get("uids")))
		"search": return g.choose_search(p, int(m.get("uid", 0)))
	return []

func _send(ws, msg: Dictionary) -> void:
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))
