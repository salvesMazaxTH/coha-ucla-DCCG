shader_type canvas_item;
// The fire destroy (Reduzir a Cinzas): flames climb up ONE unit from its base, engulf it while it
// dissolves, and die out. Drawn on a small ColorRect over the card (a bit wider and taller than it,
// so the tongues of fire lick past its edges). FxCasts._burn_unit tweens `progress` (how high the
// flames climbed) and `fade` (the fire dying out).
// Coordinates: UV.y = 0 at the top of the rectangle, 1 at the bottom.

uniform float progress = 0.0; // 0 = no flames yet, 1 = the flames cover the whole card
uniform float fade = 1.0; // 1 = burning, 0 = all gone
uniform float aspect = 0.75; // rectangle width / height, so the flames are not stretched

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
	float height = 1.0 - UV.y; // 0 = the base of the flames, 1 = the top of the rectangle
	vec2 surface = vec2(UV.x * aspect, height);

	// flames: turbulence scrolling upward, swaying sideways, shorter and thinner near the sides
	float sway = noise(vec2(surface.x * 3.0, height * 2.0 - time * 1.8)) * 0.8;
	float flicker = turbulence(vec2(surface.x * 5.0 + sway, height * 3.0 - time * 4.0));
	float from_middle = abs(UV.x - 0.5) * 2.0; // 0 = the middle, 1 = a side edge
	float sides = 1.0 - smoothstep(0.55, 1.0, from_middle);
	// how far up this pixel is, compared with how high the flames have climbed (1 = their tips)
	float reach = height / max(progress * 1.25, 0.02);
	float heat = (flicker * 1.7 + 0.12 - reach * 1.15) * sides * fade;

	// soot: the card darkens under and behind the flames (only over the card, the lower ~70% of the rectangle)
	float soot = smoothstep(1.2, 0.6, reach) * (1.0 - smoothstep(0.55, 0.7, height)) * sides * fade * 0.4;

	// embers: small round sparks in some cells of a grid that drifts upward, just above the flames
	vec2 ember_grid = surface * vec2(9.0, 10.0) - vec2(0.0, time * 2.4);
	vec2 ember_cell = floor(ember_grid);
	vec2 ember_offset = fract(ember_grid) - 0.5 - (vec2(hash(ember_cell + 3.1), hash(ember_cell + 7.7)) - 0.5) * 0.6;
	float ember_twinkle = 0.6 + 0.4 * sin(time * 9.0 + hash(ember_cell) * 30.0);
	float ember_zone = smoothstep(0.5, 0.9, reach) * (1.0 - smoothstep(1.3, 1.8, reach));
	float embers = (1.0 - smoothstep(0.05, 0.14, length(ember_offset))) * step(0.7, hash(ember_cell)) * ember_twinkle * ember_zone * sides * fade;

	vec4 result = vec4(0.05, 0.03, 0.02, soot);
	result.rgb = mix(result.rgb, vec3(1.0, 0.5, 0.1), embers);
	result.a = max(result.a, embers);
	float flame_alpha = smoothstep(0.18, 0.4, heat);
	result.rgb = mix(result.rgb, fire_color(heat), flame_alpha);
	result.a = max(result.a, flame_alpha * 0.95);
	COLOR = result;
}
