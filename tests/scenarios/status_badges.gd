extends RefCounted
## Playtest dos medalhões de status: quanto espaço eles ocupam com 2, 3 e 4 status ao mesmo tempo.
## Meu campo (da esquerda para a direita): uma unidade com 2 status, uma com 3, uma com 4 (o 4º é o
## pseudo-status "congelar", que nenhuma carta aplica ainda) e uma com 3 + Atordoada (o pior caso real).
## Meu Líder tem 3 status e o Líder inimigo tem 4 (também com o pseudo "congelar").
## Os números têm 1 e 2 dígitos de propósito. Apagar depois do playtest (e o "TEMP congelar" do card_view,
## leader_view e main).

const PLAYER_DECK := "eryon"
const ENEMY_DECK := "fogo"

static func setup(g: GameState) -> void:
	# não é o começo da partida: os dois mantêm a mão (sem mulligan) e o turno é meu
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	var two_statuses := _put(g, 0, "elefante_incomodante")
	two_statuses.dot_markers = {"queimadura": 3, "veneno": 5}
	var three_statuses := _put(g, 0, "elefante_incomodante")
	three_statuses.dot_markers = {"queimadura": 2, "veneno": 12, "sangramento": 4}
	var four_statuses := _put(g, 0, "elefante_incomodante")
	four_statuses.dot_markers = {"queimadura": 7, "veneno": 3, "sangramento": 1, "congelar": 2}
	var three_plus_stun := _put(g, 0, "elefante_incomodante")
	three_plus_stun.dot_markers = {"queimadura": 4, "veneno": 6, "sangramento": 9}
	three_plus_stun.stun_markers = 2
	g.players[0]["leader_dots"] = {"queimadura": 5, "veneno": 8, "sangramento": 2}
	g.players[1]["leader_dots"] = {"queimadura": 5, "veneno": 8, "sangramento": 2, "congelar": 3}
	g._check_state()
	g._flush()

## Põe uma carta direto no campo, resolve as escolhas que a entrada pedir e tira o enjoo de invocação.
static func _put(g: GameState, player: int, card_id: String) -> Card:
	var uid := g._uid()
	g._summon(player, Card.new(uid, card_id, player), false, 0)
	g._flush()
	if g.phase == "search":
		g.choose_search(player, int(g.pending_search["cards"][0]["uid"]))
		g._flush()
	if g.phase == "enter_tapped":
		g.choose_enter_tapped(player, false)
		g._flush()
	g.pending_tap.erase(uid)
	var unit := g.find_unit(uid)
	unit.sick = false
	return unit
