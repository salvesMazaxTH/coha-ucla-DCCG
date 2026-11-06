extends Node
## Server-only Supabase access. The service key must never be shipped in a client export.

signal recorded(match_id: String)
signal recording_failed(match_id: String)

const SupabaseAuthScript := preload("res://scripts/net/supabase_auth.gd")
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
	_load_credentials()
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
		print("match stats: service key absent; accounts are validated, but match results stay queued until it is set")

## Which Supabase project and keys the server uses. Accounts live in the project the client signs in
## to, so that project (and its public key, which is not a secret) is the default. A .env file only
## counts when it names that same project; a .env pointing at another project is ignored, so a stale
## file can never send tokens (or the service key) to the wrong place.
func _load_credentials() -> void:
	project_url = SupabaseAuthScript.PROJECT_URL
	public_key = SupabaseAuthScript.PUBLISHABLE_KEY
	var from_environment := OS.get_environment("SUPABASE_URL").trim_suffix("/")
	var dotenv := _read_dotenv()
	var dotenv_url := String(dotenv.get("SUPABASE_URL", "")).trim_suffix("/")
	if not from_environment.is_empty():
		project_url = from_environment
	elif not dotenv_url.is_empty() and dotenv_url != project_url:
		printerr("match stats: .env points to another Supabase project than the game client uses; ignoring .env")
		dotenv = {}
	# Only the explicit name overrides the client's key. The old SUPABASE_ANON_KEY name is ignored on
	# purpose: stale .env files held a key from another project, and Supabase then refused every account.
	var configured_public := _setting("SUPABASE_PUBLISHABLE_KEY", dotenv)
	if not configured_public.is_empty():
		public_key = configured_public
	service_key = _setting("SUPABASE_SERVICE_ROLE_KEY", dotenv)

## A real environment variable wins; otherwise the value comes from the project's .env file, so the
## server works no matter which .bat (or none) started it.
func _setting(name: String, dotenv: Dictionary) -> String:
	var from_environment := OS.get_environment(name)
	if not from_environment.is_empty():
		return from_environment
	return String(dotenv.get(name, ""))

## Reads KEY=value lines from the .env next to project.godot (server machine only, git-ignored).
func _read_dotenv() -> Dictionary:
	var values: Dictionary = {}
	var path := ProjectSettings.globalize_path("res://.env")
	if not FileAccess.file_exists(path):
		return values
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#") or not line.contains("="):
			continue
		var separator := line.find("=")
		values[line.left(separator).strip_edges()] = line.substr(separator + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return values

## Enough to check who a player is (token and saved deck); needs no secret.
func can_identify() -> bool:
	return not project_url.is_empty() and not public_key.is_empty()

## Enough to also write match results, which needs the server-only service key.
func configured() -> bool:
	return can_identify() and not service_key.is_empty()

## Empty token means a guest. An account's own deck is checked against its saved contents.
func identify(token: String, deck_key: String, payload: Variant) -> Dictionary:
	if token.is_empty():
		return {"user_id": "", "deck_key": "", "error": ""}
	if not can_identify():
		return {"error": "Servidor sem conexão com o banco de contas."}
	var user := await _request(HTTPClient.METHOD_GET, "/auth/v1/user", token, public_key)
	if not user.ok or not user.data is Dictionary or String(user.data.get("id", "")).is_empty():
		# Status 0 = the request never reached Supabase; 401 = Supabase refused the token (expired or from another project).
		printerr("match stats: could not validate account token (HTTP %d)" % user.status)
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
