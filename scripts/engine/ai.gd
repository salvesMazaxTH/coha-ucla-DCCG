class_name SimpleAI
extends RefCounted
## Greedy AI: spends Momentum on the most expensive plays, attacks with
## units that survive or trade, blocks to protect the Leader when needed.

## Performs one action for player p. Returns its events, or [] when the AI
## has nothing more to do (the caller should then stop asking).
static func step(g: GameState, p: int) -> Array:
	match g.phase:
		"mulligan":
			var cards_to_return: Array = []
			for card: Card in g.players[p]["hand"]:
				if _base_cost(card) >= 5 and cards_to_return.size() < GameState.MULLIGAN_MAX:
					cards_to_return.append(card.uid)
			return g.mulligan(p, cards_to_return)
		"blocks":
			return g.declare_blocks(p, _choose_blocks(g, p))
		"search":
			return g.choose_search(p, _choose_search(g))
		"enter_target":
			var card_data := CardDB.card(g.pending_enter["card_id"])
			var target := _pick_target(g, p, g.pending_enter["spec"], card_data, int(g.pending_enter["uid"]))
			var events := g.choose_enter_target(p, target)
			return events if not events.is_empty() else g.choose_enter_target(p, 0)
		"discard":
			var hand := _hand_most_expensive_first(g, p)
			var uids_to_discard: Array = []
			for i in hand.size() - GameState.HAND_LIMIT:
				uids_to_discard.append(hand[i].uid)
			return g.discard(p, uids_to_discard)
		"combat":
			var events := _try_play(g, p)
			return events if not events.is_empty() else g.pass_priority(p)
		"main":
			if not g.stack.is_empty() or p != g.active:
				var response := _try_play(g, p)
				return response if not response.is_empty() else g.pass_priority(p)
			var events := _try_play(g, p)
			if not events.is_empty():
				return events
			if not g.players[p]["attacked"]:
				events = _try_attack(g, p)
				if not events.is_empty():
					return events
			return g.end_turn(p)
	return []

## Printed cost of a card (ignores discounts).
static func _base_cost(card: Card) -> int:
	return int(CardDB.card(card.card_id)["cost"])

## Copy of the hand sorted from the most to the least expensive card.
static func _hand_most_expensive_first(g: GameState, p: int) -> Array:
	var hand: Array = g.players[p]["hand"].duplicate()
	hand.sort_custom(func(a: Card, b: Card): return _base_cost(a) > _base_cost(b))
	return hand

static func _choose_search(g: GameState) -> int:
	var best_uid := 0
	var best_score := -999
	# search options are plain dicts {uid, card_id}
	for option in g.pending_search.get("cards", []):
		var card_data := CardDB.card(option["card_id"])
		var score := int(card_data.get("cost", 0)) * 10
		if card_data.get("type", "") == "unit":
			score += 2
		if score > best_score:
			best_score = score
			best_uid = int(option["uid"])
	return best_uid

static func _try_play(g: GameState, p: int) -> Array:
	if g.can_cast_legendary(p):
		var events := g.cast_legendary(p)
		if not events.is_empty():
			return events
	for card: Card in _hand_most_expensive_first(g, p):
		if not g.can_play(p, card.uid):
			continue
		var card_data := CardDB.card(card.card_id)
		var is_unit: bool = card_data["type"] == "unit"
		if not is_unit and g.is_dud(p, card_data):
			continue
		var spec := g.card_spec(card_data)
		var target := _pick_sacrifice(g, p) if card_data.get("cost_sacrifice", false) else _pick_target(g, p, spec, card_data, 0, not is_unit)
		if spec != "" and target == 0 and not is_unit:
			continue
		var spec2 := g.second_spec(card_data)
		var second_target := 0
		if spec2 != "":
			var foe_leader: int = GameState.LEADER_UID[g.opponent(p)]
			second_target = foe_leader if g.valid_targets(p, spec2).has(foe_leader) else _pick_target(g, p, spec2, card_data, 0, true)
			if second_target == 0:
				continue
		var events := g.play_card(p, card.uid, target, second_target)
		if not events.is_empty():
			return events
	for unit: Card in g.players[p]["board"]:
		# untargeted Ao Ativar, before attacking (e.g. Yuki's temporary attack)
		var activated_effects: Array = CardDB.card(unit.card_id).get("activated", {}).get("effects", [])
		if g.can_activate(p, unit.uid) and g.target_spec(activated_effects) == "" and g.can_attack(unit):
			return g.activate(p, unit.uid)
	for unit: Card in g.players[p]["board"]:
		if g.can_transform(p, unit.uid):
			return g.transform(p, unit.uid)
	if g.can_use_ability(p):
		var ability: Dictionary = CardDB.leader(g.players[p]["leader_id"])["ability"]
		var ability_spec := g.target_spec(ability["effects"])
		var target := _pick_target(g, p, ability_spec, ability, 0, true)
		if ability_spec == "" or target != 0:
			return g.use_ability(p, target)
	return []

## Additional sacrifice cost: give up the weakest ally.
static func _pick_sacrifice(g: GameState, p: int) -> int:
	var weakest_uid := 0
	var weakest_score := 999
	for unit: Card in g.players[p]["board"]:
		var score: int = unit.atk_total() + unit.hp_left()
		if score < weakest_score:
			weakest_score = score
			weakest_uid = unit.uid
	return weakest_uid

## Hostile effects pick the biggest enemy (or the Leader); friendly ones the biggest ally.
## `strict` (spells and abilities): damage to a unit only counts if it kills, because damage on units
## wears off at end of turn; otherwise only the Leader (permanent damage) is a worthwhile target.
## `source` is the card data (or leader ability) whose effects need a target.
static func _pick_target(g: GameState, p: int, spec: String, source, self_uid := 0, strict := false) -> int:
	if spec == "":
		return 0
	if spec == "enemy_stack": # counter the priciest enemy spell/ability in reach
		var best_stack_id := 0
		var best_cost := -1
		for stack_id in g.card_targets(p, source):
			for item in g.stack:
				if item["sid"] == stack_id and g.stack_cost(item) > best_cost:
					best_cost = g.stack_cost(item)
					best_stack_id = stack_id
		return best_stack_id
	var options := g.valid_targets(p, spec, self_uid)
	if options.is_empty():
		return 0
	var effects: Array = source.get("effects", []) if source is Dictionary else []
	var friendly := spec in ["ally_unit", "other_ally_unit"]
	if not friendly:
		for effect in effects:
			if effect.get("action") == "buff":
				friendly = true
	var best_uid := 0
	var best_score := -999
	for uid in options:
		var score := 0
		if uid < 0: # a Leader
			if friendly or uid != GameState.LEADER_UID[g.opponent(p)]:
				continue
			score = 3
			# go face when the damage finishes the enemy Leader
			if not friendly:
				for effect in effects:
					if effect.get("action") == "damage" and int(effect["amount"]) >= g.players[g.opponent(p)]["leader_hp"]:
						score = 999
		else:
			var unit := g.find_unit(uid)
			var is_mine: bool = unit.owner == p
			if is_mine != friendly:
				continue
			score = unit.atk_total() + unit.hp_left()
			# prefer damage that actually kills
			if not friendly:
				var hits := false
				var kills := false
				for effect in effects:
					if effect.get("action") == "damage":
						hits = true
						if int(effect["amount"]) >= unit.hp_left() and not unit.shield:
							kills = true
				if kills:
					score += 10
				elif hits and strict:
					continue # would heal off at end of turn
				if unit.spell_shield:
					score -= 20 # wasted on Escudo de Feitiço
		if score > best_score:
			best_score = score
			best_uid = uid
	return best_uid

static func _try_attack(g: GameState, p: int) -> Array:
	var enemy := g.opponent(p)
	var enemy_board: Array = g.players[enemy]["board"]
	var ready: Array = []
	for unit: Card in g.players[p]["board"]:
		if g.can_attack(unit):
			ready.append(unit)
	if ready.is_empty():
		return []
	var all_in := _lethal_push(g, p, ready)
	var attacks := {}
	var already_provoked: Array = []
	for attacker: Card in ready:
		var provoked_uid := 0
		if attacker.has_kw("provocacao"):
			for enemy_unit: Card in enemy_board:
				if not already_provoked.has(enemy_unit.uid) and not enemy_unit.is_frozen() \
						and enemy_unit.atk_total() < attacker.hp_left() \
						and (attacker.atk_total() >= enemy_unit.hp_left() or enemy_unit.shield):
					provoked_uid = enemy_unit.uid
					already_provoked.append(provoked_uid)
					break
		var safe := true
		for enemy_unit: Card in enemy_board:
			if g.can_block(enemy_unit, attacker) and enemy_unit.atk_total() >= attacker.hp_left() and attacker.atk_total() < enemy_unit.hp_left():
				safe = false
		# aggression: attacking costs no defense, so push when the enemy is low
		# or we outnumber their blockers
		var pressure: bool = g.players[enemy]["leader_hp"] <= 10 or g.players[p]["board"].size() > enemy_board.size() + 1
		if all_in or safe or provoked_uid != 0 or enemy_board.size() == 0 or pressure:
			attacks[attacker.uid] = provoked_uid
	if attacks.is_empty():
		return []
	return g.declare_attack(p, attacks)

## True when sending everything kills the Leader even if the enemy blocks our biggest attackers.
static func _lethal_push(g: GameState, p: int, ready: Array) -> bool:
	var blocker_count := 0
	for enemy_unit: Card in g.players[g.opponent(p)]["board"]:
		if not enemy_unit.is_frozen():
			blocker_count += 1
	var attack_values: Array = []
	for attacker: Card in ready:
		attack_values.append(attacker.atk_total())
	attack_values.sort()
	attack_values.reverse()
	var unblocked_damage := 0
	for i in range(blocker_count, attack_values.size()):
		unblocked_damage += attack_values[i]
	return unblocked_damage >= g.players[g.opponent(p)]["leader_hp"]

static func _choose_blocks(g: GameState, p: int) -> Dictionary:
	var blocks := {}
	var used: Array = [] # uids that can't block anymore (provoked or already blocking)
	for provoked_uid in g.attackers.values():
		used.append(provoked_uid)
	var incoming := 0
	var order: Array = [] # attackers going for the Leader, biggest first
	for attacker_uid in g.attackers:
		if g.attackers[attacker_uid] == 0:
			incoming += g.find_unit(attacker_uid).atk_total()
			order.append(attacker_uid)
	order.sort_custom(func(x, y): return g.find_unit(x).atk_total() > g.find_unit(y).atk_total())
	var desperate: bool = incoming >= g.players[p]["leader_hp"] - 3
	for attacker_uid in order:
		var attacker := g.find_unit(attacker_uid)
		var best_uid := 0
		var chump_uid := 0 # the cheapest unit to throw in front if we must
		var chump_score := 999
		for blocker: Card in g.players[p]["board"]:
			if used.has(blocker.uid) or not g.can_block(blocker, attacker):
				continue
			var kills: bool = blocker.atk_total() >= attacker.hp_left() and not attacker.shield
			var survives: bool = attacker.atk_total() < blocker.hp_left() or blocker.shield
			if survives or (kills and attacker.atk_total() >= blocker.atk_total()):
				best_uid = blocker.uid
				break
			var worth: int = blocker.atk_total() + blocker.hp_left()
			if worth < chump_score:
				chump_score = worth
				chump_uid = blocker.uid
		if best_uid == 0 and desperate:
			best_uid = chump_uid # sacrifice the cheapest body to save life
		if best_uid != 0:
			blocks[attacker_uid] = best_uid
			used.append(best_uid)
			if g.attackers[attacker_uid] == 0:
				incoming -= attacker.atk_total()
				desperate = incoming >= g.players[p]["leader_hp"] - 3
	return blocks
