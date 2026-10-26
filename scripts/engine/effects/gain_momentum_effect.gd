class_name GainMomentumEffect
extends Effect
## "gain_momentum": +amount Momentum right now (never above the cap), or at the start of the
## controller's next turn ("next_turn": true). A negative amount with "next_turn" is a debt: the
## next turn starts with that much less Momentum (never below 0).
## "overflow": true lets the gain go past the normal cap (up to GameState.MOMENTUM_OVERFLOW_CAP) for this
## turn only; the part above the cap pays neutral cards and leader abilities, and vanishes at end of turn.
## "restriction": {...} (only when the Momentum really went up) starts a PlayRestriction on the controller,
## e.g. "only neutral cards this turn", so ramp packages can't cheat out other essences' champions.
## "refresh": true only wins back Momentum already spent this turn: it stops at the Momentum the turn
## started with, so unlike a plain gain it can never push the total above that (Tormenta's gains can).
## "amount_from": "sacrificed_cost" (inside a sacrifice's "then") gains the printed cost of the sacrificed unit, at most `max`.
## "per": "leaked" refunds the Momentum that leaked past the Reserva this turn instead:
## floor(leaked / divisor), at most `max`.
## "per": "returned_allies" gains `amount` Momentum for each allied unit that a "return_to_hand" earlier in the same
## effect run sent back to the hand (Kazeminus), at most `max`.
## "per": "stored" releases all the Momentum this artifact has stored (Bateria de Segunda Mão) and empties it.
## "lock": true (only when the Momentum really went up) stops the controller from gaining plain Momentum
## until the end of this turn; a refresh still works, and so do the next turn's gains.

var amount := 0
var per := ""
var divisor := 1
var maximum := GameState.MOMENTUM_CAP
var next_turn := false
var overflow := false
var refresh := false
var restriction: Dictionary = {}
var amount_from := ""
var lock := false

func _read_parameters(data: Dictionary) -> void:
	lock = bool(data.get("lock", false))
	amount_from = String(data.get("amount_from", ""))
	overflow = bool(data.get("overflow", false))
	refresh = bool(data.get("refresh", false))
	restriction = data.get("restriction", {})
	amount = int(data.get("amount", 0))
	per = String(data.get("per", ""))
	divisor = maxi(1, int(data.get("divisor", 1)))
	maximum = int(data.get("max", GameState.MOMENTUM_CAP))
	next_turn = bool(data.get("next_turn", false))

func apply(context: EffectContext, _target_uid: int) -> void:
	var player: Dictionary = context.game.players[context.controller]
	var gain := amount
	if amount_from == "sacrificed_cost":
		# Momentum equal to the cost of the unit a sacrifice just killed, capped by "max"
		gain = mini(maximum, context.sacrificed_cost)
		if gain <= 0:
			return
	elif per == "leaked":
		gain = mini(maximum, int(player["leaked"]) / divisor)
		if gain <= 0:
			return
	elif per == "returned_allies":
		gain = mini(maximum, amount * context.returned_ally_count)
		if gain <= 0:
			return
	elif per == "stored":
		var artifact: Card = context.game.find_relic(context.self_uid)
		if artifact == null or artifact.stored_momentum <= 0:
			return
		gain = artifact.stored_momentum
		artifact.stored_momentum = 0 # released: whatever the cap refuses is lost too
		context.game._emit({"type": "momentum_stored", "player": artifact.owner, "uid": artifact.uid, "stored": 0})
	if next_turn:
		player["next_momentum"] += gain
	else:
		var momentum_before := int(player["momentum"])
		context.game.gain_momentum(context.controller, gain, overflow, refresh)
		var really_gained: bool = int(player["momentum"]) > momentum_before
		if not restriction.is_empty() and really_gained:
			context.game.add_play_restriction(context.controller, restriction)
		if lock and really_gained:
			player["momentum_lock_turn"] = context.game.turn
