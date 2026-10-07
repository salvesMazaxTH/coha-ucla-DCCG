// Serve the Web export (build/web) over HTTP on the LAN: node tools/serve_web.js [port]
// Gzips wasm/js/html on the fly (cached in memory) and revalidates files with ETag so reloads are fast.
const http = require("http"), https = require("https"), fs = require("fs"), path = require("path"), os = require("os"), net = require("net"), zlib = require("zlib");
const root = path.join(__dirname, "..", "build", "web");
const port = Number(process.argv[2]) || 8060;
const types = {".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream",
	".png": "image/png", ".ico": "image/x-icon", ".json": "application/json", ".css": "text/css"};
const zipped = new Map();
const handler = (req, res) => {
	let p = decodeURIComponent(req.url.split("?")[0]);
	if (p === "/") p = "/index.html";
	const file = path.join(root, path.normalize(p));
	if (!file.startsWith(root) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); return res.end("404"); }
	const st = fs.statSync(file), ext = path.extname(file);
	const etag = '"' + st.size + "-" + st.mtimeMs + '"';
	const head = {"Content-Type": types[ext] || "application/octet-stream", "ETag": etag, "Cache-Control": "no-cache"};
	if (req.headers["if-none-match"] === etag) { res.writeHead(304, head); return res.end(); }
	if (/gzip/.test(req.headers["accept-encoding"] || "")) {
		let z = zipped.get(file);
		if (!z || z.etag !== etag) { z = {etag, buf: zlib.gzipSync(fs.readFileSync(file), {level: 6})}; zipped.set(file, z); }
		res.writeHead(200, {...head, "Content-Encoding": "gzip", "Content-Length": z.buf.length});
		return res.end(z.buf);
	}
	res.writeHead(200, {...head, "Content-Length": st.size});
	fs.createReadStream(file).pipe(res);
};
const certDir = path.join(__dirname, "cert");
const tls = fs.existsSync(path.join(certDir, "key.pem")) ? {key: fs.readFileSync(path.join(certDir, "key.pem")), cert: fs.readFileSync(path.join(certDir, "cert.pem"))} : null;
// Godot Web exige contexto seguro (HTTPS) quando acessado por IP da LAN.
const server = tls ? https.createServer(tls, handler) : http.createServer(handler);
// wss://host:port/ws -> match server (headless Godot, plain ws on localhost): raw TCP passthrough of the upgrade.
const matchPort = Number(process.env.MATCH_PORT) || 8061;
server.on("upgrade", (req, sock, head) => {
	if (req.url.split("?")[0] !== "/ws") return sock.destroy();
	const up = net.connect(matchPort, "127.0.0.1", () => {
		let raw = req.method + " " + req.url + " HTTP/" + req.httpVersion + "\r\n";
		for (let k = 0; k < req.rawHeaders.length; k += 2) raw += req.rawHeaders[k] + ": " + req.rawHeaders[k + 1] + "\r\n";
		up.write(raw + "\r\n");
		if (head.length) up.write(head);
		sock.pipe(up).pipe(sock);
	});
	up.on("error", () => sock.destroy());
	sock.on("error", () => up.destroy());
});
server.listen(port, "0.0.0.0", () => {
	const proto = tls ? "https" : "http";
	console.log("Servindo build/web na porta " + port);
	for (const list of Object.values(os.networkInterfaces()))
		for (const i of list) if (i.family === "IPv4" && !i.internal) console.log("  celular: " + proto + "://" + i.address + ":" + port);
});
