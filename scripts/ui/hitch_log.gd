class_name HitchLog
extends RefCounted
## Writes down the heavy work done each frame (an art loaded, a card photo painted, an effect started...),
## so when a frame takes too long the performance panel (?perf=1 on the web) can say what happened in it.

const SLOW_FRAME_MS := 65.0
const HITCHES_KEPT := 5
const MAX_LINE_LENGTH := 110

static var enabled := false
static var recent_hitches: PackedStringArray = []
static var _work_this_frame: PackedStringArray = []

static func note(work: String) -> void:
	if enabled:
		_work_this_frame.append(work)

## Called once per frame (by Main) with how long the last frame took.
static func end_frame(frame_seconds: float) -> void:
	if not enabled:
		return
	var frame_ms := frame_seconds * 1000.0
	if frame_ms >= SLOW_FRAME_MS:
		var what := "nada anotado" if _work_this_frame.is_empty() else ", ".join(_work_this_frame)
		recent_hitches.append(("%d ms: %s" % [roundi(frame_ms), what]).left(MAX_LINE_LENGTH))
		if recent_hitches.size() > HITCHES_KEPT:
			recent_hitches.remove_at(0)
	_work_this_frame.clear()
