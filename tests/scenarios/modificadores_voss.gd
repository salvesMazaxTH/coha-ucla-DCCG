extends RefCounted
## Playtest visual do painel de modificadores com o deck do Berengar Voss. Apagar depois do playtest.
## Campo cheio de aliados com artefatos e um Contador Exagerado (dobra os Constantes de texto).
## Clique em cada unidade para abrir o overlay:
##   Berengar Voss: +1/+1 por artefato, dobrado pelo Contador Exagerado.
##   Sacoleiro Tobias: três equipamentos ao mesmo tempo (Coração, Placa Espelhada, Cristal do Poder).
##   Matusalém: dois equipamentos (Manto da Ladainha e Coração da Montanha).
##   Montadora Porca-Frouxa: um Cristal do Poder equipado.
##   Relojoeiro Pino-14 e Contador Exagerado: sem equipamento (contam para o Voss).
## Na zona de artefatos: dois Cristais do Poder soltos.

const PLAYER_DECK := "berengar_voss"
const ENEMY_DECK := "fogo"

static func setup(g: GameState) -> void:
	_put(g, 0, "contador_exagerado")
	_put(g, 0, "berengar_voss")
	_put(g, 0, "relojoeiro_pino_14")

	var bag_carrier := _put(g, 0, "sacoleiro_tobias_bolso_fundo")
	_equip(g, bag_carrier, "coracao_da_montanha", {"atk": 2, "hp": 4})
	_equip(g, bag_carrier, "placa_espelhada_de_adamantina", {"atk": 1, "hp": 3, "keywords": ["reflexao"]})
	_equip(g, bag_carrier, "cristal_do_poder", {"atk": 2})

	var tortoise := _put(g, 0, "matusalem_tartaruga_relicario")
	_equip(g, tortoise, "manto_da_ladainha", {"armor": 1, "keywords": ["roubo_de_vida"]})
	_equip(g, tortoise, "coracao_da_montanha", {"atk": 2, "hp": 4})

	var assembler := _put(g, 0, "montadora_porca_frouxa")
	_equip(g, assembler, "cristal_do_poder", {"atk": 2})

	# artefatos soltos em campo (também contam para o Voss)
	for loose_artifact_id in ["cristal_do_poder", "cristal_do_poder"]:
		var loose_artifact := Card.new(g._uid(), loose_artifact_id, 0, "hand")
		g.players[0]["relics"].append(loose_artifact)
		g._move(loose_artifact, "relics")

	g.players[0]["momentum"] = 10
	g._refresh_scaling() # recalcula o Voss agora, com todos os artefatos já em jogo
	g._flush()

## Equipa um artefato direto na unidade, aplicando o bônus que ele concede.
static func _equip(g: GameState, holder: Card, artifact_id: String, granted: Dictionary) -> void:
	var artifact := Card.new(g._uid(), artifact_id, 0, "hand")
	var actually_granted := g.stack_system().apply_equipment_bonus(holder, granted)
	g.stack_system().attach(holder, artifact, actually_granted)

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
