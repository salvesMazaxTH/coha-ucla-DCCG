class_name DeckAutofill
extends RefCounted
## Completes a partly built deck for the deck builder's "completar deck" button.
##
## The fill follows the plan the player gave the Deck Assistant (profile + focus): it builds a mana curve
## that fits the plan and reaches the card counts the assistant's "grave" and "médio" warnings ask for
## (cheap units for aggro, mid-cost threats for pressure midrange, card advantage for value midrange,
## removal for control, spells for a spell combo...). The numbers in _goals() are written to sit at or
## above the thresholds of DeckBuilder._coach_notes(). tests/smoke_ui.gd checks that a filled deck never
## gets a "grave" note, so change both places together.
##
## How it works: the deck is filled one card at a time. For every legal candidate the fill measures how
## much closer the deck gets to its goals ("deficit" = how far the deck is from them), adds a small bonus
## for card quality and for fitting the Leader's domains, and adds the best one. Only cards the player
## may already add by hand are used, so the result obeys every deck rule (copies, champion cap, two domains).

## Cost buckets of the curve: 0, 1, 2, 3, 4, 5, 6, 7 or more.
const CURVE_BUCKETS := 8
## How much a missing card costs the deck, by kind of shortage.
const GRAVE_WEIGHT := 8.0 # below the level the assistant calls "grave"
const MEDIUM_WEIGHT := 3.0 # below the level the assistant calls "médio"
const CURVE_SHORTAGE_WEIGHT := 1.0 # a slot of the ideal curve that is still empty
const CURVE_EXCESS_WEIGHT := 0.5 # a card beyond the ideal curve of its cost
const OTHER_DOMAIN_PENALTY := 0.75 # prefer the Leader's domains, but don't exclude strong role-fitting cards of another one
const LEADER_DOMAIN_BONUS := 0.5
const NEUTRAL_BONUS := 0.2
const SAME_TRIBE_BONUS := 0.25 # small push toward a deck whose cards share a tribe
const REPEAT_COPY_BONUS := 0.3 # per copy already in the deck: a consistent deck plays full sets, not one of everything

# ---------------------------------------------------------------- card traits

## What a card does for the assistant's counting (the same questions DeckBuilder._coach_notes() asks):
## burn to the enemy Leader, removal that has no restriction, and ways to draw or select cards.
static func traits_of(card: Dictionary) -> Dictionary:
	var has_burn := false
	var has_targeted_removal := false
	var has_global_removal := false
	var has_card_selection := false
	var has_soft_removal := false
	var has_sustain := false
	var effects := _effects_of(card)
	var activated: Dictionary = card.get("activated", {})
	var has_repeatable_sustain := false
	for effect in effects:
		var action := String(effect.get("action", ""))
		var target := String(effect.get("target", ""))
		if action in ["draw", "search_deck", "look_top", "look_bottom"]:
			has_card_selection = true
		if _is_sustain_effect(effect):
			has_sustain = true
		if _is_soft_removal_effect(effect):
			has_soft_removal = true
		var is_group_target := target.begins_with("all_") or target.begins_with("each_") \
				or target.begins_with("other_") or target.begins_with("center_")
		var removes_units := action in ["destroy", "banish", "damage"] \
				and (target.contains("unit") or target == "any")
		if removes_units:
			if is_group_target:
				var is_global_target := target in ["all_enemy_units", "all_units", "other_units"]
				var has_group_restriction: bool = not effect.get("unit_filter", {}).is_empty() \
						or String(effect.get("unit_state", "")) != "" \
						or not effect.get("unit_state_any", []).is_empty()
				if is_global_target and not has_group_restriction:
					has_global_removal = true
			else:
				var is_broad_target := target in ["enemy_unit", "any_unit", "any"]
				var has_target_restriction: bool = int(effect.get("max_target_cost", -1)) >= 0 \
						or not effect.get("requires_markers", {}).is_empty()
				if action in ["destroy", "banish"] and is_broad_target and not has_target_restriction:
					has_targeted_removal = true
		if action == "damage" and (target == "enemy_leader" or target == "both_leaders"):
			has_burn = true
	for effect in activated.get("effects", []):
		if _is_sustain_effect(effect):
			has_repeatable_sustain = true
	return {
		"burn": has_burn,
		"targeted_removal": has_targeted_removal,
		"global_removal": has_global_removal,
		"card_selection": has_card_selection,
		"soft_removal": has_soft_removal,
		"sustain": has_sustain,
		"repeatable_sustain": has_repeatable_sustain,
	}

static func _effects_of(card: Dictionary) -> Array:
	var effects: Array = card.get("effects", []).duplicate()
	var activated: Dictionary = card.get("activated", {})
	effects.append_array(activated.get("effects", []))
	return effects

static func _is_sustain_effect(effect: Dictionary) -> bool:
	var action := String(effect.get("action", ""))
	if action in ["heal_unit", "heal_leader", "heal_full", "leader_max_up"]:
		return true
	if action != "buff":
		return false
	var keywords: Array = effect.get("keywords", [])
	return int(effect.get("hp", 0)) > 0 or int(effect.get("armor", 0)) > 0 \
			or keywords.has("escudo") or keywords.has("escudo_magico") or keywords.has("escudo_supremo")

static func _is_soft_removal_effect(effect: Dictionary) -> bool:
	var action := String(effect.get("action", ""))
	var target := String(effect.get("target", ""))
	if not target.contains("enemy") and target != "opposed_unit":
		return false
	match action:
		"damage":
			var damage := maxi(int(effect.get("amount", 0)), int(effect.get("amount_if_frozen", 0)))
			damage = maxi(damage, int(effect.get("amount_if_stunned", 0)))
			return damage >= 2
		"freeze", "stun", "return_to_hand", "take_control", "silence":
			return true
		"buff":
			return int(effect.get("atk", 0)) < 0 or int(effect.get("hp", 0)) < 0
	return false

# ---------------------------------------------------------------- goals

## The card counts the filled deck should reach. "grave" is the level under which the assistant raises a
## serious warning; "goal" is the level under which it raises a milder one (or a bit more, for safety).
## Every count is for a full deck (DeckDB.DECK_SIZE cards).
static func _goals(profile: String, focus: String) -> Array[Dictionary]:
	var goals: Array[Dictionary] = []
	var deck_size := DeckDB.DECK_SIZE
	# every plan benefits from some answers and some card selection
	var value_midrange := profile == "midrange" and focus == "value"
	var selection_goal := 3 if (profile == "control" or (profile == "combo" and focus == "spells") or value_midrange) else 1
	var targeted_removal_goal := 4 if profile == "control" else (3 if value_midrange else 2)
	goals.append({"metric": "targeted_removal", "grave": 2 if profile == "control" else 0, "goal": targeted_removal_goal})
	goals.append({"metric": "global_removal", "grave": 0, "goal": 1})
	goals.append({"metric": "card_selection", "grave": 0, "goal": selection_goal})
	match profile:
		"aggro":
			var cheap_metric := "cheap_unit" if focus == "board" else "cheap"
			goals.append({
				"metric": cheap_metric,
				"grave": maxi(8, ceili(deck_size * 0.35)),
				"goal": maxi(10, ceili(deck_size * 0.45)),
			})
			goals.append({"metric": "unit", "grave": 0, "goal": 24})
			if focus == "burn":
				goals.append({"metric": "burn", "grave": 1, "goal": 5})
		"midrange":
			goals.append({"metric": "middle", "grave": ceili(deck_size * 0.40), "goal": ceili(deck_size * 0.50)})
			goals.append({"metric": "cheap", "grave": 0, "goal": 5})
			goals.append({"metric": "unit", "grave": 0, "goal": 22})
			if focus == "pressure":
				goals.append({"metric": "middle_unit", "grave": 0, "goal": ceili(deck_size * 0.30)})
			elif focus == "value":
				goals.append({"metric": "soft_removal", "grave": 0, "goal": 2})
		"control":
			goals.append({"metric": "cheap", "grave": 0, "goal": 4})
			goals.append({"metric": "unit", "grave": 0, "goal": 16})
			goals.append({"metric": "soft_removal", "grave": 0, "goal": 3})
			goals.append({"metric": "sustain", "grave": 0, "goal": 2})
			goals.append({"metric": "repeatable_sustain", "grave": 0, "goal": 1})
			if focus == "late":
				goals.append({"metric": "late_threat", "grave": 3, "goal": 8})
		"combo":
			goals.append({"metric": "cheap", "grave": 0, "goal": 5})
			goals.append({"metric": "unit", "grave": 0, "goal": 14})
			if focus == "spells":
				goals.append({"metric": "spell", "grave": 6, "goal": 10})
			else:
				goals.append({"metric": "pursued_tribe", "grave": 8, "goal": 13})
		_: # "unsure", or no plan chosen: a balanced deck
			goals.append({"metric": "cheap", "grave": 0, "goal": 6})
			goals.append({"metric": "unit", "grave": 0, "goal": 20})
	return goals

## How many cards of each cost the deck should have (sums to DeckDB.DECK_SIZE).
static func _ideal_curve(profile: String) -> Array[int]:
	var shape: Array[int]
	match profile:
		"aggro": shape = [2, 8, 10, 9, 7, 4, 3, 1]
		"midrange": shape = [1, 4, 7, 9, 9, 6, 5, 3]
		"control": shape = [1, 4, 7, 7, 7, 6, 6, 6]
		_: shape = [1, 5, 8, 8, 8, 6, 5, 3]
	return _scaled_to_deck_size(shape)

## The curve shapes above are written as proportions; this stretches one to exactly DeckDB.DECK_SIZE cards
## (the buckets with the biggest rounding remainder get the leftover cards).
static func _scaled_to_deck_size(shape: Array[int]) -> Array[int]:
	var shape_total := 0
	for count in shape:
		shape_total += count
	var scaled: Array[int] = []
	var remainders: Array[float] = []
	var assigned := 0
	for count in shape:
		var exact := float(count) * DeckDB.DECK_SIZE / shape_total
		scaled.append(int(exact))
		remainders.append(exact - int(exact))
		assigned += int(exact)
	while assigned < DeckDB.DECK_SIZE:
		var best_bucket := 0
		for bucket in remainders.size():
			if remainders[bucket] > remainders[best_bucket]:
				best_bucket = bucket
		scaled[best_bucket] += 1
		remainders[best_bucket] = -1.0
		assigned += 1
	return scaled

# ---------------------------------------------------------------- the fill

## Returns {"cards": the completed {card_id: copies} list, "added": how many cards were put in}.
## `candidates` is every card the player may add (the deck builder's pool). The incarnation card keeps
## its single copy and is never added again. When no legal card is left the deck stays shorter than full.
static func complete(
	leader_id: String,
	incarnation_id: String,
	cards: Dictionary,
	candidates: Array,
	profile: String,
	focus: String,
) -> Dictionary:
	var result_cards: Dictionary = cards.duplicate()
	var goals := _goals(profile, focus)
	var ideal_curve := _ideal_curve(profile)
	var pursued_tribe := ""
	if profile == "combo" and focus == "tribal":
		pursued_tribe = _choose_pursued_tribe(leader_id, incarnation_id, result_cards, candidates)
	var descriptions: Dictionary = {}
	for candidate in candidates:
		var candidate_id := String(candidate)
		if candidate_id != incarnation_id:
			descriptions[candidate_id] = _describe(candidate_id, leader_id, pursued_tribe)
	var state := _state_of(result_cards, incarnation_id, leader_id, pursued_tribe)
	var added := 0
	while int(state["total"]) < DeckDB.DECK_SIZE:
		var best_id := ""
		var best_score := -INF
		var current_deficit := _deficit(state, goals, ideal_curve)
		var leading_tribe := _leading_tribe(state)
		for card_id in descriptions:
			var description: Dictionary = descriptions[card_id]
			if not _can_add(description, result_cards, leader_id, incarnation_id):
				continue
			_apply(state, description, 1)
			var improvement := current_deficit - _deficit(state, goals, ideal_curve)
			_apply(state, description, -1)
			var score: float = improvement + float(description["fit"]) + float(description["quality"])
			if leading_tribe != "" and description["tribes"].has(leading_tribe):
				score += SAME_TRIBE_BONUS
			score += REPEAT_COPY_BONUS * int(result_cards.get(card_id, 0))
			if score > best_score:
				best_score = score
				best_id = String(card_id)
		if best_id == "":
			break # nothing legal is left to add
		_apply(state, descriptions[best_id], 1)
		result_cards[best_id] = int(result_cards.get(best_id, 0)) + 1
		added += 1
	return {"cards": result_cards, "added": added}

## Everything the fill needs to know about one candidate card, worked out once.
static func _describe(card_id: String, leader_id: String, pursued_tribe: String) -> Dictionary:
	var card: Dictionary = CardDB.card(card_id)
	var cost := int(card.get("cost", 0))
	var card_type := String(card.get("type", ""))
	var rarity := String(card.get("rarity", ""))
	var is_unit := card_type == "unit"
	var traits := traits_of(card)
	var tribes: Array = []
	for tribe_id in card.get("tribe", []):
		tribes.append(String(tribe_id))
	# the metrics this card adds one to, using the same names as _goals()
	var metrics: Array[String] = []
	if cost <= 2:
		metrics.append("cheap")
		if is_unit:
			metrics.append("cheap_unit")
	elif cost <= 5:
		metrics.append("middle")
		if is_unit:
			metrics.append("middle_unit")
	else:
		metrics.append("expensive")
		if is_unit:
			metrics.append("late_threat")
	if is_unit:
		metrics.append("unit")
	if card_type == "spell":
		metrics.append("spell")
	for trait_name in traits:
		if traits[trait_name]:
			metrics.append(String(trait_name))
	if pursued_tribe != "" and tribes.has(pursued_tribe):
		metrics.append("pursued_tribe")
	var is_outside := DeckDB.is_outside_leader_domain(leader_id, card_id)
	var fit := -OTHER_DOMAIN_PENALTY
	if not is_outside:
		fit = LEADER_DOMAIN_BONUS if DeckDB.is_in_leader_domain(leader_id, card_id) else NEUTRAL_BONUS
	return {
		"id": card_id,
		"bucket": mini(cost, CURVE_BUCKETS - 1),
		"metrics": metrics,
		"tribes": tribes,
		"is_champion": rarity == "champion",
		"limit": DeckDB.copy_limit(card_id),
		"is_outside": is_outside,
		"fit": fit,
		"quality": _quality(card),
	}

## A small, rough sense of card quality (kept below one deficit point so plan goals remain decisive).
## Unlike rarity, effect actions and magnitudes help identify actual interaction and repeatable value.
static func _quality(card: Dictionary) -> float:
	var quality := 0.0
	if String(card.get("type", "")) == "unit":
		var stat_total := int(card.get("atk", 0)) + int(card.get("hp", 0))
		var expected_total := float(card.get("cost", 0)) * 1.6 + 2.5
		quality += clampf((float(stat_total) - expected_total) * 0.08, -0.25, 0.35)
	quality += minf(0.15, 0.05 * card.get("keywords", []).size())
	var effect_quality := 0.0
	for effect in _effects_of(card):
		var action := String(effect.get("action", ""))
		var value := 0.0
		match action:
			"draw", "search_deck", "look_top", "look_bottom":
				value = 0.2
			"destroy", "banish", "return_to_hand", "take_control":
				value = 0.24
			"damage":
				var damage := maxi(int(effect.get("amount", 0)), int(effect.get("amount_if_frozen", 0)))
				damage = maxi(damage, int(effect.get("amount_if_stunned", 0)))
				value = minf(0.25, float(damage) * 0.06)
			"freeze", "stun":
				value = 0.16
			"heal_unit", "heal_leader", "heal_full", "leader_max_up":
				value = minf(0.22, float(effect.get("amount", 1)) * 0.06)
			"snowball_level":
				value = 0.18
			"buff":
				var stat_delta := absi(int(effect.get("atk", 0))) + absi(int(effect.get("hp", 0))) + absi(int(effect.get("armor", 0)))
				value = minf(0.18, float(stat_delta) * 0.04)
			_:
				value = 0.03
		if effect.has("if"):
			value *= 0.65
		var target := String(effect.get("target", ""))
		if target.begins_with("all_") or target.begins_with("each_"):
			value *= 1.25
		effect_quality += value
	quality += minf(0.6, effect_quality)
	return quality

## The counters the fill keeps up to date as cards are added. "counts" uses the metric names of _goals().
static func _state_of(cards: Dictionary, incarnation_id: String, leader_id: String, pursued_tribe: String) -> Dictionary:
	var state := {
		"total": 0,
		"counts": {},
		"buckets": [],
		"tribes": {},
	}
	state["buckets"].resize(CURVE_BUCKETS)
	state["buckets"].fill(0)
	for card_id in cards:
		var copies := int(cards[card_id])
		if String(card_id) == incarnation_id:
			copies -= 1 # the Encarnação is not drawn
		for copy_index in copies:
			_apply(state, _describe(String(card_id), leader_id, pursued_tribe), 1)
	return state

## Adds (delta 1) or removes (delta -1) one copy of a described card from the counters.
static func _apply(state: Dictionary, description: Dictionary, delta: int) -> void:
	state["total"] += delta
	for metric in description["metrics"]:
		state["counts"][metric] = int(state["counts"].get(metric, 0)) + delta
	state["buckets"][description["bucket"]] += delta
	for tribe_id in description["tribes"]:
		state["tribes"][tribe_id] = int(state["tribes"].get(tribe_id, 0)) + delta

## Whether one more copy of the card keeps the deck legal: copy limit, champion cap and deck domains.
## The last two are measured by DeckDB.stats() on the deck as it would be after the addition, so the
## fill obeys exactly the rules the deck builder shows.
static func _can_add(description: Dictionary, cards: Dictionary, leader_id: String, incarnation_id: String) -> bool:
	var card_id := String(description["id"])
	if int(cards.get(card_id, 0)) >= int(description["limit"]):
		return false
	if not description["is_champion"] and not description["is_outside"]:
		return true # not a champion and not from outside the Leader's domains: no other rule can be broken
	var deck_after := cards.duplicate()
	deck_after[card_id] = int(cards.get(card_id, 0)) + 1
	var totals := DeckDB.stats(leader_id, deck_after, incarnation_id)
	# the fill never starts a 3-domain deck on its own: that mode forbids the neutral cards it may add later
	var domains_allowed: bool = totals["domain_mode"] == "two" or (totals["domain_mode"] == "three" and not description["is_outside"])
	return int(totals["elite"]) <= DeckDB.MAX_ELITE_CARDS and domains_allowed

## How far the deck is from its goals: lower is better, 0 means every goal and the whole ideal curve is met.
static func _deficit(state: Dictionary, goals: Array[Dictionary], ideal_curve: Array[int]) -> float:
	var deficit := 0.0
	for goal in goals:
		var have := int(state["counts"].get(String(goal["metric"]), 0))
		deficit += GRAVE_WEIGHT * maxi(0, int(goal["grave"]) - have)
		deficit += MEDIUM_WEIGHT * maxi(0, int(goal["goal"]) - have)
	for bucket in CURVE_BUCKETS:
		var difference: int = int(state["buckets"][bucket]) - ideal_curve[bucket]
		if difference < 0:
			deficit += CURVE_SHORTAGE_WEIGHT * -difference
		else:
			deficit += CURVE_EXCESS_WEIGHT * difference
	return deficit

## The tribe with the most cards in the deck so far ("" when no card has a tribe).
static func _leading_tribe(state: Dictionary) -> String:
	var leading := ""
	var leading_copies := 0
	for tribe_id in state["tribes"]:
		var copies := int(state["tribes"][tribe_id])
		if copies > leading_copies or (copies == leading_copies and copies > 0 and String(tribe_id) < leading):
			leading = String(tribe_id)
			leading_copies = copies
	return leading

## For the tribal combo: the tribe that can reach the most cards in this deck, counting the copies
## already in it and those still available to add from the Leader's own domains (or neutral).
static func _choose_pursued_tribe(leader_id: String, incarnation_id: String, cards: Dictionary, candidates: Array) -> String:
	var reachable: Dictionary = {}
	for candidate in candidates:
		var candidate_id := String(candidate)
		if candidate_id == incarnation_id or DeckDB.is_outside_leader_domain(leader_id, candidate_id):
			continue
		var room := DeckDB.copy_limit(candidate_id)
		for tribe_id in CardDB.card(candidate_id).get("tribe", []):
			reachable[String(tribe_id)] = int(reachable.get(String(tribe_id), 0)) + room
	var best_tribe := ""
	var best_reach := 0
	var tribe_ids: Array = reachable.keys()
	tribe_ids.sort() # same answer every time when two tribes are equal
	for tribe_id in tribe_ids:
		if int(reachable[tribe_id]) > best_reach:
			best_reach = int(reachable[tribe_id])
			best_tribe = String(tribe_id)
	return best_tribe
