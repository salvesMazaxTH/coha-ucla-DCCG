class_name StackSystem
extends RefCounted
## The stack and the priority windows: pushing spells/abilities, resolving them newest-first,
## countering, equipment, and the auto-pass that skips windows nobody can use.

var game: GameState

func _init(game_state: GameState) -> void:
	game = game_state

## Equipping, an Ao Entrar and abilities flagged "uncounterable" can be responded to but never countered.
func is_uncounterable(it: Dictionary) -> bool:
	if it["kind"] == "enter_trigger":
		return true
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
	if item["kind"] == "enter_trigger":
		return 0 # the unit's cost was paid when it was played
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
		if unit == null:
			unit = game.find_relic(chosen)
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

func push(p: int, kind: String, uid: int, card_id: String, target: int, speed: String, target2: int = 0, requiem := false, extra_fields: Dictionary = {}) -> void:
	var item := {"sid": game._uid(), "player": p, "kind": kind, "uid": uid, "card_id": card_id, "target": target, "target2": target2, "speed": speed}
	item.merge(extra_fields)
	if requiem:
		item["requiem"] = true # cast from the graveyard: banished when the cast ends
	game.stack.append(item)
	game.summon_window = false
	game._summon_pending = false
	game.stack_passed = false # every new item restarts the round of passes
	game.priority = game.opponent(p)
	game._emit({"type": "stack_push", "item": item.duplicate()})

## A Bola de Neve cast by a unit (Wanessa Tempesfrost's Ao Atacar): a card item with no real card behind
## it. "virtual" = it never goes to a hand or graveyard; "forced_target" = it keeps its target even when
## a Bola from the hand couldn't aim there (the enemy Leader, an exhausted unit); "source_uid" = the unit
## that cast it (where the UI draws the ghost from).
func push_unit_snowball(p: int, source_uid: int, card_id: String, target: int) -> void:
	var cast_uid := game._uid()
	# the same "play" event a card from the hand sends: the UI shows the card (flying out of the casting unit)
	game._emit({"type": "play", "player": p, "uid": cast_uid, "card_id": card_id, "source_uid": source_uid})
	push(p, "card", cast_uid, card_id, target, "lento", 0, false, {"virtual": true, "forced_target": true, "source_uid": source_uid})

func effects_of(item: Dictionary) -> Array:
	if item["kind"] == "ability":
		return CardDB.leader(game.players[item["player"]]["leader_id"])["ability"]["effects"]
	if item["kind"] == "unit_ability":
		return CardDB.card(item["card_id"])["activated"]["effects"]
	if item["kind"] == "subito":
		return [] # a Súbito summon has no effect of its own: the unit just enters when it resolves
	return CardDB.card(item["card_id"])["effects"]

## Resolves the stack newest-first. Stops early if the game ends or a search needs a choice.
func resolve_stack() -> void:
	game.stack_passed = false
	while not game.stack.is_empty() and game.phase in ["main", "combat"]:
		var item: Dictionary = game.stack.pop_back()
		var p: int = item["player"]
		var effects := effects_of(item)
		# For equipment: the unit's stats before the buff, to work out what the equipment gave it
		var stats_before_equip := {}
		var equip_target := game.find_unit(int(item.get("target", 0)))
		if item["kind"] == "card" and CardDB.is_equipment(CardDB.card(item["card_id"])) and equip_target != null:
			stats_before_equip = unit_stats(equip_target)
		var is_enter: bool = item["kind"] == "enter_trigger"
		# an Ao Entrar never fizzles: a target that left is simply skipped by the effect itself
		var spec := "" if is_enter else game.target_spec(effects)
		var gone := spec != "" and not game.valid_targets(p, spec).has(int(item["target"]))
		if item.get("forced_target", false):
			gone = int(item["target"]) > 0 and game.find_unit(int(item["target"])) == null # only a unit that left the board is lost
		if gone and item["kind"] == "card" and CardDB.card(item["card_id"]).get("same_target_ok", false) and game.valid_targets(p, spec).has(int(item.get("target2", 0))):
			gone = false # twin bolts: the other target is still there, only this bolt is lost
		if gone:
			game._emit({"type": "fizzle", "sid": item["sid"], "player": p, "card_id": item["card_id"], "kind": item["kind"]})
		else:
			game._emit({"type": "resolve", "sid": item["sid"], "player": p, "card_id": item["card_id"], "kind": item["kind"]})
			if is_enter:
				var entering := game.find_unit(int(item["uid"]))
				if entering != null:
					game._announce(entering, effects, "on_enter")
				game._run_effects(game._enter_context(p, int(item["uid"]), int(item["target"]), int(item.get("target2", 0))), effects)
			else:
				var resolve_context := EffectContext.new(game, p, "on_play" if item["kind"] == "card" else "")
				resolve_context.chosen_target = int(item["target"])
				resolve_context.forced_target = item.get("forced_target", false)
				resolve_context.second_target = int(item.get("target2", 0))
				resolve_context.self_uid = int(item["uid"]) if item["kind"] == "unit_ability" else 0
				game._spell_resolving = item["kind"] == "card" and CardDB.card(item["card_id"]).get("type", "") == "spell"
				game._run_effects(resolve_context, effects)
				game._spell_resolving = false
		if item.get("virtual", false):
			pass # cast by a unit: there is no card to send anywhere
		elif item["kind"] == "card":
			var holder := game.find_unit(int(item["target"]))
			var played := take_stack_card(item)
			if CardDB.is_equipment(CardDB.card(item["card_id"])) and holder != null and spec != "" and game.valid_targets(p, spec).has(int(item["target"])):
				attach(holder, played, stat_gain_since(holder, stats_before_equip))
			elif CardDB.is_relic(CardDB.card(item["card_id"])) and not gone:
				game._place_relic(p, played)
			elif item.get("requiem", false) or played.banish_after_cast:
				game._banish_requiem(played)
			else:
				game.players[p]["graveyard"].append(played)
				game._move(played, "graveyard")
		elif item["kind"] == "subito":
			_resolve_subito(item)
		game._check_state()
	if game.stack.is_empty():
		game.combat_system().finish_pending_attack() # the attack that cast it deals its combat damage now
	if game.phase in ["main", "combat"] and game.stack.is_empty():
		game.summon_window = false
		game.priority = window_owner()

## A Súbito summon resolves: the unit enters at the chosen slot (its Ao Entrar fires as usual).
## If the board filled up while it waited on the stack, the card goes to the graveyard instead.
func _resolve_subito(item: Dictionary) -> void:
	var p: int = item["player"]
	var unit := take_stack_card(item)
	if game.has_free_slot(p):
		game._summon(p, unit, false, 0, {}, false, int(item.get("slot", -1)))
	else:
		game.players[p]["graveyard"].append(unit)
		game._move(unit, "graveyard")

## The Card a "card" stack item stands for (a fresh one if it was never played from a hand).
func take_stack_card(item: Dictionary) -> Card:
	var uid := int(item["uid"])
	if game._stack_cards.has(uid):
		var c: Card = game._stack_cards[uid]
		game._stack_cards.erase(uid)
		return c
	return Card.new(uid, item["card_id"], int(item["player"]), "stack")

## Equipment stays on the board under its unit. A unit holds only one: equipping an already
## equipped unit sends the previous equipment back to its owner's hand (not to the graveyard),
## and the unit loses what that equipment had given it. `granted` is what the new one gave.
func attach(holder: Card, eq: Card, granted: Dictionary = {}) -> void:
	return_equipment_to_hand(holder)
	holder.equipment = eq
	holder.equipment_grant = granted
	game._move(eq, "equipped")
	game._emit({"type": "attach", "uid": holder.uid, "equip_uid": eq.uid, "card_id": eq.card_id})

## The stats an equipment's buff can change, as they are right now.
func unit_stats(unit: Card) -> Dictionary:
	return {"atk": unit.atk, "hp": unit.hp, "armor": unit.armor, "keywords": unit.keywords.duplicate()}

## What the unit gained since `before` (a unit_stats snapshot). Keywords the unit already had are not
## counted, so removing the equipment later never strips something the unit owns by itself.
func stat_gain_since(unit: Card, before: Dictionary) -> Dictionary:
	if before.is_empty():
		return {}
	var gained_keywords: Array = []
	for keyword in unit.keywords:
		if not before["keywords"].has(keyword):
			gained_keywords.append(keyword)
	return {"atk": unit.atk - before["atk"], "hp": unit.hp - before["hp"], "armor": unit.armor - before["armor"], "keywords": gained_keywords}

## Takes back what the unit's equipment gave it. The unit never dies from this: if losing the
## Vida would kill it, it stays with 1 Vida left.
func remove_equipment_bonus(unit: Card) -> void:
	var granted := unit.equipment_grant
	unit.equipment_grant = {}
	if granted.is_empty():
		return
	unit.atk = maxi(0, unit.atk - int(granted.get("atk", 0)))
	unit.hp -= int(granted.get("hp", 0))
	unit.armor = maxi(0, unit.armor - int(granted.get("armor", 0)))
	for keyword in granted.get("keywords", []):
		unit.keywords.erase(keyword)
	if unit.hp_left() < 1:
		unit.damage = unit.hp + unit.bonus_hp + unit.temp_hp - 1

## Gives the unit's equipment (if any) back to its owner's hand, to be played again.
func return_equipment_to_hand(c: Card) -> void:
	if c.equipment == null:
		return
	var old_equipment := c.equipment
	c.equipment = null
	remove_equipment_bonus(c)
	game.players[c.owner]["hand"].append(old_equipment)
	game._move(old_equipment, "hand")
	game._emit({"type": "equipment_returned", "uid": c.uid, "equip_uid": old_equipment.uid, "card_id": old_equipment.card_id})

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
	if it.get("virtual", false):
		pass # a countered unit-cast Bola just disappears
	elif it["kind"] in ["card", "subito"]:
		var countered := take_stack_card(it)
		if it.get("requiem", false) or countered.banish_after_cast:
			game._banish_requiem(countered)
		else:
			game.players[it["player"]]["graveyard"].append(countered)
			game._move(countered, "graveyard")
	game._emit({"type": "countered", "sid": sid, "player": it["player"], "by": p, "card_id": it["card_id"], "kind": it["kind"]})

## Who holds priority when a window opens or the stack empties: always the active player
## (in the pre-combat window the attacker acts first, then the defender).
func window_owner() -> int:
	return game.active

func open_window(w: String) -> void:
	game.window = w
	game.priority = window_owner()
	game._emit({"type": "window", "window": w, "player": game.priority})

func pass_once() -> void:
	if not game.stack.is_empty():
		if game.self_response_enabled and not game.stack_passed:
			# first pass of the round: the other player may respond (or stack more) before it resolves
			game.stack_passed = true
			game.priority = game.opponent(game.priority)
		else:
			resolve_stack() # both passed in a row
		return
	if game.summon_window:
		game.summon_window = false
		game.priority = game.active
		return
	match game.window:
		"pre_combat":
			if game.priority == game.active:
				game.priority = game.opponent(game.active) # attacker passed: the defender may still act
			else:
				game.combat_system().start_attacks() # both passed in a row with an empty stack
		"attacks":
			game.combat_system().end_combat() # passing during the attacks = ENCERRAR COMBATE

## After a unit enters from hand/Santuário in the main phase, the opponent may respond.
func open_summon_window(p: int) -> void:
	if game.phase in ["search", "enter_target", "enter_tapped"] and p == game.active:
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
	for c in game.players[p]["board"] + game.players[p]["relics"]:
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
		if not game.pending_tap.is_empty() and game.ask_enter_tapped():
			return # a Provocação just entered: its controller chooses tapped or not first
		if game.stack.is_empty():
			game.stack_passed = false
			game.combat_system().finish_pending_attack()
		if game.stack.is_empty() and game.phase == "main" and not game.summon_window:
			game.priority = game.active
			return
		if game.phase == "combat" and game.window == "attacks" and game.stack.is_empty():
			return # the attacker declares attacks (or ends combat) by hand; never auto-pass here
		var holder: int = game.priority
		# "PASSAR TUDO" only covers answering the opponent's moves, never the player's own turn
		var passing_everything: bool = game.skip_rest_of_turn[holder] and holder != game.active
		if not passing_everything and (not game.auto_pass[holder] or has_play(holder)):
			return
		pass_once()
