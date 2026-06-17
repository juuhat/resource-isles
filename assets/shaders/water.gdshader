shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Per-island shore-distance field, baked in island_renderer.gd: R = normalized distance
// from this world point to the nearest land (0 at the shore, 1 in open water). UVs are
// mapped from world XZ via grid_min / grid_size; outside the island the clamp samples the
// deep-water edge.
uniform sampler2D shore_distance : filter_linear;
uniform vec2 grid_min;
uniform vec2 grid_size;

uniform vec4 shallow_color : source_color = vec4(0.278, 0.608, 0.824, 1.0);
uniform vec4 deep_color : source_color = vec4(0.165, 0.494, 0.749, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);

uniform float deep_start = 0.6;     // shore value at which water reads as fully deep
uniform float foam_width = 0.06;    // shore-value band where foam appears
uniform float shimmer_scale = 0.015;
uniform float shimmer_speed = 0.5;

varying vec3 world_pos;


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	vec2 uv = (world_pos.xz - grid_min) / grid_size;
	float shore = texture(shore_distance, clamp(uv, vec2(0.0), vec2(1.0))).r;

	// Shallow ring near land, fading to deep water.
	float depth_t = smoothstep(0.0, deep_start, shore);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, depth_t);

	// Shimmer: two scrolling noise layers add subtle moving highlights.
	float n1 = value_noise(world_pos.xz * shimmer_scale + vec2(TIME * shimmer_speed, TIME * shimmer_speed * 0.7));
	float n2 = value_noise(world_pos.xz * shimmer_scale * 2.0 - vec2(TIME * shimmer_speed * 0.5, 0.0));
	float shimmer = smoothstep(0.55, 1.0, n1 * 0.6 + n2 * 0.4);
	col += vec3(0.07) * shimmer;

	// Animated foam band hugging the shoreline.
	float edge = foam_width * (0.7 + 0.3 * sin(TIME * 2.0 + world_pos.x * 0.05 + world_pos.z * 0.05));
	float foam = 1.0 - smoothstep(0.0, edge, shore);
	foam *= 0.55 + 0.45 * value_noise(world_pos.xz * 0.05 + vec2(TIME * 0.6));
	col = mix(col, foam_color.rgb, clamp(foam, 0.0, 1.0));

	ALBEDO = col;
	ROUGHNESS = 0.15;
	METALLIC = 0.0;
	SPECULAR = 0.5;
}
