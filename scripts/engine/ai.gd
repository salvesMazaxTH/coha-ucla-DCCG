class_name SimpleAI
extends RefCounted
## Greedy AI: spends Momentum on the most expensive plays, then attacks one unit at a time:
## challenges that win or trade up, the enemy Leader's face when it is safe or worth the risk.

## Performs one action for player p. Returns its events, or [] when the AI
## has nothing more to do (the caller should then stop asking).
## `held_card_ids`: cards the AI must not play on its own (a scripted pilot, see ComboPilot, plays them).
static func step(g: GameState, p: int, held_card_ids: Array = []) -> Array:
	match g.phase:
		"mulligan":
			var cards_to_return: Array = []
			for card: Card in g.players[p]["hand"]:
				if _base_cost(card) >= 5 and cards_to_return.size() < GameState.MULLIGAN_MAX:
					cards_to_return.append(card.uid)
			return g.mulligan(p, cards_to_return)
		"enter_tapped":
			var waiting_unit := g.find_unit(int(g.pending_tap[0]))
			return g.choose_enter_tapped(p, _wants_enter_tapped(g, p, waiting_unit))
		"search":
			return g.choose_search(p, _choose_search(g))
		"enter_target":
			var card_data := CardDB.card(g.pending_enter["card_id"])
			var asked_spec: String = g.pending_enter["spec2"] if g.pending_enter.has("first") else g.pending_enter["spec"]
			var target := _pick_target(g, p, asked_spec, card_data, int(g.pending_enter["uid"]))
			var events := g.choose_enter_target(p, target)
			return events if not events.is_empty() else g.choose_enter_target(p, 0)
		"discard":
			var hand := _hand_most_expensive_first(g, p)
			var uids_to_discard: Array = []
			for i in hand.size() - GameState.HAND_LIMIT:
				uids_to_discard.append(hand[i].uid)
			return g.discard(p, uids_to_discard)
		"combat":
			if g.window == "attacks" and p == g.active and g.stack.is_empty():
				# the attacks: one attack per step, ending the combat when nothing is worth it
				var attack_events := _try_attack(g, p)
				return attack_events if not attack_events.is_empty() else g.end_combat(p)
			# the pre-combat window (or an answer on the stack): play a Rápido/Instantâneo if there
			# is a worthwhile one, otherwise pass
			var events := _try_play(g, p, held_card_ids)
			return events if not events.is_empty() else g.pass_priority(p)
		"main":
			if not g.stack.is_empty() or p != g.active:
				var response := _try_play(g, p, held_card_ids)
				return response if not response.is_empty() else g.pass_priority(p)
			var events := _try_play(g, p, held_card_ids)
			if not events.is_empty():
				return events
			if g.can_go_to_combat(p):
				return g.go_to_combat(p)
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
	var discarding: bool = g.pending_search.get("discard_hand", false)
	# search options are plain dicts {uid, card_id}
	for option in g.pending_search.get("cards", []):
		var card_data := CardDB.card(option["card_id"])
		var score := int(card_data.get("cost", 0)) * 10
		if card_data.get("type", "") == "unit":
			score += 2
		if discarding:
			score = -score # a discard gives up the least valuable card in hand
		if score > best_score:
			best_score = score
			best_uid = int(option["uid"])
	return best_uid

static func _try_play(g: GameState, p: int, held_card_ids: Array = []) -> Array:
	if g.can_cast_legendary(p):
		var events := g.cast_legendary(p)
		if not events.is_empty():
			return events
	# hand first; Réquiem spells in the graveyard are the fallback (they cost 2 more)
	var candidates: Array = _hand_most_expensive_first(g, p) + g.requiem_cards(p)
	for card: Card in candidates:
		if held_card_ids.has(card.card_id) or not g.can_play(p, card.uid):
			continue
		var card_data := CardDB.card(card.card_id)
		var is_unit: bool = card_data["type"] == "unit"
		if not is_unit and (g.is_dud(p, card_data) or not _spell_is_worth_it(g, p, card_data)):
			continue
		var spec := g.card_spec(card_data)
		var target := _pick_sacrifice(g, p) if card_data.get("cost_sacrifice", false) else _pick_target(g, p, spec, card_data, 0, not is_unit)
		var spec2 := g.second_spec(card_data)
		var second_target := 0
		if _has_sacrifice_effect(card_data):
			# Mordida / Colheita / Tributo: what is given up and where the damage goes is one decision
			var plan := _plan_sacrifice_spell(g, p, card_data)
			if plan.is_empty():
				continue
			target = plan[0]
			second_target = plan[1] if spec2 != "" else 0
		elif _has_fight(card_data):
			# a fight needs a matching pair, not the "biggest" unit of each side
			var pair := _pick_fight(g, p)
			if pair.is_empty():
				continue
			target = pair[0]
			second_target = pair[1]
		elif not is_unit and spec == "ally_unit" and not _temporary_buff_effect(card_data).is_empty():
			# a this-turn buff goes to the strongest ally that will actually attack with it
			var best_attack := -1
			for unit: Card in _temporary_buff_beneficiaries(g, p, _temporary_buff_effect(card_data)):
				if unit.atk_total() > best_attack:
					best_attack = unit.atk_total()
					target = unit.uid
		elif spec != "" and target == 0 and not is_unit:
			continue
		elif spec2 != "":
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
		if g.can_activate(p, unit.uid) and g.target_spec(activated_effects) == "" and g.can_attack(unit) and _revive_is_worth_it(g, p, activated_effects):
			return g.activate(p, unit.uid)
	for artifact: Card in g.players[p]["relics"]:
		# free-standing artifacts' untargeted Ao Ativar (e.g. Ossuário Sem Fundo's revive)
		var artifact_effects: Array = CardDB.card(artifact.card_id).get("activated", {}).get("effects", [])
		if g.can_activate(p, artifact.uid) and g.target_spec(artifact_effects) == "" and _revive_is_worth_it(g, p, artifact_effects):
			return g.activate(p, artifact.uid)
	for unit: Card in g.players[p]["board"]:
		if g.can_transform(p, unit.uid):
			return g.transform(p, unit.uid)
	if g.can_use_ability(p):
		var ability: Dictionary = CardDB.leader(g.players[p]["leader_id"])["ability"]
		var ability_spec := g.target_spec(ability["effects"])
		var target := _pick_target(g, p, ability_spec, ability, 0, true)
		var temporary_armor := _temporary_armor_amount(ability["effects"])
		if temporary_armor > 0:
			# Massa Inamolgável: the bonus is temporary, so it is only worth Momentum to save an ally from a kill
			target = _pick_armor_save(g, p, temporary_armor)
		if ability_spec == "" or target != 0:
			return g.use_ability(p, target)
	return []

## Temporary Armadura an ability gives to one ally (Massa Inamolgável), or 0 when it has none.
static func _temporary_armor_amount(effects: Array) -> int:
	for effect in effects:
		if effect.get("action") == "buff" and effect.get("target", "") == "ally_unit":
			return int(effect.get("armor_temp", 0))
	return 0

## The ally that `bonus` extra Armadura saves from dying: an enemy unit can challenge it and kill it as it
## is, and with the bonus none of the enemy units that can challenge it still kills it. When several
## qualify the most valuable one is picked. 0 when nobody is in that danger (the ability is not used).
static func _pick_armor_save(g: GameState, p: int, bonus: int) -> int:
	var best_uid := 0
	var best_value := -999
	for ally: Card in g.players[p]["board"]:
		if ally.shield:
			continue # the shield already absorbs the first hit
		var killed_today := false
		var killed_with_bonus := false
		for enemy_unit: Card in g.players[g.opponent(p)]["board"]:
			if not g.can_challenge(enemy_unit, ally):
				continue
			var attack := g.atk_of(enemy_unit)
			if g.damage_after_armor(ally, attack) >= g.hp_left(ally):
				killed_today = true
			if maxi(1, attack - g.armor_of(ally) - bonus) >= g.hp_left(ally):
				killed_with_bonus = true
		if killed_today and not killed_with_bonus and _unit_value(g, ally) > best_value:
			best_value = _unit_value(g, ally)
			best_uid = ally.uid
	return best_uid

## True when the card has a "sacrifice" effect (Mordida de Defunto, Colheita de Almas, Tributo ao Abismo).
static func _has_sacrifice_effect(card_data: Dictionary) -> bool:
	for effect in card_data.get("effects", []):
		if effect.get("action") == "sacrifice":
			return true
	return false

## Plan for a spell that sacrifices an ally: returns [ally to sacrifice, damage target] or [] when it
## isn't worth casting now. Damage-after-sacrifice spells are finishers: they fire when the damage
## kills the enemy Leader (giving up the smallest ally that is enough) or when they trade a cheap ally
## for a clearly more valuable enemy unit. Without damage (Tributo ao Abismo) the weakest ally is given up.
static func _plan_sacrifice_spell(g: GameState, p: int, card_data: Dictionary) -> Array:
	var allies: Array = g.players[p]["board"]
	if allies.is_empty():
		return []
	var damage_effect: Dictionary = {}
	for effect in card_data["effects"]:
		for follow_up in effect.get("then", []):
			if follow_up.get("action") == "damage":
				damage_effect = follow_up
	if damage_effect.is_empty():
		var weakest_uid := _pick_sacrifice(g, p)
		return [weakest_uid, 0] if weakest_uid != 0 else []
	var foe: int = g.opponent(p)
	var foe_leader_uid: int = GameState.LEADER_UID[foe]
	var leader_hp: int = g.players[foe]["leader_hp"]
	var from_attack: bool = damage_effect.get("amount_from", "") == "sacrificed_atk"
	var lethal_ally: Card = null
	var lethal_damage := 999
	for ally: Card in allies:
		var damage: int = ally.atk_total() if from_attack else int(damage_effect.get("amount", 0))
		if damage >= leader_hp and damage < lethal_damage:
			lethal_damage = damage
			lethal_ally = ally
	if lethal_ally != null:
		return [lethal_ally.uid, foe_leader_uid]
	if not from_attack:
		return [] # fixed damage that doesn't finish the Leader: not worth a unit
	# no lethal: only trade a cheap ally for an enemy unit worth clearly more
	var best_plan: Array = []
	var best_gain := 2
	for ally: Card in allies:
		for enemy_unit: Card in g.players[foe]["board"]:
			if enemy_unit.shield or enemy_unit.spell_shield or not g.valid_targets(p, "any").has(enemy_unit.uid):
				continue
			if g.damage_after_armor(enemy_unit, ally.atk_total()) < g.hp_left(enemy_unit):
				continue
			var gain := _unit_value(g, enemy_unit) - _unit_value(g, ally)
			if gain > best_gain:
				best_gain = gain
				best_plan = [ally.uid, enemy_unit.uid]
	return best_plan

## Filters out plays that would waste Momentum: heals with little to heal, revives of trivial units
## and area removal that isn't worth it (see _sweeper_is_worth_it).
static func _spell_is_worth_it(g: GameState, p: int, card_data: Dictionary) -> bool:
	var effects: Array = card_data.get("effects", [])
	if not _revive_is_worth_it(g, p, effects):
		return false
	var temporary_buff := _temporary_buff_effect(card_data)
	if not temporary_buff.is_empty() and _temporary_buff_beneficiaries(g, p, temporary_buff).is_empty():
		return false
	for effect in effects:
		var action: String = effect.get("action", "")
		if action in ["heal_unit", "heal_leader", "heal_full"] and not _heal_is_worth_it(g, p, effect):
			return false
		if action in ["damage", "destroy"] and effect.get("target", "") in ["all_enemy_units", "all_units"]:
			if not _sweeper_is_worth_it(g, p, effect):
				return false
	return true

## The buff effect of a spell whose gain only lasts this turn (+ATK, Ímpeto, Crítico...), or {} when the
## card has none. Such a buff is wasted unless an ally actually attacks with it.
static func _temporary_buff_effect(card_data: Dictionary) -> Dictionary:
	for effect in card_data.get("effects", []):
		if effect.get("action") == "buff" and effect.get("target", "") in ["ally_unit", "all_ally_units"] \
				and (effect.get("temp", false) or int(effect.get("critico_temp", 0)) > 0):
			return effect
	return {}

## Allies that would really use a this-turn buff: it must be our own turn and the unit must have something
## to hit once it has the keywords the buff grants (Ímpeto lets a fresh unit challenge, never go face).
static func _temporary_buff_beneficiaries(g: GameState, p: int, effect: Dictionary) -> Array:
	var beneficiaries: Array = []
	if g.active != p:
		return beneficiaries
	for unit: Card in g.players[p]["board"]:
		var granted: Array = []
		for keyword in effect.get("keywords", []):
			if not unit.keywords.has(keyword):
				granted.append(keyword)
		unit.keywords.append_array(granted)
		var has_target := not g.attack_targets(unit).is_empty()
		for keyword in granted:
			unit.keywords.erase(keyword)
		if has_target:
			beneficiaries.append(unit)
	return beneficiaries

## A heal needs enough missing life to be worth the card: all but 1 point of it must land, unless the
## own Leader is in danger (then any real heal counts).
static func _heal_is_worth_it(g: GameState, p: int, effect: Dictionary) -> bool:
	var amount := int(effect.get("amount", 99))
	var leader_missing: int = g.players[p]["leader_max"] - g.players[p]["leader_hp"]
	var most_missing := 0
	var total_unit_missing := 0
	for unit: Card in g.players[p]["board"]:
		most_missing = maxi(most_missing, unit.damage)
		total_unit_missing += unit.damage
	var target: String = effect.get("target", "")
	if target == "own_leader":
		most_missing = leader_missing
	elif target == "all_ally_units":
		most_missing = total_unit_missing
	elif target == "ally_or_own_leader":
		most_missing = maxi(most_missing, leader_missing)
	var leader_in_danger: bool = g.players[p]["leader_hp"] <= 8 and leader_missing >= 2 and target != "all_ally_units"
	return most_missing >= maxi(1, amount - 1) or leader_in_danger

## Pressure = our Leader is low, or the enemy board outnumbers ours by 2+.
static func _under_pressure(g: GameState, p: int) -> bool:
	return g.players[p]["leader_hp"] <= 10 or g.players[g.opponent(p)]["board"].size() >= g.players[p]["board"].size() + 2

## Area removal: worth it when it kills 2+ enemy units for more value than it costs us, or, under real
## pressure, 1+ of them. Never to kill a lone unit while we are comfortable.
static func _sweeper_is_worth_it(g: GameState, p: int, effect: Dictionary) -> bool:
	var killed_enemies := 0
	var net_value := 0
	var hits_own: bool = effect.get("target", "") == "all_units"
	for side in [g.opponent(p), p]:
		if side == p and not hits_own:
			continue
		for unit: Card in g.players[side]["board"]:
			var dies: bool = effect.get("action") == "destroy" or g.damage_after_armor(unit, int(effect.get("amount", 0))) >= g.hp_left(unit)
			if not dies or unit.shield or unit.spell_shield:
				continue
			if side == p:
				net_value -= _unit_value(g, unit)
			else:
				killed_enemies += 1
				net_value += _unit_value(g, unit)
	if net_value <= 0:
		return false
	return killed_enemies >= 2 or (killed_enemies >= 1 and _under_pressure(g, p))

## Reviving only pays when the best unit that could come back is not a throwaway.
static func _revive_is_worth_it(g: GameState, p: int, effects: Array) -> bool:
	for effect in effects:
		var action: String = effect.get("action", "")
		if action != "revive" and action != "revive_pick":
			continue
		var best_cost := -1
		for option in g.revive_options(p, int(effect.get("max_cost", 99))):
			best_cost = maxi(best_cost, int(CardDB.card(option["card_id"]).get("cost", 0)))
		if best_cost < 2 or not g.has_free_slot(p):
			return false
	return true

static func _has_fight(card_data: Dictionary) -> bool:
	for effect in card_data.get("effects", []):
		if effect.get("action") == "fight":
			return true
	return false

## Best fight for a "fight" spell: an ally that kills an enemy unit and survives the fight.
## Returns [ally uid, enemy uid], or [] when no fight is worth it. Armadura counts on both sides.
static func _pick_fight(g: GameState, p: int) -> Array:
	var best_pair: Array = []
	var best_score := 0
	for ally: Card in g.players[p]["board"]:
		for enemy: Card in g.players[g.opponent(p)]["board"]:
			var damage_to_enemy := g.damage_after_armor(enemy, ally.atk_total())
			var damage_to_ally := g.damage_after_armor(ally, enemy.atk_total())
			var kills_enemy := damage_to_enemy >= enemy.hp_left() and not enemy.shield and not enemy.spell_shield
			var ally_survives := damage_to_ally < ally.hp_left() or ally.shield
			if kills_enemy and ally_survives:
				var score := enemy.atk_total() + enemy.hp_left()
				if score > best_score:
					best_score = score
					best_pair = [ally.uid, enemy.uid]
	return best_pair

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

## The effects of `source` that are played right when it is cast or enters (spells: on_play, units: on_enter,
## abilities: no trigger). Its other triggers (Ao Sofrer Dano, Ao Morrer...) happen later, on the
## card itself, so they must not decide who the chosen target should be: Ronan's own "Ao Sofrer Dano:
## ganhe +1 de Ataque" is a buff, and reading it as part of his Ao Entrar made the AI skip his damage.
static func _effects_that_use_the_pick(source) -> Array:
	var effects: Array = []
	if not (source is Dictionary):
		return effects
	for effect in source.get("effects", []):
		if effect.get("trigger", "") in ["", "on_play", "on_enter"]:
			effects.append(effect)
	return effects

## True when damage that leaves `unit` alive would make it better (an Ao Sofrer Dano buff, e.g. Ronan's +1 Ataque).
## A harmless Ao Sofrer Dano (nothing good for the unit) does not count: damaging it is just as fine.
static func _punishes_surviving_damage(unit: Card) -> bool:
	for effect in unit.data().get("effects", []):
		if effect.get("trigger", "") == "on_damaged" and effect.get("action", "") == "buff":
			return true
	return false

## Hostile effects pick the biggest enemy (or the Leader); friendly ones the biggest ally.
## Damage that doesn't kill is worth nothing on a unit with Regeneração (it heals at the end of the turn)
## or one that gets stronger from it; on any other unit it stays marked, so it is never skipped.
## `strict` (spells and abilities): that chip damage is only worth its amount (the face is usually better).
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
	var effects: Array = _effects_that_use_the_pick(source)
	if spec == "ally_or_own_leader":
		return _most_damaged(g, p, options)
	var friendly := spec in ["ally_unit", "other_ally_unit", "ally_or_own_leader"]
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
				var damage_amount := 0
				for effect in effects:
					if effect.get("action") == "damage":
						hits = true
						damage_amount += int(effect["amount"])
						if int(effect["amount"]) >= unit.hp_left() and not unit.shield:
							kills = true
				if kills:
					score += 10
				elif hits:
					# Damage that doesn't kill stays marked on the unit, so it is worth doing...
					if unit.has_kw("regeneracao"):
						continue # ...except on Regeneração: it heals at the end of the turn
					if _punishes_surviving_damage(unit):
						continue # ...and except on a unit that grows stronger from it (Ao Sofrer Dano)
					if strict:
						score = damage_amount + 1 # chip damage from a spell: the face is usually better
				if unit.spell_shield:
					score -= 20 # wasted on Escudo de Feitiço
		if score > best_score:
			best_score = score
			best_uid = uid
	return best_uid

## One attack (or [] when no attack is worth it). Priorities, best first:
##   1. lethal on the enemy Leader;
##   2. a challenge that kills the target without losing the attacker, or trades up;
##   3. the enemy Leader's face, when going all-in, under pressure, or when the tapped attacker
##      won't be punished by an enemy challenge on their turn.
static func _try_attack(g: GameState, p: int) -> Array:
	var enemy := g.opponent(p)
	var enemy_leader_uid: int = GameState.LEADER_UID[enemy]
	var enemy_board: Array = g.players[enemy]["board"]
	var ready: Array = []
	for unit: Card in g.players[p]["board"]:
		# a 0 ATK unit may attack, but it would only be hit back for nothing: the AI never does it
		if g.atk_of(unit) > 0 and not g.attack_targets(unit).is_empty():
			ready.append(unit)
	if ready.is_empty():
		return []
	var all_in := _lethal_push(g, p, ready)
	var best_challenge_score := 0
	var best_challenge: Array = [] # [attacker uid, target uid]
	var face_attacker: Card = null
	for attacker: Card in ready:
		var targets := g.attack_targets(attacker)
		if targets.has(enemy_leader_uid) and g.atk_of(attacker) >= g.players[enemy]["leader_hp"]:
			return g.attack_unit(p, attacker.uid, enemy_leader_uid) # this hit wins the game
		# a tapped enemy (Provocação or not) closes the face: it must challenge (a fresh Ímpeto unit just can't reach the face yet)
		var forced := (not attacker.sick or g.combat_system().is_rompante_rush(attacker)) and not targets.has(enemy_leader_uid)
		for target_uid in targets:
			if target_uid < 0:
				continue
			var score := _challenge_score(g, attacker, g.find_unit(target_uid))
			if forced:
				score = maxi(score, 1) # it must challenge someone anyway: pick the best one
			if score > best_challenge_score:
				best_challenge_score = score
				best_challenge = [attacker.uid, target_uid]
		if face_attacker == null and targets.has(enemy_leader_uid):
			# aggression: push when the enemy is low or we have many more units. An engine unit
			# never goes face if that leaves it exposed to any enemy that can kill it, pressure or not.
			var pressure: bool = g.players[enemy]["leader_hp"] <= 10 or g.players[p]["board"].size() > enemy_board.size() + 1
			var exposed := _punishable(g, attacker, 0, _is_engine(attacker))
			if all_in or enemy_board.is_empty() or not exposed or (pressure and not _is_engine(attacker)):
				face_attacker = attacker
	if not best_challenge.is_empty() and not all_in:
		return g.attack_unit(p, best_challenge[0], best_challenge[1])
	if face_attacker != null:
		return g.attack_unit(p, face_attacker.uid, enemy_leader_uid)
	if not best_challenge.is_empty():
		return g.attack_unit(p, best_challenge[0], best_challenge[1])
	return []

## How good it is for `attacker` to challenge `target` (0 or less = not worth it). Strikes follow
## Rapidez: a faster attacker that kills its target takes nothing back. Challenging also taps the
## attacker, so a survivor that the enemy can then kill on their turn counts as a delayed trade.
static func _challenge_score(g: GameState, attacker: Card, target: Card) -> int:
	var damage_to_target := 0 if target.shield else g.damage_after_armor(target, g.atk_of(attacker))
	var kills_target := damage_to_target >= g.hp_left(target)
	var strikes_first := attacker.rapidez_total() > target.rapidez_total()
	var damage_back := 0 if attacker.shield or (kills_target and strikes_first) else g.damage_after_armor(attacker, g.atk_of(target))
	var attacker_dies := damage_back >= g.hp_left(attacker)
	var target_value := _unit_value(g, target)
	var attacker_value := _unit_value(g, attacker)
	if kills_target and not attacker_dies:
		if _punishable(g, attacker, damage_back, _is_engine(attacker)):
			return target_value - attacker_value + 1 # it will be challenged back and die: a slow trade
		return target_value + 10
	if kills_target and attacker_dies:
		return target_value - attacker_value + 1 # a trade: only worth it against something more valuable
	if not attacker_dies and damage_to_target > 0 and not _is_engine(attacker):
		return 1 # chip damage that stays marked; only used when nothing better exists
	return 0

## How much a unit is worth keeping (or killing): its stats on the board, what was paid for it,
## and a bonus for engines, whose effects keep paying off while they live.
static func _unit_value(g: GameState, unit: Card) -> int:
	var value := g.atk_of(unit) + g.hp_left(unit) + int(unit.data().get("cost", 0))
	if _is_engine(unit):
		value += 4
	return value

## Triggers that keep paying off turn after turn while the unit stays on the board.
const ENGINE_TRIGGERS := ["on_ally_death", "on_turn_start", "on_turn_end", "constante"]

## True for a synergy engine (e.g. Diabrete Sombrio: "Aliado Morre"): a unit with a repeating
## trigger, an Ao Ativar ability, or a Lendário. The AI avoids leaving these exposed to a trade.
static func _is_engine(unit: Card) -> bool:
	var card_data := unit.data()
	if unit.legendary or card_data.has("activated"):
		return true
	for effect in card_data.get("effects", []):
		if ENGINE_TRIGGERS.has(effect.get("trigger", "")):
			return true
	return false

## True when, once tapped (and after taking `extra_damage`), this unit could be challenged and
## killed on the enemy's turn by an enemy unit that survives the exchange. With `any_killer`,
## even an enemy that dies doing it counts (an engine should not be traded off at all).
static func _punishable(g: GameState, unit: Card, extra_damage := 0, any_killer := false) -> bool:
	var was_exhausted := unit.exhausted
	unit.exhausted = true # pretend it already attacked, to ask who could challenge it
	unit.damage += extra_damage # the damage it would carry after this attack
	var punished := false
	for enemy_unit: Card in g.players[g.opponent(unit.owner)]["board"]:
		if not g.can_challenge(enemy_unit, unit):
			continue
		var kills := not unit.shield and g.damage_after_armor(unit, g.atk_of(enemy_unit)) >= g.hp_left(unit)
		var survives := enemy_unit.shield or g.damage_after_armor(enemy_unit, g.atk_of(unit)) < g.hp_left(enemy_unit)
		if kills and (survives or any_killer):
			punished = true
	unit.damage -= extra_damage
	unit.exhausted = was_exhausted
	return punished

## True when the ready units that can reach the enemy Leader deal enough to kill it.
static func _lethal_push(g: GameState, p: int, ready: Array) -> bool:
	var enemy_leader_uid: int = GameState.LEADER_UID[g.opponent(p)]
	var face_damage := 0
	for attacker: Card in ready:
		if g.attack_targets(attacker).has(enemy_leader_uid):
			face_damage += g.atk_of(attacker)
	return face_damage >= g.players[g.opponent(p)]["leader_hp"]

## A Provocação entering: tapped makes it guard (enemy attackers must challenge it). Worth it
## when it survives the strongest enemy hit, or when our Leader is low and needs the protection.
static func _wants_enter_tapped(g: GameState, p: int, unit: Card) -> bool:
	if unit == null:
		return false
	var strongest_enemy_atk := 0
	for enemy_unit: Card in g.players[g.opponent(p)]["board"]:
		strongest_enemy_atk = maxi(strongest_enemy_atk, g.atk_of(enemy_unit))
	var survives := unit.shield or g.damage_after_armor(unit, strongest_enemy_atk) < g.hp_left(unit)
	return survives or g.players[p]["leader_hp"] <= 10

## The healing pick: whichever option (own Leader or ally unit) has the most damage to heal.
## Ties go to the Leader, which is listed last.
static func _most_damaged(g: GameState, p: int, options: Array) -> int:
	var best_uid := 0
	var most_damage := -1
	for uid in options:
		var damage := 0
		if uid < 0:
			damage = g.players[p]["leader_max"] - g.players[p]["leader_hp"]
		else:
			damage = g.find_unit(uid).damage
		if damage >= most_damage:
			most_damage = damage
			best_uid = uid
	return best_uid
