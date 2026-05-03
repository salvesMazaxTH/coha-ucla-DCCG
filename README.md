# Arena dos Campeões - UCLA RPG Card Game

Um jogo de cartas multiplayer em tempo real com engine de combate e sistema de efeitos.

## 🎮 Estrutura do Projeto

```
engine/
  ├── CombatEngine.js      # Motor de combate
  └── CombatResolver.js    # Resolutor de dano e morte

server/
  ├── core/
  │   ├── DeckValidator.js  # Validação de decks
  │   └── GameInstance.js   # Instância de jogo
  └── network/
      └── SocketHandler.js  # Comunicação em tempo real

shared/
  ├── core/
  │   ├── ActionStack.js    # Pilha de ações
  │   ├── Creature.js       # Entidade criatura
  │   ├── Entity.js         # Entidade base
  │   ├── GameState.js      # Estado do jogo
  │   └── Player.js         # Jogador
  ├── effects/
  │   ├── EffectBus.js      # Bus de eventos
  │   ├── Keywords.js       # Sistema de palavras-chave
  │   ├── StatusRegistry.js # Registro de status
  │   ├── keywords/         # Palavras-chave específicas
  │   └── status/           # Efeitos de status
  └── utils/
      └── DeckCoder.js      # Codificar/decodificar decks

public/
  ├── js/
  │   └── index.js          # Frontend logic (em desenvolvimento)
  └── ... (assets estáticos)

index.html  # Frontend HTML com Tailwind CSS
```

## 📋 Requisitos Instalados

- **Tailwind CSS** (via CDN)
- **Google Fonts** - Montserrat
- **Boxicons** - Ícones SVG
- **Socket.io Client** - Comunicação em tempo real
- **Eruda** - Debugger de console

## 🚀 Começar

### Instalação de Dependências

```bash
npm install
```

### Rodar o Servidor

```bash
npm start
```

Ou em modo desenvolvimento com reload automático:

```bash
npm run dev
```

O servidor será executado em `http://localhost:3000` (configure conforme necessário em `server/index.js`)

## 🎨 Frontend

### Estrutura HTML

O arquivo `index.html` contém:

- **Header**: Controles de turno, desfazer, render-se
- **Game Board**: Área de combate (oponente vs jogador)
- **Player Hand**: Mão de cartas com efeito de perspectiva
- **Heroes**: Avatares do jogador e oponente com HP display

### Tailwind CSS

Toda a estilização usa **Tailwind CSS** com cores personalizadas:

- Cores escuras para imersão: `#0a0e27`, `#050812`
- Neon verde para destaque: `#00ff41`
- Gradientes e efeitos de brilho

### Componentes Visuais

#### 🎴 Card Placeholder

- Efeito shimmer animado
- Stats de ataque e HP
- Hover lift effect

#### 🏆 Hero Portrait

- Avatar arredondado
- Display de HP em círculo
- Border neon verde

#### 🎯 Turn Display Pill

- Background verde escuro semi-transparente
- Border neon com glow
- Estilo "pill" arredondado

#### 🔴 End Turn Button

- Gradiente vermelho
- Hover scale up
- Disabled gray state

#### ⚒️ Undo Button

- Estilo metallic cinza
- Inset glow efeito
- Hover lift effect
- Disabled opacity

#### 🏳️ Surrender Button

- Minimalista low-opacity
- Hover red color
- Subtle UI element

## 🛠️ Scripts Inclusos

```html
<script src="/socket.io/socket.io.js"></script>
<script type="module" src="/js/index.js"></script>
<script src="https://cdn.jsdelivr.net/npm/eruda"></script>
```

## 📝 Próximos Passos

1. [ ] Implementar Socket.io server setup
2. [ ] Conectar frontend ao backend via Socket.io
3. [ ] Implementar lógica de turno
4. [ ] Drag & drop para cartas
5. [ ] Sistema de animações de combate
6. [ ] Persistência de estado do jogo
7. [ ] Integração com CombatEngine

## 🎯 Requisitos Atendidos

✅ Tailwind CSS configurado (via CDN + config customizado)
✅ Google Fonts Montserrat
✅ Boxicons inclusos
✅ Socket.io client pronto
✅ Eruda debugger ativado
✅ HTML estruturado com áreas de jogo
✅ Sem lógica JavaScript implementada (apenas placeholders)
✅ Design moderno tipo Hearthstone/Legends of Runeterra
✅ Estilos visuais com Tailwind
✅ Hero portraits com HP display
✅ Player hand com efeito de perspectiva
✅ Board divider com neon glow
✅ Buttons com estilos específicos

## 📦 Dependências

```json
{
  "dependencies": {
    "express": "^4.18.2",
    "socket.io": "^4.7.2"
  },
  "devDependencies": {
    "tailwindcss": "^3.3.6"
  }
}
```

## 👨‍💻 Autor

Thiago

## 📄 License

MIT
