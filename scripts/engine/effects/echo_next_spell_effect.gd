class_name EchoNextSpellEffect
extends Effect
## "echo_next_spell": arms an echo for the controller. The NEXT spell they cast (from hand or graveyard) is cast
## a second time right after it resolves, aimed at the same target(s) as the original (Mali Magarc's Dragão Primordial).
## Rules (see StackSystem._queue_spell_echo):
##  - it stays armed until the controller casts a spell; arming twice does not stack, and it ignores spells cast by units;
##  - the echo is a new item on the stack: the opponent can respond to it, and if a target is no longer valid it fizzles;
##  - the echo is not a cast: it does not fire spell_cast listeners and it never goes to the graveyard (only the original does);
##  - a countered original leaves no echo behind.
## Example, inside the card's "activated" block: "effects": [{"action": "echo_next_spell", "target": "none"}].

func apply(context: EffectContext, _target_uid: int) -> void:
	var game := context.game
	game.players[context.controller]["spell_echo_source"] = context.self_uid if context.self_uid != 0 else -1
	game._emit({"type": "spell_echo_armed", "player": context.controller, "uid": context.self_uid})
