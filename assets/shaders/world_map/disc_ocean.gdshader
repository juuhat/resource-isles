shader_type spatial;
render_mode specular_schlick_ggx;

/**
 * The top face of the flat-disc planet on the world map: one calm ocean, lighter at the centre
 * ("calm centre, wild edge", docs/island-unlocks.md) and darkening toward the ice rim. The
 * charted area (the rings the player has revealed) carries a faint navigator's grid — ring
 * circles plus radial meridians, like an azimuthal chart — and a brighter frontier line; the
 * uncharted rest of the disc is dimmed.
 */

uniform float disc_radius = 50.0;
uniform float charted_radius = 12.0;
uniform float ring_spacing = 11.0;

uniform vec3 center_color : source_color = vec3(0.36, 0.76, 0.76);
uniform vec3 mid_color : source_color = vec3(0.19, 0.55, 0.63);
uniform vec3 edge_color : source_color = vec3(0.1, 0.32, 0.45);
uniform vec3 uncharted_color : source_color = vec3(0.07, 0.2, 0.3);
uniform vec3 grid_color : source_color = vec3(0.86, 0.95, 0.96);
uniform vec3 frontier_color : source_color = vec3(0.98, 0.9, 0.62);
uniform float grid_strength = 0.22;
uniform float meridian_count = 12.0;

uniform sampler2D surface_noise : repeat_enable, filter_linear_mipmap;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

// Antialiased thin line: 1 on the line, 0 away from it, `width` in the same units as `d`.
float line_mask(float d, float width) {
	float aa = max(fwidth(d), 0.0001);
	return 1.0 - smoothstep(width, width + aa * 1.5, d);
}

void fragment() {
	vec2 p = local_position.xz;
	float r = length(p);
	// The mesh is a square plane; the ice rim hides the disc edge.
	if (r > disc_radius) {
		discard;
	}
	float t = clamp(r / disc_radius, 0.0, 1.0);

	vec3 color = mix(center_color, mid_color, smoothstep(0.0, 0.45, t));
	color = mix(color, edge_color, smoothstep(0.45, 1.0, t));

	// Uncharted water beyond the frontier is dimmer, fading in over a soft band.
	float charted = 1.0 - smoothstep(charted_radius + 0.5, charted_radius + 4.0, r);
	color = mix(mix(color, uncharted_color, 0.7), color, charted);

	// Navigator's grid, only inside the charted area.
	float ring_distance = abs(fract(r / ring_spacing + 0.5) - 0.5) * ring_spacing;
	float rings = line_mask(ring_distance, 0.06) * step(0.5 * ring_spacing, r);
	float segment = TAU / meridian_count;
	float angle = atan(p.y, p.x);
	float meridian_distance = abs(fract(angle / segment + 0.5) - 0.5) * segment * r;
	float meridians = line_mask(meridian_distance, 0.04) * smoothstep(1.5, 4.0, r) * 0.7;
	float grid = max(rings, meridians) * charted;
	color = mix(color, grid_color, grid * grid_strength);

	// Frontier: the edge of the charted world.
	float frontier = line_mask(abs(r - charted_radius), 0.12) * step(1.0, charted_radius);
	color = mix(color, frontier_color, frontier * 0.7);

	// Sparse, slow glints — kept quiet per the art direction.
	float n1 = texture(surface_noise, p * 0.018 + vec2(TIME * 0.004, TIME * 0.002)).r;
	float n2 = texture(surface_noise, p * 0.027 - vec2(TIME * 0.003, -TIME * 0.005)).r;
	float glint = smoothstep(0.74, 0.8, (n1 + n2) * 0.5);
	color += vec3(0.08, 0.12, 0.12) * glint * (1.0 - t * 0.6);

	ALBEDO = color;
	ROUGHNESS = 0.75;
	SPECULAR = 0.12;
}
