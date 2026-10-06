shader_type canvas_item;
// Burn-away dissolve for code-drawn cards: value noise in local space eats
// the card from the top, leaving a glowing ember edge.

uniform vec2 size = vec2(120.0, 170.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.55, 0.15, 1.0);
varying vec2 local;

void vertex() {
	local = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = local / size;
	float n = noise(uv * vec2(5.0, 7.0)) * 0.6 + noise(uv * vec2(16.0, 22.0)) * 0.4;
	n = n * 0.7 + clamp(uv.y, 0.0, 1.0) * 0.3;
	float d = n - (progress * 1.2 - 0.1);
	if (d < 0.0) {
		discard;
	}
	float e = 1.0 - smoothstep(0.0, 0.08, d);
	COLOR.rgb = mix(COLOR.rgb, edge_color.rgb * 1.8, e * step(0.001, progress));
}
