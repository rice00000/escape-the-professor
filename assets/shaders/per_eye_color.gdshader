// TEMPLATE FILE #############################

//############################################

shader_type spatial;

uniform vec3 left_eye_color : source_color = vec3(1, 0, 0);
uniform vec3 right_eye_color : source_color = vec3(0, 1, 0);

void fragment() {
	ALBEDO = mix(left_eye_color, right_eye_color, float(VIEW_INDEX));
    ROUGHNESS = 0.4;
	METALLIC = 1.0;
}
