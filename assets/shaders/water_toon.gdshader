shader_type spatial;
render_mode unshaded, cull_disabled;

/**
 * Stylized toon water for the hex islands. Mobile-safe: no depth- or screen-texture reads.
 *
 * Everything keys off one number, the distance from the fragment to the nearest land hex (in
 * world units). It comes from two sources:
 *   - Near the shore it is exact: the fragment's hex cell is found analytically and the 3x3
 *     block of neighbouring cells is tested against the per-cell land mask (`cell_mask`), so
 *     the foam traces the true hexagonal coastline at any zoom level.
 *   - Further out, where the true nearest land may lie beyond the neighbour block, a coarse
 *     baked field (`shore_distance`, see island_renderer.gd) takes over for the broad
 *     shallow -> deep gradient.
 *
 * From that distance it draws: banded toon depth colours, a crisp foam rim hugging the coast,
 * broken swell lines rolling in toward the shore, and sparse drifting wave strokes offshore.
 */

// --- Island data (set per island by island_renderer.gd) ---
uniform sampler2D cell_mask : filter_nearest; // R = 1 for land cells, one texel per cell
uniform ivec2 cell_count = ivec2(1, 1);
uniform vec2 cell_size = vec2(128.0, 128.0);
uniform sampler2D shore_distance : filter_linear; // R = distance to land / far_distance
uniform vec2 grid_min;
uniform vec2 grid_size = vec2(1.0);
uniform float far_distance = 768.0;

// --- Noise ---
uniform sampler2D surface_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D distort_noise : repeat_enable, filter_linear_mipmap;

// --- Depth colours: three toon bands, alpha lets the coast shelf show through ---
// Islanders-style palette: soft teal that lightens smoothly toward the beach. Mostly opaque so
// the coast shelf is only a faint hint underneath.
uniform vec4 shallow_color : source_color = vec4(0.32, 0.74, 0.75, 0.82);
uniform vec4 mid_color : source_color = vec4(0.19, 0.55, 0.63, 0.93);
uniform vec4 deep_color : source_color = vec4(0.14, 0.43, 0.53, 1.0);
uniform float shallow_band = 90.0;  // world units from shore where shallow -> mid
uniform float deep_band = 340.0;    // world units from shore where mid -> deep
uniform float band_softness = 70.0;
uniform float band_wobble = 18.0;   // noise displacement of the band edges

// --- Shore foam ---
uniform vec4 foam_color : source_color = vec4(0.93, 1.0, 0.96, 0.75);
uniform float foam_width = 4.5;
uniform float foam_wobble = 4.0;
uniform float foam_pulse = 1.5;     // how far the rim breathes in and out
uniform float wet_band_width = 45.0; // soft glow fading out from the beach
uniform float wet_band_strength : hint_range(0.0, 1.0) = 0.28;

// --- Swell lines rolling in toward the shore ---
uniform vec4 swell_color : source_color = vec4(0.93, 1.0, 0.96, 0.3);
uniform float swell_spacing = 34.0;
uniform float swell_speed = 0.18;   // lines per second
uniform float swell_reach = 80.0;   // how far out the lines start
uniform float swell_width = 3.0;
uniform float swell_breakup : hint_range(0.0, 1.0) = 0.55;

// --- Offshore wave strokes: the odd small white dash ---
uniform vec4 stroke_color : source_color = vec4(1.0, 1.0, 1.0, 0.7);
uniform float stroke_cutoff : hint_range(0.0, 1.0) = 0.8;
uniform vec2 stroke_scale = vec2(0.0022, 0.009);
uniform vec2 stroke_scroll = vec2(0.016, 0.004);
uniform float patch_scale = 0.0024;
uniform float deep_variation : hint_range(0.0, 1.0) = 0.05;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float seg_distance(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// Unsigned distance from p (relative to a cell centre) to that pointy-top hex. Matches
// HexGrid.hex_corners_3d: corners at (0, ±h.y), (±h.x, ±h.y / 2).
float hex_distance(vec2 p) {
	vec2 q = abs(p);
	vec2 h = cell_size * 0.5;
	if (q.x <= h.x && q.y <= h.y - q.x * 0.5 * h.y / h.x) {
		return 0.0;
	}
	vec2 corner = vec2(h.x, h.y * 0.5);
	return min(seg_distance(q, vec2(0.0, h.y), corner), seg_distance(q, corner, vec2(h.x, 0.0)));
}

vec2 cell_center(ivec2 cell) {
	float row_offset = (cell.y & 1) != 0 ? 0.5 : 0.0;
	return vec2(
		(float(cell.x) + row_offset + 0.5) * cell_size.x,
		(float(cell.y) * 0.75 + 0.5) * cell_size.y
	);
}

// The odd-r offset cell containing p. Normalised so each hex is regular in axial space,
// then cube-rounded.
ivec2 containing_cell(vec2 p) {
	vec2 uv = (p - cell_size * 0.5) / cell_size;
	float q = uv.x - uv.y * (2.0 / 3.0);
	float r = uv.y * (4.0 / 3.0);
	vec3 cube = vec3(q, -q - r, r);
	vec3 rounded = round(cube);
	vec3 diff = abs(rounded - cube);
	if (diff.x > diff.y && diff.x > diff.z) {
		rounded.x = -rounded.y - rounded.z;
	} else if (diff.y > diff.z) {
		rounded.y = -rounded.x - rounded.z;
	}
	int row = int(rounded.z);
	int col = int(rounded.x) + (row - (row & 1)) / 2;
	return ivec2(col, row);
}

// Exact distance to the nearest land hex among the containing cell and its neighbours.
float near_land_distance(vec2 p) {
	ivec2 center = containing_cell(p);
	float best = 1e6;
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			ivec2 cell = center + ivec2(dx, dy);
			if (cell.x < 0 || cell.y < 0 || cell.x >= cell_count.x || cell.y >= cell_count.y) {
				continue;
			}
			if (texelFetch(cell_mask, cell, 0).r > 0.5) {
				best = min(best, hex_distance(p - cell_center(cell)));
			}
		}
	}
	return best;
}

// Coarse baked distance; past the baked rectangle it keeps growing with the overshoot.
float far_land_distance(vec2 p) {
	vec2 uv = (p - grid_min) / grid_size;
	vec2 clamped = clamp(uv, vec2(0.0), vec2(1.0));
	return texture(shore_distance, clamped).r * far_distance + length((uv - clamped) * grid_size);
}

// Anti-aliased "value < edge" step.
float below(float value, float edge) {
	float aa = max(fwidth(value), 1e-4);
	return 1.0 - smoothstep(edge - aa, edge + aa, value);
}

vec4 over(vec4 top, vec4 bottom) {
	float alpha = top.a + bottom.a * (1.0 - top.a);
	vec3 color = (top.rgb * top.a + bottom.rgb * bottom.a * (1.0 - top.a)) / max(alpha, 1e-4);
	return vec4(color, alpha);
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = min(near_land_distance(p), far_land_distance(p));

	// Two slow noise layers: one wobbles every contour, one breaks the foam lines up.
	vec2 wobble = texture(distort_noise, p * 0.0045 + vec2(TIME * 0.01, TIME * 0.007)).rg - 0.5;
	float breakup = texture(surface_noise, p * vec2(0.011, 0.013) + vec2(TIME * 0.02, -TIME * 0.015)).r;

	// Depth bands.
	float band_dist = dist + wobble.x * band_wobble;
	vec4 water = shallow_color;
	water = mix(water, mid_color, smoothstep(shallow_band - band_softness, shallow_band + band_softness, band_dist));
	water = mix(water, deep_color, smoothstep(deep_band - band_softness * 2.0, deep_band + band_softness * 2.0, band_dist));

	// Gentle large-scale light/dark patches so open water is not a flat fill.
	float patches = texture(distort_noise, p * patch_scale + vec2(TIME * 0.004, -TIME * 0.003)).r;
	float open_water = smoothstep(shallow_band, deep_band, dist);
	water.rgb *= 1.0 + (patches - 0.5) * 2.0 * deep_variation * open_water;

	// Soft lighter glow fading out from the beach.
	float foam_dist = dist + wobble.y * foam_wobble * 2.0;
	float wet = (1.0 - smoothstep(0.0, wet_band_width, foam_dist)) * wet_band_strength;
	water.rgb = mix(water.rgb, foam_color.rgb, wet * 0.6);
	water.a = mix(water.a, 1.0, wet * 0.5);

	// Swell lines: evenly spaced contours of the shore distance that travel inward, thin out
	// with distance, and are broken into dashes by noise so they read as individual waves.
	float swell_phase = foam_dist / swell_spacing + TIME * swell_speed;
	float swell_offset = abs(fract(swell_phase) - 0.5) * swell_spacing;
	float swell_fade = 1.0 - smoothstep(swell_reach * 0.45, swell_reach, foam_dist);
	float swell_thickness = swell_width * swell_fade;
	float swell = below(swell_offset, swell_thickness * 0.5) * swell_fade;
	swell *= smoothstep(swell_breakup - 0.08, swell_breakup + 0.08, breakup + (1.0 - swell_fade) * 0.2 - 0.1);
	swell *= smoothstep(foam_width, foam_width + 6.0, foam_dist);
	vec4 swell_layer = vec4(swell_color.rgb, swell_color.a * swell);

	// Foam rim: solid right at the coast, breathing slightly in time with the swell.
	float rim_width = foam_width + foam_pulse * sin(TIME * 1.4 + breakup * 6.0);
	vec4 foam_layer = vec4(foam_color.rgb, foam_color.a * below(foam_dist, rim_width));

	// Sparse elongated strokes offshore, clustered by a broad patch mask.
	vec2 stroke_uv = vec2(p.x * stroke_scale.x + TIME * stroke_scroll.x, p.y * stroke_scale.y - TIME * stroke_scroll.y) + wobble * 0.03;
	float stroke_noise = texture(surface_noise, stroke_uv).r;
	float stroke = smoothstep(stroke_cutoff, stroke_cutoff + 0.02, stroke_noise);
	stroke *= smoothstep(0.45, 0.8, patches) * smoothstep(swell_reach, swell_reach * 2.0, dist);
	vec4 stroke_layer = vec4(stroke_color.rgb, stroke_color.a * stroke);

	vec4 color = over(stroke_layer, water);
	color = over(swell_layer, color);
	color = over(foam_layer, color);

	ALBEDO = color.rgb;
	ALPHA = color.a;
}
