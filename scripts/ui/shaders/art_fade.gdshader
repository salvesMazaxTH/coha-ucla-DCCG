shader_type canvas_item;
// Large splash art for the menu: fades out toward one side and the bottom.

uniform float fade_from_right = 1.0; // 1 = fades toward the right edge
uniform float strength = 1.0;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float x = mix(UV.x, 1.0 - UV.x, 1.0 - fade_from_right);
	float a = (1.0 - smoothstep(0.35, 1.0, x)) * (1.0 - smoothstep(0.6, 1.0, UV.y));
	COLOR = vec4(tex.rgb * 0.85, tex.a * a * strength);
}
