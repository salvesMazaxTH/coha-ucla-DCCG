shader_type canvas_item;
// Rai's execution, the veil over the whole screen: the table sinks into a violet void, and ten ink arms
// (the ten Fragments) wind in a spiral into the doomed Leader, as if it were being swallowed. No flash and
// no shockwave: the Leader just comes apart and the void quietly lifts.
// Drawn on ONE ColorRect over the whole screen, with normal blending, so the dark really darkens the table.
// FxExecutions._rai tweens `veil` (the darkness coming and going).
// Cost: 2 noise lookups per pixel and no loops, so it stays cheap on phones.

uniform float veil = 0.0; // 0 = no void, 1 = the table fully sunk in it
uniform vec2 focus = vec2(0.5); // the Leader's center, in UV
uniform float aspect = 1.0; // width / height, so the spiral is round, not stretched
uniform vec4 accent : source_color = vec4(0.65, 0.24, 1.0, 1.0);

const vec3 VOID = vec3(0.035, 0.0, 0.07);
const mat2 TURN = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

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

void fragment() {
	vec2 offset = (UV - focus) * vec2(aspect, 1.0);
	float dist = max(length(offset), 0.0001);
	float angle = atan(offset.y, offset.x);

	// ten arms on a log spiral; the phase grows with time, so they keep flowing inward
	float arms = 0.5 + 0.5 * sin(10.0 * angle + 7.0 * log(dist) + TIME * 5.0);
	float ink = noise(TURN * offset * 7.0 + vec2(TIME * 0.4, 0.0)) * 0.6 + noise(offset * 19.0 - TIME * 0.7) * 0.4;
	float tendril = smoothstep(0.62, 0.95, arms * 0.75 + ink * 0.45);
	tendril *= smoothstep(1.5, 0.05, dist) * smoothstep(0.0, 0.06, dist);

	// the void: darker at the edges, a little thinner right on the Leader so it stays readable
	float darkness = veil * (0.62 + 0.28 * smoothstep(0.15, 1.1, dist));
	darkness *= mix(0.25, 1.0, smoothstep(0.06, 0.28, dist));

	vec3 glow = accent.rgb * tendril * veil * 1.1;
	glow += accent.rgb * exp(-dist * 9.0) * veil * 0.9; // the core the arms pour into

	float glow_strength = clamp(max(glow.r, max(glow.g, glow.b)), 0.0, 1.0);
	float alpha = clamp(darkness + glow_strength, 0.0, 1.0);
	vec3 color = (VOID * darkness + glow) / max(alpha, 0.001);
	COLOR = vec4(min(color, vec3(1.0)), alpha);
}
