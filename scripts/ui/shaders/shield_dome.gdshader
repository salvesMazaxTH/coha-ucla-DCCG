shader_type canvas_item;
// Escudo, Escudo Mágico and Escudo Supremo: an energy dome raised over the top of the card, wider than
// the card and above it, so it reads as a force field the game puts on the card, not as part of the art.
// Its base is a ring seen in perspective (bright in front, faint behind), which gives it depth.
// The three shields share the dome; each keeps its own color and detail:
//   Escudo          cyan honeycomb
//   Escudo Mágico   violet rune band and diamonds orbiting the base
//   Escudo Supremo  gold, a second outer rim, a comet running along it and twinkling stars
// Runs on the GPU every frame, so the card itself never redraws to animate it.
// Distances are measured in card widths (1 = the width of the card face).

uniform vec2 rect_size = vec2(240.0, 200.0); // size of this ColorRect, in pixels
uniform vec4 face_rect = vec4(45.0, 30.0, 150.0, 210.0); // the card face inside this rect, in pixels: x, y, width, height
uniform float base_pixel = 0.0067; // one card base pixel (the "s" in CardView), in card widths
uniform float plain_on = 0.0; // 1 = the card has Escudo
uniform float spell_on = 0.0; // 1 = the card has Escudo Mágico
uniform float supreme_on = 0.0; // 1 = the card has Escudo Supremo
uniform float detail = 1.0; // 0 = phone: skips the honeycomb, the costliest part
uniform float phase = 0.0; // per-card time offset, so two shielded cards don't pulse in lockstep

const float FULL_TURN = 6.28318530718;

// how much of this pixel a shape covers, from its distance (negative = inside), smoothed over one screen pixel
float coverage(float distance_to_edge, float screen_pixel) {
	return 1.0 - smoothstep(-screen_pixel, screen_pixel, distance_to_edge);
}

// distance to the edge of an ellipse (close enough near the edge), negative inside
float ellipse_distance(vec2 p, vec2 radii) {
	float k = length(p / radii);
	return (k - 1.0) * k / max(length(p / (radii * radii)), 0.0001);
}

// distance to the nearest line of a honeycomb whose cells are `cell` wide
float honeycomb_distance(vec2 p, float cell) {
	vec2 grid = vec2(1.0, 1.7320508);
	vec2 a = mod(p / cell, grid) - grid * 0.5;
	vec2 b = mod(p / cell - grid * 0.5, grid) - grid * 0.5;
	vec2 nearest = dot(a, a) < dot(b, b) ? a : b;
	vec2 folded = abs(nearest);
	return (0.5 - max(dot(folded, vec2(0.5, 0.8660254)), folded.x)) * cell;
}

// a four-pointed star with curved sides, plus a faint glow around it
float star(vec2 q, float star_radius) {
	if (star_radius <= 0.0) {
		return 0.0;
	}
	vec2 a = abs(q);
	float shape = 1.0 - smoothstep(-0.02, 0.02, (sqrt(a.x) + sqrt(a.y) - sqrt(star_radius)) / sqrt(star_radius));
	float glow = exp(-dot(q, q) / (star_radius * star_radius * 0.08)) * 0.5;
	return max(shape, glow);
}

// paints `color` over what is already there, `amount` of the way (0..1)
vec4 paint(vec4 below, vec3 color, float amount) {
	float a = clamp(amount, 0.0, 1.0);
	return vec4(mix(below.rgb, color, a / max(a + below.a * (1.0 - a), 0.0001)), a + below.a * (1.0 - a));
}

// puts a whole layer over what is already there
vec4 layer_over(vec4 below, vec4 top) {
	float alpha = top.a + below.a * (1.0 - top.a);
	vec3 rgb = (top.rgb * top.a + below.rgb * below.a * (1.0 - top.a)) / max(alpha, 0.0001);
	return vec4(rgb, alpha);
}

// one shield dome. kind: 0 = Escudo, 1 = Escudo Mágico, 2 = Escudo Supremo.
// grow makes it a bit bigger or smaller, so stacked shields nest instead of overlapping.
vec4 shield_layer(vec2 q, float card_height, float grow, int kind, float t, float screen_pixel) {
	float s = base_pixel;
	vec3 color = kind == 0 ? vec3(0.62, 0.89, 1.0) : (kind == 1 ? vec3(0.79, 0.66, 1.0) : vec3(1.0, 0.85, 0.42));
	vec3 hot = mix(color, vec3(1.0), 0.65);

	// the dome sits a little right of the middle and slightly tilted, so it is not a perfect mirror
	vec2 center = vec2(0.53, 0.51 * card_height);
	vec2 radii = vec2(0.60 + grow, 0.54 * card_height + grow);
	float base_height = 0.11 * card_height + grow * 0.3; // how flat the base ring looks in perspective
	float tilt = -0.05;
	vec2 r = q - center;
	vec2 p = vec2(r.x * cos(tilt) - r.y * sin(tilt), r.x * sin(tilt) + r.y * cos(tilt));
	float dome = ellipse_distance(p, radii);
	float base = ellipse_distance(p, vec2(radii.x, base_height));
	float d = min(max(dome, p.y), base); // upper half of the dome plus the front of its base
	if (d > 14.0 * s) {
		return vec4(0.0);
	}

	vec2 normal = normalize(p / (radii * radii) + vec2(0.0001));
	float lit = 0.6 + 0.4 * dot(normal, vec2(-0.6, -0.8)); // brighter toward the top left, as if lit from there
	float fresnel = smoothstep(-0.24, 0.0, d); // denser toward the edge, like a bubble
	float breath = kind == 2 ? 0.8 + 0.2 * sin(t * 3.0) : 1.0;
	vec4 layer = vec4(0.0);

	if (d < 0.0) {
		// a see-through tint over the whole inside, denser toward the edge
		layer = paint(layer, color, (0.35 + 0.22 * fresnel * fresnel) * lit);
		// a light sweeping diagonally across the dome every few seconds
		float sweep_position = fract(t * 0.22) * 2.6 - 0.8;
		float sweep = exp(-pow(q.x + q.y * 0.5 - sweep_position, 2.0) * 60.0);
		layer = paint(layer, hot, sweep * (0.06 + 0.22 * fresnel));
		if (kind != 1 && detail > 0.5) {
			float lines = coverage(honeycomb_distance(q, kind == 0 ? 0.075 : 0.06) - 0.45 * s, screen_pixel);
			layer = paint(layer, hot, lines * fresnel * (0.12 + 0.55 * sweep));
		}
	} else {
		layer = paint(layer, color, exp(-d / (4.0 * s)) * 0.5 * lit * breath);
	}

	// back half of the base ring, seen through the dome: faint, so the front reads closer
	layer = paint(layer, color, coverage(abs(base) - 0.6 * s, screen_pixel) * step(p.y, 0.0) * 0.35);

	if (kind == 1) {
		// a band of runes turning just inside the rim
		float around = atan(p.y / radii.y, p.x / radii.x);
		float runes = smoothstep(0.40, 0.46, fract(around * 18.0 / FULL_TURN + t * 0.12)) * smoothstep(0.15, 0.22, fract(around * 7.0 / FULL_TURN - t * 0.05));
		layer = paint(layer, hot, coverage(abs(d + 5.0 * s) - 0.8 * s, screen_pixel) * runes * 0.8);
		// six diamonds orbiting the base: bigger and brighter when they pass in front
		for (int i = 0; i < 6; i++) {
			float angle = t * 0.55 + float(i) * FULL_TURN / 6.0;
			float front = 0.5 + 0.5 * sin(angle);
			vec2 offset = p - vec2(cos(angle) * radii.x, sin(angle) * base_height);
			float half_height = (1.6 + 1.6 * front) * s;
			float diamond = coverage(abs(offset.x) / 0.8 + abs(offset.y) - half_height, screen_pixel);
			layer = paint(layer, vec3(0.92, 0.86, 1.0), diamond * (0.35 + 0.65 * front));
		}
	}

	if (kind == 2) {
		// a second rim just outside, breathing
		layer = paint(layer, color, coverage(abs(d - 4.5 * s) - 0.6 * s, screen_pixel) * (0.3 + 0.4 * (breath - 0.6) / 0.4));
		// a white comet running along the rim: bright head, fading tail
		float around = atan(p.y / radii.y, p.x / radii.x);
		float behind_head = mod(t * 1.8 - around, FULL_TURN);
		float tail = 1.0 - smoothstep(0.0, 1.3, behind_head);
		layer = paint(layer, vec3(1.0), coverage(abs(d) - 1.6 * s, screen_pixel) * tail);
		// four stars across the top of the dome, each blinking on its own beat
		for (int i = 0; i < 4; i++) {
			float angle = -2.5 + float(i) * 0.6;
			vec2 spot = vec2(cos(angle) * radii.x, sin(angle) * radii.y) * 0.82;
			float twinkle = max(0.0, sin(t * 2.6 + float(i) * 1.9));
			layer = paint(layer, vec3(1.0), star(p - spot, 6.0 * s * twinkle) * twinkle * 0.9);
		}
	}

	// the rim itself, on top of everything; the front of the base is the edge nearest to the viewer
	float rim_light = p.y > 0.0 ? 0.95 : lit;
	layer = paint(layer, hot, coverage(abs(d) - 0.8 * s, screen_pixel) * (0.55 + 0.45 * rim_light));
	return layer;
}

void fragment() {
	vec2 pixel = UV * rect_size;
	float card_height = face_rect.w / face_rect.z;
	vec2 q = (pixel - face_rect.xy) / face_rect.z;
	float screen_pixel = 1.0 / face_rect.z;
	float t = TIME + phase;
	vec4 result = vec4(0.0);
	// outermost first, so the inner domes are painted over it
	if (supreme_on > 0.5) {
		result = layer_over(result, shield_layer(q, card_height, 0.035, 2, t, screen_pixel));
	}
	if (plain_on > 0.5) {
		result = layer_over(result, shield_layer(q, card_height, 0.0, 0, t, screen_pixel));
	}
	if (spell_on > 0.5) {
		result = layer_over(result, shield_layer(q, card_height, -0.035, 1, t, screen_pixel));
	}
	COLOR = result;
}
