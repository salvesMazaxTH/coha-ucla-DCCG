class_name StackSystem
extends RefCounted
## The stack and the priority windows: pushing spells/abilities, resolving them newest-first,
## countering, equipment, and the auto-pass that skips windows nobody can use.

var game: GameState

func _init(game_state: GameState) -> void:
	game = game_state

## Equipping and abilities flagged "uncounterable" can be responded to but never countered.
func is_uncounterable(it: Dictionary) -> bool:
	if it["kind"] == "ability":
		return CardDB.leader(game.players[it["player"]]["leader_id"])["ability"].get("uncounterable", false)
	return it["kind"] == "card" and CardDB.is_equipment(CardDB.card(it["card_id"]))

func stack_item(sid: int) -> Dictionary:
	for it in game.stack:
		if it["sid"] == sid:
			return it
	return {}

## Momentum cost of a spell/ability on the stack.
func stack_cost(item: Dictionary) -> int:
	if item["kind"] == "ability":
		return int(CardDB.leader(game.players[item["player"]]["leader_id"])["ability"]["cost"])
	if item["kind"] == "unit_ability":
		return int(CardDB.card(item["card_id"])["activated"]["cost"])
	return int(CardDB.card(item["card_id"]).get("cost", 0)) + (GameState.REQUIEM_EXTRA_COST if item.get("requiem", false) else 0)

## True when the stack item's chosen target(s) include a unit or the Leader of the player who
## would counter it (the opponent of whoever cast it). Area effects choose no target, so they never count.
func targets_countering_side(item: Dictionary) -> bool:
	var defender: int = game.opponent(item["player"])
	for chosen in [int(item["target"]), int(item.get("target2", 0))]:
		if chosen == 0:
			continue
		if chosen == GameState.LEADER_UID[defender]:
			return true
		var unit := game.find_unit(chosen)
		if unit != null and unit.owner == defender:
			return true
	return false

## Extra Momentum a counter (action "counter") must pay to hit stack item `sid`:
## 0 up to max_cost, kicker_cost up to kicker_max_cost, -1 when out of reach.
func counter_extra(cd: Dictionary, sid: int) -> int:
	var it := stack_item(sid)
	if it.is_empty():
		return -1
	for e in cd["effects"]:
		if e.get("action", "") != "counter":
			continue
		if e.get("only_if_targets_ally", false) and not targets_countering_side(it):
			return -1
		var c := stack_cost(it)
		if c <= int(e.get("max_cost", 99)):
			return 0
		if e.has("kicker_cost") and c <= int(e.get("kicker_max_cost", 99)):
			return int(e["kicker_cost"])
		return -1
	return 0

func push(p: int, kind: String, uid: int, card_id: String, target: int, speed: String, target2: int = 0, requiem := false) -> void:
	var item := {"sid": game._uid(), "player": p, "kind": kind, "uid": uid, "card_id": card_id, "target": target, "target2": target2, "speed": speed}
	if requiem:
		item["requiem"] = true # cast from the graveyard: banished when the cast ends
	game.stack.append(item)
	game.summon_window = false
	game._summon_pending = false
	game.priority = game.opponent(p)
	game._emit({"type": "stack_push", "item": item.duplicate()})

func effects_of(item: Dictionary) -> Array:
	if item["kind"] == "ability":
		return CardDB.leader(game.players[item["player"]]["leader_id"])["ability"]["effects"]
	if item["kind"] == "unit_ability":
		return CardDB.card(item["card_id"])["activated"]["effects"]
	return CardDB.card(item["card_id"])["effects"]

## Resolves the stack newest-first. Stops early if the game ends or a search needs a choice.
func resolve_stack() -> void:
	while not game.stack.is_empty() and game.phase in ["main", "combat"]:
		var item: Dictionary = game.stack.pop_back()
		var p: int = item["player"]
		var effects := effects_of(item)
		var spec := game.target_spec(effects)
		var gone := spec != "" and not game.valid_targets(p, spec).has(int(item["target"]))
		if gone and item["kind"] == "card" and CardDB.card(item["card_id"]).get("same_target_ok", false) and game.valid_targets(p, spec).has(int(item.get("target2", 0))):
			gone = false # twin bolts: the other target is still there, only this bolt is lost
		if gone:
			game._emit({"type": "fizzle", "sid": item["sid"], "player": p, "card_id": item["card_id"], "kind": item["kind"]})
		else:
			game._emit({"type": "resolve", "sid": item["sid"], "player": p, "card_id": item["card_id"], "kind": item["kind"]})
			var resolve_context := EffectContext.new(game, p, "on_play" if item["kind"] == "card" else "")
			resolve_context.chosen_target = int(item["target"])
			resolve_context.second_target = int(item.get("target2", 0))
			resolve_context.self_uid = int(item["uid"]) if item["kind"] == "unit_ability" else 0
			game._run_effects(resolve_context, effects)
		if item["kind"] == "card":
			var holder := game.find_unit(int(item["target"]))
			var played := take_stack_card(item)
			if CardDB.is_equipment(CardDB.card(item["card_id"])) and holder != null and spec != "" and game.valid_targets(p, spec).has(int(item["target"])):
				attach(holder, played)
			elif item.get("requiem", false):
				game._banish_requiem(played)
			else:
				game.players[p]["graveyard"].append(played)
				game._move(played, "graveyard")
		game._check_state()
		game.combat_system().prune_attackers()
	if game.phase in ["main", "combat"] and game.stack.is_empty():
		game.summon_window = false
		game.priority = window_owner()

## The Card a "card" stack item stands for (a fresh one if it was never played from a hand).
func take_stack_card(item: Dictionary) -> Card:
	var uid := int(item["uid"])
	if game._stack_cards.has(uid):
		var c: Card = game._stack_cards[uid]
		game._stack_cards.erase(uid)
		return c
	return Card.new(uid, item["card_id"], int(item["player"]), "stack")

## Equipment stays on the board under its unit; a previous one is discarded.
func attach(holder: Card, eq: Card) -> void:
	release_equipment(holder)
	holder.equipment = eq
	game._move(eq, "equipped")
	game._emit({"type": "attach", "uid": holder.uid, "equip_uid": eq.uid, "card_id": eq.card_id})

## Sends the unit's equipment (if any) to its owner's graveyard.
func release_equipment(c: Card) -> void:
	if c.equipment == null:
		return
	var eq := c.equipment
	c.equipment = null
	game.players[c.owner]["graveyard"].append(eq)
	game._move(eq, "graveyard")
	game._emit({"type": "equipment_break", "uid": c.uid, "equip_uid": eq.uid, "card_id": eq.card_id})

## Removes stack item `sid` without resolving it; a countered card goes to the graveyard.
func counter(p: int, sid: int) -> void:
	var it := stack_item(sid)
	if it.is_empty() or is_uncounterable(it):
		return
	game.stack.erase(it)
	if it["kind"] == "card":
		var countered := take_stack_card(it)
		if it.get("requiem", false):
			game._banish_requiem(countered)
		else:
			game.players[it["player"]]["graveyard"].append(countered)
			game._move(countered, "graveyard")
	game._emit({"type": "countered", "sid": sid, "player": it["player"], "by": p, "card_id": it["card_id"], "kind": it["kind"]})

## Damage window: the attacker holds priority after the stack resolves.
func window_owner() -> int:
	return game.opponent(game.active) if game.phase == "combat" and game.window == "prepare" else game.active

func open_window(w: String) -> void:
	game.window = w
	game.priority = window_owner()
	game._emit({"type": "window", "window": w, "player": game.priority})

func pass_once() -> void:
	if not game.stack.is_empty():
		resolve_stack()
		return
	if game.summon_window:
		game.summon_window = false
		game.priority = game.active
		return
	match game.window:
		"attack":
			open_window("prepare")
		"prepare":
			game.combat_system().to_blocks()
		"damage":
			if game.priority == game.active:
				game.priority = game.opponent(game.active) # attacker passed: the defender may still act
			else:
				game.combat_system().resolve_combat() # both passed in a row with an empty stack
		_:
			game.combat_system().to_blocks()

## After a unit enters from hand/Santuário in the main phase, the opponent may respond.
func open_summon_window(p: int) -> void:
	if game.phase in ["search", "enter_target"] and p == game.active:
		game._summon_pending = true
		return
	if game.phase == "main" and game.stack.is_empty() and p == game.active:
		game.summon_window = true
		game.priority = game.opponent(p)

## A summon whose on_play searched (or whose Ao Entrar awaited a target) opens its
## response window once the pick is made.
func after_search() -> void:
	if game._summon_pending and game.phase == "main":
		game._summon_pending = false
		open_summon_window(game.active)

## Can p do anything right now besides passing?
func has_play(p: int) -> bool:
	for c in game.players[p]["hand"]:
		if game.can_play(p, c.uid):
			return true
	for c in game.players[p]["board"]:
		if game.can_activate(p, c.uid):
			return true
	for c in game.players[p]["graveyard"]:
		if game.is_requiem(c) and game.can_play(p, c.uid):
			return true
	return game.can_use_ability(p)

## Auto-passes for whoever holds priority with no legal play, so windows nobody can use
## cost no clicks. Stops at a real decision.
func settle() -> void:
	for guard in 64:
		if game.phase not in ["main", "combat"]:
			return
		if game.stack.is_empty() and game.phase == "main" and not game.summon_window:
			game.priority = game.active
			return
		if not game.auto_pass[game.priority] or has_play(game.priority):
			return
		pass_once()
