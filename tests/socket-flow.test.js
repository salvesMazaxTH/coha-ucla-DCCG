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

    const p1Accepted = once(p1, ServerEvents.DECK_ACCEPTED);
    const p2Accepted = once(p2, ServerEvents.DECK_ACCEPTED);
    const p1Match = once(p1, ServerEvents.MATCH_FOUND);
    const p2Match = once(p2, ServerEvents.MATCH_FOUND);
    const p1State = once(p1, ServerEvents.GAME_STATE);
    const p2State = once(p2, ServerEvents.GAME_STATE);

    p1.emit(ClientEvents.SUBMIT_DECK, { deckCode });
    p2.emit(ClientEvents.SUBMIT_DECK, { deckCode });

    await Promise.all([
      p1Accepted,
      p2Accepted,
      p1Match,
      p2Match,
      p1State,
      p2State,
    ]);

    p1.close();
    p2.close();

    assert.ok(true);
  } finally {
    server.kill();
  }
});
