class_name RemoteState
extends GameState
## Client-side mirror of the server's GameState. Fields come from StateView snapshots, so every
## query helper the UI uses (can_play, valid_targets, ...) keeps working; actions are not run
## locally but sent to the server through `send`, and return [] (the UI waits for the reply).

var seat := 0
var send: Callable ## func(msg: Dictionary)

func _init(deck_a: String = "fogo", deck_b: String = "agua") -> void:
	super(deck_a, deck_b)

## JSON turns ints into floats and int dict keys into strings; undo both.
static func normalize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) else v
		TYPE_ARRAY:
			var out: Array = []
			for x in v:
				out.append(normalize(x))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				var key: Variant = k
				if typeof(k) == TYPE_STRING and (k as String).is_valid_int():
					key = int(k)
				d[key] = normalize(v[k])
			return d
	return v

func apply_snapshot(snap: Dictionary) -> void:
	var s: Dictionary = normalize(snap)
	players = s["players"]
	active = s["active"]
	turn = s["turn"]
	phase = s["phase"]
	winner = s["winner"]
	attackers = s["attackers"]
	pending_search = s["pending_search"]

func _act(m: Dictionary) -> Array:
	m["t"] = "act"
	send.call(m)
	return []

func mulligan(_p: int, hand_uids: Array) -> Array:
	return _act({"a": "mulligan", "uids": hand_uids})

func play_card(_p: int, hand_uid: int, target: int = 0) -> Array:
	return _act({"a": "play", "uid": hand_uid, "target": target})

func cast_legendary(_p: int, target: int = 0) -> Array:
	return _act({"a": "legendary", "target": target})

func use_ability(_p: int, target: int = 0) -> Array:
	return _act({"a": "ability", "target": target})

func declare_attack(_p: int, attacks: Dictionary) -> Array:
	return _act({"a": "attack", "attacks": attacks})

func declare_blocks(_p: int, blocks: Dictionary) -> Array:
	return _act({"a": "blocks", "blocks": blocks})

func end_turn(_p: int) -> Array:
	return _act({"a": "end_turn"})

func discard(_p: int, hand_uids: Array) -> Array:
	return _act({"a": "discard", "uids": hand_uids})

func choose_search(_p: int, card_uid: int) -> Array:
	return _act({"a": "search", "uid": card_uid})
