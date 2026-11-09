shader_type canvas_item;
// The light destroy (any card of the element luz that destroys one unit): the unit is smitten by holy light.
// A pillar of golden-white light falls from above onto the card, the card is washed out by a bright veil, and
// a halo (a ring plus soft rays) opens from its middle. The unit dissolves while the veil fades.
// Drawn on ONE ColorRect much taller than the card (the pillar comes from above) and a little wider, with
// normal blending, no textures and no screen reads.
// FxCasts._smite_unit tweens `progress` (the pillar falling), `wash` (the veil over the card), `halo` (the ring
// opening) and `beam_strength` (the pillar fading out), and tells the shader how big the card is in `card_uv_size`.
// Cost: 1 value-noise lookup for the pillar, 1 for the shimmer, no loops.
// Coordinates: UV.y = 0 at the top of the rectangle; the card sits in the middle of it.

uniform float progress = 0.0; // 0 = the pillar has not started, 1 = it has fallen all the way down
uniform float wash = 0.0; // 0 = the card is as it is, 1 = washed out by the light
uniform float halo = 0.0; // 0 = the halo has not opened, 1 = it has opened as far as it goes
uniform float beam_strength = 1.0; // 1 = full pillar, 0 = gone
uniform float aspect = 0.5; // rectangle width / height, so the shapes are not stretched
uniform vec2 card_uv_size = vec2(0.6, 0.42); // the size of the card inside the rectangle, as a fraction of it

const vec3 GOLD = vec3(1.0, 0.82, 0.45);
const vec3 WHITE_GOLD = vec3(1.0, 0.97, 0.86);

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
	vec2 middle = vec2((UV.x - 0.5) * aspect, UV.y - 0.5); // 0,0 = the middle of the card
	float radius = length(middle);
	// the rectangle's own edges fade out, so no hard line is left in the middle of the screen
	float edge = smoothstep(0.0, 0.14, UV.x) * smoothstep(0.0, 0.14, 1.0 - UV.x) * smoothstep(0.0, 0.3, UV.y) * smoothstep(0.0, 0.1, 1.0 - UV.y);

	// --- the pillar: a column of light with a slightly wavering edge, falling from the top
	float half_width = card_uv_size.x * 0.5 * aspect * 0.55;
	float wobble = 1.0 + 0.12 * (noise(vec2(middle.y * 18.0, TIME * 6.0)) - 0.5);
	float across = abs(middle.x) / (half_width * wobble);
	float core = 1.0 - smoothstep(0.0, 1.0, across);
	float glow = exp(-across * 0.9) * 0.45;
	float head = progress * 1.05;
	float fallen = 1.0 - smoothstep(head - 0.03, head, UV.y);
	float head_flare = exp(-abs(UV.y - head) * 25.0) * step(0.001, progress) * 0.6;
	float shimmer = 0.86 + 0.14 * noise(vec2(middle.x * 38.0, UV.y * 5.0 - TIME * 5.0));
	float beam_alpha = clamp((core + glow + head_flare * core) * fallen * shimmer, 0.0, 1.0) * 0.9 * beam_strength * edge;
	vec3 beam_color = mix(GOLD, WHITE_GOLD, core);

	// --- the veil over the card: strongest in the middle, with the shape of the card
	vec2 from_card = abs(UV - 0.5) / (card_uv_size * 0.5);
	float on_card = (1.0 - smoothstep(0.92, 1.0, from_card.x)) * (1.0 - smoothstep(0.94, 1.0, from_card.y));
	float veil_alpha = wash * (0.62 + 0.3 * (1.0 - smoothstep(0.0, 0.6, length(from_card)))) * on_card;

	// --- the halo: an expanding ring, and soft rays that fade as it opens
	float ring_radius = halo * 0.22;
	float ring_alpha = exp(-abs(radius - ring_radius) * 55.0) * (1.0 - halo) * step(0.001, halo) * 0.9;
	float angle = atan(middle.y, middle.x);
	float rays = pow(0.5 + 0.5 * sin(angle * 7.0 + 1.3), 6.0) * exp(-radius * 7.0);
	float ray_alpha = rays * halo * (1.0 - halo) * 3.2;
	float halo_alpha = clamp(ring_alpha + ray_alpha, 0.0, 1.0) * edge;

	// --- stack them: pillar, then veil, then halo
	vec3 color = beam_color;
	float alpha = beam_alpha;
	color = mix(color, WHITE_GOLD, veil_alpha);
	alpha = 1.0 - (1.0 - alpha) * (1.0 - veil_alpha);
	color = mix(color, mix(GOLD, WHITE_GOLD, 0.5), halo_alpha);
	alpha = 1.0 - (1.0 - alpha) * (1.0 - halo_alpha);

	COLOR = vec4(color, alpha);
}
