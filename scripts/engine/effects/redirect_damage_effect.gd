class_name RedirectDamageEffect
extends Effect
## "redirect_next_damage" (Helena): the target (an allied unit or the caster's own Leader) has the NEXT damage it would
## suffer this turn dealt to the unit that used the ability instead. The redirect is consumed by that hit and lapses
## at the end of the turn, or at once if the protector has left the board (see GameState._take_damage_redirect).
## Periodic damage (Veneno, Sangramento...) and Fadiga are never redirected.


func apply(context: EffectContext, target_uid: int) -> void:
	var game := context.game
	var protector := game.find_unit(context.self_uid)
	if protector == null or target_uid == context.self_uid or target_uid == 0:
		return
	game.damage_redirects.append({ "protected": target_uid, "to": protector.uid, "turn": game.turn })
	game.emit_event({ "type": "damage_redirect_armed", "uid": target_uid, "to": protector.uid })
