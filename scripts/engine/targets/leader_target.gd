class_name LeaderTarget
extends TargetSelector
## Leaders (negative uids): enemy_leader, own_leader, both_leaders (own first).

const NAMES := ["enemy_leader", "own_leader", "both_leaders"]

func resolve(context: EffectContext, _effect: Effect) -> Array:
	var own_leader: int = GameState.LEADER_UID[context.controller]
	var enemy_leader: int = GameState.LEADER_UID[context.opponent()]
	match name:
		"enemy_leader": return [enemy_leader]
		"own_leader": return [own_leader]
		"both_leaders": return [own_leader, enemy_leader]
	return []
