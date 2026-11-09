shader_type canvas_item;
// The plant area cast (any card of the element vegetal that hurts a whole row of units): a thicket.
// Thorny vines sprout from the caster's edge of the arena and snake across it, leaves opening along them;
// they hold for a moment, then wither brown and break apart.
// Drawn on ONE ColorRect over the arena. FxCasts._vine_area tweens `progress` (the vines growing) and
// `fade` (the vines withering away). `from_bottom` flips it so the vines always grow from the caster's side.
// Coordinates: UV.y = 0 at the top of the arena. `depth` = 0 at the caster's side, 1 at the far side.
// Cost: 2 vines checked per pixel (the ones whose lane the pixel is in), no big loops.

uniform float progress = 0.0; // 0 = nothing yet, 1 = the vines reach the far side
uniform float fade = 1.0; // 1 = green and alive, 0 = withered and gone
uniform float aspect = 1.5; // arena width / height, so the leaves are not stretched
uniform float from_bottom = 0.0; // 1 = the caster is at the bottom, so the vines grow up

const float VINE_COUNT = 11.0; // vines side by side across the arena
const float LEAF_SPACING = 0.085; // the distance between two leaves along a vine (in depth)
const float THORN_SPACING = 0.042; // the distance between two thorns along a vine
const vec3 STEM_DARK = vec3(0.13, 0.27, 0.10);
const vec3 LEAF_GREEN = vec3(0.30, 0.64, 0.26);
const vec3 LEAF_LIGHT = vec3(0.62, 0.88, 0.42);
const vec3 THORN = vec3(0.42, 0.30, 0.16);
const vec3 WITHERED = vec3(0.42, 0.31, 0.15);

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

// the x (across the arena, in aspect units) of a vine at a given depth: it winds as it grows, and sways a little
float vine_x(float depth, float base_x, float seed) {
	float sway = sin(TIME * 1.5 + seed) * 0.02 * depth;
	return base_x + sin(depth * (9.0 + 5.0 * hash(vec2(seed, 1.0))) + seed) * 0.07 + sway;
}

void fragment() {
	float depth = from_bottom > 0.5 ? 1.0 - UV.y : UV.y;
	float x = UV.x * aspect;
	float lane_width = aspect / VINE_COUNT;
	float own_lane = floor(UV.x * VINE_COUNT);
	vec4 result = vec4(0.0);

	// a faint green shade on the ground, under the thicket, as it grows
	float reach = progress * 1.15 - depth + (noise(vec2(x * 3.0, depth * 3.0)) - 0.5) * 0.3;
	result = vec4(0.05, 0.14, 0.04, smoothstep(0.0, 0.3, reach) * 0.22);

	// the vine of this lane and of the one beside it (their leaves reach over the border)
	for (int side_lane = -1; side_lane <= 0; side_lane++) {
		float lane = own_lane + float(side_lane);
		if (lane < 0.0 || lane >= VINE_COUNT) {
			continue;
		}
		float seed = lane * 5.17 + 0.9;
		float base_x = (lane + 0.5) * lane_width + (hash(vec2(seed, 2.0)) - 0.5) * lane_width * 0.3;
		// some vines go all the way, some stop short
		float vine_length = (0.62 + 0.55 * hash(vec2(seed, 3.0))) * progress * 1.1;
		if (depth > vine_length + 0.08) {
			continue;
		}
		float stem_center = vine_x(depth, base_x, seed);
		float distance_to_stem = abs(x - stem_center);
		float stem_width = mix(0.024, 0.007, clamp(depth / max(vine_length, 0.01), 0.0, 1.0));
		float stem = (1.0 - smoothstep(stem_width - 0.003, stem_width + 0.003, distance_to_stem)) * step(depth, vine_length);
		if (stem > 0.0) {
			vec3 stem_color = mix(STEM_DARK, LEAF_GREEN, 0.45 * (1.0 - distance_to_stem / stem_width));
			result = vec4(mix(result.rgb, stem_color, stem), max(result.a, stem));
		}

		// thorns: small brown spikes sticking out of the stem, alternating sides
		float thorn_index = floor(depth / THORN_SPACING + 0.5);
		float thorn_depth = thorn_index * THORN_SPACING;
		if (thorn_index > 1.0 && thorn_depth < vine_length - 0.02) {
			float thorn_side = mod(thorn_index, 2.0) < 0.5 ? 1.0 : -1.0;
			vec2 from_thorn = vec2(x - vine_x(thorn_depth, base_x, seed) - thorn_side * stem_width * 0.8, depth - thorn_depth);
			// a thin triangle pointing outward and a little forward
			float along = from_thorn.x * thorn_side;
			float across = from_thorn.y - along * 0.5;
			float thorn_length = 0.022;
			float thorn = (1.0 - smoothstep(0.0, thorn_length * (1.0 - clamp(along / thorn_length, 0.0, 1.0)) * 0.4 + 0.0015, abs(across))) * step(0.0, along) * step(along, thorn_length);
			result = vec4(mix(result.rgb, THORN, thorn), max(result.a, thorn));
		}

		// the nearest leaf: leaves open once the vine has grown past them
		float leaf_index = floor(depth / LEAF_SPACING + 0.5);
		float leaf_depth = leaf_index * LEAF_SPACING + hash(vec2(seed, leaf_index)) * 0.025;
		float leaf_growth = clamp((vine_length - leaf_depth) / 0.1, 0.0, 1.0);
		if (leaf_growth > 0.0 && leaf_index > 1.0) {
			float leaf_side = mod(leaf_index, 2.0) < 0.5 ? 1.0 : -1.0;
			vec2 leaf_base = vec2(vine_x(leaf_depth, base_x, seed), leaf_depth);
			vec2 leaf_direction = normalize(vec2(leaf_side, 0.8));
			vec2 to_pixel = vec2(x, depth) - leaf_base;
			float along = dot(to_pixel, leaf_direction);
			float across = dot(to_pixel, vec2(-leaf_direction.y, leaf_direction.x));
			float leaf_size = 0.07 * leaf_growth;
			// a pointed ellipse from the base to the tip
			float shape = (along / leaf_size - 0.5) * (along / leaf_size - 0.5) * 4.0 + pow(across / (leaf_size * 0.36), 2.0);
			float leaf = (1.0 - smoothstep(0.85, 1.0, shape)) * step(0.0, along);
			if (leaf > 0.0) {
				float vein = 1.0 - smoothstep(0.0, leaf_size * 0.07, abs(across));
				vec3 leaf_color = mix(LEAF_GREEN, LEAF_LIGHT, vein * 0.7 + 0.25 * hash(vec2(seed + leaf_index, 7.0)));
				result = vec4(mix(result.rgb, leaf_color, leaf), max(result.a, leaf));
			}
		}
	}

	// withering: green turns brown as `fade` drops, then the plants break apart in patches
	float wither = smoothstep(1.0, 0.45, fade);
	result.rgb = mix(result.rgb, WITHERED * (0.8 + 0.4 * noise(vec2(x, UV.y) * 30.0)), wither);
	result.a *= step(noise(vec2(x, UV.y) * vec2(10.0, 14.0)) * 0.5, fade - 0.05) * smoothstep(0.0, 0.25, fade);
	COLOR = vec4(result.rgb, clamp(result.a, 0.0, 0.95));
}
