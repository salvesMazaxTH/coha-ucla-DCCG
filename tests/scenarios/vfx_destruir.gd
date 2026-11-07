extends RefCounted
## Playtest das animações de destruir/banir uma unidade (alvo único).
## 99 de Momentum; o oponente tem o campo cheio (8 unidades) com 30 de Vida e 4 de Veneno cada.
## A mão, da esquerda para a direita:
##   1. Ponto Final sem Vírgula (veneno, bane)   2. Desabamento Oportuno (pedra)
##   3. Capina Seletiva (vegetal, bane)          4. Reduzir a Cinzas (fogo)
##   5. Afogar (água)
## Apagar depois do playtest.

const PLAYER_DECK := "sagrada"
const ENEMY_DECK := "fogo"

const HAND := [
	"ponto_final_sem_virgula",
	"desabamento_oportuno",
	"capina_seletiva",
	"reduzir_a_cinzas",
	"afogar",
]

## Quantas unidades o oponente tem em campo (o campo cheio é GameState.BOARD_LIMIT = 8).
const ENEMY_UNIT_COUNT := 8
## Vida extra de cada unidade inimiga, para aguentar todos os feitiços de dano.
const ENEMY_EXTRA_HP := 26
## Marcadores de Veneno em cada unidade inimiga (a Ponto Final só bane quem tem 3 ou mais).
const ENEMY_POISON_MARKERS := 4

static func setup(g: GameState) -> void:
	# não é o começo da partida: os dois mantêm a mão (sem mulligan) e o turno é meu
	g.first = 0
	g.mulligan(0, [])
	g.mulligan(1, [])
	# a mão só com os feitiços do teste (substitui a mão sorteada)
	g.players[0]["hand"].clear()
	for card_id: String in HAND:
		g.players[0]["hand"].append(Card.new(g._uid(), card_id, 0, "hand"))
	# o campo inimigo cheio de unidades parrudas
	for i in ENEMY_UNIT_COUNT:
		var unit := _put(g, 1, "tromba_de_aluguel")
		_buff(unit, "remendeira_de_esquina", {"hp": ENEMY_EXTRA_HP})
		# já envenenadas, para a Ponto Final sem Vírgula poder mirar em qualquer uma
		unit.dot_markers["veneno"] = ENEMY_POISON_MARKERS
	# Momentum de sobra para jogar a mão inteira neste turno
	g.players[0]["max_momentum"] = 10
	g.players[0]["momentum"] = 99
	g._flush()

## Buff permanente, registrado com a carta de origem como um efeito de verdade faria.
static func _buff(unit: Card, source: String, changes: Dictionary) -> void:
	unit.atk += int(changes.get("atk", 0))
	unit.hp += int(changes.get("hp", 0))
	unit.record_stat_change(source, "", changes)

## Põe uma carta direto no campo, resolve as escolhas que a entrada pedir e tira o enjoo de invocação.
static func _put(g: GameState, player: int, card_id: String) -> Card:
	var uid := g._uid()
	g._summon(player, Card.new(uid, card_id, player), false, 0)
	g._flush()
	if g.phase == "search":
		g.choose_search(player, 0) # recusa a busca
		g._flush()
	if g.phase == "enter_tapped":
		g.choose_enter_tapped(player, false)
		g._flush()
	g.pending_tap.erase(uid)
	var unit := g.find_unit(uid)
	unit.sick = false
	return unit
