extends RefCounted
## Scripted pilot for the Ronan "all-in" burst deck, used by tests/sim_matchup.gd (SimpleAI never holds Irina or the
## Arauto for a doubled burst). It HOLDS the burst pieces and plays everything else with SimpleAI. Each main phase it asks
## "if I fire every burst piece I can afford, is it lethal on the enemy Leader?"; if so it plays them, if not it waits.
## When no kill is possible now but one is possible next turn, it casts Cancelamento do Plano de Saúde on the enemy
## Leader first, so the Leader cannot heal out of reach.

const IRINA_ID := "irina_lancachamas"
const ARAUTO_ID := "arauto_repeteco"
const SOPRA_ID := "sopra_brasas"
const BOLA_ID := "bola_de_fogo"
const ERUPCAO_ID := "erupcao"
const RITUAL_ID := "ritual_do_degelo"
const CANCELAMENTO_ID := "cancelamento_do_plano_de_saude"

const IRINA_DAMAGE := 4
const SOPRA_DAMAGE := 1
const BOLA_DAMAGE := 3
const ERUPCAO_LEADER_DAMAGE := 4
const PAVIO_DAMAGE := 1
const RITUAL_MOMENTUM := 3

## Own turn number -> how many games fired the burst on that turn (read by the sim for its report).
static var fired_by_turn := {}
static var last_fired_turn := -1
## Own turn number -> the biggest Leader damage any affordable line reached at the start of that main phase (all games).
static var potential_by_turn := {}
static var last_sampled_turn := -1
static var running_max_damage := 0

static func step(g: GameState, p: int) -> Array:
	if g.phase == "main" and p == g.active and g.stack.is_empty():
		running_max_damage = 0
		var plan := _plan(g, p, 0)
		if g.turn != last_sampled_turn:
			last_sampled_turn = g.turn
			var own_turn: int = (g.turn + 1) / 2
			if not potential_by_turn.has(own_turn):
				potential_by_turn[own_turn] = []
			potential_by_turn[own_turn].append(running_max_damage)
		if not plan.is_empty():
			var events := g.play_card(p, int(plan["uid"]), int(plan["target"]))
			if not events.is_empty():
				_note_fired(g)
				return events
			var pavio_events := g.use_ability(p, int(plan["target"]))
			if not pavio_events.is_empty():
				return pavio_events
		elif _should_cancel_before_next_turn(g, p):
			var foe_leader: int = GameState.LEADER_UID[g.opponent(p)]
			var cancel_card := _first_in_hand(g, p, CANCELAMENTO_ID)
			var cancel_events := g.play_card(p, cancel_card.uid, foe_leader)
			if not cancel_events.is_empty():
				return cancel_events
	return SimpleAI.step(g, p, _held_card_ids(g, p))

static func _note_fired(g: GameState) -> void:
	if g.turn == last_fired_turn:
		return
	last_fired_turn = g.turn
	var own_turn: int = (g.turn + 1) / 2
	fired_by_turn[own_turn] = int(fired_by_turn.get(own_turn, 0)) + 1

## Cards SimpleAI must leave alone: the burst pieces. The Cancelamento is held while the Leader can still be killed
## through it (SimpleAI would waste it on a unit).
static func _held_card_ids(g: GameState, p: int) -> Array:
	var held: Array = [IRINA_ID, ARAUTO_ID, SOPRA_ID, BOLA_ID, ERUPCAO_ID, RITUAL_ID, CANCELAMENTO_ID]
	return held

static func _cards_in_hand(g: GameState, p: int, card_id: String) -> Array:
	var found: Array = []
	for card: Card in g.players[p]["hand"]:
		if card.card_id == card_id:
			found.append(card)
	return found

static func _first_in_hand(g: GameState, p: int, card_id: String) -> Card:
	var found := _cards_in_hand(g, p, card_id)
	return found[0] if not found.is_empty() else null

## The cheapest `count` cards first.
static func _cheapest_first(g: GameState, p: int, cards: Array) -> Array:
	var sorted_cards := cards.duplicate()
	sorted_cards.sort_custom(func(a: Card, b: Card) -> bool: return g.cost_of(p, a.data(), a) < g.cost_of(p, b.data(), b))
	return sorted_cards

static func _arauto_on_board(g: GameState, p: int) -> bool:
	for unit: Card in g.players[p]["board"]:
		if unit.card_id == ARAUTO_ID:
			return true
	return false

## True when the enemy Leader cannot be killed now, but the burst would kill it next turn (one more Momentum), and the
## Cancelamento is in hand and can be paid without hurting anything.
static func _should_cancel_before_next_turn(g: GameState, p: int) -> bool:
	var cancel_card := _first_in_hand(g, p, CANCELAMENTO_ID)
	if cancel_card == null or not g.can_play(p, cancel_card.uid):
		return false
	var foe := g.opponent(p)
	if g.leader_heal_blocked(foe):
		return false
	return not _best_line(g, p, 1, true).is_empty()

## The next card to play (or {"uid": 0, "target"} for Pavio Curto) of a lethal burst, as {uid, target}; {} when none.
static func _plan(g: GameState, p: int, extra_momentum: int) -> Dictionary:
	var line := _best_line(g, p, extra_momentum, false)
	if line.is_empty():
		return {}
	var foe_leader: int = GameState.LEADER_UID[g.opponent(p)]
	var order: Array = line["order"]
	if order.is_empty():
		return {}
	return {"uid": int(order[0]), "target": foe_leader}

## The cheapest lethal line (fewest pieces) among all counts of each piece, as {order, damage}; {} if none.
## `extra_momentum`: Momentum added to this turn's budget (to look one turn ahead).
## `look_ahead`: plan for next turn, so the cards in hand count but the Momentum is the next turn's.
static func _best_line(g: GameState, p: int, extra_momentum: int, look_ahead: bool) -> Dictionary:
	var foe := g.opponent(p)
	var foe_hp := int(g.players[foe]["leader_hp"])
	var pl: Dictionary = g.players[p]
	var budget := g.budget(p, true)
	if look_ahead:
		budget = mini(g.momentum_cap(p), int(pl["turn_start_momentum"]) + extra_momentum)
	else:
		budget += extra_momentum
	var free_slots: int = GameState.BOARD_LIMIT - pl["board"].size()
	var irinas := _cheapest_first(g, p, _cards_in_hand(g, p, IRINA_ID))
	var sopras := _cheapest_first(g, p, _cards_in_hand(g, p, SOPRA_ID))
	var bolas := _cheapest_first(g, p, _cards_in_hand(g, p, BOLA_ID))
	var erupcoes := _cheapest_first(g, p, _cards_in_hand(g, p, ERUPCAO_ID))
	var rituais := _cheapest_first(g, p, _cards_in_hand(g, p, RITUAL_ID))
	var arautos := _cheapest_first(g, p, _cards_in_hand(g, p, ARAUTO_ID))
	var doubled_already := _arauto_on_board(g, p)
	var pavio_ready := true if look_ahead else g.can_use_ability(p)
	var best: Dictionary = {}
	var arauto_options: Array = [0, 1] if not arautos.is_empty() and not doubled_already else [0]
	for use_arauto in arauto_options:
		for ritual_count in range(rituais.size() + 1):
			for irina_count in range(irinas.size() + 1):
				for sopra_count in range(sopras.size() + 1):
					if use_arauto + irina_count + sopra_count > free_slots:
						continue
					for bola_count in range(bolas.size() + 1):
						for erupcao_count in range(erupcoes.size() + 1):
							for pavio_count in range(2 if pavio_ready else 1):
								var line := _price_line(g, p, budget, {
									"arauto": arautos.slice(0, use_arauto), "rituais": rituais.slice(0, ritual_count),
									"irinas": irinas.slice(0, irina_count), "sopras": sopras.slice(0, sopra_count),
									"bolas": bolas.slice(0, bola_count), "erupcoes": erupcoes.slice(0, erupcao_count),
									"pavio": pavio_count, "doubled": doubled_already or use_arauto == 1,
								})
								if not line.is_empty():
									running_max_damage = maxi(running_max_damage, int(line["damage"]))
								if line.is_empty() or int(line["damage"]) < foe_hp:
									continue
								if best.is_empty() or line["order"].size() < best["order"].size():
									best = line
	return best

## Plays a line out on paper: Rituals first (each pays for itself and gives 3), then the Arauto, then the Irinas and
## Sopras (doubled by the Arauto), then the spells and Pavio. {} when it cannot be paid, else {order, damage}.
static func _price_line(g: GameState, p: int, budget: int, line: Dictionary) -> Dictionary:
	var order: Array = []
	var damage := 0
	var left := budget
	for ritual: Card in line["rituais"]:
		var ritual_cost := g.cost_of(p, ritual.data(), ritual)
		if ritual_cost > left:
			return {}
		left += RITUAL_MOMENTUM - ritual_cost
		order.append(ritual.uid)
	var multiplier := 2 if line["doubled"] else 1
	for arauto: Card in line["arauto"]:
		var arauto_cost := g.cost_of(p, arauto.data(), arauto)
		if arauto_cost > left:
			return {}
		left -= arauto_cost
		order.append(arauto.uid)
	for irina: Card in line["irinas"]:
		var irina_cost := g.cost_of(p, irina.data(), irina)
		if irina_cost > left:
			return {}
		left -= irina_cost
		damage += IRINA_DAMAGE * multiplier
		order.append(irina.uid)
	for sopra: Card in line["sopras"]:
		var sopra_cost := g.cost_of(p, sopra.data(), sopra)
		if sopra_cost > left:
			return {}
		left -= sopra_cost
		damage += SOPRA_DAMAGE * multiplier
		order.append(sopra.uid)
	for bola: Card in line["bolas"]:
		var bola_cost := g.cost_of(p, bola.data(), bola)
		if bola_cost > left:
			return {}
		left -= bola_cost
		damage += BOLA_DAMAGE
		order.append(bola.uid)
	for erupcao: Card in line["erupcoes"]:
		var erupcao_cost := g.cost_of(p, erupcao.data(), erupcao)
		if erupcao_cost > left:
			return {}
		left -= erupcao_cost
		damage += ERUPCAO_LEADER_DAMAGE
		order.append(erupcao.uid)
	if int(line["pavio"]) > 0:
		var pavio_cost := int(CardDB.leader(g.players[p]["leader_id"])["ability"]["cost"])
		if pavio_cost > left:
			return {}
		left -= pavio_cost
		damage += PAVIO_DAMAGE
		order.append(0) # 0 = Pavio Curto
	return {"order": order, "damage": damage}
