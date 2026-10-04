shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

uniform float frontier_radius = 3200.0;
uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float radius = length(world_position.xz);
	vec2 uv = world_position.xz * 0.0007 + vec2(TIME * 0.003, TIME * -0.002);
	float noise = texture(cloud_noise, uv).r;
	float detail = texture(cloud_noise, uv * 3.1 + vec2(TIME * -0.001)).r;
	float edge = smoothstep(frontier_radius - 128.0, frontier_radius + 80.0, radius);
	ALBEDO = mix(vec3(0.47, 0.65, 0.69), vec3(0.88, 0.94, 0.93), noise * 0.75 + detail * 0.25);
	ALPHA = edge * 0.97;
}
