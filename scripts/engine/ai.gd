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
	# burn that finishes the game goes first, before the Momentum is spent on anything else
	if g.active == p and g.stack.is_empty() and _burn_plan(g, p) == "lethal":
		var finisher_events := _cast_face_burn(g, p, held_card_ids)
		if not finisher_events.is_empty():
			return finisher_events
	# hand first; Réquiem spells in the graveyard are the fallback (they cost 2 more)
	var candidates: Array = _hand_most_expensive_first(g, p) + g.requiem_cards(p)
	for card: Card in candidates:
		if held_card_ids.has(card.card_id) or not g.can_play(p, card.uid):
			continue
		var card_data := CardDB.card(card.card_id)
		if g.takes_field_slot(card_data, g.is_subito_play(p, card_data)) and not g.has_free_slot(p):
			continue # the AI never banishes its own permanents to make room
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
				if not _buff_target_is_worth_it(g, unit, _temporary_buff_effect(card_data)):
					continue
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
		if card_data["type"] == "spell" and not _spell_changes_the_game(g, p, card.uid, target, second_target):
			continue # it would resolve and change nothing: keep the Momentum (and the card)
		var events := g.play_card(p, card.uid, target, second_target)
		if not events.is_empty():
			return events
	# The Encarnação is a powerful fallback, not an automatic first play: spend Momentum on
	# worthwhile cards from hand first, then cast it if no other legal play is available.
	if g.can_cast_incarnation(p) and g.has_free_slot(p): # never banishes its own permanent to make room
		var incarnation_events := g.cast_incarnation(p)
		if not incarnation_events.is_empty():
			return incarnation_events
	for unit: Card in g.players[p]["board"]:
		# untargeted Ao Ativar, before attacking (e.g. Yuki's temporary attack)
		var activated_effects: Array = unit.data().get("activated", {}).get("effects", [])
		if g.can_activate(p, unit.uid) and g.target_spec(activated_effects) == "" and g.can_attack(unit) and _revive_is_worth_it(g, p, activated_effects):
			return g.activate(p, unit.uid)
	for artifact: Card in g.players[p]["relics"]:
		# free-standing artifacts' untargeted Ao Ativar (e.g. Ossuário Sem Fundo's revive)
		var artifact_effects: Array = CardDB.card(artifact.card_id).get("activated", {}).get("effects", [])
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
	if g.can_use_ability(p) and not _ability_borrows_momentum(CardDB.leader(g.players[p]["leader_id"])["ability"]["effects"]):
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
	var temporary_buff := _temporary_buff_effect(card_data)
	if not temporary_buff.is_empty() and _temporary_buff_beneficiaries(g, p, temporary_buff).is_empty():
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
	var burn_reach := maxi(_burn_reach(g, p, g.budget(p, true)), _burn_reach(g, p, _next_turn_budget(g, p)))
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
const ENGINE_TRIGGERS := ["on_ally_death", "on_turn_start", "on_turn_end", "constante"]

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

## Momentum the AI can spend on spells next turn (one more than now, plus what is banked in the Reserva).
static func _next_turn_budget(g: GameState, p: int) -> int:
	return mini(g.momentum_cap(p), int(g.players[p]["max_momentum"]) + 1) + int(g.players[p]["reserve"])

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
static func _burn_reach(g: GameState, p: int, budget: int) -> int:
	var damages: Array = []
	var costs: Array = []
	for card: Card in g.players[p]["hand"]:
		var card_data := CardDB.card(card.card_id)
		var damage := _face_burn_damage(card_data)
		if damage > 0 and not g.is_dud(p, card_data):
			damages.append(damage)
			costs.append(g.cost_of(p, card_data, card))
	var best := 0
	for subset in range(1, 1 << damages.size()): # burn is a handful of cards, so trying every subset is cheap
		var damage_sum := 0
		var cost_sum := 0
		for i in damages.size():
			if subset & (1 << i):
				damage_sum += damages[i]
				cost_sum += costs[i]
		if cost_sum <= budget:
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
	var burn_now := _burn_reach(g, p, g.budget(p, true))
	if burn_now <= 0:
		return "free"
	if g.active == p and enemy_hp <= burn_now + _face_strike_total(g, p):
		return "lethal"
	var burn_next := maxi(burn_now, _burn_reach(g, p, _next_turn_budget(g, p)))
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
static func _priciest_artifact(g: GameState, options: Array) -> int:
	var best_uid := 0
	var best_cost := -1
	for uid in options:
		var relic := g.find_relic(uid)
		if relic != null and int(relic.data().get("cost", 0)) > best_cost:
			best_cost = int(relic.data().get("cost", 0))
			best_uid = uid
	return best_uid

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
