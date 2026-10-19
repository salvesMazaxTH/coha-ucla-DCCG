class_name StaticEffect
extends Effect
## "cost_reduction", "scale", "species_aura", "graveyard_armor", "graveyard_damage_reduction" and the doublers "double_constants", "double_enter", "double_death" (read by GameState.has_doubler): continuous abilities that never
## run from a trigger. GameState.cost_of reads cost_reduction; _refresh_scaling reads scale and
## species_aura (Ataque/Vida); armor_of reads species_aura (Armadura) and graveyard_armor.
## All of them are read straight from `raw`.

func is_static() -> bool:
	return action == "cost_reduction" or super()
