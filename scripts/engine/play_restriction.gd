class_name PlayRestriction
extends RefCounted
## One rule of "what a player is restricted to when playing cards" (the "restriction" of cards.json).
##
## {
##   "mode": "only" | "forbid",   # only: cards that do NOT match are barred; forbid: cards that match are barred
##   "match": {                   # every field given must match (AND); a list matches if ANY of its entries does
##     "essence": ["neutra"],     # the card has one of these essences
##     "rarity":  ["champion"],   # common | epic | champion | legendary
##     "card_type": ["unit"],     # unit | spell | artifact
##     "subtype": ["local"],      # the card is an artifact of one of these subtypes (equipment | local)
##     "cost": {"op": "<=", "value": 3}   # printed cost, compared with == != < <= > >=
##   },
##   "turns": 1                   # how long it lasts, counted in turns (every player's turn counts):
##                                # 1 = the rest of the current turn, 2 = also the next turn, ...
## }
##
## Examples: "only neutral cards this turn" = {"mode": "only", "match": {"essence": ["neutra"]}};
## "can't play non-Fúria cards" = {"mode": "only", "match": {"essence": ["furia"]}};
## "can't play champions" = {"mode": "forbid", "match": {"rarity": ["champion"]}};
## "can't play Locais" = {"mode": "forbid", "match": {"subtype": ["local"]}}.
## A new kind of filter: add its name to MATCH_FIELDS, a check in _matches() and one in error_of().

const MODES := ["only", "forbid"]
const MATCH_FIELDS := ["essence", "rarity", "card_type", "subtype", "cost"]
const RARITIES := ["common", "epic", "champion", "legendary"]
const CARD_TYPES := ["unit", "spell", "artifact"]
const SUBTYPES := ["equipment", "local"]
const COST_OPERATORS := ["==", "!=", "<", "<=", ">", ">="]

## True when this rule bars the card `cd` (the card's data) from being played.
static func blocks(rule: Dictionary, cd: Dictionary) -> bool:
	var matches := _matches(rule.get("match", {}), cd)
	return not matches if rule.get("mode", "only") == "only" else matches

## True when the card satisfies every field of `match_fields`.
static func _matches(match_fields: Dictionary, cd: Dictionary) -> bool:
	if match_fields.has("essence"):
		var has_wanted_essence := false
		for essence_id in match_fields["essence"]:
			has_wanted_essence = has_wanted_essence or CardDB.has_essence(cd, String(essence_id))
		if not has_wanted_essence:
			return false
	if match_fields.has("rarity") and String(cd.get("rarity", "")) not in match_fields["rarity"]:
		return false
	if match_fields.has("card_type"):
		var has_wanted_type := false
		for type_id in match_fields["card_type"]:
			has_wanted_type = has_wanted_type or CardDB.has_type(cd, String(type_id))
		if not has_wanted_type:
			return false
	if match_fields.has("subtype"):
		var has_wanted_subtype := false
		for subtype_id in match_fields["subtype"]:
			has_wanted_subtype = has_wanted_subtype or cd.get("subtypes", []).has(String(subtype_id))
		if not has_wanted_subtype:
			return false
	if match_fields.has("cost"):
		var comparison: Dictionary = match_fields["cost"]
		if not _compare(int(cd.get("cost", 0)), String(comparison["op"]), int(comparison["value"])):
			return false
	return true

static func _compare(left: int, operator: String, right: int) -> bool:
	match operator:
		"==": return left == right
		"!=": return left != right
		"<": return left < right
		"<=": return left <= right
		">": return left > right
		">=": return left >= right
	return false

## The problem with a restriction rule, or "" when it is valid (checked when the catalog loads).
static func error_of(rule: Variant, known_essences: Dictionary) -> String:
	if not rule is Dictionary:
		return "restriction precisa ser um objeto"
	if String(rule.get("mode", "only")) not in MODES:
		return "restriction.mode desconhecido \"%s\"" % rule.get("mode")
	if not rule.get("match", null) is Dictionary or rule["match"].is_empty():
		return "restriction.match precisa ser um objeto com ao menos um filtro"
	if int(rule.get("turns", 1)) < 1:
		return "restriction.turns precisa ser pelo menos 1"
	var match_fields: Dictionary = rule["match"]
	for field in match_fields:
		if field not in MATCH_FIELDS:
			return "restriction.match filtro desconhecido \"%s\"" % field
		if field == "cost":
			var comparison: Variant = match_fields[field]
			if not comparison is Dictionary or not comparison.has("op") or not comparison.has("value") \
					or String(comparison["op"]) not in COST_OPERATORS:
				return "restriction.match.cost precisa de {op, value} com op em %s" % str(COST_OPERATORS)
			continue
		if not match_fields[field] is Array or match_fields[field].is_empty():
			return "restriction.match.%s precisa ser uma lista não vazia" % field
		for entry in match_fields[field]:
			if field == "essence" and not known_essences.has(entry):
				return "restriction.match.essence desconhecida \"%s\"" % entry
			if field == "rarity" and entry not in RARITIES:
				return "restriction.match.rarity desconhecida \"%s\"" % entry
			if field == "card_type" and entry not in CARD_TYPES:
				return "restriction.match.card_type desconhecido \"%s\"" % entry
			if field == "subtype" and entry not in SUBTYPES:
				return "restriction.match.subtype desconhecido \"%s\"" % entry
	return ""
