class_name DeckStore
extends Node
## The player's own decks. Signed in with Google: they live in the Supabase `decks` table (through the
## SupabaseAuth autoload). Playing as a guest: they live in this device's local storage (the browser's
## localStorage on the web export, user://decks.json on desktop).
##
## A deck is always handled as the same Dictionary, wherever it is kept:
##   {id, name, description, leader, incarnation_id, cards {card_id: copies}, updated_at, cloud, problems [String]}
## `problems` lists what had to be repaired while loading (unknown cards dropped, unknown Leader...).
## Rules are NOT enforced here: an unfinished deck is a valid draft. DeckDB.validate_cards judges it.
##
## Cloud writes are queued and sent one at a time, because SupabaseAuth only reports the latest action.

signal changed ## the list of decks changed (saved, deleted, account state changed)
signal saved(deck: Dictionary)
signal deleted(deck_id: String)
signal failed(message: String)
signal import_finished(imported: int, failed_count: int)

const STORAGE_KEY := "csa_user_decks_v1"
## Per account (or per device for a guest). The database enforces the same number on its own
## (supabase/migrations/202610250003_deck_limit.sql); keep the two in sync.
const MAX_DECKS := 24
const DECK_LIMIT_ERROR := "deck_limit_reached" ## what the database trigger raises
const MAX_NAME := 60
const MAX_CARD_COPIES := 99
const OPERATION_TIMEOUT := 20.0
const LOCAL_PREFIX := "local-"

## Where guest decks are kept outside the web export. Tests point this somewhere disposable.
var local_path := "user://decks.json"
var use_web_storage := OS.has_feature("web")
## Tests switch this off so they stay on disposable local files even when a Google session is saved on this
## machine; otherwise they would write into the real account.
var allow_cloud := true
var busy := false

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _operation_serial := 0
var _import_ok := 0
var _import_failed := 0
var _importing := false

func _ready() -> void:
	var auth := _auth()
	if auth != null:
		auth.state_changed.connect(_on_state_changed)
		auth.action_completed.connect(_on_action_completed)

func _exit_tree() -> void:
	var auth := _auth()
	if auth == null:
		return
	if auth.state_changed.is_connected(_on_state_changed):
		auth.state_changed.disconnect(_on_state_changed)
	if auth.action_completed.is_connected(_on_action_completed):
		auth.action_completed.disconnect(_on_action_completed)

func _auth() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("SupabaseAuth") if tree != null else null

func is_cloud() -> bool:
	var auth := _auth()
	return allow_cloud and auth != null and auth.is_signed_in()

## "Conta Google" name for the banner; empty for a guest.
func account_name() -> String:
	var auth := _auth()
	if auth == null or not auth.is_signed_in():
		return ""
	var profile: Dictionary = auth.state.get("profile", {})
	var user: Dictionary = auth.state.get("user", {})
	for candidate in [profile.get("display_name", ""), profile.get("username", ""), user.get("email", "")]:
		if String(candidate) != "":
			return String(candidate)
	return "Conta Google"

# ---------------------------------------------------------------- reading

## Every deck of the current destination (the account while signed in, this device otherwise), most
## recently changed first.
func list() -> Array[Dictionary]:
	var decks: Array[Dictionary] = []
	if is_cloud():
		for row in _auth().state.get("decks", []):
			if row is Dictionary:
				decks.append(normalize(row, true))
	else:
		for row in _read_local():
			decks.append(normalize(row, false))
	decks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["updated_at"]) > String(b["updated_at"]))
	return decks

func find(deck_id: String) -> Dictionary:
	for deck in list():
		if deck["id"] == deck_id:
			return deck
	return {}

## Decks saved on this device (guest mode) that could be moved into the account.
func local_decks() -> Array[Dictionary]:
	var decks: Array[Dictionary] = []
	for row in _read_local():
		decks.append(normalize(row, false))
	return decks

func is_full() -> bool:
	return list().size() >= MAX_DECKS

## Turns a stored row ({id, name, content{leader, cards, description}, updated_at}) into a deck, repairing
## whatever the card data no longer knows about instead of failing.
static func normalize(row: Dictionary, cloud: bool) -> Dictionary:
	var content: Dictionary = row.get("content", {}) if row.get("content", {}) is Dictionary else {}
	var problems: Array[String] = []
	var cards: Dictionary = {}
	var dropped := 0
	var raw_cards: Dictionary = content.get("cards", {}) if content.get("cards", {}) is Dictionary else {}
	for card_id in raw_cards:
		var copies := clampi(int(raw_cards[card_id]), 0, MAX_CARD_COPIES)
		if copies <= 0:
			continue
		if not CardDB.data()["cards"].has(card_id):
			dropped += copies
			continue
		cards[String(card_id)] = copies
	if dropped > 0:
		problems.append("%d carta%s que não existe%s mais foi%s removida%s." % [dropped, "" if dropped == 1 else "s", "" if dropped == 1 else "m", "" if dropped == 1 else "ram", "" if dropped == 1 else "s"])
	var leader := String(content.get("leader", ""))
	if not CardDB.data()["leaders"].has(leader):
		if leader != "":
			problems.append("O Líder \"%s\" não existe mais." % leader)
		leader = ""
	var raw_incarnation := String(content.get("incarnation_id", ""))
	var incarnation_id := ""
	if leader != "":
		incarnation_id = DeckDB.resolved_incarnation_id(leader, raw_incarnation)
		if raw_incarnation != "" and raw_incarnation != incarnation_id:
			problems.append("A Encarnação salva não combina com este Líder; a opção padrão foi restaurada.")
	return {
		"id": String(row.get("id", "")),
		"name": String(row.get("name", "Deck sem nome")),
		"description": String(content.get("description", "")),
		"leader": leader,
		"incarnation_id": incarnation_id,
		"cards": DeckDB.sorted_cards(cards),
		"updated_at": String(row.get("updated_at", row.get("created_at", ""))),
		"cloud": cloud,
		"problems": problems,
	}

## The JSON that gets stored for a deck.
static func to_content(leader: String, cards: Dictionary, description := "", incarnation_id := "") -> Dictionary:
	return {"leader": leader, "incarnation_id": DeckDB.resolved_incarnation_id(leader, incarnation_id), "cards": DeckDB.sorted_cards(cards), "description": description}

static func clean_name(deck_name: String) -> String:
	var cleaned := deck_name.strip_edges().left(MAX_NAME)
	return cleaned if cleaned != "" else "Deck sem nome"

# ---------------------------------------------------------------- writing

## Creates (deck_id == "") or updates a deck. Emits `saved` with the stored deck, or `failed`.
func save_deck(deck_id: String, deck_name: String, leader: String, cards: Dictionary, description := "", incarnation_id := "") -> void:
	var content := to_content(leader, cards, description, incarnation_id)
	var clean := clean_name(deck_name)
	if deck_id == "" and is_full():
		failed.emit("Limite de %d decks atingido. Exclua algum para criar outro." % MAX_DECKS)
		return
	if is_cloud():
		_enqueue({"kind": "save_deck", "id": deck_id, "name": clean, "content": content})
	else:
		_save_local(deck_id, clean, content)

func delete_deck(deck_id: String) -> void:
	if is_cloud():
		_enqueue({"kind": "delete_deck", "id": deck_id})
	else:
		var rows := _read_local().filter(func(row: Dictionary) -> bool: return String(row.get("id", "")) != deck_id)
		if _write_local(rows):
			deleted.emit(deck_id)
			changed.emit()

## Moves every deck saved on this device into the signed-in account, one at a time. Each local copy is
## removed only after the account confirmed it.
func import_local_decks() -> void:
	if not is_cloud() or _importing:
		return
	var rows := _read_local()
	if rows.is_empty():
		import_finished.emit(0, 0)
		return
	_importing = true
	_import_ok = 0
	_import_failed = 0
	var free_slots := maxi(0, MAX_DECKS - list().size())
	for row in rows:
		if free_slots <= 0:
			_import_failed += 1 # stays on the device; it can be imported after the account frees a slot
			continue
		free_slots -= 1
		var deck := normalize(row, false)
		_enqueue({"kind": "save_deck", "id": "", "name": clean_name(deck["name"]), "content": to_content(deck["leader"], deck["cards"], deck["description"], deck["incarnation_id"]), "import_local_id": deck["id"]})
	if _queue.is_empty() and _current.is_empty(): # nothing could be sent (the account is full)
		_importing = false
		import_finished.emit(_import_ok, _import_failed)

# ---------------------------------------------------------------- local storage

func _read_local() -> Array[Dictionary]:
	var text := ""
	if use_web_storage:
		var value: Variant = JavaScriptBridge.eval("(function(){try{return window.localStorage.getItem(%s)||''}catch(e){return ''}})()" % JSON.stringify(STORAGE_KEY))
		text = String(value) if value != null else ""
	elif FileAccess.file_exists(local_path):
		text = FileAccess.get_file_as_string(local_path)
	var rows: Array[Dictionary] = []
	if text == "":
		return rows
	var parsed: Variant = JSON.parse_string(text)
	var raw: Array = parsed.get("decks", []) if parsed is Dictionary else []
	for row in raw:
		if row is Dictionary and String(row.get("id", "")) != "":
			rows.append(row)
	return rows

func _write_local(rows: Array) -> bool:
	var text := JSON.stringify({"version": 1, "decks": rows})
	if use_web_storage:
		var ok: Variant = JavaScriptBridge.eval("(function(){try{window.localStorage.setItem(%s,%s);return true}catch(e){return false}})()" % [JSON.stringify(STORAGE_KEY), JSON.stringify(text)])
		if not bool(ok):
			failed.emit("O navegador não deixou salvar os decks neste dispositivo (armazenamento cheio ou bloqueado).")
			return false
		return true
	var file := FileAccess.open(local_path, FileAccess.WRITE)
	if file == null:
		failed.emit("Não foi possível salvar os decks neste dispositivo.")
		return false
	file.store_string(text)
	return true

func _save_local(deck_id: String, deck_name: String, content: Dictionary) -> void:
	var rows := _read_local()
	var now := Time.get_datetime_string_from_system(true) + "Z"
	var row: Dictionary = {}
	for existing in rows:
		if String(existing.get("id", "")) == deck_id and deck_id != "":
			row = existing
			break
	if row.is_empty():
		row = {"id": _new_local_id()}
		rows.append(row)
	row["name"] = deck_name
	row["content"] = content
	row["updated_at"] = now
	if not _write_local(rows):
		return
	saved.emit(normalize(row, false))
	changed.emit()

func _new_local_id() -> String:
	return "%s%d-%04x" % [LOCAL_PREFIX, Time.get_unix_time_from_system(), randi() % 0x10000]

# ---------------------------------------------------------------- cloud queue

func _enqueue(operation: Dictionary) -> void:
	_queue.append(operation)
	busy = true
	_pump()

func _pump() -> void:
	if not _current.is_empty():
		return
	if _queue.is_empty():
		busy = false
		return
	var auth := _auth()
	_current = _queue.pop_front()
	if auth == null or not auth.is_signed_in():
		_finish_current("Entre com Google para usar seus decks da conta.", {})
		return
	_operation_serial += 1
	var serial := _operation_serial
	var tree := get_tree()
	if tree != null:
		tree.create_timer(OPERATION_TIMEOUT).timeout.connect(func():
			if _operation_serial == serial and not _current.is_empty():
				_finish_current("O servidor demorou demais para responder. Tente novamente.", {}))
	if _current["kind"] == "save_deck":
		auth.save_deck(_current["id"], _current["name"], _current["content"])
	else:
		auth.delete_deck(_current["id"])

func _on_action_completed(action: Dictionary) -> void:
	if _current.is_empty() or String(action.get("kind", "")) != String(_current["kind"]):
		return
	var error := String(action.get("error", ""))
	_finish_current(error, action.get("data", {}) if action.get("data", {}) is Dictionary else {})

func _on_state_changed(_state: Dictionary) -> void:
	changed.emit()

func _finish_current(error: String, data: Dictionary) -> void:
	var operation := _current
	_current = {}
	_operation_serial += 1
	var import_id := String(operation.get("import_local_id", ""))
	if error != "":
		if import_id != "":
			_import_failed += 1
		failed.emit(_friendly_error(error))
	elif operation["kind"] == "save_deck":
		var row: Dictionary = data if not data.is_empty() else {"id": operation["id"], "name": operation["name"], "content": operation["content"]}
		if import_id != "":
			_import_ok += 1
			var rows := _read_local().filter(func(r: Dictionary) -> bool: return String(r.get("id", "")) != import_id)
			_write_local(rows)
		saved.emit(normalize(row, true))
	else:
		deleted.emit(String(operation["id"]))
	changed.emit()
	if _queue.is_empty() and _importing:
		_importing = false
		import_finished.emit(_import_ok, _import_failed)
	_pump()

static func _friendly_error(error: String) -> String:
	var lowered := error.to_lower()
	if lowered.contains(DECK_LIMIT_ERROR):
		return "Limite de %d decks atingido. Exclua algum para criar outro." % MAX_DECKS
	if lowered.contains("failed to fetch") or lowered.contains("network") or lowered.contains("conex"):
		return "Sem conexão com a conta. Verifique sua internet e tente de novo."
	return "Não foi possível concluir: %s" % error
