class_name GameEvent
extends RefCounted
## Something that happened in the game, told to the TriggerBus. Cards react to it either through
## their own trigger ("trigger": "on_attack", only the unit it happened to) or by listening to it
## from anywhere ("listen": "leader_damaged", see Effect and TriggerBus).

## Events a card can listen to with "listen" (the unit triggers of cards.json work too).
const LISTENABLE := ["leader_damaged", "leader_healed", "card_moved", "unit_entered", "unit_damaged", "unit_healed", "card_drawn", "turn_started", "turn_ended", "spell_cast", "snowball_cast", "snowball_grande", "unit_readied", "unit_targeted", "unit_attacked", "combat_damage_dealt"]

var trigger := "" ## the event name: "on_attack", "leader_damaged", "card_moved"...
var player := -1 ## whose leader / card / unit it happened to
var source: Card = null ## the card it happened to or that caused it (null when there is none)
var other_uid := 0 ## the opposing unit in combat triggers (blocker, attacker, damage source)
var amount := 0 ## damage or healing done
var hp_before := 0 ## life before / after, for leader_damaged, leader_healed, unit_damaged and unit_healed
var hp_after := 0
var data: Dictionary = {} ## extra facts a "when" filter can test, e.g. card_moved: {"from": "hand", "to": "graveyard"}

func _init(event_trigger: String, event_player: int = -1, event_source: Card = null) -> void:
	trigger = event_trigger
	player = event_player
	source = event_source
