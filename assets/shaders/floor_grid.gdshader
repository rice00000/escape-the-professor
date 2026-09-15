// TEMPLATE FILE #############################
// Antialiasing is practically required in VR. This shader will fill in the floor
// with a texture where lines are ALWAYS one pixel, no matter where they are.
// This type of thing fights the jittery mess a traditional texture becomes at distance.
//############################################

shader_type spatial;

uniform vec3 floor_color : source_color = vec3(0.10, 0.11, 0.13);
uniform vec3 line_color : source_color = vec3(0.30, 0.48, 0.68);
uniform float grid_size = 0.5;

void fragment() {
	// Here we first get the current point in world space. This is a relatively complex operation,
	// so bear with me. The inverse view matrix is a 4x4 affine transform, so we pad the vertex with an extra 1 (w = 1, basically scale 1).
	// at the end, we also drop the additional w component with .xyz to obtain a vec3.
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// We now obtain the transformed xz coordinate scaled to the grid. (ex, smaller grid size will expand these)
	vec2 grid = world.xz / grid_size;

	// fwidth(cell) will tell us how many pixels in the given spot for the grid.
	// Far away, fwidth gets a lot larger, and so on.
	vec2 edge = abs(fract(grid - 0.5) - 0.5) / fwidth(grid);

	// Ramp based on whether axis is closer and if this point is actually on a gridline
	float line = 1.0 - min(min(edge.x, edge.y), 1.0);

	// Lastly we apply everything we computed. The mix basically just says to draw a pixel
	// if we are on a line, and draw the floor if not.
	ALBEDO = mix(floor_color, line_color, line);
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
