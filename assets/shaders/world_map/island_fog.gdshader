shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 fog_color : source_color = vec4(0.39, 0.47, 0.53, 0.92);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float drift = TIME * 0.045 + seed;
	float wisps = sin(p.x * 8.0 + drift) * sin(p.y * 7.0 - drift * 0.7);
	float edge = 1.0 - smoothstep(0.48, 1.0, length(p) + wisps * 0.06);
	ALBEDO = fog_color.rgb + wisps * 0.025;
	ALPHA = fog_color.a * edge * opacity;
}
