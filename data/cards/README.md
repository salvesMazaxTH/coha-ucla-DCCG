# Cartas

Cada carta fica em um arquivo JSON próprio, usando o ID do jogo como nome do arquivo.

Exemplos:

- `kai.json` — carta do Kai
- `ronan_lendario.json` — carta lendária do Ronan
- `labareda.json` — carta de feitiço Labareda

Para alterar habilidades, edite o campo `keywords` usando os IDs definidos em `../cards.json`, na seção `keywords`.

Por exemplo:

```json
"keywords": ["golpe_rapido", "impeto"]
```

O arquivo `../cards.json` continua guardando elementos, palavras-chave, líderes e decks. O carregamento das cartas individuais é feito por `scripts/engine/card_db.gd`.

## Tags

`keywords` representam habilidades mecânicas, como `impeto` e `golpe_rapido`.
`tags` representam classificações da carta, como `espirito`, e podem ser usadas em efeitos de busca.

Exemplo:

```json
"tags": ["espirito"]
```
