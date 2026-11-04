// End-to-end match-server test with a local fake Supabase; no real accounts or database are used.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createServer } from "node:http";
import { createServer as createTcpServer } from "node:net";
import { mkdtemp, readFile, rm, rmdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const temp = await mkdtemp(join(tmpdir(), "csa-stats-test-"));
const queue = join(temp, "pending.json");
const deck = JSON.parse(await readFile("data/decks/prebuilt/fogo.json", "utf8"));
const users = { "token-a": "11111111-1111-4111-8111-111111111111", "token-b": "22222222-2222-4222-8222-222222222222" };
const savedId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const attempts = [];
const committed = new Map();
const http = createServer(async (req, res) => {
	const bearer = (req.headers.authorization || "").replace(/^Bearer /, "");
	res.setHeader("Content-Type", "application/json");
	if (req.url === "/auth/v1/user") {
		res.statusCode = users[bearer] ? 200 : 401;
		res.end(JSON.stringify(users[bearer] ? { id: users[bearer] } : {}));
	} else if (req.url.startsWith("/rest/v1/decks?")) {
		res.end(JSON.stringify(bearer === "token-a" ? [{ name: deck.name, content: deck }] : []));
	} else if (req.url === "/rest/v1/rpc/record_deck_match_results" && bearer === "test-service-key") {
		let body = "";
		for await (const chunk of req) body += chunk;
		const results = JSON.parse(body).p_results;
		attempts.push(results);
		for (const result of results) committed.set(`${result.match_id}:${result.seat}`, result);
		// The first response is lost after the database committed: the retry must be idempotent.
		res.statusCode = attempts.length === 1 ? 503 : 204;
		res.end();
	} else {
		res.statusCode = 404;
		res.end("{}");
	}
});
http.listen(0, "127.0.0.1");
await once(http, "listening");
const reservation = createTcpServer();
reservation.listen(0, "127.0.0.1");
await once(reservation, "listening");
const port = reservation.address().port;
await new Promise(resolve => reservation.close(resolve));
const godot = process.env.GODOT_BIN || "godot";
const child = spawn(godot, ["--headless", "--path", ".", "-s", "scripts/net/match_server.gd", "--", String(port)], {
	env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${http.address().port}`,
		SUPABASE_PUBLISHABLE_KEY: "test-public-key", SUPABASE_SERVICE_ROLE_KEY: "test-service-key",
		MATCH_STATS_QUEUE_PATH: queue },
	stdio: ["ignore", "pipe", "pipe"]
});
const processes = [child];
let output = "";
child.stdout.on("data", data => { output += data; });
child.stderr.on("data", data => { output += data; });
const sockets = [];

async function connect(targetPort = port) {
	const ws = new WebSocket(`ws://127.0.0.1:${targetPort}`);
	const inbox = [];
	ws.addEventListener("message", event => inbox.push(JSON.parse(event.data)));
	await Promise.race([once(ws, "open"), new Promise((_, reject) => setTimeout(() => reject(new Error("WebSocket timeout")), 5000))]);
	sockets.push(ws);
	return {
		ws,
		send: message => ws.send(JSON.stringify(message)),
		async take(type, timeout = 5000) {
			const end = Date.now() + timeout;
			while (Date.now() < end) {
				const i = inbox.findIndex(message => message.t === type);
				if (i >= 0) return inbox.splice(i, 1)[0];
				await new Promise(resolve => setTimeout(resolve, 20));
			}
			throw new Error(`Timed out waiting for ${type}; server output:\n${output}`);
		}
	};
}

try {
	const deadline = Date.now() + 10000;
	while (!output.includes("match_server listening")) {
		if (child.exitCode !== null || Date.now() > deadline) throw new Error(`Server failed to start:\n${output}`);
		await new Promise(resolve => setTimeout(resolve, 50));
	}
	const invalid = await connect();
	invalid.send({ t: "create", deck: "fogo", deck_key: "fogo", account: true, access_token: "bad-token" });
	assert.match((await invalid.take("error")).msg, /validar sua conta/);

	const forged = await connect();
	const alteredDeck = { ...deck, cards: { ...deck.cards, fada_do_fogo: 2 } };
	forged.send({ t: "create", deck: alteredDeck, deck_key: `mine:${savedId}`, account: true, access_token: "token-a" });
	assert.match((await forged.take("error")).msg, /deck mudou/);

	const guestA = await connect();
	const guestB = await connect();
	guestA.send({ t: "create", deck: "fogo" });
	const guestRoom = await guestA.take("room");
	guestB.send({ t: "join", code: guestRoom.code, deck: "agua" });
	await guestA.take("start");
	await guestB.take("start");
	guestB.send({ t: "act", a: "concede" });
	assert.equal((await guestA.take("events")).snap.phase, "over");
	await new Promise(resolve => setTimeout(resolve, 300));
	assert.equal(attempts.length, 0, "guest matches must not write account results");

	const a = await connect();
	const b = await connect();
	a.send({ t: "create", deck, deck_key: `mine:${savedId}`, account: true, access_token: "token-a" });
	const room = await a.take("room");
	b.send({ t: "join", code: room.code, deck: "agua", deck_key: "agua", account: true, access_token: "token-b" });
	await a.take("start");
	await b.take("start");
	a.ws.close();
	const resumed = await connect();
	resumed.send({ t: "resume", code: room.code, token: room.token });
	await resumed.take("start");
	b.send({ t: "act", a: "concede" });
	assert.equal((await resumed.take("events")).snap.winner, 0);
	await resumed.take("stats_error");
	assert.equal(JSON.parse(await readFile(queue, "utf8")).length, 1, "failed writes must remain queued");
	await resumed.take("stats_saved", 15000);
	assert.equal(attempts.length, 2);
	assert.deepEqual(attempts[0], attempts[1]);
	assert.equal(committed.size, 2, "a retried match must not be double-counted");
	assert.deepEqual([...committed.values()].map(({ user_id, deck_key, result }) => ({ user_id, deck_key, result })), [
		{ user_id: users["token-a"], deck_key: `mine:${savedId}`, result: "win" },
		{ user_id: users["token-b"], deck_key: "agua", result: "loss" }
	]);
	assert.deepEqual(JSON.parse(await readFile(queue, "utf8")), []);
	const devReservation = createTcpServer();
	devReservation.listen(0, "127.0.0.1");
	await once(devReservation, "listening");
	const devPort = devReservation.address().port;
	await new Promise(resolve => devReservation.close(resolve));
	const devServer = spawn(godot, ["--headless", "--path", ".", "-s", "scripts/net/match_server.gd", "--", String(devPort), "--dev"], {
		env: { ...process.env, SUPABASE_URL: `http://127.0.0.1:${http.address().port}`,
			SUPABASE_PUBLISHABLE_KEY: "test-public-key", SUPABASE_SERVICE_ROLE_KEY: "test-service-key",
			MATCH_STATS_QUEUE_PATH: join(temp, "dev-pending.json") },
		stdio: ["ignore", "pipe", "pipe"]
	});
	processes.push(devServer);
	let devOutput = "";
	devServer.stdout.on("data", data => { devOutput += data; });
	devServer.stderr.on("data", data => { devOutput += data; });
	const devDeadline = Date.now() + 10000;
	while (!devOutput.includes("match_server listening")) {
		if (devServer.exitCode !== null || Date.now() > devDeadline) throw new Error(`Dev server failed:\n${devOutput}`);
		await new Promise(resolve => setTimeout(resolve, 50));
	}
	const devA = await connect(devPort);
	const devB = await connect(devPort);
	devA.send({ t: "create", deck: "fogo", deck_key: "fogo", account: true, access_token: "token-a" });
	const devRoom = await devA.take("room");
	devB.send({ t: "join", code: devRoom.code, deck: "agua", deck_key: "agua", account: true, access_token: "token-b" });
	await devA.take("start");
	await devB.take("start");
	devB.send({ t: "act", a: "concede" });
	assert.equal((await devA.take("events")).snap.phase, "over");
	await new Promise(resolve => setTimeout(resolve, 400));
	assert.equal(attempts.length, 2, "development-mode matches must not write results");
	console.log("deck stats online integration passed");
} finally {
	for (const socket of sockets) socket.close();
	for (const process of processes) {
		if (process.exitCode === null) {
			process.kill();
			await once(process, "exit").catch(() => {});
		}
	}
	await new Promise(resolve => http.close(resolve));
	await rm(queue, { force: true });
	await rm(`${queue}.tmp`, { force: true });
	await rm(join(temp, "dev-pending.json"), { force: true });
	await rm(join(temp, "dev-pending.json.tmp"), { force: true });
	await rmdir(temp);
}
