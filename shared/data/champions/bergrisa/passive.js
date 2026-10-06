import { formatChampionName } from "../../../ui/formatters.js";
import { HealEvent } from "../../../engine/combat/HealEvent.js";
import { roundToFive } from "../../../core/championCombat.js";
import { deriveContext } from "../../../engine/combat/deriveContext.js";

export default {
  key: "strata",
  name: "Strata",
  maxSediment: 20,
  sedimentPerTurn: 4,
  healPerSediment: 8,
  sedimentPerHeal: 2,
  defensePerSediment: 2.5,
  maxDefenseGain: 50,
  baseSubtraction: 10,
  subtractionPerSediment: 0.75,
  subtractionCapRatio: 0.5,
  gapRatio: 0.5,
  maxGapBonus: 45,
  incomingDamageBonus: 65,

  description() {
    return {
      en: `Bergrisa does not move so much as accumulate. Every turn another layer of the world settles into her, <b>${this.sedimentPerTurn}</b> <b>Sediment</b> at a time up to <b>${this.maxSediment}</b>, each one granting <b>${this.defensePerSediment}</b> <b>Defense</b> up to <b>${this.maxDefenseGain}</b>. At the start of her turns, if she is wounded, she burns up to <b>${this.sedimentPerHeal}</b> <b>Sediment</b> to restore <b>${this.healPerSediment}</b> HP each. But all that weight lands somewhere: every standard hit against her lands <b>${this.incomingDamageBonus}%</b> harder before it's blunted. Every blow that reaches her is then blunted by <b>${this.baseSubtraction}</b> plus <b>${this.subtractionPerSediment}</b> per <b>Sediment</b>, never past half the blow, and never <b>Absolute Damage</b>, damage over time or piercing hits. Everything she deals carries bonus damage equal to <b>${this.gapRatio * 100}%</b> of however much her <b>Defense</b> exceeds the chosen target's, up to <b>${this.maxGapBonus}</b>.`,
      pt: `Bergrisa não se move tanto quanto acumula. A cada turno outra camada do mundo se assenta sobre ela, <b>${this.sedimentPerTurn}</b> de <b>Sedimento</b> por vez até <b>${this.maxSediment}</b>, cada um concedendo <b>${this.defensePerSediment}</b> de <b>Defesa</b> até <b>${this.maxDefenseGain}</b>. No início de seus turnos, se estiver ferida, ela queima até <b>${this.sedimentPerHeal}</b> de <b>Sedimento</b> para restaurar <b>${this.healPerSediment}</b> de HP cada. Mas todo esse peso cobra seu preço: cada golpe padrão contra ela chega <b>${this.incomingDamageBonus}%</b> mais forte antes de ser amortecido. Todo golpe que a atinge é então amortecido em <b>${this.baseSubtraction}</b> mais <b>${this.subtractionPerSediment}</b> por <b>Sedimento</b>, nunca além de metade do golpe, e nunca <b>Dano Absoluto</b>, dano ao longo do tempo ou acertos perfurantes. Tudo o que ela causa carrega dano bônus igual a <b>${this.gapRatio * 100}%</b> de quanto sua <b>Defesa</b> excede a do alvo escolhido, até <b>${this.maxGapBonus}</b>.`,
    };
  },

  hookScope: {
    onBeforeDmgDealing: "attacker",
    onBeforeDmgTaking: "defender",
  },

  subtractionFor(owner) {
    const sediment = owner.runtime?.bergrisaSediment || 0;
    return Math.round(
      this.baseSubtraction + this.subtractionPerSediment * sediment,
    );
  },

  blunt(damage, subtraction) {
    return Math.max(
      damage - subtraction,
      Math.round(damage * (1 - this.subtractionCapRatio)),
    );
  },

  // Returns the blunted damage, or undefined for hits Strata never touches.
  bluntHit({ damage, mode, piercingPercentage }, subtraction) {
    if (!(damage > 0)) return;
    if (mode === "piercing" || (piercingPercentage || 0) > 0) return;

    return this.blunt(damage, subtraction);
  },

  setSediment(owner, value, context) {
    owner.runtime ??= {};
    owner.runtime.bergrisaSediment = Math.max(
      0,
      Math.min(this.maxSediment, value),
    );

    const target = Math.min(
      this.maxDefenseGain,
      roundToFive(this.defensePerSediment * owner.runtime.bergrisaSediment),
    );
    const held = (owner.runtime.bergrisaDefenseModifiers ?? []).filter((mod) =>
      owner.statModifiers.includes(mod),
    );
    const granted = held.reduce((sum, mod) => sum + mod.amount, 0);
    if (target === granted) return;

    // Rising Defense adds only the gap; shedding Sediment rebuilds silently.
    const from = owner.statModifiers.length;
    if (target > granted) {
      owner.buffStat({
        statName: "Defense",
        amount: target - granted,
        isPermanent: true,
        context,
      });
      owner.runtime.bergrisaDefenseModifiers = [
        ...held,
        ...owner.statModifiers.slice(from),
      ];
      return;
    }

    owner.removeStatModifiers(held);
    const rebuildFrom = owner.statModifiers.length;
    if (target > 0) {
      owner.buffStat({
        statName: "Defense",
        amount: target,
        isPermanent: true,
        context: deriveContext(context, { registerBuff: null }),
      });
    }
    owner.runtime.bergrisaDefenseModifiers =
      owner.statModifiers.slice(rebuildFrom);
  },

  onBeforeDmgDealing({ attacker, defender, skill }) {
    if (!defender) return;

    const ratio = skill?.defenseGapRatio ?? this.gapRatio;
    const reference = skill?.gapReference ?? defender;
    const gap = (attacker.Defense || 0) - (reference.Defense || 0);
    if (gap <= 0 || ratio <= 0) return;

    const cap = skill?.maxGapBonus ?? this.maxGapBonus;

    return { bonusDamage: Math.min(cap, Math.round(gap * ratio)) };
  },

  onBeforeDmgTaking(payload) {
    const inflated =
      payload.mode === "standard"
        ? {
            ...payload,
            damage: payload.damage * (1 + this.incomingDamageBonus / 100),
          }
        : payload;

    const damage = this.bluntHit(
      inflated,
      this.subtractionFor(payload.owner),
    );
    if (damage === undefined) return;

    return { damage };
  },

  onTurnStart({ owner, context }) {
    if (!owner.alive) return;

    const missing = (owner.maxHP || 0) - (owner.HP || 0);
    if (missing <= 0) return;

    const spent = Math.min(
      this.sedimentPerHeal,
      owner.runtime?.bergrisaSediment || 0,
      Math.ceil(missing / this.healPerSediment),
    );
    if (spent <= 0) return;

    const healed = new HealEvent({
      target: owner,
      amount: spent * this.healPerSediment,
      context,
    }).execute();

    this.setSediment(
      owner,
      (owner.runtime.bergrisaSediment || 0) - spent,
      context,
    );

    return {
      log: {
        en: `<b>[Passive — ${this.name}]</b> ${formatChampionName(owner)} burned ${spent} Sediment and restored ${healed} HP.`,
        pt: `<b>[Passiva — ${this.name}]</b> ${formatChampionName(owner)} queimou ${spent} de Sedimento e recuperou ${healed} de HP.`,
      },
    };
  },

  onTurnEnd({ owner, context }) {
    if (!owner.alive) return;

    this.setSediment(
      owner,
      (owner.runtime?.bergrisaSediment || 0) + this.sedimentPerTurn,
      context,
    );
  },
};
