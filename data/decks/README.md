# Decks

Cada deck é um arquivo JSON próprio. O ID do deck é o nome do arquivo, sem a extensão.

```
data/decks/
  prebuilt/        decks prontos da demo (aparecem no hub de seleção do Online)
    fogo.json
    agua.json
    obscura.json   ("Ceifa de Jeff", mono-Obscura)
    eletrica.json  ("Slow Midrange", mono-Elétrica)
    glacial.json   ("Nevasca de Nythera", Glacial, combo da Bola de Neve)
    vael.json      ("Lâmina de Vael", Líder neutro, aggro de Crítico com convidados de outras essências)
    metalica.json  ("Montanha de Ferro de Morakhan", Metálica, compra e filtro com artefatos e peças, trituração do deck do oponente que vira Fadiga)
```

## Formato

```json
{
  "name": "Fúria de Ronan",
  "description": "Frase curta de estilo de jogo, mostrada no hub.",
  "order": 1,
  "leader": "ronan",
  "cards": { "ronan": 1, "kai": 3 }
}
```

- `name`, `description`: texto exibido na tela de seleção.
- `order`: posição no grid (menor primeiro; desempate pelo ID).
- `leader`: ID em `leaders` do `../cards.json`.
- `cards`: `id da carta -> cópias`. Precisa somar **44** cartas **mais 1 Encarnação** do Líder (45 no arquivo), com no máximo **3** cópias, só essências permitidas pelo Líder.

## Carregamento

`scripts/engine/deck_db.gd` (`DeckDB`) lê a pasta `prebuilt/`, ordena e valida (`DeckDB.validate(id)`). `tests/run_tests.gd` valida todos os decks da pasta.

Para adicionar um deck pronto: crie `prebuilt/<id>.json`. Nada mais precisa mudar (o servidor e o hub leem a lista de `DeckDB.ids()`). Decks de jogadores (deckbuilder) vão numa pasta própria no futuro, por exemplo `data/decks/user/` ou `user://`.
