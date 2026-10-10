shader_type canvas_item;
// Banish: the card drains of colour, turns pale and is swallowed by a closing hole that
// shrinks toward its center, leaving a glowing rim (unlike the dissolve, nothing is left to burn).

uniform vec2 size = vec2(120.0, 170.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(0.8, 0.7, 1.0, 1.0);
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
	vec2 p = (local / size - 0.5) * 2.0;
	float r = length(p) / 1.2;
	float ang = atan(p.y, p.x);
	// ragged, swirling edge of the hole
	float wob = (noise(vec2(ang * 2.0 + progress * 6.0, r * 3.0)) - 0.5) * 0.18;
	float radius = 1.0 - progress * 1.15;
	float d = radius + wob - r;
	if (d < 0.0) {
		discard;
	}
	float luma = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	vec3 pale = mix(COLOR.rgb, vec3(luma), clamp(progress * 2.0, 0.0, 1.0));
	pale = mix(pale, edge_color.rgb, clamp(progress * 0.6, 0.0, 0.6));
	float e = 1.0 - smoothstep(0.0, 0.12, d);
	COLOR.rgb = mix(pale, edge_color.rgb * 2.0, e * step(0.001, progress));
}
