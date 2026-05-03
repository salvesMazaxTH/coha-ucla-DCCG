import test from "node:test";
import assert from "node:assert/strict";

import { DeckValidator } from "../server/core/DeckValidator.js";
import { buildValidDeckIds } from "./testDeckFactory.js";

test("accepts a legal 48-card deck", () => {
  const deck = buildValidDeckIds();
  const result = DeckValidator.validateDetailed(deck);
  assert.equal(result.valid, true);
  assert.equal(result.error, null);
});

test("rejects deck with invalid size", () => {
  const deck = buildValidDeckIds().slice(0, 47);
  const result = DeckValidator.validateDetailed(deck);
  assert.equal(result.valid, false);
  assert.equal(result.error.rule, "size");
});

test("rejects champion copies above limit", () => {
  const deck = buildValidDeckIds();
  deck[0] = "galeRider";
  deck[1] = "galeRider";
  deck[2] = "galeRider";

  const result = DeckValidator.validateDetailed(deck);
  assert.equal(result.valid, false);
  assert.equal(result.error.rule, "copies");
});

test("rejects non-neutral card without shared essence", () => {
  const deck = buildValidDeckIds();
  const firstDusk = deck.indexOf("duskInvoker");
  const secondDusk = deck.lastIndexOf("duskInvoker");

  if (firstDusk === -1 || secondDusk === -1 || firstDusk === secondDusk) {
    throw new Error("Test deck must include two duskInvoker cards");
  }

  // Keeps one crepuscular card isolated while preserving deck size and copy limits.
  deck[secondDusk] = "neutralSquire";

  const result = DeckValidator.validateDetailed(deck);
  assert.equal(result.valid, false);
  assert.equal(result.error.rule, "cohesion");
});
