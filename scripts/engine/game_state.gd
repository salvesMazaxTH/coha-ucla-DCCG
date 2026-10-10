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
const INTIMIDATE_ATK := 3 ## Intimidacao: blockers with this ATK or less cannot block
const SECOND_BONUS_TURNS := 2 ## the second player's first turns that start with +1 Reserve (the first also with +1 Momentum)
const REQUIEM_EXTRA_COST := 2 ## Réquiem: a spell cast from the graveyard costs this much more, then is banished

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
## Item: {sid, player, kind:"card"|"ability"|"unit_ability", uid, card_id, target, speed}
## ("unit_ability" = a unit's Ao Ativar; uid is the unit, card_id its card.)
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
var rng := RandomNumberGenerator.new()
var _next_uid := 1
var _events: Array = []
## Triggers that happened but have not resolved yet (PendingTrigger), oldest first.
var _pending: Array = []
var _bus: TriggerBus ## built on first use (RemoteState never runs GameState._init)
var _stack_system: StackSystem ## built on first use, like _bus
var _combat_system: CombatSystem ## built on first use, like _bus
const EVENT_CAP := 300 ## events one action may produce before triggers/effects stop resolving
const MAX_TRIGGERS_PER_ACTION := 60 ## queued triggers resolved in one go, so trigger loops always end
## Cards played from hand while they wait on the stack (uid -> Card); stack items themselves stay plain dicts.
var _stack_cards: Dictionary = {}

func _init(deck_a: String, deck_b: String, seed_value: int = 0, first_player: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	first = first_player
	for i in 2:
		players.append(_make_player(i, [deck_a, deck_b][i]))
	for i in 2:
		_draw(i, START_HAND)
	_events.clear()

## The stack and priority windows (built on first use, like bus()).
func stack_system() -> StackSystem:
	if _stack_system == null:
		_stack_system = StackSystem.new(self)
	return _stack_system

## Attack, block and damage resolution (built on first use).
func combat_system() -> CombatSystem:
	if _combat_system == null:
		_combat_system = CombatSystem.new(self)
	return _combat_system

## Delivers GameEvents to the cards that react to them (own triggers and "listen").
func bus() -> TriggerBus:
	if _bus == null:
		_bus = TriggerBus.new(self)
	return _bus

func _make_player(i: int, deck_id: String) -> Dictionary:
	var d := DeckDB.get_deck(deck_id)
	var ld := CardDB.leader(d["leader"])
	var deck: Array = []
	for id in d["cards"]:
		if id == ld["legendary"]:
			continue
		for n in int(d["cards"][id]):
			deck.append(Card.new(_uid(), id, i, "deck"))
	_shuffle(deck)
	return {
		"index": i, "deck_id": deck_id, "leader_id": d["leader"],
		"leader_hp": int(ld["hp"]), "leader_max": int(ld["hp"]),
		"momentum": 0, "max_momentum": 0, "reserve": 0,
			"saved_momentum": 0, "idle_turns": 0, "next_momentum": 0, "leaked": 0, "unspent": 0,
		"deck": deck, "hand": [], "board": [], "graveyard": [], "banished": [],
		"legendary": {"card_id": ld["legendary"], "in_zone": true, "casts": 0},
		"ability_used": false, "passive_used": false, "attacked": false, "fatigue": 0, "mulligan_done": false,
		"played_two": false,
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

## Triggers and effects stop resolving once a Leader is down (combat strikes still land, so the overkill shows,
## but nothing new fires off it) or when one action has already produced EVENT_CAP events (runaway chain).
func _chain_stopped() -> bool:
	return _events.size() >= EVENT_CAP or players[0]["leader_hp"] <= 0 or players[1]["leader_hp"] <= 0

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

## The unit with this uid on either board, or null.
func find_unit(uid: int) -> Card:
	for p in players:
		for c: Card in p["board"]:
			if c.uid == uid:
				return c
	return null

## The card with this uid in any zone of either player (board, hand, deck, graveyard, banished), or null.
func find_card(uid: int) -> Card:
	for p in players:
		for zone in TriggerBus.ZONES:
			for c: Card in p[zone]:
				if c.uid == uid:
					return c
	return null

## Moves a card to another zone (the caller takes it out of its old array and puts it in the new one).
## The single place a card changes zone, so later "goes to the graveyard" hooks live here.
func _move(c: Card, to_zone: String) -> void:
	var from_zone := c.zone
	c.zone = to_zone
	if to_zone != "hand":
		c.discount = 0
	var moved := GameEvent.new("card_moved", c.owner, c)
	moved.data = {"from": from_zone, "to": to_zone}
	bus().emit(moved)

func card_of(c: Card) -> Dictionary:
	return c.data()

func has_kw(c: Card, kw: String) -> bool:
	return c.has_kw(kw)

func atk_of(c: Card) -> int:
	return c.atk_total()

func hp_left(c: Card) -> int:
	return c.hp_left()

## Unit cards in a player's graveyard.
func graveyard_units(p: int) -> int:
	var n := 0
	for e: Card in players[p]["graveyard"]:
		if CardDB.card(e.card_id)["type"] == "unit":
			n += 1
	return n

## Recomputes the "constante" effects of board units. Action "scale" gives
## atk/hp per counted thing (e.g. +2/+2 per unit card in the own graveyard).
func _refresh_scaling() -> void:
	for p in 2:
		for c: Card in players[p]["board"]:
			var b := scale_bonus(p, card_of(c))
			c.bonus_atk = b.x
			c.bonus_hp = b.y
			c.has_bonus = true

## Atk/hp a card's "constante" scale effects would give it under player p right
## now.
func scale_bonus(p: int, cd: Dictionary) -> Vector2i:
	var out := Vector2i.ZERO
	for e in cd.get("effects", []):
		if e.get("trigger", "") != "constante" or e.get("action", "") != "scale":
			continue
		var n := _scale_count(p, e)
		out += Vector2i(n * int(e.get("atk", 0)), n * int(e.get("hp", 0)))
	return out

func _scale_count(p: int, e: Dictionary) -> int:
	match e.get("per", ""):
		"own_graveyard_units": return graveyard_units(p)
		"enemy_graveyard_units": return graveyard_units(opponent(p))
	return 0

## What a "scale" card counts right now (shown in its text off the board), or -1 if it has none.
func scale_count(p: int, cd: Dictionary) -> int:
	for e in cd.get("effects", []):
		if e.get("trigger", "") == "constante" and e.get("action", "") == "scale":
			return _scale_count(p, e)
	return -1

## The Encarnação left the board by dying or being banished (a return to hand doesn't count).
## If its next cast would cost more than the Momentum cap, it retires: it goes to the bottom of
## the deck as a normal card at its base cost, for good. Otherwise it goes back to the Santuário.
func _legendary_leaves(p: int) -> void:
	var l: Dictionary = players[p]["legendary"]
	if legendary_cost(p) <= MOMENTUM_CAP:
		l["in_zone"] = true
		return
	l["retired"] = true
	players[p]["deck"].insert(0, Card.new(_uid(), l["card_id"], p, "deck")) # draws pop the back
	_emit({"type": "legendary_retired", "player": p, "card_id": l["card_id"]})

func legendary_cost(p: int) -> int:
	var l: Dictionary = players[p]["legendary"]
	return cost_of(p, CardDB.card(l["card_id"])) + COMMANDER_TAX * int(l["casts"])

## Congelada: can't attack or block until the end of its owner's next turn.
func is_frozen(c: Card) -> bool:
	return c.is_frozen()

func can_attack(c: Card) -> bool:
	return not is_frozen(c) and not c.exhausted and (not c.sick or has_kw(c, "impeto")) and atk_of(c) > 0

func can_block(blocker: Card, attacker: Card) -> bool:
	if is_frozen(blocker) or has_kw(blocker, "nao_bloqueia"):
		return false
	if has_kw(attacker, "voo") and not (has_kw(blocker, "voo") or has_kw(blocker, "longo_alcance")):
		return false
	if has_kw(attacker, "furtividade") and not (has_kw(blocker, "furtividade") or has_kw(blocker, "vigilancia")):
		return false
	if has_kw(attacker, "intimidacao") and atk_of(blocker) <= INTIMIDATE_ATK:
		return false
	return true

## Effect spec of a card/ability that needs a chosen target, or "" if none.
func target_spec(effects: Array) -> String:
	for e in effects:
		if e.get("target", "") in ["enemy_unit", "ally_unit", "other_ally_unit", "any_unit", "any", "enemy_stack"]:
			return e["target"]
	return ""

## Second target a card needs on top of its first (e.g. the damage target after the sacrifice), or "".
## Declared on a "then" effect with "pick": true, or on a top-level effect with "pick2": true
## (Relâmpagos Gêmeos; "same_target_ok" on the card lets both picks be the same target).
## A "fight" effect names its second unit with "second_target" instead.
func second_spec(cd: Dictionary) -> String:
	for e in cd.get("effects", []):
		if e.get("pick2", false):
			return e["target"]
		if e.has("second_target"):
			return e["second_target"]
		for t in e.get("then", []):
			if t.get("pick", false):
				return t["target"]
	return ""

## True when a spell would do nothing right now (only revive effects, and no unit to bring back).
func is_dud(p: int, cd: Dictionary) -> bool:
	var effects: Array = cd.get("effects", [])
	if effects.is_empty():
		return false
	for e in effects:
		if e.get("action") != "revive":
			return false
		if players[p]["board"].size() < BOARD_LIMIT:
			for grave: Card in players[p]["graveyard"]:
				var gd := CardDB.card(grave.card_id)
				if gd["type"] == "unit" and int(gd["cost"]) <= int(e.get("max_cost", 99)):
					return false
	return true

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

## Momentum cost of a card for player p, after its cost_reduction effects (no trigger: they apply
## wherever the card is, not only on the board, so they are not "Constante")
## (e.g. per: "saved_momentum" =
## per Momentum that leaked past the Reserva by the start of the owner's turns, over the whole game; "idle_turns" =
## per owner turn that started with Momentum leaking past the Reserva; "unspent_momentum" = a flat "amount" off when
## at least "threshold" plain Momentum was left over from the previous turn). Never below 0, or below the effect's "min_cost".
func cost_of(p: int, cd: Dictionary, card: Card = null) -> int:
	var c := int(cd["cost"]) - (card.discount if card != null else 0) # per-copy discount (Tecnomante); stacks with cost_reduction, same "min_cost" floor
	if card != null:
		c += card.cost_mod # permanent per-copy change (modify_cost), kept in every zone
	var floor_cost := 0
	for e in cd.get("effects", []):
		if e.get("action", "") != "cost_reduction":
			continue
		var n := 0
		match e.get("per", ""):
			"saved_momentum": n = int(players[p]["saved_momentum"])
			"idle_turns": n = int(players[p]["idle_turns"])
			"unspent_momentum": n = 1 if int(players[p]["unspent"]) >= int(e.get("threshold", 1)) else 0
		c -= n * int(e.get("amount", 1))
		floor_cost = maxi(floor_cost, int(e.get("min_cost", 0)))
	var requiem_extra := REQUIEM_EXTRA_COST if card != null and card.zone == "graveyard" else 0
	return maxi(c, floor_cost) + requiem_extra

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
			for c: Card in theirs: out.append(c.uid)
		"ally_unit":
			for c: Card in mine: out.append(c.uid)
		"other_ally_unit":
			for c: Card in mine:
				if c.uid != self_uid: out.append(c.uid)
		"any_unit":
			for c: Card in mine + theirs: out.append(c.uid)
		"any":
			for c: Card in mine + theirs: out.append(c.uid)
			out.append(LEADER_UID[opponent(p)])
		"enemy_stack":
			for it in stack:
				if it["player"] != p and not stack_system().is_uncounterable(it): out.append(it["sid"])
	return out

## Targets a card from hand can be played on right now (counters filter by reach and Momentum).
func card_targets(p: int, cd: Dictionary, inst: Card = null) -> Array:
	var spec := card_spec(cd)
	var out := valid_targets(p, spec)
	if spec != "enemy_stack":
		return out
	var ok: Array = []
	for sid in out:
		var x := counter_extra(cd, sid)
		if x >= 0 and cost_of(p, cd, inst) + x <= budget(p, _is_spell(cd)):
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
	var inst := _castable_card(p, hand_uid)
	if inst == null:
		return false
	var cd := CardDB.card(inst.card_id)
	if cost_of(p, cd, inst) > budget(p, _is_spell(cd)):
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
	return spec == "" or not card_targets(p, cd, inst).is_empty()

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

## Unit Ao Ativar (cards.json unit field "activated": {cost, speed, effects, once_per_turn, exhaust}):
## paid like an ability (Reserva counts) and put on the stack, so it can be answered and countered.
## "exhaust": the unit must be ready (not exhausted) and becomes exhausted, so it cannot attack
## that turn (and an attacker cannot activate). Exhaustion never stops it from blocking.
func can_activate(p: int, uid: int) -> bool:
	var c := find_unit(uid)
	if c == null or c.owner != p:
		return false
	var ab: Dictionary = card_of(c).get("activated", {})
	if ab.is_empty() or not can_cast_speed(p, speed_of(ab)) or int(ab["cost"]) > budget(p, true):
		return false
	if ab.get("once_per_turn", false) and c.activated_turn == turn:
		return false
	if ab.get("exhaust", false) and c.exhausted:
		return false
	var spec := target_spec(ab["effects"])
	return spec == "" or not valid_targets(p, spec, uid).is_empty()

## Transformar (cards.json unit field "transform": {into, cost}) (cards.json unit field {into, cost}): Lento, paid like an ability
## (Reserva counts), and it never uses the stack, so it cannot be answered or countered.
func can_transform(p: int, uid: int) -> bool:
	var c := find_unit(uid)
	if c == null or c.owner != p or not _sorcery_time(p):
		return false
	var tf: Dictionary = card_of(c).get("transform", {})
	return not tf.is_empty() and int(tf["cost"]) <= budget(p, true)

func _hand_card(p: int, uid: int) -> Card:
	for c: Card in players[p]["hand"]:
		if c.uid == uid:
			return c
	return null

## True for a spell with Réquiem (it can be cast from the graveyard).
func is_requiem(c: Card) -> bool:
	var cd := CardDB.card(c.card_id)
	return cd["type"] == "spell" and (cd.get("keywords", []) as Array).has("requiem")

## The card a play action with this uid refers to: from the hand, or a Réquiem spell in the graveyard.
func _castable_card(p: int, uid: int) -> Card:
	var from_hand := _hand_card(p, uid)
	if from_hand != null:
		return from_hand
	for c: Card in players[p]["graveyard"]:
		if c.uid == uid and is_requiem(c):
			return c
	return null

## Réquiem spells in p's graveyard that p could cast right now, newest first.
func requiem_cards(p: int) -> Array:
	var out: Array = []
	for c: Card in players[p]["graveyard"]:
		if is_requiem(c) and can_play(p, c.uid):
			out.append(c)
	out.reverse()
	return out

## Banishes a Réquiem spell once its cast is over (resolved, fizzled or countered).
func _banish_requiem(c: Card) -> void:
	players[c.owner]["banished"].append(c)
	_move(c, "banished")
	_emit({"type": "banish", "uid": c.uid, "player": c.owner, "card_id": c.card_id})

# ---------------------------------------------------------------- actions

## Put back up to MULLIGAN_MAX cards and redraw that many.
func mulligan(p: int, hand_uids: Array) -> Array:
	if phase != "mulligan" or p != decider() or hand_uids.size() > MULLIGAN_MAX:
		return []
	var pl: Dictionary = players[p]
	var back: Array = []
	for uid in hand_uids:
		var c := _hand_card(p, uid)
		if c == null:
			return []
		back.append(c)
	for c: Card in back:
		pl["hand"].erase(c)
		pl["deck"].append(c)
		_move(c, "deck")
	_shuffle(pl["deck"])
	_draw(p, back.size())
	pl["mulligan_done"] = true
	_emit({"type": "mulligan", "player": p, "count": back.size()})
	if players[0]["mulligan_done"] and players[1]["mulligan_done"]:
		_start_turn(first, false)
	return _flush()

## slot: where a unit enters the board (0 = leftmost, -1 = rightmost); ignored for spells.
func play_card(p: int, hand_uid: int, target: int = 0, target2: int = 0, slot: int = -1) -> Array:
	if not can_play(p, hand_uid):
		return []
	var inst := _castable_card(p, hand_uid)
	var from_graveyard := inst.zone == "graveyard" # Réquiem
	var cd := CardDB.card(inst.card_id)
	var sacrifice: bool = cd["type"] == "unit" and cd.get("cost_sacrifice", false)
	var spec := target_spec(cd["effects"])
	if sacrifice:
		if not valid_targets(p, "ally_unit").has(target):
			return []
	elif cd["type"] != "unit" and spec != "" and not card_targets(p, cd, inst).has(target):
		return []
	var spec2 := second_spec(cd)
	if spec2 != "" and ((target2 == target and not cd.get("same_target_ok", false)) or not valid_targets(p, spec2).has(target2)):
		return []
	var pl: Dictionary = players[p]
	_pay(p, cost_of(p, cd, inst) + (counter_extra(cd, target) if spec == "enemy_stack" else 0), _is_spell(cd))
	pl["graveyard" if from_graveyard else "hand"].erase(inst)
	if int(cd.get("cost", 0)) == 2 or int(cd.get("atk", 0)) == 2 or int(cd.get("hp", 0)) == 2:
		pl["played_two"] = true # Rusco: a card with cost, ATK or HP exactly 2 this turn
	_move(inst, "")
	var play_event := {"type": "play", "player": p, "uid": hand_uid, "card_id": inst.card_id}
	if from_graveyard:
		play_event["requiem"] = true
	_emit(play_event)
	if sacrifice:
		# additional cost: the chosen ally dies first (its Ao Morrer / Aliado Morre resolve before the card enters)
		var sacrificed_index: int = pl["board"].find(find_unit(target))
		if sacrificed_index >= 0 and sacrificed_index < slot:
			slot -= 1 # the slot was picked with the sacrificed unit still on the board
		find_unit(target).damage = 1000000
		_emit({"type": "sacrifice", "player": p, "uid": target})
		_check_state()
		if phase == "over":
			return _flush()
		if pl["board"].size() >= BOARD_LIMIT: # a death effect refilled the slot
			pl["graveyard"].append(inst)
			_move(inst, "graveyard")
			stack_system().settle()
			return _flush()
	if cd["type"] == "unit":
		_summon(p, inst, false, 0, {}, true, slot)
		_check_state()
		stack_system().open_summon_window(p)
	else:
		_stack_cards[hand_uid] = inst
		_move(inst, "stack")
		stack_system().push(p, "card", hand_uid, inst.card_id, target, speed_of(cd), target2, from_graveyard)
	stack_system().settle()
	return _flush()

func cast_legendary(p: int, _target: int = 0, slot: int = -1) -> Array:
	if not can_cast_legendary(p):
		return []
	var pl: Dictionary = players[p]
	pl["momentum"] -= legendary_cost(p)
	pl["legendary"]["in_zone"] = false
	pl["legendary"]["casts"] += 1
	var c := Card.new(_uid(), pl["legendary"]["card_id"], p)
	_emit({"type": "play", "player": p, "uid": c.uid, "card_id": c.card_id, "legendary": true})
	_summon(p, c, true, 0, {}, true, slot)
	_check_state()
	stack_system().open_summon_window(p)
	stack_system().settle()
	return _flush()

func activate(p: int, uid: int, target: int = 0) -> Array:
	if not can_activate(p, uid):
		return []
	var c := find_unit(uid)
	var ab: Dictionary = card_of(c)["activated"]
	var spec := target_spec(ab["effects"])
	if spec != "" and not valid_targets(p, spec, uid).has(target):
		return []
	_pay(p, int(ab["cost"]), true)
	c.activated_turn = turn
	if ab.get("exhaust", false):
		c.exhausted = true
	_emit({"type": "trigger", "uid": uid, "player": p, "card_id": c.card_id, "trigger": "on_activate"})
	stack_system().push(p, "unit_ability", uid, c.card_id, target, speed_of(ab))
	stack_system().settle()
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
	stack_system().push(p, "ability", 0, "", target, speed_of(ab))
	stack_system().settle()
	return _flush()

## The unit becomes its "transform" card in place (same uid, keeps damage, exhaustion and
## equipment; base stats and keywords come from the new card), then its Ao Entrar fires.
func transform(p: int, uid: int) -> Array:
	if not can_transform(p, uid):
		return []
	var c := find_unit(uid)
	var tf: Dictionary = card_of(c)["transform"]
	_pay(p, int(tf["cost"]), true)
	_emit({"type": "trigger", "uid": uid, "player": p, "card_id": c.card_id, "trigger": "transform"})
	var from: String = c.card_id
	var cd := CardDB.card(tf["into"])
	var kws: Array = cd.get("keywords", []).duplicate()
	c.card_id = tf["into"]
	c.over = {}
	c.used_turn = {}
	c.atk = int(cd["atk"])
	c.hp = int(cd["hp"])
	c.shield = c.shield or kws.has("escudo")
	c.spell_shield = c.spell_shield or kws.has("escudo_feitico")
	kws.erase("escudo")
	kws.erase("escudo_feitico")
	c.keywords = kws
	_emit({"type": "transform", "player": p, "uid": uid, "from": from, "card_id": tf["into"]})
	_announce(c, cd["effects"], "on_enter")
	var target := uid if target_spec(cd["effects"]) == "ally_unit" else 0
	_run_effects(_enter_context(p, uid, target), cd["effects"])
	_check_state()
	stack_system().settle()
	return _flush()

## Gives up priority. With items on the stack, everything resolves (newest first);
## in an empty combat window the combat moves on to the next window.
func pass_priority(p: int) -> Array:
	if phase not in ["main", "combat"] or p != priority:
		return []
	if stack.is_empty() and phase == "main" and not summon_window:
		return [] # nothing to pass: end the turn instead
	_emit({"type": "pass", "player": p})
	stack_system().pass_once()
	stack_system().settle()
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
		if _hand_card(p, uid) == null:
			return []
	for uid in hand_uids:
		var c := _hand_card(p, uid)
		players[p]["hand"].erase(c)
		# Banished, not discarded: the card never reaches the graveyard (hidden from the opponent).
		players[p]["banished"].append(c)
		_move(c, "banished")
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
		_emit({"type": "enter_skip", "player": p, "uid": uid, "card_id": c.card_id})
		var rest: Array = []
		for e in effects:
			if target_spec([e]) == "":
				rest.append(e)
		effects = rest
	_announce(c, effects, "on_enter")
	_run_effects(_enter_context(p, uid, target), effects)
	_check_state()
	stack_system().after_search()
	stack_system().settle()
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
			if grave[i].uid == card_uid:
				gi = i
				break
		if gi < 0:
			return []
		var taken: Card = grave[gi]
		grave.remove_at(gi)
		players[p]["hand"].append(taken)
		_move(taken, "hand")
		pending_search.clear()
		phase = _search_return
		_emit({"type": "search_take", "player": p, "uid": card_uid, "card_id": chosen["card_id"]})
		_resolve_stack()
		_check_state() # resumes the triggers that waited for this choice
		stack_system().after_search()
		stack_system().settle()
		return _flush()
	var deck: Array = players[p]["deck"]
	var found: Card = null
	for c: Card in deck:
		if c.uid == card_uid:
			found = c
			break
	if found == null:
		return []
	deck.erase(found)
	players[p]["hand"].append(found)
	_move(found, "hand")
	var look: bool = pending_search.get("look", false)
	var reshuffle: bool = pending_search.get("shuffle", false)
	if look and not reshuffle:
		# the cards not taken go to the bottom of the deck, unrevealed
		for c in options:
			if int(c["uid"]) == card_uid:
				continue
			for d: Card in deck:
				if d.uid == int(c["uid"]):
					deck.erase(d)
					deck.push_front(d)
					break
	else:
		_shuffle(deck)
	pending_search.clear()
	phase = _search_return
	_emit({"type": "search_take", "player": p, "uid": card_uid, "card_id": chosen["card_id"]})
	_emit({"type": "look_bottom" if look and not reshuffle else "search_shuffle", "player": p})
	_resolve_stack() # a search opened mid-resolution: finish the rest of the stack
	_check_state() # resumes the triggers that waited for this choice
	stack_system().after_search()
	stack_system().settle()
	return _flush()

# ---------------------------------------------------------------- stack & combat (see systems/)

## attacks: Dictionary attacker_uid -> provoked enemy uid (0 when none).
func declare_attack(p: int, attacks: Dictionary) -> Array:
	return combat_system().declare_attack(p, attacks)

## blocks: Dictionary attacker_uid -> blocker_uid.
func declare_blocks(p: int, picks: Dictionary) -> Array:
	return combat_system().declare_blocks(p, picks)

## Momentum cost of a spell/ability on the stack.
func stack_cost(item: Dictionary) -> int:
	return stack_system().stack_cost(item)

## Extra Momentum a counter must pay to hit stack item `sid` (-1 when out of reach).
func counter_extra(cd: Dictionary, sid: int) -> int:
	return stack_system().counter_extra(cd, sid)

func _resolve_stack() -> void:
	stack_system().resolve_stack()

func _counter(p: int, sid: int) -> void:
	stack_system().counter(p, sid)

func _release_equipment(c: Card) -> void:
	stack_system().release_equipment(c)

## Can p do anything right now besides passing?
func _has_play(p: int) -> bool:
	return stack_system().has_play(p)

## Turns p's auto-pass on or off. Turning it on while p holds an unusable window passes it.
func set_auto_pass(p: int, on: bool) -> Array:
	auto_pass[p] = on
	if on:
		stack_system().settle()
	return _flush()

# ---------------------------------------------------------------- internals

## ask: played from hand/Santuário, so a targeted Ao Entrar waits for its owner's pick
## (phase "enter_target") instead of resolving right away.
## slot: board position to enter at (0 = leftmost); -1 or past the end = rightmost. Position
## matters for adjacency (Armadura from neighbours, "random_enemy_and_adjacent", ...).
func _summon(p: int, c: Card, legendary: bool, target: int, over: Dictionary = {}, ask := false, slot := -1) -> void:
	var uid := c.uid
	var card_id := c.card_id
	c.owner = p
	c.enter_board(legendary, over)
	var cd := c.data()
	_move(c, "board")
	var board: Array = players[p]["board"]
	if slot < 0 or slot >= board.size():
		board.append(c)
	else:
		board.insert(slot, c)
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
	_run_effects(_enter_context(p, uid, target), cd["effects"])

## Context for a unit's Ao Entrar effects; `target` is the ally the player chose (0 if none).
func _enter_context(p: int, uid: int, target: int) -> EffectContext:
	var context := EffectContext.new(self, p, "on_enter")
	context.self_uid = uid
	context.chosen_target = target
	return context

## Tells the UI that unit c's `trigger` went off, so it can show where the effects that
## follow come from. Only when at least one of `effects` actually runs for that trigger.
func _announce(c: Card, effects: Array, trigger: String) -> void:
	for e in effects:
		var entry_trigger: String = e.trigger if e is Effect else e.get("trigger", "")
		if entry_trigger == trigger:
			_emit({"type": "trigger", "uid": c.uid, "player": c.owner, "card_id": c.card_id, "trigger": trigger})
			return

## Fires a unit's own trigger. Depth-capped so on_damaged chains cannot loop forever.
func _fire(c: Card, trigger: String, other_uid: int = 0) -> void:
	if c == null:
		return
	var event := GameEvent.new(trigger, c.owner, c)
	event.other_uid = other_uid
	bus().emit(event)

## Gatilhos (cards.json "triggers"): on_play, on_enter, on_death, on_attack, on_block,
## on_blocked, on_damaged, on_hit_leader, on_turn_start, on_turn_end. "constante" never fires
## here: it is continuous and handled by _refresh_scaling.
## other_uid is the opposing unit in combat triggers (blocker, attacker, damage source).
func _run_effects(context: EffectContext, effects: Array) -> void:
	for entry in effects:
		# entries are Effect objects (raw card dictionaries are parsed on the fly)
		var effect: Effect = entry if entry is Effect else EffectRegistry.parse(entry)
		if _chain_stopped():
			return
		if context.trigger != "" and effect.trigger != context.trigger:
			continue
		if context.trigger == "" and effect.listen != "":
			continue # listening effects only run when their event happens
		if effect.is_static() or effect.action == "cost_reduction":
			continue
		if effect.condition != null and not effect.condition.check(context):
			continue
		for target_uid in effect.target.resolve(context, effect):
			effect.apply_to(context, target_uid)
		if effect.opens_choice() and effect.trigger == context.trigger:
			effect.open_choice(context)

## Effects a card has while it sits in the deck ("deck_effects": [{trigger, if, action}]).
## "summon_self": that copy leaves the deck and enters its owner's board (no shuffle, nothing is
## drawn). Optional "cost": paid on the way in like an ability (Reserva first, then Momentum); if it
## can't be paid, or the board is full, the copy stays in the deck.
func _fire_deck_effects(p: int, trigger: String) -> void:
	for c in players[p]["deck"].duplicate():
		for e in CardDB.card(c.card_id).get("deck_effects", []):
			if e.get("trigger", "") != trigger:
				continue
			var condition := ConditionRegistry.parse(e.get("if", ""))
			if condition != null and not condition.check(EffectContext.new(self, p, trigger)):
				continue
			var fee := int(e.get("cost", 0))
			if e.get("action", "") == "summon_self" and players[p]["deck"].has(c) and players[p]["board"].size() < BOARD_LIMIT and budget(p, true) >= fee:
				_pay(p, fee, true)
				players[p]["deck"].erase(c)
				_emit({"type": "deck_summon", "player": p, "uid": c.uid, "card_id": c.card_id})
				_summon(p, c, false, 0)

func _begin_search(p: int, e: Dictionary, source_uid: int) -> void:
	if phase == "search":
		return
	var matches: Array = []
	var seen: Dictionary = {}
	for c in players[p]["deck"]:
		var cd := CardDB.card(c.card_id)
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
		if seen.has(c.card_id):
			continue
		seen[c.card_id] = true
		matches.append({"uid": c.uid, "card_id": c.card_id})
	if matches.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": matches}
	_search_return = phase
	phase = "search"
	_emit({"type": "search_reveal", "player": p, "source_uid": source_uid, "cards": matches})

## Offers the cards just milled (public: they are in the graveyard); one goes to the hand.
func _begin_grave_pick(p: int, milled: Array, source_uid: int) -> void:
	if phase == "search":
		return
	var options: Array = []
	for c in milled:
		for g in players[p]["graveyard"]:
			if g.uid == c.uid:
				options.append({"uid": c.uid, "card_id": c.card_id})
				break
	if options.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": options, "grave": true}
	_search_return = phase
	phase = "search"
	_emit({"type": "search_reveal", "player": p, "source_uid": source_uid, "cards": options})

## Private look at the top `n` cards: only the owner sees them (StateView hides them from
## the other seat); the one taken is revealed by search_take, the rest go to the bottom (or, with "shuffle", the deck is shuffled).
func _begin_look(p: int, n: int, source_uid: int, reshuffle: bool = false) -> void:
	if phase == "search":
		return
	var deck: Array = players[p]["deck"]
	var top: Array = []
	for i in range(deck.size() - 1, maxi(deck.size() - n, 0) - 1, -1): # top of the deck is the back
		top.append({"uid": deck[i].uid, "card_id": deck[i].card_id})
	if top.is_empty():
		_emit({"type": "search_empty", "player": p, "source_uid": source_uid})
		return
	pending_search = {"player": p, "source_uid": source_uid, "cards": top, "look": true, "shuffle": reshuffle}
	_search_return = phase
	phase = "search"
	_emit({"type": "look_top", "player": p, "source_uid": source_uid, "cards": top})

## Returns damage actually dealt. source is the dealing unit or null.
## Armadura a unit really has: its own (printed + buffs) plus "adjacent_armor" from the allies
## standing right next to it on the board (the board order is the order the units were played).
func armor_of(c: Card) -> int:
	var total := c.armor_total()
	var board: Array = players[c.owner]["board"]
	var index := board.find(c)
	if index < 0:
		return total
	for neighbour_index in [index - 1, index + 1]:
		if neighbour_index >= 0 and neighbour_index < board.size():
			total += int(card_of(board[neighbour_index]).get("adjacent_armor", 0))
	return total

func _deal_damage(t: int, amount: int, source: Card) -> int:
	if amount <= 0:
		return 0
	var dealt := 0
	var src_uid := source.uid if source != null else 0
	if t < 0:
		var tp := LEADER_UID.find(t)
		var hp_before: int = players[tp]["leader_hp"]
		players[tp]["leader_hp"] -= amount
		dealt = amount
		_emit({"type": "damage", "uid": t, "amount": amount, "src": src_uid})
		var damaged := GameEvent.new("leader_damaged", tp, source)
		damaged.amount = amount
		damaged.hp_before = hp_before
		damaged.hp_after = players[tp]["leader_hp"]
		bus().emit(damaged)
		if source != null:
			_fire(source, "on_hit_leader")
	else:
		var c := find_unit(t)
		if c == null:
			return 0
		if has_kw(c, "indestrutivel"):
			return 0 # damage is always 0 against it (Escudo isn't consumed)
		# Esquiva: the first combat damage each turn from a qualifying attacker is avoided
		if _combat_damage and has_kw(c, "esquiva") and source != null and combat_system().dodges(c, source) 				and c.dodge_turn != turn:
			c.dodge_turn = turn
			_emit({"type": "dodge", "uid": t, "src": src_uid})
			return 0
		# Armadura: reduces every damage instance; if nothing is left there is no instance, so Escudo stays
		var armor := armor_of(c)
		if armor > 0:
			amount = maxi(0, amount - armor)
			if amount == 0:
				_emit({"type": "armor_block", "uid": t, "src": src_uid})
				return 0
		if c.shield:
			c.shield = false
			_emit({"type": "shield_break", "uid": t, "src": src_uid})
			return 0
		c.damage += amount
		dealt = amount
		_emit({"type": "damage", "uid": t, "amount": amount, "src": src_uid})
		var unit_hurt := GameEvent.new("unit_damaged", c.owner, c)
		unit_hurt.other_uid = src_uid
		unit_hurt.amount = amount
		unit_hurt.hp_before = c.hp_left() + amount
		unit_hurt.hp_after = c.hp_left()
		bus().emit(unit_hurt)
		# Mar que Retorna: the marked unit survived damage -> its owner draws once
		if c.tide_mark and c.hp_left() > 0:
			c.tide_mark = false
			_emit({"type": "tide_draw", "uid": t, "player": c.owner})
			_draw(c.owner, 1)
		_fire(c, "on_damaged", src_uid)
	if source != null and has_kw(source, "roubo_de_vida"):
		_heal_leader(source.owner, dealt)
	return dealt

func _heal_leader(p: int, amount: int) -> void:
	var pl: Dictionary = players[p]
	var healed: int = min(amount, pl["leader_max"] - pl["leader_hp"])
	if healed > 0:
		var hp_before: int = pl["leader_hp"]
		pl["leader_hp"] += healed
		_emit({"type": "heal", "uid": LEADER_UID[p], "amount": healed})
		_emit_leader_healed(p, healed, hp_before)

## Raises the Leader's maximum life and its current life by the same amount (can pass the starting life).
func _raise_leader_max(p: int, amount: int) -> void:
	var pl: Dictionary = players[p]
	pl["leader_max"] += amount
	var hp_before: int = pl["leader_hp"]
	pl["leader_hp"] += amount
	_emit({"type": "heal", "uid": LEADER_UID[p], "amount": amount})
	_emit_leader_healed(p, amount, hp_before)

func _emit_leader_healed(p: int, amount: int, hp_before: int) -> void:
	var healed := GameEvent.new("leader_healed", p)
	healed.amount = amount
	healed.hp_before = hp_before
	healed.hp_after = players[p]["leader_hp"]
	bus().emit(healed)

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
			_deal_damage(LEADER_UID[p], dmg, null)
			continue
		var c: Card = pl["deck"].pop_back()
		pl["hand"].append(c)
		_move(c, "hand")
		_emit({"type": "draw", "player": p, "uid": c.uid})
		bus().emit(GameEvent.new("card_drawn", p, c))

## Draws the first card (from the top) whose base cost is at least `min_base_cost`; that copy costs
## `discount` less while it stays in hand (Tecnomante). Nothing happens, and no Fadiga, if none qualifies.
func _draw_discounted(p: int, min_base_cost: int, discount: int) -> void:
	var deck: Array = players[p]["deck"]
	for i in range(deck.size() - 1, -1, -1):
		if int(CardDB.card(deck[i].card_id)["cost"]) >= min_base_cost:
			var c: Card = deck[i]
			deck.remove_at(i)
			players[p]["hand"].append(c)
			_move(c, "hand")
			c.discount += discount
			_emit({"type": "draw", "player": p, "uid": c.uid})
			bus().emit(GameEvent.new("card_drawn", p, c))
			return

## Stabilizes the game after an action: moves dead units out, then resolves the queued triggers one
## at a time (active player's first), looping until nothing is left to do. A trigger that opens a
## choice (search, enter target) pauses the queue; it resumes when the choice is made.
func _check_state() -> void:
	var resolved := 0
	while true:
		_move_dead_units()
		if _pending.is_empty() or phase in ["search", "enter_target"]:
			break
		if _chain_stopped() or resolved >= MAX_TRIGGERS_PER_ACTION:
			_pending.clear() # a Leader is down or a trigger loop ran away: nothing new resolves
			break
		resolved += 1
		_take_next_pending().resolve(self)
	if not _combat_damage:
		_check_leaders()

## Called by the TriggerBus (and the death/passive code) when a trigger fires.
func queue_trigger(trigger: PendingTrigger) -> void:
	_pending.append(trigger)

## APNAP: the oldest trigger of the active player goes first, else the oldest of the opponent.
func _take_next_pending() -> PendingTrigger:
	for i in _pending.size():
		if _pending[i].controller() == active:
			return _pending.pop_at(i)
	return _pending.pop_front()

## Moves dead units out and queues their Ao Morrer / Aliado Morre. Loops until stable.
## Deaths are processed active player first (APNAP), then the opponent.
func _move_dead_units() -> void:
	var changed := true
	while changed:
		changed = false
		_refresh_scaling()
		for p in [active, opponent(active)]:
			for c in players[p]["board"].duplicate():
				if hp_left(c) <= 0:
					var dead_uid: int = c.uid # a revive_self below gives c a new uid
					var effects: Array = c.effect_list()
					players[p]["board"].erase(c)
					changed = true
					_emit({"type": "death", "uid": dead_uid, "player": p})
					_release_equipment(c)
					if c.legendary:
						_move(c, "")
						_legendary_leaves(p)
					elif c.data().get("token", false):
						_move(c, "") # a ficha dies without ever reaching the graveyard (Vagante, Jeff don't count it)
					else:
						players[p]["graveyard"].append(c)
						_move(c, "graveyard")
					var death_context := EffectContext.new(self, p, "on_death")
					death_context.self_uid = dead_uid
					death_context.dying_card = c
					if not _chain_stopped():
						queue_trigger(PendingTrigger.new(c, effects, death_context, "on_death"))
					# Aliado Morre fires on every death, even if the unit comes right back (Revivente, Fênix)
					# or a Legendary returns to its zone.
					for ally in players[p]["board"].duplicate():
						if players[p]["board"].has(ally):
							_fire(ally, "on_ally_death", dead_uid)
					_fire_leader_passive(p, "on_ally_death")

func _check_leaders() -> void:
	if phase == "over":
		return
	var dead := [players[0]["leader_hp"] <= 0, players[1]["leader_hp"] <= 0]
	if dead[0] or dead[1]:
		winner = 2 if dead[0] and dead[1] else (1 if dead[0] else 0)
		phase = "over"
		_emit({"type": "game_over", "winner": winner})

## Leader passive ("passive": true in the leader's ability): runs its effects when `trigger` happens,
## once per turn if "once_per_turn". Depth-capped like unit triggers.
func _fire_leader_passive(p: int, trigger: String) -> void:
	var ab: Dictionary = CardDB.leader(players[p]["leader_id"])["ability"]
	if not ab.get("passive", false) or ab.get("trigger", "") != trigger or _chain_stopped():
		return
	if ab.get("own_turn_only", false) and active != p:
		return
	if ab.get("once_per_turn", false) and players[p]["passive_used"]:
		return
	players[p]["passive_used"] = true
	_emit({"type": "passive", "player": p})
	queue_trigger(PendingTrigger.new(null, EffectRegistry.parse_list(ab["effects"]), EffectContext.new(self, p, "")))

func _finish_turn() -> void:
	bus().emit(GameEvent.new("turn_ended", active))
	for c in players[active]["board"].duplicate():
		_fire(c, "on_turn_end")
	_fire_deck_effects(active, "on_turn_end")
	_check_state()
	if phase == "over":
		return
	for p in players:
		for c in p["board"]:
			c.damage = 0
			c.temp_atk = 0
			for kw in c.temp_keywords:
				c.keywords.erase(kw)
			c.temp_keywords.clear()
			c.tide_mark = false
			if c.frozen > 0 and turn >= c.frozen:
				c.frozen = 0
				_emit({"type": "thaw", "uid": c.uid})
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
	# Momentum that leaks past a full Reserva, after the opponent's turn too, is what really went
	# unspent (Voltexz and Fulgurvoltz get cheaper by it)
	var leaked: int = int(pl["reserve"]) + int(pl["momentum"]) - RESERVE_CAP
	pl["leaked"] = maxi(0, leaked) # Sobrecarga refunds part of it this turn
	pl["unspent"] = int(pl["momentum"]) # plain Momentum left from the last turn (Gigante Elétrico)
	if leaked > 0:
		pl["saved_momentum"] += leaked
		pl["idle_turns"] += 1
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
	if int(pl["next_momentum"]) > 0:
		pl["momentum"] = mini(MOMENTUM_CAP, int(pl["momentum"]) + int(pl["next_momentum"]))
		pl["next_momentum"] = 0
	pl["attacked"] = false
	pl["played_two"] = false
	for c in pl["board"]:
		c.exhausted = false
		c.sick = false
		c.temp_armor = 0
	_emit({"type": "start_turn", "player": p, "turn": turn})
	bus().emit(GameEvent.new("turn_started", p))
	_fire_leader_passive(p, "on_turn_start")
	for c in pl["board"].duplicate():
		_fire(c, "on_turn_start")
	if draw:
		_draw(p, 1)
	_check_state()

## Test helpers: apply one raw effect dictionary / run raw effect dictionaries as a trigger would.
func _apply_effect(player: int, effect_data: Dictionary, target_uid: int) -> void:
	EffectRegistry.parse(effect_data).apply_to(EffectContext.new(self, player, ""), target_uid)

func _run_effect_dicts(player: int, effects: Array, trigger: String, chosen: int, self_uid: int) -> void:
	var context := EffectContext.new(self, player, trigger)
	context.chosen_target = chosen
	context.self_uid = self_uid
	_run_effects(context, effects)
