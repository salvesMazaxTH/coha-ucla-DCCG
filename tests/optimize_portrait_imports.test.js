const assert = require("node:assert/strict");
const test = require("node:test");
const {optimize} = require("../tools/optimize_portrait_imports.js");

const defaultImport = [
	"[params]",
	"compress/mode=0",
	"compress/lossy_quality=0.7",
	"mipmaps/generate=false",
	"process/size_limit=0",
	"other=value",
	"",
].join("\r\n");

test("optimizes default imports and preserves line endings and unrelated settings", () => {
	const optimized = optimize(defaultImport);
	assert.equal(optimized, defaultImport
		.replace("compress/mode=0", "compress/mode=1")
		.replace("compress/lossy_quality=0.7", "compress/lossy_quality=0.9")
		.replace("mipmaps/generate=false", "mipmaps/generate=true")
		.replace("process/size_limit=0", "process/size_limit=1024"));
	assert.equal(optimize(optimized), optimized);
});

test("leaves customized or incomplete imports unchanged", () => {
	for (const custom of [
		defaultImport.replace("compress/mode=0", "compress/mode=2"),
		defaultImport.replace("compress/lossy_quality=0.7", "compress/lossy_quality=0.8"),
		defaultImport.replace("mipmaps/generate=false", "mipmaps/generate=true"),
		defaultImport.replace("process/size_limit=0\r\n", ""),
	]) {
		assert.equal(optimize(custom), custom);
	}
});
