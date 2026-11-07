shader_type canvas_item;
// additive: the light brightens the table under it instead of covering it with a flat color
render_mode blend_add;
// The holy light area cast (Expurgo Sagrado, Última Badalada): shafts of light pour down from the sky
// over the whole arena, a bright band running from the top to the bottom, with motes of light rising
// where it shines. Then the light softly goes out.
// Drawn on ONE ColorRect over the arena. FxCasts._light_area tweens `progress` (the light coming down)
// and `fade` (the light going out).
// Coordinates: UV.y = 0 at the top of the arena, 1 at the bottom. The light always comes from above.

uniform float progress = 0.0; // 0 = no light yet, 1 = the light reached the bottom of the arena
uniform float fade = 1.0; // 1 = shining, 0 = all gone
uniform float aspect = 1.5; // arena width / height

const vec3 LIGHT_GOLD = vec3(1.0, 0.84, 0.48);
const vec3 LIGHT_WHITE = vec3(1.0, 0.98, 0.9);

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

void fragment() {
	vec2 surface = vec2(UV.x * aspect, UV.y);
	// the shafts lean a little, like sun through a high window
	float slanted_x = surface.x + UV.y * 0.22;
	// shafts: bright vertical stripes from noise that only changes sideways, drifting slowly
	float shafts = pow(noise(vec2(slanted_x * 5.0 + TIME * 0.15, 0.5)), 2.2) * 1.3;
	shafts += pow(noise(vec2(slanted_x * 13.0 - TIME * 0.25, 3.5)), 4.0) * 0.8;
	// the light comes down from the top: lit above `reach`, with a soft lower edge
	float reach = progress * 1.3;
	float lit = smoothstep(reach, reach - 0.25, UV.y);
	// the bright band at the leading edge, coming down
	float band = exp(-pow((UV.y - (reach - 0.1)) / 0.09, 2.0)) * (1.0 - smoothstep(0.9, 1.0, progress));
	// stronger near the top (the source), still clear at the bottom
	float falloff = 0.55 + 0.45 * (1.0 - UV.y);

	// motes: small soft points rising slowly inside the light
	vec2 mote_grid = surface * vec2(14.0, 9.0) + vec2(0.0, TIME * 0.9);
	vec2 mote_cell = floor(mote_grid);
	vec2 mote_offset = fract(mote_grid) - 0.5 - (vec2(hash(mote_cell + 1.3), hash(mote_cell + 5.1)) - 0.5) * 0.6;
	float motes = (1.0 - smoothstep(0.03, 0.12, length(mote_offset))) * step(0.78, hash(mote_cell)) * (0.6 + 0.4 * sin(TIME * 5.0 + hash(mote_cell) * 30.0));

	float glow = (0.10 + shafts * 0.42) * falloff * lit + band * 0.32;
	vec3 color = mix(LIGHT_GOLD, LIGHT_WHITE, clamp(shafts * 0.7 + band, 0.0, 1.0));
	vec4 result = vec4(color, glow);
	result.rgb = mix(result.rgb, LIGHT_WHITE, motes);
	result.a = max(result.a, motes * lit * 0.9);
	result.a *= fade;
	COLOR = result;
}
