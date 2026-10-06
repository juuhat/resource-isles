shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, fog_disabled;

/**
 * The uncharted world as an unscanned sector of the robot's chart display: dark slate hex tiles
 * on the world's own lattice (each one sits over a cell boats sail across), lit along the scan
 * frontier by a cyan rim that glows onto the water, with a few loose outline tiles flickering
 * just off the edge. It carries on the sea's ring grid, shows each island nobody has visited as a
 * rough silhouette of tiles, and gives K9-DA's island a pulsing amber ring once Set Sail detects
 * its signal. A faint sweep circles the disc.
 *
 * One sheet covers everything beyond the sailing frontier. Each reachable island that has not
 * been sighted keeps its own patch; discovery opens a hole in the patch from the island's centre
 * outward. Tiles are whole: each tests the coverage at its centre, nudged by broad noise and a
 * little per-tile jitter so the frontier is ragged rather than a perfect ring. Everything is
 * placed in world units on the xz plane, so the patches and the sheet share one lattice.
 */

uniform float disc_radius = 30000.0;
// The sheet's ragged edge runs around this radius from the world centre.
uniform float frontier_radius = 3200.0;
// x, y = centre; z = patch radius; w = hole radius (opened on discovery).
uniform vec4 patches[64];
uniform int patch_count = 0;
// x, y = centre; z = coastline radius; w = seed.
uniform vec4 sketches[64];
uniform int sketch_count = 0;
// An amber ring around one sketch (K9-DA's signal); z <= 0 hides it.
uniform vec3 marker = vec3(0.0);
uniform float ring_spacing = 6400.0;
uniform float meridian_count = 12.0;
uniform sampler2D scan_noise : repeat_enable, filter_linear;

uniform vec3 tile_dark : source_color = vec3(0.07, 0.12, 0.16);
uniform vec3 tile_light : source_color = vec3(0.10, 0.17, 0.22);
uniform vec3 land_color : source_color = vec3(0.15, 0.28, 0.32);
uniform vec3 line_color : source_color = vec3(0.45, 0.84, 0.94);
uniform vec3 rim_color : source_color = vec3(0.62, 0.95, 1.0);
uniform vec3 signal_color : source_color = vec3(1.0, 0.70, 0.28);

// The world lattice (WorldNavigation.CELL_SIZE): pointy-top hexes 128 wide, rows 96 apart.
// Stretching z by HEX_STRETCH makes them regular hexes with this inradius.
const float HEX_WIDTH = 128.0;
const float HEX_ROW = 96.0;
const float HEX_STRETCH = 1.1547005;
const float HEX_INRADIUS = 64.0;
// Axial steps to the six neighbours.
const vec2 HEX_STEPS[6] = vec2[6](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0),
		vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(0.0, -1.0));
// Per-tile jitter and broad noise on a tile's coverage test (at most their sum either way).
const float JITTER = 40.0;
const float BROAD = 60.0;
// Tiles this far short of switching on may still show as loose outlines. World_view's
// CHART_EDGE_REACH must clear JITTER + BROAD + LOOSE.
const float LOOSE = 110.0;
// How far the rim's glow reaches onto the water.
const float GLOW = 56.0;
const float SWEEP_SECONDS = 24.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 a) {
	return fract(sin(dot(a, vec2(127.1, 311.7))) * 43758.5453);
}

// The lattice cell holding `p`: its centre (xy) and axial coordinates (zw), by cube rounding as
// in WorldNavigation.cell_from_position.
vec4 hex_cell(vec2 p) {
	float r = p.y / HEX_ROW;
	float q = p.x / HEX_WIDTH - r * 0.5;
	vec3 cube = vec3(q, -q - r, r);
	vec3 rounded = round(cube);
	vec3 error = abs(rounded - cube);
	if (error.x > error.y && error.x > error.z) {
		rounded.x = -rounded.y - rounded.z;
	} else if (error.y > error.z) {
		rounded.y = -rounded.x - rounded.z;
	} else {
		rounded.z = -rounded.x - rounded.y;
	}
	return vec4((rounded.x + rounded.z * 0.5) * HEX_WIDTH, rounded.z * HEX_ROW, rounded.x, rounded.z);
}

// Coverage as a signed distance: positive under the chart. The sheet is everything beyond the
// frontier; each patch is a disc minus its opening hole. Their union is the max.
float coverage(vec2 p) {
	float covered = length(p) - frontier_radius - 40.0;
	for (int i = 0; i < patch_count; i++) {
		vec4 piece = patches[i];
		float d = length(p - piece.xy);
		covered = max(covered, min(piece.z - d, d - piece.w));
	}
	return covered;
}

// A tile is on when this is positive: the coverage at its centre, made ragged.
float tile_coverage(vec2 center, vec2 axial) {
	float broad = (textureLod(scan_noise, center * 0.0004, 0.0).r - 0.5) * 2.0 * BROAD;
	return coverage(center) + broad + (hash(axial) - 0.5) * 2.0 * JITTER;
}

// How far `p` is from the nearest sketched coastline (negative on its land).
float land_at(vec2 p) {
	float nearest = 1e9;
	for (int i = 0; i < sketch_count; i++) {
		vec4 sketch = sketches[i];
		vec2 v = p - sketch.xy;
		float d = length(v);
		if (d > sketch.z * 1.9) {
			continue;
		}
		// A rough coastline: the radius wanders with noise read around a circle, so it closes.
		vec2 dir = v / max(d, 0.001);
		vec2 seed_uv = vec2(fract(sketch.w * 0.137), fract(sketch.w * 0.291));
		float wander = textureLod(scan_noise, seed_uv + dir * 0.07, 0.0).r - 0.5;
		wander += (textureLod(scan_noise, seed_uv.yx + dir * 0.2, 0.0).r - 0.5) * 0.3;
		nearest = min(nearest, d - sketch.z * (0.92 + wander * 0.9));
	}
	return nearest;
}

// Antialiased line of half-width `w` (world units) over distance `d`, which changes by `aa` per
// pixel. Lines thinner than a pixel stay a pixel wide but fade, so the chart still reads from
// the overview.
float ink_line_aa(float d, float w, float aa) {
	aa = max(aa, 0.0001);
	float width = max(w, aa * 0.75);
	return (1.0 - smoothstep(width, width + aa, abs(d))) * clamp(w / width, 0.3, 1.0);
}

float ink_line(float d, float w) {
	return ink_line_aa(d, w, fwidth(d));
}

// Per-pixel change of a distance measured along `normal` in a tile, from the stretched world
// position's screen derivatives. Distances inside a tile jump where the pixel quad straddles two
// tiles, so fwidth of them would smear lines along the seams.
float tile_aa(vec2 normal, vec2 dx, vec2 dy) {
	return abs(dot(dx, normal)) + abs(dot(dy, normal));
}

// Lays `top` with opacity `a` over a colour that has opacity `alpha`.
vec4 over(vec3 color, float alpha, vec3 top, float a) {
	float out_alpha = a + alpha * (1.0 - a);
	return vec4((top * a + color * alpha * (1.0 - a)) / max(out_alpha, 0.0001), out_alpha);
}

void fragment() {
	vec2 p = world_position.xz;
	float r = length(p);

	// Everything that needs screen derivatives comes first, while every pixel of the quad is
	// still running (before any discard or per-tile branch).
	vec2 dx = dFdx(p) * vec2(1.0, HEX_STRETCH);
	vec2 dy = dFdy(p) * vec2(1.0, HEX_STRETCH);
	// Fine marks (tile outlines, crosshairs) fade out once they shrink below a few pixels, so the
	// overview stays clean instead of shimmering.
	float detail = 1.0 - smoothstep(4.0, 10.0, length(fwidth(p)));

	// The navigator's grid, continuing the one on the charted sea: rings and meridians.
	float ring_distance = abs(fract(r / ring_spacing + 0.5) - 0.5) * ring_spacing;
	float segment = TAU / meridian_count;
	float meridian_distance = abs(fract(atan(p.y, p.x) / segment + 0.5) - 0.5) * segment * r;
	float grid = max(ink_line(ring_distance, 6.0), ink_line(meridian_distance, 4.0) * smoothstep(800.0, 2500.0, r));

	// K9-DA's signal: a slowly turning dashed ring with a ping spreading out from the island.
	float signal = 0.0;
	if (marker.z > 0.0) {
		vec2 v = p - marker.xy;
		float d = length(v);
		float dash = step(0.5, fract(atan(v.y, v.x) / TAU * 36.0 + TIME * 0.04));
		signal = max(ink_line(d - marker.z, 8.0) * dash * 0.9, ink_line(d - marker.z - 45.0, 3.0) * 0.5);
		float ping = fract(TIME / 2.6);
		signal = max(signal, ink_line(d - marker.z * mix(0.5, 1.15, ping), 5.0) * (1.0 - ping) * 0.7);
	}

	if (r > disc_radius || coverage(p) < -(JITTER + BROAD + LOOSE + 2.4 * HEX_INRADIUS)) {
		discard;
	}

	vec4 cell = hex_cell(p);
	vec2 center = cell.xy;
	vec2 axial = cell.zw;
	// Position in the tile, stretched so it is a regular hex, and how far in from its edge.
	vec2 local = (p - center) * vec2(1.0, HEX_STRETCH);
	vec2 folded = abs(local);
	float edge = HEX_INRADIUS - max(folded.x, dot(folded, vec2(0.5, 0.8660254)));
	vec2 edge_normal = folded.x > dot(folded, vec2(0.5, 0.8660254)) ? vec2(1.0, 0.0) : vec2(0.5, 0.8660254);
	float edge_aa = tile_aa(edge_normal * sign(local), dx, dy);
	float covered = tile_coverage(center, axial);
	bool on = covered > 0.0;

	// Edges facing a tile in the other state: a rim inside the tiles that are on, a glow on the
	// water beside them. Tiles far from the frontier have neighbours in the same state.
	float rim = 0.0;
	float glow = 0.0;
	if (edge < GLOW && abs(covered) < 2.4 * HEX_INRADIUS + 2.0 * (JITTER + BROAD)) {
		for (int i = 0; i < 6; i++) {
			vec2 step_axial = HEX_STEPS[i];
			vec2 normal = vec2(step_axial.x + step_axial.y * 0.5, step_axial.y * 0.8660254);
			float to_edge = HEX_INRADIUS - dot(local, normal);
			if (to_edge > GLOW) {
				continue;
			}
			vec2 neighbour = center + vec2((step_axial.x + step_axial.y * 0.5) * HEX_WIDTH, step_axial.y * HEX_ROW);
			bool neighbour_on = tile_coverage(neighbour, axial + step_axial) > 0.0;
			if (on && !neighbour_on) {
				rim = max(rim, max(ink_line_aa(to_edge, 3.0, tile_aa(normal, dx, dy)), exp(-to_edge / 16.0) * 0.4));
			} else if (!on && neighbour_on) {
				float falloff = 1.0 - to_edge / GLOW;
				glow = max(glow, falloff * falloff);
			}
		}
	}

	if (!on) {
		vec4 result = vec4(rim_color, glow * 0.45);
		// Loose tiles just off the edge: a faint fragment and a flickering outline.
		float loose_seed = hash(axial + 31.0);
		if (covered > -LOOSE && loose_seed < 0.45) {
			float strength = (1.0 + covered / LOOSE) * (0.65 + 0.35 * sin(TIME * 1.7 + loose_seed * 40.0));
			float inset = edge - 9.0;
			result = over(result.rgb, result.a, tile_light, step(0.0, inset) * 0.3 * strength);
			result = over(result.rgb, result.a, line_color, ink_line_aa(inset, 2.0, edge_aa) * 0.75 * strength);
		}
		if (result.a < 0.003) {
			discard;
		}
		ALBEDO = result.rgb;
		ALPHA = result.a;
	} else {
		float tone = hash(axial + 17.0);
		vec3 color = mix(tile_dark, tile_light, tone * 0.6);
		float line = 0.0;

		// Islands nobody has visited, as a silhouette of lighter tiles, the shore ones outlined.
		float land = land_at(center);
		if (land < 0.0) {
			color = land_color * (0.92 + tone * 0.16);
			float shore = smoothstep(-200.0, -90.0, land);
			line = max(line, ink_line_aa(edge - 10.0, 2.5, edge_aa) * shore * 0.55);
		} else if (hash(axial + 5.0) < 0.05 && land > 160.0) {
			// The odd crosshair on open sea.
			float arm = HEX_INRADIUS * 0.22;
			float cross = max(ink_line_aa(local.x, 1.5, abs(dx.x) + abs(dy.x)) * step(abs(local.y), arm),
					ink_line_aa(local.y, 1.5, abs(dx.y) + abs(dy.y)) * step(abs(local.x), arm));
			line = max(line, cross * 0.45 * detail);
		}

		// Every tile's outline, faint.
		line = max(line, ink_line_aa(edge, 1.5, edge_aa) * 0.22 * detail);

		color = mix(color, line_color, grid * 0.3 * smoothstep(0.0, 200.0, land));
		color = mix(color, line_color, line);
		color = mix(color, signal_color, signal);

		// A faint sweep circling the disc, brightest at its leading edge.
		float behind = fract(TIME / SWEEP_SECONDS - atan(p.y, p.x) / TAU);
		color += line_color * pow(1.0 - behind, 16.0) * smoothstep(0.0, 0.01, behind) * 0.025;

		color = mix(color, rim_color, rim);
		ALBEDO = color;
		ALPHA = 1.0;
	}
}
