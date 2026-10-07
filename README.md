# CSA — Card Game (alpha 0.2)

Card game PvP com os campeões do Champion Showdown Arena, feito em **Godot 4.7**.

- **Jogar:** abra o `project.godot` no Godot e aperte F5. No menu dá para escolher partida contra a IA ou hot-seat.
- **Regras:** [docs/REGRAS_v0.2.md](docs/REGRAS_v0.2.md)
- **Cartas:** [data/cards/](data/cards/). **Líderes, essências e keywords:** [data/cards.json](data/cards.json). **Decks prontos:** [data/decks/](data/decks/)
- **Testes:** `godot --headless --path . -s tests/run_tests.gd`. Validam os decks, testam o combate e rodam 40 partidas de IA contra IA.

## Estrutura
- `scripts/engine/`: motor de regras puro, sem UI (`game_state.gd`), catálogo de cartas (`card_db.gd`) e IA (`ai.gd`).
- `scripts/ui/`: mesa (`main.gd`) e carta desenhada em código (`card_view.gd`).
- `assets/`: retratos e ícones.
