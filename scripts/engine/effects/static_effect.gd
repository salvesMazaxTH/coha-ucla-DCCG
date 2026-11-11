class_name StaticEffect
extends Effect
## "cost_reduction", "scale", "base_scale", "tribe_aura", "equipped_aura", "graveyard_armor", "graveyard_damage_reduction" and the doublers "double_constants", "double_enter", "double_death" (read by GameState.has_doubler): continuous abilities that never
## run from a trigger. GameState.cost_of reads cost_reduction; refresh_scaling reads scale and
## tribe_aura / equipped_aura (Ataque/Vida) and momentum_surge (Ataque, keywords and Crítico while the owner has
## Momentum above the normal cap: {"min_momentum": 10, "atk": 15, "keywords": [...], "critico": 4}); armor_of reads tribe_aura (Armadura) and graveyard_armor.
## "keyword_aura" ({"keywords": ["ataque_duplo"], "min_rapidez": 2, "include_self": true}) gives allied units the keywords while their own Rapidez is at least "min_rapidez" (GameState.keyword_aura_of, refreshed by refresh_scaling).
## "opponent_aura" ({"atk": 1, "hp": 0}) gives every ENEMY unit that bonus while the source is on the board (GameState.opponent_aura_bonus, refreshed by refresh_scaling; Magni's curse).
## "opponent_cost_tax" ({"card_type": "spell", "amount": 1}) makes the OPPONENT's cards of that type (empty = all) cost `amount` more while the source is on the board (GameState.opponent_cost_tax, read by cost_of; Cornélia Aldrovane).
## "spell_amplifier" ({"damage": 1, "draw": 1, "deck_units_max": 0, "deck_spell_ratio": 2, "deck_spell_ratio_strict": true}) makes the owner's spells that already damage / draw do more, while the deck condition holds (GameState.spell_amplifier_bonus; Ottilia Varnholt).
## "strike_cap" ({"stat": "atk" | "hp_left", "at_most": 3, "capped_damage": 1}) makes every unit on either board whose current stat is at most `at_most` strike for only `capped_damage`; two different cards with it cancel each other (GameState.strike_cap_applied; the edicts of Avarik and Avarion).
## "momentum_cap" ({"cap": 15}) raises the owner's Momentum ceiling (read by GameState.momentum_cap; Agiota das Nuvens).
## "battery_cap" ({"cap": 3}) raises how much the owner's Bateria holds when it refills (read by GameState.battery_cap; Agiota das Nuvens).
## "reservoir_store_limit" ({"limit": 2}) raises how many hand cards the owner may deposit in the Reservoir each turn (read by GameState.reservoir_store_limit; Eletroad).
## All of them are read straight from `raw`.

func is_static() -> bool:
	return action == "cost_reduction" or super()
