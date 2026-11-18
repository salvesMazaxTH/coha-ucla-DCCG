// Serves build/android/csa.apk on the home Wi-Fi so a phone can download it.
// Usage: node tools/serve_apk.js [port]   (default 8070)
const http = require("http");
const fs = require("fs");
const path = require("path");

const port = Number(process.argv[2] || 8070);
const apkPath = path.join(__dirname, "..", "build", "android", "csa.apk");

http.createServer((request, response) => {
	if (request.url !== "/csa.apk") {
		response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
		return response.end('<meta name=viewport content="width=device-width"><a style="font-size:40px" href="/csa.apk">Baixar csa.apk</a>');
	}
	if (!fs.existsSync(apkPath)) {
		response.writeHead(404);
		return response.end("APK ainda nao foi gerado.");
	}
	response.writeHead(200, {
		"Content-Type": "application/vnd.android.package-archive",
		"Content-Length": fs.statSync(apkPath).size,
		"Content-Disposition": "attachment; filename=csa.apk",
	});
	fs.createReadStream(apkPath).pipe(response);
}).listen(port, "0.0.0.0", () => console.log("APK em http://<IP do PC>:" + port));
