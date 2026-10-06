shader_type canvas_item;
// Round portrait: circular mask (in local space, so it works with cropped
// texture regions), rim shading and optional desaturation.

uniform vec2 size = vec2(120.0, 120.0);
uniform float grey = 0.0;
varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 c = local / size - 0.5;
	float r = length(c);
	vec4 tex = texture(TEXTURE, UV);
	vec3 col = mix(tex.rgb, vec3(dot(tex.rgb, vec3(0.299, 0.587, 0.114))), grey);
	col *= 1.0 - smoothstep(0.28, 0.5, r) * 0.5;
	COLOR = vec4(col, tex.a * (1.0 - smoothstep(0.49, 0.5, r)));
}
