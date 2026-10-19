class_name EffectRegistry
extends RefCounted
## Maps each "action" of cards.json to its Effect class.
## A new action: write its class in this folder and add one line here.

const AddDotEffectScript = preload("res://scripts/engine/effects/add_dot_effect.gd")
const DeathWardEffectScript = preload("res://scripts/engine/effects/death_ward_effect.gd")

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
	"grave_retrieve": DeckEffect,
	"freeze": FreezeEffect,
	"stun": StunEffect,
	"cap_stats": CapStatsEffect,
	"add_dot": AddDotEffectScript,
	"burn": AddDotEffectScript, # compatibility alias for old card data
	"exhaust": ExhaustEffect,
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
	"put_artifact": PutArtifactEffect,
	"arm_death_ward": DeathWardEffectScript,
	"decoy": DecoyEffect,
	"mill": MillEffect,
	"fatigue_burn": FatigueBurnEffect,
	"mill_pick": MillEffect,
	"revive": ReviveEffect,
	"revive_self": ReviveEffect,
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
	"buff": BuffEffect,
	"counter": CounterEffect,
	"modify_cost": ModifyCostEffect,
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
}

## Actions with no target: continuous abilities, never run by a trigger.
const STATIC_ACTIONS := ["cost_reduction", "scale", "species_aura", "graveyard_armor", "graveyard_damage_reduction", "double_constants", "double_enter", "double_death"]

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
