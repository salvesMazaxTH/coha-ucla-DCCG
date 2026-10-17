extends RefCounted
## Scripted pilot for the Glacial combo deck ("Ladeira Ascendente"), used by tests/sim_matchup.gd to measure
## the combo's real ceiling: SimpleAI never sequences Ritual -> Ladeira -> Grande Bola de Neve on purpose.
##
## The pilot plays like a person would: it HOLDS the combo pieces (Ritual, Ladeira, the Bola in hand, and the
## Gertrudes + Princesa pair) and plays everything else with SimpleAI. Each main phase it asks "if I fire the
## whole combo now, is it lethal?". If so it plays the pieces in the best order; if not it waits.
##
## Two ways to kill, both planned as "lines" (a list of cards to play, then the damage they add up to):
##  - the Grande Bola de Neve: its Sobrepujança sends the excess damage of every hit to the enemy Leader;
##  - Wanessa Tempesfrost: once the level reaches 8 the Princesa transforms (freezing every enemy unit)
##    and attacks the Leader for her ATK plus a Bola at the current level. With Dona Gertrudes the
##    Princesa comes in for free in the same turn, so the whole combo needs no turn of waiting.

const LADEIRA_ID := "ladeira_abaixo_e_sem_freio"
const RITUAL_ID := "ritual_do_degelo"
const BOLA_ID := "bola_de_neve"
const GRANDE_ID := "grande_bola_de_neve"
const GERTRUDES_ID := "dona_gertrudes_fura_fila"
const PRINCESA_ID := "princesa_wanessa"
const TEMPESFROST_ID := "wanessa_tempesfrost"

## Where the Bola de Neve finisher goes in a line: not at all, before the Ladeiras (to raise the level through
## its bounces) or after them (as a Grande Bola, to overflow into the Leader).
const FINISHER_NONE := "none"
const FINISHER_FIRST := "first"
const FINISHER_LAST := "last"

## Biggest Leader damage the pilot ever predicted for a combo it fired (read by the sim for its report).
static var biggest_fired_prediction := 0

## Per own turn number: the Leader damage the best combo line available at the start of the main phase would deal
## (0 when there is no line), sampled once per turn. Read by the sim for its damage report.
static var potential_by_turn := {}
static var last_sampled_turn := -1

static func step(g: GameState, p: int) -> Array:
	if g.phase == "search" and g.pending_search.get("hand_summon", false):
		# Dona Gertrudes: the champion to put into play is the Princesa Wanessa, when she is on offer
		for option in g.pending_search.get("cards", []):
			if option["card_id"] == PRINCESA_ID:
				return g.choose_search(p, int(option["uid"]))
	if g.phase == "enter_tapped":
		# entering tapped would leave the Princesa unable to attack once she transforms
		var waiting_unit := g.find_unit(int(g.pending_tap[0]))
		if waiting_unit != null and waiting_unit.card_id == PRINCESA_ID:
			return g.choose_enter_tapped(p, false)
	if g.phase == "combat" and g.window == "attacks" and p == g.active and g.stack.is_empty():
		var tempesfrost_events := _attack_leader_with_tempesfrost(g, p)
		if not tempesfrost_events.is_empty():
			return tempesfrost_events
	if g.phase == "main" and p == g.active and g.stack.is_empty():
		if g.turn != last_sampled_turn:
			last_sampled_turn = g.turn
			var own_turn: int = (g.turn + 1) / 2
			if not potential_by_turn.has(own_turn):
				potential_by_turn[own_turn] = []
			potential_by_turn[own_turn].append(_best_damage(g, p))
		var plan := _plan(g, p)
		if not plan.is_empty():
			var events := g.play_card(p, int(plan["uid"]), int(plan["target"]))
			if not events.is_empty():
				biggest_fired_prediction = maxi(biggest_fired_prediction, int(plan["predicted"]))
				return events
	return SimpleAI.step(g, p, _held_card_ids(g, p))

## The attack of a transformed Wanessa Tempesfrost on the enemy Leader, when it is lethal (ATK plus a Bola at the
## current level) or when she is a Gertrudes guest and will be banished at the end of the turn anyway.
static func _attack_leader_with_tempesfrost(g: GameState, p: int) -> Array:
	var foe := g.opponent(p)
	var leader_uid: int = GameState.LEADER_UID[foe]
	for unit: Card in g.players[p]["board"]:
		if unit.card_id != TEMPESFROST_ID or not g.can_attack(unit):
			continue
		if not g.attack_targets(unit).has(leader_uid):
			continue
		var face_damage := g.atk_of(unit) + int(g.players[p]["snowball"])
		if unit.banish_at_turn_end or face_damage >= int(g.players[foe]["leader_hp"]):
			return g.attack_unit(p, unit.uid, leader_uid)
	return []

## Cards SimpleAI must leave alone: the combo pieces, and the last Bola in hand (the finisher).
static func _held_card_ids(g: GameState, p: int) -> Array:
	var held: Array = [LADEIRA_ID, RITUAL_ID]
	if _finishers_in_hand(g, p).size() < 2:
		held.append(BOLA_ID)
		held.append(GRANDE_ID)
	# Gertrudes only makes sense with a Princesa to put into play for free, and the Princesa waits for Gertrudes
	if not _cards_in_hand(g, p, GERTRUDES_ID).is_empty() and not _cards_in_hand(g, p, PRINCESA_ID).is_empty():
		held.append(GERTRUDES_ID)
		held.append(PRINCESA_ID)
	return held

static func _finishers_in_hand(g: GameState, p: int) -> Array:
	var finishers: Array = []
	for card: Card in g.players[p]["hand"]:
		if card.card_id == BOLA_ID or card.card_id == GRANDE_ID:
			finishers.append(card)
	return finishers

static func _cards_in_hand(g: GameState, p: int, card_id: String) -> Array:
	var found: Array = []
	for card: Card in g.players[p]["hand"]:
		if card.card_id == card_id:
			found.append(card)
	return found

## The Princesa Wanessa of player p that is on the board, or null.
static func _princesa_on_board(g: GameState, p: int) -> Card:
	for unit: Card in g.players[p]["board"]:
		if unit.card_id == PRINCESA_ID:
			return unit
	return null

## The next card to play of a lethal combo, as {uid, target, predicted}; {} when no lethal combo exists now
## (or when the combo is already set up and only the attack is left, which step() does in the combat phase).
static func _plan(g: GameState, p: int) -> Dictionary:
	var foe_leader_hp := int(g.players[g.opponent(p)]["leader_hp"])
	# keep the cheapest lethal line
	var best_line: Dictionary = {}
	for line in _all_lines(g, p):
		if int(line["predicted"]) < foe_leader_hp:
			continue
		if best_line.is_empty() or int(line["pieces"]) < int(best_line["pieces"]):
			best_line = line
	if best_line.is_empty() or int(best_line["pieces"]) == 0:
		return {}
	# the first piece of the line is what gets played now (the plan is recomputed every step)
	var first_uid: int = int(best_line["order"][0])
	var target := 0
	if first_uid == int(best_line["finisher_uid"]):
		target = int(best_line["target"])
	return {"uid": first_uid, "target": target, "predicted": best_line["predicted"]}

## Every affordable line: each count of Rituals and of Ladeiras, with or without Gertrudes, with the finisher
## before, after or left out.
static func _all_lines(g: GameState, p: int) -> Array:
	var lines: Array = []
	var finishers := _finishers_in_hand(g, p)
	var ritual_cards := _cards_in_hand(g, p, RITUAL_ID)
	var ladeira_cards := _cards_in_hand(g, p, LADEIRA_ID)
	var gertrudes_cards := _cards_in_hand(g, p, GERTRUDES_ID)
	var princesa_cards := _cards_in_hand(g, p, PRINCESA_ID)
	# Gertrudes needs a Princesa in hand and room for both of them
	var gertrudes_possible: bool = not gertrudes_cards.is_empty() and not princesa_cards.is_empty() \
			and g.players[p]["board"].size() + 2 <= GameState.BOARD_LIMIT
	var gertrudes_choices: Array = [false, true] if gertrudes_possible else [false]
	var finisher_slots: Array = [FINISHER_NONE]
	if not finishers.is_empty():
		finisher_slots = [FINISHER_NONE, FINISHER_FIRST, FINISHER_LAST]
	for ritual_count in range(ritual_cards.size() + 1):
		for ladeira_count in range(ladeira_cards.size() + 1):
			for use_gertrudes in gertrudes_choices:
				for finisher_slot in finisher_slots:
					var line := _simulate_line(g, p, {
						"ritual_cards": ritual_cards.slice(0, ritual_count),
						"ladeira_cards": ladeira_cards.slice(0, ladeira_count),
						"gertrudes": gertrudes_cards[0] if use_gertrudes else null,
						"finisher": finishers[0] if not finishers.is_empty() else null,
						"finisher_slot": finisher_slot,
					})
					if not line.is_empty():
						lines.append(line)
	return lines

## Leader damage of the strongest affordable line right now (0 when there is none).
static func _best_damage(g: GameState, p: int) -> int:
	var best := 0
	for line in _all_lines(g, p):
		best = maxi(best, int(line["predicted"]))
	return best

## Plays out a line on paper. `options` holds the cards of the line: ritual_cards, ladeira_cards, gertrudes (a Card or
## null), finisher (a Card or null) and finisher_slot. Returns {} when it is not affordable, else
## {order, target, finisher_uid, predicted, pieces}.
static func _simulate_line(g: GameState, p: int, options: Dictionary) -> Dictionary:
	var foe_board: Array = g.players[g.opponent(p)]["board"]
	var level := int(g.players[p]["snowball"])
	var budget := g.budget(p, true)
	var order: Array = []
	var finisher: Card = options["finisher"]
	var finisher_slot: String = options["finisher_slot"]
	var finisher_uid := 0
	var finisher_target := 0
	var leader_damage := 0
	# the Princesa is ready to transform when she is already on the board or Gertrudes brings her in
	var princesa_ready := _princesa_on_board(g, p) != null

	for ritual: Card in options["ritual_cards"]:
		var ritual_cost := g.cost_of(p, ritual.data(), ritual)
		if ritual_cost > budget:
			return {}
		budget += 3 - ritual_cost # the Ritual pays for itself and gives 3 Momentum (it doesn't touch the level)
		order.append(ritual.uid)
	var gertrudes: Card = options["gertrudes"]
	if gertrudes != null:
		var gertrudes_cost := g.cost_of(p, gertrudes.data(), gertrudes)
		if gertrudes_cost > budget:
			return {}
		budget -= gertrudes_cost # the Princesa herself is free
		order.append(gertrudes.uid)
		princesa_ready = true

	# the Ladeiras come between the two finisher slots
	for slot in [FINISHER_FIRST, FINISHER_LAST]:
		if slot == FINISHER_LAST:
			for ladeira: Card in options["ladeira_cards"]:
				var ladeira_cost := g.cost_of(p, ladeira.data(), ladeira)
				if ladeira_cost > budget:
					return {}
				budget -= ladeira_cost
				level = _level_after_ladeira(ladeira, level)
				order.append(ladeira.uid)
		if finisher_slot != slot:
			continue
		if foe_board.is_empty():
			return {} # a Bola de Neve needs an enemy unit to be thrown at
		# the finisher is a Grande Bola de Neve only if the level got to Grande (or already was)
		var is_grande := level >= GameState.SNOWBALL_GRANDE_AT
		var finisher_cost := g.cost_of(p, CardDB.card(GRANDE_ID if is_grande else BOLA_ID), finisher)
		if finisher_cost > budget:
			return {}
		budget -= finisher_cost
		order.append(finisher.uid)
		finisher_uid = finisher.uid
		# the bounce goes one way only when the first unit is at an end of the board; try both ends
		var best_overflow := -1
		for end_index in [0, foe_board.size() - 1]:
			var path: Array = foe_board.duplicate()
			if end_index != 0:
				path.reverse()
			var overflow := _overflow_to_leader(g, level, path, is_grande)
			if overflow > best_overflow:
				best_overflow = overflow
				finisher_target = path[0].uid
		leader_damage += best_overflow
		# the level ends where the last bounce stopped: one more per unit after the first
		level += foe_board.size() - 1

	# level 8 transforms the Princesa: she freezes every enemy unit and attacks the Leader (her ATK plus a Bola)
	if princesa_ready and level >= GameState.SNOWBALL_GRANDE_AT:
		leader_damage += int(CardDB.card(TEMPESFROST_ID)["atk"]) + level
	return {"order": order, "target": finisher_target, "finisher_uid": finisher_uid, "predicted": leader_damage, "pieces": order.size()}

## Level after one Ladeira, read from the card so a rebalanced Ladeira is measured correctly.
static func _level_after_ladeira(ladeira: Card, level: int) -> int:
	for effect: Dictionary in ladeira.data()["effects"]:
		if effect.get("action", "") != "snowball_level":
			continue
		if effect.has("multiply"):
			return level * int(effect["multiply"])
		if effect.has("half_up"):
			return level + int(ceil(level / 2.0))
		return level + int(effect.get("amount", 0))
	return level

## Damage that reaches the Leader from a Grande Bola (Sobrepujança) bouncing along `path`; a plain Bola
## has no Sobrepujança, so it sends nothing to the Leader.
static func _overflow_to_leader(g: GameState, level: int, path: Array, is_grande: bool) -> int:
	if not is_grande:
		return 0
	var total := 0
	var damage_now := level
	for unit: Card in path:
		if not unit.spell_shield and not unit.shield:
			total += maxi(0, damage_now - g.hp_left(unit))
		damage_now += 1
	return total
