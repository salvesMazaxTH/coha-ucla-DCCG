/**
 * server/index.js
 *
 * Main server entry point
 * Sets up Express + Socket.io
 */

import express from "express";
import { createServer } from "http";
import { Server } from "socket.io";
import path from "path";
import { fileURLToPath } from "url";
import { setupSocketHandlers } from "./network/SocketHandler.js";
import { cardList } from "../public/data/cardDB.js";
import { DeckCoder } from "../shared/utils/DeckCoder.js";
import { DeckValidator } from "./core/DeckValidator.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"],
  },
});

// Serve static files (frontend)
app.use(express.static(path.join(__dirname, "../public")));
app.use("/shared", express.static(path.join(__dirname, "../shared")));
app.use(express.json());

app.get("/api/cards", (_req, res) => {
  res.json({ cards: cardList });
});

app.post("/api/decks/validate", (req, res) => {
  const { deckCode } = req.body || {};
  const cardIds = DeckCoder.decode(deckCode);
  const result = DeckValidator.validateDetailed(cardIds);
  if (!result.valid) {
    res.status(400).json(result);
    return;
  }

  res.json(result);
});

setupSocketHandlers(io);

// Start server
const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log(
    `🎮 Arena dos Campeões server running on http://localhost:${PORT}`,
  );
});
