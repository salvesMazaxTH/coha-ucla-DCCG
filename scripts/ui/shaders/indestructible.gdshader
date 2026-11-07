shader_type canvas_item;
// Indestrutível on a unit: the card looks forged from polished steel. A silver rim hugs the card's
// rounded frame with a soft halo outside it, two glints run around that rim, and every few seconds
// a diagonal sheen sweeps over the face and lights up a faint diamond-hard lattice where it passes.
// Silver/white on purpose: the shields already use cyan (Escudo), violet (Mágico) and gold (Supremo).
// Drawn on a ColorRect a bit bigger than the card face (see CardView._place_indestructible_glow);
// the GPU animates it, so the card itself never has to redraw.

uniform vec2 rect_size = vec2(200.0, 280.0); // the ColorRect, in pixels
uniform float margin = 8.0; // pixels of room around the card face, for the halo
uniform float corner_radius = 10.0; // the card frame's rounded corners, in pixels
uniform float base_pixel = 1.0; // one card base pixel (the "s" in CardView), in screen pixels
uniform float phase = 0.0; // per-card time offset, so two indestructible cards don't shine in lockstep

const vec3 STEEL = vec3(0.86, 0.90, 0.95);
const vec3 WHITE_HOT = vec3(1.0, 0.99, 0.94);
const float FULL_TURN = 6.28318530718;

// distance to a rounded box centered at 0 (negative = inside)
float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// distance to the nearest line of a hexagon grid (0 = on a line)
float hex_lines(vec2 uv) {
	vec2 ratio = vec2(1.0, 1.7320508);
	vec2 half_ratio = ratio * 0.5;
	vec2 a = mod(uv, ratio) - half_ratio;
	vec2 b = mod(uv - half_ratio, ratio) - half_ratio;
	vec2 inside = dot(a, a) < dot(b, b) ? a : b;
	vec2 folded = abs(inside);
	float to_center = max(dot(folded, normalize(ratio)), folded.x);
	return 0.5 - to_center;
}

void fragment() {
	float t = TIME + phase;
	vec2 face_size = rect_size - vec2(2.0 * margin);
	vec2 p = UV * rect_size - rect_size * 0.5; // pixels from the card's center
	float edge = rounded_box(p, face_size * 0.5, corner_radius); // < 0 = on the card
	vec4 result = vec4(0.0);

	// where along the frame this pixel is (0..1 around the card), for the glints
	float around = atan(p.y / face_size.y, p.x / face_size.x) / FULL_TURN + 0.5;
	float glint = 0.0;
	for (int i = 0; i < 2; i++) {
		float head = fract(t * 0.22 + float(i) * 0.5);
		float gap = abs(fract(around - head + 0.5) - 0.5);
		glint = max(glint, exp(-gap * gap / 0.0016));
	}

	// the soft halo just outside the card, brighter where a glint passes
	float outside = max(edge, 0.0);
	float halo = exp(-outside / (3.0 * base_pixel)) * step(0.0, edge);
	result = vec4(STEEL, halo * (0.22 + 0.45 * glint));

	// the polished rim right on the frame
	float rim_width = 1.3 * base_pixel;
	float rim = 1.0 - smoothstep(rim_width - 0.75, rim_width + 0.75, abs(edge));
	vec3 rim_color = mix(STEEL, WHITE_HOT, glint);
	result.rgb = mix(result.rgb, rim_color, rim);
	result.a = max(result.a, rim * (0.6 + 0.4 * glint));

	// the sheen: a diagonal band of light crossing the face every few seconds, with the lattice in it
	float diagonal = (p.x + p.y * 0.6) / (face_size.x * 0.5 + face_size.y * 0.3); // -1..1 across the card
	float sweep = fract(t / 3.4) * 3.4 - 1.4; // runs from -1.4 to 2.0: on the card for ~1s, then a pause
	float band = exp(-pow((diagonal - sweep) / 0.16, 2.0)) * step(edge, 0.0);
	float lattice = 1.0 - smoothstep(0.0, 0.06, hex_lines(p / (13.0 * base_pixel)));
	float sheen = band * (0.16 + 0.5 * lattice);
	result.rgb = mix(result.rgb, WHITE_HOT, sheen / max(sheen + result.a, 0.0001));
	result.a = max(result.a, sheen);

	COLOR = result;
}
