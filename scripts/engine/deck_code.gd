class_name DeckCode
extends RefCounted
## Shareable deck code, "<prefix>.<base64url>". Two versions:
## - "CSA2." (the one written): compact binary. Every card and Leader is written as a 3-byte number
##   (a hash of its id), so nothing has to be registered or kept up to date when a card is added.
## - "CSA1." (still read; also the fallback written when CSA2 cannot be used safely): the deck as JSON.
##
## CSA2 layout, in bytes:
##   3        Leader
##   1        flags (bit 0: the deck uses an Encarnação other than the Leader's default)
##   3        that Encarnação, only when bit 0 is set
##   then, for 1, 2 and 3 copies in this order: 1 byte N, followed by N cards of 3 bytes each
##   rest     deck name in UTF-8
## The description is never written (a code is for sharing the cards, and a long description made it huge),
## but codes made earlier may carry one after the name (a 0 byte, then the text), and those are still read.
##
## Two ids can, rarely, hash to the same number. That never produces a wrong deck: a deck that
## uses such a card is written as CSA1 instead, and a CSA2 code that names an ambiguous number is
## refused. tests/run_tests.gd lists collisions so one can be fixed by renaming a card.

const PREFIX_V1 := "CSA1."
const PREFIX_V2 := "CSA2."
const INDEX_BYTES := 3
const INDEX_MASK := 0xFFFFFF
const MAX_COPIES_IN_CODE := 3
const FLAG_CUSTOM_INCARNATION := 1

## number -> id, or "" when two ids share that number. Built on first use.
static var _card_by_index: Dictionary = {}
static var _leader_by_index: Dictionary = {}
static var _collisions: Array[String] = []

## The number a card or Leader id is written as: FNV-1a (32 bit) folded to 24 bits. It is computed here
## by hand, not with String.hash(), because a shared code must give the same number on every Godot version.
static func index_of(id: String) -> int:
	var running_hash := 2166136261
	for byte in id.to_utf8_buffer():
		running_hash = ((running_hash ^ byte) * 16777619) & 0xFFFFFFFF
	return (running_hash ^ (running_hash >> 24)) & INDEX_MASK

## Human-readable list of ids that share a number (empty when all is well).
static func collisions() -> Array[String]:
	_build_maps()
	return _collisions.duplicate()

static func _build_maps() -> void:
	if not _card_by_index.is_empty():
		return
	_collisions.clear()
	_fill_map(_card_by_index, CardDB.data()["cards"], "carta")
	_fill_map(_leader_by_index, CardDB.data()["leaders"], "Líder")

static func _fill_map(map: Dictionary, ids: Dictionary, kind: String) -> void:
	var first_owner: Dictionary = {}
	for raw_id in ids:
		var id := String(raw_id)
		var number := index_of(id)
		if first_owner.has(number):
			_collisions.append("%s %s e %s têm o mesmo número" % [kind, first_owner[number], id])
			map[number] = ""
		else:
			first_owner[number] = id
			map[number] = id

# ---------------------------------------------------------------- writing

static func encode(deck_name: String, leader: String, incarnation_id: String, cards: Dictionary) -> String:
	var compact := _encode_compact(deck_name, leader, incarnation_id, cards)
	if not compact.is_empty():
		return PREFIX_V2 + _to_base64url(compact)
	var payload := {
		"name": deck_name,
		"leader": leader,
		"incarnation_id": incarnation_id,
		"cards": DeckDB.sorted_cards(cards),
	}
	return PREFIX_V1 + _to_base64url(JSON.stringify(payload).to_utf8_buffer())

## Empty when the deck cannot be written as CSA2 without risk (unknown or ambiguous id, odd copy count).
static func _encode_compact(deck_name: String, leader: String, incarnation_id: String, cards: Dictionary) -> PackedByteArray:
	_build_maps()
	if not _is_unambiguous(_leader_by_index, leader):
		return PackedByteArray()
	var uses_custom_incarnation := incarnation_id != "" and incarnation_id != String(CardDB.leader(leader).get("incarnation", ""))
	if uses_custom_incarnation and not _is_unambiguous(_card_by_index, incarnation_id):
		return PackedByteArray()
	var bytes := PackedByteArray()
	_append_index(bytes, index_of(leader))
	bytes.append(FLAG_CUSTOM_INCARNATION if uses_custom_incarnation else 0)
	if uses_custom_incarnation:
		_append_index(bytes, index_of(incarnation_id))
	var ids_by_copies := {1: [], 2: [], 3: []}
	for raw_id in cards:
		var card_id := String(raw_id)
		var copies := int(cards[raw_id])
		if copies < 1 or copies > MAX_COPIES_IN_CODE or not _is_unambiguous(_card_by_index, card_id):
			return PackedByteArray()
		ids_by_copies[copies].append(index_of(card_id))
	for copies in range(1, MAX_COPIES_IN_CODE + 1):
		var numbers: Array = ids_by_copies[copies]
		if numbers.size() > 255:
			return PackedByteArray()
		numbers.sort() # the same deck always gives the same code
		bytes.append(numbers.size())
		for number in numbers:
			_append_index(bytes, number)
	bytes.append_array(deck_name.to_utf8_buffer())
	return bytes

static func _is_unambiguous(map: Dictionary, id: String) -> bool:
	return id != "" and map.get(index_of(id), "") == id

static func _append_index(bytes: PackedByteArray, number: int) -> void:
	bytes.append((number >> 16) & 0xFF)
	bytes.append((number >> 8) & 0xFF)
	bytes.append(number & 0xFF)

static func _to_base64url(bytes: PackedByteArray) -> String:
	var encoded := Marshalls.raw_to_base64(bytes)
	return encoded.replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")

# ---------------------------------------------------------------- reading

## {"payload": {name, description, leader, cards[, incarnation_id]}} or {"error": text}. Only the shape is
## checked here (known ids, readable code): whether the deck is legal is up to the caller.
static func decode(code: String) -> Dictionary:
	var cleaned := code.strip_edges()
	var is_compact := cleaned.begins_with(PREFIX_V2)
	if not is_compact and not cleaned.begins_with(PREFIX_V1):
		return {"error": "Código inválido. Esperava um código iniciado por %s." % PREFIX_V2}
	var bytes := _from_base64url(cleaned.substr(PREFIX_V2.length()))
	if bytes.is_empty():
		return {"error": "Não foi possível decodificar este deckCode."}
	if is_compact:
		return _decode_compact(bytes)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return {"error": "Conteúdo do deckCode inválido."}
	return {"payload": parsed}

static func _from_base64url(text: String) -> PackedByteArray:
	var encoded := text.replace("-", "+").replace("_", "/")
	while encoded.length() % 4 != 0:
		encoded += "="
	return Marshalls.base64_to_raw(encoded)

static func _decode_compact(bytes: PackedByteArray) -> Dictionary:
	_build_maps()
	var truncated := {"error": "O deckCode está incompleto ou corrompido."}
	var position := 0
	if bytes.size() < INDEX_BYTES + 1:
		return truncated
	var leader_number := _read_index(bytes, position)
	position += INDEX_BYTES
	var leader := String(_leader_by_index.get(leader_number, ""))
	if leader == "":
		return {"error": "O deckCode contém um Líder desconhecido."}
	var flags := bytes[position]
	position += 1
	var payload := {"leader": leader}
	if flags & FLAG_CUSTOM_INCARNATION:
		if position + INDEX_BYTES > bytes.size():
			return truncated
		var incarnation := String(_card_by_index.get(_read_index(bytes, position), ""))
		position += INDEX_BYTES
		if incarnation == "":
			return {"error": "O deckCode contém uma carta desconhecida (Encarnação)."}
		payload["incarnation_id"] = incarnation
	var cards: Dictionary = {}
	for copies in range(1, MAX_COPIES_IN_CODE + 1):
		if position >= bytes.size():
			return truncated
		var group_size := bytes[position]
		position += 1
		if position + group_size * INDEX_BYTES > bytes.size():
			return truncated
		for _card in group_size:
			var card_id := String(_card_by_index.get(_read_index(bytes, position), ""))
			position += INDEX_BYTES
			if card_id == "":
				return {"error": "O deckCode contém uma carta desconhecida."}
			cards[card_id] = copies
	payload["cards"] = cards
	var text := bytes.slice(position)
	var separator := text.find(0)
	payload["name"] = (text if separator < 0 else text.slice(0, separator)).get_string_from_utf8()
	payload["description"] = "" if separator < 0 else text.slice(separator + 1).get_string_from_utf8()
	return {"payload": payload}

static func _read_index(bytes: PackedByteArray, position: int) -> int:
	return (bytes[position] << 16) | (bytes[position + 1] << 8) | bytes[position + 2]
