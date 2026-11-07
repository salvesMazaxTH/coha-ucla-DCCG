shader_type canvas_item;
// The fire area cast (Pira-Mundo, D'Lorafya): a wall of flames sweeps over the whole arena from the
// caster's side, leaving smoke and glowing embers behind, then dies out.
// Drawn on ONE ColorRect over the arena. FxCasts._fire_area tweens `progress` (the wall advancing)
// and `fade` (the fire dying out at the end).
// Coordinates: UV.y = 0 at the top of the arena, 1 at the bottom.

uniform float progress = 0.0; // 0 = the wall has not entered yet, 1 = it crossed the whole arena
uniform float fade = 1.0; // 1 = burning, 0 = all gone
uniform float from_bottom = 1.0; // 1 = the wall comes from the bottom (the caster is the player below)
uniform float aspect = 1.5; // arena width / height, so the flames are not stretched

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

// layered noise (big shapes + smaller and smaller detail): the turbulence of the flames
float turbulence(vec2 p) {
	float total = 0.0;
	float weight = 0.5;
	for (int layer = 0; layer < 4; layer++) {
		total += noise(p) * weight;
		p = p * 2.03 + vec2(1.7, 9.2);
		weight *= 0.5;
	}
	return total;
}

// the color of fire by how hot it is: dark red at the tips, orange, yellow, almost white at the core
vec3 fire_color(float heat) {
	vec3 color = mix(vec3(0.45, 0.04, 0.0), vec3(1.0, 0.38, 0.03), smoothstep(0.25, 0.5, heat));
	color = mix(color, vec3(1.0, 0.78, 0.22), smoothstep(0.5, 0.75, heat));
	return mix(color, vec3(1.0, 0.97, 0.82), smoothstep(0.8, 1.05, heat));
}

void fragment() {
	float time = TIME;
	// how far this pixel is along the wall's path (0 = the caster's edge, 1 = the far edge)
	float along = mix(UV.y, 1.0 - UV.y, from_bottom);
	vec2 surface = vec2(UV.x * aspect, along);

	// the base of the flames (their hottest line) and how far this pixel is past it, toward the front
	float base = progress * 1.5 - 0.3;
	float past_base = along - base;

	// flames: turbulence scrolling forward, stretched along the path so it breaks into tongues, and cut off
	// more and more the further it reaches from the base; behind the base the fire dies off faster
	// (that side has already burned). Right at the base there is a flat hot strip, so no bright seam.
	float sway = noise(vec2(surface.x * 3.0, along * 2.0 - time * 1.5)) * 0.9;
	float flicker = turbulence(vec2(surface.x * 6.0 + sway, along * 2.4 - time * 3.2));
	float reach = max(past_base, 0.0) * 2.3 + max(-past_base - 0.08, 0.0) * 4.5;
	float heat = (flicker * 1.75 - reach) * fade;

	// smoke and embers on the burned side (behind the base)
	float burned = smoothstep(0.05, 0.2, -past_base) * (1.0 - smoothstep(0.4, 0.9, -past_base));
	float smoke = turbulence(surface * 2.5 - vec2(time * 0.3, time * 0.9)) * burned * fade;
	// embers: one small round spark in some cells of a grid that drifts forward
	vec2 ember_grid = surface * vec2(16.0, 12.0) - vec2(0.0, time * 1.8);
	vec2 ember_cell = floor(ember_grid);
	vec2 ember_offset = fract(ember_grid) - 0.5 - (vec2(hash(ember_cell + 3.1), hash(ember_cell + 7.7)) - 0.5) * 0.6;
	float ember_twinkle = 0.6 + 0.4 * sin(time * 9.0 + hash(ember_cell) * 30.0);
	float embers = (1.0 - smoothstep(0.05, 0.13, length(ember_offset))) * step(0.72, hash(ember_cell)) * ember_twinkle * burned * fade;

	vec4 result = vec4(0.06, 0.04, 0.03, smoke * 0.45);
	result.rgb = mix(result.rgb, vec3(1.0, 0.5, 0.1), embers);
	result.a = max(result.a, embers);
	float flame_alpha = smoothstep(0.18, 0.4, heat);
	result.rgb = mix(result.rgb, fire_color(heat), flame_alpha);
	result.a = max(result.a, flame_alpha * 0.95);
	COLOR = result;
}
