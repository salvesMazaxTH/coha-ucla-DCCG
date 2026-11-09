shader_type canvas_item;
// The lightning destroy (any card of the element raio that destroys one unit): the unit is electrocuted.
// Jagged bolts strike the card from above and keep crackling over it (they redraw their zigzag many times
// a second and blink on and off), the whole card strobing blue-white. Twice, very quickly, a skeleton
// "X-ray" flashes over the card, like in the cartoons: the body goes dark blue and the bones light up.
// Drawn on ONE ColorRect a little bigger than the card, with normal blending, no textures and no screen reads.
// FxCasts._electrocute_unit tweens `progress` (the bolts striking), `xray` (each of the two flashes) and
// `fade` (everything dying out).
// Cost: 4 bolts (4 x 4 cheap noise lookups) plus about 20 simple shapes for the skeleton, no big loops, so it
// stays cheap on phones.
// Coordinates: UV.y = 0 at the top of the rectangle.

uniform float progress = 0.0; // 0 = no bolt yet, 1 = the bolts have all struck
uniform float xray = 0.0; // 0 = no X-ray, 1 = the peak of an X-ray flash
uniform float fade = 1.0; // 1 = full strength, 0 = everything gone
uniform float aspect = 0.75; // rectangle width / height, so the shapes are not stretched

const vec3 BOLT_CORE = vec3(0.93, 0.96, 1.0);
const vec3 BOLT_GLOW = vec3(0.42, 0.48, 1.0);
const vec3 XRAY_BONE = vec3(0.86, 0.98, 1.0);
const vec3 XRAY_BODY = vec3(0.03, 0.07, 0.24);
const float BOLTS_PER_SECOND = 22.0; // how often the zigzags are redrawn

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// smooth 1D noise
float noise(float x) {
	float cell = floor(x);
	float inside = fract(x);
	float blend = inside * inside * (3.0 - 2.0 * inside);
	return mix(hash(cell), hash(cell + 1.0), blend);
}

// one bolt falling from the top: returns (bright core, soft glow). `seed` changes the zigzag, `base_x` is
// where the bolt is on average, `reach` is how far down it has struck (0 to 1)
vec2 bolt(vec2 p, float seed, float base_x, float reach) {
	float here = base_x + (noise(p.y * 8.0 + seed) - 0.5) * 0.30 + (noise(p.y * 27.0 + seed * 2.7) - 0.5) * 0.08;
	float below = base_x + (noise((p.y + 0.01) * 8.0 + seed) - 0.5) * 0.30 + (noise((p.y + 0.01) * 27.0 + seed * 2.7) - 0.5) * 0.08;
	float slant = (below - here) / 0.01;
	// distance to the line, corrected for how slanted it is, so the bolt keeps the same width everywhere
	float dist = abs(p.x - here) / sqrt(1.0 + slant * slant);
	float arrived = 1.0 - smoothstep(reach - 0.05, reach, p.y);
	float core = (1.0 - smoothstep(0.0, 0.007, dist)) * arrived;
	float glow = exp(-dist * 38.0) * 0.55 * arrived;
	return vec2(core, glow);
}

// a bar from a to b, w thick (soft edge)
float bar(vec2 p, vec2 a, vec2 b, float w) {
	vec2 from_a = p - a;
	vec2 along = b - a;
	float h = clamp(dot(from_a, along) / dot(along, along), 0.0, 1.0);
	return 1.0 - smoothstep(w * 0.55, w, length(from_a - along * h));
}

// a filled oval at c with radii r
float oval(vec2 p, vec2 c, vec2 r) {
	return 1.0 - smoothstep(0.9, 1.0, length((p - c) / r));
}

// the outline of an oval (a rib, the hips), w thick
float outline(vec2 p, vec2 c, vec2 r, float w) {
	float dist = abs(length((p - c) / r) - 1.0) * min(r.x, r.y);
	return 1.0 - smoothstep(w * 0.55, w, dist);
}

// the skeleton, standing in the middle of the card (0 = no bone, 1 = bone)
float skeleton(vec2 s) {
	// everything but the head, the spine and the ribs is drawn once, on the right side, and mirrored
	vec2 m = vec2(abs(s.x), s.y);
	float w = 0.014;
	// skull: an oval with the two eye holes and the nose cut out of it, and a jaw with teeth
	float skull = oval(s, vec2(0.0, -0.28), vec2(0.075, 0.08));
	skull *= 1.0 - oval(m, vec2(0.03, -0.285), vec2(0.02, 0.022));
	skull *= 1.0 - oval(s, vec2(0.0, -0.245), vec2(0.008, 0.014));
	float jaw = oval(s, vec2(0.0, -0.205), vec2(0.048, 0.03)) * (0.55 + 0.45 * step(0.0, sin(s.x * 330.0)));
	float bones = max(skull, jaw);
	// spine, with its vertebrae
	bones = max(bones, bar(s, vec2(0.0, -0.18), vec2(0.0, 0.13), 0.012) * (0.65 + 0.35 * step(0.0, sin(s.y * 170.0))));
	// collarbones and arms (upper arm, forearm, hand)
	bones = max(bones, bar(m, vec2(0.0, -0.172), vec2(0.1, -0.19), w * 0.8));
	bones = max(bones, bar(m, vec2(0.1, -0.19), vec2(0.175, -0.06), w));
	bones = max(bones, bar(m, vec2(0.175, -0.06), vec2(0.135, 0.075), w));
	bones = max(bones, oval(m, vec2(0.135, 0.09), vec2(0.016, 0.022)));
	// ribs: five curves hanging from the spine, shorter toward the bottom
	for (int rib = 0; rib < 5; rib++) {
		float height = -0.15 + float(rib) * 0.036;
		float hanging = step(height, s.y); // only the lower half of each oval is a rib
		bones = max(bones, outline(s, vec2(0.0, height), vec2(0.115 - float(rib) * 0.011, 0.04), 0.011) * hanging);
	}
	// hips and legs (thigh, shin, foot), knees as round dots
	bones = max(bones, outline(s, vec2(0.0, 0.165), vec2(0.082, 0.042), 0.013));
	bones = max(bones, bar(m, vec2(0.045, 0.175), vec2(0.065, 0.31), w * 1.1));
	bones = max(bones, oval(m, vec2(0.065, 0.315), vec2(0.02, 0.02)));
	bones = max(bones, bar(m, vec2(0.065, 0.32), vec2(0.052, 0.44), w));
	bones = max(bones, bar(m, vec2(0.052, 0.445), vec2(0.1, 0.46), w));
	return bones;
}

void fragment() {
	// the zigzags are redrawn this many times a second
	float tick = floor(TIME * BOLTS_PER_SECOND);
	vec2 p = vec2(UV.x * aspect, UV.y);
	float strike = clamp(progress * 3.5, 0.0, 1.0);
	float reach = progress * 1.35;

	// --- the bolts: four of them across the card, each blinking on and off on its own
	vec2 total = vec2(0.0);
	for (int index = 0; index < 4; index++) {
		float number = float(index);
		float seed = tick * 13.7 + number * 5.3;
		float base_x = aspect * (0.2 + 0.2 * number) + (hash(tick + number * 9.1) - 0.5) * 0.08;
		float blink = step(0.3, hash(tick * 3.1 + number * 17.0));
		total = max(total, bolt(p, seed, base_x, reach) * blink);
	}
	float bolt_alpha = clamp(total.x + total.y, 0.0, 1.0) * strike;
	vec3 bolt_color = mix(BOLT_GLOW, BOLT_CORE, clamp(total.x * 1.2, 0.0, 1.0));

	// --- a blue-white strobe over the whole card, on some of the redraws only
	float inside = smoothstep(0.07, 0.09, UV.x) * smoothstep(0.07, 0.09, 1.0 - UV.x)
		* smoothstep(0.04, 0.06, UV.y) * smoothstep(0.04, 0.06, 1.0 - UV.y);
	float strobe = step(0.55, hash(tick * 1.7 + 3.0)) * 0.3 * strike * inside;

	// --- the X-ray: the card goes dark blue and the bones light up (with a few scanlines, and the picture
	// shivering sideways a little, like a bad screen)
	float shiver = (hash(floor(UV.y * 48.0) + tick) - 0.5) * 0.02 * xray;
	vec2 skeleton_spot = vec2((UV.x - 0.5) * aspect + shiver, UV.y - 0.5);
	float bones = skeleton(skeleton_spot) * xray;
	float scanlines = 0.88 + 0.12 * sin(UV.y * 260.0);
	float xray_body = xray * 0.62 * inside;
	vec3 xray_color = mix(XRAY_BODY, XRAY_BONE, bones) * scanlines;
	float xray_alpha = clamp(xray_body + bones * inside, 0.0, 1.0);

	// --- stack them: strobe under the X-ray, bolts over everything
	vec3 color = mix(BOLT_GLOW, BOLT_CORE, 0.5);
	float alpha = strobe;
	color = mix(color, xray_color, xray_alpha);
	alpha = 1.0 - (1.0 - alpha) * (1.0 - xray_alpha);
	color = mix(color, bolt_color, bolt_alpha);
	alpha = 1.0 - (1.0 - alpha) * (1.0 - bolt_alpha);

	COLOR = vec4(color, alpha * fade);
}
