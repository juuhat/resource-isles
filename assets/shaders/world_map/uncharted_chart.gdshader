shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, fog_disabled;

/**
 * The uncharted world on the robot's chart display, in two layers of hex tiles on the world's own
 * lattice (each one sits over a cell boats sail across):
 *
 * - Exploration fog: slate tiles over every cell inside the radar frontier the robot has not seen
 *   yet (explored_map), and over each reachable island until discovery opens its patch. A cyan rim
 *   runs along its edge and glows onto the water, with a few loose outline tiles flickering just
 *   off it, and, once the ship's radar is repaired, its sweep circles across it.
 * - Beyond the radar: near-black tiles over every cell outside the frontier, where no boat can
 *   sail (exactly WorldNavigation.inside_frontier). A dim red limit line runs along its edge.
 *
 * Both carry the sea's ring grid. Islands nobody has found are not drawn: the player discovers
 * them by sailing. The one exception is K9-DA's signal, a tutorial-style ping (ripples spreading
 * from a pulsing beacon inside a turning dashed ring) drawn over every layer. Tiles are whole: each decides its layer at its centre. A patch tests its coverage there too, nudged by
 * broad noise and a little per-tile jitter so its edge is ragged rather than round. Everything is
 * placed in world units on the xz plane.
 */

uniform float disc_radius = 30000.0;
// Cells whose edge reaches past this radius from the world centre are beyond the radar.
uniform float frontier_radius = 3200.0;
// One byte per cell over axial coordinates -explored_radius..explored_radius (ExplorationMap);
// explored_radius < 0 means nothing is explored.
uniform sampler2D explored_map : filter_nearest;
uniform int explored_radius = -1;
// x, y = centre; z = patch radius; w = hole radius (opened on discovery).
uniform vec4 patches[64];
uniform int patch_count = 0;
// K9-DA's signal: x, y = centre; z = radius (at least PING_MIN_PIXELS on screen); z <= 0 hides it.
uniform vec3 ping = vec3(0.0);
// How strongly the radar's sweep shows, 0..1: off until the ship's radar is repaired, then fading in
// (WorldView, WorldData.is_radar_online).
uniform float radar_sweep = 0.0;
// Where the sweep's leading edge points, in radians from +x toward +z (WorldView.radar_sweep_angle,
// which the repaired dish on the wreck turns with).
uniform float sweep_angle = 0.0;
uniform float ring_spacing = 6400.0;
uniform float meridian_count = 12.0;
uniform sampler2D scan_noise : repeat_enable, filter_linear;

uniform vec3 tile_dark : source_color = vec3(0.07, 0.12, 0.16);
uniform vec3 tile_light : source_color = vec3(0.10, 0.17, 0.22);
uniform vec3 line_color : source_color = vec3(0.45, 0.84, 0.94);
uniform vec3 rim_color : source_color = vec3(0.62, 0.95, 1.0);
uniform vec3 signal_color : source_color = vec3(1.0, 0.70, 0.28);
uniform vec3 void_dark : source_color = vec3(0.016, 0.024, 0.036);
uniform vec3 void_light : source_color = vec3(0.028, 0.040, 0.056);
uniform vec3 limit_color : source_color = vec3(0.92, 0.38, 0.34);

// The world lattice (WorldNavigation.CELL_SIZE): pointy-top hexes 128 wide, rows 96 apart.
// Stretching z by HEX_STRETCH makes them regular hexes with this inradius.
const float HEX_WIDTH = 128.0;
const float HEX_ROW = 96.0;
const float HEX_STRETCH = 1.1547005;
const float HEX_INRADIUS = 64.0;
// Axial steps to the six neighbours.
const vec2 HEX_STEPS[6] = vec2[6](vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0),
		vec2(-1.0, 1.0), vec2(1.0, -1.0), vec2(0.0, -1.0));
// Per-tile jitter and broad noise on a patch tile's coverage test (at most their sum either way).
// World_view's CHART_EDGE_REACH must clear JITTER + BROAD.
const float JITTER = 40.0;
const float BROAD = 60.0;
// How far the rims' glow reaches onto the water.
const float GLOW = 56.0;
// K9-DA's ping: never smaller than this many pixels across its radius, so it reads from the
// overview, and a ripple leaves the beacon this often.
const float PING_MIN_PIXELS = 34.0;
const float PING_SECONDS = 2.4;

// The layer a tile is in.
const int LAYER_OPEN = 0;
const int LAYER_FOG = 1;
const int LAYER_BEYOND = 2;

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

bool explored(vec2 axial) {
	ivec2 texel = ivec2(axial) + ivec2(explored_radius);
	int size = explored_radius * 2 + 1;
	if (explored_radius < 0 || texel.x < 0 || texel.y < 0 || texel.x >= size || texel.y >= size) {
		return false;
	}
	return texelFetch(explored_map, texel, 0).r > 0.5;
}

// Patch coverage as a signed distance: positive under a patch. Each patch is a disc minus its
// opening hole; their union is the max.
float patch_coverage(vec2 p) {
	float covered = -1e9;
	for (int i = 0; i < patch_count; i++) {
		vec4 piece = patches[i];
		float d = length(p - piece.xy);
		covered = max(covered, min(piece.z - d, d - piece.w));
	}
	return covered;
}

int tile_state(vec2 center, vec2 axial) {
	if (length(center) + HEX_INRADIUS > frontier_radius) {
		return LAYER_BEYOND;
	}
	if (!explored(axial)) {
		return LAYER_FOG;
	}
	if (patch_count > 0) {
		float broad = (textureLod(scan_noise, center * 0.0004, 0.0).r - 0.5) * 2.0 * BROAD;
		if (patch_coverage(center) + broad + (hash(axial) - 0.5) * 2.0 * JITTER > 0.0) {
			return LAYER_FOG;
		}
	}
	return LAYER_OPEN;
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

// K9-DA's ping at `p`, 0..1: a pulsing beacon, ripples spreading out from it and a slowly turning
// dashed ring at its edge. `pixel` is the world size of a pixel.
float signal_ping(vec2 p, float pixel) {
	if (ping.z <= 0.0) {
		return 0.0;
	}
	float radius = max(ping.z, pixel * PING_MIN_PIXELS);
	vec2 v = p - ping.xy;
	float d = length(v);
	if (d > radius * 1.25) {
		return 0.0;
	}
	float line = max(radius * 0.012, pixel * 1.2);
	float pulse = 0.5 + 0.5 * sin(TIME * TAU / PING_SECONDS);

	// The beacon: a bright core with a soft halo breathing around it.
	float core = 1.0 - smoothstep(radius * 0.08, radius * 0.08 + pixel * 1.5, d);
	float halo = exp(-d / (radius * (0.12 + 0.06 * pulse))) * 0.55;
	float amount = max(core, halo);

	// Three ripples, each fading as it spreads.
	for (int i = 0; i < 3; i++) {
		float phase = fract(TIME / PING_SECONDS + float(i) / 3.0);
		float fade = pow(1.0 - phase, 1.5) * smoothstep(0.0, 0.08, phase);
		amount = max(amount, ink_line_aa(d - phase * radius * 1.1, line * (1.0 + phase), pixel) * fade);
	}

	// The turning dashed ring.
	float dash = step(0.45, fract(atan(v.y, v.x) / TAU * 24.0 + TIME * 0.05));
	amount = max(amount, ink_line_aa(d - radius, line, pixel) * dash * 0.85);
	return amount;
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

	float signal = signal_ping(p, length(fwidth(p)));

	if (r > disc_radius) {
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
	int state = tile_state(center, axial);

	// Edges facing a tile in another layer: a rim inside the fog and the limit line inside the
	// beyond, each glowing onto the open water beside them.
	float rim = 0.0;
	float limit = 0.0;
	float glow = 0.0;
	float limit_glow = 0.0;
	bool beside_fog = false;
	for (int i = 0; i < 6; i++) {
		vec2 step_axial = HEX_STEPS[i];
		vec2 neighbour = center + vec2((step_axial.x + step_axial.y * 0.5) * HEX_WIDTH, step_axial.y * HEX_ROW);
		int neighbour_state = tile_state(neighbour, axial + step_axial);
		if (neighbour_state == state) {
			continue;
		}
		beside_fog = beside_fog || neighbour_state == LAYER_FOG;
		vec2 normal = vec2(step_axial.x + step_axial.y * 0.5, step_axial.y * 0.8660254);
		float to_edge = HEX_INRADIUS - dot(local, normal);
		if (to_edge > GLOW) {
			continue;
		}
		float falloff = 1.0 - to_edge / GLOW;
		if (state == LAYER_FOG && neighbour_state == LAYER_OPEN) {
			rim = max(rim, max(ink_line_aa(to_edge, 3.0, tile_aa(normal, dx, dy)), exp(-to_edge / 16.0) * 0.4));
		} else if (state == LAYER_BEYOND) {
			limit = max(limit, max(ink_line_aa(to_edge, 2.5, tile_aa(normal, dx, dy)) * 0.8, exp(-to_edge / 14.0) * 0.25));
		} else if (state == LAYER_OPEN && neighbour_state == LAYER_FOG) {
			glow = max(glow, falloff * falloff);
		} else if (state == LAYER_OPEN) {
			limit_glow = max(limit_glow, falloff * falloff);
		}
	}

	if (state == LAYER_OPEN) {
		vec4 result = over(limit_color, limit_glow * 0.3, rim_color, glow * 0.45);
		// Loose tiles just off the fog: a faint fragment and a flickering outline.
		float loose_seed = hash(axial + 31.0);
		if (beside_fog && loose_seed < 0.45) {
			float strength = 0.6 * (0.65 + 0.35 * sin(TIME * 1.7 + loose_seed * 40.0));
			float inset = edge - 9.0;
			result = over(result.rgb, result.a, tile_light, step(0.0, inset) * 0.3 * strength);
			result = over(result.rgb, result.a, line_color, ink_line_aa(inset, 2.0, edge_aa) * 0.75 * strength);
		}
		result = over(result.rgb, result.a, signal_color, signal);
		if (result.a < 0.003) {
			discard;
		}
		ALBEDO = result.rgb;
		ALPHA = result.a;
	} else {
		bool fog = state == LAYER_FOG;
		float tone = hash(axial + 17.0);
		vec3 color = fog ? mix(tile_dark, tile_light, tone * 0.6) : mix(void_dark, void_light, tone * 0.6);
		float line = 0.0;

		if (fog && hash(axial + 5.0) < 0.05) {
			// The odd crosshair.
			float arm = HEX_INRADIUS * 0.22;
			float cross = max(ink_line_aa(local.x, 1.5, abs(dx.x) + abs(dy.x)) * step(abs(local.y), arm),
					ink_line_aa(local.y, 1.5, abs(dx.y) + abs(dy.y)) * step(abs(local.x), arm));
			line = max(line, cross * 0.45 * detail);
		}

		// Every tile's outline, faint (fainter still beyond the radar).
		line = max(line, ink_line_aa(edge, 1.5, edge_aa) * (fog ? 0.22 : 0.07) * detail);

		color = mix(color, line_color, grid * (fog ? 0.3 : 0.1));
		color = mix(color, line_color, line);
		color = mix(color, signal_color, signal);

		if (fog && radar_sweep > 0.0) {
			// The radar's sweep circling the disc, brightest at its leading edge.
			float behind = fract((sweep_angle - atan(p.y, p.x)) / TAU);
			color += line_color * pow(1.0 - behind, 16.0) * smoothstep(0.0, 0.01, behind) * 0.025 * radar_sweep;
		}

		color = mix(color, rim_color, rim);
		color = mix(color, limit_color, limit);
		ALBEDO = color;
		ALPHA = 1.0;
	}
}
