shader_type spatial;
// The blueprint: a see-through teal hologram of the finished building, drawn over everything the
// robot hasn't built yet (above build_height). Brighter at grazing angles, with scan lines drifting
// up through it, so it reads as a projection rather than a pale copy of the model.
render_mode unshaded, cull_back, depth_draw_never;

uniform vec4 color : source_color = vec4(0.36, 0.95, 0.86, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.3;
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.55;
// Scan line spacing and drift speed, in world units.
uniform float line_spacing = 9.0;
uniform float line_speed = 6.0;

instance uniform float build_height = -100000.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (world_position.y < build_height) {
		discard;
	}
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float line = smoothstep(0.82, 1.0, fract((world_position.y - TIME * line_speed) / line_spacing));
	// A slow shimmer so a waiting blueprint still looks alive.
	float pulse = 0.85 + 0.15 * sin(TIME * 2.2);
	ALBEDO = color.rgb;
	ALPHA = clamp((base_alpha + rim * rim_alpha + line * 0.18) * pulse, 0.0, 1.0);
}
