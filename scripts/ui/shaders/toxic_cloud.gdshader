shader_type canvas_item;
// The poison area cast (Cicuta no Chá, Névoa de Esporos Teimosos): a thick toxic cloud rolls over the
// arena from the caster's side, purple billows with sickly green veins swirling inside, spores
// drifting in it; it hangs over the table for a moment, then thins out into wisps and is gone.
// Drawn on ONE ColorRect over the arena. FxCasts._poison_area tweens `progress` (the cloud rolling in)
// and `fade` (the cloud thinning away).
// Coordinates: UV.y = 0 at the top of the arena, 1 at the bottom. `from_bottom` flips it so the cloud
// always comes from the caster's side.

uniform float progress = 0.0; // 0 = no cloud yet, 1 = the cloud covers the whole arena
uniform float fade = 1.0; // 1 = thick cloud, 0 = all gone
uniform float aspect = 1.5; // arena width / height, so the billows are round and not stretched
uniform float from_bottom = 0.0; // 1 = the caster is at the bottom, so the cloud rolls up

const vec3 CLOUD_DARK = vec3(0.16, 0.06, 0.22);
const vec3 CLOUD_PURPLE = vec3(0.48, 0.24, 0.62);
const vec3 CLOUD_LIGHT = vec3(0.74, 0.55, 0.86);
const vec3 SICKLY_GREEN = vec3(0.58, 0.95, 0.32);

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

// billowy noise: four layers of noise, each smaller and fainter (the classic cloud recipe)
float billows(vec2 p) {
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
	// the cloud swirls: its noise is pushed around by another, slower noise
	vec2 swirl = vec2(noise(surface * 2.0 + TIME * 0.25), noise(surface * 2.0 - TIME * 0.2 + 5.0)) - 0.5;
	float cloud = billows(surface * 3.0 + swirl * 1.2 + vec2(TIME * 0.12, -TIME * 0.18));

	// the rolling front: a lumpy edge moving from the caster's side to the far side
	float front = progress * 1.35 - 0.1 + (cloud - 0.5) * 0.35;
	float covered = smoothstep(front, front - 0.18, depth);
	// the billows at the front edge are the thickest and brightest
	float front_bulge = exp(-pow((depth - front + 0.08) / 0.08, 2.0)) * (1.0 - smoothstep(0.85, 1.0, progress));

	// color: dark in the thin parts, lighter purple in the thick, green veins winding through it
	float thickness = smoothstep(0.25, 0.8, cloud);
	vec3 color = mix(CLOUD_DARK, CLOUD_PURPLE, thickness);
	color = mix(color, CLOUD_LIGHT, smoothstep(0.62, 0.85, cloud) * 0.5 + front_bulge * 0.3);
	float vein = 1.0 - smoothstep(0.0, 0.045, abs(billows(surface * 4.0 - swirl + TIME * 0.1) - 0.5));
	color = mix(color, SICKLY_GREEN, vein * 0.55 * thickness);

	// spores: small soft dots drifting slowly up inside the cloud, pulsing green
	vec2 spore_grid = surface * vec2(16.0, 11.0) + vec2(TIME * 0.2, -TIME * 0.6);
	vec2 spore_cell = floor(spore_grid);
	vec2 spore_offset = fract(spore_grid) - 0.5 - (vec2(hash(spore_cell + 2.3), hash(spore_cell + 7.7)) - 0.5) * 0.6;
	float spores = (1.0 - smoothstep(0.04, 0.11, length(spore_offset))) * step(0.8, hash(spore_cell));
	spores *= 0.6 + 0.4 * sin(TIME * 4.0 + hash(spore_cell) * 25.0);
	color = mix(color, SICKLY_GREEN, spores * 0.8);

	float alpha = covered * (0.42 + 0.4 * thickness + front_bulge * 0.15);
	alpha = max(alpha, spores * covered * 0.9);
	// thinning away: the thin parts of the cloud vanish first, the thick billows last
	alpha *= smoothstep(0.0, 0.35, fade * 1.35 - (1.0 - cloud) * 0.6);
	COLOR = vec4(color, clamp(alpha, 0.0, 0.88));
}
