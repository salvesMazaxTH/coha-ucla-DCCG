shader_type canvas_item;
// The water area cast (Tsunami, Julgamento da Era Afogada): a wave rolls over the whole arena from the
// caster's side, covers the table for a moment and drains away in patches.
// Drawn on ONE ColorRect over the arena, with normal blending (not additive), so it reads as liquid,
// not as light. FxCasts._water_area tweens `progress` (the wave advancing) and `drain` (the water leaving).
// Coordinates: UV.y = 0 at the top of the arena, 1 at the bottom.

uniform float progress = 0.0; // 0 = the wave has not entered yet, 1 = it covered the whole arena
uniform float drain = 0.0; // 0 = the arena is under water, 1 = all the water is gone
uniform float from_bottom = 1.0; // 1 = the wave comes from the bottom (the caster is the player below)
uniform float aspect = 1.5; // arena width / height, so the ripples are round, not stretched

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

// the bright net of light that dances on the bottom of a pool (3 rounds of a well-known trick)
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
	vec2 surface = vec2(UV.x * aspect, UV.y);
	// how far this pixel is along the wave's path (0 = the caster's edge, 1 = the far edge)
	float along = mix(UV.y, 1.0 - UV.y, from_bottom);

	// the crest: where the wave front is now, wobbling along its width
	float front = progress * 1.35 - 0.2;
	float wobble = 0.035 * sin(UV.x * 11.0 + time * 4.0) + 0.05 * (noise(vec2(UV.x * 9.0, time * 2.0)) - 0.5);
	float to_crest = front + wobble - along; // > 0 = behind the crest (under water)
	float under = smoothstep(0.0, 0.015, to_crest);

	// the body: deeper (darker) further behind the crest, with rolling ripples
	float ripples = noise(surface * 7.0 + vec2(0.0, time * 1.5)) * 0.6 + noise(surface * 15.0 - vec2(time * 1.2, 0.0)) * 0.4;
	float depth = clamp(to_crest * 2.2, 0.0, 1.0);
	vec3 water = mix(SHALLOW, DEEP, depth * 0.8 + ripples * 0.25);
	water += vec3(0.55, 0.85, 1.0) * caustics(surface * 1.4 + vec2(0.0, time * 0.05), time * 0.6) * 0.55;

	// the foam: a thick white band on the crest that breaks into streaks behind it
	float crest_foam = 1.0 - smoothstep(0.0, 0.07, to_crest);
	float streaks = smoothstep(0.55, 0.85, noise(surface * vec2(10.0, 22.0) + vec2(time * 0.7, 0.0))) * (1.0 - smoothstep(0.0, 0.35, to_crest));
	float foam = clamp(crest_foam * (0.75 + 0.25 * ripples) + streaks * 0.7, 0.0, 1.0);
	water = mix(water, FOAM, foam);

	// draining: the water leaves in patches (each pixel has its own moment to dry)
	float dry_moment = noise(surface * 5.0) * 0.7 + noise(surface * 13.0) * 0.3;
	float still_wet = 1.0 - smoothstep(dry_moment - 0.1, dry_moment + 0.05, drain * 1.15);

	float alpha = under * mix(0.78, 0.95, foam) * still_wet;
	COLOR = vec4(water, alpha);
}
