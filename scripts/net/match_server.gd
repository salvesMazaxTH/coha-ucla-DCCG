extends SceneTree
## Authoritative match server. GameState lives only here; clients send actions and
## receive events plus a per-seat snapshot (StateView), so the opponent's hand never leaves the server.
## Run: godot --headless --path . -s scripts/net/match_server.gd -- [port]
## Plain ws:// on localhost; tools/serve_web.js proxies wss://<host>:8060/ws to it.
##
## client -> server (JSON):
##   {t:"create", deck:<deck>}               -> {t:"room", code, seat, token}
##   {t:"join", code, deck:<deck>}           -> {t:"room", code, seat, token}   (mirror matches allowed)
##     <deck> is a prebuilt id (DeckDB.ids()) or the player's own deck {name, description, leader, cards},
##     which is validated with DeckDB.check_incoming and kept per room as "room:<code>:<seat>"
##   {t:"resume", code, token}               -> {t:"start", ...} again (reconnect)
##   {t:"act", a:<action>, ...args}          -> broadcast {t:"events"} or {t:"reject"} to the sender
## actions: mulligan{uids} play{uid,target} incarnation{target} ability{target} attack{attacker,target}
##          end_combat enter_tapped{tapped} effect_choice{index,target} end_turn pass discard{uids} search{uid}
## server -> client: room, start{seat,decks,deck_data,snap}, events{events,snap}, reject{a},
## opponent{connected}, error{msg}. deck_data holds the contents of the "room:" decks.

const ROOM_TTL := 1800.0 ## seconds an empty room is kept
const MatchStatsServer = preload("res://scripts/net/match_stats_server.gd")

var server := TCPServer.new()
var pending: Array = [] ## peers that have not identified yet
var rooms: Dictionary = {} ## code -> room
var stats: Node

func _initialize() -> void:
	stats = MatchStatsServer.new()
	root.add_child.call_deferred(stats)
	stats.recorded.connect(_on_stats_recorded)
	stats.recording_failed.connect(_on_stats_recording_failed)
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
		if r.get("stats_retry", false) and Time.get_ticks_msec() >= int(r.get("stats_retry_at", 0)):
			_record_if_over(r)
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
		if (
			not bool(r.get("stats_retry", false)) and r["peers"][0] == null and r["peers"][1] == null
			and Time.get_ticks_msec() - r["idle"] > ROOM_TTL * 1000.0
		):
			rooms.erase(code)
			DeckDB.clear_custom("%s%s:" % [DeckDB.ROOM_PREFIX, code])
	return false

func _drain_lobby(ws: WebSocketPeer) -> void:
	var peer := _pending_peer(ws)
	if peer.is_empty() or bool(peer.get("identifying", false)):
		return
	while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
		var msg = JSON.parse_string(ws.get_packet().get_string_from_utf8())
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		peer["identifying"] = true
		_handle_lobby(ws, msg)
		if not pending.any(func(p): return p["ws"] == ws):
			return # seated: the room loop owns this peer now
		if bool(peer.get("identifying", false)):
			return

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
	var peer := _pending_peer(ws)
	if peer.is_empty():
		return
	var identity := {"user_id": "", "deck_key": "", "error": ""}
	if m.get("t", "") in ["create", "join"] and bool(m.get("account", false)):
		var access_token := String(m.get("access_token", ""))
		if access_token.is_empty():
			_send(ws, {"t": "error", "msg": "Sessão da conta indisponível. Entre novamente."})
			peer["identifying"] = false
			return
		identity = await stats.identify(access_token, String(m.get("deck_key", "")), m.get("deck"))
		if _pending_peer(ws).is_empty() or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			return
		if not String(identity.get("error", "")).is_empty():
			_send(ws, {"t": "error", "msg": identity.error})
			peer["identifying"] = false
			return
	match m.get("t", ""):
		"create":
			var code := _code()
			var accepted := _accept_deck(code, 0, m.get("deck"))
			if accepted["error"] != "":
				_send(ws, {"t": "error", "msg": accepted["error"]})
				peer["identifying"] = false
				return
			var deck: String = accepted["id"]
			var token := _token()
			rooms[code] = {"g": null, "decks": [deck, ""], "peers": [ws, null],
				"match_id": Crypto.new().generate_random_bytes(16).hex_encode(), "identities": [identity, {}],
				"tokens": [token, ""], "idle": Time.get_ticks_msec()}
			_unpend(ws)
			_send(ws, {"t": "room", "code": code, "seat": 0, "token": token, "deck": deck})
		"join":
			var code := String(m.get("code", "")).to_upper()
			var r = rooms.get(code)
			if r == null:
				_send(ws, {"t": "error", "msg": "Sala não encontrada."})
				peer["identifying"] = false
				return
			if r["tokens"][1] != "":
				_send(ws, {"t": "error", "msg": "Sala cheia."})
				peer["identifying"] = false
				return
			var accepted := _accept_deck(code, 1, m.get("deck"))
			if accepted["error"] != "":
				_send(ws, {"t": "error", "msg": accepted["error"]})
				peer["identifying"] = false
				return
			var join_deck: String = accepted["id"]
			var token := _token()
			r["decks"][1] = join_deck
			r["identities"][1] = identity
			r["tokens"][1] = token
			r["peers"][1] = ws
			_unpend(ws)
			_send(ws, {"t": "room", "code": code, "seat": 1, "token": token, "deck": r["decks"][1]})
			r["g"] = GameState.new(r["decks"][0], r["decks"][1], 0, randi() % 2) # coin flip, not always the room creator
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
				peer["identifying"] = false
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
	peer["identifying"] = false

func _pending_peer(ws: WebSocketPeer) -> Dictionary:
	for peer in pending:
		if peer["ws"] == ws:
			return peer
	return {}

## A client names its deck either by prebuilt id or by sending the full contents of one of the player's
## own decks. Contents are never trusted: DeckDB.check_incoming applies every deck rule, and only then is
## the deck registered under a room-specific id ("room:<code>:<seat>"). Returns {id, error}.
func _accept_deck(code: String, seat: int, raw: Variant) -> Dictionary:
	if raw is String:
		if DeckDB.ids().has(raw):
			return {"id": raw, "error": ""}
		return {"id": "", "error": "Deck inválido."}
	var checked := DeckDB.check_incoming(raw)
	var errors: Array = checked["errors"]
	if not errors.is_empty():
		return {"id": "", "error": "Deck inválido: %s." % errors[0]}
	var room_deck_id := "%s%s:%d" % [DeckDB.ROOM_PREFIX, code, seat]
	var deck: Dictionary = checked["deck"]
	DeckDB.register_custom(
		room_deck_id, deck["name"], deck["description"], deck["leader"], deck["cards"],
		String(deck.get("incarnation_id", "")),
	)
	return {"id": room_deck_id, "error": ""}

## The contents of the room's decks that are not prebuilt, so each client can register them before the match.
func _custom_deck_contents(r: Dictionary) -> Dictionary:
	var contents: Dictionary = {}
	for deck_id in r["decks"]:
		if String(deck_id).begins_with(DeckDB.ROOM_PREFIX):
			contents[deck_id] = DeckDB.get_deck(deck_id)
	return contents

func _unpend(ws: WebSocketPeer) -> void:
	for p in pending.duplicate():
		if p["ws"] == ws:
			pending.erase(p)

func _token() -> String:
	return "%08x%08x" % [randi(), randi()]

# ---------------------------------------------------------------- match

func _send_start(r: Dictionary, seat: int) -> void:
	_send(r["peers"][seat], {
		"t": "start", "seat": seat, "decks": r["decks"],
		"deck_data": _custom_deck_contents(r), "snap": StateView.snapshot(r["g"], seat),
	})

func _handle_room(r: Dictionary, seat: int, m: Dictionary) -> void:
	r["idle"] = Time.get_ticks_msec()
	if m.get("t", "") != "act" or r["g"] == null:
		return
	var g: GameState = r["g"]
	if m.get("a", "") == "auto": # a setting, not a move: allowed off-turn, never rejected
		var ev := g.set_auto_pass(seat, bool(m.get("on", true)))
		_record_if_over(r)
		for s in 2:
			_send(r["peers"][s], {"t": "events", "events": StateView.filter_events(ev, s), "snap": StateView.snapshot(g, s)})
		return
	# PASSAR TUDO is a setting and can be switched during the opponent's turn.
	if m.get("a", "") == "pass_all":
		var pass_all_events := g.pass_rest_of_turn(seat) if bool(m.get("on", true)) else g.cancel_pass_rest_of_turn(seat)
		_record_if_over(r)
		for s in 2:
			_send(r["peers"][s], {"t": "events", "events": StateView.filter_events(pass_all_events, s), "snap": StateView.snapshot(g, s)})
		return
	var events := g.concede(seat) if m.get("a", "") == "concede" else _apply(g, seat, m) # conceding is allowed off-turn
	if events.is_empty():
		_send(r["peers"][seat], {"t": "reject", "a": m.get("a", "")})
		return
	_record_if_over(r)
	for s in 2:
		_send(r["peers"][s], {"t": "events", "events": StateView.filter_events(events, s), "snap": StateView.snapshot(g, s)})

func _record_if_over(r: Dictionary) -> void:
	var g: GameState = r["g"]
	if g == null or g.phase != "over" or bool(r.get("stats_queued", false)):
		return
	if DeckDB.development_mode_enabled():
		r["stats_queued"] = true
		return
	if stats.enqueue(r["match_id"], r["identities"], g.winner):
		r["stats_queued"] = true
		r["stats_retry"] = false
	else:
		if not bool(r.get("stats_retry", false)):
			for seat in 2:
				_send(r["peers"][seat], {"t": "stats_error", "msg": "Não foi possível guardar o resultado; o servidor tentará novamente."})
		r["stats_retry"] = true
		r["stats_retry_at"] = Time.get_ticks_msec() + 10000

func _on_stats_recorded(match_id: String) -> void:
	for r in rooms.values():
		if r.get("match_id", "") == match_id:
			for seat in 2:
				_send(r["peers"][seat], {"t": "stats_saved"})

func _on_stats_recording_failed(match_id: String) -> void:
	for r in rooms.values():
		if r.get("match_id", "") == match_id:
			for seat in 2:
				_send(r["peers"][seat], {"t": "stats_error", "msg": "Estatísticas pendentes: o servidor tentará novamente."})

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
		"play":
			return g.play_card(
				p, int(m.get("uid", 0)), int(m.get("target", 0)), int(m.get("target2", 0)),
				int(m.get("slot", -1)), int(m.get("banish", 0)),
			)
		"store_in_reservoir": return g.store_in_reservoir(p, int(m.get("uid", 0)))
		"incarnation": return g.cast_incarnation(p, int(m.get("target", 0)), int(m.get("slot", -1)), int(m.get("banish", 0)))
		"ability": return g.use_ability(p, int(m.get("target", 0)))
		"activate": return g.activate(p, int(m.get("uid", 0)), int(m.get("target", 0)), int(m.get("payer", 0)))
		"effect_choice": return g.choose_effect_option(p, int(m.get("index", -1)), int(m.get("target", 0)))
		"activate_discard": return g.begin_activation_discard(p, int(m.get("uid", 0)))
		"transform": return g.transform(p, int(m.get("uid", 0)))
		"go_to_combat": return g.go_to_combat(p)
		"skip_combat": return g.skip_combat(p)
		"attack": return g.attack_unit(p, int(m.get("attacker", 0)), int(m.get("target", 0)))
		"end_combat": return g.end_combat(p)
		"enter_tapped": return g.choose_enter_tapped(p, bool(m.get("tapped", false)))
		"end_turn": return g.end_turn(p)
		"pass": return g.pass_priority(p)
		"discard": return g.discard(p, _ints(m.get("uids")))
		"search": return g.choose_search(p, int(m.get("uid", 0)))
		"enter": return g.choose_enter_target(p, int(m.get("target", 0)))
	return []

func _send(ws, msg: Dictionary) -> void:
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))
