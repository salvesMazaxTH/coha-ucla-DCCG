class_name SupabaseDesktopAuth
extends Node
## Google login for the desktop executable (Windows/Linux/macOS), where there is no browser page to
## host the Supabase JavaScript client. The flow:
##   1. the game opens the system browser on Supabase's Google login page;
##   2. after login, Supabase sends the browser to http://127.0.0.1:54321/auth/callback?code=...,
##      a tiny web server this script runs only while waiting;
##   3. the game trades that code for a session (PKCE: only the game knows the secret "verifier"),
##      saves it encrypted on this PC and keeps it fresh.
## It produces the same state Dictionary as the web bridge, so SupabaseAuth treats both alike.
## Supabase needs http://127.0.0.1:54321/** in Authentication → URL Configuration → Redirect URLs.

signal state_updated(new_state: Dictionary)

const CALLBACK_PORT := 54321
const CALLBACK_PATH := "/auth/callback"
const SESSION_FILE := "user://supabase_session.dat"
## How long the little callback server waits for the browser before giving up (seconds).
const LOGIN_WAIT_LIMIT := 300.0
## Refresh the access token this many seconds before it expires.
const REFRESH_MARGIN := 60

var project_url := ""
var publishable_key := ""
var state: Dictionary = {"ready": true, "session_checked": false, "signed_in": false, "user": {}, "profile": {}, "decks": [], "error": "", "action": {}}

var _session: Dictionary = {} ## access_token, refresh_token, expires_at (unix seconds), user
var _callback_server: TCPServer
var _callback_connection: StreamPeerTCP
var _callback_request_text := ""
var _code_verifier := ""
var _seconds_waiting_for_browser := 0.0
var _refreshing := false

func setup(url: String, key: String) -> void:
	project_url = url
	publishable_key = key

## Called once at startup: restores the session saved by an earlier login, if any.
func restore_saved_session() -> void:
	var saved := _load_session_file()
	if not saved.is_empty():
		_session = saved
		var refreshed := await _refresh_session()
		if refreshed:
			await refresh_account_data()
	state.session_checked = true
	_publish()

func _process(delta: float) -> void:
	_keep_session_fresh()
	if _callback_server == null:
		return
	_seconds_waiting_for_browser += delta
	if _seconds_waiting_for_browser > LOGIN_WAIT_LIMIT:
		_stop_callback_server()
		state.error = "O login pelo navegador demorou demais. Tente de novo."
		_publish()
		return
	if _callback_connection == null and _callback_server.is_connection_available():
		_callback_connection = _callback_server.take_connection()
		_callback_request_text = ""
	if _callback_connection == null:
		return
	_callback_connection.poll()
	var byte_count := _callback_connection.get_available_bytes()
	if byte_count > 0:
		_callback_request_text += _callback_connection.get_utf8_string(byte_count)
	if _callback_request_text.contains("\r\n\r\n"):
		_handle_browser_request()
	elif _callback_connection.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_callback_connection = null

# ---------------------------------------------------------------- login / logout

func sign_in_with_google() -> void:
	_stop_callback_server()
	state.error = ""
	_callback_server = TCPServer.new()
	if _callback_server.listen(CALLBACK_PORT, "127.0.0.1") != OK:
		_callback_server = null
		state.error = "A porta %d está ocupada; feche outros jogos abertos e tente de novo." % CALLBACK_PORT
		_publish()
		return
	_seconds_waiting_for_browser = 0.0
	# PKCE: a random secret stays in the game; only its SHA-256 fingerprint goes to the browser
	_code_verifier = _base64_url(Crypto.new().generate_random_bytes(48))
	var code_challenge := _base64_url(_code_verifier.sha256_buffer())
	var redirect_url := "http://127.0.0.1:%d%s" % [CALLBACK_PORT, CALLBACK_PATH]
	var login_url := "%s/auth/v1/authorize?provider=google&redirect_to=%s&code_challenge=%s&code_challenge_method=s256" % [
		project_url, redirect_url.uri_encode(), code_challenge]
	OS.shell_open(login_url)

func sign_out() -> void:
	_stop_callback_server()
	if _session.has("access_token"):
		await _send(HTTPClient.METHOD_POST, "/auth/v1/logout")
	_session = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))
	state.signed_in = false
	state.user = {}
	state.profile = {}
	state.decks = []
	state.error = ""
	_publish()

## Reads one request from the browser. Only /auth/callback matters; anything else (like the
## favicon the browser asks for) gets a 404 and the server keeps waiting.
func _handle_browser_request() -> void:
	var request_target := _callback_request_text.get_slice("\r\n", 0).get_slice(" ", 1)
	var request_path := request_target.get_slice("?", 0)
	if request_path != CALLBACK_PATH:
		_answer_browser(404, "", "")
		return
	var query := _parse_query(request_target.get_slice("?", 1) if request_target.contains("?") else "")
	if not query.has("code"):
		var reason := String(query.get("error_description", query.get("error", "login cancelado")))
		_answer_browser(200, "Não foi possível entrar", "Motivo: %s. Volte ao jogo e tente de novo." % reason)
		_stop_callback_server()
		state.error = "Login Google falhou: %s" % reason
		_publish()
		return
	_answer_browser(200, "Login concluído!", "Pode fechar esta aba e voltar ao Duelo de Cartas.")
	_stop_callback_server()
	DisplayServer.window_move_to_foreground()
	_exchange_code_for_session(String(query["code"]))

func _exchange_code_for_session(auth_code: String) -> void:
	var response := await _send(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=pkce",
		{"auth_code": auth_code, "code_verifier": _code_verifier})
	_code_verifier = ""
	if not response.ok:
		state.error = "Login Google falhou: %s" % response.error
		_publish()
		return
	_store_session(response.data)
	await refresh_account_data()

func _answer_browser(status_code: int, heading: String, message: String) -> void:
	var page := ""
	if status_code == 200:
		page = "<!doctype html><meta charset=\"utf-8\"><title>Duelo de Cartas</title>" \
			+ "<body style=\"font-family:sans-serif;background:#0b0a10;color:#ece6d6;text-align:center;padding-top:20vh\">" \
			+ "<h1 style=\"color:#e8c25a\">%s</h1><p>%s</p></body>" % [heading.xml_escape(), message.xml_escape()]
	var body_bytes := page.to_utf8_buffer()
	var status_text := "OK" if status_code == 200 else "Not Found"
	var header := "HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [
		status_code, status_text, body_bytes.size()]
	_callback_connection.put_data(header.to_utf8_buffer())
	_callback_connection.put_data(body_bytes)
	_callback_connection.disconnect_from_host()
	_callback_connection = null

func _stop_callback_server() -> void:
	if _callback_connection:
		_callback_connection.disconnect_from_host()
		_callback_connection = null
	if _callback_server:
		_callback_server.stop()
		_callback_server = null

# ---------------------------------------------------------------- session

func _keep_session_fresh() -> void:
	if _refreshing or not state.signed_in or not _session.has("expires_at"):
		return
	if Time.get_unix_time_from_system() >= float(_session.expires_at) - REFRESH_MARGIN:
		_refresh_session()

## Trades the long-lived refresh token for a new access token. Returns true when signed in.
func _refresh_session() -> bool:
	_refreshing = true
	var response := await _send(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token",
		{"refresh_token": String(_session.get("refresh_token", ""))})
	_refreshing = false
	if response.ok:
		_store_session(response.data)
		return true
	if response.status == 0:
		# no internet: keep the saved file so the next start can try again
		state.error = "Sem conexão com o servidor de contas; jogando como convidado."
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))
	_session = {}
	state.signed_in = false
	state.user = {}
	_publish()
	return false

## Keeps a token response (from login or refresh) in memory and on disk, and marks us signed in.
func _store_session(token_response: Dictionary) -> void:
	var user_data: Dictionary = token_response.get("user", {})
	var expires_at := float(token_response.get("expires_at", 0))
	if expires_at <= 0:
		expires_at = Time.get_unix_time_from_system() + float(token_response.get("expires_in", 3600))
	_session = {
		"access_token": String(token_response.get("access_token", "")),
		"refresh_token": String(token_response.get("refresh_token", "")),
		"expires_at": expires_at,
		"user": user_data,
	}
	state.signed_in = true
	state.user = {
		"id": String(user_data.get("id", "")),
		"email": String(user_data.get("email", "")),
		"metadata": user_data.get("user_metadata", {}),
	}
	state.error = ""
	_save_session_file()
	_publish()

## The file is encrypted with this PC's id, so copying it to another computer does not log in there.
func _session_file_password() -> String:
	var machine_id := OS.get_unique_id()
	return machine_id if not machine_id.is_empty() else "csa-duelo-de-cartas"

func _save_session_file() -> void:
	var file := FileAccess.open_encrypted_with_pass(SESSION_FILE, FileAccess.WRITE, _session_file_password())
	if file:
		file.store_string(JSON.stringify(_session))

func _load_session_file() -> Dictionary:
	if not FileAccess.file_exists(SESSION_FILE):
		return {}
	var file := FileAccess.open_encrypted_with_pass(SESSION_FILE, FileAccess.READ, _session_file_password())
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY and parsed.has("refresh_token") else {}

# ---------------------------------------------------------------- profile and decks (Supabase REST)

func refresh_account_data() -> void:
	if not state.signed_in:
		return
	var profile_response := await _send(HTTPClient.METHOD_GET, "/rest/v1/profiles?select=id,username,display_name",
		null, ["Accept: application/vnd.pgrst.object+json"])
	var decks_response := await _send(HTTPClient.METHOD_GET,
		"/rest/v1/decks?select=id,name,content,created_at,updated_at&order=updated_at.desc")
	if profile_response.ok:
		state.profile = profile_response.data
	else:
		state.error = profile_response.error
	if decks_response.ok:
		state.decks = decks_response.data
	else:
		state.error = decks_response.error
	_publish()

func save_deck(deck_id: String, deck_name: String, content: Dictionary) -> void:
	if not state.signed_in:
		_finish_action("save_deck", {}, "Entre com Google para salvar decks.")
		return
	var row := {"name": deck_name, "content": content}
	var single_row_headers := ["Accept: application/vnd.pgrst.object+json", "Prefer: return=representation"]
	var response: Dictionary
	if deck_id.is_empty():
		row["user_id"] = state.user.id
		response = await _send(HTTPClient.METHOD_POST, "/rest/v1/decks", row, single_row_headers)
	else:
		response = await _send(HTTPClient.METHOD_PATCH, "/rest/v1/decks?id=eq.%s" % deck_id.uri_encode(), row, single_row_headers)
	_finish_action("save_deck", response.data if response.ok else {}, response.error)
	if response.ok:
		await refresh_account_data()

func delete_deck(deck_id: String) -> void:
	if not state.signed_in:
		_finish_action("delete_deck", {}, "Entre com Google para gerenciar decks.")
		return
	var response := await _send(HTTPClient.METHOD_DELETE, "/rest/v1/decks?id=eq.%s" % deck_id.uri_encode())
	_finish_action("delete_deck", {"id": deck_id}, response.error)
	if response.ok:
		await refresh_account_data()

func update_profile(username: String, display_name: String) -> void:
	if not state.signed_in:
		_finish_action("update_profile", {}, "Entre com Google para editar o perfil.")
		return
	var response := await _send(HTTPClient.METHOD_PATCH, "/rest/v1/profiles?id=eq.%s" % String(state.user.id).uri_encode(),
		{"username": username, "display_name": display_name},
		["Accept: application/vnd.pgrst.object+json", "Prefer: return=representation"])
	_finish_action("update_profile", response.data if response.ok else {}, response.error)
	if response.ok:
		await refresh_account_data()

func _finish_action(kind: String, data, error_message: String) -> void:
	var previous_id := int(state.get("action", {}).get("id", 0))
	state.action = {"id": previous_id + 1, "kind": kind, "data": data if data != null else {}, "error": error_message}
	if not error_message.is_empty():
		state.error = error_message
	_publish()

# ---------------------------------------------------------------- helpers

## One HTTP call to Supabase. Returns {ok, status, data, error}; status 0 means no connection.
func _send(method: HTTPClient.Method, path: String, body = null, extra_headers: Array = []) -> Dictionary:
	var request := HTTPRequest.new()
	add_child(request)
	var headers := PackedStringArray(["apikey: " + publishable_key, "Content-Type: application/json"])
	if _session.has("access_token") and not path.begins_with("/auth/v1/token"):
		headers.append("Authorization: Bearer " + String(_session.access_token))
	for header in extra_headers:
		headers.append(header)
	var body_text := "" if body == null else JSON.stringify(body)
	if request.request(project_url + path, headers, method, body_text) != OK:
		request.queue_free()
		return {"ok": false, "status": 0, "data": null, "error": "Não foi possível falar com o servidor de contas."}
	var result: Array = await request.request_completed
	request.queue_free()
	var status_code := int(result[1])
	var response_text := (result[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(response_text) if not response_text.is_empty() else null
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "data": null, "error": "Sem conexão com o servidor de contas."}
	if status_code >= 200 and status_code < 300:
		return {"ok": true, "status": status_code, "data": data, "error": ""}
	return {"ok": false, "status": status_code, "data": data, "error": _error_text(data, status_code)}

func _error_text(data, status_code: int) -> String:
	if typeof(data) == TYPE_DICTIONARY:
		for field in ["error_description", "msg", "message", "error"]:
			if data.has(field):
				return String(data[field])
	return "Erro %d no servidor de contas." % status_code

func _parse_query(query_text: String) -> Dictionary:
	var values := {}
	for pair in query_text.split("&", false):
		var name := pair.get_slice("=", 0).uri_decode()
		var value := pair.substr(pair.find("=") + 1).uri_decode() if pair.contains("=") else ""
		values[name] = value.replace("+", " ")
	return values

## Base64 with URL-safe letters and no padding, as PKCE requires.
func _base64_url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

func _publish() -> void:
	state_updated.emit(state.duplicate(true))
