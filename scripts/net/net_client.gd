class_name NetClient
extends Node
## WebSocket link to the match server: create/join/resume a room and relay messages.
## Web: wss://<page host>/ws (proxied by tools/serve_web.js). Desktop: ws://127.0.0.1:8061.

signal message(m: Dictionary)
signal link_changed(up: bool)

const SESSION_FILE := "user://net_session.cfg"
const DESKTOP_URL := "ws://127.0.0.1:8061"

var ws: WebSocketPeer
var up := false
var code := ""
var token := ""
var seat := -1
var want_resume := false ## re-send "resume" whenever the link comes back
var _retry_at := 0.0
var _outbox: Array = []

static func url() -> String:
	if OS.has_feature("web"):
		var host = JavaScriptBridge.eval("window.location.host")
		var secure = JavaScriptBridge.eval("window.location.protocol === 'https:'")
		return ("wss://" if secure else "ws://") + String(host) + "/ws"
	return DESKTOP_URL

func connect_server() -> void:
	ws = WebSocketPeer.new()
	ws.connect_to_url(url())

func disconnect_server() -> void:
	want_resume = false
	if ws:
		ws.close()
	ws = null
	_set_up(false)

func send(m: Dictionary) -> void:
	if ws != null and up:
		ws.send_text(JSON.stringify(m))
	else:
		_outbox.append(m)
		if ws == null:
			connect_server()

func create(deck: String) -> void:
	send({"t": "create", "deck": deck})

func join(room_code: String) -> void:
	send({"t": "join", "code": room_code})

func resume() -> void:
	want_resume = true
	send({"t": "resume", "code": code, "token": token})

func remember() -> void:
	var cf := ConfigFile.new()
	cf.set_value("s", "code", code)
	cf.set_value("s", "token", token)
	cf.save(SESSION_FILE)

func forget() -> void:
	code = ""
	token = ""
	want_resume = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))

## Loads a stored session; true if there is one.
func load_session() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SESSION_FILE) != OK:
		return false
	code = cf.get_value("s", "code", "")
	token = cf.get_value("s", "token", "")
	return code != "" and token != ""

func _set_up(v: bool) -> void:
	if up != v:
		up = v
		link_changed.emit(v)

func _process(_d: float) -> void:
	if ws == null:
		return
	ws.poll()
	match ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not up:
				_set_up(true)
				if want_resume and code != "":
					ws.send_text(JSON.stringify({"t": "resume", "code": code, "token": token}))
				for m in _outbox:
					ws.send_text(JSON.stringify(m))
				_outbox.clear()
			while ws.get_available_packet_count() > 0:
				var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
				if typeof(m) == TYPE_DICTIONARY:
					message.emit(RemoteState.normalize(m))
		WebSocketPeer.STATE_CLOSED:
			_set_up(false)
			if want_resume:
				if Time.get_ticks_msec() >= _retry_at:
					_retry_at = Time.get_ticks_msec() + 2000
					connect_server()
			else:
				ws = null
