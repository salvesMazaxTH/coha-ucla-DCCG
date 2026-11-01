// Apply the existing portrait import settings to newly imported, default-configured images.
const fs = require("fs");
const path = require("path");

const defaults = {
	"compress/mode": ["0", "1"],
	"compress/lossy_quality": ["0.7", "0.9"],
	"mipmaps/generate": ["false", "true"],
	"process/size_limit": ["0", "1024"],
};

function optimize(text) {
	for (const [key, [oldValue]] of Object.entries(defaults)) {
		if (!text.split(/\r?\n/).includes(`${key}=${oldValue}`)) return text;
	}
	for (const [key, [oldValue, newValue]] of Object.entries(defaults)) {
		text = text.replace(`${key}=${oldValue}`, `${key}=${newValue}`);
	}
	return text;
}

function optimizeDirectory(directory) {
	let changed = 0;
	for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
		const file = path.join(directory, entry.name);
		if (entry.isDirectory()) {
			changed += optimizeDirectory(file);
		} else if (entry.isFile() && /\.(webp|png|jpg|jpeg)\.import$/i.test(entry.name)) {
			const before = fs.readFileSync(file, "utf8");
			const after = optimize(before);
			if (after !== before) {
				fs.writeFileSync(file, after);
				changed++;
			}
		}
	}
	return changed;
}

if (require.main === module) {
	const root = path.join(__dirname, "..", "assets", "portraits");
	console.log(`Retratos com importacao otimizada: ${optimizeDirectory(root)}`);
}

module.exports = {optimize};
