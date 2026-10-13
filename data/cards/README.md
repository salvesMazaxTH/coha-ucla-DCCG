# Cartas

Cada carta fica em um arquivo JSON próprio, usando o ID do jogo como nome do arquivo, dentro da pasta da sua **essência**:
`ignea/`, `aquatica/`, `glacial/`, `vegetal/`, `rochosa/`, `metalica/`, `eletrica/`, `obscura/`, `sagrada/` e `neutra/`.
O campo `essence` da carta deve bater com a pasta. Pastas de essências sem cartas ainda não precisam existir.

Exemplos:

- `ignea/kai.json` — carta do Kai
- `ignea/ronan.json` — carta de campeão do Ronan
- `ignea/labareda.json` — carta de feitiço Labareda

Para alterar habilidades, edite o campo `keywords` usando os IDs definidos em `../cards.json`, na seção `keywords`.

Por exemplo:

```json
"keywords": ["voo", "impeto"]
```

O arquivo `../cards.json` continua guardando elementos, palavras-chave, espécies e líderes. Os decks prontos ficam em `../decks/` (ver o README de lá). O carregamento das cartas individuais é feito por `scripts/engine/card_db.gd`.

## Campos opcionais

- `max_copies`: máximo de cópias no deck (padrão 3; 2 para cartas Lendárias). `1` = **Única**; escreva "Única." na primeira linha do `text`.
- `armor`: Armadura impressa da unidade (N). Todo dano que ela receberia cai em N; os valores somam quando um efeito dá mais (`armor` fixo ou `armor_temp` até o início do próximo turno do dono, no `buff`). Dano zerado pela Armadura não gasta o Escudo.
- `adjacent_armor`: enquanto a unidade estiver no campo, as unidades aliadas ao lado dela (posição anterior e seguinte no campo, que segue a ordem em que foram jogadas) ganham N de Armadura.
- `token`: `true` = ficha (só existe invocada por `summon`, nunca em deck). Ao morrer ou ser banida some do jogo: não vai ao cemitério nem aos banidos, mas ainda dispara Aliado Morre. Não conta nas cartas únicas da essência.
- `deck_effects`: efeitos que valem enquanto a carta está no deck (`trigger`, `if`, `action`). Hoje só existe `summon_self` (a cópia sai do deck e entra em campo; `cost` opcional = Momentum pago na entrada, como uma habilidade: a Reserva vale e é gasta primeiro) (ver `_fire_deck_effects` em `game_state.gd`).

## Tags

`keywords` representam habilidades mecânicas, como `impeto` e `voo`.
`tags` representam classificações da carta, como `espirito`, e podem ser usadas em efeitos de busca.

Exemplo:

```json
"tags": ["espirito"]
```

## Flavor text

`flavor` é uma string ou uma lista de até 3 strings. Com lista, a primeira é a frase principal (fora de partida) e, durante a partida, cada carta mostra uma frase fixa sorteada no início dela. O sorteio é só visual e usa RNG próprio (`CardDB.flavor_for`).

```json
"flavor": ["Frase principal.", "Segunda frase.", "Terceira frase."]
```

## Retratos

Os retratos ficam em `assets/portraits/<essência>/<id>.webp`, na mesma pasta de essência da carta (`ignea/`, `aquatica/`, `neutra/`…). O campo `art` da carta guarda o caminho relativo a `assets/portraits/`, por exemplo `"art": "ignea/kai.webp"`. Retratos de Líderes ficam na pasta da essência do Líder.
