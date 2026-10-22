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

## Cards waiting for a photo are served this many per frame, so a whole board never stalls one frame.
const PHOTO_BAKES_PER_FRAME := 2
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
			viewport.queue_free()

static var _photos := {} ## hash of signature -> Photo
static var _requests := {} ## card instance id -> {"signature", "since_frame"}
static var _studio: CardPhotoStudio
static var _unfinished: Array[Photo] = [] ## photos whose painter is still alive

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

static func _make_sure_studio_exists() -> void:
	if is_instance_valid(_studio):
		return
	_studio = CardPhotoStudio.new()
	_studio.name = "CardPhotoStudio"
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_studio)

func _process(_delta: float) -> void:
	var frame := Engine.get_frames_drawn()
	var bakes_this_frame := 0
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
		if waited >= FRAMES_UNCHANGED_BEFORE_BAKE and bakes_this_frame < PHOTO_BAKES_PER_FRAME:
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

func _bake(signature: Dictionary) -> void:
	var pixel_scale: float = signature["pixel_scale"]
	var face_size: Vector2 = signature["face_size"]
	var photo := Photo.new()
	photo.signature = signature
	photo.padding_pixels = _padding_pixels(face_size, pixel_scale)
	photo.slot_pixels = Vector2i(
		ceili(face_size.x * pixel_scale) + 2 * photo.padding_pixels,
		ceili(face_size.y * pixel_scale) + 2 * photo.padding_pixels)

	var viewport := SubViewport.new()
	# It must be in the tree before canvas_transform is sent to the rendering server.
	add_child(viewport)
	viewport.size = Vector2i(photo.slot_pixels.x, photo.slot_pixels.y * 2)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.canvas_transform = Transform2D().scaled(Vector2(pixel_scale, pixel_scale))
	viewport.oversampling_override = pixel_scale # letters are rasterized at the size they will be shown at
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var group := CanvasGroup.new()
	# The second painted slot sits one full card height below the painter's own control rectangle.
	group.fit_margin = photo.slot_pixels.y / pixel_scale
	var material := ShaderMaterial.new()
	material.shader = Shader.new()
	material.shader.code = UNPREMULTIPLY_SHADER
	group.material = material
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
