shader_type canvas_item;
// The lightning area cast (Tempestade Estática, Cumulonimbra): the arena darkens under a storm and
// several jagged bolts strike the two rows of units one after another, each with a branch, a white-hot
// core, a blue-violet glow and a burst on the spot it hits.
// Drawn on ONE ColorRect over the arena. FxCasts._lightning_area tweens `progress` (the storm's
// timeline: the bolts strike at different moments of it) and `fade` (the storm clearing).
// Coordinates: UV.y = 0 at the top of the arena, 1 at the bottom.

uniform float progress = 0.0; // 0 = the storm begins, 1 = the last bolt has struck
uniform float fade = 1.0; // 1 = storm, 0 = cleared
uniform float aspect = 1.5; // arena width / height, so the bolts are not stretched
uniform float seed = 0.0; // a different number every cast, so the bolts never fall in the same places

const int BOLT_COUNT = 6;
const float BOLT_LIFE = 0.16; // how long one bolt stays on screen, as a part of the timeline
const vec3 BOLT_CORE = vec3(1.0, 1.0, 0.92);
const vec3 BOLT_GLOW = vec3(0.62, 0.66, 1.0);
const vec3 BOLT_YELLOW = vec3(1.0, 0.89, 0.25);
const vec3 STORM_DARK = vec3(0.05, 0.05, 0.14);

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

// how bright a bolt is at this point: a jagged line from the top of the arena down to `impact`,
// entering at `x_start`, with one branch splitting off to a side.
float bolt_light(vec2 uv, float x_start, vec2 impact, float bolt_seed) {
	if (uv.y > impact.y + 0.02) {
		return 0.0;
	}
	float down = clamp(uv.y / impact.y, 0.0, 1.0); // 0 = top, 1 = the hit
	// the path: a straight line from the top to the impact, plus big zigzags and small ones
	float path_x = mix(x_start, impact.x, down);
	path_x += (noise(vec2(down * 7.0, bolt_seed)) - 0.5) * 0.16 * (1.0 - down * 0.7);
	path_x += (noise(vec2(down * 28.0, bolt_seed + 4.0)) - 0.5) * 0.035;
	float distance_to_path = abs(uv.x - path_x) * aspect;
	float core = 1.0 - smoothstep(0.004, 0.009, distance_to_path);
	float glow = exp(-distance_to_path * 28.0) * 0.75;

	// one branch splitting from the middle and fading out sideways
	float branch_start = 0.35 + hash(vec2(bolt_seed, 2.0)) * 0.25;
	float branch_side = hash(vec2(bolt_seed, 9.0)) > 0.5 ? 1.0 : -1.0;
	float along_branch = (down - branch_start) / 0.3;
	if (along_branch > 0.0 && along_branch < 1.0) {
		float branch_x = mix(x_start, impact.x, branch_start) + branch_side * along_branch * 0.08;
		branch_x += (noise(vec2(along_branch * 9.0, bolt_seed + 8.0)) - 0.5) * 0.04;
		float distance_to_branch = abs(uv.x - branch_x) * aspect;
		float branch_strength = 1.0 - along_branch;
		core = max(core, (1.0 - smoothstep(0.002, 0.005, distance_to_branch)) * branch_strength);
		glow = max(glow, exp(-distance_to_branch * 40.0) * 0.5 * branch_strength);
	}
	return core + glow;
}

void fragment() {
	vec2 uv = UV;
	// the storm darkness, there from the start and clearing with `fade`
	float darkness = smoothstep(0.0, 0.08, progress) * 0.3;
	vec4 result = vec4(STORM_DARK, darkness);
	float flash = 0.0;
	float light = 0.0;
	float splash = 0.0;
	for (int i = 0; i < BOLT_COUNT; i++) {
		float bolt_seed = float(i) * 13.7 + seed;
		float strike_moment = (float(i) + 0.3) / float(BOLT_COUNT) * 0.82;
		float age = (progress - strike_moment) / BOLT_LIFE; // 0 = just struck, 1 = gone
		if (age < 0.0 || age > 1.0) {
			continue;
		}
		// it flickers: on, a quick dip, on again, then gone
		float flicker = (1.0 - age) * (0.65 + 0.35 * step(0.5, fract(age * 3.5)));
		// alternate rows: the even bolts hit the far row, the odd ones the near row
		float row_y = mod(float(i), 2.0) < 0.5 ? 0.27 : 0.73;
		vec2 impact = vec2(0.1 + 0.8 * hash(vec2(bolt_seed, 1.0)), row_y + (hash(vec2(bolt_seed, 3.0)) - 0.5) * 0.12);
		float x_start = impact.x + (hash(vec2(bolt_seed, 5.0)) - 0.5) * 0.25;
		light = max(light, bolt_light(uv, x_start, impact, bolt_seed) * flicker);
		// the hit: a white burst on the unit
		vec2 to_impact = (uv - impact) * vec2(aspect, 1.0);
		splash = max(splash, exp(-dot(to_impact, to_impact) / 0.008) * flicker);
		flash = max(flash, (1.0 - age) * (1.0 - age));
	}
	// the whole arena blinks pale when a bolt strikes
	result.rgb = mix(result.rgb, BOLT_GLOW, flash * 0.5);
	result.a = mix(result.a, 0.22, flash * 0.6);
	vec3 bolt_color = mix(BOLT_GLOW, BOLT_CORE, smoothstep(0.5, 1.0, light));
	bolt_color = mix(bolt_color, BOLT_YELLOW, splash * 0.4);
	float bolt_alpha = clamp(max(light, splash), 0.0, 1.0);
	result.rgb = mix(result.rgb, bolt_color, bolt_alpha);
	result.a = max(result.a, bolt_alpha);
	result.a *= fade;
	COLOR = result;
}
