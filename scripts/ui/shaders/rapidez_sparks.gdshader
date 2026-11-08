shader_type canvas_item;
// Rapidez during combat: electric arcs crackle around the card's frame. Jagged white-hot bolts appear
// at random spots, hug the frame for a moment and jump to somewhere else, and short forks shoot outward.
// The bolt's shape is re-rolled about 14 times a second, which is what makes it look like crackling electricity.
// Drawn on a ColorRect a bit bigger than the card face (see CardView._place_rapidez_sparks);
// the GPU animates it, so the card itself never has to redraw.

uniform vec2 rect_size = vec2(200.0, 280.0); // the ColorRect, in pixels
uniform float margin = 8.0; // pixels of room around the card face, for the bolts that fly outside
uniform float corner_radius = 10.0; // the card frame's rounded corners, in pixels
uniform float base_pixel = 1.0; // one card base pixel (the "s" in CardView), in screen pixels
uniform float phase = 0.0; // per-card time offset, so two fast cards don't crackle in lockstep

const vec3 BOLT_GLOW = vec3(0.45, 0.80, 1.0); // electric blue halo
const vec3 BOLT_CORE = vec3(0.95, 0.99, 1.0); // white-hot center
const int ARCS = 3; // bolts crawling along the frame at the same time
const float ARC_MOVES_PER_SECOND = 3.0; // how often a bolt jumps to a new place
const float SHAPE_CHANGES_PER_SECOND = 14.0; // how often the zigzag is re-rolled
const float KINK_LENGTH = 4.5; // base pixels between two kinks of the zigzag
const float KINK_HEIGHT = 3.0; // base pixels: how far the zigzag swings in and out
const float FORK_CELLS = 16.0; // places around the frame where a fork can appear
const float FORK_CHANGES_PER_SECOND = 9.0;

// distance to a rounded box centered at 0 (negative = inside)
float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// a pseudo-random number from 0 to 1 for a number
float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

// random zigzag from 0 to 1: straight lines between random points, so the kinks stay sharp
float zigzag(float x, float seed) {
	float whole = floor(x);
	return mix(hash(whole + seed), hash(whole + 1.0 + seed), fract(x));
}

// how far (in base pixels) the bolt swings away from its middle line, at position x along the frame
float bolt_swing(float x, float seed) {
	float big = zigzag(x, seed) - 0.5;
	float small = zigzag(x * 2.7, seed + 31.0) - 0.5;
	return (big * 2.0 + small * 0.8) * KINK_HEIGHT;
}

void fragment() {
	float t = TIME + phase;
	vec2 half_face = (rect_size - vec2(2.0 * margin)) * 0.5;
	vec2 p = UV * rect_size - rect_size * 0.5; // pixels from the card's center
	float edge = rounded_box(p, half_face, corner_radius); // < 0 = on the card

	// distance travelled along the frame in pixels, clockwise from the top-left corner (same speed on every side)
	float width = half_face.x * 2.0;
	float height = half_face.y * 2.0;
	float perimeter = 2.0 * (width + height);
	float along;
	if (abs(p.x) * half_face.y > abs(p.y) * half_face.x) {
		along = p.x > 0.0 ? width + (p.y + half_face.y) : 2.0 * width + height + (half_face.y - p.y);
	} else {
		along = p.y < 0.0 ? p.x + half_face.x : width + height + (half_face.x - p.x);
	}
	float around = along / perimeter; // 0..1

	float result_strength = 0.0;
	float core_amount = 0.0;
	float shape_step = floor(t * SHAPE_CHANGES_PER_SECOND);

	// bolts that hug the frame: each lives a short while at one spot, then jumps to a new one
	float middle_line = 2.5 * base_pixel;
	for (int i = 0; i < ARCS; i++) {
		float arc_index = float(i);
		float life = floor(t * ARC_MOVES_PER_SECOND + arc_index * 1.7);
		float center = hash(life * 2.17 + arc_index * 5.0 + 3.0);
		float half_length = 0.045 + 0.06 * hash(life * 0.77 + arc_index * 9.0);
		float away = around - center;
		away -= round(away); // the frame is a loop
		float visible_part = smoothstep(half_length, half_length * 0.55, abs(away));

		float seed = hash(shape_step + arc_index * 31.0) * 90.0;
		float x = along / (KINK_LENGTH * base_pixel);
		float swing = bolt_swing(x, seed) * base_pixel;
		float slope = (bolt_swing(x + 0.05, seed) - bolt_swing(x - 0.05, seed)) / (0.1 * KINK_LENGTH); // steepness of the zigzag
		float line_distance = abs(edge - middle_line - swing) / sqrt(1.0 + slope * slope);

		float core = exp(-pow(line_distance / (0.75 * base_pixel), 2.0));
		float halo = exp(-pow(line_distance / (2.6 * base_pixel), 2.0)) * 0.35;
		float strength = (core + halo) * visible_part;
		core_amount = max(core_amount, core * visible_part);
		result_strength = max(result_strength, strength);
	}

	// short forks that shoot outward from the frame, each in its own spot, blinking on and off
	float cell_width = perimeter / FORK_CELLS;
	float cell = floor(along / cell_width);
	float fork_step = floor(t * FORK_CHANGES_PER_SECOND);
	float fork_on = step(0.62, hash(cell * 3.3 + fork_step * 7.1 + 1.0));
	float anchor = (0.25 + 0.5 * hash(cell + 7.0)) * cell_width + cell * cell_width;
	float fork_length = (5.0 + 7.0 * hash(cell + fork_step * 2.0 + 13.0)) * base_pixel;
	float out_distance = edge - middle_line; // how far the point is outside the middle line
	float lean = (hash(cell + fork_step * 5.0 + 21.0) - 0.5) * 1.2;
	float fork_seed = hash(cell + fork_step * 11.0) * 90.0;
	float fork_swing = (zigzag(out_distance / (2.5 * base_pixel), fork_seed) - 0.5) * 2.0 * 2.2 * base_pixel + lean * out_distance;
	float fork_distance = abs(along - anchor - fork_swing) / 1.3;
	float fork_fade = smoothstep(fork_length, fork_length * 0.3, out_distance) * step(0.0, out_distance);
	float fork_core = exp(-pow(fork_distance / (0.6 * base_pixel), 2.0)) * fork_fade * fork_on;
	core_amount = max(core_amount, fork_core);
	result_strength = max(result_strength, fork_core * 0.9);

	// never paint over the card face itself
	result_strength *= smoothstep(-1.0 * base_pixel, 0.5 * base_pixel, edge);
	vec3 result_color = mix(BOLT_GLOW, BOLT_CORE, clamp(core_amount * 1.4, 0.0, 1.0));
	COLOR = vec4(result_color, clamp(result_strength, 0.0, 1.0));
}
