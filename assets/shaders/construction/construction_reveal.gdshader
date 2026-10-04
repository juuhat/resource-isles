shader_type spatial;
// The real building as the robot raises it: the model is "printed" up from the ground, everything
// above build_height cut away. A glowing seam rides the cut, and back faces seen through the open
// top are filled with the seam colour so the cut reads as a solid, freshly laid layer rather than
// a hollow shell. The surface colours are copied from the model's own materials (see
// ConstructionSite.reveal_material); build_height is set per building, in world units.
render_mode cull_disabled;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform bool use_vertex_color = false;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.78;
uniform vec4 seam_color : source_color = vec4(0.42, 1.0, 0.9, 1.0);
// Height of the glowing band just under the cut, in world units.
uniform float seam_width = 2.5;

instance uniform float build_height = -100000.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	if (world_y > build_height) {
		discard;
	}
	if (!FRONT_FACING) {
		// Looking down into the cut: a dim teal cap.
		ALBEDO = seam_color.rgb * 0.18;
		EMISSION = seam_color.rgb * 0.3;
		ROUGHNESS = 1.0;
	} else {
		vec3 color = albedo.rgb * texture(albedo_texture, UV).rgb;
		if (use_vertex_color) {
			color *= COLOR.rgb;
		}
		ALBEDO = color;
		METALLIC = metallic;
		ROUGHNESS = roughness;
		float seam = 1.0 - smoothstep(0.0, seam_width, build_height - world_y);
		EMISSION = seam_color.rgb * seam * 0.9;
	}
}
