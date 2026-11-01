# Cartas

Cada carta fica em um arquivo JSON próprio, usando o ID do jogo como nome do arquivo, dentro da pasta do seu **set** e do seu **domínio**:
`data/cards/<set>/<domínio>/<id>.json`, por exemplo `set1/furia/kai.json`.

- Sets: identificados só pelo **número**. A pasta é `set<número>/` (`set1/`, `set2/`...) e o nome completo que aparece na UI (ex.: "Nuliterra (2026)") fica em `sets` de `../cards.json`, assim: `"2": {"name": "Nuliterra (2026)"}`. Para criar um set novo: cadastre o número e o nome lá e crie a pasta `set<número>/`.
- Domínios: `furia/`, `fluxo/`, `natureza/`, `montanha/`, `tormenta/`, `trevas/`, `devocao/` e `neutra/`. Pastas vazias não precisam existir.
- O campo `set` da carta é o número do set (ex.: `"set": 2`) e deve bater com a pasta; o campo `essence` deve bater com a pasta do domínio. O carregador acusa erro se não baterem.
- O ID (nome do arquivo) é único no jogo inteiro, mesmo entre sets: duas cartas com o mesmo ID em sets diferentes dão erro. Decks, Líderes e efeitos citam a carta só pelo ID, sem o set.
- Para achar uma carta qualquer: `docs/INDICE_CARTAS.md` (gerado por `tools/generate_card_index.gd`, ver abaixo).

Exemplos:

- `set1/furia/kai.json` — carta do Kai
- `set1/furia/ronan.json` — carta de campeão do Ronan
- `set1/furia/labareda.json` — carta de feitiço Labareda

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
- `identity`: id (nome minúsculo) do Líder que esta carta encarna, quando o nome dela não é o do Líder. Sem o campo, uma Encarnação só é reconhecida pelo nome igual ao do Líder (ou começando com "Líder,"). Com ele, `CardDB.is_incarnation_option` aceita a carta como Encarnação desse Líder. Veja `set2/tormenta/layla_veyr.json` (Encarnação do Líder Layla, enquanto a Layla do set 1 continua uma carta normal).
- `deck_effects`: efeitos que valem enquanto a carta está no deck (`trigger`, `if`, `action`). Hoje só existe `summon_self` (a cópia sai do deck e entra em campo; `cost` opcional = Momentum pago na entrada, como uma habilidade: a Reserva vale e é gasta primeiro) (ver `_fire_deck_effects` em `game_state.gd`).
- `choose_effect`: pausa a resolução e oferece as opções em `options`; cada opção tem `title`, `detail` e uma lista `effects`. Um alvo escolhido na opção é pedido depois da escolha, com até um tipo de alvo por opção. Em gatilhos de combate, `requires_opposed` exige a unidade adversária do evento, e `exclude_opposed` a exclui dos alvos escolhidos. Há testes para Ao Desafiar, Ao Entrar e feitiços. Outras telas de escolha, como busca no deck, não podem estar nas opções ou na mesma lista de efeitos; interações indiretas com essas telas ainda precisam de implementação e testes antes do uso. Veja `set2/furia/nicolas.json`.
- `activated.extra_cost` de tipo `discard_or_sacrifice`: define duas `options` com `title`, `detail`, `reason` e `pick` (`hand_card` ou `other_ally_unit`). Usa a mesma avaliação de opções e a mesma janela de `choose_effect`, mas a escolha é cancelável e o custo é pago antes da habilidade entrar na pilha. Veja `set1/trevas/drex.json`. Outros tipos de custo precisam de implementação própria.

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

Os retratos ficam em `assets/portraits/<domínio>/<id>.webp`, na mesma pasta de domínio da carta (`furia/`, `fluxo/`, `neutra/`…). Por enquanto os retratos não são separados por set (o caminho vem do campo `art`, então dá para espelhar os sets depois sem mexer no motor). O campo `art` da carta guarda o caminho relativo a `assets/portraits/`, por exemplo `"art": "furia/kai.webp"`. Retratos de Líderes ficam na pasta do domínio do Líder.

## Índice de cartas

`docs/INDICE_CARTAS.md` lista todas as cartas (set, domínio, ID, nome, raridade, tipo, custo) agrupadas por set. Para regenerar depois de criar ou renomear cartas:

```
godot --headless --path . -s tools/generate_card_index.gd
```
