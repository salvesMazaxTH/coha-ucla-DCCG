import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { io as createClient } from "socket.io-client";

import { DeckCoder } from "../shared/utils/DeckCoder.js";
import {
  ClientEvents,
  ServerEvents,
} from "../shared/contracts/SocketEvents.js";
import { buildValidDeckIds } from "./testDeckFactory.js";

const PORT = 4017;
const BASE_URL = `http://127.0.0.1:${PORT}`;

function waitForServer(serverProcess) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error("Server did not start in time"));
    }, 10000);

    serverProcess.stdout.on("data", (chunk) => {
      const text = chunk.toString();
      if (text.includes("server running")) {
        clearTimeout(timeout);
        resolve();
      }
    });

    serverProcess.on("exit", (code) => {
      clearTimeout(timeout);
      reject(new Error(`Server exited early with code ${code}`));
    });
  });
}

function createConnectedClient() {
  const client = createClient(BASE_URL, {
    transports: ["websocket"],
    forceNew: true,
  });
  return client;
}

test("socket flow: two validated decks produce match and game state", async () => {
  const server = spawn("node", ["server/server.js"], {
    env: { ...process.env, PORT: String(PORT) },
    stdio: ["ignore", "pipe", "pipe"],
  });

  try {
    await waitForServer(server);

    const p1 = createConnectedClient();
    const p2 = createConnectedClient();

    await Promise.all([once(p1, "connect"), once(p2, "connect")]);

    const deckCode = DeckCoder.encode(buildValidDeckIds());

    const p1PairReady = once(p1, ServerEvents.PAIR_READY);
    const p2PairReady = once(p2, ServerEvents.PAIR_READY);

    const p1Accepted = once(p1, ServerEvents.DECK_ACCEPTED);
    const p2Accepted = once(p2, ServerEvents.DECK_ACCEPTED);
    const p1Match = once(p1, ServerEvents.MATCH_FOUND);
    const p2Match = once(p2, ServerEvents.MATCH_FOUND);
    const p1State = once(p1, ServerEvents.GAME_STATE);
    const p2State = once(p2, ServerEvents.GAME_STATE);

    p1.emit(ClientEvents.REGISTER_PLAYER, { username: "Thiago" });
    p2.emit(ClientEvents.REGISTER_PLAYER, { username: "Rival" });

    await Promise.all([p1PairReady, p2PairReady]);

    p1.emit(ClientEvents.SUBMIT_DECK, { deckCode });
    p2.emit(ClientEvents.SUBMIT_DECK, { deckCode });

    const [, , , , [p1StatePayload], [p2StatePayload]] = await Promise.all([
      p1Accepted,
      p2Accepted,
      p1Match,
      p2Match,
      p1State,
      p2State,
    ]);

    assert.equal(p1StatePayload.players.p1.hand.length, 6);
    assert.equal(p2StatePayload.players.p2.hand.length, 6);

    p1.close();
    p2.close();

    assert.ok(true);
  } finally {
    server.kill();
  }
});

test("socket flow: surrender ends match and emits game over", async () => {
  const server = spawn("node", ["server/server.js"], {
    env: { ...process.env, PORT: String(PORT) },
    stdio: ["ignore", "pipe", "pipe"],
  });

  try {
    await waitForServer(server);

    const p1 = createConnectedClient();
    const p2 = createConnectedClient();

    await Promise.all([once(p1, "connect"), once(p2, "connect")]);

    const deckCode = DeckCoder.encode(buildValidDeckIds());

    const p1PairReady = once(p1, ServerEvents.PAIR_READY);
    const p2PairReady = once(p2, ServerEvents.PAIR_READY);

    const p1MatchPromise = once(p1, ServerEvents.MATCH_FOUND);
    const p2MatchPromise = once(p2, ServerEvents.MATCH_FOUND);
    const p1GameOverPromise = once(p1, ServerEvents.GAME_OVER);
    const p2GameOverPromise = once(p2, ServerEvents.GAME_OVER);

    p1.emit(ClientEvents.REGISTER_PLAYER, { username: "Thiago" });
    p2.emit(ClientEvents.REGISTER_PLAYER, { username: "Rival" });

    await Promise.all([p1PairReady, p2PairReady]);

    p1.emit(ClientEvents.SUBMIT_DECK, { deckCode });
    p2.emit(ClientEvents.SUBMIT_DECK, { deckCode });

    const [[p1Match], [p2Match]] = await Promise.all([
      p1MatchPromise,
      p2MatchPromise,
    ]);

    assert.equal(p1Match.playerId, "p1");
    assert.equal(p2Match.playerId, "p2");

    p2.emit(ClientEvents.SURRENDER);

    const [[p1GameOver], [p2GameOver]] = await Promise.all([
      p1GameOverPromise,
      p2GameOverPromise,
    ]);

    assert.equal(p1GameOver.reason, "surrender");
    assert.equal(p2GameOver.reason, "surrender");
    assert.equal(p1GameOver.result, "victory");
    assert.equal(p2GameOver.result, "defeat");

    p1.close();
    p2.close();
  } finally {
    server.kill();
  }
});
