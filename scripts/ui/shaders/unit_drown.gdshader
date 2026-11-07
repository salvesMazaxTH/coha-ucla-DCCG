shader_type canvas_item;
// The water destroy (Afogar): water rises over ONE unit like a tank filling up, bubbles escaping,
// holds it under while it dissolves, and drains away in patches. Drawn on a small ColorRect over the
// card. FxCasts._drown_unit tweens `level` (how high the water rose) and `drain` (the water leaving).
// Coordinates: UV.y = 0 at the top of the rectangle, 1 at the bottom.

uniform float level = 0.0; // 0 = no water yet, 1 = the card is fully under water
uniform float drain = 0.0; // 0 = under water, 1 = all the water is gone
uniform float aspect = 0.75; // rectangle width / height, so the bubbles are round, not stretched

const vec3 DEEP = vec3(0.02, 0.16, 0.32);
const vec3 SHALLOW = vec3(0.07, 0.42, 0.62);
const vec3 FOAM = vec3(0.90, 0.97, 1.0);

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

// the bright net of light that dances on the bottom of a pool (same trick as water_surge)
float caustics(vec2 uv, float time) {
	vec2 p = mod(uv * 6.28318, 6.28318) - 250.0;
	vec2 bent = p;
	float light = 1.0;
	for (int round_index = 0; round_index < 3; round_index++) {
		float round_time = time * (1.0 - 3.5 / float(round_index + 1));
		bent = p + vec2(cos(round_time - bent.x) + sin(round_time + bent.y), sin(round_time - bent.y) + cos(round_time + bent.x));
		light += 1.0 / length(vec2(p.x / (sin(bent.x + round_time) / 0.005), p.y / (cos(bent.y + round_time) / 0.005)));
	}
	light = 1.17 - pow(light / 3.0, 1.4);
	return pow(abs(light), 8.0);
}

void fragment() {
	float time = TIME;
	float height = 1.0 - UV.y; // 0 = the bottom of the rectangle, 1 = the top
	vec2 surface = vec2(UV.x * aspect, UV.y);

	// the water surface: where it is now, sloshing from side to side
	float slosh = 0.03 * sin(UV.x * 12.0 + time * 6.0) + 0.04 * (noise(vec2(UV.x * 7.0, time * 2.5)) - 0.5);
	float water_line = level * 1.02 - 0.06 + slosh;
	float below = water_line - height; // > 0 = under water
	float under = smoothstep(0.0, 0.012, below);

	// the body: deeper (darker) toward the bottom, with ripples and light on it
	float ripples = noise(surface * 6.0 + vec2(0.0, time * 1.2)) * 0.6 + noise(surface * 13.0 - vec2(time * 1.0, 0.0)) * 0.4;
	vec3 water = mix(SHALLOW, DEEP, clamp(below * 1.4, 0.0, 1.0) * 0.8 + ripples * 0.25);
	water += vec3(0.55, 0.85, 1.0) * caustics(surface * 0.9 + vec2(0.0, time * 0.05), time * 0.6) * 0.5;

	// bubbles escaping: thin round rings in some cells of a grid that rises; each column rises at its
	// own speed and each bubble sits at a random spot in its cell, so they never line up in rows
	float bubble_column = floor(surface.x * 7.0);
	float column_speed = 1.6 + hash(vec2(bubble_column, 4.2)) * 1.6;
	vec2 bubble_grid = vec2(surface.x * 7.0, surface.y * 7.0 + time * column_speed + hash(vec2(bubble_column, 8.5)) * 5.0);
	vec2 bubble_cell = floor(bubble_grid);
	vec2 bubble_offset = fract(bubble_grid) - 0.5 - (vec2(hash(bubble_cell + 5.3), hash(bubble_cell + 2.7)) - 0.5) * 0.5;
	bubble_offset.x += 0.08 * sin(time * 5.0 + hash(bubble_cell) * 20.0); // they wobble as they rise
	float bubble_size = mix(0.07, 0.16, hash(bubble_cell + 1.9));
	float bubble_distance = length(bubble_offset);
	float bubble_ring = smoothstep(bubble_size - 0.05, bubble_size, bubble_distance) * (1.0 - smoothstep(bubble_size, bubble_size + 0.03, bubble_distance));
	float bubbles = bubble_ring * step(0.7, hash(bubble_cell)) * smoothstep(0.03, 0.12, below);
	water = mix(water, FOAM, bubbles * 0.8);

	// the foam: a white band on the surface line
	float foam = (1.0 - smoothstep(0.0, 0.06, below)) * (0.75 + 0.25 * ripples);
	water = mix(water, FOAM, foam);

	// draining: the water leaves in patches (each pixel has its own moment to dry)
	float dry_moment = noise(surface * 5.0) * 0.7 + noise(surface * 13.0) * 0.3;
	float still_wet = 1.0 - smoothstep(dry_moment - 0.1, dry_moment + 0.05, drain * 1.15);

	// soft side edges, so it is a body of water around the card, not a hard box
	float from_middle = abs(UV.x - 0.5) * 2.0;
	float sides = 1.0 - smoothstep(0.8, 1.0, from_middle);

	COLOR = vec4(water, under * mix(0.8, 0.95, foam) * still_wet * sides);
}
