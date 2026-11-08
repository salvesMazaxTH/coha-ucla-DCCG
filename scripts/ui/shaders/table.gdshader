shader_type canvas_item;
// Background of the whole game. Two looks, chosen by `marble_floor`:
// - false (menus, deck builder...): plain dark slate, so the menu art stays in front.
// - true (only during a match): the battle table, described below.
//
// Battle table: an arena floor of polished dark marble slabs (Nero-Marquina style:
// near-black stone with pale and golden veins), laid in staggered rows with worn,
// chipped joints and battle scuffs. Each half is lit by its owner's element colour,
// with an overhead spotlight, a polished sheen and a heavy vignette.
//
// Everything is procedural (no texture files). It is cheap enough because main.gd
// bakes this shader ONCE into a SubViewport texture, it does not run every frame.

uniform vec4 top_tint : source_color = vec4(0.25, 0.45, 0.9, 1.0);
uniform vec4 bottom_tint : source_color = vec4(0.9, 0.35, 0.15, 1.0);
uniform float divider_y = 0.452;
uniform float aspect = 1.7778;
uniform float intensity = 1.0;
uniform bool marble_floor = false; // main.gd turns it on only while the match table is on screen

const float SLAB_HEIGHT = 0.36; // one row of slabs, in screen heights
const float SLAB_WIDTH = 0.72;
const float JOINT_WIDTH = 0.0022; // the dark groove between two slabs
const vec3 STONE_DARK = vec3(0.068, 0.065, 0.074);
const vec3 STONE_LIGHT = vec3(0.205, 0.195, 0.210);
const vec3 VEIN_PALE = vec3(0.62, 0.60, 0.58);
const vec3 VEIN_GOLD = vec3(0.62, 0.47, 0.24);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + vec2(17.3, 41.9)));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// Turbulence: like fbm but with creases (abs of signed noise). Creases are what make marble veins fork and wander.
float turbulence(vec2 p, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		v += a * abs(noise(p) * 2.0 - 1.0);
		p = p * 2.07 + vec2(3.1, 7.7);
		a *= 0.5;
	}
	return v;
}

// Thin bright line where `field` crosses a sine wave: the classic marble vein.
float vein_line(float field, float sharpness) {
	return pow(1.0 - abs(sin(field)), sharpness);
}

// The marble pattern of one slab. `seed` makes every slab cut from a different part of the block.
vec3 marble(vec2 p, vec2 seed) {
	// the whole floor shares one vein direction (as if cut from one block), each slab slightly turned
	float angle = 0.55 + (seed.x - 0.5) * 0.5;
	mat2 rotation = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle)));
	vec2 q = rotation * p + seed * 23.0;

	// stone body: deep layered clouds, like looking a little way into polished stone
	float deep = fbm(q * 1.8 + 4.0, 5);
	float mottling = fbm(q * 7.0 + deep * 2.0, 4);
	vec3 col = mix(STONE_DARK, STONE_LIGHT, smoothstep(0.3, 0.75, deep));
	col *= 0.85 + mottling * 0.3;

	// main veins: long streaks along the vein direction, wandering and forking via turbulence
	float main_field = q.y * 6.0 + turbulence(q * vec2(0.8, 1.5), 6) * 7.0;
	float main_core = vein_line(main_field, 90.0);
	float main_soft = vein_line(main_field, 6.0);
	float main_presence = smoothstep(0.25, 0.55, fbm(q * vec2(0.7, 1.4) + 9.0, 3)); // veins fade in and out
	// a cloudy, milky band around each main vein
	col = mix(col, col + VEIN_PALE * 0.16, main_soft * main_presence);
	col = mix(col, VEIN_PALE, main_core * main_presence * 0.85);

	// secondary veins: thinner, crossing the main ones at an angle
	vec2 r = mat2(vec2(0.6, -0.8), vec2(0.8, 0.6)) * q;
	float second_field = r.y * 11.0 + turbulence(r * 1.9 + 31.0, 5) * 9.0;
	float second = vein_line(second_field, 160.0) * smoothstep(0.4, 0.65, fbm(r * 1.2 + 17.0, 3));
	col = mix(col, VEIN_PALE * 0.75, second * 0.7);

	// hairline crackle web, very faint
	float hair = vein_line(q.x * 9.0 + turbulence(q * 3.5 + 51.0, 4) * 14.0, 200.0) * smoothstep(0.4, 0.7, fbm(q * 2.0 + 3.0, 3));
	col += VEIN_PALE * hair * 0.22;

	// golden veins: rare, following the main flow but offset
	float gold_field = q.y * 3.0 + turbulence(q * vec2(0.8, 1.5) + 2.5, 6) * 5.0 + 1.3;
	float gold = vein_line(gold_field, 180.0) * smoothstep(0.55, 0.72, fbm(q * 0.8 + 13.0, 3));
	col = mix(col, VEIN_GOLD, gold * 0.75);

	// fine crystalline grain of the stone surface
	col += (hash(floor(p * 900.0)) - 0.5) * 0.010;
	return col;
}

// Menu background: the original dark worn slate, lit by the two tints, spotlight and vignette.
vec3 slate_floor(vec2 uv) {
	vec2 p = vec2(uv.x * aspect, uv.y);
	float cloud = fbm(p * 2.2, 3);
	float grain = hash(floor(p * 220.0));
	float vn = fbm(p * 5.0 + cloud * 2.0, 3);
	float veins = smoothstep(0.48, 0.5, vn) * (1.0 - smoothstep(0.5, 0.53, vn));
	vec3 col = mix(vec3(0.035, 0.032, 0.05), vec3(0.085, 0.078, 0.11), cloud);
	col += (grain - 0.5) * 0.025;
	col += veins * 0.035;

	float top_w = 1.0 - smoothstep(0.0, divider_y, uv.y);
	float bot_w = smoothstep(divider_y, 1.0, uv.y);
	float center_x = max(0.0, 1.0 - pow(abs(uv.x - 0.52) * 1.6, 2.0));
	col += top_tint.rgb * 0.136 * top_w * center_x * intensity;
	col += bottom_tint.rgb * 0.136 * bot_w * center_x * intensity;

	vec2 d = vec2((uv.x - 0.52) * aspect * 0.55, uv.y - 0.47);
	col *= 0.55 + 0.75 * exp(-dot(d, d) * 3.2);
	vec2 v = uv - 0.5;
	col *= 1.0 - smoothstep(0.35, 0.95, length(v * vec2(1.15, 1.35)));
	return col;
}

// Match background: the marble slab floor.
vec3 battle_marble_floor(vec2 uv) {
	vec2 p = vec2(uv.x * aspect, uv.y);

	// --- slab layout: staggered rows (running bond), with a joint running along the divider line ---
	vec2 grid = vec2(p.x, p.y - divider_y + SLAB_HEIGHT * 4.0);
	float row = floor(grid.y / SLAB_HEIGHT);
	grid.x += mod(row, 2.0) * SLAB_WIDTH * 0.5; // every other row shifted by half a slab
	vec2 cell = vec2(floor(grid.x / SLAB_WIDTH), row);
	vec2 local = vec2(fract(grid.x / SLAB_WIDTH) * SLAB_WIDTH, fract(grid.y / SLAB_HEIGHT) * SLAB_HEIGHT);
	vec2 seed = hash2(cell + 3.7);

	// distance to the nearest joint, roughened so the edges look chipped, not machine-cut
	float edge_wobble = (fbm(p * 60.0, 2) - 0.5) * 0.0025;
	float dist_x = min(local.x, SLAB_WIDTH - local.x);
	float dist_y = min(local.y, SLAB_HEIGHT - local.y);
	float dist_to_joint = min(dist_x, dist_y) + edge_wobble;

	vec3 col = marble(p, seed);
	// every slab is a slightly different shade, as real stone from different blocks is
	col *= 0.85 + seed.y * 0.3;

	// --- polished bevel: the top/left lip of each slab catches light, the bottom/right falls in shadow ---
	float bevel = 1.0 - smoothstep(0.0, 0.006, dist_to_joint);
	float lit_side = (local.y < SLAB_HEIGHT * 0.5 ? 1.0 : -1.0) * step(dist_y, dist_x)
		+ (local.x < SLAB_WIDTH * 0.5 ? 0.6 : -0.6) * step(dist_x, dist_y);
	col += bevel * lit_side * 0.035;

	// --- joints: dark grout line, with dirt gathering next to it ---
	float joint = 1.0 - smoothstep(JOINT_WIDTH * 0.5, JOINT_WIDTH, dist_to_joint);
	float grime = (1.0 - smoothstep(0.0, 0.03, dist_to_joint)) * fbm(p * 18.0, 3);
	col *= 1.0 - grime * 0.35;
	col = mix(col, vec3(0.012, 0.011, 0.014), joint);

	// --- battle wear: scuffed, duller patches and a few fine scratches ---
	float wear = smoothstep(0.55, 0.85, fbm(p * 3.5 + 40.0, 4));
	col = mix(col, col * 0.78 + vec3(0.012), wear * 0.6);
	vec2 scratch_p = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	float scratches = vein_line(scratch_p.x * 140.0 + fbm(scratch_p * 8.0, 2) * 4.0, 400.0);
	scratches *= smoothstep(0.6, 0.8, fbm(p * 5.0 + 60.0, 3));
	col += scratches * 0.03 * (1.0 - joint);

	// --- element light pooling on each half ---
	float top_w = 1.0 - smoothstep(0.0, divider_y, uv.y);
	float bot_w = smoothstep(divider_y, 1.0, uv.y);
	float center_x = max(0.0, 1.0 - pow(abs(uv.x - 0.52) * 1.6, 2.0));
	col += top_tint.rgb * 0.13 * top_w * center_x * intensity;
	col += bottom_tint.rgb * 0.13 * bot_w * center_x * intensity;

	// --- overhead spotlight on the play area ---
	vec2 d = vec2((uv.x - 0.52) * aspect * 0.55, uv.y - 0.47);
	float spotlight = exp(-dot(d, d) * 3.2);
	col *= 0.6 + 0.75 * spotlight;

	// polished sheen: a broad soft reflection of the overhead light, stronger where the stone is not scuffed
	vec2 sheen_d = vec2((uv.x - 0.45) * aspect * 0.7, (uv.y - 0.38) * 1.4);
	float sheen = exp(-dot(sheen_d, sheen_d) * 2.5) * (1.0 - wear * 0.7) * (1.0 - joint);
	col += vec3(0.05, 0.048, 0.055) * sheen;

	// vignette
	vec2 v = uv - 0.5;
	col *= 1.0 - smoothstep(0.35, 0.95, length(v * vec2(1.15, 1.35)));
	return col;
}

void fragment() {
	vec3 col = marble_floor ? battle_marble_floor(UV) : slate_floor(UV);
	COLOR = vec4(col, 1.0);
}
