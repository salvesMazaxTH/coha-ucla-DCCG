class_name StripEffect
extends Effect
## Takes protections away from the target unit, told apart by `action`:
## "strip_defenses": the unit loses its Escudo and all of its Armadura (printed, gained, temporary) for good (Furador de Casca).
##   The Escudo Mágico is a different protection and stays.
## "strip_armor" (Soren): like strip_defenses, but only the Armadura goes; the Escudo stays.
## "strip_magic_shield" (Gavião de Vigília): the unit loses its Escudo Mágico (it breaks, as if an effect had hit it).
##   Nothing else is touched. It does nothing to a unit with no Escudo Mágico.
## "suppress_keyword": the unit loses the keyword named in "keyword" until the end of this turn, then gets it back
##   (Saltador de Cerca takes Provocação away so it can be walked past this turn).

var keyword_name := ""

func _read_parameters(data: Dictionary) -> void:
	keyword_name = String(data.get("keyword", ""))

func apply(context: EffectContext, target_uid: int) -> void:
	var unit := context.game.find_unit(target_uid)
	if unit == null:
		return
	if action == "suppress_keyword":
		_suppress_keyword(context, unit)
	elif action == "strip_magic_shield":
		_strip_magic_shield(context, unit)
	else:
		_strip_defenses(context, unit, action == "strip_armor")

func _strip_defenses(context: EffectContext, unit: Card, armor_only: bool) -> void:
	var loses_shield := unit.shield and not armor_only
	if not loses_shield and unit.armor_total() <= 0:
		return # nothing to strip
	if not armor_only:
		unit.shield = false
	unit.armor = 0
	unit.temp_armor = 0
	unit.turn_armor = 0
	unit.forget_stat_sources("armor")
	context.game.emit_event({"type": "strip_defenses", "uid": unit.uid})

func _strip_magic_shield(context: EffectContext, unit: Card) -> void:
	if not unit.magic_shield:
		return
	unit.magic_shield = false
	unit.magic_shield_until_next_turn = false
	unit.magic_shield_until_end_turn = false
	context.game.emit_event({"type": "magic_shield_break", "uid": unit.uid})

func _suppress_keyword(context: EffectContext, unit: Card) -> void:
	if not unit.keywords.has(keyword_name):
		return
	unit.keywords.erase(keyword_name)
	unit.lost_keywords.append(keyword_name)
	context.game.emit_event({"type": "keyword_lost", "uid": unit.uid, "keyword": keyword_name})
