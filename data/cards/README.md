# Cartas

Cada carta fica em um arquivo JSON próprio, usando o ID do jogo como nome do arquivo, dentro da pasta da sua **essência**:
`ignea/`, `aquatica/`, `glacial/`, `vegetal/`, `rochosa/`, `metalica/`, `eletrica/`, `obscura/`, `sagrada/` e `neutra/`.
O campo `essence` da carta deve bater com a pasta. Pastas de essências sem cartas ainda não precisam existir.

Exemplos:

- `ignea/kai.json` — carta do Kai
- `ignea/ronan_lendario.json` — carta lendária do Ronan
- `ignea/labareda.json` — carta de feitiço Labareda

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

## Retratos

Os retratos ficam em `assets/portraits/<essência>/<id>.webp`, na mesma pasta de essência da carta (`ignea/`, `aquatica/`, `neutra/`…). O campo `art` da carta guarda o caminho relativo a `assets/portraits/`, por exemplo `"art": "ignea/kai.webp"`. Retratos de Líderes ficam na pasta da essência do Líder.
