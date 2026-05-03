import test from "node:test";
import assert from "node:assert/strict";

import { DeckCoder } from "../shared/utils/DeckCoder.js";
import { buildValidDeckIds } from "./testDeckFactory.js";

test("encodes and decodes a deck preserving all card ids", () => {
  const deck = buildValidDeckIds();
  const code = DeckCoder.encode(deck);
  const decoded = DeckCoder.decode(code);

  assert.equal(Array.isArray(decoded), true);
  assert.equal(decoded.length, deck.length);
  assert.deepEqual(decoded.sort(), [...deck].sort());
});

test("returns null for invalid code", () => {
  const decoded = DeckCoder.decode("not-base64:::");
  assert.equal(decoded, null);
});
