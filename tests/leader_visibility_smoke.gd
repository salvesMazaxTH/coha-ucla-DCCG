extends SceneTree

var failures := 0

func _init() -> void:
	_test_unreleased_leader_filter()
	if failures == 0:
		print("Leader visibility smoke tests passed (dev=%s)." % DeckDB.development_mode_enabled())
	quit(failures)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _test_unreleased_leader_filter() -> void:
	var leader_id := "drake"
	var leader := CardDB.leader(leader_id)
	var had_flag: bool = leader.has("unreleased")
	var previous: Variant = leader.get("unreleased", false)
	leader["unreleased"] = true
	var should_show := DeckDB.development_mode_enabled()
	check(DeckDB.is_leader_visible(leader_id) == should_show, "Leader visibility follows the debug launch flag")
	check(DeckDB.visible_leader_ids().has(leader_id) == should_show, "leader picker hides or reveals unreleased Leaders")
	check(DeckDB.is_deck_visible("drake") == should_show, "prebuilt decks using an unreleased Leader follow its visibility")
	var custom_id := DeckDB.PLAYER_PREFIX + "leader_visibility_smoke"
	DeckDB.register_custom(custom_id, "Test", "", leader_id, {}, String(leader.get("incarnation", "")))
	check(DeckDB.is_deck_visible(custom_id) == should_show, "saved decks using an unreleased Leader follow its visibility")
	DeckDB.clear_custom(DeckDB.PLAYER_PREFIX)
	if had_flag:
		leader["unreleased"] = previous
	else:
		leader.erase("unreleased")
