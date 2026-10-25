class_name CardFilter
extends RefCounted
## One shared way to say "which cards qualify" for effects that look through a zone (deck searches,
## "summon_from"...). The filter is a plain dictionary taken from the card's JSON; every key is optional
## and a card must pass all the keys that are present:
##   essence, element        the card has this essence / element
##   max_cost, min_cost       printed cost limits (inclusive)
##   type, types_any          the card type, or one of several types
##   rarity                   "common" | "epic" | "champion" | "legendary"
##   species                  the card has this species
##   species_any              the card has at least one of these species
##   card_ids                 only these named cards
##   tags                     the card has ALL of these tags
##   tags_any                 the card has at least ONE of these tags
##   any_of                   a list of whole filters; the card must pass at least ONE of them (an "or" between
##                            different kinds of requirement, e.g. element Luz OR species Anjo)

static func matches(card_id: String, filter: Dictionary) -> bool:
	var card_data := CardDB.card(card_id)
	if filter.get("essence", "") != "" and not CardDB.has_essence(card_data, filter["essence"]):
		return false
	if filter.get("element", "") != "" and not CardDB.has_element(card_data, filter["element"]):
		return false
	if filter.has("max_cost") and int(card_data.get("cost", 999)) > int(filter["max_cost"]):
		return false
	if filter.has("min_cost") and int(card_data.get("cost", 0)) < int(filter["min_cost"]):
		return false
	if filter.has("type") and card_data.get("type", "") != filter["type"]:
		return false
	if filter.has("types_any") and not filter["types_any"].has(card_data.get("type", "")):
		return false
	if filter.has("rarity") and card_data.get("rarity", "") != filter["rarity"]:
		return false
	if filter.has("card_ids") and not filter["card_ids"].has(card_id):
		return false
	var card_species: Array = card_data.get("species", [])
	if filter.has("species") and not card_species.has(filter["species"]):
		return false
	if filter.has("species_any") and not _shares_any(card_species, filter["species_any"]):
		return false
	var card_tags: Array = card_data.get("tags", [])
	if filter.has("tags"):
		for tag in filter["tags"]:
			if not card_tags.has(tag):
				return false
	if filter.has("tags_any") and not _shares_any(card_tags, filter["tags_any"]):
		return false
	if filter.has("any_of"):
		var passes_one_alternative := false
		for alternative: Dictionary in filter["any_of"]:
			if matches(card_id, alternative):
				passes_one_alternative = true
				break
		if not passes_one_alternative:
			return false
	return true

static func _shares_any(own_values: Array, wanted_values: Array) -> bool:
	for wanted in wanted_values:
		if own_values.has(wanted):
			return true
	return false
