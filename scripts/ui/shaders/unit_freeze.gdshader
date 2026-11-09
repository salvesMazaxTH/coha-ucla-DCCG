shader_type canvas_item;
// The ice destroy (any card of the element gelo that destroys one unit): the unit is frozen solid and shatters.
// Frost creeps in from the edges of the card toward the middle (jagged front, a bright rim on it, crystal
// facets inside, a few glints), then cracks run out of the middle in several directions, and a pale flash
// goes off at the moment it breaks (at that moment FxCasts swaps the card for flying shards of it).
// Drawn on ONE ColorRect a little bigger than the card, with normal blending, no textures and no screen reads.
// FxCasts._freeze_unit tweens `progress` (the frost creeping), `cracks` (the cracks spreading) and `flash` (the
// shatter), and sets `shattered` to 1 when the ice breaks (the frost and cracks go away: the shards carry them).
// Cost: 2 value-noise lookups for the frost front, 7 cracks (one noise lookup each), no big loops.
// Coordinates: UV.y = 0 at the top of the rectangle.

uniform float progress = 0.0; // 0 = no frost yet, 1 = the card is frozen all over
uniform float cracks = 0.0; // 0 = no cracks, 1 = the cracks have spread as far as they go
uniform float flash = 0.0; // 0 = nothing, 1 = the peak of the shatter flash
uniform float shattered = 0.0; // 0 = the ice is whole, 1 = it has broken (frost and cracks gone, only the flash is left)
uniform float aspect = 0.75; // rectangle width / height, so the shapes are not stretched

const vec3 FROST_DEEP = vec3(0.52, 0.78, 0.95);
const vec3 FROST_LIGHT = vec3(0.92, 0.98, 1.0);
const vec3 CRACK_COLOR = vec3(0.97, 1.0, 1.0);
const float CRACK_COUNT = 7.0;

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

// smooth 2D noise
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 inside = fract(p);
	vec2 blend = inside * inside * (3.0 - 2.0 * inside);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), blend.x), blend.y);
}

void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);
	// the card sits in the middle of the rectangle (the rectangle is about 18% wider and 12% taller)
	float inside = smoothstep(0.07, 0.09, UV.x) * smoothstep(0.07, 0.09, 1.0 - UV.x)
		* smoothstep(0.04, 0.06, UV.y) * smoothstep(0.04, 0.06, 1.0 - UV.y);
	// how far this spot is from the nearest edge of the card
	float from_edge = max(min(min(UV.x - 0.07, 0.93 - UV.x) * aspect, min(UV.y - 0.04, 0.96 - UV.y)), 0.0);

	// --- the frost: its front is a jagged line moving from the edges toward the middle
	float depth = progress * 0.4;
	float jag = noise(p * 14.0) * 0.07 + noise(p * 41.0) * 0.02;
	float front = from_edge + jag;
	float frozen = 1.0 - smoothstep(depth - 0.015, depth + 0.005, front);
	float rim = exp(-abs(front - depth) * 70.0) * step(0.001, progress) * (1.0 - step(0.999, progress));

	// crystal facets: every little cell of the frost has its own shade, and a few catch the light and glint
	vec2 facet_cell = floor(p * vec2(11.0, 11.0));
	float facet = 0.72 + 0.28 * hash(facet_cell);
	float glint_tick = floor(TIME * 10.0);
	float glint = step(0.975, hash(floor(p * 55.0) + glint_tick)) * frozen;
	vec3 frost_color = mix(FROST_DEEP, FROST_LIGHT, facet);
	frost_color = mix(frost_color, vec3(1.0), clamp(rim * 0.8 + glint, 0.0, 1.0));
	float frost_alpha = (frozen * 0.6 + rim * 0.35 + glint * 0.4) * inside * (1.0 - shattered);

	// --- the cracks: spokes from the middle of the card, each a little crooked, growing outward
	vec2 middle = vec2((UV.x - 0.5) * aspect, UV.y - 0.5);
	float radius = length(middle);
	float angle = atan(middle.y, middle.x);
	float crack_line = 0.0;
	for (int index = 0; index < 7; index++) {
		float number = float(index);
		float spoke = hash(vec2(number * 3.7, 1.3)) * 6.2832;
		float off_angle = angle - spoke;
		float delta = atan(sin(off_angle), cos(off_angle));
		float across = abs(radius * sin(delta)) + (noise(vec2(radius * 26.0, number * 5.1)) - 0.5) * 0.022;
		float along = radius * cos(delta);
		float reach = cracks * (0.34 + 0.2 * hash(vec2(number, 9.9)));
		float grown = step(0.0, along) * (1.0 - smoothstep(reach - 0.04, reach, radius));
		crack_line = max(crack_line, (1.0 - smoothstep(0.0, 0.005, across)) * grown);
	}
	crack_line *= inside * step(0.001, cracks) * (1.0 - shattered);

	// --- stack them: frost, then the cracks, then the shatter flash over everything
	vec3 color = frost_color;
	float alpha = frost_alpha;
	color = mix(color, CRACK_COLOR, crack_line);
	alpha = 1.0 - (1.0 - alpha) * (1.0 - crack_line * 0.95);
	float flash_alpha = flash * 0.9 * (1.0 - smoothstep(0.05, 0.45, radius)) * inside; // round, strongest in the middle
	color = mix(color, vec3(0.95, 1.0, 1.0), flash_alpha);
	alpha = 1.0 - (1.0 - alpha) * (1.0 - flash_alpha);

	COLOR = vec4(color, alpha);
}
