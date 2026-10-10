class_name CardDef
extends RefCounted
## One catalog card. `raw` is the JSON as loaded (what the engine still reads through CardDB.card);
## parsed effects/listeners are added here as the engine moves off raw dicts.

var id: String
var raw: Dictionary

var _effects: Array = [] ## parsed lazily, so every class is loaded before the first parse
var _effects_parsed := false
var _activated_effects: Array = []
var _activated_parsed := false

func _init(card_id: String, data: Dictionary) -> void:
	id = card_id
	raw = data

## The card's "effects" as Effect objects, in JSON order.
func effects() -> Array:
	if not _effects_parsed:
		_effects = EffectRegistry.parse_list(raw.get("effects", []))
		_effects_parsed = true
	return _effects

## The effects of the card's "activated" ability (empty when it has none).
func activated_effects() -> Array:
	if not _activated_parsed:
		_activated_effects = EffectRegistry.parse_list(raw.get("activated", {}).get("effects", []))
		_activated_parsed = true
	return _activated_effects
