shader_type canvas_item;
// The moving part of the Escudo de Feitiço and Escudo Supremo rings: orbiting diamonds, the
// Supremo's sweeping glint, inner sparks, twinkling stars and breathing halo. The still rings are
// drawn once by CardView; this runs on the GPU every frame, so the card itself never has to redraw
// just to keep the sparks turning (that was choppy on PC and heavy on phones).
// Drawn on a square ColorRect centered on the art window, as wide as the art window.
// Coordinates: p = 0 at the center, the square goes from -0.5 to 0.5 (1 = the art window width).

uniform float base_pixel = 0.0094; // one card base pixel (the "s" in CardView), measured in art widths
uniform float spell_on = 0.0; // 1 = the card has Escudo de Feitiço
uniform float supreme_on = 0.0; // 1 = the card has Escudo Supremo
uniform float phase = 0.0; // per-card time offset, so two shielded cards don't spin in lockstep

const float FULL_TURN = 6.28318530718;

// how much of this pixel a shape covers, from its distance (negative = inside), smoothed over one screen pixel
float coverage(float distance_to_edge) {
	float smoothing = max(fwidth(distance_to_edge), 0.0001);
	return 1.0 - smoothstep(-smoothing, smoothing, distance_to_edge);
}

// `count` diamonds evenly spaced on a circle, turned by `spin`; same shape as CardView._diamond
// (upright, `half_height` tall up and down, 0.8 of that sideways). Only the nearest one is measured.
float diamond_ring(vec2 p, float ring_radius, float count, float spin, float half_height) {
	float slot = FULL_TURN / count;
	float nearest = floor((atan(p.y, p.x) - spin) / slot + 0.5);
	float center_angle = spin + nearest * slot;
	vec2 q = p - vec2(cos(center_angle), sin(center_angle)) * ring_radius;
	return coverage(abs(q.x) / 0.8 + abs(q.y) - half_height);
}

// a thin circle line
float circle_line(vec2 p, float ring_radius, float width) {
	return coverage(abs(length(p) - ring_radius) - width * 0.5);
}

// a four-pointed star with curved sides (like CardView._sparkle), plus a faint glow around it
float star(vec2 q, float star_radius) {
	if (star_radius <= 0.0) {
		return 0.0;
	}
	vec2 a = abs(q);
	float shape = coverage(sqrt(a.x) + sqrt(a.y) - sqrt(star_radius));
	float glow = exp(-dot(q, q) / (star_radius * star_radius * 0.08)) * 0.5;
	return max(shape, glow);
}

// paints `color` over what is already there, `amount` of the way (0..1)
vec4 paint(vec4 below, vec3 color, float amount) {
	float a = clamp(amount, 0.0, 1.0);
	return vec4(mix(below.rgb, color, a / max(a + below.a * (1.0 - a), 0.0001)), a + below.a * (1.0 - a));
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float s = base_pixel;
	float t = TIME + phase;
	vec4 result = vec4(0.0);

	if (spell_on > 0.5) {
		// six pale-violet diamonds turning slowly on the violet ring
		result = paint(result, vec3(0.890, 0.824, 1.0), diamond_ring(p, 0.40, 6.0, t * 0.6, 2.6 * s));
	}

	if (supreme_on > 0.5) {
		float ring_radius = 0.43;
		// breathing halo just outside the golden ring
		float breath = 0.5 + 0.5 * sin(t * 4.0);
		result = paint(result, vec3(1.0, 0.914, 0.639), circle_line(p, ring_radius + 5.0 * s, 2.0 * s) * (0.15 + 0.3 * breath));
		// a white comet sweeping around the ring: bright head, fading tail
		float behind_head = mod(t * 2.2 - atan(p.y, p.x), FULL_TURN); // 0 = at the head, grows along the tail
		float tail = 1.0 - smoothstep(0.0, 1.1, behind_head);
		result = paint(result, vec3(1.0), circle_line(p, ring_radius, 4.0 * s) * tail * 0.95);
		// eight gold diamonds on the ring, six smaller ones inside turning the other way
		result = paint(result, vec3(1.0, 0.945, 0.761), diamond_ring(p, ring_radius, 8.0, -t * 0.5, 2.6 * s));
		result = paint(result, vec3(1.0, 0.914, 0.639), diamond_ring(p, ring_radius * 0.72, 6.0, t * 0.9, 1.8 * s) * 0.8);
		// four stars on the diagonals, each blinking on its own beat
		float slot = FULL_TURN / 4.0;
		float star_index = floor((atan(p.y, p.x) - FULL_TURN / 8.0) / slot + 0.5);
		float star_angle = FULL_TURN / 8.0 + star_index * slot;
		float twinkle = max(0.0, sin(t * 3.0 + mod(star_index, 4.0) * 1.7));
		vec2 star_offset = p - vec2(cos(star_angle), sin(star_angle)) * ring_radius * 0.55;
		result = paint(result, vec3(1.0), star(star_offset, 6.0 * s * twinkle) * 0.9 * twinkle);
	}

	COLOR = result;
}
