shader_type canvas_item;
// The shadow area cast: the light goes out over the arena. A wall of black ink-smoke rolls in from the
// caster's side with long ragged tendrils reaching ahead of it, a cold pale-gray glow along its edge, and
// ash specks drifting up inside; it hangs over the table for a moment, then frays into wisps and is gone.
// Drawn on ONE ColorRect over the arena. FxCasts._shadow_area tweens `progress` (the dark rolling in)
// and `fade` (the dark fraying away).
// Coordinates: UV.y = 0 at the top of the arena, 1 at the bottom. `from_bottom` flips it so the dark
// always comes from the caster's side.

uniform float progress = 0.0; // 0 = no dark yet, 1 = the dark covers the whole arena
uniform float fade = 1.0; // 1 = full dark, 0 = all gone
uniform float aspect = 1.5; // arena width / height, so the smoke is round and not stretched
uniform float from_bottom = 0.0; // 1 = the caster is at the bottom, so the dark rolls up

const vec3 INK = vec3(0.02, 0.02, 0.035);
const vec3 SMOKE = vec3(0.1, 0.1, 0.14);
const vec3 EDGE_GLOW = vec3(0.62, 0.66, 0.78);
const vec3 ASH = vec3(0.78, 0.8, 0.9);

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

// smoke noise: four layers of noise, each smaller and fainter
float smoke(vec2 p) {
	float total = 0.0;
	float strength = 0.5;
	for (int layer = 0; layer < 4; layer++) {
		total += noise(p) * strength;
		p = p * 2.03 + vec2(1.7, 9.2);
		strength *= 0.5;
	}
	return total;
}

void fragment() {
	// distance from the caster's edge: 0 at the caster's side, 1 at the far side
	float depth = from_bottom > 0.5 ? 1.0 - UV.y : UV.y;
	vec2 surface = vec2(UV.x * aspect, depth);
	// the smoke curls: its noise is pushed around by another, slower noise
	vec2 swirl = vec2(noise(surface * 2.5 + TIME * 0.2), noise(surface * 2.5 - TIME * 0.25 + 5.0)) - 0.5;
	float body = smoke(surface * 2.6 + swirl * 1.4 + vec2(TIME * 0.05, -TIME * 0.12));

	// tendrils: thin columns of dark that run ahead of the front, each a different length
	float column = floor(UV.x * aspect * 9.0);
	float tendril_reach = (0.12 + 0.2 * hash(vec2(column, 3.0))) * sin(clamp(progress, 0.0, 1.0) * 3.14159);
	float in_column = abs(fract(UV.x * aspect * 9.0) - 0.5);
	float tendril_width = 0.1 + 0.18 * hash(vec2(column, 8.0));
	float tendril_ahead = step(in_column, tendril_width) * (1.0 - smoothstep(0.0, tendril_reach + 0.001, depth - (progress * 1.3 - 0.12)));

	// the rolling front: a ragged edge moving from the caster's side to the far side
	float front = progress * 1.35 - 0.1 + (body - 0.5) * 0.5;
	float covered = smoothstep(front, front - 0.1, depth);
	covered = max(covered, tendril_ahead * step(depth, front + 0.4) * step(0.02, progress) * 0.8);
	// the pale glow hugging the ragged edge, strongest while the front is still moving
	float edge_glow = exp(-pow((depth - front + 0.04) / 0.045, 2.0)) * (1.0 - smoothstep(0.85, 1.0, progress));

	// color: pure ink in the thick parts, dark smoke gray in the thin ones, a cold glow on the edge
	float thickness = smoothstep(0.3, 0.7, body);
	vec3 color = mix(SMOKE, INK, thickness);
	color = mix(color, EDGE_GLOW, edge_glow * 0.55);
	// faint pale filaments winding through the dark, like light failing to get out
	float filament = 1.0 - smoothstep(0.0, 0.03, abs(smoke(surface * 5.0 - swirl * 1.5 + TIME * 0.06) - 0.5));
	color = mix(color, EDGE_GLOW, filament * 0.18 * (1.0 - thickness * 0.5));

	// ash: small pale specks drifting up inside the dark
	vec2 ash_grid = surface * vec2(20.0, 13.0) + vec2(TIME * 0.1, -TIME * 0.45);
	vec2 ash_cell = floor(ash_grid);
	vec2 ash_offset = fract(ash_grid) - 0.5 - (vec2(hash(ash_cell + 2.3), hash(ash_cell + 7.7)) - 0.5) * 0.6;
	float ash = (1.0 - smoothstep(0.03, 0.08, length(ash_offset))) * step(0.82, hash(ash_cell));
	ash *= 0.5 + 0.5 * sin(TIME * 3.0 + hash(ash_cell) * 25.0);
	color = mix(color, ASH, ash * 0.7);

	float alpha = covered * (0.6 + 0.3 * thickness);
	alpha = max(alpha, ash * covered * 0.8);
	alpha = max(alpha, edge_glow * covered * 0.5);
	// fraying away: the thin smoke goes first, the thick ink last
	alpha *= smoothstep(0.0, 0.35, fade * 1.35 - (1.0 - body) * 0.6);
	COLOR = vec4(color, clamp(alpha, 0.0, 0.92));
}
