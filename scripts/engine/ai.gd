class_name SimpleAI
extends RefCounted
## Greedy AI: spends Momentum on the most expensive plays, then attacks one unit at a time:
## challenges that win or trade up, the enemy Leader's face when it is safe or worth the risk.

## Aggression knobs (see _try_attack, _face_hit_is_acceptable and _burn_plan).
const FREE_KILL_BONUS := 10 ## challenge score added for a kill that costs nothing; a score above it = take it at once
const TRADE_MIN_GAIN := 3 ## a trade must be worth at least this much value to be taken (even trades are not)
const RUSH_TURNS := 2 ## "rush" when the Leader (minus burn in hand) dies within this many swings of the ready board
const HOLD_TURNS := 2 ## hold burn for the face when the Leader dies within this many swings of the whole board plus burn
const FACE_POINT_VALUE := 2 ## value of 1 face damage when deciding whether an exposed unit may go face
const FACE_POINT_VALUE_LATE := 3 ## same, with the enemy Leader low (NEAR_END_HP) or late in the game (LATE_GAME_TURN)
const NEAR_END_HP := 12
const LATE_GAME_TURN := 16

## The Encarnação competes with the hand (see _untaxed_incarnation_should_come_first and _incarnation_rank_against_hand).
const INCARNATION_WALL_MIN_UNITS := 4 ## an enemy board this wide may be too dangerous to cast into
const INCARNATION_WALL_STAT_LIMIT := 20 ## ...when its units' Ataque + Vida (current) add up to this much: ~5 per unit, i.e. real
## units. Four 0/2 fichas add up to 8 and never stop the cast; four 2/3 units add up to 20 and do.
const INCARNATION_RELIEF_MAX_CHAIN := 3 ## when the table is dangerous, hand plays of up to this many cards are tried (on a copy) to see if they fix it
const INCARNATION_MAX_EXTRA_WASTED_MOMENTUM := 2 ## casting may leave at most this much more Momentum unspent than keeping it for the hand would
const INCARNATION_HEAVY_TAX := 3 ## from the third cast on (tax 3+) a hand card of the same cost is usually stronger than the Encarnação
const INCARNATION_RANK_FIRST := 99 ## rank of an Encarnação cast before every card of the hand

## Performs one action for player p. Returns its events, or [] when the AI
## has nothing more to do (the caller should then stop asking).
## `held_card_ids`: cards the AI must not play on its own (a scripted pilot, see ComboPilot, plays them).
static func step(g: GameState, p: int, held_card_ids: Array = []) -> Array:
	match g.phase:
		"mulligan":
			return g.mulligan(p, _mulligan_returns(g, p))
		"enter_tapped":
			var waiting_unit := g.find_unit(int(g.pending_tap[0]))
			return g.choose_enter_tapped(p, _wants_enter_tapped(g, p, waiting_unit))
		"search":
			return g.choose_search(p, _choose_search(g))
		"enter_target":
			var card_data := CardDB.card(g.pending_enter["card_id"])
			var asked_spec: String = g.pending_enter["spec2"] if g.pending_enter.has("first") else g.pending_enter["spec"]
			# lethal first: the damage goes to the Leader when it is the road to the win, otherwise the usual pick
			var target := _lethal_enter_target(g, p, card_data, asked_spec, int(g.pending_enter["uid"]))
			if target == 0:
				target = _pick_target(g, p, asked_spec, card_data, int(g.pending_enter["uid"]))
			var events := g.choose_enter_target(p, target)
			return events if not events.is_empty() else g.choose_enter_target(p, 0)
		"effect_choice":
			return _choose_effect_option(g, p)
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

static func _choose_effect_option(g: GameState, p: int) -> Array:
	var options: Array = g.pending_effect_choice.get("options", [])
	var best_index := -1
	var best_target := 0
	var best_score := -INF
	for index in options.size():
		if not g.effect_choice_available(index):
			continue
		var option: Dictionary = options[index]
		var targets := g.effect_choice_targets(index)
		if targets.is_empty():
			targets = [0]
		for uid in targets:
			var actual_uid := int(uid)
			if actual_uid == 0:
				actual_uid = int(g.pending_effect_choice["opposed"])
			var unit := g.find_unit(actual_uid)
			var damage := 0
			var score := 0.0
			for effect: Dictionary in option.get("effects", []):
				if effect.get("action", "") == "damage":
					damage += int(effect.get("amount", 0))
				elif effect.get("action", "") in ["draw", "buff", "heal_unit", "heal_leader", "add_dot"]:
					score += 1.0
			if unit != null:
				var sign := 1.0 if unit.owner != p else -1.0
				score += sign * float(mini(damage, g.hp_left(unit)))
				if damage >= g.hp_left(unit):
					score += sign * float(g.atk_of(unit) + 3)
			elif actual_uid < 0:
				score += float(damage) if actual_uid == GameState.LEADER_UID[g.opponent(p)] else -float(damage)
			if actual_uid != 0 and actual_uid == int(g.pending_effect_choice["opposed"]):
				score += 1.0
			if score > best_score:
				best_score = score
				best_index = index
				best_target = int(uid)
	if best_index < 0:
		push_error("No available effect choice for AI")
		return []
	return g.choose_effect_option(p, best_index, best_target)

## Printed cost of a card (ignores discounts).
static func _base_cost(card: Card) -> int:
	return int(CardDB.card(card.card_id)["cost"])

## Cards of the opening hand to put back. Goes from the most to the least expensive card: every card of cost 5+
## goes back, and the hand keeps at most one card of cost 4 and two of cost 3, so it can still play something in the first turns.
static func _mulligan_returns(g: GameState, p: int) -> Array:
	var cards_to_return: Array = []
	var kept_cost_four := 0
	var kept_cost_three := 0
	for card: Card in _hand_most_expensive_first(g, p):
		if cards_to_return.size() >= GameState.MULLIGAN_MAX:
			break
		var cost := _base_cost(card)
		if cost >= 5:
			cards_to_return.append(card.uid)
		elif cost == 4:
			if kept_cost_four >= 1:
				cards_to_return.append(card.uid)
			else:
				kept_cost_four += 1
		elif cost == 3:
			if kept_cost_three >= 2:
				cards_to_return.append(card.uid)
			else:
				kept_cost_three += 1
	return cards_to_return

## Copy of the hand sorted from the most to the least expensive card.
static func _hand_most_expensive_first(g: GameState, p: int) -> Array:
	var hand: Array = g.players[p]["hand"].duplicate()
	hand.sort_custom(func(a: Card, b: Card): return _base_cost(a) > _base_cost(b))
	return hand

static func _choose_search(g: GameState) -> int:
	var best_uid := 0
	var best_score := -999
	# a discard and a forced sacrifice (Censo de Baixas) both give up the least valuable option
	var discarding: bool = g.pending_search.get("discard_hand", false) or g.pending_search.get("sacrifice_pick", false)
	if g.pending_search.get("hand_bottom", false):
		# Bob Veyr: take the opponent's best card, unless it is a unit and the discards would cost more than it is worth
		var best_foe_card := 0
		var best_foe_cost := -1
		for option in g.pending_search.get("cards", []):
			var foe_data := CardDB.card(option["card_id"])
			var foe_cost := int(foe_data.get("cost", 0))
			foe_cost -= 4 * int(g.pending_search.get("discard_cost", 0))
			if foe_data.get("type", "") == "unit":
				foe_cost -= 4 * int(g.pending_search.get("discard_if_unit", 0))
			if foe_cost > best_foe_cost:
				best_foe_cost = foe_cost
				best_foe_card = int(option["uid"])
		if int(g.pending_search.get("cost_increase", 0)) > 0:
			return best_foe_card # Cornélia Aldrovane: nothing is lost by taxing the opponent's priciest card
		return best_foe_card if best_foe_cost >= 0 else 0
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
	# the road to lethal comes first, before the Momentum is spent on anything else: burn, Ao Entrar damage,
	# Rompante and this-turn buffs that, added to the board's hits, finish the enemy Leader
	if g.active == p and g.stack.is_empty():
		var lethal_events := _play_toward_lethal(g, p, held_card_ids)
		if not lethal_events.is_empty():
			return lethal_events
	# the untaxed Encarnação goes before the hand: the earlier the champion is out, the more it snowballs
	if _untaxed_incarnation_should_come_first(g, p):
		var first_incarnation_events := g.cast_incarnation(p)
		if not first_incarnation_events.is_empty():
			return first_incarnation_events
	# the Encarnação sits in the hand's ordering at the place its cost earns (see _incarnation_rank_against_hand)
	var incarnation_rank := _incarnation_rank_against_hand(g, p)
	var incarnation_was_tried := false
	# hand first; Réquiem spells in the graveyard are the fallback (they cost 2 more)
	var candidates: Array = _hand_most_expensive_first(g, p) + g.requiem_cards(p)
	for card: Card in candidates:
		if not incarnation_was_tried and incarnation_rank >= _base_cost(card):
			incarnation_was_tried = true
			var ranked_incarnation_events := g.cast_incarnation(p)
			if not ranked_incarnation_events.is_empty():
				return ranked_incarnation_events
		if held_card_ids.has(card.card_id):
			continue
		var card_events := _try_play_card(g, p, card)
		if not card_events.is_empty():
			return card_events
	# Last resort: the Encarnação was ranked below everything the hand could play (or the hand had nothing
	# worth playing), so it still gets cast rather than leaving the Momentum unspent.
	if not incarnation_was_tried and g.can_cast_incarnation(p) and g.has_free_slot(p): # never banishes its own permanent to make room
		var incarnation_events := g.cast_incarnation(p)
		if not incarnation_events.is_empty():
			return incarnation_events
	for unit: Card in g.players[p]["board"]:
		# untargeted Ao Ativar, before attacking (e.g. Yuki's temporary attack)
		var activated_effects: Array = unit.data().get("activated", {}).get("effects", [])
		if g.can_activate(p, unit.uid) and g.target_spec(activated_effects) == "" and g.can_attack(unit) and _revive_is_worth_it(g, p, activated_effects) and _filtered_banish_is_worth_it(g, p, unit, activated_effects) and not _dot_only_effects_are_wasted(g, p, activated_effects):
			if unit.data().get("activated", {}).has("extra_cost"):
				# Ao Ativar with a discard-or-sacrifice cost (Drex): only worth it with a cheap payer (the enemy Leader is always a target)
				var payer_uid := _pick_activation_payer(g, p, unit)
				if payer_uid != 0:
					return g.activate(p, unit.uid, payer_uid)
				continue
			return g.activate(p, unit.uid)
	for artifact: Card in g.players[p]["relics"]:
		# free-standing artifacts' untargeted Ao Ativar (e.g. Ossuário Sem Fundo's revive)
		var artifact_effects: Array = CardDB.card(artifact.card_id).get("activated", {}).get("effects", [])
		# Bateria gives Reserve even when empty, and releases stored Momentum whenever there is room.
		if artifact.data().has("momentum_store"):
			var player: Dictionary = g.players[p]
			var can_gain_reserve := int(player["reserve"]) < GameState.RESERVE_CAP
			var can_release_stored := (
				artifact.stored_momentum > 0
				and int(player["momentum"]) < g.momentum_cap(p)
				and int(player["momentum_lock_turn"]) != g.turn
			)
			if not can_gain_reserve and not can_release_stored:
				continue
		if g.can_activate(p, artifact.uid) and g.target_spec(artifact_effects) == "" and _revive_is_worth_it(g, p, artifact_effects):
			return g.activate(p, artifact.uid)
	for artifact: Card in g.players[p]["relics"]:
		# Ampola / Garrafão Curativos: aimed heal, only when enough Vida is missing
		var heal_ability: Dictionary = CardDB.card(artifact.card_id).get("activated", {})
		var heal_effects: Array = heal_ability.get("effects", [])
		if heal_effects.size() == 1 and heal_effects[0].get("action", "") == "heal_unit" and g.can_activate(p, artifact.uid) and _heal_is_worth_it(g, p, heal_effects[0]):
			var heal_target := _pick_target(g, p, g.target_spec(heal_effects), heal_ability, artifact.uid, true)
			if heal_target != 0:
				return g.activate(p, artifact.uid, heal_target)
	for unit: Card in g.players[p]["board"]:
		if g.can_transform(p, unit.uid):
			return g.transform(p, unit.uid)
	if g.can_use_ability(p) and not _ability_borrows_momentum(CardDB.leader(g.players[p]["leader_id"])["ability"]["effects"]) \
			and not _dot_only_effects_are_wasted(g, p, CardDB.leader(g.players[p]["leader_id"])["ability"]["effects"]) \
			and _ability_is_worth_its_life_cost(g, p, CardDB.leader(g.players[p]["leader_id"])["ability"]) \
			and _ability_is_worth_its_graveyard_cost(g, p, CardDB.leader(g.players[p]["leader_id"])["ability"]):
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

## Plays one card of the hand (or a Réquiem spell of the graveyard) the way the AI would: picks its targets,
## skips it when it would change nothing, and returns the events, or [] when the card is not played.
## Used both for the real game and for plans made on a copy of it.
static func _try_play_card(g: GameState, p: int, card: Card) -> Array:
	if not g.can_play(p, card.uid):
		return []
	var card_data := CardDB.card(card.card_id)
	if g.takes_field_slot(card_data, g.is_subito_play(p, card_data)) and not g.has_free_slot(p):
		return [] # the AI never banishes its own permanents to make room
	var is_unit: bool = card_data["type"] == "unit"
	if not is_unit and (g.is_dud(p, card_data) or not _spell_is_worth_it(g, p, card_data)):
		return []
	var spec := g.card_spec(card_data)
	var target := _pick_sacrifice(g, p) if card_data.get("cost_sacrifice", false) else _pick_target(g, p, spec, card_data, 0, not is_unit)
	var spec2 := g.second_spec(card_data)
	var second_target := 0
	if _has_sacrifice_effect(card_data):
		# Mordida / Colheita / Tributo: what is given up and where the damage goes is one decision
		var plan := _plan_sacrifice_spell(g, p, card_data)
		if plan.is_empty():
			return []
		target = plan[0]
		second_target = plan[1] if spec2 != "" else 0
	elif _has_fight(card_data):
		# a fight needs a matching pair, not the "biggest" unit of each side
		var pair := _pick_fight(g, p)
		if pair.is_empty():
			return []
		target = pair[0]
		second_target = pair[1]
	elif not is_unit and spec == "ally_unit" and not _temporary_buff_effect(card_data).is_empty():
		# a this-turn buff goes to the strongest ally that will actually attack with it
		var best_attack := -1
		for unit: Card in _temporary_buff_beneficiaries(g, p, _temporary_buff_effect(card_data)):
			if not _buff_target_is_worth_it(g, unit, _temporary_buff_effect(card_data)):
				continue
			if unit.atk_total() > best_attack:
				best_attack = unit.atk_total()
				target = unit.uid
	elif spec != "" and target == 0 and not is_unit:
		return []
	elif card_data.has("extra_cost"):
		# Oferenda ao Vazio / Esporos / Tremor: the unit that pays the extra cost is the second pick
		second_target = _pick_extra_cost_payer(g, p, card_data, target)
		if second_target == 0:
			return []
	elif spec2 != "":
		var foe_leader: int = GameState.LEADER_UID[g.opponent(p)]
		second_target = foe_leader if g.valid_targets(p, spec2).has(foe_leader) else _pick_target(g, p, spec2, card_data, 0, true)
		if second_target == 0:
			return []
	if CardDB.is_equipment(card_data):
		var equipment_target := g.find_unit(target)
		if equipment_target == null or not equipment_target.has_equipment_room():
			return [] # never bounce existing gear back to hand just to play another one
	if card_data["type"] == "spell" and not _spell_changes_the_game(g, p, card.uid, target, second_target):
		return [] # it would resolve and change nothing: keep the Momentum (and the card)
	return g.play_card(p, card.uid, target, second_target)

## Vida the AI keeps in reserve after paying an ability's life cost (Sengoku, Peso dos Séculos).
const MIN_LIFE_AFTER_PAYING := 10

## False when paying the ability's Vida would leave the Leader too low, or (for a play discount) when every
## matching card in hand is already playable at its full price, so the Vida would buy nothing.
static func _ability_is_worth_its_life_cost(g: GameState, p: int, ability: Dictionary) -> bool:
	var life_cost := g.ability_life_cost(p, ability)
	if life_cost == 0:
		return true
	if int(g.players[p]["leader_hp"]) - life_cost < MIN_LIFE_AFTER_PAYING:
		return false
	for effect in ability["effects"]:
		if effect.get("action") != "grant_play_discount":
			continue
		for card: Card in g.players[p]["hand"]:
			if CardFilter.matches(card.card_id, effect.get("card_filter", {})) and g.can_play(p, card.uid):
				return false
	return true

## Cards in hand at or below which the AI will burn graveyard cards (graveyard_cost) to refill: it is a card-advantage
## engine, so a full hand gains nothing from it.
const MAX_HAND_FOR_GRAVEYARD_COST := 3

## False when the ability banishes cards from the graveyard and the AI's hand is already comfortably full.
static func _ability_is_worth_its_graveyard_cost(g: GameState, p: int, ability: Dictionary) -> bool:
	if g.ability_graveyard_cost_amount(ability) == 0:
		return true
	return (g.players[p]["hand"] as Array).size() <= MAX_HAND_FOR_GRAVEYARD_COST

## True when an ability lends Momentum now and takes it back next turn (Eryon's Leader). The AI uses
## this ability only after all its plays, when the loan can no longer buy anything, so it just skips it.
static func _ability_borrows_momentum(effects: Array) -> bool:
	for effect in effects:
		if effect.get("action") == "gain_momentum" and effect.get("next_turn", false) and int(effect.get("amount", 0)) < 0:
			return true
	return false

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
			var attack := g.strike_power_of(enemy_unit)
			if g.damage_after_armor(ally, attack) >= g.hp_left(ally):
				killed_today = true
			if attack > 0 and maxi(1, attack - g.armor_of(ally) - bonus) >= g.hp_left(ally):
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
			if enemy_unit.shield or enemy_unit.magic_shield or enemy_unit.supreme_shield or not g.valid_targets(p, "any").has(enemy_unit.uid):
				continue
			if g.damage_after_armor(enemy_unit, ally.atk_total()) < g.hp_left(enemy_unit):
				continue
			var gain := _unit_value(g, enemy_unit) - _unit_value(g, ally)
			if gain > best_gain:
				best_gain = gain
				best_plan = [ally.uid, enemy_unit.uid]
	return best_plan

## Most passes of priority a preview makes while waiting for its spell to resolve.
const PREVIEW_PASS_LIMIT := 20

## True when casting this spell right now (with these targets) would actually change something.
## Works for ANY spell, present or future, without knowing what it does: the game is copied twice, the spell
## is cast in both copies, but in one of them it resolves with no effects. If both copies end up the same,
## the spell only spends Momentum and the card. (Anything the spell leaves behind counts: damage, markers,
## cards drawn, a countered spell, a delayed effect, a deck search waiting for a choice...)
## When a copy can't be made safely, it answers true and the older checks decide, as before.
static func _spell_changes_the_game(g: GameState, p: int, card_uid: int, target: int, second_target: int) -> bool:
	var real_cast := g.preview_copy()
	var blank_cast := g.preview_copy()
	if real_cast == null or blank_cast == null:
		return true
	blank_cast.preview_blank_uid = card_uid
	for preview: GameState in [real_cast, blank_cast]:
		if preview.play_card(p, card_uid, target, second_target).is_empty():
			return true # the copy refused the play: let the real game decide
		_resolve_preview_stack(preview)
	return real_cast.preview_snapshot() != blank_cast.preview_snapshot()

## Lets the stack of a preview copy resolve: whoever holds priority passes, nobody answers.
static func _resolve_preview_stack(preview: GameState) -> void:
	for pass_number in PREVIEW_PASS_LIMIT:
		if preview.stack.is_empty() or preview.phase not in ["main", "combat"]:
			return
		if preview.pass_priority(preview.decider()).is_empty():
			return

## Filters out plays that would waste Momentum: heals with little to heal, revives of trivial units
## and area removal that isn't worth it (see _sweeper_is_worth_it).
static func _spell_is_worth_it(g: GameState, p: int, card_data: Dictionary) -> bool:
	var effects: Array = card_data.get("effects", [])
	if _is_face_burn(card_data) and _burn_plan(g, p) == "hold":
		return false # the burn is the finisher: it waits for the face
	if not _revive_is_worth_it(g, p, effects):
		return false
	if _dot_only_effects_are_wasted(g, p, effects):
		return false # every possible target already dies of its markers (or is immune): more would change nothing
	var temporary_buff := _temporary_buff_effect(card_data)
	if not temporary_buff.is_empty():
		var beneficiaries := _temporary_buff_beneficiaries(g, p, temporary_buff)
		if beneficiaries.is_empty() or _temporary_all_ally_buff_is_wasted_by_sickness(g, p, temporary_buff, beneficiaries):
			return false
	for effect in effects:
		var action: String = effect.get("action", "")
		if action == "cap_stats" and not _board_reset_is_worth_it(g, p, effect):
			return false
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

## Whether this buff actually applies to `unit`, including its printed target filters.
static func _temporary_buff_applies_to_unit(effect: Dictionary, unit: Card) -> bool:
	var unit_filter: Dictionary = effect.get("unit_filter", {})
	if not unit_filter.is_empty() and not CardFilter.matches(unit.card_id, unit_filter):
		return false
	if effect.get("requires_exhausted", false) and not unit.exhausted:
		return false
	var card_data := CardDB.card(unit.card_id)
	if (effect.get("not_rarity", []) as Array).has(card_data.get("rarity", "")):
		return false
	var tribes: Array = card_data.get("tribe", [])
	var only_tribe: Array = effect.get("only_tribe", [])
	if not only_tribe.is_empty():
		var shares_tribe := false
		for tribe in only_tribe:
			if tribes.has(tribe):
				shares_tribe = true
				break
		if not shares_tribe:
			return false
	var only_rarity: Array = effect.get("only_rarity", [])
	return only_rarity.is_empty() or only_rarity.has(card_data.get("rarity", ""))

## A unit with summoning sickness can use a temporary buff only if it grants Ímpeto and opens a legal
## challenge against an enemy unit. Ímpeto never lets it hit the Leader on the turn it enters.
static func _temporary_buff_allows_sick_unit_trade(g: GameState, unit: Card, effect: Dictionary) -> bool:
	if not unit.sick:
		return true
	var keywords: Array = effect.get("keywords", [])
	if not keywords.has("impeto"):
		return false
	var granted: Array = []
	for keyword in keywords:
		if not unit.keywords.has(keyword):
			granted.append(keyword)
	unit.keywords.append_array(granted)
	var can_trade := false
	for target_uid in g.attack_targets(unit):
		var target := g.find_unit(int(target_uid))
		if target != null and target.owner != unit.owner:
			can_trade = true
			break
	for keyword in granted:
		unit.keywords.erase(keyword)
	return can_trade

## Allies that would really use a this-turn buff: it must be our own turn and the unit must have something
## to hit once it has the keywords the buff grants (Ímpeto lets a fresh unit challenge, never go face).
static func _temporary_buff_beneficiaries(g: GameState, p: int, effect: Dictionary) -> Array:
	var beneficiaries: Array = []
	if g.active != p:
		return beneficiaries
	for unit: Card in g.players[p]["board"]:
		if not _temporary_buff_applies_to_unit(effect, unit):
			continue
		var granted: Array = []
		for keyword in effect.get("keywords", []):
			if not unit.keywords.has(keyword):
				granted.append(keyword)
		unit.keywords.append_array(granted)
		var has_target := not g.attack_targets(unit).is_empty()
		for keyword in granted:
			unit.keywords.erase(keyword)
		if has_target and _temporary_buff_allows_sick_unit_trade(g, unit, effect):
			beneficiaries.append(unit)
	return beneficiaries

## A broad temporary buff also reaches sick allies, so it is held when any affected sick ally cannot trade with it.
static func _temporary_all_ally_buff_is_wasted_by_sickness(g: GameState, p: int, effect: Dictionary, beneficiaries: Array) -> bool:
	if effect.get("target", "") != "all_ally_units":
		return false
	var affected_count := 0
	var has_sick_nonbeneficiary := false
	for unit: Card in g.players[p]["board"]:
		if not _temporary_buff_applies_to_unit(effect, unit):
			continue
		affected_count += 1
		if unit.sick and not beneficiaries.has(unit):
			has_sick_nonbeneficiary = true
	return affected_count > 1 and has_sick_nonbeneficiary

## Preview pending effects before judging a heal: the AI can get priority again while its previous heal is
## still on the stack, before the Leader's Vida has actually changed.
static func _healing_projection(g: GameState) -> GameState:
	if g.stack.is_empty():
		return g
	var preview := g.preview_copy()
	if preview == null:
		return g
	_resolve_preview_stack(preview)
	return preview

## A heal needs enough missing life to be worth the card: all but 1 point of it must land, unless the
## own Leader is in danger (then any real heal counts).
static func _heal_is_worth_it(g: GameState, p: int, effect: Dictionary) -> bool:
	var amount := int(effect.get("amount", 99))
	var projected := _healing_projection(g)
	var leader_missing: int = projected.players[p]["leader_max"] - projected.players[p]["leader_hp"]
	var most_missing := 0
	var total_unit_missing := 0
	for unit: Card in projected.players[p]["board"]:
		most_missing = maxi(most_missing, unit.damage)
		total_unit_missing += unit.damage
	var target: String = effect.get("target", "")
	if target == "own_leader":
		most_missing = leader_missing
	elif target == "all_ally_units":
		most_missing = total_unit_missing
	elif target == "ally_or_own_leader":
		most_missing = maxi(most_missing, leader_missing)
	var leader_in_danger: bool = projected.players[p]["leader_hp"] <= 8 and leader_missing >= 2 and target != "all_ally_units"
	return most_missing >= maxi(1, amount - 1) or leader_in_danger

## True when the AI should cast its Encarnação right now, before spending Momentum on the hand.
## Only the first cast (no commander tax yet): it is nearly always the right play, since the champion
## snowballs the earlier it is out. It waits when the cast is not possible (Momentum, slot, timing) or when
## the table is too dangerous (see _leader_in_reach_of_enemy_board and _enemy_wall_stands). The dangerous
## table is then handled by _incarnation_rank_against_hand.
static func _untaxed_incarnation_should_come_first(g: GameState, p: int) -> bool:
	if not _incarnation_can_be_cast_now(g, p):
		return false
	if GameState.commander_tax(int(g.players[p]["incarnation"]["casts"])) != 0:
		return false # already cast before: it competes with the hand (see _incarnation_rank_against_hand)
	return not _leader_in_reach_of_enemy_board(g, p) and not _enemy_wall_stands(g, p)

## The Encarnação is castable now, on our own turn with an empty stack and a free slot (the AI never
## banishes its own permanent to make room).
static func _incarnation_can_be_cast_now(g: GameState, p: int) -> bool:
	return g.active == p and g.stack.is_empty() and g.can_cast_incarnation(p) and g.has_free_slot(p)

## Our Leader may die to one swing of the enemy board: the Momentum is better spent on defense.
static func _leader_in_reach_of_enemy_board(g: GameState, p: int) -> bool:
	return _board_strike_total(g, g.opponent(p)) >= int(g.players[p]["leader_hp"])

## The enemy has a wall: INCARNATION_WALL_MIN_UNITS+ units whose Ataque + Vida add up to
## INCARNATION_WALL_STAT_LIMIT or more. A table of 0/2 tokens is no wall; four 3/4 units are.
static func _enemy_wall_stands(g: GameState, p: int) -> bool:
	var foe_units: Array = g.players[g.opponent(p)]["board"]
	if foe_units.size() < INCARNATION_WALL_MIN_UNITS:
		return false
	var foe_stat_total := 0
	for unit: Card in foe_units:
		foe_stat_total += unit.atk_total() + g.hp_left(unit)
	return foe_stat_total >= INCARNATION_WALL_STAT_LIMIT

## The most Momentum the plays of the hand can spend, paying at most `budget` (a subset of the playable
## cards, by their real cost). Reserve is ignored: it only pays spells and abilities.
static func _most_momentum_the_hand_can_spend(g: GameState, p: int, budget: int) -> int:
	var reachable := {0: true} # every total some subset of the hand costs, within the budget
	for card: Card in g.players[p]["hand"]:
		if not g.can_play(p, card.uid):
			continue
		var cost := g.cost_of(p, CardDB.card(card.card_id), card)
		if cost <= 0 or cost > budget:
			continue
		for total: int in reachable.keys():
			if total + cost <= budget:
				reachable[total + cost] = true
	var best := 0
	for total: int in reachable:
		best = maxi(best, total)
	return best

## Where the Encarnação stands in the order the AI tries its plays: it is cast before the first card of the
## hand whose printed cost is <= the rank. -1 = after the whole hand (only as a fallback), INCARNATION_RANK_FIRST
## = before everything. The rules, from the point of view of "the Encarnação is one more card of the hand":
##   - our Leader in reach of the enemy board: -1, the hand decides (defense first);
##   - an enemy wall stands: if some card of the hand, or a chain of up to INCARNATION_RELIEF_MAX_CHAIN cards
##     (tried on a copy), shrinks the wall below its limit or brings a Provocação to guard, the hand does it
##     (-1); if nothing does, the Encarnação comes first, unless casting it wastes more than
##     INCARNATION_MAX_EXTRA_WASTED_MOMENTUM Momentum compared with keeping the Momentum for the hand;
##   - no danger, first or second cast (tax 0 or 1): it ranks at its own cost, tying with hand cards of the same cost;
##   - no danger, third cast or more (tax 3+): a card of the same cost is usually stronger than the taxed
##     Encarnação, so the hand goes first when its plays can spend that much Momentum (several cards that add
##     up to the cost count); if the hand can't, the Encarnação comes first.
static func _incarnation_rank_against_hand(g: GameState, p: int) -> int:
	if not _incarnation_can_be_cast_now(g, p) or _leader_in_reach_of_enemy_board(g, p):
		return -1
	var cost := g.incarnation_cost(p)
	var momentum := int(g.players[p]["momentum"])
	if _enemy_wall_stands(g, p):
		if _hand_can_relieve_the_wall(g, p):
			return -1
		var momentum_left_unspent_if_hand_goes_first := momentum - _most_momentum_the_hand_can_spend(g, p, momentum)
		var momentum_left_unspent_if_cast_first := (momentum - cost) - _most_momentum_the_hand_can_spend(g, p, momentum - cost)
		if momentum_left_unspent_if_cast_first - momentum_left_unspent_if_hand_goes_first > INCARNATION_MAX_EXTRA_WASTED_MOMENTUM:
			return -1
		return INCARNATION_RANK_FIRST
	if GameState.commander_tax(int(g.players[p]["incarnation"]["casts"])) < INCARNATION_HEAVY_TAX:
		return cost
	return -1 if _most_momentum_the_hand_can_spend(g, p, momentum) >= cost else INCARNATION_RANK_FIRST

## True when the hand can answer the enemy wall by itself: one card, or a chain of up to
## INCARNATION_RELIEF_MAX_CHAIN cards played one after the other (every order is tried, on copies of the game),
## ends with the wall below its limit or with one of our Provocação units standing exhausted to guard.
## When the game can't be copied, it answers true: the hand keeps the benefit of the doubt.
static func _hand_can_relieve_the_wall(g: GameState, p: int) -> bool:
	var playable_cards: Array = []
	for card: Card in _hand_most_expensive_first(g, p):
		if g.can_play(p, card.uid):
			playable_cards.append(card.uid)
	return _a_chain_relieves_the_wall(g, p, playable_cards, 0, INCARNATION_RELIEF_MAX_CHAIN)

## One step of the search of _hand_can_relieve_the_wall: from the state `g` (a copy made by the caller, or
## the real game at the start), plays each of the cards `card_uids[first_index..]` on a fresh copy and looks.
## Cards are tried in a fixed order (each at most once per chain), so a chain is tested in one order only.
static func _a_chain_relieves_the_wall(g: GameState, p: int, card_uids: Array, first_index: int, plays_left: int) -> bool:
	for index in range(first_index, card_uids.size()):
		var preview := g.preview_copy()
		if preview == null:
			return true
		var preview_card := _card_in_hand(preview, p, int(card_uids[index]))
		if preview_card == null or _try_play_card(preview, p, preview_card).is_empty():
			continue # not playable here (or not worth playing): this card is no step of a chain
		_resolve_preview_stack(preview)
		_answer_preview_prompts(preview, p)
		if not _enemy_wall_stands(preview, p) or _a_guard_stands(preview, p):
			return true
		if plays_left > 1 and _a_chain_relieves_the_wall(preview, p, card_uids, index + 1, plays_left - 1):
			return true
	return false

static func _card_in_hand(g: GameState, p: int, uid: int) -> Card:
	for card: Card in g.players[p]["hand"]:
		if card.uid == uid:
			return card
	return null

## Settles the questions a play leaves open on a copy (enter tapped, searches, targets on entry) the way the
## AI itself would answer them, so the copy is back in the main phase.
static func _answer_preview_prompts(preview: GameState, p: int) -> void:
	for answer_number in PREVIEW_PASS_LIMIT:
		if preview.phase not in ["enter_tapped", "search", "enter_target", "discard"]:
			return
		if step(preview, preview.decider()).is_empty():
			return

## One of our Provocação units is exhausted and able to force the enemy attackers to challenge it.
static func _a_guard_stands(g: GameState, p: int) -> bool:
	for unit: Card in g.players[p]["board"]:
		if unit.exhausted and g.has_kw(unit, "provocacao") and not unit.is_frozen() and not unit.is_stunned():
			return true
	return false

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
			if not dies or unit.shield or unit.supreme_shield: # an area effect passes through Escudo Mágico
				continue
			if side == p:
				net_value -= _unit_value(g, unit)
			else:
				killed_enemies += 1
				net_value += _unit_value(g, unit)
	if net_value <= 0:
		return false
	return killed_enemies >= 2 or (killed_enemies >= 1 and _under_pressure(g, p))

## Effects that only come along with a marker effect and are worth nothing alone (Drex: X grows by 1).
const DOT_COMPANION_ACTIONS := ["grow_shared_x"]

## Putting markers on this target changes nothing: the markers it holds already kill it at its next tick
## (GameState reads 2 per Veneno/Sangramento, 1 per Queimadura), or it is immune to every marker
## the effects bring. `dot_effects` are the add_dot effects aimed at it.
static func _dot_is_pointless_on(g: GameState, target_uid: int, dot_effects: Array) -> bool:
	if target_uid < 0: # a Leader: never immune to a marker
		return g.dots_already_kill_leader(GameState.LEADER_UID.find(target_uid))
	var unit := g.find_unit(target_uid)
	if unit == null or g.dots_already_kill_unit(unit):
		return true
	for effect in dot_effects:
		if bool(effect.get("ignores_immunity", false)) or not g.unit_is_immune_to_dot(unit, String(effect.get("dot", "queimadura"))):
			return false
	return true

## True when the enemies that an area or random marker effect (Viprax, Drex) can reach still gain something.
## Aimed effects are judged by _pick_target, so any spec this does not know counts as useful.
static func _dot_effect_has_useful_target(g: GameState, p: int, effect: Dictionary) -> bool:
	var spec := String(effect.get("target", ""))
	if not spec in ["all_enemy_units", "random_enemy_spread", "random_enemy_unit_spread", "random_enemy_unit", "enemy_unit", "enemy_leader"]:
		return true
	var foe := g.opponent(p)
	if spec in ["random_enemy_spread", "enemy_leader"] and not _dot_is_pointless_on(g, GameState.LEADER_UID[foe], [effect]):
		return true
	if spec == "enemy_leader":
		return false
	for unit: Card in g.players[foe]["board"]:
		if g.hp_left(unit) > 0 and not _dot_is_pointless_on(g, unit.uid, [effect]):
			return true
	return false

## The add_dot effects of a list that does nothing else but put markers (companions like Drex's X growth
## allowed), or [] when it has none or also does something else that makes it worth using.
static func _marker_only_effects(effects: Array) -> Array:
	var dot_effects: Array = []
	for effect in effects:
		var action: String = effect.get("action", "")
		if action == "add_dot":
			dot_effects.append(effect)
		elif not action in DOT_COMPANION_ACTIONS:
			return []
	return dot_effects

## An effect list whose whole point is putting markers (a companion like Drex's X growth does not count), and
## where no marker would still land on anything. Spending Momentum or a cost on it would be a pure waste.
static func _dot_only_effects_are_wasted(g: GameState, p: int, effects: Array) -> bool:
	var dot_effects := _marker_only_effects(effects)
	if dot_effects.is_empty():
		return false
	for effect in dot_effects:
		if _dot_effect_has_useful_target(g, p, effect):
			return false
	return true

## Area banish narrowed by unit states (Fulgurvoltz, exhausted or weaker enemies): worth it when it takes at least
## two enemy units, or one while under pressure (it never hits our own side, and Escudo units pass through it).
static func _filtered_banish_is_worth_it(g: GameState, p: int, source: Card, effects: Array) -> bool:
	for effect in effects:
		if effect.get("action", "") != "banish" or effect.get("target", "") != "all_enemy_units" or not effect.has("unit_state_any"):
			continue
		var banished := 0
		for unit: Card in g.players[g.opponent(p)]["board"]:
			if unit.shield or unit.supreme_shield:
				continue
			if effect["unit_state_any"].any(func(state: String) -> bool: return GroupTarget.unit_has_state(g, unit, state, source.uid)):
				banished += 1
		return banished >= 2 or (banished >= 1 and _under_pressure(g, p))
	return true

## Board reset (Última Badalada): worth it when the stats it takes from the enemy board (plus the enemy
## units it keeps from attacking) clearly outweigh the stats it takes from our own board.
static func _board_reset_is_worth_it(g: GameState, p: int, effect: Dictionary) -> bool:
	var enemy_loss := 0
	var own_loss := 0
	var enemy_units: Array = g.players[g.opponent(p)]["board"]
	for side in [g.opponent(p), p]:
		for unit: Card in g.players[side]["board"]:
			var lost := maxi(0, unit.atk_total() - int(effect.get("atk", 99))) + maxi(0, g.hp_left(unit) - int(effect.get("hp", 99)))
			if side == p:
				own_loss += lost
			else:
				enemy_loss += lost
	return enemy_units.size() >= 2 and enemy_loss - own_loss >= 6

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
			var kills_enemy := damage_to_enemy >= enemy.hp_left() and not enemy.shield and not enemy.magic_shield and not enemy.supreme_shield
			var ally_survives := damage_to_ally < ally.hp_left() or ally.shield or ally.supreme_shield
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

## Who pays the "pay_one_of" cost of an Ao Ativar (Drex), or 0 when it is not worth paying: the cheapest
## card in hand when there are at least 2 cards (keeps a play for next turn), else a very cheap ally unit.
static func _pick_activation_payer(g: GameState, p: int, unit: Card) -> int:
	var payers: Array = g.extra_cost_payers(p, unit.uid)
	var cheapest_hand_uid := 0
	var cheapest_hand_cost := 999
	for hand_card: Card in g.players[p]["hand"]:
		if not payers.has(hand_card.uid):
			continue
		var hand_cost := int(CardDB.card(hand_card.card_id).get("cost", 0))
		if hand_cost < cheapest_hand_cost:
			cheapest_hand_cost = hand_cost
			cheapest_hand_uid = hand_card.uid
	if cheapest_hand_uid != 0 and g.players[p]["hand"].size() >= 2:
		return cheapest_hand_uid
	for payer_uid in payers:
		var ally := g.find_unit(int(payer_uid))
		if ally != null and _unit_value(g, ally) <= 2:
			return ally.uid
	return 0

## The unit that pays a spell's `extra_cost`, or 0 when nobody is cheap enough to give up.
## Losing Armadura is almost free, so any unit that can pay does. A sacrifice only happens when the
## cheapest eligible unit is not worth much more than the spell it answers (`stack_id`).
static func _pick_extra_cost_payer(g: GameState, p: int, card_data: Dictionary, stack_id: int) -> int:
	var extra_cost: Dictionary = card_data["extra_cost"]
	var cheapest_uid := 0
	var cheapest_value := 999
	for uid in g.valid_targets(p, String(extra_cost["target"])):
		var unit := g.find_unit(int(uid))
		if unit != null and _unit_value(g, unit) < cheapest_value:
			cheapest_value = _unit_value(g, unit)
			cheapest_uid = unit.uid
	if cheapest_uid == 0 or extra_cost["kind"] != "sacrifice":
		return cheapest_uid
	var answered_cost := 0
	for item in g.stack:
		if item["sid"] == stack_id:
			answered_cost = g.stack_cost(item)
	return cheapest_uid if cheapest_value <= answered_cost + 3 else 0

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

## Returning one of its own units to the hand (Naelys) only pays off when the unit comes back with an Ao Entrar to repeat,
## so the AI picks the weakest such unit and otherwise declines (0). A token never comes back: it just leaves the game.
static func _pick_bounce_ally(g: GameState, options: Array) -> int:
	var best_uid := 0
	var best_score := 9999
	for uid in options:
		var unit := g.find_unit(uid)
		if unit == null or unit.data().get("token", false):
			continue
		var has_enter_effect := false
		for effect in unit.data().get("effects", []):
			if effect.get("trigger", "") == "on_enter":
				has_enter_effect = true
		if not has_enter_effect:
			continue
		var score := unit.atk_total() + unit.hp_left()
		if score < best_score:
			best_score = score
			best_uid = uid
	return best_uid

## Hostile effects pick the biggest enemy (or the Leader); friendly ones the biggest ally.
## Damage that doesn't kill is worth nothing on a unit with Regeneração (it heals at the start of the next turn, before its owner acts)
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
	var effects: Array = _effects_that_use_the_pick(source)
	var options := g.valid_targets(p, spec, self_uid, false, effects) # Ponto Final Sem Vírgula never aims at a unit without enough Veneno
	if source is Dictionary and CardDB.is_equipment(source):
		var equipment_targets: Array = []
		for uid in options:
			var unit := g.find_unit(int(uid))
			if unit != null and unit.has_equipment_room():
				equipment_targets.append(uid)
		options = equipment_targets
	if options.is_empty():
		return 0
	if spec == "ally_or_own_leader":
		return _most_damaged(g, p, options)
	if spec in ["enemy_artifact", "ally_artifact", "any_artifact"]:
		return _priciest_artifact(g, options)
	for effect in effects:
		if effect.get("action") == "return_to_hand" and spec in ["ally_unit", "other_ally_unit"]:
			return _pick_bounce_ally(g, options)
	var friendly := spec in ["ally_unit", "other_ally_unit", "ally_or_own_leader"]
	if not friendly:
		for effect in effects:
			if effect.get("action") == "buff":
				friendly = true
	var marker_effects := _marker_only_effects(effects) # non-empty when the pick only receives markers
	var best_uid := 0
	var best_score := -999
	for uid in options:
		var score := 0
		if not marker_effects.is_empty() and _dot_is_pointless_on(g, int(uid), marker_effects):
			continue # its markers already kill it (or it is immune): a new marker would be wasted
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
			if friendly:
				var buff_effect: Dictionary = {}
				for effect in effects:
					if effect.get("action") == "buff":
						buff_effect = effect
						break
				if not buff_effect.is_empty() and not _buff_target_is_worth_it(g, unit, buff_effect):
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
						if int(effect["amount"]) >= unit.hp_left() and not unit.shield and not unit.supreme_shield:
							kills = true
				if kills:
					score += 10
				elif hits:
					# Damage that doesn't kill stays marked on the unit, so it is worth doing...
					if unit.has_kw("regeneracao"):
						continue # ...except on Regeneração: it heals at the start of the next turn, before its owner acts
					if _punishes_surviving_damage(unit):
						continue # ...and except on a unit that grows stronger from it (Ao Sofrer Dano)
					if strict:
						score = damage_amount + 1 # chip damage from a spell: the face is usually better
				if unit.magic_shield:
					score -= 20 # wasted on Escudo Mágico: any effect we aim at it only breaks it
				if unit.supreme_shield:
					score -= 20 # wasted on Escudo Supremo: it absorbs anything, from any source
		if score > best_score:
			best_score = score
			best_uid = uid
	return best_uid

## One attack (or [] when no attack is worth it). The face is always open (only a Provocação closes it),
## so the AI must decide between hitting the Leader and trading. It walks these clauses in order and the
## first one that applies wins (the numbers are the knobs at the top of the file):
##   1. LETHAL: some attacker (or the whole ready board) finishes the enemy Leader -> face.
##   2. RUSH: the enemy Leader is within RUSH_TURNS swings of dying counting the burn in our hand (and we
##      are not about to die first) -> the strongest face attacker hits, exposed or not. No trades.
##   3. FREE KILL: a challenge that kills without a slow punishment -> challenge.
##   4. SAFE FACE: an attacker whose face hit is acceptable (nobody can punish it, or it is worth the risk,
##      see _face_hit_is_acceptable) -> face. A face hit beats an ordinary trade.
##   5. GOOD TRADE: a trade that gains at least TRADE_MIN_GAIN -> challenge. Even trades, chip damage and
##      anything that only heals the enemy (Roubo de Vida) are NOT taken: the unit stays home instead.
##   6. FORCED: a Provocação closes the face, so the attacker's only choice is to challenge it or stay still;
##      it challenges when the hit is not a pure loss (score 1+), otherwise it waits.
static func _try_attack(g: GameState, p: int) -> Array:
	var enemy := g.opponent(p)
	var enemy_leader_uid: int = GameState.LEADER_UID[enemy]
	var enemy_hp: int = g.players[enemy]["leader_hp"]
	var ready: Array = []
	for unit: Card in g.players[p]["board"]:
		# a 0 ATK unit may attack, but it would only be hit back for nothing: the AI never does it
		if g.strike_power_of(unit) > 0 and not g.attack_targets(unit).is_empty():
			ready.append(unit)
	if ready.is_empty():
		return []
	var burn_reach := maxi(_burn_reach(g, p, g.budget(p, false)), _burn_reach(g, p, _next_turn_plain_budget(g, p)))
	var all_in := _lethal_push(g, p, ready)
	var face_power := _face_strike_total(g, p)
	# we only rush when the enemy cannot kill us first (otherwise the board has to stay home to trade)
	var in_danger: bool = _board_strike_total(g, enemy) >= g.players[p]["leader_hp"]
	var rush: bool = not in_danger and enemy_hp - burn_reach <= face_power * RUSH_TURNS
	var best_challenge_score := 0
	var best_challenge: Array = [] # [attacker uid, target uid]
	var forced_challenge_score := 0
	var forced_challenge: Array = [] # a challenge that is the attacker's only option (Provocação in the way)
	var strongest_face_attacker: Card = null # for clauses 1 and 2
	var safe_face_attacker: Card = null # for clause 4
	for attacker: Card in ready:
		var targets := g.attack_targets(attacker)
		var can_hit_face := targets.has(enemy_leader_uid)
		if can_hit_face and g.strike_power_of(attacker) >= enemy_hp:
			return g.attack_unit(p, attacker.uid, enemy_leader_uid) # clause 1: this hit wins the game
		# a Provocação closes the face: it must challenge (a fresh Ímpeto unit just can't reach the face yet)
		# (Prudência closes the face by itself, not because of a Provocação: its challenge is a choice)
		var forced := (not attacker.sick or g.combat_system().is_rompante_rush(attacker)) and not can_hit_face \
			and not g.has_kw(attacker, "prudencia")
		for target_uid in targets:
			if target_uid < 0:
				continue
			var score := _challenge_score(g, attacker, g.find_unit(target_uid))
			if score > best_challenge_score:
				best_challenge_score = score
				best_challenge = [attacker.uid, target_uid]
			if forced and maxi(score, 1) > forced_challenge_score:
				forced_challenge_score = maxi(score, 1)
				forced_challenge = [attacker.uid, target_uid]
		if can_hit_face:
			if strongest_face_attacker == null or g.strike_power_of(attacker) > g.strike_power_of(strongest_face_attacker):
				strongest_face_attacker = attacker
			if _face_hit_is_acceptable(g, p, attacker, burn_reach):
				if safe_face_attacker == null or g.strike_power_of(attacker) > g.strike_power_of(safe_face_attacker):
					safe_face_attacker = attacker
	if (all_in or rush) and strongest_face_attacker != null:
		return g.attack_unit(p, strongest_face_attacker.uid, enemy_leader_uid) # clauses 1 and 2
	if best_challenge_score > FREE_KILL_BONUS:
		return g.attack_unit(p, best_challenge[0], best_challenge[1]) # clause 3
	if safe_face_attacker != null:
		return g.attack_unit(p, safe_face_attacker.uid, enemy_leader_uid) # clause 4
	if best_challenge_score >= TRADE_MIN_GAIN:
		return g.attack_unit(p, best_challenge[0], best_challenge[1]) # clause 5
	if not forced_challenge.is_empty():
		return g.attack_unit(p, forced_challenge[0], forced_challenge[1]) # clause 6
	return []

## Is the face hit worth it for `attacker`, even if an enemy unit can punish it afterwards? Walks these
## cases in order:
##   - an empty enemy board, or nobody who could challenge-and-kill it once it is tapped: yes;
##   - the hit leaves the Leader inside our burn reach (the burn in hand finishes it): yes, even an engine;
##   - an engine (a unit worth keeping alive) otherwise: no;
##   - the enemy Leader is low (10 or less) or our board is 2+ units larger: yes (pressure);
##   - otherwise only when the damage is worth more than the unit it may cost: FACE_POINT_VALUE per point
##     of damage (more late in the game or with the enemy low, plus a bonus for Roubo de Vida) against
##     the unit's value.
static func _face_hit_is_acceptable(g: GameState, p: int, attacker: Card, burn_reach: int) -> bool:
	var enemy := g.opponent(p)
	var enemy_hp: int = g.players[enemy]["leader_hp"]
	var enemy_board: Array = g.players[enemy]["board"]
	var strike := g.strike_power_of(attacker)
	var engine := _is_engine(attacker)
	if enemy_board.is_empty() or not _punishable(g, attacker, 0, engine):
		return true
	if enemy_hp - strike <= burn_reach:
		return true
	if engine:
		return false
	if enemy_hp <= 10 or g.players[p]["board"].size() > enemy_board.size() + 1:
		return true
	var point_value := FACE_POINT_VALUE
	if enemy_hp <= NEAR_END_HP or g.turn >= LATE_GAME_TURN:
		point_value = FACE_POINT_VALUE_LATE
	var worth := strike * point_value
	if g.has_kw(attacker, "roubo_de_vida"):
		worth += strike # the hit also heals our Leader
	return worth >= _unit_value(g, attacker)

## How good it is for `attacker` to challenge `target` (0 or less = not worth it). Strikes follow
## Rapidez: a faster attacker that kills its target takes nothing back. Challenging also taps the
## attacker, so a survivor that the enemy can then kill on their turn counts as a delayed trade.
static func _challenge_score(g: GameState, attacker: Card, target: Card) -> int:
	var damage_to_target := 0 if target.shield else g.damage_after_armor(target, g.strike_power_of(attacker))
	var kills_target := damage_to_target >= g.hp_left(target)
	var strikes_first := attacker.rapidez_total() > target.rapidez_total()
	var damage_back := 0 if attacker.shield or (kills_target and strikes_first) else g.damage_after_armor(attacker, g.strike_power_of(target))
	var attacker_dies := damage_back >= g.hp_left(attacker)
	var target_value := _unit_value(g, target)
	var attacker_value := _unit_value(g, attacker)
	# a Roubo de Vida target heals its Leader with the blow it strikes back (it never lands if we kill it first)
	var enemy_heal := mini(damage_back, g.hp_left(attacker)) if g.has_kw(target, "roubo_de_vida") else 0
	if kills_target and not attacker_dies:
		if _punishable(g, attacker, damage_back, _is_engine(attacker), target):
			return target_value - attacker_value + 1 - enemy_heal # it will be challenged back and die: a slow trade
		return target_value + FREE_KILL_BONUS - enemy_heal
	if kills_target and attacker_dies:
		return target_value - attacker_value + 1 - enemy_heal # a trade: only worth it against something more valuable
	if not attacker_dies and damage_to_target > 0 and not _is_engine(attacker) and enemy_heal == 0:
		return 1 # chip damage that stays marked; only used when nothing better exists
	return 0

## How much a unit is worth keeping (or killing): its stats on the board, what was paid for it,
## and a bonus for engines, whose effects keep paying off while they live.
static func _unit_value(g: GameState, unit: Card) -> int:
	var value := g.atk_of(unit) + g.hp_left(unit) + int(unit.data().get("cost", 0))
	if _is_engine(unit):
		value += 4
	return value

## Don't spend a single-target buff on a throwaway body unless it changes a high-value combat or saves
## the Leader from a lethal attack. Broad all-unit buffs are handled separately and aren't filtered here.
static func _buff_target_is_worth_it(g: GameState, unit: Card, effect: Dictionary) -> bool:
	if (effect.get("temp", false) or int(effect.get("critico_temp", 0)) > 0) \
			and not _temporary_buff_allows_sick_unit_trade(g, unit, effect):
		return false
	var atk_gain := int(effect.get("atk", 0)) + int(effect.get("atk_temp", 0))
	var hp_gain := int(effect.get("hp", 0)) + int(effect.get("hp_temp", 0))
	var enemy: int = g.opponent(unit.owner)
	var leader_hp: int = int(g.players[unit.owner]["leader_hp"])
	var enemy_strike := _board_strike_total(g, enemy)
	var lethal_risk := enemy_strike >= leader_hp
	var gains_taunt: bool = (effect.get("keywords", []) as Array).has("provocacao")
	if lethal_risk and (gains_taunt or (g.has_kw(unit, "provocacao") and hp_gain > 0)):
		return true
	# Pacifistas always strike for zero, even with Ataque buffs; only defensive stats can matter in a lethal block.
	if g.has_kw(unit, "pacifista"):
		return false
	# Cheap, low-impact bodies such as Vigia do Farol aren't worth a single-target buff by default.
	if _unit_value(g, unit) <= 6:
		# Exception: the buff must turn a losing combat into a trade for an equally or more valuable enemy.
		pass
	else:
		return true
	for foe: Card in g.players[enemy]["board"]:
		var foe_value := _unit_value(g, foe)
		var buffed_strike := maxi(0, unit.atk_total() + atk_gain)
		var damage_to_foe := 0 if foe.shield or foe.supreme_shield else g.damage_after_armor(foe, buffed_strike)
		var kills_foe := damage_to_foe >= foe.hp_left() and foe.hp_left() > 0
		var base_damage := 0 if foe.shield or foe.supreme_shield else g.damage_after_armor(foe, g.strike_power_of(unit))
		var buff_enables_kill := kills_foe and base_damage < foe.hp_left()
		if buff_enables_kill and foe_value >= _unit_value(g, unit):
			var damage_back := 0 if foe.shield or foe.supreme_shield else g.damage_after_armor(unit, foe.atk_total())
			if damage_back < unit.hp_left() + hp_gain or unit.shield or unit.supreme_shield:
				return true
	return false

## Triggers that keep paying off turn after turn while the unit stays on the board.
const ENGINE_TRIGGERS := ["on_ally_death", "on_turn_start", "on_turn_end", "on_any_turn_start", "on_any_turn_end", "constante"]

## True for a synergy engine (e.g. Diabrete Sombrio: "Aliado Morre"): a unit with a repeating
## trigger, an Ao Ativar ability, or the Encarnação. The AI avoids leaving these exposed to a trade.
static func _is_engine(unit: Card) -> bool:
	var card_data := unit.data()
	if unit.incarnation or card_data.has("activated"):
		return true
	for effect in card_data.get("effects", []):
		if ENGINE_TRIGGERS.has(effect.get("trigger", "")):
			return true
	return false

## True when, once tapped (and after taking `extra_damage`), this unit could be challenged and
## killed on the enemy's turn by an enemy unit that survives the exchange. With `any_killer`,
## even an enemy that dies doing it counts (an engine should not be traded off at all).
## `slain_unit` is an enemy this very attack kills: it can't punish anyone afterwards.
static func _punishable(g: GameState, unit: Card, extra_damage := 0, any_killer := false, slain_unit: Card = null) -> bool:
	var was_exhausted := unit.exhausted
	unit.exhausted = true # pretend it already attacked, to ask who could challenge it
	unit.damage += extra_damage # the damage it would carry after this attack
	var punished := false
	for enemy_unit: Card in g.players[g.opponent(unit.owner)]["board"]:
		if enemy_unit == slain_unit or not g.can_challenge(enemy_unit, unit):
			continue
		var kills := not unit.shield and g.damage_after_armor(unit, g.strike_power_of(enemy_unit)) >= g.hp_left(unit)
		var survives := enemy_unit.shield or g.damage_after_armor(enemy_unit, g.strike_power_of(unit)) < g.hp_left(enemy_unit)
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
			face_damage += g.strike_power_of(attacker)
	return face_damage >= g.players[g.opponent(p)]["leader_hp"]

## Face damage the ready units can deal this turn (those that can reach the enemy Leader).
static func _face_strike_total(g: GameState, p: int) -> int:
	var enemy_leader_uid: int = GameState.LEADER_UID[g.opponent(p)]
	var total := 0
	for unit: Card in g.players[p]["board"]:
		if g.attack_targets(unit).has(enemy_leader_uid):
			total += g.strike_power_of(unit)
	return total

## Everything a player's board would hit for in one swing (used as "how fast can they kill a Leader").
static func _board_strike_total(g: GameState, player: int) -> int:
	var total := 0
	for unit: Card in g.players[player]["board"]:
		total += g.strike_power_of(unit)
	return total

## Plain Momentum the AI will have next turn (one more than now). The Reserva is counted apart, see _burn_reach.
static func _next_turn_plain_budget(g: GameState, p: int) -> int:
	return mini(g.momentum_cap(p), int(g.players[p]["max_momentum"]) + 1)

## True for a spell that can send damage to the enemy Leader (Bola de Fogo "any", Choque "enemy_leader").
static func _is_face_burn(card_data: Dictionary) -> bool:
	return _face_burn_damage(card_data) > 0

## Damage a spell sends at the enemy Leader (0 for anything else).
static func _face_burn_damage(card_data: Dictionary) -> int:
	if card_data.get("type", "") != "spell":
		return 0
	var total := 0
	for effect in card_data.get("effects", []):
		if effect.get("trigger", "") == "on_play" and effect.get("action", "") == "damage" \
				and effect.get("target", "") in ["any", "enemy_leader"]:
			total += int(effect.get("amount", 0))
	return total

## The most face damage the burn spells in hand can deal paying at most `budget` Momentum (best subset).
static func _burn_reach(g: GameState, p: int, plain_budget: int) -> int:
	var reserve := int(g.players[p]["reserve"])
	var damages: Array = []
	var costs: Array = []
	var fast: Array = [] # only Rápido/Instantâneo burn can be paid from the Reserva
	for card: Card in g.players[p]["hand"]:
		var card_data := CardDB.card(card.card_id)
		var damage := _face_burn_damage(card_data)
		if damage > 0 and not g.is_dud(p, card_data):
			damages.append(damage)
			costs.append(g.cost_of(p, card_data, card))
			fast.append(g.reserve_pays(card_data))
	var best := 0
	for subset in range(1, 1 << damages.size()): # burn is a handful of cards, so trying every subset is cheap
		var damage_sum := 0
		var slow_cost := 0
		var fast_cost := 0
		for i in damages.size():
			if subset & (1 << i):
				damage_sum += damages[i]
				if fast[i]:
					fast_cost += costs[i]
				else:
					slow_cost += costs[i]
		if slow_cost + maxi(0, fast_cost - reserve) <= plain_budget:
			best = maxi(best, damage_sum)
	return best

## What to do with the burn in hand. Walks these cases in order:
##   - "free": no burn in hand -> nothing to plan;
##   - "lethal": on our own turn, burn + the attackers that can reach the face kill the enemy Leader -> cast
##     it at the face now, before anything else is bought;
##   - "free": we are about to die, or the hand is nearly full -> cast it the usual way (kill a unit, or
##     whatever _pick_target prefers);
##   - "hold": the enemy Leader is within HOLD_TURNS swings of our board plus the burn (an aggro deck against a
##     slow one) -> keep the burn for the face, do not spend it on units;
##   - otherwise "free" (a control deck uses burn as removal).
static func _burn_plan(g: GameState, p: int) -> String:
	var enemy := g.opponent(p)
	var enemy_hp: int = g.players[enemy]["leader_hp"]
	var burn_now := _burn_reach(g, p, g.budget(p, false))
	if burn_now <= 0:
		return "free"
	if g.active == p and enemy_hp <= burn_now + _face_strike_total(g, p):
		return "lethal"
	var burn_next := maxi(burn_now, _burn_reach(g, p, _next_turn_plain_budget(g, p)))
	var in_danger: bool = _board_strike_total(g, enemy) >= g.players[p]["leader_hp"]
	var hand_nearly_full: bool = g.players[p]["hand"].size() >= GameState.HAND_LIMIT - 1
	if in_danger or hand_nearly_full:
		return "free"
	if enemy_hp - burn_next <= _board_strike_total(g, p) * HOLD_TURNS:
		return "hold"
	return "free"

## Casts a burn spell at the enemy Leader (the "lethal" plan). [] when none can be cast.
static func _cast_face_burn(g: GameState, p: int, held_card_ids: Array) -> Array:
	var enemy_leader_uid: int = GameState.LEADER_UID[g.opponent(p)]
	var hand: Array = g.players[p]["hand"].duplicate()
	hand.sort_custom(func(a: Card, b: Card): return _face_burn_damage(CardDB.card(a.card_id)) > _face_burn_damage(CardDB.card(b.card_id)))
	for card: Card in hand:
		var card_data := CardDB.card(card.card_id)
		if not _is_face_burn(card_data) or held_card_ids.has(card.card_id) or not g.can_play(p, card.uid) or g.is_dud(p, card_data):
			continue
		if not g.valid_targets(p, g.card_spec(card_data)).has(enemy_leader_uid):
			continue
		var events := g.play_card(p, card.uid, enemy_leader_uid, 0)
		if not events.is_empty():
			return events
	return []

## ---------------------------------------------------------------------------------------------------------
## Lethal planner. Top priority of the main phase, ahead of trades and value plays:
##   1. add up what the board already hits the enemy Leader for (_face_strike_total);
##   2. if that is not enough, the shortfall is "enemy Leader Vida - board damage";
##   3. look in the hand for everything that can add face damage this turn (burn spells, Ao Entrar damage
##      aimed at "any", Rompante units, temporary +ATK buffs) and find the cheapest group of cards that
##      covers the shortfall inside the Momentum we have;
##   4. if such a group exists, play it (damage goes to the face, never to a unit); if not, the planner
##      stays out of the way and the usual trade/value logic runs.
## ---------------------------------------------------------------------------------------------------------

## True when a tapped enemy Provocação would force a fresh Rompante unit to challenge it instead of hitting the face.
static func _enemy_guard_closes_face(g: GameState, p: int) -> bool:
	for enemy_unit: Card in g.players[g.opponent(p)]["board"]:
		if enemy_unit.exhausted and g.has_kw(enemy_unit, "provocacao") and not g.has_kw(enemy_unit, "eterea") \
				and not enemy_unit.is_frozen() and not enemy_unit.is_stunned():
			return true
	return false

## Our units that can hit the enemy Leader this turn (what a temporary +ATK buff would actually pump).
static func _face_capable_attackers(g: GameState, p: int) -> Array:
	var enemy_leader_uid: int = GameState.LEADER_UID[g.opponent(p)]
	var attackers: Array = []
	for unit: Card in g.players[p]["board"]:
		if g.attack_targets(unit).has(enemy_leader_uid):
			attackers.append(unit)
	return attackers

## Damage a card of the hand adds to the enemy Leader this turn (0 when it adds none):
##   - spell: its burn damage, plus the +ATK of a this-turn buff times the attackers that would use it;
##   - unit: Ao Entrar damage that can be aimed at the Leader, plus (Rompante, face not guarded) its own
##     attack and the damage it deals to the Leader when attacking.
static func _face_damage_of_hand_card(g: GameState, p: int, card_data: Dictionary, face_attackers: Array) -> int:
	var total := 0
	if card_data.get("type", "") == "spell":
		total += _face_burn_damage(card_data)
		var temporary_buff := _temporary_buff_effect(card_data)
		if not temporary_buff.is_empty() and not face_attackers.is_empty():
			var beneficiaries := _temporary_buff_beneficiaries(g, p, temporary_buff)
			if not _temporary_all_ally_buff_is_wasted_by_sickness(g, p, temporary_buff, beneficiaries):
				var pumped_attackers := 0
				for unit: Card in beneficiaries:
					if face_attackers.has(unit):
						pumped_attackers += 1
						if temporary_buff.get("target", "") != "all_ally_units":
							break
				total += int(temporary_buff.get("atk", 0)) * pumped_attackers
		return total
	if card_data.get("type", "") != "unit":
		return 0
	for effect in card_data.get("effects", []):
		if effect.get("trigger", "") == "on_enter" and effect.get("action", "") == "damage" \
				and effect.get("target", "") in ["any", "enemy_leader"]:
			total += int(effect.get("amount", 0))
	if card_data.get("keywords", []).has("rompante") and not _enemy_guard_closes_face(g, p):
		total += int(card_data.get("atk", 0))
		for effect in card_data.get("effects", []):
			if effect.get("trigger", "") == "on_attack" and effect.get("action", "") == "damage" \
					and effect.get("target", "") == "enemy_leader":
				total += int(effect.get("amount", 0))
	return total

## The buff of an ability that can make an attacker hit harder this turn (+ATK to itself, to one ally or to all of
## them), or {} when the ability has none.
static func _attack_buff_effect(effects: Array) -> Dictionary:
	for effect in effects:
		if effect.get("action", "") != "buff" or not effect.get("target", "") in ["self", "ally_unit", "all_ally_units"]:
			continue
		var tribe_bonus: Dictionary = effect.get("tribe_temp_bonus", {})
		if int(effect.get("atk", 0)) > 0 or int(tribe_bonus.get("atk", 0)) > 0:
			return effect
	return {}

## Attack one buff adds to one unit: its "atk" (times the artifacts in play for "per": "own_artifacts") plus the
## bonus of the right tribe (Drake's power). A buff that scales with something else is not counted: not a promise.
static func _attack_gain_of_buff(g: GameState, p: int, buff: Dictionary, unit: Card) -> int:
	var per: String = buff.get("per", "")
	var multiplier := 1
	if per == "own_artifacts":
		multiplier = g.artifact_count(p)
	elif per != "":
		multiplier = 0
	var gain := int(buff.get("atk", 0)) * multiplier
	var tribe_bonus: Dictionary = buff.get("tribe_temp_bonus", {})
	var unit_tribes: Array = CardDB.card(unit.card_id).get("tribe", [])
	for tribe in tribe_bonus.get("tribe", []):
		if unit_tribes.has(tribe):
			gain += int(tribe_bonus.get("atk", 0))
			break
	return gain

## Face damage an Ao Ativar (of a unit or artifact) or the Leader power adds this turn. `activator` is that unit or
## artifact, null for the Leader power. Answer: {"damage": int, "aim": int, "direct": bool}, or {} when it adds none.
##   - direct damage that can be aimed at the enemy Leader: "aim" is the Leader, "direct" is true;
##   - an +ATK buff: its gain on the best attacker that can reach the face ("aim" is that unit, 0 when it needs no
##     aim); a unit that taps itself to activate gives up its own attack, which is taken off the gain.
## Abilities that cost Vida, or make a unit pay (discard / sacrifice), are left out: too fiddly to promise in a plan.
static func _face_gain_of_ability(g: GameState, p: int, ability: Dictionary, activator: Card, face_attackers: Array) -> Dictionary:
	if ability.has("extra_cost") or ability.has("life_cost") or ability.has("graveyard_cost"):
		return {}
	var effects: Array = ability.get("effects", [])
	var enemy_leader_uid: int = GameState.LEADER_UID[g.opponent(p)]
	var activator_uid := activator.uid if activator != null else 0
	var aim_spec := g.target_spec(effects)
	var direct_damage := 0
	for effect in effects:
		if effect.get("action", "") == "damage" and effect.get("target", "") in ["any", "enemy_leader"]:
			direct_damage += int(effect.get("amount", 0))
	if direct_damage > 0 and aim_spec in ["any", "enemy_leader"] \
			and g.valid_targets(p, aim_spec, activator_uid, false, effects).has(enemy_leader_uid):
		return {"damage": direct_damage, "aim": enemy_leader_uid, "direct": true}
	var buff := _attack_buff_effect(effects)
	if buff.is_empty() or face_attackers.is_empty():
		return {}
	var taps_itself: bool = ability.get("exhaust", false) and activator != null
	var best_gain := 0
	var best_aim := 0
	match buff.get("target", ""):
		"self":
			if activator != null and not taps_itself and face_attackers.has(activator):
				best_gain = _attack_gain_of_buff(g, p, buff, activator)
				best_aim = 0
		"all_ally_units":
			for unit: Card in face_attackers:
				if buff.has("unit_filter") and not CardFilter.matches(unit.card_id, buff["unit_filter"]):
					continue
				best_gain += _attack_gain_of_buff(g, p, buff, unit)
		"ally_unit":
			var valid_aims: Array = g.valid_targets(p, aim_spec, activator_uid, false, effects)
			for unit: Card in face_attackers:
				if not valid_aims.has(unit.uid) or (taps_itself and unit == activator):
					continue
				var gain := _attack_gain_of_buff(g, p, buff, unit)
				if gain > best_gain:
					best_gain = gain
					best_aim = unit.uid
	if taps_itself and face_attackers.has(activator):
		best_gain -= g.strike_power_of(activator) # it turns to activate, so it no longer attacks
	if best_gain <= 0:
		return {}
	return {"damage": best_gain, "aim": best_aim, "direct": false}

## Every ability the player could activate for face damage right now: the Leader power, then the Ao Ativar of the
## units and artifacts in play. Same entry shape as a hand card (see _affordable_face_lines), with "activator"
## (the unit/artifact; null for the Leader power) in place of "card".
static func _face_ability_sources(g: GameState, p: int, face_attackers: Array) -> Array:
	var sources: Array = []
	if g.can_use_ability(p):
		var power: Dictionary = CardDB.leader(g.players[p]["leader_id"])["ability"]
		var power_gain := _face_gain_of_ability(g, p, power, null, face_attackers)
		if not power_gain.is_empty():
			sources.append(_ability_source(g, power, null, power_gain))
	var holders: Array = g.players[p]["board"] + g.players[p]["relics"]
	for holder: Card in holders:
		var ability: Dictionary = holder.data().get("activated", {})
		if ability.is_empty() or not g.can_activate(p, holder.uid):
			continue
		var gain := _face_gain_of_ability(g, p, ability, holder, face_attackers)
		if not gain.is_empty():
			sources.append(_ability_source(g, ability, holder, gain))
	return sources

static func _ability_source(g: GameState, ability: Dictionary, activator: Card, gain: Dictionary) -> Dictionary:
	return {
		"card": null,
		"activator": activator,
		"aim": int(gain["aim"]),
		"damage": int(gain["damage"]),
		"cost": int(ability.get("cost", 0)),
		"paid_by_reserve": g.reserve_pays(ability),
		"needs_slot": false,
		"rank": 1 if gain["direct"] else 2,
	}

## Every group of things that adds face damage and can be paid this turn: hand cards (plain Momentum, the Reserva for
## Rápido/Instantâneo spells, free field slots for units), the Leader power and the Ao Ativar of what is in play.
## Each line: {"steps": Array[Dictionary], "damage": int, "cost": int}; a step is a source as built here or by
## _face_ability_sources: {"card" (hand card, or null for an ability), "activator", "aim", "damage", "cost",
## "paid_by_reserve", "needs_slot", "rank"}. "rank" is the order to do things in (0 unit, 1 direct damage, 2 buff).
static func _affordable_face_lines(g: GameState, p: int, held_card_ids: Array = []) -> Array:
	var face_attackers := _face_capable_attackers(g, p)
	var sources: Array = []
	for card: Card in g.players[p]["hand"]:
		var card_data := CardDB.card(card.card_id)
		if held_card_ids.has(card.card_id) or g.is_dud(p, card_data) or not g.can_play(p, card.uid):
			continue
		if card_data.get("cost_sacrifice", false) or card_data.has("extra_cost"):
			continue # another unit pays for it: too fiddly to promise in a plan
		var damage := _face_damage_of_hand_card(g, p, card_data, face_attackers)
		if damage <= 0:
			continue
		var card_rank := 0
		if card_data.get("type", "") != "unit":
			card_rank = 1 if _is_face_burn(card_data) else 2
		sources.append({
			"card": card,
			"activator": null,
			"aim": 0,
			"damage": damage,
			"cost": g.cost_of(p, card_data, card),
			"paid_by_reserve": card_data.get("type", "") == "spell" and g.reserve_pays(card_data),
			"needs_slot": g.takes_field_slot(card_data, false),
			"rank": card_rank,
		})
	sources.append_array(_face_ability_sources(g, p, face_attackers))
	var plain_budget := g.budget(p, false)
	var reserve := int(g.players[p]["reserve"])
	var free_slots: int = GameState.BOARD_LIMIT - g.slots_used(p) - int(g.players[p]["frozen_slots"])
	var lines: Array = []
	for subset in range(1, 1 << sources.size()): # a hand holds a handful of useful cards, so every subset is cheap to try
		var steps: Array = []
		var damage_sum := 0
		var slow_cost := 0
		var reserve_cost := 0
		var slots_needed := 0
		for i in sources.size():
			if not subset & (1 << i):
				continue
			var source: Dictionary = sources[i]
			steps.append(source)
			damage_sum += int(source["damage"])
			if source["paid_by_reserve"]:
				reserve_cost += int(source["cost"])
			else:
				slow_cost += int(source["cost"])
			if source["needs_slot"]:
				slots_needed += 1
		if slots_needed > free_slots or slow_cost + maxi(0, reserve_cost - reserve) > plain_budget:
			continue
		lines.append({"steps": steps, "damage": damage_sum, "cost": slow_cost + reserve_cost})
	return lines

## The most face damage the hand, the Leader power and the Ao Ativar in play could still add this turn (0 when none reaches the face).
static func _hand_face_reach(g: GameState, p: int, held_card_ids: Array = []) -> int:
	var best := 0
	for line: Dictionary in _affordable_face_lines(g, p, held_card_ids):
		best = maxi(best, int(line["damage"]))
	return best

## The steps (in the order to do them: hand cards to play, abilities to activate) that close the game this turn
## together with the board, or [] when the board already does it, or when no affordable group covers the shortfall.
## Among the groups that do, the one with the fewest steps wins, then the cheapest: the rest of the Momentum stays
## free for other plays. A step is a source of _affordable_face_lines.
static func _lethal_line(g: GameState, p: int, held_card_ids: Array = []) -> Array:
	var shortfall: int = g.players[g.opponent(p)]["leader_hp"] - _face_strike_total(g, p)
	if shortfall <= 0:
		return [] # the attackers alone are lethal: nothing to buy, just swing
	var best_line: Dictionary = {}
	for line: Dictionary in _affordable_face_lines(g, p, held_card_ids):
		if int(line["damage"]) < shortfall:
			continue
		if best_line.is_empty() or line["steps"].size() < best_line["steps"].size() \
				or (line["steps"].size() == best_line["steps"].size() and int(line["cost"]) < int(best_line["cost"])):
			best_line = line
	if best_line.is_empty():
		return []
	var ordered: Array = best_line["steps"].duplicate()
	# units go first (their Ao Entrar and Rompante change the board), direct damage next, buffs last (they pump what is out by then)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return int(a["rank"]) < int(b["rank"]))
	return ordered

## Does the next step of the lethal line, if there is a line. [] when there is nothing to do (the usual logic runs).
static func _play_toward_lethal(g: GameState, p: int, held_card_ids: Array) -> Array:
	var enemy_leader_uid: int = GameState.LEADER_UID[g.opponent(p)]
	for step: Dictionary in _lethal_line(g, p, held_card_ids):
		var events: Array = []
		var card: Card = step["card"]
		if card == null:
			events = _run_ability_step(g, p, step)
		else:
			var card_data := CardDB.card(card.card_id)
			if card_data.get("type", "") == "spell" and _is_face_burn(card_data):
				if g.valid_targets(p, g.card_spec(card_data)).has(enemy_leader_uid):
					events = g.play_card(p, card.uid, enemy_leader_uid, 0)
			else:
				events = _try_play_card(g, p, card)
		if not events.is_empty():
			return events
	return []

## Activates the ability of a lethal-line step: the Leader power when it has no activator, else the Ao Ativar of
## the unit or artifact, aimed at the step's aim (the enemy Leader, or the unit that receives the buff).
static func _run_ability_step(g: GameState, p: int, step: Dictionary) -> Array:
	var activator: Card = step["activator"]
	if activator == null:
		return g.use_ability(p, int(step["aim"]))
	return g.activate(p, activator.uid, int(step["aim"]))

## Answer to a unit's Ao Entrar prompt when the unit's damage can be aimed at the enemy Leader and that, together
## with what the board and the rest of the hand can still add, finishes the game. 0 when it should not go face.
static func _lethal_enter_target(g: GameState, p: int, card_data: Dictionary, asked_spec: String, entering_uid: int) -> int:
	if g.active != p:
		return 0
	var enemy_leader_uid: int = GameState.LEADER_UID[g.opponent(p)]
	if not g.valid_targets(p, asked_spec, entering_uid).has(enemy_leader_uid):
		return 0
	var damage := 0
	for effect in card_data.get("effects", []):
		if effect.get("trigger", "") == "on_enter" and effect.get("action", "") == "damage" and effect.get("target", "") == asked_spec:
			damage += int(effect.get("amount", 0))
	if damage <= 0:
		return 0
	var enemy_hp: int = g.players[g.opponent(p)]["leader_hp"]
	if damage + _face_strike_total(g, p) + _hand_face_reach(g, p) >= enemy_hp:
		return enemy_leader_uid
	return 0

## A Provocação entering: tapped makes it guard (enemy attackers must challenge it). Worth it
## when it survives the strongest enemy hit, or when our Leader is low and needs the protection.
static func _wants_enter_tapped(g: GameState, p: int, unit: Card) -> bool:
	if unit == null:
		return false
	var strongest_enemy_atk := 0
	for enemy_unit: Card in g.players[g.opponent(p)]["board"]:
		strongest_enemy_atk = maxi(strongest_enemy_atk, g.strike_power_of(enemy_unit))
	var survives := unit.shield or g.damage_after_armor(unit, strongest_enemy_atk) < g.hp_left(unit)
	return survives or g.players[p]["leader_hp"] <= 10

## The artifact pick: free-standing artifacts are not units, so they have no stats to score; the priciest one wins.
## A unit that is also an artifact is an option too, and is judged by its cost like the others.
static func _priciest_artifact(g: GameState, options: Array) -> int:
	var best_uid := 0
	var best_cost := -1
	for uid in options:
		var artifact: Card = g.find_relic(uid) if g.find_relic(uid) != null else g.find_unit(uid)
		if artifact != null and int(artifact.data().get("cost", 0)) > best_cost:
			best_cost = int(artifact.data().get("cost", 0))
			best_uid = uid
	return best_uid

## The healing pick: whichever option (own Leader or ally unit) has the most damage to heal.
## Ties go to the Leader, which is listed last.
static func _most_damaged(g: GameState, p: int, options: Array) -> int:
	var projected := _healing_projection(g)
	var best_uid := 0
	var most_damage := -1
	for uid in options:
		var damage := 0
		if uid < 0:
			damage = projected.players[p]["leader_max"] - projected.players[p]["leader_hp"]
		else:
			var unit := projected.find_unit(uid)
			if unit == null:
				continue
			damage = unit.damage
		if damage >= most_damage:
			most_damage = damage
			best_uid = uid
	return best_uid
