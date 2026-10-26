extends Node
## Google login and user-owned Supabase data.
## Web export: the Supabase JavaScript client does the work (supabase_web_bridge.js).
## Desktop executable: SupabaseDesktopAuth opens the system browser and receives the login back.

signal state_changed(state: Dictionary)
signal action_completed(action: Dictionary)

const PROJECT_URL := "https://iaehiefkmwkmjjarscpm.supabase.co"
const PUBLISHABLE_KEY := "sb_publishable_D-9i3aIC9HnP_WOpYqtdHw_0Y3oqs3F"
const BRIDGE_PATH := "res://scripts/net/supabase_web_bridge.js"
const POLL_INTERVAL := 0.4
## If Supabase takes longer than this to say whether a saved session exists (slow or blocked
## network), the entry screen stops waiting and shows its buttons anyway.
const SESSION_CHECK_TIMEOUT := 6.0

var state: Dictionary = {"ready": false, "session_checked": false, "signed_in": false, "user": {}, "profile": {}, "decks": [], "error": ""}
var _poll_elapsed := 0.0
var _seconds_since_start := 0.0
var _session_check_gave_up := false
var _last_state_json := ""
var _last_action_id := 0
var _bridge_started := false
var _desktop_auth: SupabaseDesktopAuth

func _ready() -> void:
	if not OS.has_feature("web"):
		_start_desktop_auth()
		return
	var bridge_source := FileAccess.get_file_as_string(BRIDGE_PATH)
	if bridge_source.is_empty():
		state.error = "Ponte de autenticação não encontrada no export web."
		state.session_checked = true
		return
	JavaScriptBridge.eval(bridge_source, true)
	_bridge_started = true

## Desktop: the helper node owns the session and tells us whenever its state changes.
func _start_desktop_auth() -> void:
	_desktop_auth = SupabaseDesktopAuth.new()
	_desktop_auth.name = "DesktopAuth"
	_desktop_auth.setup(PROJECT_URL, PUBLISHABLE_KEY)
	_desktop_auth.state_updated.connect(_apply_new_state)
	add_child(_desktop_auth)
	state = _desktop_auth.state.duplicate(true)
	_desktop_auth.restore_saved_session()

func _process(delta: float) -> void:
	if not _bridge_started:
		return
	_seconds_since_start += delta
	if not is_session_checked() and _seconds_since_start >= SESSION_CHECK_TIMEOUT:
		_session_check_gave_up = true
		state.session_checked = true
		state_changed.emit(state.duplicate(true))
	_poll_elapsed += delta
	if _poll_elapsed < POLL_INTERVAL:
		return
	_poll_elapsed = 0.0
	if not bool(JavaScriptBridge.eval("!!(window.CSAAuthBridge && window.CSAAuthBridge.sdkReady && !window.CSAAuthBridge.client)")):
		if not bool(JavaScriptBridge.eval("!!(window.CSAAuthBridge && window.CSAAuthBridge.client)")):
			var raw_error := str(JavaScriptBridge.eval("window.CSAAuthBridge ? window.CSAAuthBridge.state.error : ''"))
			if not raw_error.is_empty() and raw_error != state.get("error", ""):
				# the Supabase library failed to load: there is no session to wait for
				state.error = raw_error
				state.session_checked = true
				state_changed.emit(state.duplicate(true))
			return
	else:
		var url_json := JSON.stringify(PROJECT_URL)
		var key_json := JSON.stringify(PUBLISHABLE_KEY)
		JavaScriptBridge.eval("window.CSAAuthBridge.configure(%s, %s)" % [url_json, key_json])
	var raw := str(JavaScriptBridge.eval("window.CSAAuthBridge ? window.CSAAuthBridge.getStateJson() : ''"))
	if raw.is_empty() or raw == _last_state_json:
		return
	_last_state_json = raw
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	if _session_check_gave_up:
		parsed.session_checked = true
	_apply_new_state(parsed)

## Shared by web and desktop: store the new state, tell listeners, and report finished actions.
func _apply_new_state(new_state: Dictionary) -> void:
	state = new_state
	state_changed.emit(state.duplicate(true))
	var action: Dictionary = state.get("action", {})
	var action_id := int(action.get("id", 0))
	if action_id > _last_action_id:
		_last_action_id = action_id
		action_completed.emit(action.duplicate(true))

func is_signed_in() -> bool:
	return bool(state.get("signed_in", false))

## False only during the first moments, while Supabase looks for a saved session.
func is_session_checked() -> bool:
	return bool(state.get("session_checked", false))

func sign_in_with_google() -> void:
	if _desktop_auth:
		_desktop_auth.sign_in_with_google()
	else:
		_call_bridge("signInGoogle", [])

func sign_out() -> void:
	if _desktop_auth:
		_desktop_auth.sign_out()
	else:
		_call_bridge("signOut", [])

func refresh_account_data() -> void:
	if _desktop_auth:
		_desktop_auth.refresh_account_data()
	else:
		_call_bridge("refreshAccountData", [])

func save_deck(deck_id: String, deck_name: String, content: Dictionary) -> void:
	if _desktop_auth:
		_desktop_auth.save_deck(deck_id, deck_name, content)
	else:
		_call_bridge("saveDeck", [deck_id, deck_name, content])

func delete_deck(deck_id: String) -> void:
	if _desktop_auth:
		_desktop_auth.delete_deck(deck_id)
	else:
		_call_bridge("deleteDeck", [deck_id])

func update_profile(username: String, display_name: String) -> void:
	if _desktop_auth:
		_desktop_auth.update_profile(username, display_name)
	else:
		_call_bridge("updateProfile", [username, display_name])

func _call_bridge(method: String, args: Array) -> void:
	if not _bridge_started:
		state_changed.emit(state.duplicate(true))
		return
	var args_json := JSON.stringify(args)
	JavaScriptBridge.eval("window.CSAAuthBridge.%s(...%s)" % [method, args_json])
