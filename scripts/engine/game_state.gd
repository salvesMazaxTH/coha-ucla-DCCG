class_name GameState
extends RefCounted
## Pure, UI-free rules engine. Every public action validates input, mutates
## state and returns an Array of event Dictionaries the UI can animate.
## Invalid actions return [] and leave state untouched.

const START_HAND := 6
const MULLIGAN_MAX := 3
const HAND_LIMIT := 10
const BOARD_LIMIT := 8
const MOMENTUM_CAP := 10
const COMMANDER_TAX := 2

## Leaders are addressed with negative uids so targets are a single int.
const LEADER_UID := [-1, -2]

var players: Array = []
var active := 0
var turn := 0
var phase := "mulligan"
var winner := -1 ## -1 none, 0/1 player, 2 draw
## Pending combat: attacker uid -> provoked enemy uid (or 0)
var attackers: Dictionary = {}
## Pending deterministic deck search. The matching cards are public until chosen.
var pending_search: Dictionary = {}
var rng := RandomNumberGenerator.new()
var _next_uid := 1
var _events: Array = []
var _trigger_depth := 0
var _dying: Dictionary = {} ## creature whose Ao Morrer is resolving (for summon "self")

func _init(deck_a: String, deck_b: String, seed_value: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	for i in 2:
		players.append(_make_player(i, [deck_a, deck_b][i]))
	for i in 2:
		_draw(i, START_HAND + i) # second player gets one extra card
	_events.clear()

func _make_player(i: int, deck_id: String) -> Dictionary:
	var d := CardDB.deck(deck_id)
	var ld := CardDB.leader(d["leader"])
	var deck: Array = []
	for id in d["cards"]:
		if id == ld["legendary"]:
			continue
		for n in int(d["cards"][id]):
			deck.append({"uid": _uid(), "card_id": id})
	_shuffle(deck)
	return {
		"index": i, "deck_id": deck_id, "leader_id": d["leader"],
		"leader_hp": int(ld["hp"]), "leader_max": int(ld["hp"]),
		"momentum": 0, "max_momentum": 0,
		"deck": deck, "hand": [], "board": [], "graveyard": [],
		"legendary": {"card_id": ld["legendary"], "in_zone": true, "casts": 0},
		"ability_used": false, "attacked": false, "fatigue": 0, "mulligan_done": false,
	}

func _uid() -> int:
	_next_uid += 1
	return _next_uid

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

func _emit(e: Dictionary) -> void:
	_events.append(e)

func _flush() -> Array:
	var out := _events
	_events = []
	return out

# ---------------------------------------------------------------- queries

func opponent(p: int) -> int:
	return 1 - p

## The player whose input the game is waiting for.
func decider() -> int:
	match phase:
		"mulligan":
			return 0 if not players[0]["mulligan_done"] else 1
		"blocks":
			return opponent(active)
		"search":
			return int(pending_search.get("player", active))
	return active

func find_creature(uid: int) -> Dictionary:
	for p in players:
		for c in p["board"]:
			if c["uid"] == uid:
				return c
	return {}

func card_of(c: Dictionary) -> Dictionary:
	return CardDB.card_for(c["card_id"], c)

func has_kw(c: Dictionary, kw: String) -> bool:
	if kw == "escudo":
		return c["shield"]
	return c["keywords"].has(kw)

func atk_of(c: Dictionary) -> int:
	return max(0, c["atk"] + c["temp_atk"])

func hp_left(c: Dictionary) -> int:
	return c["hp"] - c["damage"]

func legendary_cost(p: int) -> int:
	var l: Dictionary = players[p]["legendary"]
	return int(CardDB.card(l["card_id"])["cost"]) + COMMANDER_TAX * int(l["casts"])

func can_attack(c: Dictionary) -> bool:
	return not c["exhausted"] and (not c["sick"] or has_kw(c, "impeto")) and atk_of(c) > 0

func can_block(blocker: Dictionary, attacker: Dictionary) -> bool:
	if has_kw(attacker, "voo") and not (has_kw(blocker, "voo") or has_kw(blocker, "longo_alcance")):
		return false
	if has_kw(attacker, "furtivo") and not (has_kw(blocker, "furtivo") or has_kw(blocker, "vigia")):
		return false
	return true

## Effect spec of a card/ability that needs a chosen target, or "" if none.
func target_spec(effects: Array) -> String:
	for e in effects:
		if e.get("target", "") in ["enemy_creature", "ally_creature", "other_ally_creature", "any_creature", "any"]:
			return e["target"]
	return ""

func valid_targets(p: int, spec: String, self_uid: int = 0) -> Array:
	var out: Array = []
	var mine: Array = players[p]["board"]
	var theirs: Array = players[opponent(p)]["board"]
	match spec:
		"enemy_creature":
			for c in theirs: out.append(c["uid"])
		"ally_creature":
			for c in mine: out.append(c["uid"])
		"other_ally_creature":
			for c in mine:
				if c["uid"] != self_uid: out.append(c["uid"])
		"any_creature":
			for c in mine + theirs: out.append(c["uid"])
		"any":
			for c in mine + theirs: out.append(c["uid"])
			out.append(LEADER_UID[opponent(p)])
	return out

func can_play(p: int, hand_uid: int) -> bool:
	if phase != "main" or p != active:
		return false
	var inst := _hand_card(p, hand_uid)
	if inst.is_empty():
		return false
	var cd := CardDB.card(inst["card_id"])
	if int(cd["cost"]) > players[p]["momentum"]:
		return false
	if cd["type"] == "creature":
		return players[p]["board"].size() < BOARD_LIMIT
	var spec := target_spec(cd["effects"])
	return spec == "" or not valid_targets(p, spec).is_empty()

func can_cast_legendary(p: int) -> bool:
	return phase == "main" and p == active and players[p]["legendary"]["in_zone"] \
		and legendary_cost(p) <= players[p]["momentum"] and players[p]["board"].size() < BOARD_LIMIT

func can_use_ability(p: int) -> bool:
	var ab: Dictionary = CardDB.leader(players[p]["leader_id"])["ability"]
	if phase != "main" or p != active or int(ab["cost"]) > players[p]["momentum"]:
		return false
	if ab.get("once_per_turn", false) and players[p]["ability_used"]:
		return false
	var spec := target_spec(ab["effects"])
	return spec == "" or not valid_targets(p, spec).is_empty()

func _hand_card(p: int, uid: int) -> Dictionary:
	for c in players[p]["hand"]:
		if c["uid"] == uid:
			return c
	return {}

# ---------------------------------------------------------------- actions

## Put back up to MULLIGAN_MAX cards and redraw that many.
func mulligan(p: int, hand_uids: Array) -> Array:
	if phase != "mulligan" or p != decider() or hand_uids.size() > MULLIGAN_MAX:
		return []
	var pl: Dictionary = players[p]
	var back: Array = []
	for uid in hand_uids:
		var c := _hand_card(p, uid)
		if c.is_empty():
			return []
		back.append(c)
	for c in back:
		pl["hand"].erase(c)
		pl["deck"].append(c)
	_shuffle(pl["deck"])
	_draw(p, back.size())
	pl["mulligan_done"] = true
	_emit({"type": "mulligan", "player": p, "count": back.size()})
	if players[0]["mulligan_done"] and players[1]["mulligan_done"]:
		_start_turn(0, false)
	return _flush()

func play_card(p: int, hand_uid: int, target: int = 0) -> Array:
	if not can_play(p, hand_uid):
		return []
	var inst := _hand_card(p, hand_uid)
	var cd := CardDB.card(inst["card_id"])
	var spec := target_spec(cd["effects"])
	if cd["type"] != "creature" and spec != "" and not valid_targets(p, spec).has(target):
		return []
	var pl: Dictionary = players[p]
	pl["momentum"] -= int(cd["cost"])
	pl["hand"].erase(inst)
	_emit({"type": "play", "player": p, "uid": hand_uid, "card_id": inst["card_id"]})
	if cd["type"] == "creature":
		_summon(p, inst["card_id"], hand_uid, false, target)
	else:
		_run_effects(p, cd["effects"], "on_play", target, 0)
		pl["graveyard"].append(inst)
	_check_state()
	return _flush()

func cast_legendary(p: int, target: int = 0) -> Array:
	if not can_cast_legendary(p):
		return []
	var pl: Dictionary = players[p]
	pl["momentum"] -= legendary_cost(p)
	pl["legendary"]["in_zone"] = false
	pl["legendary"]["casts"] += 1
	var uid := _uid()
	_emit({"type": "play", "player": p, "uid": uid, "card_id": pl["legendary"]["card_id"], "legendary": true})
	_summon(p, pl["legendary"]["card_id"], uid, true, target)
	_check_state()
	return _flush()

func use_ability(p: int, target: int = 0) -> Array:
	if not can_use_ability(p):
		return []
	var ab: Dictionary = CardDB.leader(players[p]["leader_id"])["ability"]
	var spec := target_spec(ab["effects"])
	if spec != "" and not valid_targets(p, spec).has(target):
		return []
	players[p]["momentum"] -= int(ab["cost"])
	players[p]["ability_used"] = true
	_emit({"type": "ability", "player": p})
	_run_effects(p, ab["effects"], "", target, 0)
	_check_state()
	return _flush()

## attacks: Dictionary attacker_uid -> provoked enemy uid (0 when none).
func declare_attack(p: int, attacks: Dictionary) -> Array:
	if phase != "main" or p != active or players[p]["attacked"] or attacks.is_empty():
		return []
	var enemy_board: Array = players[opponent(p)]["board"]
	var provoked_used: Array = []
	for uid in attacks:
		var c := find_creature(uid)
		if c.is_empty() or c["owner"] != p or not can_attack(c):
			return []
		var prov: int = attacks[uid]
		if prov != 0:
			var t := find_creature(prov)
			if not has_kw(c, "provocacao") or t.is_empty() or t["owner"] == p or provoked_used.has(prov):
				return []
			provoked_used.append(prov)
	attackers = attacks.duplicate()
	players[p]["attacked"] = true
	for uid in attacks:
		find_creature(uid)["exhausted"] = true
	_emit({"type": "attack", "player": p, "attackers": attacks.keys()})
	for uid in attacks:
		_fire(find_creature(uid), "on_attack")
	_check_state()
	if phase == "over":
		return _flush()
	if enemy_board.is_empty():
		return _resolve_combat({})
	phase = "blocks"
	return _flush()

## blocks: Dictionary attacker_uid -> blocker_uid. One blocker per attacker,
## one attacker per blocker. Provoked creatures are forced onto their provoker.
func declare_blocks(p: int, blocks: Dictionary) -> Array:
	if phase != "blocks" or p != decider():
		return []
	var final := {}
	for a in attackers:
		if attackers[a] != 0 and not find_creature(attackers[a]).is_empty():
			final[a] = attackers[a]
	var used: Array = final.values()
	for a in blocks:
		if final.has(a):
			continue
		var b: int = blocks[a]
		var att := find_creature(a)
		var blk := find_creature(b)
		if not attackers.has(a) or blk.is_empty() or blk["owner"] != p or used.has(b) or not can_block(blk, att):
			return []
		final[a] = b
		used.append(b)
	return _resolve_combat(final)

func end_turn(p: int) -> Array:
	if phase != "main" or p != active:
		return []
	if players[p]["hand"].size() > HAND_LIMIT:
		phase = "discard"
		_emit({"type": "discard_required", "player": p, "count": players[p]["hand"].size() - HAND_LIMIT})
		return _flush()
	_finish_turn()
	return _flush()

func discard(p: int, hand_uids: Array) -> Array:
	var need: int = players[p]["hand"].size() - HAND_LIMIT
	if phase != "discard" or p != active or hand_uids.size() != need:
		return []
	for uid in hand_uids:
		if _hand_card(p, uid).is_empty():
			return []
	for uid in hand_uids:
		var c := _hand_card(p, uid)
		players[p]["hand"].erase(c)
		players[p]["graveyard"].append(c)
		_emit({"type": "discard", "player": p, "uid": uid})
	phase = "main"
	_finish_turn()
	return _flush()

## Choose one of the public cards revealed by a deterministic deck search.
func choose_search(p: int, card_uid: int) -> Array:
	if phase != "search" or p != decider():
		return []
	var options: Array = pending_search.get("cards", [])
	var chosen: Dictionary = {}
	for c in options:
		if int(c["uid"]) == card_uid:
			chosen = c
			break
	if chosen.is_empty():
		return []
	var deck: Array = players[p]["deck"]
	var found := false
	for c in deck:
		if int(c["uid"]) == card_uid:
			deck.erase(c)
			found = true
			break
	if not found:
		return []
	players[p]["hand"].append(chosen)
	_shuffle(deck)
	pending_search.clear()
	phase = "main"
	_emit({"type": "search_take", "player": p, "uid": card_uid, "card_id": chosen["card_id"]})
	_emit({"type": "search_shuffle", "player": p})
	return _flush()

# ---------------------------------------------------------------- internals

func _summon(p: int, card_id: String, uid: int, legendary: bool, target: int, over: Dictionary = {}) -> void:
	var cd := CardDB.card_for(card_id, {"over": over})
	var kws: Array = cd.get("keywords", []).duplicate()
	var c := {
		"uid": uid, "card_id": card_id, "owner": p, "legendary": legendary,
		"atk": int(cd["atk"]), "hp": int(cd["hp"]), "damage": 0, "temp_atk": 0,
		"keywords": kws, "temp_keywords": [], "shield": kws.has("escudo"),
		"exhausted": false, "sick": true,
	}
	if not over.is_empty():
		c["over"] = over
	kws.erase("escudo")
	players[p]["board"].append(c)
	_emit({"type": "summon", "player": p, "uid": uid, "card_id": card_id})
	_run_effects(p, cd["effects"], "on_enter", target, uid)

## Fires a creature's own trigger. Depth-capped so on_damaged chains cannot loop forever.
func _fire(c: Dictionary, trigger: String, other_uid: int = 0) -> void:
	if c.is_empty() or _trigger_depth >= 4:
		return
	_trigger_depth += 1
	_run_effects(c["owner"], card_of(c)["effects"], trigger, 0, c["uid"], other_uid)
	_trigger_depth -= 1

## Gatilhos (cards.json "triggers"): on_play, on_enter, on_death, on_attack, on_block,
## on_blocked, on_damaged, on_hit_leader, on_turn_start, on_turn_end.
## other_uid is the opposing creature in combat triggers (blocker, attacker, damage source).
func _run_effects(p: int, effects: Array, trigger: String, chosen: int, self_uid: int, other_uid: int = 0) -> void:
	for e in effects:
		if trigger != "" and e.get("trigger", "") != trigger:
			continue
		var targets: Array = []
		match e.get("target", ""):
			"enemy_creature", "ally_creature", "other_ally_creature", "any_creature", "any":
				if valid_targets(p, e["target"], self_uid).has(chosen):
					targets = [chosen]
			"all_enemy_creatures":
				for c in players[opponent(p)]["board"]: targets.append(c["uid"])
			"enemy_leader":
				targets = [LEADER_UID[opponent(p)]]
			"own_leader":
				targets = [LEADER_UID[p]]
			"random_enemy_creature":
				var b: Array = players[opponent(p)]["board"]
				if not b.is_empty(): targets = [b[rng.randi_range(0, b.size() - 1)]["uid"]]
			"random_enemy_and_adjacent":
				var eb: Array = players[opponent(p)]["board"]
				if not eb.is_empty():
					var ci := rng.randi_range(0, eb.size() - 1)
					for j in range(maxi(ci - 1, 0), mini(ci + 1, eb.size() - 1) + 1): targets.append(eb[j]["uid"])
			"self":
				if not find_creature(self_uid).is_empty(): targets = [self_uid]
			"none":
				targets = [0]
			"opposed_creature":
				if not find_creature(other_uid).is_empty(): targets = [other_uid]
			"all_creatures":
				for side in [p, opponent(p)]:
					for c in players[side]["board"]: targets.append(c["uid"])
			"all_ally_creatures":
				for c in players[p]["board"]: targets.append(c["uid"])
			"random_ally_creature", "random_other_ally_creature":
				var pool: Array = []
				for c in players[p]["board"]:
					if e["target"] == "random_ally_creature" or c["uid"] != self_uid: pool.append(c["uid"])
				if not pool.is_empty(): targets = [pool[rng.randi_range(0, pool.size() - 1)]]
		for t in targets:
			_apply(p, e, t)
		if e.get("action", "") == "search_deck" and e.get("trigger", "") == trigger:
			_begin_search(p, e, self_uid)

func _begin_search(p: int, e: Dictionary, source_uid: int) -> void:
	if phase == "search":
		return
	var matches: Array = []
	var seen: Dictionary = {}
	for c in players[p]["deck"]:
		var cd := CardDB.card(c["card_id"])
		if e.get("essence", "") != "" and cd.get("essence", "") != e["essence"]:
			continue
		if e.has("max_cost") and int(cd.get("cost", 999)) > int(e["max_cost"]):
			continue
		if e.has("type") and cd.get("type", "") != e["type"]:
			continue
		if e.has("tags"):
			var card_tags: Array = cd.get("tags", [])
			var matches_tags := true
			for tag in e["tags"]:
				if not card_tags.has(tag):
					matches_tags = false
					break
			if not matches_tags:
				continue
		if seen.has(c["card_id"]):
			continue
		seen[c["card_id"]] = true
		matches.append({"uid": c["uid"], "card_id": c["card_id"]})
	if matches.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": matches}
	phase = "search"
	_emit({"type": "search_reveal", "player": p, "source_uid": source_uid, "cards": matches})

func _apply(p: int, e: Dictionary, t: int) -> void:
	match e["action"]:
		"damage":
			var amount := int(e["amount"])
			var red: Dictionary = e.get("ally_reduce", {})
			var victim := find_creature(t)
			if not red.is_empty() and not victim.is_empty() and victim["owner"] == p and card_of(victim).get("essence", "") == red["essence"]:
				amount = int(red["amount"])
			_deal_damage(t, amount, {})
		"heal_leader":
			_heal_leader(p, int(e["amount"]))
		"draw":
			_draw(p, int(e["amount"]))
		"search_deck":
			pass # Search effects are opened by _run_effects after their trigger resolves.
		"summon":
			_summon_effect(p, e)
		"buff":
			var c := find_creature(t)
			if c.is_empty():
				return
			if e.get("temp", false):
				c["temp_atk"] += int(e.get("atk", 0))
			else:
				c["atk"] += int(e.get("atk", 0))
				c["hp"] += int(e.get("hp", 0))
			for kw in e.get("keywords", []):
				if kw == "escudo":
					c["shield"] = true
				elif not c["keywords"].has(kw):
					c["keywords"].append(kw)
					if e.get("temp", false):
						c["temp_keywords"].append(kw)
			_emit({"type": "buff", "uid": t, "atk": e.get("atk", 0), "hp": e.get("hp", 0), "keywords": e.get("keywords", [])})

## Returns damage actually dealt. source is the dealing creature or {}.
func _deal_damage(t: int, amount: int, source: Dictionary) -> int:
	if amount <= 0:
		return 0
	var dealt := 0
	if t < 0:
		var tp := LEADER_UID.find(t)
		players[tp]["leader_hp"] -= amount
		dealt = amount
		_emit({"type": "damage", "uid": t, "amount": amount, "src": source.get("uid", 0)})
		if not source.is_empty():
			_fire(source, "on_hit_leader")
	else:
		var c := find_creature(t)
		if c.is_empty():
			return 0
		if c["shield"]:
			c["shield"] = false
			_emit({"type": "shield_break", "uid": t})
			return 0
		c["damage"] += amount
		dealt = amount
		_emit({"type": "damage", "uid": t, "amount": amount, "src": source.get("uid", 0)})
		_fire(c, "on_damaged", source.get("uid", 0))
	if not source.is_empty() and has_kw(source, "roubo_de_vida"):
		_heal_leader(source["owner"], dealt)
	return dealt

func _heal_leader(p: int, amount: int) -> void:
	var pl: Dictionary = players[p]
	var healed: int = min(amount, pl["leader_max"] - pl["leader_hp"])
	if healed > 0:
		pl["leader_hp"] += healed
		_emit({"type": "heal", "uid": LEADER_UID[p], "amount": healed})

func _draw(p: int, n: int) -> void:
	var pl: Dictionary = players[p]
	for i in n:
		if pl["deck"].is_empty():
			pl["fatigue"] += 1
			_emit({"type": "fatigue", "player": p, "amount": pl["fatigue"]})
			_deal_damage(LEADER_UID[p], pl["fatigue"], {})
			continue
		var c: Dictionary = pl["deck"].pop_back()
		pl["hand"].append(c)
		_emit({"type": "draw", "player": p, "uid": c["uid"]})

func _resolve_combat(blocks: Dictionary) -> Array:
	var defender := opponent(active)
	_emit({"type": "blocks", "blocks": blocks})
	for a in blocks:
		_fire(find_creature(blocks[a]), "on_block", a)
		_fire(find_creature(a), "on_blocked", blocks[a])
	_check_state()
	if phase == "over":
		attackers.clear()
		return _flush()
	var pairs: Array = []
	for a in attackers:
		pairs.append([a, blocks.get(a, 0)])
	for first_strike in [true, false]:
		for pair in pairs:
			var att := find_creature(pair[0])
			var blk := find_creature(pair[1]) if pair[1] != 0 else {}
			if not att.is_empty() and has_kw(att, "golpe_rapido") == first_strike:
				if pair[1] == 0:
					_deal_damage(LEADER_UID[defender], atk_of(att), att)
				elif not blk.is_empty():
					var excess := atk_of(att) - hp_left(blk)
					_deal_damage(blk["uid"], atk_of(att), att)
					if has_kw(att, "sobrepujanca") and excess > 0:
						_deal_damage(LEADER_UID[defender], excess, att)
				elif has_kw(att, "sobrepujanca"):
					_deal_damage(LEADER_UID[defender], atk_of(att), att) # blocker already dead
			if not blk.is_empty() and has_kw(blk, "golpe_rapido") == first_strike and not att.is_empty():
				_deal_damage(att["uid"], atk_of(blk), blk)
		_check_state()
		if phase == "over":
			break
	attackers.clear()
	if phase != "over":
		phase = "main"
	return _flush()

## Moves dead creatures out, fires Ao Morrer, checks leaders. Loops until stable.
func _check_state() -> void:
	var changed := true
	while changed:
		changed = false
		for p in 2:
			for c in players[p]["board"].duplicate():
				if hp_left(c) <= 0:
					players[p]["board"].erase(c)
					changed = true
					_emit({"type": "death", "uid": c["uid"], "player": p})
					if c["legendary"]:
						players[p]["legendary"]["in_zone"] = true
					else:
						players[p]["graveyard"].append({"uid": c["uid"], "card_id": c["card_id"]})
					_dying = c
					_run_effects(p, card_of(c)["effects"], "on_death", 0, c["uid"])
					_dying = {}
	var dead := [players[0]["leader_hp"] <= 0, players[1]["leader_hp"] <= 0]
	if dead[0] or dead[1]:
		winner = 2 if dead[0] and dead[1] else (1 if dead[0] else 0)
		phase = "over"
		_emit({"type": "game_over", "winner": winner})

func _finish_turn() -> void:
	for c in players[active]["board"].duplicate():
		_fire(c, "on_turn_end")
	_check_state()
	if phase == "over":
		return
	for p in players:
		for c in p["board"]:
			c["damage"] = 0
			c["temp_atk"] = 0
			for kw in c["temp_keywords"]:
				c["keywords"].erase(kw)
			c["temp_keywords"].clear()
	_emit({"type": "end_turn", "player": active})
	_start_turn(opponent(active), true)

func _start_turn(p: int, draw: bool) -> void:
	active = p
	turn += 1
	phase = "main"
	var pl: Dictionary = players[p]
	pl["max_momentum"] = min(MOMENTUM_CAP, pl["max_momentum"] + 1)
	pl["momentum"] = pl["max_momentum"]
	pl["ability_used"] = false
	pl["attacked"] = false
	for c in pl["board"]:
		c["exhausted"] = false
		c["sick"] = false
	_emit({"type": "start_turn", "player": p, "turn": turn})
	for c in pl["board"].duplicate():
		_fire(c, "on_turn_start")
	if draw:
		_draw(p, 1)
	_check_state()

## Generic summon: {"action":"summon","target":"none","card":<id|"self">,"overrides":{atk,hp,keywords,effects,text,...}}.
## "self" is the creature whose effect is running (works from Ao Morrer). Overrides stick to the instance.
func _summon_effect(p: int, e: Dictionary) -> void:
	var id: String = e.get("card", "self")
	if id == "self":
		if _dying.is_empty():
			return
		id = _dying["card_id"]
	if players[p]["board"].size() >= BOARD_LIMIT:
		return
	_summon(p, id, _uid(), false, 0, e.get("overrides", {}))
