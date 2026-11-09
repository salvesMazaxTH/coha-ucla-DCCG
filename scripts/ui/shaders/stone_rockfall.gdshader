shader_type canvas_item;
// The stone area cast (any card of the element pedra that hurts a whole row of units): a rockslide.
// Boulders rain down over the whole arena, each one landing at its own moment with a puff of dust and a
// crack in the ground around it; they lie there for a moment, then crumble to dust and are gone.
// Drawn on ONE ColorRect over the arena. FxCasts._stone_area tweens `progress` (the rocks falling) and
// `fade` (the rubble crumbling away).
// Coordinates: UV.y = 0 at the top of the arena. The arena is cut into a grid; each cell has at most one boulder.
// Cost: 3 cells checked per pixel (the ones above it, where a boulder may still be falling), no big loops.

uniform float progress = 0.0; // 0 = no rock has fallen yet, 1 = every rock has landed
uniform float fade = 1.0; // 1 = rubble lying there, 0 = crumbled away
uniform float aspect = 1.5; // arena width / height, so the rocks are round and not stretched

const float GRID_SCALE = 5.0; // cells per arena height (about 5 rows and 7 or 8 columns)
const float FALL_DISTANCE = 2.6; // how many cells above its landing spot a rock starts
const float FALL_SPAN = 0.32; // how much of `progress` one rock takes to fall
const float LAST_START = 0.58; // the latest moment (in `progress`) a rock starts to fall
const vec3 ROCK_DARK = vec3(0.22, 0.17, 0.13);
const vec3 ROCK_LIGHT = vec3(0.66, 0.55, 0.42);
const vec3 DUST = vec3(0.70, 0.60, 0.47);
const vec3 CRACK_GLOW = vec3(0.95, 0.62, 0.25);

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

// smooth 2D noise
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 inside = fract(p);
	vec2 blend = inside * inside * (3.0 - 2.0 * inside);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0, 1.0)), blend.x), blend.y);
}

void fragment() {
	vec2 grid = vec2(UV.x * aspect, UV.y) * GRID_SCALE;
	vec2 pixel_cell = floor(grid);
	vec4 result = vec4(0.0);
	float dust_alpha = 0.0;
	float crack_alpha = 0.0;

	// a boulder that lands in a cell below this pixel's cell may still be passing through it on its way down
	for (int below = 2; below >= 0; below--) {
		vec2 cell = pixel_cell + vec2(0.0, float(below));
		if (hash(cell + 3.1) < 0.4) {
			continue; // no boulder in this cell
		}
		float start = hash(cell + 11.7) * LAST_START;
		float fall = clamp((progress - start) / FALL_SPAN, 0.0, 1.0);
		if (progress <= start) {
			continue; // not started yet
		}
		float radius = 0.27 + 0.1 * hash(cell + 5.3);
		vec2 landing_spot = cell + vec2(0.5 + (hash(cell + 8.9) - 0.5) * 0.3, 0.5);
		// it speeds up as it falls (gravity)
		float rock_y = landing_spot.y - FALL_DISTANCE * (1.0 - fall * fall);
		vec2 offset = grid - vec2(landing_spot.x, rock_y);

		// the boulder: a round lump with a bumpy outline
		float angle = atan(offset.y, offset.x);
		float bumpy = radius * (0.82 + 0.3 * noise(vec2(angle * 1.6 + hash(cell) * 20.0, hash(cell + 1.3) * 9.0)));
		float distance_to_rock = length(offset);
		float rock = 1.0 - smoothstep(bumpy - 0.03, bumpy, distance_to_rock);
		// crumbling away: each boulder goes at its own moment, shrinking as it turns to dust
		float crumble = smoothstep(0.0, 0.3, fade * 1.3 - hash(cell + 21.0) * 0.55);
		rock *= crumble;
		if (rock > 0.0) {
			// lit from the top left: a lighter side, a dark rim, and rough speckle
			vec2 normal = offset / max(bumpy, 0.01);
			float light = clamp(0.5 - dot(normal, normalize(vec2(-0.6, -0.8))) * 0.5, 0.0, 1.0);
			vec3 rock_color = mix(ROCK_DARK, ROCK_LIGHT, light * (1.0 - 0.35 * length(normal)));
			rock_color *= 0.8 + 0.4 * noise(offset * 14.0 + hash(cell) * 30.0);
			rock_color *= 1.0 - 0.45 * smoothstep(0.72, 1.0, length(normal));
			result = vec4(mix(result.rgb, rock_color, rock), max(result.a, rock));
		}

		// the streak behind a falling rock
		if (fall < 1.0) {
			float streak_x = abs(grid.x - landing_spot.x);
			float streak = (1.0 - smoothstep(0.0, radius * 0.7, streak_x)) * step(grid.y, rock_y) * exp(-(rock_y - grid.y) * 1.4) * 0.3;
			dust_alpha = max(dust_alpha, streak);
		}

		// the puff of dust and the cracks, only inside the cell the rock lands in (below == 0)
		if (below == 0 && fall >= 1.0) {
			float since_landing = clamp((progress - start - FALL_SPAN) / 0.25, 0.0, 1.0);
			vec2 from_landing = grid - landing_spot;
			float puff_radius = 0.2 + since_landing * 0.34;
			float puff = (1.0 - smoothstep(puff_radius - 0.2, puff_radius, length(from_landing * vec2(1.0, 1.6)))) * (1.0 - since_landing * 0.8);
			puff *= 0.55 + 0.45 * noise(from_landing * 9.0 + TIME);
			dust_alpha = max(dust_alpha, puff * 0.8 * smoothstep(0.0, 0.5, fade));
			// cracks in the ground: thin ridges of noise around the landing, widest near the rock
			float ridge = 1.0 - smoothstep(0.0, 0.07, abs(noise(from_landing * 6.0 + hash(cell) * 40.0) - 0.5));
			float reach = 1.0 - smoothstep(radius, 0.95, length(from_landing));
			crack_alpha = max(crack_alpha, ridge * reach * smoothstep(0.0, 0.4, since_landing) * smoothstep(0.0, 0.5, fade));
		}
	}

	// stack: cracks (dark with a glowing rim), the rocks on top of them, dust over everything
	vec3 color = result.rgb;
	float alpha = result.a;
	vec4 crack = vec4(mix(vec3(0.08, 0.05, 0.03), CRACK_GLOW, 0.35), crack_alpha * 0.85);
	color = mix(crack.rgb, color, alpha);
	alpha = 1.0 - (1.0 - alpha) * (1.0 - crack.a);
	color = mix(color, DUST, dust_alpha * (1.0 - alpha * 0.5));
	alpha = 1.0 - (1.0 - alpha) * (1.0 - dust_alpha);
	COLOR = vec4(color, clamp(alpha, 0.0, 0.95));
}
