// TEMPLATE FILE #############################

//############################################

shader_type spatial;

uniform vec3 left_eye_color : source_color = vec3(0.25, 0.53, 0.96);
uniform vec3 right_eye_color : source_color = vec3(0.71, 0.25, 0.96);

void fragment() {
	ALBEDO = mix(left_eye_color, right_eye_color, float(VIEW_INDEX));
}
