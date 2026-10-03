shader_type spatial;
render_mode unshaded;

/**
 * The open sea of the flat-disc planet (docs/intro-story.md), under and between every island.
 * Each island draws its own toon water (assets/shaders/water_toon.gdshader) that fades out a
 * few cells offshore; this takes over from there, so its charted colour and its patches and
 * strokes match that shader's deep water (same colours, same world-space noise) and the seam
 * disappears. Toward the ice rim it darkens, and the uncharted sea beyond the revealed rings
 * is dimmer still.
 *
 * Zoomed out, the charted area shows a navigator's grid — ring circles plus radial meridians,
 * like an azimuthal chart — and a brighter frontier line. `chart_visibility` (0 in play, 1 in
 * the full-disc overview, driven by the camera zoom) fades it in.
 *
 * Geometry is in disc units (the planet node is scaled up into the world); `world_scale`
 * converts them back to world units for the noise, which must line up with the island water.
 */

uniform float disc_radius = 50.0;
uniform float charted_radius = 12.0;
uniform float ring_spacing = 11.0;
uniform float world_scale = 1.0;
uniform float chart_visibility : hint_range(0.0, 1.0) = 0.0;

// deep_color matches water_toon.gdshader's deep_color.
uniform vec3 deep_color : source_color = vec3(0.14, 0.43, 0.53);
uniform vec3 edge_color : source_color = vec3(0.09, 0.29, 0.41);
uniform vec3 uncharted_color : source_color = vec3(0.06, 0.18, 0.27);
uniform vec3 grid_color : source_color = vec3(0.86, 0.95, 0.96);
uniform vec3 frontier_color : source_color = vec3(0.98, 0.9, 0.62);
uniform float grid_strength = 0.3;
uniform float meridian_count = 12.0;

// Offshore detail, mirroring water_toon.gdshader's open-water terms.
uniform sampler2D surface_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D distort_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 stroke_color : source_color = vec4(1.0, 1.0, 1.0, 0.7);
uniform float stroke_cutoff : hint_range(0.0, 1.0) = 0.8;
uniform vec2 stroke_scale = vec2(0.0022, 0.009);
uniform vec2 stroke_scroll = vec2(0.016, 0.004);
uniform float patch_scale = 0.0024;
uniform float deep_variation : hint_range(0.0, 1.0) = 0.05;

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

	// Calm, island-matching sea across the rings; it only darkens near the ice.
	vec3 color = mix(deep_color, edge_color, smoothstep(0.86, 1.0, t));

	vec2 world = p * world_scale;
	vec2 wobble = texture(distort_noise, world * 0.0045 + vec2(TIME * 0.01, TIME * 0.007)).rg - 0.5;
	float patches = texture(distort_noise, world * patch_scale + vec2(TIME * 0.004, -TIME * 0.003)).r;
	color *= 1.0 + (patches - 0.5) * 2.0 * deep_variation;

	vec2 stroke_uv = vec2(world.x * stroke_scale.x + TIME * stroke_scroll.x, world.y * stroke_scale.y - TIME * stroke_scroll.y) + wobble * 0.03;
	float stroke = smoothstep(stroke_cutoff, stroke_cutoff + 0.02, texture(surface_noise, stroke_uv).r);
	stroke *= smoothstep(0.45, 0.8, patches);
	color = mix(color, stroke_color.rgb, stroke_color.a * stroke);

	// Uncharted water beyond the frontier is dimmer, fading in over a soft band.
	float charted = 1.0 - smoothstep(charted_radius + 0.5, charted_radius + 4.0, r);
	color = mix(mix(color, uncharted_color, 0.7), color, charted);

	// Navigator's grid, only inside the charted area and only when zoomed out.
	float ring_distance = abs(fract(r / ring_spacing + 0.5) - 0.5) * ring_spacing;
	float rings = line_mask(ring_distance, 0.06) * step(0.5 * ring_spacing, r);
	float segment = TAU / meridian_count;
	float angle = atan(p.y, p.x);
	float meridian_distance = abs(fract(angle / segment + 0.5) - 0.5) * segment * r;
	float meridians = line_mask(meridian_distance, 0.04) * smoothstep(1.5, 4.0, r) * 0.7;
	float grid = max(rings, meridians) * charted * chart_visibility;
	color = mix(color, grid_color, grid * grid_strength);

	// Frontier: the edge of the charted world.
	float frontier = line_mask(abs(r - charted_radius), 0.12) * step(1.0, charted_radius) * chart_visibility;
	color = mix(color, frontier_color, frontier * 0.7);

	ALBEDO = color;
}
