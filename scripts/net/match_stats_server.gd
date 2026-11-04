extends Node
## Server-only Supabase access. The service key must never be shipped in a client export.

signal recorded(match_id: String)
signal recording_failed(match_id: String)

const DEFAULT_QUEUE_PATH := "user://match_stats_pending.json"
const RETRY_SECONDS := 10.0

var project_url := ""
var public_key := ""
var service_key := ""
var queue_path := DEFAULT_QUEUE_PATH
var pending: Array = []
var _sending := false
var _retry_at := 0.0
var _queue_valid := true

func _ready() -> void:
	project_url = OS.get_environment("SUPABASE_URL").trim_suffix("/")
	public_key = OS.get_environment("SUPABASE_PUBLISHABLE_KEY")
	service_key = OS.get_environment("SUPABASE_SERVICE_ROLE_KEY")
	var configured_queue := OS.get_environment("MATCH_STATS_QUEUE_PATH")
	if not configured_queue.is_empty():
		queue_path = configured_queue
	if FileAccess.file_exists(queue_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(queue_path))
		if not parsed is Array:
			push_error("match stats: invalid pending queue; refusing to overwrite it")
			_queue_valid = false
			set_process(false)
			return
		pending = parsed
	if not configured():
		print("match stats: server credentials absent; signed-in online games are unavailable")

func configured() -> bool:
	return not project_url.is_empty() and not public_key.is_empty() and not service_key.is_empty()

## Empty token means a guest. An account's own deck is checked against its saved contents.
func identify(token: String, deck_key: String, payload: Variant) -> Dictionary:
	if token.is_empty():
		return {"user_id": "", "deck_key": "", "error": ""}
	if not configured():
		return {"error": "Estatísticas online indisponíveis: servidor de contas não configurado."}
	var user := await _request(HTTPClient.METHOD_GET, "/auth/v1/user", token, public_key)
	if not user.ok or not user.data is Dictionary or String(user.data.get("id", "")).is_empty():
		return {"error": "Não foi possível validar sua conta. Entre novamente e tente outra vez."}
	if payload is String:
		if deck_key != payload:
			return {"error": "Identificação do deck inválida."}
	else:
		if not deck_key.begins_with(DeckDB.PLAYER_PREFIX):
			return {"error": "Deck da conta não identificado."}
		var deck_id := deck_key.trim_prefix(DeckDB.PLAYER_PREFIX)
		var response := await _request(HTTPClient.METHOD_GET,
			"/rest/v1/decks?select=name,content&id=eq.%s" % deck_id.uri_encode(), token, public_key)
		if not response.ok or not response.data is Array or response.data.size() != 1:
			return {"error": "Não foi possível validar o deck salvo na sua conta."}
		var row: Dictionary = response.data[0]
		var saved: Dictionary = row.get("content", {}).duplicate(true)
		saved["name"] = row.get("name", "")
		var checked_saved := DeckDB.check_incoming(saved)
		var checked_payload := DeckDB.check_incoming(payload)
		if not checked_saved.errors.is_empty() or not checked_payload.errors.is_empty() or checked_saved.deck != checked_payload.deck:
			return {"error": "O deck mudou na conta. Atualize a lista e tente novamente."}
	return {"user_id": String(user.data.id), "deck_key": deck_key, "error": ""}

func enqueue(match_id: String, identities: Array, winner: int) -> bool:
	if not _queue_valid:
		return false
	var results: Array = []
	for seat in 2:
		var identity: Dictionary = identities[seat]
		if String(identity.get("user_id", "")).is_empty():
			continue
		results.append({"match_id": match_id, "seat": seat, "user_id": identity.user_id,
			"deck_key": identity.deck_key, "result": "draw" if winner == 2 else ("win" if winner == seat else "loss")})
	if results.is_empty():
		return true
	pending.append({"match_id": match_id, "results": results})
	if not _save_queue():
		pending.pop_back()
		return false
	_retry_at = 0.0
	return true

func _process(_delta: float) -> void:
	if not _sending and not pending.is_empty() and configured() and Time.get_ticks_msec() >= _retry_at:
		_flush()

func _flush() -> void:
	_sending = true
	var item: Dictionary = pending[0]
	var response := await _request(HTTPClient.METHOD_POST, "/rest/v1/rpc/record_deck_match_results",
		service_key, service_key, {"p_results": item.results})
	if response.ok:
		pending.pop_front()
		if _save_queue():
			recorded.emit(String(item.match_id))
		else:
			pending.push_front(item)
			push_error("match stats: could not persist queue after recording; will retry")
	else:
		printerr("match stats: could not record match %s (HTTP %d); retrying" % [item.match_id, response.status])
		recording_failed.emit(String(item.match_id))
	_retry_at = Time.get_ticks_msec() + int(RETRY_SECONDS * 1000)
	_sending = false

func _save_queue() -> bool:
	var file := FileAccess.open(queue_path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("match stats: cannot write pending queue: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(pending))
	file.flush()
	var err := file.get_error()
	file.close()
	if err != OK:
		push_error("match stats: cannot flush pending queue: %s" % error_string(err))
		return false
	err = DirAccess.rename_absolute(ProjectSettings.globalize_path(queue_path + ".tmp"), ProjectSettings.globalize_path(queue_path))
	if err != OK:
		push_error("match stats: cannot replace pending queue: %s" % error_string(err))
		return false
	return true

func _request(method: HTTPClient.Method, path: String, bearer: String, apikey: String, body: Variant = null) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 8.0
	add_child(request)
	var headers := PackedStringArray(["apikey: " + apikey, "Authorization: Bearer " + bearer, "Content-Type: application/json"])
	var err := request.request(project_url + path, headers, method, "" if body == null else JSON.stringify(body))
	if err != OK:
		request.queue_free()
		return {"ok": false, "status": 0, "data": null}
	var result: Array = await request.request_completed
	request.queue_free()
	var status := int(result[1])
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	return {"ok": result[0] == HTTPRequest.RESULT_SUCCESS and status >= 200 and status < 300,
		"status": status, "data": JSON.parse_string(text) if not text.is_empty() else null}
