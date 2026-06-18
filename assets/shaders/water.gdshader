shader_type spatial;
render_mode unshaded, cull_disabled;

// Per-island shore-distance field, baked in island_renderer.gd: R = normalized distance
// from this world point to the nearest land (0 at the shore, 1 in open water). UVs are
// mapped from world XZ via grid_min / grid_size; outside the island the clamp samples the
// deep-water edge.
uniform sampler2D shore_distance : filter_linear;
uniform vec2 grid_min;
uniform vec2 grid_size;

uniform vec4 shallow_color : source_color = vec4(0.08, 0.68, 0.64, 1.0);
uniform vec4 mid_color : source_color = vec4(0.05, 0.50, 0.52, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.30, 0.34, 1.0);
uniform vec4 glint_color : source_color = vec4(0.55, 0.90, 0.86, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.94, 0.82, 1.0);

uniform float deep_start = 0.7;     // shore value at which water reads as fully deep
uniform float foam_width = 0.035;
uniform float shimmer_scale = 0.006;
uniform float shimmer_speed = 0.12;
uniform float wave_scale = 0.018;
uniform float wave_strength = 0.055;

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

	// Shallow turquoise near land, fading to darker teal in open water.
	float depth_t = smoothstep(0.0, deep_start, shore);
	vec3 col = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.0, 0.55, depth_t));
	col = mix(col, deep_color.rgb, smoothstep(0.45, 1.0, depth_t));

	// Broad animated color movement, like soft painterly patches in mobile map water.
	float large = value_noise(world_pos.xz * shimmer_scale + vec2(TIME * shimmer_speed, TIME * shimmer_speed * 0.55));
	float counter = value_noise(world_pos.xz * shimmer_scale * 1.8 - vec2(TIME * shimmer_speed * 0.42, TIME * shimmer_speed * 0.18));
	float swirls = smoothstep(0.18, 0.98, large * 0.65 + counter * 0.35);
	col = mix(col, shallow_color.rgb, swirls * wave_strength * (0.35 + shore * 0.65));

	// Tiny moving glints break up the flat plane without normals, transparency, or depth reads.
	float n1 = value_noise(world_pos.xz * shimmer_scale + vec2(TIME * shimmer_speed, TIME * shimmer_speed * 0.7));
	float n2 = value_noise(world_pos.xz * wave_scale - vec2(TIME * shimmer_speed * 0.8, TIME * shimmer_speed * 0.2));
	float shimmer = smoothstep(0.88, 1.0, n1 * 0.55 + n2 * 0.45);
	col = mix(col, glint_color.rgb, shimmer * 0.045);

	// A clean pale band sells the mobile-map shoreline more reliably than depth foam.
	float foam = 1.0 - smoothstep(0.0, foam_width, shore);
	float broken = value_noise(world_pos.xz * 0.025 + vec2(TIME * 0.08, -TIME * 0.05));
	foam *= mix(0.65, 1.0, broken);
	col = mix(col, foam_color.rgb, clamp(foam * 0.75, 0.0, 1.0));

	ALBEDO = col;
}
