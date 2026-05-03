// shared/effects/status/Burn.js
export const BurnEffect = {
  id: 'burn',
  name: 'Queimando',
  hooks: {
    onTurnStart({ self, context }) {
      const damage = 2; // Dano fixo de burn
      self.takeDamage(damage, context);
      console.log(`${self.name} sofreu ${damage} de dano por Queimadura.`);
    }
  }
};

// shared/effects/status/Poison.js
export const PoisonEffect = {
  id: 'poison',
  name: 'Veneno',
  hooks: {
    onTurnStart({ self, context }) {
      // Veneno que escala ou causa dano no fim do turno
      self.takeDamage(1, context);
    }
  }
};