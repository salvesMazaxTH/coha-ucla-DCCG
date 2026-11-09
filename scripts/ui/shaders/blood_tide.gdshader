shader_type canvas_item;
// The blood area cast (Coagulhão, and any card of the element sangue): a thick tide of blood seeps over the
// arena from the caster's side, reaching ahead in slow tongues. It moves like a heart pumps it: it surges at
// each beat, the vessels in it light up, and the bead on its edge shines wet. Then it clots: it darkens to
// maroon, cracks and flakes away in patches.
// Drawn on ONE ColorRect over the arena, with normal blending (not additive), so it reads as liquid, not as
// light. FxCasts._blood_area tweens `progress` (the tide advancing), `pulse` (each heartbeat) and `clot`
// (the blood drying and going away).
// Cost: 7 noise lookups per pixel and no loops (lighter than the water wave), so it stays cheap on phones.
// Coordinates: UV.y = 0 at the top of the arena, 1 at the bottom.

uniform float progress = 0.0; // 0 = the blood has not entered yet, 1 = it covered the whole arena
uniform float pulse = 0.0; // 0 = between beats, 1 = the peak of a heartbeat
uniform float clot = 0.0; // 0 = fresh wet blood, 1 = all of it dried and gone
uniform float from_bottom = 1.0; // 1 = the blood comes from the bottom (the caster is the player below)
uniform float aspect = 1.5; // arena width / height, so the shapes are round, not stretched

const vec3 BLOOD_DEEP = vec3(0.20, 0.0, 0.025);
const vec3 BLOOD = vec3(0.56, 0.02, 0.06);
const vec3 BLOOD_BRIGHT = vec3(0.90, 0.12, 0.14);
const vec3 CLOTTED = vec3(0.15, 0.025, 0.02);
const vec3 SHINE = vec3(1.0, 0.80, 0.76);
// a small turn of the noise coordinates, so the shapes never line up with the grid the noise is made on
const mat2 TURN = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

// a random number from 0 to 1 for each grid cell
float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

// smooth noise: random values on a grid, blended between the corners
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
	float time = TIME;
	vec2 surface = vec2(UV.x * aspect, UV.y);
	vec2 turned = TURN * surface;
	// how far this pixel is along the tide's path (0 = the caster's edge, 1 = the far edge)
	float along = mix(UV.y, 1.0 - UV.y, from_bottom);
	// the blood drifts slowly away from the caster (it is thick, so much slower than the water)
	vec2 flow = vec2(0.0, mix(-1.0, 1.0, from_bottom) * time * 0.06);

	// the front: a few long tongues of blood reach ahead of the rest, and each heartbeat pushes it a little
	float tongue = noise(vec2(UV.x * aspect * 4.5, 3.7));
	tongue = tongue * tongue * tongue * 0.38;
	float front = progress * 1.4 - 0.25 + tongue + pulse * 0.025 + 0.01 * sin(UV.x * 23.0 + time * 1.2);
	float to_front = front - along; // > 0 = behind the front (under the blood)
	float covered = smoothstep(0.0, 0.008, to_front);

	// the surface: a lumpy height (thick liquid), and its slope from two nearby samples, for the wet shine
	vec2 p = turned * 5.0 + flow * 5.0;
	float lumps = noise(p);
	float height = lumps * 0.65 + noise(p * 2.3 + 7.1) * 0.35;
	vec2 slope = vec2(noise(p + vec2(0.09, 0.0)) - lumps, noise(p + vec2(0.0, 0.09)) - lumps) / 0.09;
	vec3 normal = normalize(vec3(-slope * 0.3, 1.0));
	vec3 half_way = normalize(vec3(-0.35, -0.55, 1.6)); // between the light (top left) and the eye
	float shine = pow(max(dot(normal, half_way), 0.0), 64.0);

	// the body: darker further behind the front and in the hollows
	float depth = clamp(to_front * 1.8, 0.0, 1.0);
	vec3 blood = mix(BLOOD, BLOOD_DEEP, depth * 0.65 + (1.0 - height) * 0.35);
	// the bead on the edge: the blood piles up on its front, brighter and shinier
	float bead = 1.0 - smoothstep(0.0, 0.045, to_front);
	blood = mix(blood, BLOOD_BRIGHT, bead * 0.55);

	// the vessels: thin lines in the blood, dark between beats, lit up red at each beat
	float vessel_noise = noise(TURN * turned * 7.0 + flow * 7.0 + 3.3);
	float vessel = smoothstep(0.94, 0.99, 1.0 - abs(vessel_noise * 2.0 - 1.0));
	blood = mix(blood, mix(BLOOD_DEEP * 0.5, BLOOD_BRIGHT * 1.15, pulse), vessel * 0.65);
	// the whole tide throbs brighter at each beat (the far part, already settled, less)
	blood = mix(blood, BLOOD_BRIGHT, pulse * 0.3 * (1.0 - depth * 0.6));

	// clotting: the shine goes dull, the color turns maroon, and cracks open between the patches
	float drying = smoothstep(0.0, 0.55, clot);
	blood += SHINE * shine * (0.5 + bead * 0.5) * (1.0 - drying);
	blood = mix(blood, CLOTTED + vec3(0.06, 0.0, 0.0) * height, drying * 0.85);
	float flake_patch = noise(turned * 6.0 + 11.0) * 0.7 + height * 0.3;
	float crack = (1.0 - smoothstep(0.0, 0.012, abs(flake_patch - 0.5))) * smoothstep(0.15, 0.45, clot);
	blood *= 1.0 - crack * 0.75;
	// then the dried patches flake away one by one (each pixel has its own moment to go)
	float flaking = clamp((clot - 0.2) / 0.8, 0.0, 1.0) * 1.15;
	float still_there = 1.0 - smoothstep(flake_patch - 0.015, flake_patch + 0.015, flaking);

	// a little translucent, so the table and the units stay faintly readable under the tide (between the old
	// 0.84-0.94 and the too see-through 0.58-0.74, leaning to the old one)
	float alpha = covered * mix(0.75, 0.87, depth) * still_there;
	COLOR = vec4(blood, alpha);
}
