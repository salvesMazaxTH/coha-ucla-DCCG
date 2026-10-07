class_name SimpleAI
extends RefCounted
## Greedy AI: spends Momentum on the most expensive plays, attacks with
## creatures that survive or trade, blocks to protect the Leader when needed.

## Performs one action for player p. Returns its events, or [] when the AI
## has nothing more to do (the caller should then stop asking).
static func step(g: GameState, p: int) -> Array:
	match g.phase:
		"mulligan":
			var back: Array = []
			for c in g.players[p]["hand"]:
				if int(CardDB.card(c["card_id"])["cost"]) >= 5 and back.size() < GameState.MULLIGAN_MAX:
					back.append(c["uid"])
			return g.mulligan(p, back)
		"blocks":
			return g.declare_blocks(p, _choose_blocks(g, p))
		"search":
			return g.choose_search(p, _choose_search(g))
		"discard":
			var hand: Array = g.players[p]["hand"].duplicate()
			hand.sort_custom(func(a, b): return int(CardDB.card(a["card_id"])["cost"]) > int(CardDB.card(b["card_id"])["cost"]))
			var uids: Array = []
			for i in hand.size() - GameState.HAND_LIMIT:
				uids.append(hand[i]["uid"])
			return g.discard(p, uids)
		"main":
			var ev := _try_play(g, p)
			if not ev.is_empty():
				return ev
			if not g.players[p]["attacked"]:
				ev = _try_attack(g, p)
				if not ev.is_empty():
					return ev
			return g.end_turn(p)
	return []

static func _choose_search(g: GameState) -> int:
	var best_uid := 0
	var best_score := -999
	for c in g.pending_search.get("cards", []):
		var cd := CardDB.card(c["card_id"])
		var score := int(cd.get("cost", 0)) * 10
		if cd.get("type", "") == "creature":
			score += 2
		if score > best_score:
			best_score = score
			best_uid = int(c["uid"])
	return best_uid

static func _try_play(g: GameState, p: int) -> Array:
	if g.can_cast_legendary(p):
		var ev := g.cast_legendary(p, _pick_target(g, p, g.target_spec(CardDB.card(g.players[p]["legendary"]["card_id"])["effects"]), 0))
		if not ev.is_empty():
			return ev
	var hand: Array = g.players[p]["hand"].duplicate()
	hand.sort_custom(func(a, b): return int(CardDB.card(a["card_id"])["cost"]) > int(CardDB.card(b["card_id"])["cost"]))
	for c in hand:
		if not g.can_play(p, c["uid"]):
			continue
		var cd := CardDB.card(c["card_id"])
		var spec := g.target_spec(cd["effects"])
		var t := _pick_target(g, p, spec, cd)
		if spec != "" and t == 0 and cd["type"] != "creature":
			continue
		var ev := g.play_card(p, c["uid"], t)
		if not ev.is_empty():
			return ev
	if g.can_use_ability(p):
		var ab: Dictionary = CardDB.leader(g.players[p]["leader_id"])["ability"]
		var t := _pick_target(g, p, g.target_spec(ab["effects"]), ab)
		return g.use_ability(p, t)
	return []

## Hostile effects pick the biggest enemy (or the Leader); friendly ones the biggest ally.
static func _pick_target(g: GameState, p: int, spec: String, src) -> int:
	if spec == "":
		return 0
	var opts := g.valid_targets(p, spec)
	if opts.is_empty():
		return 0
	var friendly := spec in ["ally_creature", "other_ally_creature"]
	if not friendly and src is Dictionary and src.has("effects"):
		for e in src["effects"]:
			if e.get("action") == "buff":
				friendly = true
	var best := 0
	var best_score := -999
	for uid in opts:
		var score := 0
		if uid < 0:
			if friendly or uid != GameState.LEADER_UID[g.opponent(p)]:
				continue
			score = 3
			# go face when the damage finishes the enemy Leader
			if not friendly and src is Dictionary:
				for e in src.get("effects", []):
					if e.get("action") == "damage" and int(e["amount"]) >= g.players[g.opponent(p)]["leader_hp"]:
						score = 999
		else:
			var c := g.find_creature(uid)
			var mine: bool = c["owner"] == p
			if mine != friendly:
				continue
			score = g.atk_of(c) + g.hp_left(c)
			# prefer damage that actually kills
			if not friendly and src is Dictionary:
				for e in src.get("effects", []):
					if e.get("action") == "damage" and int(e["amount"]) >= g.hp_left(c) and not c["shield"]:
						score += 10
		if score > best_score:
			best_score = score
			best = uid
	return best

static func _try_attack(g: GameState, p: int) -> Array:
	var enemy_board: Array = g.players[g.opponent(p)]["board"]
	var attacks := {}
	var used_prov: Array = []
	for c in g.players[p]["board"]:
		if not g.can_attack(c):
			continue
		var prov := 0
		if g.has_kw(c, "provocar"):
			for e in enemy_board:
				if not used_prov.has(e["uid"]) and g.atk_of(e) < g.hp_left(c) and (g.atk_of(c) >= g.hp_left(e) or e["shield"]):
					prov = e["uid"]
					used_prov.append(prov)
					break
		var safe := true
		for e in enemy_board:
			if g.can_block(e, c) and g.atk_of(e) >= g.hp_left(c) and g.atk_of(c) < g.hp_left(e):
				safe = false
		# aggression: attacking costs no defense, so push when the enemy is low
		# or we outnumber their blockers
		var pressure: bool = g.players[g.opponent(p)]["leader_hp"] <= 10 or g.players[p]["board"].size() > enemy_board.size() + 1
		if safe or prov != 0 or enemy_board.size() == 0 or pressure:
			attacks[c["uid"]] = prov
	if attacks.is_empty():
		return []
	return g.declare_attack(p, attacks)

static func _choose_blocks(g: GameState, p: int) -> Dictionary:
	var blocks := {}
	var used: Array = []
	for a in g.attackers.values():
		used.append(a)
	var incoming := 0
	for a in g.attackers:
		if g.attackers[a] == 0:
			incoming += g.atk_of(g.find_creature(a))
	var desperate: bool = incoming >= g.players[p]["leader_hp"] - 3
	for a in g.attackers:
		if g.attackers[a] != 0:
			continue
		var att := g.find_creature(a)
		var best := 0
		for b in g.players[p]["board"]:
			if used.has(b["uid"]) or not g.can_block(b, att):
				continue
			var kills: bool = g.atk_of(b) >= g.hp_left(att) and not att["shield"]
			var survives: bool = g.atk_of(att) < g.hp_left(b) or b["shield"]
			if survives or (kills and g.atk_of(att) >= g.atk_of(b)) or desperate:
				best = b["uid"]
				break
		if best != 0:
			blocks[a] = best
			used.append(best)
	return blocks
