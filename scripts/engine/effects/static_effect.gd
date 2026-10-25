class_name StaticEffect
extends Effect
## "cost_reduction", "scale", "species_aura", "graveyard_armor", "graveyard_damage_reduction" and the doublers "double_constants", "double_enter", "double_death" (read by GameState.has_doubler): continuous abilities that never
## run from a trigger. GameState.cost_of reads cost_reduction; _refresh_scaling reads scale and
## species_aura (Ataque/Vida) and momentum_surge (Ataque, keywords and Crítico while the owner has
## Momentum above the normal cap: {"min_momentum": 11, "atk": 15, "keywords": [...], "critico": 4}); armor_of reads species_aura (Armadura) and graveyard_armor.
## "momentum_cap" ({"cap": 12}) raises the owner's Momentum ceiling (read by GameState.momentum_cap).
## All of them are read straight from `raw`.

func is_static() -> bool:
	return action == "cost_reduction" or super()
