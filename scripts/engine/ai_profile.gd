class_name AIProfile
extends RefCounted
## How a deck's AI weighs trading against hitting the face. A deck picks one with "ai_profile" in its JSON.
##   trade_min_gain: value a trade must gain to be taken (1 = even trades too)
##   rush_turns: all-in at the face when the enemy Leader dies within this many swings
##   hold_turns: burn is kept for the face when the enemy Leader dies within this many swings (0 = burn is removal)
##   face_point_value(_late): value of 1 face damage against the unit it may cost
##   store_duplicate_first: when storing in the Reservatório, a card with another copy in hand goes first (else the dearest)

const DEFAULT := "midrange"
const PROFILES := {
	"aggro": {"trade_min_gain": 5, "rush_turns": 3, "hold_turns": 3, "face_point_value": 3, "face_point_value_late": 4, "store_duplicate_first": false},
	"midrange": {"trade_min_gain": 3, "rush_turns": 2, "hold_turns": 2, "face_point_value": 2, "face_point_value_late": 3, "store_duplicate_first": false},
	"control": {"trade_min_gain": 1, "rush_turns": 1, "hold_turns": 0, "face_point_value": 1, "face_point_value_late": 2, "store_duplicate_first": true},
}


static func of_player(g: GameState, p: int) -> Dictionary:
	var deck_id := String(g.players[p].get("deck_id", ""))
	var profile_name := String(g.players[p].get("ai_profile_override", DEFAULT)) # set by sims only
	if not g.players[p].has("ai_profile_override") and DeckDB.has(deck_id):
		profile_name = String(DeckDB.get_deck(deck_id).get("ai_profile", DEFAULT))
	return PROFILES.get(profile_name, PROFILES[DEFAULT])
