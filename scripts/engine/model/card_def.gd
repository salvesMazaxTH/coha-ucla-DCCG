class_name CardDef
extends RefCounted
## One catalog card. `raw` is the JSON as loaded (what the engine still reads through CardDB.card);
## parsed effects/listeners are added here as the engine moves off raw dicts.

var id: String
var raw: Dictionary

func _init(card_id: String, data: Dictionary) -> void:
	id = card_id
	raw = data
