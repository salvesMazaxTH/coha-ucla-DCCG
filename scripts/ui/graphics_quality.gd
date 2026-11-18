class_name GraphicsQuality
extends RefCounted
## How much visual work the game spends per frame. The defaults are the full look (PC).
## Phones switch to the economy values with use_phone_settings() (called by Main at startup):
## their GPUs fill pixels several times slower than a PC's, so the purely decorative layers
## are trimmed and the gameplay feedback stays.

## Floating embers drifting over the whole table.
static var show_motes := true
## Height in pixels of the marble table texture. It is baked once (not every frame), so the cost is
## only memory and a short bake when the window changes size; a lower value blurs the fine veins.
static var table_bake_height := 1080
## Multiplier for the particle counts and the costly glow layers of battle effects (1.0 = full).
## Below 0.7 the effects also skip their widest glows (see FxLibrary.fx_scale).
static var effect_detail := 1.0
## Noise layers in the Furtividade fog (1 to 4; each layer adds finer swirls and costs as much as the first).
static var fog_layers := 4
## The Furtividade fog warps itself for a swirling look; turning it off halves the fog's cost.
static var fog_swirl := true
## Seconds between redraws of the few card animations still drawn by the script (chains, status
## medallions taking turns). Glows, shine, stars and "z"s are animated by card_glow.gdshader instead.
static var card_animation_interval := 0.033
## Seconds between redraws of a flying card's floating shadow (0 = every frame).
static var flight_redraw_interval := 0.0
## Seconds between redraws of an animated Leader portrait (0 = every frame).
static var leader_redraw_interval := 0.0
## Frame rate cap (0 = no cap: follows the screen). Phones with 90/120 Hz screens would otherwise draw
## up to twice as many frames, heating up and draining the battery for no visible gain.
static var max_fps := 0
## Each card keeps a "photo" of the parts of its face that never move (frame, art, name, text, gems) and
## draws that one picture instead of hundreds of shapes and letters; only the animated layers are drawn
## live on top (see CardPhotoStudio). On for every device; turn it off to compare the two looks.
static var bake_card_faces := true
## Card photos painted per frame at most. Each one draws a whole card, so a phone takes one at a time.
static var photo_bakes_per_frame := 2
## How many card arts stay loaded in memory at once (0 = no limit: every art ever shown stays).
## A decoded art takes about 5-7 MB, so hundreds of them (browsing the deck builder, two full decks) can
## exhaust a phone browser's memory and make it kill the whole page. Past the limit, the art that went
## unused the longest is let go and simply loads again if it is ever needed (see CardView.texture).
static var art_cache_limit := 0
## The same for the small copies of the arts the table cards use (about 1 MB each).
static var thumbnail_cache_limit := 0

static func use_phone_settings() -> void:
	show_motes = false
	table_bake_height = 720
	effect_detail = 0.5
	# Furtividade is rare enough that its shape is worth keeping legible on a phone.
	# Three layers with a warp still cost less than the four-layer desktop fog.
	fog_layers = 3
	fog_swirl = true
	card_animation_interval = 0.05
	flight_redraw_interval = 1.0 / 30.0
	leader_redraw_interval = 0.05
	max_fps = 60
	art_cache_limit = 24
	thumbnail_cache_limit = 160
	photo_bakes_per_frame = 1
	# The Android app's video driver paints the card photos with a black band at the bottom.
	# Native code is fast enough to draw every card live, so the app goes without photos.
	if OS.has_feature("android"):
		bake_card_faces = false
