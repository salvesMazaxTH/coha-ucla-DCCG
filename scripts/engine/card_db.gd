class_name CardDB
extends RefCounted
## Static card catalog loaded from data/cards.json and data/cards/<essence>/*.json.

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/cards.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
		_data["cards"] = {}
		for essence_id in _data["essences"]:
			var dir_path: String = "res://data/cards/" + str(essence_id)
			if not DirAccess.dir_exists_absolute(dir_path):
				continue
			for file_name in DirAccess.get_files_at(dir_path):
				if not file_name.ends_with(".json"):
					continue
				var card_file := FileAccess.open(dir_path + "/" + file_name, FileAccess.READ)
				if card_file:
					_data["cards"][file_name.trim_suffix(".json")] = JSON.parse_string(card_file.get_as_text())
	return _data

static func card(id: String) -> Dictionary:
	return data()["cards"][id]

## Card data with a summoned instance's overrides (atk, hp, keywords, effects, text...) applied.
static func card_for(id: String, inst: Dictionary = {}) -> Dictionary:
	var cd: Dictionary = data()["cards"][id]
	var over: Dictionary = inst.get("over", {})
	if over.is_empty():
		return cd
	var m := cd.duplicate()
	m.merge(over, true)
	return m

static func leader(id: String) -> Dictionary:
	return data()["leaders"][id]

## True for a Leader's own champion card (cast from the Command Zone).
static func is_leader_card(id: String) -> bool:
	for lid in data()["leaders"]:
		if data()["leaders"][lid]["legendary"] == id:
			return true
	return false

static func keyword(id: String) -> Dictionary:
	return data()["keywords"][id]

static func essence(id: String) -> Dictionary:
	return data()["essences"][id]

## A card's essences: "essence" is one id or an Array of ids (dual cards, e.g. aquática + glacial).
static func essences_of(cd: Dictionary) -> Array:
	var e: Variant = cd.get("essence", "neutra")
	return (e as Array).duplicate() if e is Array else [String(e)]

static func has_essence(cd: Dictionary, id: String) -> bool:
	return essences_of(cd).has(id)

## Display name of a card's essences ("Aquática / Glacial").
static func essence_names(cd: Dictionary) -> String:
	var names: Array = []
	for id in essences_of(cd):
		names.append(essence(id).get("name", id))
	return " / ".join(names)

## Display name of a card's species ("Humano / Dragão"); empty when it has none.
static func species_names(cd: Dictionary) -> String:
	var names: Array = []
	for id in cd.get("species", []):
		names.append(data().get("species", {}).get(id, {}).get("name", id))
	return " / ".join(names)
