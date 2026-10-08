class_name GameState
extends RefCounted
## Pure, UI-free rules engine. Every public action validates input, mutates
## state and returns an Array of event Dictionaries the UI can animate.
## Invalid actions return [] and leave state untouched.

const START_HAND := 5
const MULLIGAN_MAX := 3
const HAND_LIMIT := 10
const BOARD_LIMIT := 8
const MOMENTUM_CAP := 10
const RESERVE_CAP := 2 ## unspent Momentum banked at turn start; pays only spells and abilities
const COMMANDER_TAX := 2
const SECOND_BONUS_TURNS := 2 ## the second player's first turns that start with +1 Reserve (the first also with +1 Momentum)

## Leaders are addressed with negative uids so targets are a single int.
const LEADER_UID := [-1, -2]

var players: Array = []
var active := 0
var turn := 0
var first := 0 ## who takes turn 1 (skips that draw, mulligans first; the other gets the early Momentum bonus)
var phase := "mulligan"
var winner := -1 ## -1 none, 0/1 player, 2 draw
## Pending combat: attacker uid -> provoked enemy uid (or 0)
var attackers: Dictionary = {}
## Locked-in blocks (attacker uid -> blocker uid) during the damage window. Final: a
## blocker that dies before damage still leaves its attacker blocked.
var blocks: Dictionary = {}
## Pending deterministic deck search. The matching cards are public until chosen.
var pending_search: Dictionary = {}
## Ao Entrar waiting for its owner to pick a target, after the unit is already on the board
## (phase "enter_target"): {player, uid, card_id, spec}. Optional: target 0 skips the effect.
var pending_enter: Dictionary = {}
## Spells, equipment and leader abilities wait here (LIFO) until both players let them resolve.
## Item: {sid, player, kind:"card"|"ability", uid, card_id, target, speed}
var stack: Array = []
## Who may act during "main"/"combat". Casting hands priority to the opponent (response);
## a pass with items on the stack resolves the whole stack.
var priority := 0
## Combat window while phase == "combat": "attack" (attacker), "prepare" (defender),
## then blocks, then "damage" (attacker first; damage when both pass in a row).
var window := ""
## Main-phase response window right after the active player summoned a unit from hand or
## the Santuário (stack empty): the opponent holds priority and may cast Rápido/Instantâneo.
var summon_window := false
var _summon_pending := false # a summon's search delays its response window
## Per seat: skip priority windows where that player has no legal play (a player can turn
## this off to be asked every time). Also skips a block prompt with no possible blocker.
var auto_pass: Array = [true, true]
var _search_return := "main"
## True while combat damage is being dealt and the deaths it causes are resolved; effects
## marked "not_in_combat" stay silent then (Cientista da Morte).
var _combat_damage := false
## Cards sent to the graveyard by the latest mill (offered by mill_pick).
var _milled: Array = []
var rng := RandomNumberGenerator.new()
var _next_uid := 1
var _events: Array = []
var _trigger_depth := 0
var _chosen2 := 0 ## second target of the stack item being resolved (e.g. the damage target of a sacrifice spell)
var _sac_atk := 0 ## total attack of the unit the last "sacrifice" killed
var _dying: Dictionary = {} ## unit whose Ao Morrer is resolving (for summon "self")

func _init(deck_a: String, deck_b: String, seed_value: int = 0, first_player: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	first = first_player
	for i in 2:
		players.append(_make_player(i, [deck_a, deck_b][i]))
	for i in 2:
		_draw(i, START_HAND)
	_events.clear()

func _make_player(i: int, deck_id: String) -> Dictionary:
	var d := DeckDB.get_deck(deck_id)
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
		"momentum": 0, "max_momentum": 0, "reserve": 0,
		"deck": deck, "hand": [], "board": [], "graveyard": [], "banished": [],
		"legendary": {"card_id": ld["legendary"], "in_zone": true, "casts": 0},
		"ability_used": false, "passive_used": false, "attacked": false, "fatigue": 0, "mulligan_done": false,
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
			return first if not players[first]["mulligan_done"] else opponent(first)
		"blocks":
			return opponent(active)
		"search":
			return int(pending_search.get("player", active))
		"enter_target":
			return int(pending_enter.get("player", active))
		"main", "combat":
			return priority
	return active

func find_unit(uid: int) -> Dictionary:
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
	if kw == "escudo_feitico":
		return c.get("spell_shield", false)
	return c["keywords"].has(kw)

func atk_of(c: Dictionary) -> int:
	return max(0, c["atk"] + c["temp_atk"] + int(c.get("bonus_atk", 0)))

func hp_left(c: Dictionary) -> int:
	return c["hp"] + int(c.get("bonus_hp", 0)) - c["damage"]

## Unit cards in a player's graveyard.
func graveyard_units(p: int) -> int:
	var n := 0
	for e in players[p]["graveyard"]:
		if CardDB.card(e["card_id"])["type"] == "unit":
			n += 1
	return n

## Recomputes the "constante" effects of board units. Action "scale" gives
## atk/hp per counted thing (e.g. +2/+2 per unit card in the own graveyard).
func _refresh_scaling() -> void:
	for p in 2:
		for c in players[p]["board"]:
			var b := scale_bonus(p, card_of(c))
			c["bonus_atk"] = b.x
			c["bonus_hp"] = b.y

## Atk/hp a card's "constante" scale effects would give it under player p right
## now. Also used to preview the live stats of cards off the board (hand, command zone).
func scale_bonus(p: int, cd: Dictionary) -> Vector2i:
	var out := Vector2i.ZERO
	for e in cd.get("effects", []):
		if e.get("trigger", "") != "constante" or e.get("action", "") != "scale":
			continue
		var n := 0
		match e.get("per", ""):
			"own_graveyard_units": n = graveyard_units(p)
			"enemy_graveyard_units": n = graveyard_units(opponent(p))
		out += Vector2i(n * int(e.get("atk", 0)), n * int(e.get("hp", 0)))
	return out

## The Encarnação left the board by dying or being banished (a return to hand doesn't count).
## If its next cast would cost more than the Momentum cap, it retires: it goes to the bottom of
## the deck as a normal card at its base cost, for good. Otherwise it goes back to the Santuário.
func _legendary_leaves(p: int) -> void:
	var l: Dictionary = players[p]["legendary"]
	if legendary_cost(p) <= MOMENTUM_CAP:
		l["in_zone"] = true
		return
	l["retired"] = true
	players[p]["deck"].insert(0, {"uid": _uid(), "card_id": l["card_id"]}) # draws pop the back
	_emit({"type": "legendary_retired", "player": p, "card_id": l["card_id"]})

func legendary_cost(p: int) -> int:
	var l: Dictionary = players[p]["legendary"]
	return int(CardDB.card(l["card_id"])["cost"]) + COMMANDER_TAX * int(l["casts"])

## Congelada: can't attack or block until the end of its owner's next turn.
func is_frozen(c: Dictionary) -> bool:
	return c.has("frozen")

func can_attack(c: Dictionary) -> bool:
	return not is_frozen(c) and not c["exhausted"] and (not c["sick"] or has_kw(c, "impeto")) and atk_of(c) > 0

func can_block(blocker: Dictionary, attacker: Dictionary) -> bool:
	if is_frozen(blocker) or has_kw(blocker, "nao_bloqueia"):
		return false
	if has_kw(attacker, "voo") and not (has_kw(blocker, "voo") or has_kw(blocker, "longo_alcance")):
		return false
	if has_kw(attacker, "furtividade") and not (has_kw(blocker, "furtividade") or has_kw(blocker, "vigilancia")):
		return false
	return true

## Effect spec of a card/ability that needs a chosen target, or "" if none.
func target_spec(effects: Array) -> String:
	for e in effects:
		if e.get("target", "") in ["enemy_unit", "ally_unit", "other_ally_unit", "any_unit", "any", "enemy_stack"]:
			return e["target"]
	return ""

## Second target a card needs on top of its first (e.g. the damage target after the sacrifice), or "".
## Declared on a "then" effect with "pick": true.
func second_spec(cd: Dictionary) -> String:
	for e in cd.get("effects", []):
		for t in e.get("then", []):
			if t.get("pick", false):
				return t["target"]
	return ""

## Target a card needs when played: its additional sacrifice cost (the unit to sacrifice)
## or the chosen target of its effects. A unit's Ao Entrar target is picked after it enters
## (see enter_spec), so it is not part of playing it.
func card_spec(cd: Dictionary) -> String:
	if cd.get("cost_sacrifice", false):
		return "ally_unit"
	return "" if cd["type"] == "unit" else target_spec(cd["effects"])

## Target spec of a unit's Ao Entrar, or "".
func enter_spec(cd: Dictionary) -> String:
	var on_enter: Array = []
	for e in cd.get("effects", []):
		if e.get("trigger", "") == "on_enter":
			on_enter.append(e)
	return target_spec(on_enter)

## Momentum cost of a card for player p, after "constante" cost_reduction effects
## (e.g. per: "own_graveyard" = 1 less for each card in the own graveyard). Never below 0.
func cost_of(p: int, cd: Dictionary) -> int:
	var c := int(cd["cost"])
	for e in cd.get("effects", []):
		if e.get("trigger", "") != "constante" or e.get("action", "") != "cost_reduction":
			continue
		var n := 0
		match e.get("per", ""):
			"own_graveyard": n = players[p]["graveyard"].size()
		c -= n * int(e.get("amount", 1))
	return maxi(c, 0)

## Momentum p can spend on a play: the Reserva only counts for spells and leader abilities.
func budget(p: int, spell: bool) -> int:
	return int(players[p]["momentum"]) + (int(players[p]["reserve"]) if spell else 0)

## Pays `amount`; spells and abilities drain the Reserva first so more plain Momentum is
## left over to bank next turn.
func _pay(p: int, amount: int, spell: bool) -> void:
	var pl: Dictionary = players[p]
	if spell:
		var r := mini(amount, int(pl["reserve"]))
		pl["reserve"] -= r
		amount -= r
	pl["momentum"] -= amount

static func _is_spell(cd: Dictionary) -> bool:
	return cd.get("type", "") == "spell"

func valid_targets(p: int, spec: String, self_uid: int = 0) -> Array:
	var out: Array = []
	var mine: Array = players[p]["board"]
	var theirs: Array = players[opponent(p)]["board"]
	match spec:
		"enemy_unit":
			for c in theirs: out.append(c["uid"])
		"ally_unit":
			for c in mine: out.append(c["uid"])
		"other_ally_unit":
			for c in mine:
				if c["uid"] != self_uid: out.append(c["uid"])
		"any_unit":
			for c in mine + theirs: out.append(c["uid"])
		"any":
			for c in mine + theirs: out.append(c["uid"])
			out.append(LEADER_UID[opponent(p)])
		"enemy_stack":
			for it in stack:
				if it["player"] != p and not _is_equip_item(it): out.append(it["sid"])
	return out

## Equipping can be responded to but never countered.
func _is_equip_item(it: Dictionary) -> bool:
	return it["kind"] == "card" and CardDB.is_equipment(CardDB.card(it["card_id"]))

func _stack_item(sid: int) -> Dictionary:
	for it in stack:
		if it["sid"] == sid:
			return it
	return {}

## Momentum cost of a spell/ability on the stack.
func stack_cost(item: Dictionary) -> int:
	if item["kind"] == "ability":
		return int(CardDB.leader(players[item["player"]]["leader_id"])["ability"]["cost"])
	return int(CardDB.card(item["card_id"]).get("cost", 0))

## Extra Momentum a counter (action "counter") must pay to hit stack item `sid`:
## 0 up to max_cost, kicker_cost up to kicker_max_cost, -1 when out of reach.
func counter_extra(cd: Dictionary, sid: int) -> int:
	var it := _stack_item(sid)
	if it.is_empty():
		return -1
	for e in cd["effects"]:
		if e.get("action", "") != "counter":
			continue
		var c := stack_cost(it)
		if c <= int(e.get("max_cost", 99)):
			return 0
		if e.has("kicker_cost") and c <= int(e.get("kicker_max_cost", 99)):
			return int(e["kicker_cost"])
		return -1
	return 0

## Targets a card from hand can be played on right now (counters filter by reach and Momentum).
func card_targets(p: int, cd: Dictionary) -> Array:
	var spec := card_spec(cd)
	var out := valid_targets(p, spec)
	if spec != "enemy_stack":
		return out
	var ok: Array = []
	for sid in out:
		var x := counter_extra(cd, sid)
		if x >= 0 and cost_of(p, cd) + x <= budget(p, _is_spell(cd)):
			ok.append(sid)
	return ok

## Speed of a card or leader ability: "lento" (default), "rapido" or "instantaneo".
func speed_of(src: Dictionary) -> String:
	if src.has("speed"):
		return String(src["speed"])
	if (src.get("keywords", []) as Array).has("saque_rapido") or (src.get("tags", []) as Array).has("saque_rapido"):
		return "rapido"
	return "lento"

## Lento: own Main Phase with an empty stack. Rápido: also combat windows.
## Instantâneo: also as a response to anything on the stack.
func can_cast_speed(p: int, speed: String) -> bool:
	if phase not in ["main", "combat"] or p != priority:
		return false
	if not stack.is_empty():
		return speed == "instantaneo"
	if phase == "main":
		return p == active or (summon_window and speed != "lento")
	return speed != "lento"

## Units, the Legendary, attacking and ending the turn: own Main Phase, empty stack.
func _sorcery_time(p: int) -> bool:
	return phase == "main" and p == active and priority == p and stack.is_empty() and not summon_window

func can_play(p: int, hand_uid: int) -> bool:
	var inst := _hand_card(p, hand_uid)
	if inst.is_empty():
		return false
	var cd := CardDB.card(inst["card_id"])
	if cost_of(p, cd) > budget(p, _is_spell(cd)):
		return false
	if cd["type"] == "unit":
		if not _sorcery_time(p):
			return false
		if cd.get("cost_sacrifice", false):
			return not players[p]["board"].is_empty() # the sacrifice also frees the slot
		return players[p]["board"].size() < BOARD_LIMIT
	if not can_cast_speed(p, speed_of(cd)):
		return false
	var spec := target_spec(cd["effects"])
	return spec == "" or not card_targets(p, cd).is_empty()

func can_cast_legendary(p: int) -> bool:
	return _sorcery_time(p) and players[p]["legendary"]["in_zone"] \
		and legendary_cost(p) <= players[p]["momentum"] and players[p]["board"].size() < BOARD_LIMIT

func can_use_ability(p: int) -> bool:
	var ab: Dictionary = CardDB.leader(players[p]["leader_id"])["ability"]
	if ab.get("passive", false):
		return false # passives fire on their own trigger
	if not can_cast_speed(p, speed_of(ab)) or int(ab["cost"]) > budget(p, true):
		return false
	if (ab.get("once_per_turn", false) or ab.get("once_per_cycle", false)) and players[p]["ability_used"]:
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
		_start_turn(first, false)
	return _flush()

func play_card(p: int, hand_uid: int, target: int = 0, target2: int = 0) -> Array:
	if not can_play(p, hand_uid):
		return []
	var inst := _hand_card(p, hand_uid)
	var cd := CardDB.card(inst["card_id"])
	var sacrifice: bool = cd["type"] == "unit" and cd.get("cost_sacrifice", false)
	var spec := target_spec(cd["effects"])
	if sacrifice:
		if not valid_targets(p, "ally_unit").has(target):
			return []
	elif cd["type"] != "unit" and spec != "" and not card_targets(p, cd).has(target):
		return []
	var spec2 := second_spec(cd)
	if spec2 != "" and (target2 == target or not valid_targets(p, spec2).has(target2)):
		return []
	var pl: Dictionary = players[p]
	_pay(p, cost_of(p, cd) + (counter_extra(cd, target) if spec == "enemy_stack" else 0), _is_spell(cd))
	pl["hand"].erase(inst)
	_emit({"type": "play", "player": p, "uid": hand_uid, "card_id": inst["card_id"]})
	if sacrifice:
		# additional cost: the chosen ally dies first (its Ao Morrer / Aliado Morre resolve before the card enters)
		find_unit(target)["damage"] = 1000000
		_emit({"type": "sacrifice", "player": p, "uid": target})
		_check_state()
		if phase == "over":
			return _flush()
		if pl["board"].size() >= BOARD_LIMIT: # a death effect refilled the slot
			pl["graveyard"].append({"uid": hand_uid, "card_id": inst["card_id"]})
			_settle()
			return _flush()
	if cd["type"] == "unit":
		_summon(p, inst["card_id"], hand_uid, false, 0, {}, true)
		_check_state()
		_open_summon_window(p)
	else:
		_push(p, "card", hand_uid, inst["card_id"], target, speed_of(cd), target2)
	_settle()
	return _flush()

func cast_legendary(p: int, _target: int = 0) -> Array:
	if not can_cast_legendary(p):
		return []
	var pl: Dictionary = players[p]
	pl["momentum"] -= legendary_cost(p)
	pl["legendary"]["in_zone"] = false
	pl["legendary"]["casts"] += 1
	var uid := _uid()
	_emit({"type": "play", "player": p, "uid": uid, "card_id": pl["legendary"]["card_id"], "legendary": true})
	_summon(p, pl["legendary"]["card_id"], uid, true, 0, {}, true)
	_check_state()
	_open_summon_window(p)
	_settle()
	return _flush()

func use_ability(p: int, target: int = 0) -> Array:
	if not can_use_ability(p):
		return []
	var ab: Dictionary = CardDB.leader(players[p]["leader_id"])["ability"]
	var spec := target_spec(ab["effects"])
	if spec != "" and not valid_targets(p, spec).has(target):
		return []
	_pay(p, int(ab["cost"]), true)
	players[p]["ability_used"] = true
	_emit({"type": "ability", "player": p})
	_push(p, "ability", 0, "", target, speed_of(ab))
	_settle()
	return _flush()

## Gives up priority. With items on the stack, everything resolves (newest first);
## in an empty combat window the combat moves on to the next window.
func pass_priority(p: int) -> Array:
	if phase not in ["main", "combat"] or p != priority:
		return []
	if stack.is_empty() and phase == "main" and not summon_window:
		return [] # nothing to pass: end the turn instead
	_emit({"type": "pass", "player": p})
	_pass()
	_settle()
	return _flush()

## attacks: Dictionary attacker_uid -> provoked enemy uid (0 when none).
func declare_attack(p: int, attacks: Dictionary) -> Array:
	if not _sorcery_time(p) or players[p]["attacked"] or attacks.is_empty():
		return []
	var provoked_used: Array = []
	for uid in attacks:
		var c := find_unit(uid)
		if c.is_empty() or c["owner"] != p or not can_attack(c):
			return []
		var prov: int = attacks[uid]
		if prov != 0:
			var t := find_unit(prov)
			if not has_kw(c, "provocacao") or t.is_empty() or t["owner"] == p or provoked_used.has(prov) or is_frozen(t) or has_kw(t, "nao_bloqueia"):
				return []
			provoked_used.append(prov)
	attackers = attacks.duplicate()
	players[p]["attacked"] = true
	for uid in attacks:
		find_unit(uid)["exhausted"] = true
	_emit({"type": "attack", "player": p, "attackers": attacks.keys()})
	for uid in attacks:
		_fire(find_unit(uid), "on_attack")
	_check_state()
	if phase == "over":
		return _flush()
	phase = "combat"
	_open_window("attack")
	_settle()
	return _flush()

## blocks: Dictionary attacker_uid -> blocker_uid. One blocker per attacker,
## one attacker per blocker. Provoked units are forced onto their provoker.
## Provoked units must block their provoker (unless dead or frozen).
func _forced_blocks() -> Dictionary:
	var final := {}
	for a in attackers:
		if attackers[a] != 0 and not find_unit(attackers[a]).is_empty() and not is_frozen(find_unit(attackers[a])):
			final[a] = attackers[a]
	return final

func declare_blocks(p: int, picks: Dictionary) -> Array:
	if phase != "blocks" or p != decider():
		return []
	var final := _forced_blocks()
	var used: Array = final.values()
	for a in picks:
		if final.has(a):
			continue
		var b: int = picks[a]
		var att := find_unit(a)
		var blk := find_unit(b)
		if not attackers.has(a) or blk.is_empty() or blk["owner"] != p or used.has(b) or not can_block(blk, att):
			return []
		final[a] = b
		used.append(b)
	_start_damage(final)
	_settle()
	return _flush()

## Gives up the match: the opponent wins at once. Allowed at any moment, even off-turn or mid-stack.
func concede(p: int) -> Array:
	if phase == "over":
		return []
	_emit({"type": "concede", "player": p})
	winner = opponent(p)
	phase = "over"
	_emit({"type": "game_over", "winner": winner})
	return _flush()

func end_turn(p: int) -> Array:
	if not _sorcery_time(p):
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
		# Banished, not discarded: the card never reaches the graveyard (hidden from the opponent).
		players[p]["banished"].append({"uid": c["uid"], "card_id": c["card_id"]})
		_emit({"type": "ban", "player": p, "uid": uid})
	phase = "main"
	_finish_turn()
	return _flush()

## Picks the target of the pending Ao Entrar (0 = decline: its targeted effects are skipped,
## the rest still happen), then the unit's summon response window opens.
func choose_enter_target(p: int, target: int) -> Array:
	if phase != "enter_target" or p != decider():
		return []
	var uid := int(pending_enter["uid"])
	if target != 0 and not valid_targets(p, pending_enter["spec"], uid).has(target):
		return []
	pending_enter.clear()
	phase = "main"
	var c := find_unit(uid)
	var effects: Array = card_of(c)["effects"]
	if target == 0:
		_emit({"type": "enter_skip", "player": p, "uid": uid, "card_id": c["card_id"]})
		var rest: Array = []
		for e in effects:
			if target_spec([e]) == "":
				rest.append(e)
		effects = rest
	_announce(c, effects, "on_enter")
	_run_effects(p, effects, "on_enter", target, uid)
	_check_state()
	_after_search()
	_settle()
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
	if pending_search.get("grave", false):
		# Moer + escolher: the card comes out of the graveyard; the others stay there
		var grave: Array = players[p]["graveyard"]
		var gi := -1
		for i in grave.size():
			if int(grave[i]["uid"]) == card_uid:
				gi = i
				break
		if gi < 0:
			return []
		grave.remove_at(gi)
		players[p]["hand"].append(chosen)
		pending_search.clear()
		phase = _search_return
		_emit({"type": "search_take", "player": p, "uid": card_uid, "card_id": chosen["card_id"]})
		_resolve_stack()
		_after_search()
		_settle()
		return _flush()
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
	var look: bool = pending_search.get("look", false)
	if look:
		# the cards not taken go to the bottom of the deck, unrevealed
		for c in options:
			if int(c["uid"]) == card_uid:
				continue
			for d in deck:
				if int(d["uid"]) == int(c["uid"]):
					deck.erase(d)
					deck.push_front(d)
					break
	else:
		_shuffle(deck)
	pending_search.clear()
	phase = _search_return
	_emit({"type": "search_take", "player": p, "uid": card_uid, "card_id": chosen["card_id"]})
	_emit({"type": "look_bottom" if look else "search_shuffle", "player": p})
	_resolve_stack() # a search opened mid-resolution: finish the rest of the stack
	_after_search()
	_settle()
	return _flush()

# ---------------------------------------------------------------- stack & windows

func _push(p: int, kind: String, uid: int, card_id: String, target: int, speed: String, target2: int = 0) -> void:
	var item := {"sid": _uid(), "player": p, "kind": kind, "uid": uid, "card_id": card_id, "target": target, "target2": target2, "speed": speed}
	stack.append(item)
	summon_window = false
	_summon_pending = false
	priority = opponent(p)
	_emit({"type": "stack_push", "item": item.duplicate()})

func _effects_of(item: Dictionary) -> Array:
	if item["kind"] == "ability":
		return CardDB.leader(players[item["player"]]["leader_id"])["ability"]["effects"]
	return CardDB.card(item["card_id"])["effects"]

## Resolves the stack newest-first. Stops early if the game ends or a search needs a choice.
func _resolve_stack() -> void:
	while not stack.is_empty() and phase in ["main", "combat"]:
		var item: Dictionary = stack.pop_back()
		var p: int = item["player"]
		var effects := _effects_of(item)
		var spec := target_spec(effects)
		if spec != "" and not valid_targets(p, spec).has(int(item["target"])):
			_emit({"type": "fizzle", "sid": item["sid"], "player": p, "card_id": item["card_id"], "kind": item["kind"]})
		else:
			_emit({"type": "resolve", "sid": item["sid"], "player": p, "card_id": item["card_id"], "kind": item["kind"]})
			_chosen2 = int(item.get("target2", 0))
			_run_effects(p, effects, "on_play" if item["kind"] == "card" else "", int(item["target"]), 0)
			_chosen2 = 0
		if item["kind"] == "card":
			var holder := find_unit(int(item["target"]))
			if CardDB.is_equipment(CardDB.card(item["card_id"])) and not holder.is_empty() and spec != "" and valid_targets(p, spec).has(int(item["target"])):
				_attach(holder, item["uid"], item["card_id"])
			else:
				players[p]["graveyard"].append({"uid": item["uid"], "card_id": item["card_id"]})
		_check_state()
		_prune_attackers()
	if phase in ["main", "combat"] and stack.is_empty():
		summon_window = false
		priority = _window_owner()

## Equipment stays on the board under its unit; a previous one is discarded.
func _attach(holder: Dictionary, uid: int, card_id: String) -> void:
	_release_equipment(holder)
	holder["equipment"] = {"uid": uid, "card_id": card_id}
	_emit({"type": "attach", "uid": holder["uid"], "equip_uid": uid, "card_id": card_id})

## Sends the unit's equipment (if any) to its owner's graveyard.
func _release_equipment(c: Dictionary) -> void:
	if not c.has("equipment"):
		return
	var eq: Dictionary = c["equipment"]
	c.erase("equipment")
	players[int(c["owner"])]["graveyard"].append(eq)
	_emit({"type": "equipment_break", "uid": c["uid"], "equip_uid": eq["uid"], "card_id": eq["card_id"]})

## Removes stack item `sid` without resolving it; a countered card goes to the graveyard.
func _counter(p: int, sid: int) -> void:
	var it := _stack_item(sid)
	if it.is_empty() or _is_equip_item(it):
		return
	stack.erase(it)
	if it["kind"] == "card":
		players[it["player"]]["graveyard"].append({"uid": it["uid"], "card_id": it["card_id"]})
	_emit({"type": "countered", "sid": sid, "player": it["player"], "by": p, "card_id": it["card_id"], "kind": it["kind"]})

## Damage window: the attacker holds priority after the stack resolves.
func _window_owner() -> int:
	return opponent(active) if phase == "combat" and window == "prepare" else active

func _open_window(w: String) -> void:
	window = w
	priority = _window_owner()
	_emit({"type": "window", "window": w, "player": priority})

func _pass() -> void:
	if not stack.is_empty():
		_resolve_stack()
		return
	if summon_window:
		summon_window = false
		priority = active
		return
	match window:
		"attack":
			_open_window("prepare")
		"prepare":
			_to_blocks()
		"damage":
			if priority == active:
				priority = opponent(active) # attacker passed: the defender may still act
			else:
				_resolve_combat() # both passed in a row with an empty stack
		_:
			_to_blocks()

## Attackers that died during the windows leave combat.
func _prune_attackers() -> void:
	for a in attackers.keys():
		if find_unit(a).is_empty():
			attackers.erase(a)

func _to_blocks() -> void:
	window = ""
	_prune_attackers()
	if attackers.is_empty():
		_end_combat()
	elif players[opponent(active)]["board"].is_empty() or (auto_pass[opponent(active)] and not _can_block_any()):
		_start_damage(_forced_blocks())
	else:
		phase = "blocks"

## Blocks are locked in, block triggers fire, then the damage window opens.
func _start_damage(final: Dictionary) -> void:
	phase = "combat"
	blocks = final
	_emit({"type": "blocks", "blocks": final})
	for a in final:
		_fire(find_unit(final[a]), "on_block", a)
		_fire(find_unit(a), "on_blocked", final[a])
	_check_state()
	if phase == "over":
		attackers.clear()
		blocks.clear()
		return
	_prune_attackers()
	if attackers.is_empty():
		_end_combat()
		return
	_open_window("damage")

## Is there any attacker that some defending unit may legally block?
func _can_block_any() -> bool:
	var forced := _forced_blocks()
	for a in attackers:
		if forced.has(a):
			continue
		var att := find_unit(a)
		for blk in players[opponent(active)]["board"]:
			if not forced.values().has(blk["uid"]) and can_block(blk, att):
				return true
	return false

func _end_combat() -> void:
	attackers.clear()
	blocks.clear()
	window = ""
	if phase != "over":
		phase = "main"
		priority = active

## After a unit enters from hand/Santuário in the main phase, the opponent may respond.
func _open_summon_window(p: int) -> void:
	if phase in ["search", "enter_target"] and p == active:
		_summon_pending = true
		return
	if phase == "main" and stack.is_empty() and p == active:
		summon_window = true
		priority = opponent(p)

## A summon whose on_play searched (or whose Ao Entrar awaited a target) opens its
## response window once the pick is made.
func _after_search() -> void:
	if _summon_pending and phase == "main":
		_summon_pending = false
		_open_summon_window(active)

## Turns p's auto-pass on or off. Turning it on while p holds an unusable window passes it.
func set_auto_pass(p: int, on: bool) -> Array:
	auto_pass[p] = on
	if on:
		_settle()
	return _flush()

## Can p do anything right now besides passing?
func _has_play(p: int) -> bool:
	for c in players[p]["hand"]:
		if can_play(p, c["uid"]):
			return true
	return can_use_ability(p)

## Auto-passes for whoever holds priority with no legal play, so windows nobody can use
## cost no clicks. Stops at a real decision.
func _settle() -> void:
	for guard in 64:
		if phase not in ["main", "combat"]:
			return
		if stack.is_empty() and phase == "main" and not summon_window:
			priority = active
			return
		if not auto_pass[priority] or _has_play(priority):
			return
		_pass()

# ---------------------------------------------------------------- internals

## ask: played from hand/Santuário, so a targeted Ao Entrar waits for its owner's pick
## (phase "enter_target") instead of resolving right away.
func _summon(p: int, card_id: String, uid: int, legendary: bool, target: int, over: Dictionary = {}, ask := false) -> void:
	var cd := CardDB.card_for(card_id, {"over": over})
	var kws: Array = cd.get("keywords", []).duplicate()
	var c := {
		"uid": uid, "card_id": card_id, "owner": p, "legendary": legendary,
		"atk": int(cd["atk"]), "hp": int(cd["hp"]), "damage": 0, "temp_atk": 0,
		"keywords": kws, "temp_keywords": [], "shield": kws.has("escudo"),
		"spell_shield": kws.has("escudo_feitico"), "exhausted": false, "sick": true,
	}
	if not over.is_empty():
		c["over"] = over
	kws.erase("escudo")
	kws.erase("escudo_feitico")
	players[p]["board"].append(c)
	_emit({"type": "summon", "player": p, "uid": uid, "card_id": card_id})
	var spec := enter_spec(cd)
	if ask and spec != "" and not valid_targets(p, spec, uid).is_empty():
		pending_enter = {"player": p, "uid": uid, "card_id": card_id, "spec": spec}
		phase = "enter_target"
		_emit({"type": "enter_target", "player": p, "uid": uid, "card_id": card_id})
		return
	# "ally_unit" Ao Entrar with no chosen ally falls back to the unit itself
	if target == 0 and target_spec(cd["effects"]) == "ally_unit":
		target = uid
	_announce(c, cd["effects"], "on_enter")
	_run_effects(p, cd["effects"], "on_enter", target, uid)

## Tells the UI that unit c's `trigger` went off, so it can show where the effects that
## follow come from. Only when at least one of `effects` actually runs for that trigger.
func _announce(c: Dictionary, effects: Array, trigger: String) -> void:
	for e in effects:
		if e.get("trigger", "") == trigger:
			_emit({"type": "trigger", "uid": c["uid"], "player": c["owner"], "card_id": c["card_id"], "trigger": trigger})
			return

## Fires a unit's own trigger. Depth-capped so on_damaged chains cannot loop forever.
func _fire(c: Dictionary, trigger: String, other_uid: int = 0) -> void:
	if c.is_empty() or _trigger_depth >= 4:
		return
	var effects: Array = []
	var used: Dictionary = c.get("used_turn", {})
	var all_effects: Array = card_of(c)["effects"]
	for i in all_effects.size():
		var e: Dictionary = all_effects[i]
		if e.get("trigger", "") == trigger and _combat_damage and e.get("not_in_combat", false):
			continue
		if e.get("trigger", "") == trigger and e.get("once_per_turn", false):
			if used.get(i, -1) == turn:
				continue # "once per turn" effect already used this turn
			used[i] = turn
			c["used_turn"] = used
		effects.append(e)
	_announce(c, effects, trigger)
	_trigger_depth += 1
	_run_effects(c["owner"], effects, trigger, 0, c["uid"], other_uid)
	_trigger_depth -= 1

## Gatilhos (cards.json "triggers"): on_play, on_enter, on_death, on_attack, on_block,
## on_blocked, on_damaged, on_hit_leader, on_turn_start, on_turn_end. "constante" never fires
## here: it is continuous and handled by _refresh_scaling.
## other_uid is the opposing unit in combat triggers (blocker, attacker, damage source).
func _run_effects(p: int, effects: Array, trigger: String, chosen: int, self_uid: int, other_uid: int = 0) -> void:
	for e in effects:
		if trigger != "" and e.get("trigger", "") != trigger:
			continue
		if e.get("trigger", "") == "constante":
			continue
		var targets: Array = []
		match e.get("target", ""):
			"enemy_unit", "ally_unit", "other_ally_unit", "any_unit", "any", "enemy_stack":
				if valid_targets(p, e["target"], self_uid).has(chosen):
					targets = [chosen]
			"all_enemy_units":
				for c in players[opponent(p)]["board"]: targets.append(c["uid"])
			"enemy_leader":
				targets = [LEADER_UID[opponent(p)]]
			"own_leader":
				targets = [LEADER_UID[p]]
			"both_leaders":
				targets = [LEADER_UID[p], LEADER_UID[opponent(p)]]
			"random_enemy_unit":
				var b: Array = players[opponent(p)]["board"]
				if not b.is_empty(): targets = [b[rng.randi_range(0, b.size() - 1)]["uid"]]
			"random_enemy_and_adjacent":
				var eb: Array = players[opponent(p)]["board"]
				if not eb.is_empty():
					var ci := rng.randi_range(0, eb.size() - 1)
					for j in range(maxi(ci - 1, 0), mini(ci + 1, eb.size() - 1) + 1): targets.append(eb[j]["uid"])
			"self":
				if not find_unit(self_uid).is_empty(): targets = [self_uid]
			"none":
				targets = [0]
			"opposed_unit":
				if not find_unit(other_uid).is_empty(): targets = [other_uid]
			"all_units":
				for side in [p, opponent(p)]:
					for c in players[side]["board"]: targets.append(c["uid"])
			"all_ally_units":
				for c in players[p]["board"]: targets.append(c["uid"])
			"random_ally_unit", "random_other_ally_unit":
				var pool: Array = []
				for c in players[p]["board"]:
					if e["target"] == "random_ally_unit" or c["uid"] != self_uid: pool.append(c["uid"])
				if not pool.is_empty(): targets = [pool[rng.randi_range(0, pool.size() - 1)]]
		for t in targets:
			_apply(p, e, t)
		if e.get("action", "") == "search_deck" and e.get("trigger", "") == trigger:
			_begin_search(p, e, self_uid)
		elif e.get("action", "") == "mill_pick" and e.get("trigger", "") == trigger:
			_begin_grave_pick(p, self_uid)
		elif e.get("action", "") == "look_top" and e.get("trigger", "") == trigger:
			_begin_look(p, int(e.get("count", 4)), self_uid)

func _begin_search(p: int, e: Dictionary, source_uid: int) -> void:
	if phase == "search":
		return
	var matches: Array = []
	var seen: Dictionary = {}
	for c in players[p]["deck"]:
		var cd := CardDB.card(c["card_id"])
		if e.get("essence", "") != "" and not CardDB.has_essence(cd, e["essence"]):
			continue
		if e.has("max_cost") and int(cd.get("cost", 999)) > int(e["max_cost"]):
			continue
		if e.has("type") and cd.get("type", "") != e["type"]:
			continue
		if e.has("species") and not cd.get("species", []).has(e["species"]):
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
	_search_return = phase
	phase = "search"
	_emit({"type": "search_reveal", "player": p, "source_uid": source_uid, "cards": matches})

## Offers the cards just milled (public: they are in the graveyard); one goes to the hand.
func _begin_grave_pick(p: int, source_uid: int) -> void:
	if phase == "search":
		return
	var options: Array = []
	for c in _milled:
		for g in players[p]["graveyard"]:
			if int(g["uid"]) == int(c["uid"]):
				options.append({"uid": c["uid"], "card_id": c["card_id"]})
				break
	if options.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": options, "grave": true}
	_search_return = phase
	phase = "search"
	_emit({"type": "search_reveal", "player": p, "source_uid": source_uid, "cards": options})

## Private look at the top `n` cards: only the owner sees them (StateView hides them from
## the other seat); the one taken is revealed by search_take, the rest go to the bottom.
func _begin_look(p: int, n: int, source_uid: int) -> void:
	if phase == "search":
		return
	var deck: Array = players[p]["deck"]
	var top: Array = []
	for i in range(deck.size() - 1, maxi(deck.size() - n, 0) - 1, -1): # top of the deck is the back
		top.append({"uid": deck[i]["uid"], "card_id": deck[i]["card_id"]})
	if top.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": top, "look": true}
	_search_return = phase
	phase = "search"
	_emit({"type": "look_top", "player": p, "source_uid": source_uid, "cards": top})

func _apply(p: int, e: Dictionary, t: int) -> void:
	if e["action"] == "counter":
		_counter(p, t)
		return
	# Escudo de Feitiço: the first non-combat effect from the enemy side is cancelled
	var hit := find_unit(t) if t > 0 else {}
	if not hit.is_empty() and hit["owner"] != p and hit.get("spell_shield", false):
		hit["spell_shield"] = false
		_emit({"type": "spell_shield_break", "uid": t})
		return
	match e["action"]:
		"damage":
			var amount := _sac_atk if e.get("amount_from", "") == "sacrificed_atk" else int(e["amount"])
			var red: Dictionary = e.get("ally_reduce", {})
			var victim := find_unit(t)
			if not red.is_empty() and not victim.is_empty() and victim["owner"] == p and CardDB.has_essence(card_of(victim), red["essence"]):
				amount = int(red["amount"])
			_deal_damage(t, amount, {})
		"heal_leader":
			_heal_leader(p, int(e["amount"]))
		"heal_full":
			var hc := find_unit(t)
			if not hc.is_empty() and hc["damage"] > 0:
				_emit({"type": "heal", "uid": t, "amount": hc["damage"]})
				hc["damage"] = 0
		"draw":
			_draw(opponent(p) if t == LEADER_UID[opponent(p)] else p, int(e["amount"]))
		"tide_mark":
			var m := find_unit(t)
			if not m.is_empty():
				m["tide_mark"] = true
				_emit({"type": "tide_mark", "uid": t})
		"search_deck", "look_top":
			pass # Search effects are opened by _run_effects after their trigger resolves.
		"freeze":
			var fz := find_unit(t)
			if fz.is_empty():
				return
			# thaws at the end of its owner's next turn
			var until: int = turn + (2 if fz["owner"] == active else 1)
			fz["frozen"] = maxi(int(fz.get("frozen", 0)), until)
			_emit({"type": "freeze", "uid": t})
		"summon":
			_summon_effect(p, e)
		"mill", "mill_pick":
			_mill(p, int(e.get("amount", 1)))
		"revive":
			_revive(p, int(e.get("max_cost", 99)))
		"revive_self":
			_revive_self(p, e)
		"destroy":
			# not damage: ignores size and Escudo, but Indestrutível stops it (only removal from the game, e.g. banish, bypasses it)
			var doomed := find_unit(t)
			if doomed.is_empty() or has_kw(doomed, "indestrutivel"):
				return
			doomed["damage"] = 1000000
			_emit({"type": "destroy", "uid": t})
		"sacrifice":
			# kills one of the caster's own units; "then" effects run only if it happened
			var victim := find_unit(t)
			if victim.is_empty() or victim["owner"] != p:
				return
			_sac_atk = atk_of(victim) # last known attack, buffs included
			victim["damage"] = victim["hp"] + int(victim.get("bonus_hp", 0))
			_emit({"type": "sacrifice", "player": p, "uid": t})
			_run_effects(p, e.get("then", []), "", _chosen2, 0)
		"buff":
			var c := find_unit(t)
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
				elif kw == "escudo_feitico":
					c["spell_shield"] = true
				elif not c["keywords"].has(kw):
					c["keywords"].append(kw)
					if e.get("temp", false):
						c["temp_keywords"].append(kw)
			_emit({"type": "buff", "uid": t, "atk": e.get("atk", 0), "hp": e.get("hp", 0), "keywords": e.get("keywords", [])})

## Top cards of the deck go to the graveyard (no fatigue when the deck runs out).
func _mill(p: int, n: int) -> void:
	var pl: Dictionary = players[p]
	var cards: Array = []
	_milled = []
	for i in n:
		if pl["deck"].is_empty():
			break
		var c: Dictionary = pl["deck"].pop_back()
		pl["graveyard"].append({"uid": c["uid"], "card_id": c["card_id"]})
		_milled.append({"uid": c["uid"], "card_id": c["card_id"]})
		cards.append(c["card_id"])
	if not cards.is_empty():
		_emit({"type": "mill", "player": p, "cards": cards})

## Returns a random unit card (cost <= max_cost) from the graveyard to the board.
func _revive(p: int, max_cost: int) -> void:
	if players[p]["board"].size() >= BOARD_LIMIT:
		return
	var pool: Array = []
	for e in players[p]["graveyard"]:
		var cd := CardDB.card(e["card_id"])
		if cd["type"] == "unit" and int(cd["cost"]) <= max_cost:
			pool.append(e)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	players[p]["graveyard"].erase(pick)
	_emit({"type": "revive", "player": p, "card_id": pick["card_id"]})
	_summon(p, pick["card_id"], _uid(), false, 0)

## Ao Morrer: the dying unit comes back to the board as a new instance (so it no longer takes
## part in the combat it died in), with base atk/hp changed by e["atk"]/e["hp"] (usually negative)
## relative to what it had when it died. It does not return if atk or hp would reach 0.
## While on the board it is not a graveyard card, so its entry leaves the graveyard.
func _revive_self(p: int, e: Dictionary) -> void:
	if _dying.is_empty() or _dying["legendary"]:
		return
	var atk: int = int(_dying["atk"]) + int(e.get("atk", 0))
	var hp: int = int(_dying["hp"]) + int(e.get("hp", 0))
	if atk <= 0 or hp <= 0 or players[p]["board"].size() >= BOARD_LIMIT:
		return
	for entry in players[p]["graveyard"]:
		if entry["uid"] == _dying["uid"]:
			players[p]["graveyard"].erase(entry)
			break
	var over: Dictionary = (_dying.get("over", {}) as Dictionary).duplicate()
	over["atk"] = atk
	over["hp"] = hp
	_emit({"type": "revive", "player": p, "card_id": _dying["card_id"]})
	_summon(p, _dying["card_id"], _uid(), false, 0, over)

## Returns damage actually dealt. source is the dealing unit or {}.
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
		var c := find_unit(t)
		if c.is_empty():
			return 0
		if has_kw(c, "indestrutivel"):
			return 0 # damage is always 0 against it (Escudo isn't consumed)
		if c["shield"]:
			c["shield"] = false
			_emit({"type": "shield_break", "uid": t, "src": source.get("uid", 0)})
			return 0
		c["damage"] += amount
		dealt = amount
		_emit({"type": "damage", "uid": t, "amount": amount, "src": source.get("uid", 0)})
		# Mar que Retorna: the marked unit survived damage -> its owner draws once
		if c.get("tide_mark", false) and hp_left(c) > 0:
			c.erase("tide_mark")
			_emit({"type": "tide_draw", "uid": t, "player": c["owner"]})
			_draw(c["owner"], 1)
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

## Fadiga: damage of the next draw from an empty deck. Doubles each time: 2, 4, 8, 16…
func fatigue_next(p: int) -> int:
	return 2 << int(players[p]["fatigue"])

func _draw(p: int, n: int) -> void:
	var pl: Dictionary = players[p]
	for i in n:
		if pl["deck"].is_empty():
			var dmg := fatigue_next(p)
			pl["fatigue"] += 1
			_emit({"type": "fatigue", "player": p, "amount": dmg})
			_deal_damage(LEADER_UID[p], dmg, {})
			continue
		var c: Dictionary = pl["deck"].pop_back()
		pl["hand"].append(c)
		_emit({"type": "draw", "player": p, "uid": c["uid"]})

## Dead attackers deal nothing; a blocked attacker whose blocker died hits nothing
## (Sobrepujança: all of it goes to the leader); a blocker whose attacker died deals nothing.
func _resolve_combat() -> void:
	var defender := opponent(active)
	window = ""
	_emit({"type": "combat_damage"})
	_combat_damage = true
	_prune_attackers()
	var pairs: Array = []
	for a in attackers:
		pairs.append([a, blocks.get(a, 0)])
	for first_strike in [true, false]:
		for pair in pairs:
			var att := find_unit(pair[0])
			var blk := find_unit(pair[1]) if pair[1] != 0 else {}
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
	_combat_damage = false
	_end_combat()

## Moves dead units out, fires Ao Morrer, checks leaders. Loops until stable.
## Deaths resolve active player first (APNAP), then the opponent.
func _check_state() -> void:
	var changed := true
	while changed:
		changed = false
		_refresh_scaling()
		for p in [active, opponent(active)]:
			for c in players[p]["board"].duplicate():
				if hp_left(c) <= 0:
					players[p]["board"].erase(c)
					changed = true
					_emit({"type": "death", "uid": c["uid"], "player": p})
					_release_equipment(c)
					if c["legendary"]:
						_legendary_leaves(p)
					else:
						players[p]["graveyard"].append({"uid": c["uid"], "card_id": c["card_id"]})
					_dying = c
					_announce(c, card_of(c)["effects"], "on_death")
					_run_effects(p, card_of(c)["effects"], "on_death", 0, c["uid"])
					_dying = {}
					# Aliado Morre fires on every death, even if the unit comes right back (Revivente, Fênix)
					# or a Legendary returns to its zone.
					for ally in players[p]["board"].duplicate():
						if players[p]["board"].has(ally):
							_fire(ally, "on_ally_death", c["uid"])
					_fire_leader_passive(p, "on_ally_death")
	var dead := [players[0]["leader_hp"] <= 0, players[1]["leader_hp"] <= 0]
	if dead[0] or dead[1]:
		winner = 2 if dead[0] and dead[1] else (1 if dead[0] else 0)
		phase = "over"
		_emit({"type": "game_over", "winner": winner})

## Leader passive ("passive": true in the leader's ability): runs its effects when `trigger` happens,
## once per turn if "once_per_turn". Depth-capped like unit triggers.
func _fire_leader_passive(p: int, trigger: String) -> void:
	var ab: Dictionary = CardDB.leader(players[p]["leader_id"])["ability"]
	if not ab.get("passive", false) or ab.get("trigger", "") != trigger or _trigger_depth >= 4:
		return
	if ab.get("own_turn_only", false) and active != p:
		return
	if ab.get("once_per_turn", false) and players[p]["passive_used"]:
		return
	players[p]["passive_used"] = true
	_emit({"type": "passive", "player": p})
	_trigger_depth += 1
	_run_effects(p, ab["effects"], "", 0, 0)
	_trigger_depth -= 1

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
			c.erase("tide_mark")
			if c.has("frozen") and turn >= int(c["frozen"]):
				c.erase("frozen")
				_emit({"type": "thaw", "uid": c["uid"]})
	_emit({"type": "end_turn", "player": active})
	_start_turn(opponent(active), true)

func _start_turn(p: int, draw: bool) -> void:
	active = p
	priority = p
	summon_window = false
	_summon_pending = false
	turn += 1
	phase = "main"
	var pl: Dictionary = players[p]
	pl["reserve"] = mini(RESERVE_CAP, int(pl["reserve"]) + int(pl["momentum"])) # bank what went unspent
	pl["max_momentum"] = min(MOMENTUM_CAP, pl["max_momentum"] + 1)
	pl["momentum"] = pl["max_momentum"]
	if p != first and turn <= SECOND_BONUS_TURNS * 2:
		# going second: +1 Reserve on each of the first SECOND_BONUS_TURNS turns, and +1 Momentum on the very first
		pl["reserve"] = mini(RESERVE_CAP, int(pl["reserve"]) + 1)
		if turn == 2:
			pl["momentum"] += 1
	for i in 2:
		var q: Dictionary = players[i]
		# once_per_turn: refreshed every turn, so instants can be used on either turn.
		# once_per_cycle: refreshed only when its owner's own turn starts.
		if i == p or not CardDB.leader(q["leader_id"])["ability"].get("once_per_cycle", false):
			q["ability_used"] = false
		q["passive_used"] = false
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
## "self" is the unit whose effect is running (works from Ao Morrer). Overrides stick to the instance.
func _summon_effect(p: int, e: Dictionary) -> void:
	var id: String = e.get("card", "self")
	if id == "self":
		if _dying.is_empty():
			return
		id = _dying["card_id"]
	if players[p]["board"].size() >= BOARD_LIMIT:
		return
	_summon(p, id, _uid(), false, 0, e.get("overrides", {}))
