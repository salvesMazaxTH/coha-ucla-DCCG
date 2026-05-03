/**
 * DeckCoder.js
 * Transforma uma lista de IDs de cartas em uma string compacta e vice-versa.
 */
export class DeckCoder {
  static toBase64(input) {
    if (typeof btoa === "function") {
      return btoa(input);
    }
    return Buffer.from(input, "utf-8").toString("base64");
  }

  static fromBase64(input) {
    if (typeof atob === "function") {
      return atob(input);
    }
    return Buffer.from(input, "base64").toString("utf-8");
  }

  static encode(deckArray) {
    // Agrupa cartas: { id: count }
    const counts = deckArray.reduce((acc, id) => {
      acc[id] = (acc[id] || 0) + 1;
      return acc;
    }, {});

    // Formato: "id:count,id:count"
    const stringMap = Object.entries(counts)
      .map(([id, count]) => `${id}:${count}`)
      .join(",");

    return this.toBase64(stringMap);
  }

  static decode(code) {
    try {
      const decoded = this.fromBase64(code);
      const deck = [];
      decoded.split(",").forEach((part) => {
        const [id, count] = part.split(":");
        const parsedCount = Number.parseInt(count, 10);
        if (!id || !Number.isInteger(parsedCount) || parsedCount <= 0) {
          throw new Error("Invalid deck segment");
        }

        for (let i = 0; i < parsedCount; i++) {
          deck.push(id);
        }
      });
      return deck;
    } catch (e) {
      return null; // Código inválido
    }
  }
}
