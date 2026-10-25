class_name SummonFromEffect
extends Effect
## "summon_from": a unit card comes out of a zone of the controller (deck, hand or graveyard) and enters the
## board for free. One generic action for every "cheat-summon" card; the zone and the rules are parameters:
##   source            "deck" (default) | "hand" | "graveyard"
##   <card filter>     any CardFilter key (essence, element, max_cost, species_any, tags_any, rarity...);
##                     only unit cards can be summoned, whatever the filter says
##   pick              "choose" (default): the controller picks one of the matching cards, or none (it is optional)
##                     "random": a random matching card enters, no choice
##   top               deck only: only the N cards on top of the deck are looked at
##   reveal_until      deck only: look from the top until the FIRST matching card shows up, and stop there.
##                     The controller sees every card looked at, topmost first (the unfit ones dimmed, only the found one
##                     can be picked); the opponent sees nothing. With no match nothing is shown, so nothing is moved.
##   leftover          deck only, what happens to the cards looked at but not summoned:
##                     "bottom" (default): go to the bottom of the deck in random order | "graveyard"
##   banish_at_turn_end  true: the summoned unit is banished when the turn ends
## With neither "top" nor "reveal_until" the whole deck is looked through and then shuffled: only for very
## narrow filters, a broad filter over the whole deck is too strong.

func opens_choice() -> bool:
	return String(raw.get("pick", "choose")) == "choose"

func open_choice(context: EffectContext) -> void:
	context.game._begin_summon_from(context.controller, raw, context.self_uid)

func apply(context: EffectContext, _target_uid: int) -> void:
	if String(raw.get("pick", "choose")) == "random":
		context.game.summon_from_random(context.controller, raw, context.self_uid)
