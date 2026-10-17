class_name DecoyEffect
extends Effect
## "decoy": {"card": <token id>}, with target "self". Summons the token on the controller's side and makes
## it take a blow in place of its summoner, depending on the trigger:
##   on_challenged: the attacker's blow hits the token instead of the challenged unit (Hikari defending);
##   on_challenge:  the defender's counter-blow hits the token instead of the attacker (Hikari attacking).
##     Only when there is a counter-blow to avoid: if the attacker kills first (more Rapidez) or the
##     defender deals no damage, nothing is summoned, so the board isn't filled for nothing.
## Does nothing when the board is full (then the summoner takes the blow as usual).

var card_id := ""

func _read_parameters(data: Dictionary) -> void:
	card_id = String(data.get("card", ""))

func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var summoner := game.find_unit(target_uid)
	if card_id == "" or summoner == null or not game.has_free_slot(context.controller):
		return
	if trigger == "on_challenge":
		var defender := game.find_unit(context.other_uid)
		if defender == null or not game.combat_system().defender_will_counter(summoner, defender):
			return
	var decoy := Card.new(game._uid(), card_id, context.controller)
	game._summon(context.controller, decoy, false, 0)
	match trigger:
		"on_challenged":
			game.combat_system().redirect_hit_to = decoy.uid
		"on_challenge":
			game.combat_system().redirect_counter_to = decoy.uid
