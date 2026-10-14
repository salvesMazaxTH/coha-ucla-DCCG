extends RefCounted
## Scripted pilot for the Glacial combo deck ("Ladeira de Nythera"), used by tests/sim_matchup.gd to measure
## the combo's real ceiling: SimpleAI never sequences Ritual -> Ladeira -> Grande Bola de Neve on purpose.
##
## The pilot plays like a person would: it HOLDS the combo pieces (Ritual, Ladeira, the Bola in hand) and
## plays everything else with SimpleAI. Each main phase it asks "if I fire the whole combo now, does the
## Grande Bola de Neve kill the enemy Leader?". If so it plays the pieces in the best order; if not it waits.

const LADEIRA_ID := "ladeira_abaixo_e_sem_freio"
const RITUAL_ID := "ritual_do_degelo"
const BOLA_ID := "bola_de_neve"
const GRANDE_ID := "grande_bola_de_neve"

## Biggest Leader damage the pilot ever predicted for a combo it fired (read by the sim for its report).
static var biggest_fired_prediction := 0

## Per own turn number: the Leader damage the best combo line available at the start of the main phase would deal
## (0 when there is no line), sampled once per turn. Read by the sim for its damage report.
static var potential_by_turn := {}
static var last_sampled_turn := -1

static func step(g: GameState, p: int) -> Array:
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

## Cards SimpleAI must leave alone: the combo pieces, and the last Bola in hand (the finisher).
static func _held_card_ids(g: GameState, p: int) -> Array:
	var held: Array = [LADEIRA_ID, RITUAL_ID]
	if _finishers_in_hand(g, p).size() < 2:
		held.append(BOLA_ID)
		held.append(GRANDE_ID)
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

## The next card to play of a lethal combo, as {uid, target, predicted}; {} when no lethal combo exists now.
## Order: Ritual first (a cheap +1 level before the doubling, and +3 Momentum), then the Ladeiras, then the Bola.
static func _plan(g: GameState, p: int) -> Dictionary:
	var finishers := _finishers_in_hand(g, p)
	if finishers.is_empty():
		return {}
	var foe := g.opponent(p)
	var foe_board: Array = g.players[foe]["board"]
	if foe_board.is_empty():
		return {}
	var foe_leader_hp := int(g.players[foe]["leader_hp"])

	# keep the cheapest lethal line
	var best_line: Dictionary = {}
	for line in _all_lines(g, p):
		if int(line["predicted"]) < foe_leader_hp:
			continue
		if best_line.is_empty() or int(line["pieces"]) < int(best_line["pieces"]):
			best_line = line
	if best_line.is_empty():
		return {}
	# the first piece of the line is what gets played now (the plan is recomputed every step)
	var first_uid: int = int(best_line["order"][0])
	var target := 0
	if first_uid == int(finishers[0].uid):
		target = int(best_line["target"])
	return {"uid": first_uid, "target": target, "predicted": best_line["predicted"]}

## Every affordable line: each count of Ritual (0..all) and of Ladeiras (0..all), then the finisher.
static func _all_lines(g: GameState, p: int) -> Array:
	var lines: Array = []
	var finishers := _finishers_in_hand(g, p)
	var foe_board: Array = g.players[g.opponent(p)]["board"]
	if finishers.is_empty() or foe_board.is_empty():
		return lines
	var ritual_cards := _cards_in_hand(g, p, RITUAL_ID)
	var ladeira_cards := _cards_in_hand(g, p, LADEIRA_ID)
	var level := int(g.players[p]["snowball"])
	var budget := g.budget(p, true)
	for use_ritual in range(ritual_cards.size() + 1):
		for ladeira_count in range(ladeira_cards.size() + 1):
			var line := _simulate_line(g, p, level, budget, use_ritual > 0, ladeira_count, ritual_cards, ladeira_cards, finishers[0], foe_board)
			if not line.is_empty():
				lines.append(line)
	return lines

## Leader damage of the strongest affordable line right now (0 when there is none).
static func _best_damage(g: GameState, p: int) -> int:
	var best := 0
	for line in _all_lines(g, p):
		best = maxi(best, int(line["predicted"]))
	return best

## Plays out a line on paper. Returns {} when it is not affordable, else {order, target, predicted, pieces}.
static func _simulate_line(g: GameState, p: int, level: int, budget: int, use_ritual: bool, ladeira_count: int,
		ritual_cards: Array, ladeira_cards: Array, finisher: Card, foe_board: Array) -> Dictionary:
	var order: Array = []
	if use_ritual:
		var ritual: Card = ritual_cards[0]
		var ritual_cost := g.cost_of(p, ritual.data(), ritual)
		if ritual_cost > budget:
			return {}
		budget += 3 - ritual_cost # the Ritual pays for itself and gives 3 Momentum
		level += 1
		order.append(ritual.uid)
	for i in ladeira_count:
		var ladeira: Card = ladeira_cards[i]
		var ladeira_cost := g.cost_of(p, ladeira.data(), ladeira)
		if ladeira_cost > budget:
			return {}
		budget -= ladeira_cost
		level = _level_after_ladeira(ladeira, level)
		order.append(ladeira.uid)
	# the finisher: it is a Grande Bola de Neve only if the level got to Grande (or already was)
	var is_grande := level >= GameState.SNOWBALL_GRANDE_AT
	var finisher_data := CardDB.card(GRANDE_ID if is_grande else BOLA_ID)
	var finisher_cost := g.cost_of(p, finisher_data, finisher)
	if finisher_cost > budget:
		return {}
	order.append(finisher.uid)
	var best_target := 0
	var best_leader_damage := -1
	# the bounce goes one way only when the first unit is at an end of the board; try both ends
	for end_index in [0, foe_board.size() - 1]:
		var path: Array = foe_board.duplicate()
		if end_index != 0:
			path.reverse()
		var leader_damage := _overflow_to_leader(g, level, path, is_grande)
		if leader_damage > best_leader_damage:
			best_leader_damage = leader_damage
			best_target = path[0].uid
	return {"order": order, "target": best_target, "predicted": best_leader_damage, "pieces": order.size()}

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
