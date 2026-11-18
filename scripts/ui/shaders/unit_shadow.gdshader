shader_type canvas_item;
// The shadow destroy: the dark closes in on ONE unit. Ink-black tendrils creep in from the edges of the
// card and the darkness shuts over it like an eye closing, a cold pale rim glowing along its edge; the unit
// dissolves inside it, then the dark frays into wisps that rise away.
// Drawn on a small ColorRect over the card, a bit bigger than it. FxCasts._shadow_unit tweens
// `progress` (the dark closing in) and `fade` (the dark fraying away).
// Coordinates: UV.y = 0 at the top of the rectangle, 1 at the bottom.

uniform float progress = 0.0; // 0 = nothing yet, 1 = the dark covers the card
uniform float fade = 1.0; // 1 = there, 0 = gone
uniform float aspect = 0.7; // rectangle width / height, so the smoke is round

const vec3 INK = vec3(0.02, 0.02, 0.035);
const vec3 SMOKE = vec3(0.11, 0.11, 0.15);
const vec3 RIM_GLOW = vec3(0.62, 0.66, 0.8);

// a random number from 0 to 1 for each grid cell
float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

// smooth noise: random values on a grid, blended between the corners
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 inside = fract(p);
	vec2 blend = inside * inside * (3.0 - 2.0 * inside);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

void fragment() {
	vec2 surface = vec2(UV.x * aspect, UV.y);
	vec2 from_center = (UV - 0.5) * vec2(aspect, 1.0) * 2.0;
	// how far this pixel is from the middle of the card, 0 in the middle and about 1 at the edges
	float distance_to_middle = length(from_center * vec2(0.9, 0.7));

	// the dark closes from the outside in: smoke noise makes the closing edge ragged, with tendrils
	float ragged = noise(surface * 6.0 + vec2(0.0, TIME * 0.5)) * 0.6 + noise(surface * 14.0 - TIME * 0.4) * 0.4;
	float angle = atan(from_center.y, from_center.x);
	float tendrils = noise(vec2(angle * 2.5 + 3.0, TIME * 0.3)) * 0.35;
	float closing_edge = 1.25 - progress * 1.45 + (ragged - 0.5) * 0.45 - tendrils * (1.0 - progress);
	float covered = smoothstep(closing_edge - 0.1, closing_edge + 0.02, distance_to_middle);
	// the glowing rim right at the closing edge
	float rim = exp(-pow((distance_to_middle - closing_edge - 0.03) / 0.05, 2.0)) * step(0.03, progress) * (1.0 - smoothstep(0.9, 1.0, progress));

	// color: ink in the middle of the dark, smoke gray where it is thin, cold glow on the rim
	float thickness = smoothstep(0.0, 0.5, ragged + (1.0 - distance_to_middle) * 0.4);
	vec3 color = mix(SMOKE, INK, thickness);
	color = mix(color, RIM_GLOW, rim * 0.6);

	// wisps rising off the card: faint dark streaks drifting up
	float wisps = noise(vec2(surface.x * 6.0, UV.y * 3.0 + TIME * 1.1)) * progress * (1.0 - smoothstep(0.0, 0.7, UV.y));
	color = mix(color, SMOKE, wisps * 0.5 * (1.0 - covered));

	float alpha = covered * (0.7 + 0.25 * thickness);
	alpha = max(alpha, rim * 0.7);
	alpha = max(alpha, wisps * 0.22);
	// fraying away: patches of the dark vanish, the thick ink last
	alpha *= smoothstep(0.0, 0.3, fade - noise(surface * 12.0) * 0.5 + 0.3);
	COLOR = vec4(color, clamp(alpha, 0.0, 0.94));
}
