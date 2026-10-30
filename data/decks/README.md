# Decks

Cada deck é um arquivo JSON próprio. O ID do deck é o nome do arquivo, sem a extensão.

```
data/decks/
  prebuilt/        decks prontos da demo (aparecem no hub de seleção do Online)
    fogo.json                      Ronan
    agua.json                      Naelthos
    eletrica_greedy.json           Voltexz ("Tormenta Voraz", a versão lenta)
    glacial.json                   Nythera ("Nevasca Eterna")
    obscura_lento.json             Jeff ("Cemitério Vivo", a versão lenta)
    rochosa.json, metalica.json, sagrada.json, vegetal.json, venenosa.json, vael.json
    berengar_voss.json, eryon.json, ignisar_controle.json, kazeminus_vento_de_cauda.json,
    mare_consagrada.json, saraya_kovan.json
```

## Seções do hub

Há exatamente um deck pronto por Líder, todos na seção "ESSENCIAIS: DECKS DOS LÍDERES" (o campo opcional `section` do JSON existe, mas só o valor padrão `essencia` é usado pelos prontos; "meus" é dos decks do jogador).

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
- `cards`: `id da carta -> cópias`. Precisa somar **44** cartas **mais 1 Encarnação** do Líder (45 no arquivo), com no máximo **3** cópias, só domínios permitidos pelo Líder.

## Carregamento

`scripts/engine/deck_db.gd` (`DeckDB`) lê a pasta `prebuilt/`, ordena e valida (`DeckDB.validate(id)`). `tests/run_tests.gd` valida todos os decks da pasta.

Para adicionar um deck pronto: crie `prebuilt/<id>.json`. Nada mais precisa mudar (o servidor e o hub leem a lista de `DeckDB.ids()`). Decks de jogadores (deckbuilder) vão numa pasta própria no futuro, por exemplo `data/decks/user/` ou `user://`.
