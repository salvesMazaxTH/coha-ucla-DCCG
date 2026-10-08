shader_type canvas_item;
// Furtividade: the unit turns half see-through (the art most of all) while a slow,
// warped fog drifts across the card. Works in local space like dissolve.gdshader.

uniform vec2 size = vec2(120.0, 170.0);
uniform vec4 mist_color : source_color = vec4(0.80, 0.77, 0.93, 1.0);
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = local / size;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	// art window (~y 8..106 of 170): the most ghostly part; frame, name and gems stay readable
	float art = smoothstep(0.03, 0.07, uv.y) * (1.0 - smoothstep(0.58, 0.63, uv.y));
	float t = TIME * 0.11;
	vec2 p = uv * vec2(2.6, 3.6);
	float warp = fbm(p + vec2(t, t * 0.4));
	float n = fbm(p + vec2(warp * 1.5 - t * 0.7, -t * 0.3));
	float mist = smoothstep(0.42, 0.78, n) * inside;
	float breathe = 0.5 + 0.5 * sin(TIME * 1.2);
	COLOR.rgb = mix(COLOR.rgb, mist_color.rgb, mist * mix(0.28, 0.6, art));
	float see = mix(0.82, 0.5 + 0.08 * breathe, art * inside);
	COLOR.a *= mix(see, 0.92, mist * art);
}
