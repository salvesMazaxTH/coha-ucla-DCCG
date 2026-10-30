class_name DamageEffect
extends Effect
## "damage": deals `amount` damage to each target.
## "amount_from": "sacrificed_atk" uses the attack of the unit a "sacrifice" just killed;
## "self_half_armor" uses half of this unit's own Armadura, rounded up (Tharox);
## "target_veneno_markers" deals `amount` damage per Veneno marker on the target (Hikari);
## "self_atk" uses this unit's current Ataque (its Ataque at the hit that fired the effect if it already died; Rália).
## "ally_reduce": {"element", "amount"} = own units of that element take only that much.
## "adjacent_amount": the units right beside each target also take this much (Deslizamento de Placas).
## "freeze": true also freezes each target that survives the damage (Mestra do Gelo Frígido).
## "stun": true also gives each target that survives the damage one Atordoamento marker.
## "amount_if_frozen": a target that is already Congelada takes this much instead of `amount` (Sabrina).
## "amount_if_stunned": same for a target that is already Atordoada (Layla's Ao Atacar).
## "amount_from": "momentum_left" deals `amount` damage per `divisor` Momentum the controller still has (Antena de Varal, Curto-Circuito).
## "amount_from": "own_graveyard_cards" deals `amount` damage per `divisor` cards in the controller's graveyard (Ossada Rancorosa).
## "spend_momentum": true (with momentum_left) also spends all that Momentum (Curto-Circuito).
## "amount_from": "healing_this_round" deals `amount` damage per Vida the controller's Leader and units recovered this turn (Banquete Carmesim).
## "lifesteal": true heals the controller's Leader by the damage this effect really dealt (Rália).
## "lifesteal_self": true (with lifesteal) also heals this unit by that same damage, if it is still on the board.
## "source_gain_per_kill": N = if the damage kills a unit, this unit permanently gains +N Ataque (Jovahr).

var amount := 0
var amount_from := ""
var ally_reduce: Dictionary = {}
var adjacent_amount := 0
var freezes_target := false
var stuns_target := false
var amount_if_frozen := 0
var amount_if_stunned := 0
var amount_if_leader := 0
var heals_by_damage_dealt := false
var heals_source_too := false
var divisor := 1
var spends_momentum := false
var source_gain_per_kill := 0

func _read_parameters(data: Dictionary) -> void:
	divisor = maxi(1, int(data.get("divisor", 1)))
	spends_momentum = bool(data.get("spend_momentum", false))
	amount = int(data.get("amount", 0))
	amount_from = String(data.get("amount_from", ""))
	ally_reduce = data.get("ally_reduce", {})
	adjacent_amount = int(data.get("adjacent_amount", 0))
	freezes_target = bool(data.get("freeze", false))
	stuns_target = bool(data.get("stun", false))
	amount_if_frozen = int(data.get("amount_if_frozen", 0))
	amount_if_stunned = int(data.get("amount_if_stunned", 0))
	amount_if_leader = int(data.get("amount_if_leader", 0))
	heals_by_damage_dealt = bool(data.get("lifesteal", false))
	heals_source_too = bool(data.get("lifesteal_self", false))
	source_gain_per_kill = int(data.get("source_gain_per_kill", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var damage_amount := context.sacrificed_attack if amount_from == "sacrificed_atk" else amount
	if amount_from == "self_half_armor":
		var source_unit := game.find_unit(context.self_uid)
		damage_amount = ceili(game.armor_of(source_unit) / 2.0) if source_unit != null else 0
	if amount_from == "self_atk":
		damage_amount = _current_attack_of_source(context)
	if amount_from == "momentum_left":
		var momentum_left := int(game.players[context.controller]["momentum"])
		damage_amount = amount * (momentum_left / divisor)
		if spends_momentum:
			game.drain_momentum(context.controller)
		if damage_amount <= 0:
			return
	if amount_from == "own_graveyard_cards":
		var graveyard_size: int = game.players[context.controller]["graveyard"].size()
		damage_amount = amount * (graveyard_size / divisor)
		if damage_amount <= 0:
			return
	if amount_from == "healing_this_round":
		damage_amount = amount * int(game.players[context.controller]["healing_this_round"])
		if damage_amount <= 0:
			return
	var victim := game.find_unit(target_uid)
	if amount_from == "target_veneno_markers":
		var marker_count := int(victim.dot_markers.get("veneno", 0)) if victim != null else 0
		damage_amount = amount * marker_count
	# checked before the damage, so a freeze applied by this same effect doesn't count
	if amount_if_frozen > 0 and victim != null and game.is_frozen(victim):
		damage_amount = amount_if_frozen
	if amount_if_stunned > 0 and victim != null and victim.is_stunned():
		damage_amount = amount_if_stunned
	if amount_if_leader > 0 and GameState.LEADER_UID.has(target_uid):
		damage_amount = amount_if_leader
	if not ally_reduce.is_empty() and victim != null and victim.owner == context.controller \
			and CardDB.has_element(victim.data(), ally_reduce["element"]):
		damage_amount = int(ally_reduce["amount"])
	# the neighbours are found before any damage, so they stay the same if the target dies
	var neighbour_uids := _neighbours_of(game, victim) if adjacent_amount > 0 else []
	var damage_dealt := game._deal_damage(target_uid, damage_amount, null)
	# deaths are settled later, so a victim left with no Vida on the board is the one this damage killed
	if source_gain_per_kill > 0 and victim != null and damage_dealt > 0 and victim.hp_left() <= 0:
		_grant_kill_bonus(context)
	for neighbour_uid in neighbour_uids:
		damage_dealt += game._deal_damage(neighbour_uid, adjacent_amount, null)
	if heals_by_damage_dealt:
		game._heal_leader(context.controller, damage_dealt, context.heal_origin())
		if heals_source_too:
			_heal_source_unit(context, damage_dealt)
	# a unit the damage already killed is gone from the board, so find_unit finds nothing to freeze
	if freezes_target:
		FreezeEffect.new().apply(context, target_uid)
	if stuns_target:
		StunEffect.new().apply(context, target_uid)

## The unit that owns this effect permanently gains Ataque for a kill (nothing happens if it already left the board).
func _grant_kill_bonus(context: EffectContext) -> void:
	var source_unit := context.game.find_unit(context.self_uid)
	if source_unit == null:
		return
	source_unit.atk += source_gain_per_kill
	source_unit.record_stat_change(context.source_id(), "", {"atk": source_gain_per_kill})
	context.game._emit({"type": "buff", "uid": source_unit.uid, "atk": source_gain_per_kill, "hp": 0, "keywords": []})

## Heals the unit that owns this effect (never above its Vida); a unit that already left the board is not healed.
func _heal_source_unit(context: EffectContext, heal_amount: int) -> void:
	var source_unit := context.game.find_unit(context.self_uid)
	if source_unit == null or context.game.unit_heal_blocked(source_unit):
		return
	var healed := mini(heal_amount, source_unit.damage)
	if healed > 0:
		context.game._emit({"type": "heal", "uid": source_unit.uid, "amount": healed})
		source_unit.damage -= healed
		context.game.emit_unit_healed(source_unit, healed, context.heal_origin())

## The Ataque of the unit that owns this effect: live while it is on the board, otherwise the
## Ataque it had when it dealt the damage that fired an Ao Causar Dano (0 if neither is known).
func _current_attack_of_source(context: EffectContext) -> int:
	var source_unit := context.game.find_unit(context.self_uid)
	if source_unit != null:
		return context.game.atk_of(source_unit)
	if context.event != null:
		return int(context.event.data.get("dealer_atk", 0))
	return 0

## The units right to the left and right of `unit` on its owner's board.
func _neighbours_of(game: GameState, unit: Card) -> Array:
	if unit == null:
		return []
	var board: Array = game.players[unit.owner]["board"]
	var index := board.find(unit)
	var neighbour_uids: Array = []
	for neighbour_index in [index - 1, index + 1]:
		if index >= 0 and neighbour_index >= 0 and neighbour_index < board.size():
			neighbour_uids.append(board[neighbour_index].uid)
	return neighbour_uids
