extends SceneTree
## Compares the recorded golden games with what the engine plays today. Not part of run_tests.gd on purpose:
## any card or deck balance change makes the goldens diverge. Run it by hand after an engine/rules change:
##   godot --headless --path . -s tests/golden_check.gd
## A divergence you did NOT intend is a bug; an intended one means re-recording with tests/golden_replay.gd.

func _init() -> void:
	var errors: Array[String] = preload("res://tests/golden_replay.gd").compare()
	for error in errors:
		printerr("FAIL: ", error)
	print("golden check done, failures: ", errors.size())
	quit(1 if not errors.is_empty() else 0)
