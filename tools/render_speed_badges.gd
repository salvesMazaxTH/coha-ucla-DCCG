extends SceneTree
## Renders the spell speed seals (CardView._speed_badge) to assets/ui/speed_<speed>.png,
## used inline in rules text ("Ao Ativar (2) [rapido] ..."). Needs a GPU (not --headless):
## Godot --path . -s tools/render_speed_badges.gd

const H := 48 ## seal height in px (12.4 units at scale H / 12.4)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	for speed in ["lento", "rapido", "instantaneo"]:
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.size = Vector2i(H * 6, H + 8)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cv := CardView.new()
		cv.badge_only = speed
		cv.size = Vector2(vp.size)
		vp.add_child(cv)
		root.add_child(vp)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.crop(img.get_width(), img.get_height())
		var used := img.get_used_rect()
		img = img.get_region(used)
		img.save_png("res://assets/ui/speed_%s.png" % speed)
		vp.queue_free()
	quit()
