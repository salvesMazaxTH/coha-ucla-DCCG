extends SceneTree
## Focused smoke test for the local development tools: godot --headless --path . -s tests/dev_tools_smoke.gd

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func _init() -> void:
	var game := GameState.new("agua", "fogo", 17)
	_test_specific_draw(game)
	_test_random_draw(game)
	_test_resources(game)
	_test_leader_tools(game)
	if failures == 0:
		print("Development tools smoke tests passed.")
	quit(failures)

func _test_specific_draw(game: GameState) -> void:
	var card_id := String(game.players[0]["deck"][0].card_id)
	var deck_size: int = game.players[0]["deck"].size()
	var events := game.debug_draw_specific_card(0, card_id)
	check(game.players[0]["deck"].size() == deck_size - 1, "specific draw removes one card from the deck")
	check(game.players[0]["hand"].size() == GameState.START_HAND + 1, "specific draw adds a card to hand")
	check(game.players[0]["hand"].back().card_id == card_id, "specific draw chooses the requested card")
	check(not events.is_empty(), "specific draw returns game events")
	check(game.debug_draw_specific_card(0, "missing_card").is_empty(), "specific draw rejects cards absent from the deck")

func _test_random_draw(game: GameState) -> void:
	var hand_size: int = game.players[1]["hand"].size()
	game.debug_draw_cards(1, 2)
	check(game.players[1]["hand"].size() == hand_size + 2, "draw-count tool draws the requested number for either player")

func _test_resources(game: GameState) -> void:
	game.players[0]["momentum_lock_turn"] = game.turn
	game.debug_add_momentum(0, 3)
	check(game.players[0]["momentum"] == 3, "Momentum tool bypasses regular gain restrictions")
	game.players[0]["max_momentum"] = 4
	game.debug_refill_momentum(0)
	check(game.players[0]["momentum"] == 4, "Momentum refill restores current maximum")
	game.players[0]["battery"] = 0
	game.debug_refill_battery(0)
	check(game.players[0]["battery"] == GameState.BATTERY_CAP, "Bateria refills to its cap")

func _test_leader_tools(game: GameState) -> void:
	var old_max := int(game.players[0]["leader_max"])
	game.debug_raise_leader_max(0, 5)
	check(game.players[0]["leader_max"] == old_max + 5, "max-life tool raises maximum life")
	check(game.players[0]["leader_hp"] == old_max + 5, "max-life tool also raises current life")
	game.players[0]["leader_hp"] = 1
	game.debug_heal_leader(0)
	check(game.players[0]["leader_hp"] == game.players[0]["leader_max"], "full-heal tool restores current life")
	var hp_before := int(game.players[0]["leader_hp"])
	game.debug_damage_leader(0, 2)
	check(game.players[0]["leader_hp"] == hp_before - 2, "damage tool applies test damage")
