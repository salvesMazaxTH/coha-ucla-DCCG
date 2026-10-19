class_name DamageEffect
extends Effect
## "damage": deals `amount` damage to each target.
## "amount_from": "sacrificed_atk" uses the attack of the unit a "sacrifice" just killed;
## "self_half_armor" uses half of this unit's own Armadura, rounded up (Tharox);
## "target_veneno_markers" deals `amount` damage per Veneno marker on the target (Hikari).
## "ally_reduce": {"essence", "amount"} = own units of that essence take only that much.
## "adjacent_amount": the units right beside each target also take this much (Deslizamento de Placas).
## "freeze": true also freezes each target that survives the damage (Mestra do Gelo Frígido).
## "stun": true also gives each target that survives the damage one Atordoamento marker.
## "amount_if_frozen": a target that is already Congelada takes this much instead of `amount` (Sabrina).
## "amount_if_stunned": same for a target that is already Atordoada (Layla's Ao Atacar).

var amount := 0
var amount_from := ""
var ally_reduce: Dictionary = {}
var adjacent_amount := 0
var freezes_target := false
var stuns_target := false
var amount_if_frozen := 0
var amount_if_stunned := 0

func _read_parameters(data: Dictionary) -> void:
	amount = int(data.get("amount", 0))
	amount_from = String(data.get("amount_from", ""))
	ally_reduce = data.get("ally_reduce", {})
	adjacent_amount = int(data.get("adjacent_amount", 0))
	freezes_target = bool(data.get("freeze", false))
	stuns_target = bool(data.get("stun", false))
	amount_if_frozen = int(data.get("amount_if_frozen", 0))
	amount_if_stunned = int(data.get("amount_if_stunned", 0))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var damage_amount := context.sacrificed_attack if amount_from == "sacrificed_atk" else amount
	if amount_from == "self_half_armor":
		var source_unit := game.find_unit(context.self_uid)
		damage_amount = ceili(game.armor_of(source_unit) / 2.0) if source_unit != null else 0
	var victim := game.find_unit(target_uid)
	if amount_from == "target_veneno_markers":
		var marker_count := int(victim.dot_markers.get("veneno", 0)) if victim != null else 0
		damage_amount = amount * marker_count
	# checked before the damage, so a freeze applied by this same effect doesn't count
	if amount_if_frozen > 0 and victim != null and game.is_frozen(victim):
		damage_amount = amount_if_frozen
	if amount_if_stunned > 0 and victim != null and victim.is_stunned():
		damage_amount = amount_if_stunned
	if not ally_reduce.is_empty() and victim != null and victim.owner == context.controller \
			and CardDB.has_essence(victim.data(), ally_reduce["essence"]):
		damage_amount = int(ally_reduce["amount"])
	# the neighbours are found before any damage, so they stay the same if the target dies
	var neighbour_uids := _neighbours_of(game, victim) if adjacent_amount > 0 else []
	var dealt := game._deal_damage(target_uid, damage_amount, null)
	# effect damage has no source card, so a "burns_on_damage" unit dealing it through its own effect burns here
	var dealer := game.find_unit(context.self_uid)
	if dealer != null and dealt > 0:
		game.burn_target_of_damage_dealer(dealer, target_uid)
	for neighbour_uid in neighbour_uids:
		game._deal_damage(neighbour_uid, adjacent_amount, null)
	# a unit the damage already killed is gone from the board, so find_unit finds nothing to freeze
	if freezes_target:
		FreezeEffect.new().apply(context, target_uid)
	if stuns_target:
		StunEffect.new().apply(context, target_uid)

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
