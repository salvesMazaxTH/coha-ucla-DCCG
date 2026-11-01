const assert = require("node:assert/strict");
const {spawn} = require("node:child_process");
const fs = require("node:fs");
const http = require("node:http");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const zlib = require("node:zlib");

function request(port, file, headers = {}) {
	return new Promise((resolve, reject) => {
		http.get({host: "127.0.0.1", port, path: file, headers}, (res) => {
			const chunks = [];
			res.on("data", (chunk) => chunks.push(chunk));
			res.on("end", () => resolve({status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks)}));
			res.on("error", reject);
		}).on("error", reject);
	});
}

test("serves compressed code, uncompressed packs and conditional cache responses", async (t) => {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), "csa-web-test-"));
	t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
	fs.mkdirSync(path.join(dir, "tools"));
	fs.mkdirSync(path.join(dir, "build", "web"), {recursive: true});
	fs.copyFileSync(path.join(__dirname, "..", "tools", "serve_web.js"), path.join(dir, "tools", "serve_web.js"));
	fs.writeFileSync(path.join(dir, "build", "web", "index.js"), "const test = 'compressible';\n".repeat(20));
	fs.writeFileSync(path.join(dir, "build", "web", "index.pck"), "already-compressed-pack");

	const probe = net.createServer();
	await new Promise((resolve) => probe.listen(0, "127.0.0.1", resolve));
	const port = probe.address().port;
	await new Promise((resolve, reject) => probe.close((err) => err ? reject(err) : resolve()));

	const server = spawn(process.execPath, [path.join(dir, "tools", "serve_web.js"), String(port)]);
	t.after(() => server.kill());
	await new Promise((resolve, reject) => {
		server.once("error", reject);
		server.once("exit", (code) => reject(new Error(`Server exited before starting: ${code}`)));
		server.stdout.once("data", resolve);
	});

	const js = await request(port, "/index.js", {"Accept-Encoding": "gzip"});
	assert.equal(js.status, 200);
	assert.equal(js.headers["content-encoding"], "gzip");
	assert.equal(js.headers.vary, "Accept-Encoding");
	assert.equal(zlib.gunzipSync(js.body).toString(), "const test = 'compressible';\n".repeat(20));
	const jsPlain = await request(port, "/index.js");
	assert.equal(jsPlain.headers["content-encoding"], undefined);
	assert.equal(jsPlain.headers.etag, js.headers.etag);
	assert.equal(jsPlain.body.toString(), zlib.gunzipSync(js.body).toString());

	const pack = await request(port, "/index.pck", {"Accept-Encoding": "gzip"});
	assert.equal(pack.status, 200);
	assert.equal(pack.headers["content-encoding"], undefined);
	assert.equal(pack.headers.vary, "Accept-Encoding");
	assert.equal(pack.body.toString(), "already-compressed-pack");
	const cached = await request(port, "/index.pck", {"If-None-Match": pack.headers.etag});
	assert.equal(cached.status, 304);
	assert.equal(cached.body.length, 0);
	assert.equal(cached.headers.vary, "Accept-Encoding");
});
