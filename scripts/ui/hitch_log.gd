class_name HitchLog
extends RefCounted
## Writes down the heavy work done each frame (an art loaded, a card photo painted, an effect started...),
## so when a frame takes too long the performance panel (?perf=1 on the web) can say what happened in it.

## A frame this slow starts (or continues) a run of slow frames; the run is written down when it ends.
const SLOW_FRAME_MS := 65.0
## A slow frame on its own is only written down from this long.
const LONE_HITCH_MS := 100.0
## Slow frames in a row are written down when together they reach this long.
const HITCH_RUN_MS := 130.0
const HITCHES_KEPT := 5
const MAX_LINE_LENGTH := 110

static var enabled := false
static var recent_hitches: PackedStringArray = []
static var _work_this_frame: PackedStringArray = []
static var _run_frames := 0
static var _run_ms := 0.0
static var _run_work: PackedStringArray = []

static func note(work: String) -> void:
	if enabled:
		_work_this_frame.append(work)

## Called once per frame (by Main) with how long the last frame took.
static func end_frame(frame_seconds: float) -> void:
	if not enabled:
		return
	var frame_ms := frame_seconds * 1000.0
	if frame_ms >= SLOW_FRAME_MS:
		_run_frames += 1
		_run_ms += frame_ms
		_run_work.append_array(_work_this_frame)
	elif _run_frames > 0:
		_write_down_run()
	_work_this_frame.clear()

static func _write_down_run() -> void:
	var long_enough := _run_ms >= LONE_HITCH_MS if _run_frames == 1 else _run_ms >= HITCH_RUN_MS
	if long_enough:
		var what := "nada anotado" if _run_work.is_empty() else ", ".join(_run_work)
		var duration := "%d ms" % roundi(_run_ms)
		if _run_frames > 1:
			duration += " (%d seguidos)" % _run_frames
		recent_hitches.append(("%s: %s" % [duration, what]).left(MAX_LINE_LENGTH))
		if recent_hitches.size() > HITCHES_KEPT:
			recent_hitches.remove_at(0)
	_run_frames = 0
	_run_ms = 0.0
	_run_work.clear()
