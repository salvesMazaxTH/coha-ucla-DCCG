class_name GraphicsQuality
extends RefCounted
## How much visual work the game spends per frame. The defaults are the full look (PC).
## Phones switch to the economy values with use_phone_settings() (called by Main at startup):
## their GPUs fill pixels several times slower than a PC's, so the purely decorative layers
## are trimmed and the gameplay feedback stays.

## Floating embers drifting over the whole table.
static var show_motes := true
## Multiplier for the particle counts and the costly glow layers of battle effects (1.0 = full).
## Below 0.7 the effects also skip their widest glows (see Main._fx_scale).
static var effect_detail := 1.0
## Noise layers in the Furtividade fog (1 to 4; each layer adds finer swirls and costs as much as the first).
static var fog_layers := 4
## The Furtividade fog warps itself for a swirling look; turning it off halves the fog's cost.
static var fog_swirl := true
## Seconds between redraws of animated card frames (legendary shimmer, glowing outlines, frost...).
## Each redraw of a card costs about 1.5 ms on a PC, so phones animate them less often.
static var card_animation_interval := 0.033
## Glowing (playable/targetable) and hovered cards redraw every frame so their pulse looks smooth.
## Phones show many glowing cards at once, so there they follow card_animation_interval too.
static var smooth_card_pulse := true
## Frame rate cap (0 = no cap: follows the screen). Phones with 90/120 Hz screens would otherwise draw
## up to twice as many frames, heating up and draining the battery for no visible gain.
static var max_fps := 0

static func use_phone_settings() -> void:
	show_motes = false
	effect_detail = 0.5
	fog_layers = 2
	fog_swirl = false
	card_animation_interval = 0.05
	smooth_card_pulse = false
	max_fps = 60
