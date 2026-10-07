shader_type canvas_item;
// Table surface: dark worn slate with procedural grain, each half lit by its
// owner's element color, a soft overhead spotlight and a heavy vignette.

uniform vec4 top_tint : source_color = vec4(0.25, 0.45, 0.9, 1.0);
uniform vec4 bottom_tint : source_color = vec4(0.9, 0.35, 0.15, 1.0);
uniform float divider_y = 0.452;
uniform float aspect = 1.7778;
uniform float intensity = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
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

void fragment() {
	vec2 uv = UV;
	vec2 p = vec2(uv.x * aspect, uv.y);

	// base slate with large cloudy variation and fine grain
	// (kept cheap on purpose: this runs on every pixel every frame, phones included)
	float cloud = fbm(p * 2.2, 3);
	float grain = hash(floor(p * 220.0));
	float vn = fbm(p * 5.0 + cloud * 2.0, 3);
	float veins = smoothstep(0.48, 0.5, vn) * (1.0 - smoothstep(0.5, 0.53, vn));
	vec3 col = mix(vec3(0.035, 0.032, 0.05), vec3(0.085, 0.078, 0.11), cloud);
	col += (grain - 0.5) * 0.025;
	col += veins * 0.035;

	// element light pooling on each half, slowly breathing
	float breathe = 0.85 + 0.15 * sin(TIME * 0.6);
	float top_w = 1.0 - smoothstep(0.0, divider_y, uv.y);
	float bot_w = smoothstep(divider_y, 1.0, uv.y);
	float center_x = max(0.0, 1.0 - pow(abs(uv.x - 0.52) * 1.6, 2.0));
	col += top_tint.rgb * 0.16 * top_w * center_x * breathe * intensity;
	col += bottom_tint.rgb * 0.16 * bot_w * center_x * breathe * intensity;

	// overhead spotlight on the play area
	vec2 d = vec2((uv.x - 0.52) * aspect * 0.55, uv.y - 0.47);
	col *= 0.55 + 0.75 * exp(-dot(d, d) * 3.2);

	// vignette
	vec2 v = uv - 0.5;
	col *= 1.0 - smoothstep(0.35, 0.95, length(v * vec2(1.15, 1.35)));

	COLOR = vec4(col, 1.0);
}
