class_name EffectRegistry
extends RefCounted
## Maps each "action" of cards.json to its Effect class.
## A new action: write its class in this folder and add one line here.

const AddDotEffectScript = preload("res://scripts/engine/effects/add_dot_effect.gd")
const DeathWardEffectScript = preload("res://scripts/engine/effects/death_ward_effect.gd")
const AutoAttackEffectScript = preload("res://scripts/engine/effects/auto_attack_effect.gd")
const SpendAllMomentumEffectScript = preload("res://scripts/engine/effects/spend_all_momentum_effect.gd")
const EquipSelfEffectScript = preload("res://scripts/engine/effects/equip_self_effect.gd")
const ShoutEffectScript = preload("res://scripts/engine/effects/shout_effect.gd")

static var ACTIONS: Dictionary = {
	"damage": DamageEffect,
	"heal_leader": HealEffect,
	"leader_max_up": HealEffect,
	"heal_full": HealEffect,
	"heal_unit": HealEffect,
	"draw": DrawEffect,
	"draw_discounted": DrawEffect,
	"tide_mark": TideMarkEffect,
	"search_deck": DeckEffect,
	"look_top": DeckEffect,
	"look_bottom": DeckEffect,
	"grave_retrieve": DeckEffect,
	"grave_to_hand": DeckEffect,
	"freeze": FreezeEffect,
	"unfreeze": FreezeEffect,
	"stun": StunEffect,
	"cap_stats": CapStatsEffect,
	"add_dot": AddDotEffectScript,
	"burn": AddDotEffectScript, # compatibility alias for old card data
	"exhaust": ExhaustEffect,
	"ready": ReadyEffect,
	"condemn": CondemnEffect,
	"freeze_slots": FreezeSlotsEffect,
	"add_card": AddCardEffect,
	"snowball": SnowballEffect,
	"snowball_level": SnowballLevelEffect,
	"transform_self": TransformEffect,
	"discard_hand_pick": DeckEffect,
	"summon_hand_pick": DeckEffect,
	"fight": FightEffect,
	"summon": SummonEffect,
	"summon_from": SummonFromEffect,
	"summon_copy": SummonCopyEffect,
	"put_artifact": PutArtifactEffect,
	"equip_table_artifact": EquipTableArtifactEffect,
	"equip_self": EquipSelfEffectScript,
	"inherit_equipment": InheritEquipmentEffect,
	"lose_durability": LoseDurabilityEffect,
	"arm_death_ward": DeathWardEffectScript,
	"decoy": DecoyEffect,
	"mill": MillEffect,
	"fatigue_burn": FatigueBurnEffect,
	"mill_pick": MillEffect,
	"revive": ReviveEffect,
	"revive_self": ReviveEffect,
	"revive_self_delayed": ReviveEffect,
	"revive_pick": ReviveEffect,
	"destroy": RemoveEffect,
	"destroy_artifact": RemoveEffect,
	"banish": RemoveEffect,
	"return_to_hand": ReturnToHandEffect,
	"kill_leader": RemoveEffect,
	"hold_veneno": HoldVenenoEffect,
	"veneno_lethal": VenenoLethalEffect,
	"sacrifice": SacrificeEffect,
	"fuse": FuseEffect,
	"gain_momentum": GainMomentumEffect,
	"raise_max_momentum": RaiseMaxMomentumEffect,
	"gain_reserve": GainReserveEffect,
	"empty_momentum_store": EmptyMomentumStoreEffect,
	"extra_turn": ExtraTurnEffect,
	"spend_all_momentum": SpendAllMomentumEffectScript,
	"restrict_play": RestrictPlayEffect,
	"buff": BuffEffect,
	"counter": CounterEffect,
	"modify_cost": ModifyCostEffect,
	"discount_hand": DiscountHandEffect,
	"cost_reduction": StaticEffect,
	"silence": SilenceEffect,
	"strip_defenses": StripEffect,
	"suppress_keyword": StripEffect,
	"scale": StaticEffect,
	"species_aura": StaticEffect,
	"graveyard_armor": StaticEffect,
	"graveyard_damage_reduction": StaticEffect,
	"double_constants": StaticEffect,
	"double_enter": StaticEffect,
	"double_death": StaticEffect,
	"momentum_surge": StaticEffect,
	"momentum_cap": StaticEffect,
	"auto_attack": AutoAttackEffectScript,
	"shout": ShoutEffectScript,
}

## Actions with no target: continuous abilities, never run by a trigger.
const STATIC_ACTIONS := ["cost_reduction", "scale", "species_aura", "graveyard_armor", "graveyard_damage_reduction", "double_constants", "double_enter", "double_death", "momentum_surge", "momentum_cap"]

static func is_known(action: String) -> bool:
	return ACTIONS.has(action)

## The Effect object for one JSON entry (an unknown action becomes an effect that does nothing).
static func parse(data: Dictionary) -> Effect:
	var effect_class: Variant = ACTIONS.get(String(data.get("action", "")), Effect)
	var effect: Effect = effect_class.new()
	effect.setup(data)
	return effect

## Effect objects for a JSON "effects" list, in the same order.
static func parse_list(entries: Array) -> Array:
	var effects: Array = []
	for data in entries:
		if data is Dictionary:
			effects.append(parse(data))
	return effects
