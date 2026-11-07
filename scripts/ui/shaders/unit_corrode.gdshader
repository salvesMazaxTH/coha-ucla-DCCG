shader_type canvas_item;
// The poison destroy (Ponto Final sem Vírgula): thick venom oozes down ONE unit from its top edge in
// drips, bubbling, and eats holes through the card with glowing acid-green rims while fumes rise;
// the unit dissolves inside it, then the venom fades away.
// Drawn on a small ColorRect over the card, a bit bigger than it. FxCasts._corrode_unit tweens
// `progress` (the venom running down and eating in) and `fade` (the venom fading away).
// Coordinates: UV.y = 0 at the top of the rectangle, 1 at the bottom.

uniform float progress = 0.0; // 0 = nothing yet, 1 = the venom covers the card
uniform float fade = 1.0; // 1 = there, 0 = gone
uniform float aspect = 0.7; // rectangle width / height, so the drips and bubbles are round

const float DRIP_COLUMNS = 9.0;
const vec3 VENOM_DARK = vec3(0.22, 0.06, 0.32);
const vec3 VENOM = vec3(0.54, 0.25, 0.72);
const vec3 VENOM_SHINE = vec3(0.85, 0.62, 1.0);
const vec3 ACID = vec3(0.62, 1.0, 0.32);
const vec3 HOLE = vec3(0.04, 0.01, 0.06);

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

// how far down the venom reaches at this x: a wobbly sheet from the top, with long drips hanging
// from it (each drip ends in a round drop). Returns the venom amount 0..1 at this pixel.
float venom_cover(vec2 uv) {
	float sheet_depth = progress * 0.35 + (noise(vec2(uv.x * 7.0, 1.0)) - 0.5) * 0.08;
	float sheet = smoothstep(sheet_depth + 0.01, sheet_depth - 0.01, uv.y);
	// drips: one per column, of different lengths and widths
	float column = floor(uv.x * DRIP_COLUMNS);
	float in_column = fract(uv.x * DRIP_COLUMNS) - 0.5; // -0.5..0.5 across the column
	float drip_length = progress * (0.45 + 0.75 * hash(vec2(column, 1.0)));
	float drip_width = 0.16 + 0.14 * hash(vec2(column, 2.0)); // as a part of the column
	// the drip is thinner higher up near the sheet, fatter toward its drop
	float body = step(abs(in_column), drip_width * (0.6 + 0.4 * clamp(uv.y / max(drip_length, 0.01), 0.0, 1.0))) * step(uv.y, drip_length);
	vec2 to_drop = vec2(in_column / DRIP_COLUMNS * aspect, uv.y - drip_length);
	float drop = 1.0 - smoothstep(0.0, 0.006, length(to_drop) - drip_width * 1.3 / DRIP_COLUMNS * aspect);
	return max(sheet, max(body, drop));
}

void fragment() {
	vec2 surface = vec2(UV.x * aspect, UV.y);
	float cover = venom_cover(UV);
	vec4 result = vec4(0.0);

	// holes eaten through the card where the venom has been for a while (they open as progress grows)
	float eaten = noise(surface * 7.0) * 0.7 + noise(surface * 19.0) * 0.3;
	float hole_threshold = progress * 0.4 - 0.08;
	float hole = smoothstep(hole_threshold, hole_threshold - 0.04, eaten) * step(UV.y, 0.95);
	float hole_rim = exp(-pow((eaten - hole_threshold) / 0.025, 2.0)) * step(0.05, progress);

	// the venom: dark purple, glossy on top, a little brighter where it is thick
	float thickness = noise(surface * vec2(10.0, 4.0) - vec2(0.0, TIME * 0.4));
	vec3 venom_color = mix(VENOM_DARK, VENOM, 0.4 + 0.6 * thickness);
	venom_color = mix(venom_color, VENOM_SHINE, smoothstep(0.72, 0.9, thickness) * 0.6);
	// bubbles: small rings rising inside the venom and popping
	vec2 bubble_grid = surface * 18.0 + vec2(0.0, TIME * 1.3);
	vec2 bubble_cell = floor(bubble_grid);
	float bubble_ring = abs(length(fract(bubble_grid) - 0.5) - 0.18 * hash(bubble_cell + 4.0) - 0.08);
	float bubble = (1.0 - smoothstep(0.0, 0.04, bubble_ring)) * step(0.72, hash(bubble_cell)) * cover;
	venom_color = mix(venom_color, ACID, bubble * 0.8);

	result = vec4(venom_color, cover * 0.9);
	// the holes show through as near-black with an acid glow around them
	result.rgb = mix(result.rgb, HOLE, hole);
	result.a = max(result.a, hole * 0.85);
	result.rgb = mix(result.rgb, ACID, hole_rim * 0.9);
	result.a = max(result.a, hole_rim * 0.9);

	// fumes: faint greenish wisps drifting up over the top part
	float fumes = noise(vec2(surface.x * 5.0, UV.y * 3.0 + TIME * 0.9)) * (1.0 - smoothstep(0.0, 0.6, UV.y)) * progress;
	result.rgb = mix(result.rgb, mix(ACID, VENOM_SHINE, 0.5), fumes * 0.4 * (1.0 - result.a));
	result.a = max(result.a, fumes * 0.25);

	// fading away: the venom thins out in patches
	result.a *= smoothstep(0.0, 0.3, fade - noise(surface * 12.0) * 0.5 + 0.3);
	COLOR = result;
}
