shader_type canvas_item;
// The ice area cast (Avalanche, Zero Absoluto): a sheet of frost spreads over the whole arena from the
// caster's side with a jagged, feathery front, freezing the table into big crystal plates with white
// cracks between them. At the end the ice shatters: the plates blink out one by one.
// Drawn on ONE ColorRect over the arena. FxCasts._ice_area tweens `progress` (the frost advancing)
// and `fade` (the ice shattering at the end).
// Coordinates: UV.y = 0 at the top of the arena, 1 at the bottom.

uniform float progress = 0.0; // 0 = no frost yet, 1 = the frost covers the whole arena
uniform float fade = 1.0; // 1 = frozen, 0 = every plate has shattered
uniform float from_bottom = 1.0; // 1 = the frost comes from the bottom (the caster is the player below)
uniform float aspect = 1.5; // arena width / height, so the crystals are not stretched

const vec3 ICE_DEEP = vec3(0.36, 0.66, 0.86);
const vec3 ICE_PALE = vec3(0.80, 0.94, 1.0);
const vec3 FROST_WHITE = vec3(0.97, 0.99, 1.0);

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

// layered noise (big shapes + smaller and smaller detail): the jagged frost front
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

// crystal plates (a Voronoi pattern): which plate this point is on, and how far it is from the
// nearest crack (the border with the next plate). Returns vec3(plate id x, plate id y, crack distance).
vec3 crystal_plates(vec2 p) {
	vec2 cell = floor(p);
	vec2 inside = fract(p);
	float nearest = 8.0;
	float second = 8.0;
	vec2 nearest_cell = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 seed_point = neighbor + vec2(hash(cell + neighbor), hash(cell + neighbor + 17.3)) * 0.85;
			float distance_to_seed = length(seed_point - inside);
			if (distance_to_seed < nearest) {
				second = nearest;
				nearest = distance_to_seed;
				nearest_cell = cell + neighbor;
			} else if (distance_to_seed < second) {
				second = distance_to_seed;
			}
		}
	}
	return vec3(nearest_cell, second - nearest);
}

void fragment() {
	// 0 at the caster's edge of the arena, 1 at the far edge
	float from_caster = mix(UV.y, 1.0 - UV.y, from_bottom);
	vec2 surface = vec2(UV.x * aspect, UV.y);

	// the frost front: jagged and feathery, a little ahead in some places and behind in others
	float jag = (turbulence(surface * 7.0) - 0.5) * 0.22 + (noise(surface * 38.0) - 0.5) * 0.05;
	float front = progress * 1.25 - 0.1 + jag;
	float frozen = smoothstep(front + 0.015, front - 0.015, from_caster);
	// the bright frosty rim right at the front, only while the frost is still spreading
	float rim = exp(-pow((from_caster - front) / 0.03, 2.0)) * step(0.001, progress) * (1.0 - smoothstep(0.9, 1.0, progress));

	vec3 plates = crystal_plates(surface * 6.0);
	float plate_seed = hash(plates.xy);
	// shattering: each plate disappears at its own moment while `fade` falls
	float plate_alive = step(plate_seed, fade * 1.15 - 0.08);
	float crack = 1.0 - smoothstep(0.0, 0.07, plates.z);

	// inside a plate: pale ice, some plates brighter than others
	float shine = noise(surface * vec2(2.5, 1.5) + plates.xy * 0.3);
	vec3 ice = mix(ICE_DEEP, ICE_PALE, 0.35 + 0.5 * plate_seed * shine);
	// fine frost needles inside the plates
	float needles = smoothstep(0.62, 0.9, noise(vec2(surface.x * 60.0 + surface.y * 25.0, surface.y * 6.0)));
	ice = mix(ice, FROST_WHITE, needles * 0.45);

	// sparkles: tiny twinkling points on the ice
	vec2 sparkle_grid = surface * 26.0;
	vec2 sparkle_cell = floor(sparkle_grid);
	float sparkle_dot = 1.0 - smoothstep(0.02, 0.09, length(fract(sparkle_grid) - 0.5));
	float sparkle = sparkle_dot * step(0.88, hash(sparkle_cell + 3.0)) * (0.5 + 0.5 * sin(TIME * 7.0 + hash(sparkle_cell) * 40.0));

	vec4 result = vec4(ice, 0.34 + needles * 0.2);
	result.rgb = mix(result.rgb, FROST_WHITE, crack);
	result.a = max(result.a, crack * 0.85);
	result.rgb = mix(result.rgb, vec3(1.0), sparkle);
	result.a = max(result.a, sparkle * 0.9);
	result.a *= frozen * plate_alive;
	// the rim glows on top of everything, even where the ice is still thin
	result.rgb = mix(result.rgb, FROST_WHITE, rim);
	result.a = max(result.a, rim * 0.9 * fade);
	COLOR = result;
}
