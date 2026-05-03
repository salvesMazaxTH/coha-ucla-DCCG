import { cardDB } from "../public/data/cardDB.js";

export function buildValidDeckIds() {
  const picks = [
    ["ronan", 4],
    ["blazeAdept", 4],
    ["voltaScout", 4],
    ["sparkMonk", 4],
    ["tideKeeper", 4],
    ["seaPriest", 4],
    ["frostWitch", 4],
    ["dawnSentinel", 3],
    ["obsidianBanner", 4],
    ["shadowRogue", 4],
    ["galeRider", 2],
    ["skyArcher", 4],
    ["neutralSquire", 3],
  ];

  const out = [];
  for (const [id, count] of picks) {
    if (!cardDB[id]) {
      throw new Error(`Card ${id} missing from cardDB`);
    }
    for (let i = 0; i < count; i += 1) {
      out.push(id);
    }
  }

  if (out.length !== 48) {
    throw new Error(`Expected deck size 48, got ${out.length}`);
  }

  return out;
}
