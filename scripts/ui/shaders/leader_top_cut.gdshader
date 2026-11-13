shader_type canvas_item;

// Hides the top of the Leader plate above a jagged line (a destroyed Leader: the top half burst away).
// cut_y holds the line's height at evenly spaced x positions from cut_start_x to cut_end_x.
uniform float cut_start_x = 48.0;
uniform float cut_end_x = 196.0;
uniform float cut_y[9];

varying vec2 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	if (local_position.x >= cut_start_x && local_position.x <= cut_end_x) {
		float along = (local_position.x - cut_start_x) / (cut_end_x - cut_start_x) * 8.0;
		int index = clamp(int(floor(along)), 0, 7);
		float line_y = mix(cut_y[index], cut_y[index + 1], along - float(index));
		if (local_position.y < line_y) {
			discard;
		}
	}
}
