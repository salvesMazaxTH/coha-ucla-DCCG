class_name StripEffect
extends Effect
## Takes protections away from the target unit, told apart by `action`:
## "strip_defenses": the unit loses its Escudo and all of its Armadura (printed, gained, temporary) for good (Furador de Casca).
##   The Escudo Mágico is a different protection and stays.
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
	else:
		_strip_defenses(context, unit)

func _strip_defenses(context: EffectContext, unit: Card) -> void:
	if not unit.shield and unit.armor_total() <= 0:
		return # nothing to strip
	unit.shield = false
	unit.armor = 0
	unit.temp_armor = 0
	unit.turn_armor = 0
	context.game._emit({"type": "strip_defenses", "uid": unit.uid})

func _suppress_keyword(context: EffectContext, unit: Card) -> void:
	if not unit.keywords.has(keyword_name):
		return
	unit.keywords.erase(keyword_name)
	unit.lost_keywords.append(keyword_name)
	context.game._emit({"type": "keyword_lost", "uid": unit.uid, "keyword": keyword_name})
