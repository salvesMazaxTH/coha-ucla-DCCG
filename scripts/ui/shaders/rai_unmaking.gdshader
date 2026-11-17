shader_type canvas_item;
// Rai's execution, the whole Leader: a snapshot of the plate and its gems (Polygon2D pieces sharing that
// picture) turns in a whirlpool around the portrait, loses its color, and comes apart in soft blotches
// from the top down, like something evaporating, until nothing is left. No glowing rim: the edge of each
// hole just turns to dark ash before it goes. FxExecutions._rai spawns the dust and black petals.
// FxExecutions._rai tweens `twist` (the whirlpool) and `unmake` (how much of the picture is gone).
// Cost: 1 texture read and 3 noise lookups per pixel, only on the small Leader card.

uniform float twist = 0.0; // 0 = the picture as it was, 1 = turned all the way into the whirlpool
uniform float unmake = 0.0; // 0 = whole, 1 = all of it gone
uniform vec2 pivot = vec2(0.5); // the whirlpool's center, in UV
uniform float aspect = 1.0; // picture width / height
uniform vec4 accent : source_color = vec4(0.65, 0.24, 1.0, 1.0);

const vec3 ASH = vec3(0.06, 0.04, 0.08);

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

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

vec2 rotate(vec2 v, float a) {
	float s = sin(a);
	float c = cos(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float inside_picture(vec2 uv) {
	return step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
}

void fragment() {
	vec2 offset = (UV - pivot) * vec2(aspect, 1.0);
	float dist = length(offset);
	// only the portrait spirals; the frame and gems far from it barely move, so they stay inside their pieces
	float closeness = max(0.0, 1.0 - dist * 1.3);
	float turn = twist * 2.8 * closeness * closeness;
	vec2 spun = rotate(offset, turn);
	vec2 sample_uv = pivot + spun / vec2(aspect, 1.0);

	vec4 picture = texture(TEXTURE, sample_uv);
	picture.a *= inside_picture(sample_uv);
	float grey = dot(picture.rgb, vec3(0.3, 0.59, 0.11));
	picture.rgb = mix(picture.rgb, grey * mix(vec3(0.9), accent.rgb, 0.35), twist * 0.8);

	// big soft blotches (the size of the dust motes) plus a little grain, the top going first
	float order = noise(UV * 6.0) * 0.6 + noise(UV * 17.0) * 0.15 + noise(spun * 30.0) * 0.05 + UV.y * 0.45;
	float threshold = unmake * 1.35 - 0.1;
	float kept = smoothstep(threshold, threshold + 0.03, order);
	float ash = (1.0 - smoothstep(threshold + 0.03, threshold + 0.1, order)) * step(0.001, unmake);
	COLOR = vec4(mix(picture.rgb, ASH, ash), picture.a * kept);
}
