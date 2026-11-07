shader_type canvas_item;
// The plant destroy (Capina Seletiva): vines sprout from the bottom of ONE unit and climb up over it,
// swaying, with leaves opening along them and moss darkening the card; the unit is taken under them,
// then the vines wither brown and fall apart.
// Drawn on a small ColorRect over the card, a bit bigger than it. FxCasts._overgrow_unit tweens
// `progress` (how far the vines grew) and `fade` (the vines withering away).
// Coordinates: UV.y = 0 at the top of the rectangle, 1 at the bottom.

uniform float progress = 0.0; // 0 = nothing yet, 1 = the vines cover the card
uniform float fade = 1.0; // 1 = green and alive, 0 = withered and gone
uniform float aspect = 0.65; // rectangle width / height, so the leaves are not stretched

const int VINE_COUNT = 6;
const float LEAF_SPACING = 0.11; // the distance between two leaves along a vine
const vec3 STEM_GREEN = vec3(0.17, 0.38, 0.14);
const vec3 LEAF_GREEN = vec3(0.35, 0.70, 0.29);
const vec3 LEAF_LIGHT = vec3(0.62, 0.88, 0.42);
const vec3 MOSS = vec3(0.10, 0.22, 0.08);
const vec3 WITHERED = vec3(0.42, 0.31, 0.15);

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

// the x of a vine at a given height (it winds left and right as it climbs, and sways a little)
float vine_x(float height, float base_x, float vine_seed) {
	float sway = sin(TIME * 1.6 + vine_seed) * 0.012 * height;
	return base_x + sin(height * (7.0 + 4.0 * hash(vec2(vine_seed, 1.0))) + vine_seed) * 0.09 + sway;
}

void fragment() {
	float height = 1.0 - UV.y; // 0 = the bottom of the rectangle, 1 = the top
	vec4 result = vec4(0.0);

	// moss: the card darkens in green patches, from the bottom up, as the vines grow
	float moss_reach = progress * 1.1 - height + (noise(UV * 9.0) - 0.5) * 0.35;
	float moss = smoothstep(0.0, 0.25, moss_reach) * 0.4;
	result = vec4(MOSS, moss);

	for (int i = 0; i < VINE_COUNT; i++) {
		float vine_seed = float(i) * 5.17 + 0.9;
		float base_x = (float(i) + 0.5) / float(VINE_COUNT) + (hash(vec2(vine_seed, 2.0)) - 0.5) * 0.08;
		// some vines climb all the way, some stop lower
		float vine_length = (0.7 + 0.35 * hash(vec2(vine_seed, 3.0))) * progress;
		if (height > vine_length + 0.06) {
			continue;
		}
		// the stem: thick at the root, thin at the growing tip
		float stem_x = vine_x(height, base_x, vine_seed);
		float distance_to_stem = abs(UV.x - stem_x) * aspect;
		float stem_width = mix(0.022, 0.006, clamp(height / max(vine_length, 0.01), 0.0, 1.0));
		float stem = (1.0 - smoothstep(stem_width - 0.003, stem_width + 0.003, distance_to_stem)) * step(height, vine_length);
		if (stem > 0.0) {
			// rounded look: lighter along the middle of the stem
			vec3 stem_color = mix(STEM_GREEN, LEAF_GREEN, 0.5 * (1.0 - distance_to_stem / stem_width));
			result = vec4(mix(result.rgb, stem_color, stem), max(result.a, stem));
		}
		// the nearest leaf: leaves sit at regular heights, alternating sides
		float leaf_index = floor(height / LEAF_SPACING + 0.5);
		float leaf_height = leaf_index * LEAF_SPACING + hash(vec2(vine_seed, leaf_index)) * 0.03;
		// a leaf only opens once the vine has grown past it
		float leaf_growth = clamp((vine_length - leaf_height) / 0.08, 0.0, 1.0);
		if (leaf_growth > 0.0 && leaf_index > 0.0) {
			float side = mod(leaf_index, 2.0) < 0.5 ? 1.0 : -1.0;
			vec2 leaf_base = vec2(vine_x(leaf_height, base_x, vine_seed) * aspect, leaf_height);
			vec2 leaf_direction = normalize(vec2(side, 0.7));
			vec2 to_pixel = vec2(UV.x * aspect, height) - leaf_base;
			// the pixel in the leaf's own frame: along its length and across it
			float along = dot(to_pixel, leaf_direction);
			float across = dot(to_pixel, vec2(-leaf_direction.y, leaf_direction.x));
			float leaf_size = 0.05 * leaf_growth;
			// a pointed ellipse from the base to the tip
			float shape = (along / leaf_size - 0.5) * (along / leaf_size - 0.5) * 4.0 + pow(across / (leaf_size * 0.38), 2.0);
			float leaf = (1.0 - smoothstep(0.85, 1.0, shape)) * step(0.0, along);
			if (leaf > 0.0) {
				// a lighter vein down the middle of the leaf
				float vein = 1.0 - smoothstep(0.0, leaf_size * 0.08, abs(across));
				vec3 leaf_color = mix(LEAF_GREEN, LEAF_LIGHT, vein * 0.7 + 0.2 * hash(vec2(vine_seed + leaf_index, 7.0)));
				result = vec4(mix(result.rgb, leaf_color, leaf), max(result.a, leaf));
			}
		}
	}
	// withering: green turns brown as `fade` drops, then the plants break apart in patches
	float wither = smoothstep(1.0, 0.45, fade);
	result.rgb = mix(result.rgb, WITHERED * (0.8 + 0.4 * noise(UV * 30.0)), wither);
	result.a *= step(noise(UV * vec2(14.0, 20.0)) * 0.5, fade - 0.05) * smoothstep(0.0, 0.25, fade);
	COLOR = result;
}
