class_name CardPhotoStudio
extends Node
## Takes "photos" of the parts of a card face that never move (frame, art, name, rules text, gems), so a card
## draws one picture instead of hundreds of shapes and letters. Only the animated layers are drawn live on top.
##
## A photo is one SubViewport holding two slots stacked vertically: slot 0 is the frame and art, slot 1 is the
## lettering and gems (the live frost / stun / sickness overlays sit between them, see CardView._draw).
## Photos are shared by every card that looks the same, and found again by their "signature": everything the
## still layers depend on (the card, its live stats, its size on screen, a cost override...).
##
## Flow: a card asks for its photo with lookup(). While there is none (or it is still being painted) the card
## draws itself the old way and leaves a request(); the studio paints the photo a few frames later and asks the
## card to redraw, so the new look (for example a changed cost) is never shown stale.

## A card must ask for the same photo this many frames in a row before it is painted (skips zoom / move tweens).
const FRAMES_UNCHANGED_BEFORE_BAKE := 2
## Room (in base pixels) around the face, because gems and their shadows hang over the card edge.
const PADDING_BASE_PIXELS := 8.0
const MAX_PHOTO_WIDTH := 1400
const MAX_PHOTO_HEIGHT := 3000 ## both slots together
const FRAMES_UNUSED_BEFORE_EVICTION := 300
const EVICTION_CHECK_FRAMES := 60
const MAX_PHOTOS := 96
const MAX_PHOTO_PIXELS := 14000000
## Painting a photo freezes a phone for a whole frame, so it waits until nothing is moving, at most this long.
const MAX_FRAMES_WAITING_FOR_STILL_TABLE := 120
## Viewports of forgotten photos kept to paint new photos of the same size: making a new one costs the phone
## far more than painting again into an old one.
const MAX_SPARE_VIEWPORTS := 12
## How much bigger than needed a spare viewport may be and still be reused.
const SPARE_VIEWPORT_SLACK := 1.15
## Empty rows under the two slots: on the Android app the bottom edge of the picture came out black,
## cutting the end of the card, so nothing is painted near that edge.
const EMPTY_ROWS_BELOW_FRACTION := 0.25

## Anything drawn into a see-through viewport ends up with its color already multiplied by its alpha, which
## would darken soft edges (rounded corners, shadows) when the photo is drawn again. This undoes the multiplication.
const UNPREMULTIPLY_SHADER := "shader_type canvas_item;
render_mode blend_disabled;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
void fragment() {
	vec4 picked = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (picked.a > 0.0001) {
		picked.rgb /= picked.a;
	}
	COLOR = picked;
}"

class Photo:
	extends RefCounted
	var signature: Dictionary
	var viewport: SubViewport
	var painter_group: CanvasGroup ## freed as soon as the picture is painted
	var padding_pixels := 0 ## empty border around the face, in photo pixels
	var slot_pixels := Vector2i.ZERO ## size of one slot, in photo pixels
	var painted_frame := 0
	var last_used_frame := 0

	## The picture exists one frame after the viewport was asked to paint.
	func is_ready() -> bool:
		return Engine.get_frames_drawn() > painted_frame

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and is_instance_valid(viewport):
			CardPhotoStudio._keep_spare_viewport(viewport)

static var _photos := {} ## hash of signature -> Photo
static var _requests := {} ## card instance id -> {"signature", "since_frame"}
static var _studio: CardPhotoStudio
static var _unfinished: Array[Photo] = [] ## photos whose painter is still alive
static var _unpremultiply_material: ShaderMaterial
static var _spare_viewports: Array[SubViewport] = []

## Whether a face of this size (in photo pixels) is small enough to be photographed.
static func can_photograph(face_size: Vector2, pixel_scale: float) -> bool:
	var padding := _padding_pixels(face_size, pixel_scale)
	var slot_width := ceili(face_size.x * pixel_scale) + 2 * padding
	var slot_height := ceili(face_size.y * pixel_scale) + 2 * padding
	return slot_width <= MAX_PHOTO_WIDTH and slot_height * 2 <= MAX_PHOTO_HEIGHT

## Keep the eligibility calculation and the actual render-target allocation in lockstep.
static func _padding_pixels(face_size: Vector2, pixel_scale: float) -> int:
	return ceili(PADDING_BASE_PIXELS * face_size.x / CardView.BASE.x * pixel_scale)

## The photo for this signature (ready or still being painted), or null if there is none.
static func lookup(signature: Dictionary) -> Photo:
	var photo: Photo = _photos.get(hash(signature))
	if photo != null and photo.signature == signature:
		photo.last_used_frame = Engine.get_frames_drawn()
		return photo
	return null

static func cache_stats() -> Dictionary:
	var pixels := 0
	for value in _photos.values():
		var photo: Photo = value
		pixels += photo.slot_pixels.x * photo.slot_pixels.y * 2
	return {
		"photos": _photos.size(),
		"pixels": pixels,
		"requests": _requests.size(),
		"unfinished": _unfinished.size(),
	}

## Puts back a photo a card is still showing after it was forgotten for being unused (a still card never
## looks its photo up), so the card's next move or trigger does not paint the same picture again.
static func keep(photo: Photo) -> void:
	photo.last_used_frame = Engine.get_frames_drawn()
	_photos[hash(photo.signature)] = photo

## Lets go of a photo whose card changed (cost, stats...): once no card shows it anymore, its viewport
## paints the next photo of the same size instead of a new viewport being made.
static func forget(photo: Photo) -> void:
	var key := hash(photo.signature)
	if _photos.get(key) == photo:
		_photos.erase(key)

## Whether the studio still owes this card a photo (it will redraw the card once the photo is ready).
static func is_waiting(card: CardView) -> bool:
	return _requests.has(card.get_instance_id())

## A card that could not draw with a photo leaves this; the studio redraws the card once the photo is ready.
static func request(card: CardView, signature: Dictionary) -> void:
	_make_sure_studio_exists()
	var card_instance_id := card.get_instance_id()
	var pending: Dictionary = _requests.get(card_instance_id, {})
	if not pending.is_empty() and pending["signature"] == signature:
		return
	# the card's live data keeps changing, so the request keeps its own copy of what the photo must show
	_requests[card_instance_id] = {"signature": signature.duplicate(true), "since_frame": Engine.get_frames_drawn()}

static func withdraw(card: CardView) -> void:
	_requests.erase(card.get_instance_id())

## The shared material of the photo CanvasGroups (one material, so the shader is compiled only once).
static func unpremultiply_material() -> ShaderMaterial:
	if _unpremultiply_material == null:
		_unpremultiply_material = ShaderMaterial.new()
		_unpremultiply_material.shader = Shader.new()
		_unpremultiply_material.shader.code = UNPREMULTIPLY_SHADER
	return _unpremultiply_material

## A forgotten photo gives its viewport back here; the oldest spare is freed when there are too many.
static func _keep_spare_viewport(viewport: SubViewport) -> void:
	if not is_instance_valid(_studio) or viewport.get_parent() != _studio:
		viewport.queue_free()
		return
	for leftover in viewport.get_children():
		leftover.queue_free()
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_spare_viewports.append(viewport)
	if _spare_viewports.size() > MAX_SPARE_VIEWPORTS:
		_spare_viewports.pop_front().queue_free()

## The smallest spare viewport that fits this size without wasting much room, or a new one.
## (a photo only uses its own slots, so the leftover edge of a bigger spare just stays empty)
func _take_viewport(viewport_size: Vector2i) -> SubViewport:
	var best_spare: SubViewport = null
	for spare in _spare_viewports:
		var fits := spare.size.x >= viewport_size.x and spare.size.y >= viewport_size.y \
			and spare.size.x <= viewport_size.x * SPARE_VIEWPORT_SLACK \
			and spare.size.y <= viewport_size.y * SPARE_VIEWPORT_SLACK
		if fits and (best_spare == null or spare.size.x * spare.size.y < best_spare.size.x * best_spare.size.y):
			best_spare = spare
	if best_spare != null:
		_spare_viewports.erase(best_spare)
		return best_spare
	var viewport := SubViewport.new()
	# It must be in the tree before canvas_transform is sent to the rendering server.
	add_child(viewport)
	viewport.size = viewport_size
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	return viewport

static func _make_sure_studio_exists() -> void:
	if is_instance_valid(_studio):
		return
	_studio = CardPhotoStudio.new()
	_studio.name = "CardPhotoStudio"
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_studio)

func _process(_delta: float) -> void:
	var frame := Engine.get_frames_drawn()
	var bakes_this_frame := 0
	var table_is_moving := not _requests.is_empty() and something_is_animating()
	for card_instance_id in _requests.keys():
		var card := instance_from_id(card_instance_id) as CardView
		if card == null or not card.is_visible_in_tree():
			_requests.erase(card_instance_id)
			continue
		var signature: Dictionary = _requests[card_instance_id]["signature"]
		var photo := lookup(signature)
		if photo != null:
			if photo.is_ready():
				_requests.erase(card_instance_id)
				card.queue_redraw()
			continue
		var waited: int = frame - int(_requests[card_instance_id]["since_frame"])
		if table_is_moving and waited < MAX_FRAMES_WAITING_FOR_STILL_TABLE:
			continue
		if waited >= FRAMES_UNCHANGED_BEFORE_BAKE and bakes_this_frame < GraphicsQuality.photo_bakes_per_frame:
			_bake(signature)
			bakes_this_frame += 1
	# the painter is only needed until the picture exists
	for photo in _unfinished.duplicate():
		if photo.is_ready():
			if is_instance_valid(photo.painter_group):
				photo.painter_group.queue_free()
			_unfinished.erase(photo)
	if frame % EVICTION_CHECK_FRAMES == 0:
		_evict_old_photos(frame)

## Whether a card is flying, a hit is shaking, etc. (endless loops, like a pulsing glow, do not count).
static func something_is_animating() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: # the headless tests start before the tree exists
		return false
	for tween in tree.get_processed_tweens():
		if tween.is_running() and tween.get_loops_left() != -1:
			return true
	return false

func _bake(signature: Dictionary) -> void:
	var pixel_scale: float = signature["pixel_scale"]
	var face_size: Vector2 = signature["face_size"]
	var started_microseconds := Time.get_ticks_usec()
	var spares_before := _spare_viewports.size()
	var photo := Photo.new()
	photo.signature = signature
	photo.padding_pixels = _padding_pixels(face_size, pixel_scale)
	photo.slot_pixels = Vector2i(
		ceili(face_size.x * pixel_scale) + 2 * photo.padding_pixels,
		ceili(face_size.y * pixel_scale) + 2 * photo.padding_pixels)

	var empty_rows_below := ceili(photo.slot_pixels.y * EMPTY_ROWS_BELOW_FRACTION)
	var viewport := _take_viewport(Vector2i(photo.slot_pixels.x, photo.slot_pixels.y * 2 + empty_rows_below))
	var reused := _spare_viewports.size() < spares_before
	viewport.canvas_transform = Transform2D().scaled(Vector2(pixel_scale, pixel_scale))
	viewport.oversampling_override = pixel_scale # letters are rasterized at the size they will be shown at
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var group := CanvasGroup.new()
	# The second painted slot sits one full card height below the painter's own control rectangle.
	group.fit_margin = photo.slot_pixels.y / pixel_scale
	group.material = unpremultiply_material()
	viewport.add_child(group)

	var painter := CardView.new()
	painter.prepare_photo_painter(signature, photo.padding_pixels / pixel_scale, photo.slot_pixels.y / pixel_scale)
	group.add_child(painter)

	photo.viewport = viewport
	photo.painter_group = group
	photo.painted_frame = Engine.get_frames_drawn()
	photo.last_used_frame = photo.painted_frame
	_photos[hash(signature)] = photo
	_unfinished.append(photo)
	HitchLog.note("foto %s x%.2f %s %d ms" % [
		signature["card_id"], pixel_scale, "reuso" if reused else "nova",
		roundi((Time.get_ticks_usec() - started_microseconds) / 1000.0)])

## Forgets photos nobody used for a while, and the least recently used ones when there are too many.
## (A card that is still showing a photo keeps it alive on its own, even after it is forgotten here.)
func _evict_old_photos(frame: int) -> void:
	var total_pixels := 0
	for key in _photos.keys():
		var photo: Photo = _photos[key]
		if frame - photo.last_used_frame > FRAMES_UNUSED_BEFORE_EVICTION:
			_photos.erase(key)
		else:
			total_pixels += photo.slot_pixels.x * photo.slot_pixels.y * 2
	while _photos.size() > MAX_PHOTOS or total_pixels > MAX_PHOTO_PIXELS:
		var oldest_key = null
		var oldest_frame := frame + 1
		for key in _photos.keys():
			var photo: Photo = _photos[key]
			if photo.is_ready() and photo.last_used_frame < oldest_frame:
				oldest_key = key
				oldest_frame = photo.last_used_frame
		if oldest_key == null:
			return
		var removed: Photo = _photos[oldest_key]
		total_pixels -= removed.slot_pixels.x * removed.slot_pixels.y * 2
		_photos.erase(oldest_key)
