# Cartas

Cada carta fica em um arquivo JSON próprio, usando o ID do jogo como nome do arquivo, dentro da pasta do seu **domínio**:
`furia/`, `fluxo/`, `natureza/`, `montanha/`, `tormenta/`, `trevas/`, `devocao/` e `neutra/`.
O campo `essence` da carta deve bater com a pasta. Pastas de domínios sem cartas ainda não precisam existir.

Exemplos:

- `furia/kai.json` — carta do Kai
- `furia/ronan.json` — carta de campeão do Ronan
- `furia/labareda.json` — carta de feitiço Labareda

Para alterar habilidades, edite o campo `keywords` usando os IDs definidos em `../cards.json`, na seção `keywords`.

Por exemplo:

```json
"keywords": ["voo", "impeto"]
```

O arquivo `../cards.json` continua guardando elementos, palavras-chave, espécies e líderes. Os decks prontos ficam em `../decks/` (ver o README de lá). O carregamento das cartas individuais é feito por `scripts/engine/card_db.gd`.

## Campos opcionais

- `max_copies`: máximo de cópias no deck (padrão 3; 2 para cartas Lendárias). `1` = **Única**; escreva "Única." na primeira linha do `text`.
- `armor`: Armadura impressa da unidade (N). Todo dano que ela receberia cai em N, mas nunca abaixo de 1; os valores somam quando um efeito dá mais (`armor` fixo ou `armor_temp` até o início do próximo turno do dono, no `buff`).
- `adjacent_armor`: enquanto a unidade estiver no campo, as unidades aliadas ao lado dela (posição anterior e seguinte no campo, que segue a ordem em que foram jogadas) ganham N de Armadura. É um Constante (o texto da carta começa com "Constante:") e o Contador Exagerado dobra o valor.
- `token`: `true` = ficha (só existe invocada por `summon`, nunca em deck). Ao morrer ou ser banida some do jogo: não vai ao cemitério nem aos banidos, mas ainda dispara Aliado Morre. Se fosse voltar para a mão, também é apagada do jogo. Não conta nas cartas únicas da essência.
- `inert`: `true` = compatibilidade para unidades Inertes antigas: nunca atacam, não podem desafiar e não podem ser viradas (nem por efeito). Prefira incluir a keyword `inerte` em `keywords` para que ela também apareça como badge e possa ser concedida por efeitos.
- `species_display`: rótulo alternativo na tarja de espécie. É apenas visual: não altera as espécies mecânicas em `species`. Cartas que usam esse campo recebem um estilo próprio na tarja.
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

Os retratos ficam em `assets/portraits/<domínio>/<id>.webp`, na mesma pasta de domínio da carta (`furia/`, `fluxo/`, `neutra/`…). O campo `art` da carta guarda o caminho relativo a `assets/portraits/`, por exemplo `"art": "furia/kai.webp"`. Retratos de Líderes ficam na pasta do domínio do Líder.
