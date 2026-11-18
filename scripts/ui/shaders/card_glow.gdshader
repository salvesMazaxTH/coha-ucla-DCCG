shader_type canvas_item;
// Everything that keeps moving around or across a card face, animated by the GPU so the card itself never
// has to redraw for it (see CardView._place_card_glow):
// - up to 8 sets of glowing rings around the frame (legendary halo, playable/target glow, Ao Ativar,
//   Reservatório, death ward, frost, stun, condemned);
// - the glassy shine that sweeps across legendary and champion cards;
// - the stars circling a stunned card and the "z"s rising from a summoning-sick one.
// Drawn on a ColorRect a bit bigger than the card face, on top of the card.

uniform vec2 rect_size = vec2(200.0, 280.0); // the ColorRect, in pixels
uniform float margin = 8.0; // pixels of room around the card face, for the rings
uniform float corner_radius = 10.0; // the card frame's rounded corners, in pixels
uniform float chamfer_cut = 0.0; // > 0: the frame has cut corners instead (artifacts), this many pixels long
uniform float base_pixel = 1.0; // one card base pixel (the "s" in CardView), in pixels
uniform float phase = 0.0; // per-card time offset, so two cards don't pulse in lockstep
uniform float dim = 0.0; // 1 = the card is dimmed: what is drawn over the face is darkened like the face
uniform bool shine = false; // the glassy shine of legendary and champion cards
uniform bool stun_stars = false;
uniform bool drowsy = false; // summoning sickness: "z"s rise from the art
uniform vec4 art_rect = vec4(0.0); // the art window: x, y, width, height in pixels from the face's top-left corner

// One ring set per slot (a slot whose color alpha is 0 is off). All sizes are in base pixels.
// color: rgb + strength. shape: ring count, distance of the first ring, distance between rings, line width.
// fade: alpha of the first ring, alpha lost per ring.
// wave: the alpha pulses as base + amplitude * sin(speed * time), times sin(second speed * time) when that is not 0.
uniform vec4 ring0_color = vec4(0.0); uniform vec4 ring0_shape; uniform vec2 ring0_fade; uniform vec4 ring0_wave;
uniform vec4 ring1_color = vec4(0.0); uniform vec4 ring1_shape; uniform vec2 ring1_fade; uniform vec4 ring1_wave;
uniform vec4 ring2_color = vec4(0.0); uniform vec4 ring2_shape; uniform vec2 ring2_fade; uniform vec4 ring2_wave;
uniform vec4 ring3_color = vec4(0.0); uniform vec4 ring3_shape; uniform vec2 ring3_fade; uniform vec4 ring3_wave;
uniform vec4 ring4_color = vec4(0.0); uniform vec4 ring4_shape; uniform vec2 ring4_fade; uniform vec4 ring4_wave;
uniform vec4 ring5_color = vec4(0.0); uniform vec4 ring5_shape; uniform vec2 ring5_fade; uniform vec4 ring5_wave;
uniform vec4 ring6_color = vec4(0.0); uniform vec4 ring6_shape; uniform vec2 ring6_fade; uniform vec4 ring6_wave;
uniform vec4 ring7_color = vec4(0.0); uniform vec4 ring7_shape; uniform vec2 ring7_fade; uniform vec4 ring7_wave;

const vec3 SHINE_COLOR = vec3(1.0, 0.96, 0.8);
const vec3 STAR_COLOR = vec3(1.0, 0.9, 0.45);
const vec3 DROWSY_COLOR = vec3(0.765, 0.804, 0.933);

// distance to a rounded box centered at 0 (negative = inside)
float rounded_box(vec2 p, vec2 half_size, float radius) {
	vec2 q = abs(p) - half_size + vec2(radius);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// distance to the card face's outline (negative = on the face)
float face_distance(vec2 p, vec2 half_face) {
	if (chamfer_cut > 0.0) {
		vec2 q = abs(p);
		float corner = (q.x + q.y - (half_face.x + half_face.y - chamfer_cut)) * 0.70710678;
		return max(rounded_box(p, half_face, 0.0), corner);
	}
	return rounded_box(p, half_face, corner_radius);
}

// paints a layer over what is already there (premultiplied colour)
void paint(inout vec4 result, vec3 color, float alpha) {
	result.rgb = color * alpha + result.rgb * (1.0 - alpha);
	result.a = alpha + result.a * (1.0 - alpha);
}

// how strongly one ring set covers a point that is `edge` pixels outside the face
float ring_alpha(float edge, float pixel, vec4 shape, vec2 fade, vec4 wave, float t) {
	float first_distance = shape.y * base_pixel;
	float distance_between = shape.z * base_pixel;
	float half_width = shape.w * base_pixel * 0.5;
	// a point can sit where two neighbouring rings overlap, so both are looked at
	float lower = clamp(floor((edge - first_distance) / distance_between), 0.0, shape.x - 1.0);
	float upper = min(lower + 1.0, shape.x - 1.0);
	float lower_cover = clamp((half_width - abs(edge - first_distance - lower * distance_between)) / pixel + 0.5, 0.0, 1.0);
	float upper_cover = clamp((half_width - abs(edge - first_distance - upper * distance_between)) / pixel + 0.5, 0.0, 1.0);
	if (upper == lower) {
		upper_cover = 0.0;
	}
	float lower_alpha = max(fade.x - lower * fade.y, 0.0) * lower_cover;
	float upper_alpha = max(fade.x - upper * fade.y, 0.0) * upper_cover;
	float pulse = wave.x + wave.y * sin(wave.z * t) * (wave.w > 0.0 ? sin(wave.w * t) : 1.0);
	return (lower_alpha + upper_alpha * (1.0 - lower_alpha)) * pulse;
}

void paint_rings(inout vec4 result, float edge, float pixel, float t, vec4 color, vec4 shape, vec2 fade, vec4 wave) {
	if (color.a > 0.0) {
		paint(result, color.rgb, clamp(ring_alpha(edge, pixel, shape, fade, wave, t) * color.a, 0.0, 1.0));
	}
}

// distance to a four-pointed star: tips `radius` away on the axes, inner corners at (inner, inner)
float star_distance(vec2 p, float radius, float inner) {
	vec2 q = abs(p);
	if (q.y > q.x) {
		q = q.yx;
	}
	vec2 tip = vec2(radius, 0.0);
	vec2 along = normalize(vec2(inner, inner) - tip);
	vec2 outward = vec2(along.y, -along.x);
	return max(dot(q - tip, outward), q.x - radius);
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float along = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * along);
}

// distance to the strokes of a letter "z" of font size `size`, centered at 0
float z_distance(vec2 p, float size) {
	vec2 half_box = vec2(0.24, 0.25) * size;
	float top = segment_distance(p, vec2(-half_box.x, -half_box.y), vec2(half_box.x, -half_box.y));
	float slash = segment_distance(p, vec2(half_box.x, -half_box.y), vec2(-half_box.x, half_box.y));
	float bottom = segment_distance(p, vec2(-half_box.x, half_box.y), vec2(half_box.x, half_box.y));
	return min(min(top, slash), bottom);
}

void fragment() {
	float t = TIME + phase;
	vec2 half_face = (rect_size - vec2(2.0 * margin)) * 0.5;
	vec2 p = UV * rect_size - rect_size * 0.5; // pixels from the card's center
	vec2 face_point = p + half_face; // pixels from the face's top-left corner
	float pixel = max(length(vec2(dFdx(p.x), dFdy(p.x))), 0.0001); // one screen pixel, for smooth edges
	float edge = face_distance(p, half_face);
	vec4 result = vec4(0.0);

	// rings: only outside the face
	float outside = clamp(edge / pixel + 0.5, 0.0, 1.0);
	if (outside > 0.0) {
		vec4 rings = vec4(0.0);
		paint_rings(rings, edge, pixel, t, ring0_color, ring0_shape, ring0_fade, ring0_wave);
		paint_rings(rings, edge, pixel, t, ring1_color, ring1_shape, ring1_fade, ring1_wave);
		paint_rings(rings, edge, pixel, t, ring2_color, ring2_shape, ring2_fade, ring2_wave);
		paint_rings(rings, edge, pixel, t, ring3_color, ring3_shape, ring3_fade, ring3_wave);
		paint_rings(rings, edge, pixel, t, ring4_color, ring4_shape, ring4_fade, ring4_wave);
		paint_rings(rings, edge, pixel, t, ring5_color, ring5_shape, ring5_fade, ring5_wave);
		paint_rings(rings, edge, pixel, t, ring6_color, ring6_shape, ring6_fade, ring6_wave);
		paint_rings(rings, edge, pixel, t, ring7_color, ring7_shape, ring7_fade, ring7_wave);
		result = rings * outside;
	}

	// everything below is drawn over the face, so a dimmed card darkens it too
	float darken = 1.0 - 0.5 * dim;
	float on_face = clamp(-edge / pixel + 0.5, 0.0, 1.0);
	if (on_face > 0.0) {
		if (stun_stars) {
			vec2 orbit_center = vec2(art_rect.x + art_rect.z * 0.5, art_rect.y + art_rect.w * 0.22);
			for (int star = 0; star < 5; star++) {
				float angle = t * 2.4 + float(star) * TAU / 5.0;
				vec2 star_center = orbit_center + vec2(cos(angle) * art_rect.z * 0.32, sin(angle) * art_rect.w * 0.07);
				float in_front = 0.6 + 0.4 * sin(angle);
				float radius = (4.0 + 4.0 * in_front) * base_pixel;
				float cover = clamp(-star_distance(face_point - star_center, radius, radius * 0.18) / pixel + 0.5, 0.0, 1.0);
				paint(result, STAR_COLOR * darken, (0.55 + 0.45 * in_front) * cover * on_face);
			}
		}
		if (drowsy) {
			vec2 start = vec2(art_rect.x + art_rect.z - 18.0 * base_pixel, art_rect.y + art_rect.w * 0.5);
			for (int letter = 0; letter < 3; letter++) {
				float progress = fract(t / 3.0 + float(letter) / 3.0); // 0 = just appeared, 1 = gone
				float fade = sin(progress * PI);
				float size = (14.0 + 10.0 * progress) * base_pixel;
				vec2 baseline = start + vec2(sin(progress * TAU) * 3.0 * base_pixel, -progress * art_rect.w * 0.3);
				float letter_distance = z_distance(face_point - (baseline - vec2(0.0, 0.27 * size)), size);
				float stroke = 0.075 * size;
				float outline_cover = clamp((stroke + max(1.0, 0.1 * size) - letter_distance) / pixel + 0.5, 0.0, 1.0);
				float fill_cover = clamp((stroke - letter_distance) / pixel + 0.5, 0.0, 1.0);
				paint(result, vec3(0.0), 0.85 * fade * outline_cover * on_face);
				paint(result, DROWSY_COLOR * darken, 0.95 * fade * fill_cover * on_face);
			}
		}
		if (shine) {
			// a slanted band that crosses the face from the bottom-left corner, about every 3.5 s
			float band_start = mod(t * 0.45, 1.6) * (2.0 * half_face.x + 2.0 * half_face.y) - 2.0 * half_face.y;
			float across = face_point.x + face_point.y - 2.0 * half_face.y - band_start;
			float band_width = 26.0 * base_pixel;
			float in_band = clamp(across / pixel + 0.5, 0.0, 1.0) * clamp((band_width - across) / pixel + 0.5, 0.0, 1.0);
			paint(result, SHINE_COLOR * darken, 0.16 * in_band * on_face);
		}
	}

	COLOR = vec4(result.rgb / max(result.a, 0.0001), result.a);
}
