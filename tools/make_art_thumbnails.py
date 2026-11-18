# Makes small copies of every art for the cards on the table and the deck menu tiles
# (a full art takes ~30-90 ms to open on a phone, a small copy a fraction of that).
# Run again after adding an art, then run Godot --import so the new files get imported.
import pathlib
from PIL import Image

PROJECT = pathlib.Path(__file__).resolve().parent.parent
PORTRAITS = PROJECT / "assets" / "portraits"
THUMBNAILS = PROJECT / "assets" / "portrait_thumbs"
THUMBNAIL_WIDTH = 384

# Lossy like the full arts, with mipmaps so a card shown smaller than the copy still looks smooth.
IMPORT_SETTINGS = {
	"compress/mode": "1",
	"compress/lossy_quality": "0.85",
	"mipmaps/generate": "true",
}

made = 0
for source in PORTRAITS.rglob("*.webp"):
	target = THUMBNAILS / source.relative_to(PORTRAITS)
	if target.exists() and target.stat().st_mtime >= source.stat().st_mtime:
		with Image.open(target) as existing:
			if existing.width == THUMBNAIL_WIDTH:
				continue
	target.parent.mkdir(parents=True, exist_ok=True)
	image = Image.open(source).convert("RGB")
	height = round(image.height * THUMBNAIL_WIDTH / image.width)
	image.resize((THUMBNAIL_WIDTH, height), Image.LANCZOS).save(target, "WEBP", quality=88, method=6)
	made += 1
print("miniaturas feitas:", made)

# Godot writes default settings into new .import files; this puts ours in (run --import twice the first time).
fixed = 0
for import_file in THUMBNAILS.rglob("*.webp.import"):
	lines = import_file.read_text(encoding="utf-8").splitlines()
	changed = False
	for index, line in enumerate(lines):
		key = line.split("=", 1)[0]
		if key in IMPORT_SETTINGS and line != key + "=" + IMPORT_SETTINGS[key]:
			lines[index] = key + "=" + IMPORT_SETTINGS[key]
			changed = True
	if changed:
		import_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
		fixed += 1
print("importações ajustadas:", fixed)
