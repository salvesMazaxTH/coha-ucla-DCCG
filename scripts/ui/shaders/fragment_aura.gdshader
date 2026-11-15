shader_type canvas_item;
// Fragmentos de Rai'Emofitir on a unit: the card looks like it is coming apart. Violet cracks glow and
// flicker across the face, a violet rim breathes around the frame, and small shards drift upward.
// More fragments = more cracks and more shards. The cracks are the borders of a slowly wobbling
// cell pattern, and each border is either shown or hidden by a random number compared to `intensity`.
// Drawn on a ColorRect a bit bigger than the card face (see CardView._place_fragment_aura);
// the GPU animates it, so the card itself never has to redraw.

uniform vec2 rect_size = vec2(200.0, 280.0); // the ColorRect, in pixels
uniform float margin = 6.0; // pixels of room around the card face, for the halo
uniform float corner_radius = 10.0; // the card frame's rounded corners, in pixels
uniform float base_pixel = 1.0; // one card base pixel (the "s" in CardView), in screen pixels
uniform float phase = 0.0; // per-card time offset, so two cards don't pulse in lockstep
uniform float intensity = 0.2; // 0..1, grows with the number of fragments

const vec3 VIOLET = vec3(0.65, 0.24, 1.0);
const vec3 WHITE_VIOLET = vec3(0.94, 0.82, 1.0);
const float CELL_SIZE = 34.0; // base pixels between two crack junctions
const int MAX_SHARDS = 8;

// distance to a rounded box centered at 0 (negative = inside)
float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// a pseudo-random number from 0 to 1 for a number
float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

vec2 hash_pair(vec2 cell) {
	vec2 mixed = vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)));
	return fract(sin(mixed) * 43758.5453);
}

void fragment() {
	float t = TIME + phase;
	vec2 face_size = rect_size - vec2(2.0 * margin);
	vec2 p = UV * rect_size - rect_size * 0.5; // pixels from the card's center
	float edge = rounded_box(p, face_size * 0.5, corner_radius); // < 0 = on the card
	float on_card = 1.0 - smoothstep(-0.5 * base_pixel, 0.5 * base_pixel, edge);

	// cracks: the two nearest wobbling points tell how close this pixel is to a border between cells
	vec2 grid = p / (CELL_SIZE * base_pixel);
	vec2 cell = floor(grid);
	vec2 local = fract(grid);
	float nearest = 8.0;
	float second = 8.0;
	float nearest_id = 0.0;
	float second_id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 random_pair = hash_pair(cell + offset);
			vec2 point = offset + 0.5 + 0.38 * sin(t * 0.5 + random_pair * 6.2831853);
			float distance_to_point = length(point - local);
			float point_id = hash(random_pair.x * 91.7 + random_pair.y * 17.3);
			if (distance_to_point < nearest) {
				second = nearest;
				second_id = nearest_id;
				nearest = distance_to_point;
				nearest_id = point_id;
			} else if (distance_to_point < second) {
				second = distance_to_point;
				second_id = point_id;
			}
		}
	}
	float border_distance = second - nearest;
	float border_id = fract((nearest_id + second_id) * 7.31); // same number from both sides of a border
	float shown = step(border_id, 0.18 + 0.55 * intensity);
	float flicker = 0.55 + 0.45 * sin(t * 2.4 + border_id * 20.0);
	float crack_core = (1.0 - smoothstep(0.0, 0.06, border_distance)) * shown * flicker;
	float crack_glow = (1.0 - smoothstep(0.0, 0.2, border_distance)) * shown * flicker * 0.22;
	float crack_fade = smoothstep(0.0, -3.0 * base_pixel, edge); // cracks fade out toward the frame
	crack_core *= crack_fade;
	crack_glow *= crack_fade;

	// the breathing rim, inside the frame, and a faint halo just outside it
	float breath = 0.55 + 0.45 * sin(t * 2.0);
	float rim_inside = exp(edge / (2.5 * base_pixel)) * on_card * (0.25 + 0.4 * breath);
	float halo_outside = exp(-edge / (3.0 * base_pixel)) * (1.0 - on_card) * 0.35 * breath;

	// shards drifting upward, a few more of them for each extra fragment
	float shard_amount = 0.0;
	float shard_count = 2.0 + intensity * 5.0;
	for (int i = 0; i < MAX_SHARDS; i++) {
		float seed = float(i) * 7.13;
		float progress = fract(hash(seed + 2.0) + t * (0.07 + 0.1 * hash(seed + 1.0)));
		float shard_x = (hash(seed) - 0.5) * face_size.x * 0.85 + sin(t * 1.3 + seed) * 4.0 * base_pixel;
		float shard_y = face_size.y * (0.5 - progress);
		float size = (1.4 + 1.4 * hash(seed + 3.0)) * base_pixel;
		float diamond = abs(p.x - shard_x) + abs(p.y - shard_y); // a diamond is a circle in this distance
		float shard = smoothstep(size, size * 0.4, diamond) * sin(3.14159265 * progress);
		shard_amount = max(shard_amount, shard * step(float(i), shard_count));
	}
	shard_amount *= on_card;

	float core_amount = max(crack_core, shard_amount);
	float strength = clamp(crack_core * 0.85 + crack_glow + rim_inside + halo_outside + shard_amount * 0.9, 0.0, 1.0);
	vec3 result_color = mix(VIOLET, WHITE_VIOLET, clamp(core_amount * 1.2, 0.0, 1.0));
	COLOR = vec4(result_color, strength);
}
