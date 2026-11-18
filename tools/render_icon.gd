## Draws the default card back very large and saves the square app icons.
## Usage: Godot --path . -s tools/render_icon.gd   (needs a window: no --headless)
extends SceneTree

const SCALE := 16.0

func _initialize() -> void:
	await process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i((CardView.BASE * SCALE).round())
	viewport.transparent_bg = true
	viewport.msaa_2d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var card: CardView = load("res://scripts/ui/card_view.gd").new().setup("", {}, SCALE)
	card.never_bake = true
	card.face_down = true
	viewport.add_child(card)
	for i in 10:
		await process_frame
	var whole := viewport.get_texture().get_image()
	whole.save_png("res://build/icon_card_back_full.png")
	# square from the middle of the back, as wide as the inner field (the frame stays off the edges)
	var side := int(100 * SCALE)
	var top_left := Vector2i((whole.get_width() - side) / 2, (whole.get_height() - side) / 2)
	var square := whole.get_region(Rect2i(top_left, Vector2i(side, side)))
	square.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	square.save_png("res://icon.png")
	# Android adaptive icon: the launcher cuts the outer third, so the crest shrinks into the safe middle
	# and fades out at its edges into a plain background of the same ink
	var foreground := square.duplicate()
	foreground.resize(300, 300, Image.INTERPOLATE_LANCZOS)
	for y in 300:
		for x in 300:
			var edge: float = minf(minf(x, 299 - x), minf(y, 299 - y))
			var pixel: Color = foreground.get_pixel(x, y)
			pixel.a *= clampf(edge / 30.0, 0.0, 1.0)
			foreground.set_pixel(x, y, pixel)
	var adaptive := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	adaptive.blend_rect(foreground, Rect2i(0, 0, 300, 300), Vector2i(66, 66))
	adaptive.save_png("res://assets/ui/icon_adaptive_foreground.png")
	var background := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	background.fill(Color("#17122e"))
	background.save_png("res://assets/ui/icon_adaptive_background.png")
	quit()
