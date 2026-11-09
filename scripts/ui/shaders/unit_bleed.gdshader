shader_type canvas_item;
// The blood destroy: ONE unit is bled dry. It mixes the two liquid destroys and adds its own mark:
// - its own: a wound opens in the middle of the card and veins race out of it across the whole card,
//   glowing at each heartbeat (`pulse`);
// - like the venom (unit_corrode): blood runs down from the top edge in drips;
// - like the water (unit_drown): a pool of blood rises from the bottom, dark bubbles rising in it.
// Drips and pool meet and cover the card, the unit dissolves inside, then the blood clots (darkens,
// cracks) and flakes away in pieces.
// Drawn on a small ColorRect over the card, a bit bigger than it. FxCasts._bleed_unit tweens
// `progress`, `pulse` (one beat = quick rise, slow fall) and `fade` (1 = there, 0 = flaked away).
// Cost: about 6 noise calls per pixel, no loops (it runs on phones).
// Coordinates: UV.y = 0 at the top of the rectangle, 1 at the bottom.

uniform float progress = 0.0; // 0 = nothing yet, 1 = the card is covered in blood
uniform float pulse = 0.0; // 0 = between heartbeats, 1 = the beat itself
uniform float fade = 1.0; // 1 = there, 0 = clotted and flaked away
uniform float aspect = 0.7; // rectangle width / height, so drips, bubbles and veins are not stretched

const float DRIP_COLUMNS = 8.0;
const vec3 BLOOD_DEEP = vec3(0.20, 0.01, 0.04);
const vec3 BLOOD = vec3(0.55, 0.04, 0.09);
const vec3 BLOOD_BRIGHT = vec3(0.95, 0.18, 0.20);
const vec3 SHINE = vec3(1.0, 0.70, 0.68);
const vec3 CLOTTED = vec3(0.16, 0.03, 0.03);

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

// The drips from the top edge (same shape as the venom's): a short wobbly sheet with drips of
// different lengths hanging from it, each ending in a round drop. Returns 0..1.
float drips(vec2 uv, float amount) {
	float sheet_depth = amount * 0.22 + (noise(vec2(uv.x * 7.0, 3.0)) - 0.5) * 0.06;
	float sheet = smoothstep(sheet_depth + 0.01, sheet_depth - 0.01, uv.y);
	float column = floor(uv.x * DRIP_COLUMNS);
	float in_column = fract(uv.x * DRIP_COLUMNS) - 0.5; // -0.5..0.5 across the column
	float drip_length = amount * (0.35 + 0.6 * hash(vec2(column, 1.0)));
	float drip_width = 0.13 + 0.13 * hash(vec2(column, 2.0)); // as a part of the column
	// thinner near the sheet, fatter toward its drop
	float body = step(abs(in_column), drip_width * (0.6 + 0.4 * clamp(uv.y / max(drip_length, 0.01), 0.0, 1.0))) * step(uv.y, drip_length);
	vec2 to_drop = vec2(in_column / DRIP_COLUMNS * aspect, uv.y - drip_length);
	float drop = 1.0 - smoothstep(0.0, 0.006, length(to_drop) - drip_width * 1.3 / DRIP_COLUMNS * aspect);
	return max(sheet, max(body, drop)) * step(0.01, amount);
}

void fragment() {
	vec2 surface = vec2(UV.x * aspect, UV.y);
	float time = TIME;

	// ---- the wound and its veins (this destroy's own mark) ----
	vec2 from_wound = surface - vec2(0.5 * aspect, 0.48);
	float radius = length(from_wound);
	float angle = atan(from_wound.y, from_wound.x);
	// the veins reach farther out as the blood spreads, with a little jump at each beat
	float vein_reach = smoothstep(0.0, 0.45, progress) * 0.85 + pulse * 0.04;
	// main veins: 7 lines out of the wound, bent by noise and twisting a little as they go
	float bend = (noise(surface * 5.0) - 0.5) * 1.3;
	float main_line = abs(fract(angle / 6.28318 * 7.0 + bend + radius * 1.4) - 0.5) * radius * 6.28318 / 7.0;
	float main_width = mix(0.016, 0.004, clamp(radius / 0.6, 0.0, 1.0)); // they taper toward the edges
	float veins = 1.0 - smoothstep(main_width * 0.5, main_width, main_line);
	// thinner side veins between them, starting a bit away from the wound
	float side_line = abs(fract(angle / 6.28318 * 13.0 - bend * 1.6 + radius * 2.3) - 0.5) * radius * 6.28318 / 13.0;
	veins = max(veins, (1.0 - smoothstep(0.0025, 0.005, side_line)) * smoothstep(0.1, 0.18, radius) * 0.75);
	veins *= smoothstep(vein_reach, vein_reach - 0.06, radius);
	// the wound itself: a ragged dark-red hole that swells at each beat
	float wound_size = smoothstep(0.0, 0.2, progress) * (0.055 + 0.02 * pulse) + (noise(surface * 18.0 + time * 0.5) - 0.5) * 0.02;
	float wound = smoothstep(wound_size + 0.01, wound_size - 0.01, radius) * step(0.01, progress);

	// ---- the drips from the top (from the venom) ----
	float dripping = drips(UV, smoothstep(0.15, 0.85, progress));

	// ---- the pool from the bottom (from the water) ----
	float height = 1.0 - UV.y; // 0 = bottom of the rectangle, 1 = top
	float slosh = 0.025 * sin(UV.x * 11.0 + time * 5.0) + 0.035 * (noise(vec2(UV.x * 6.0, time * 2.0)) - 0.5) + pulse * 0.025;
	float pool_line = smoothstep(0.3, 1.0, progress) * 1.08 - 0.05 + slosh;
	float below = pool_line - height; // > 0 = inside the pool
	float pooled = smoothstep(0.0, 0.012, below);

	float covered = max(max(dripping, pooled), wound);

	// ---- the color of the blood ----
	// thick and glossy: darker where it is deep, a soft shine where the thickness peaks
	float thickness = noise(surface * vec2(9.0, 5.0) + vec2(0.0, time * 0.35));
	vec3 blood = mix(BLOOD_DEEP, BLOOD, 0.35 + 0.65 * thickness);
	blood = mix(blood, BLOOD_DEEP, clamp(below * 1.2, 0.0, 1.0) * 0.5); // the pool darkens with depth
	blood = mix(blood, SHINE, smoothstep(0.86, 0.9, thickness) * 0.22 * fade);
	// a bright line where the pool's surface is (like the water's foam, but red)
	blood = mix(blood, BLOOD_BRIGHT, (1.0 - smoothstep(0.0, 0.035, below)) * pooled * 0.7);
	// dark bubbles rising in the pool (like the water's, but thick and slow)
	float bubble_column = floor(surface.x * 8.0);
	vec2 bubble_grid = vec2(surface.x * 8.0, surface.y * 8.0 + time * (0.9 + hash(vec2(bubble_column, 4.2)) * 0.9));
	vec2 bubble_cell = floor(bubble_grid);
	float bubble_distance = length(fract(bubble_grid) - 0.5 - (vec2(hash(bubble_cell + 5.3), hash(bubble_cell + 2.7)) - 0.5) * 0.4);
	float bubble_size = mix(0.08, 0.16, hash(bubble_cell + 1.9));
	float bubble = (1.0 - smoothstep(0.0, 0.04, abs(bubble_distance - bubble_size))) * step(0.72, hash(bubble_cell)) * smoothstep(0.04, 0.12, below);
	blood = mix(blood, BLOOD_BRIGHT, bubble * 0.6);
	// the whole blood throbs a little brighter at each beat
	blood *= 1.0 + pulse * 0.3;

	// ---- the veins on top: dark between beats, glowing at each beat ----
	vec3 vein_color = mix(vec3(0.30, 0.0, 0.03), BLOOD_BRIGHT * 1.2, pulse);
	vec3 color = mix(blood, vein_color, veins * mix(0.55, 1.0, pulse));
	color = mix(color, BLOOD_DEEP * 0.6, wound * 0.8);
	float alpha = max(covered * 0.92, veins * 0.9);

	// ---- clotting and flaking away (fade goes 1 -> 0) ----
	float clot = 1.0 - fade;
	color = mix(color, CLOTTED, smoothstep(0.0, 0.5, clot) * 0.8);
	float cracks = 1.0 - smoothstep(0.0, 0.012, abs(noise(surface * 9.0 + 4.0) - 0.5));
	color = mix(color, vec3(0.05, 0.0, 0.0), cracks * smoothstep(0.1, 0.4, clot) * 0.8);
	float flake_patch = noise(surface * 8.0 + 11.0) * 0.75 + thickness * 0.25;
	alpha *= smoothstep(-0.015, 0.015, flake_patch - clot * 1.15 + 0.1);

	// soft side edges, so it reads as blood around the card, not a hard box
	alpha *= 1.0 - smoothstep(0.85, 1.0, abs(UV.x - 0.5) * 2.0);
	COLOR = vec4(color, alpha);
}
