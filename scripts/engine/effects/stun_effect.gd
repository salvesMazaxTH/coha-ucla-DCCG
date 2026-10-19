class_name StunEffect
extends Effect
## "stun": Atordoamento. The unit is tapped at once and gets "markers" (default 1) stun markers. Every time its
## owner's turn starts it loses one marker INSTEAD of untapping, so each marker costs the unit one untap.
## While it has a marker the unit can't attack, has no Rapidez and its Provocação forces nothing, but its ATK
## stays whole (it strikes back normally) and, being tapped, it can be challenged. Markers stack.

var markers := 1

func _read_parameters(data: Dictionary) -> void:
	markers = maxi(1, int(data.get("markers", 1)))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var unit := game.find_unit(target_uid)
	if unit == null:
		return
	unit.stun_markers += markers
	if not unit.has_kw("inerte"):
		unit.exhausted = true
	game._emit({"type": "stun", "uid": target_uid, "markers": unit.stun_markers})
