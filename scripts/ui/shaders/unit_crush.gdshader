shader_type canvas_item;
// The stone destroy (Desabamento Oportuno): boulders fall from above one after another and pile up
// on ONE unit, each throwing a puff of dust where it lands; the unit dissolves under the pile, then
// the rocks crumble into dust and blow away.
// Drawn on a small ColorRect over the card, taller than it: the top part is empty sky the rocks fall
// through (see FxCasts._crush_unit). FxCasts tweens `progress` (the rockfall) and `fade` (crumbling).
// Coordinates: UV.y = 0 at the top of the rectangle, 1 at the bottom.

uniform float progress = 0.0; // 0 = nothing fell yet, 1 = every rock has landed
uniform float fade = 1.0; // 1 = the pile is there, 0 = all crumbled away
uniform float aspect = 0.6; // rectangle width / height, so the rocks are round and not stretched
uniform float card_top = 0.3; // where the card's top edge is in the rectangle (UV.y)

const int ROCK_COUNT = 8;
const float FALL_SHARE = 0.32; // how much of the timeline one rock takes to fall
const vec3 ROCK_DARK = vec3(0.24, 0.19, 0.14);
const vec3 ROCK_MID = vec3(0.50, 0.40, 0.28);
const vec3 ROCK_LIGHT = vec3(0.74, 0.63, 0.47);
const vec3 DUST = vec3(0.66, 0.58, 0.47);

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

// distance to a rough rock shape centered at 0 (negative = inside): an irregular, chipped polygon
float rock_shape(vec2 p, float size, float rock_seed) {
	float angle = hash(vec2(rock_seed, 1.0)) * 6.283;
	p = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * p;
	p.x *= 0.8 + 0.4 * hash(vec2(rock_seed, 2.0)); // some rocks wider, some taller
	vec2 folded = abs(p);
	// a box with its corners cut (an octagon), then roughened
	float box = max(folded.x, folded.y);
	float cut = (folded.x + folded.y) * 0.74;
	float rough = (noise(p / size * 3.0 + rock_seed) - 0.5) * 0.22 * size;
	return max(box, cut) - size + rough;
}

void fragment() {
	vec2 surface = vec2(UV.x * aspect, UV.y);
	vec4 result = vec4(0.0);
	float dust = 0.0;
	for (int i = 0; i < ROCK_COUNT; i++) {
		float rock_seed = float(i) * 7.31 + 1.7;
		float drop_moment = float(i) / float(ROCK_COUNT) * (1.0 - FALL_SHARE);
		float fall = clamp((progress - drop_moment) / FALL_SHARE, 0.0, 1.0);
		if (fall <= 0.0) {
			continue;
		}
		// where it comes to rest: the first rocks at the bottom of the card, the later ones on top of them
		float pile_height = float(i) / float(ROCK_COUNT);
		float size = (0.11 + 0.06 * hash(vec2(rock_seed, 4.0))) * (1.0 - pile_height * 0.3);
		vec2 rest = vec2(
			// spread across the card with the golden ratio, so no two rocks stack in the same column
			(0.2 + 0.6 * fract(float(i) * 0.618 + 0.15 * hash(vec2(rock_seed, 3.0)))) * aspect,
			mix(0.9, card_top + 0.15, pile_height) + (hash(vec2(rock_seed, 6.0)) - 0.5) * 0.06);
		// falling with gravity from above the rectangle
		vec2 position = vec2(rest.x, mix(-size * 2.0, rest.y, fall * fall));
		float edge = rock_shape(surface - position, size, rock_seed);
		// crumbling: bits of the rock vanish in noise as `fade` falls
		float crumble = step(noise((surface - position) * 22.0 + rock_seed) * 0.8 + 0.1, fade);
		float inside = (1.0 - smoothstep(-0.004, 0.004, edge)) * crumble;
		if (inside > 0.0) {
			// light from the top-left: the upper-left side of each rock is lighter, plus a dark outline
			vec2 local = (surface - position) / size;
			float light = clamp(0.55 - (local.x + local.y) * 0.35, 0.0, 1.0);
			vec3 color = mix(ROCK_MID, ROCK_LIGHT, light);
			color = mix(color, ROCK_DARK, smoothstep(-0.02, 0.0, edge) * 0.8);
			// cracks and grain
			float grain = noise(surface * 60.0 + rock_seed);
			color *= 0.82 + 0.3 * grain;
			color = mix(color, ROCK_DARK, smoothstep(0.08, 0.02, abs(noise(surface * 14.0 + rock_seed) - 0.5)) * 0.6);
			result = vec4(color, inside);
		}
		// the dust puff where it landed, spreading and thinning out after the hit
		float since_landing = (progress - drop_moment - FALL_SHARE) * 3.0 + (1.0 - fade) * 1.5;
		if (fall >= 1.0) {
			vec2 to_puff = (surface - rest - vec2(0.0, size * 0.6)) / vec2(1.0, 0.55);
			float puff_radius = size * (1.0 + since_landing * 1.6);
			float puff = (1.0 - smoothstep(puff_radius * 0.3, puff_radius, length(to_puff))) * noise(surface * 18.0 + vec2(0.0, TIME));
			dust = max(dust, puff * clamp(1.0 - since_landing * 0.7, 0.0, 1.0));
		}
	}
	// the dust goes behind the rocks
	float dust_alpha = dust * 0.75 * (1.0 - result.a);
	result.rgb = result.rgb * result.a + DUST * dust_alpha;
	result.a = result.a + dust_alpha;
	result.rgb /= max(result.a, 0.0001);
	COLOR = result;
}
