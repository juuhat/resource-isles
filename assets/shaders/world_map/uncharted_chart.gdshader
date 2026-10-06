shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, fog_disabled;

/**
 * The uncharted world as a navigator's paper chart lying over the sea (Civilization-style):
 * parchment with a singed, torn edge and a soft shadow on the water, inked with the chart's
 * ring grid, wave marks, and rough coastline sketches of the islands nobody has visited yet.
 *
 * One sheet covers everything beyond the sailing frontier. Each reachable island that has not
 * been sighted keeps its own torn patch of chart; discovery opens a hole in the patch from the
 * island's centre outward. Everything is placed in world units on the xz plane, so the patches
 * and the frontier sheet draw the same chart and line up seamlessly where they meet.
 */

uniform float disc_radius = 30000.0;
// The sheet's torn edge runs around this radius from the world centre.
uniform float frontier_radius = 3200.0;
// x, y = centre; z = patch radius; w = hole radius (opened on discovery).
uniform vec4 patches[64];
uniform int patch_count = 0;
// x, y = centre; z = coastline radius; w = seed.
uniform vec4 sketches[64];
uniform int sketch_count = 0;
// A ring of red ink around one sketch (K9-DA's signal); z <= 0 hides it.
uniform vec3 marker = vec3(0.0);
uniform float ring_spacing = 6400.0;
uniform float meridian_count = 12.0;
uniform sampler2D paper_noise : repeat_enable, filter_linear_mipmap;

uniform vec3 paper_light : source_color = vec3(0.95, 0.91, 0.80);
uniform vec3 paper_dark : source_color = vec3(0.87, 0.80, 0.64);
uniform vec3 singed_color : source_color = vec3(0.66, 0.50, 0.30);
uniform vec3 burnt_color : source_color = vec3(0.23, 0.15, 0.09);
uniform vec3 land_color : source_color = vec3(0.80, 0.72, 0.52);
uniform vec3 ink_color : source_color = vec3(0.33, 0.24, 0.16);
uniform vec3 red_ink_color : source_color = vec3(0.70, 0.27, 0.18);
uniform vec4 shadow_color : source_color = vec4(0.02, 0.10, 0.14, 0.35);

// How far the torn edge wanders either way, and how far its shadow reaches onto the water.
const float TORN = 110.0;
const float SHADOW = 110.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float noise_at(vec2 p, float scale) {
	return texture(paper_noise, p * scale).r;
}

// Antialiased ink line of half-width `w` (world units) over distance `d`. Lines thinner than a
// pixel stay a pixel wide but fade, so the chart still reads from the overview.
float ink_line(float d, float w) {
	float aa = max(fwidth(d), 0.0001);
	float width = max(w, aa * 0.75);
	return (1.0 - smoothstep(width, width + aa, abs(d))) * clamp(w / width, 0.3, 1.0);
}

float fill(float sd) {
	float aa = max(fwidth(sd), 0.0001);
	return 1.0 - smoothstep(-aa, aa, sd);
}

void fragment() {
	vec2 p = world_position.xz;
	float r = length(p);
	if (r > disc_radius) {
		discard;
	}

	// Coverage as a signed distance: positive on paper. The sheet is everything beyond the
	// frontier; each patch is a disc minus its opening hole. Their union is the max.
	float coverage = r - frontier_radius - 40.0;
	for (int i = 0; i < patch_count; i++) {
		vec4 piece = patches[i];
		float d = length(p - piece.xy);
		coverage = max(coverage, min(piece.z - d, d - piece.w));
	}
	if (coverage < -(TORN + SHADOW)) {
		discard;
	}
	// A torn edge: broad bites with a little raggedness on top, never so sharp that flecks of
	// paper break off.
	float torn = (noise_at(p, 0.0004) - 0.5) * 2.6 * TORN * 0.85 + (noise_at(p, 0.003) - 0.5) * 2.0 * TORN * 0.07;
	float e = coverage + torn;
	float aa = max(fwidth(e), 0.0001);
	float on_paper = smoothstep(-aa, aa, e);

	// Fine marks (fibre, hatching, wave marks) fade out once they shrink below a few pixels, so
	// the overview stays clean instead of shimmering.
	float detail = 1.0 - smoothstep(4.0, 10.0, length(fwidth(p)));

	// Paper: very broad, faint mottling and a little fibre, browned just inside the tear.
	float mottle = noise_at(p + vec2(913.0, 377.0), 0.00004);
	float fibre = noise_at(p, 0.011) - 0.5;
	vec3 color = mix(paper_light, paper_dark, smoothstep(0.35, 0.7, mottle) * 0.4);
	color *= 1.0 + fibre * 0.04 * detail;
	float singe = 1.0 - smoothstep(0.0, 70.0 + mottle * 50.0, e);
	color = mix(color, singed_color, singe * singe * 0.6);

	// Ink stays clear of the singed edge.
	float ink_room = smoothstep(50.0, 180.0, e);
	float ink = 0.0;
	float red_ink = 0.0;
	// How far we are from any coastline sketch (<= 0 on its land), to keep marks off the islands.
	float nearest_coast = 1e9;

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
		float wander = texture(paper_noise, seed_uv + dir * 0.07).r - 0.5;
		wander += (texture(paper_noise, seed_uv.yx + dir * 0.2).r - 0.5) * 0.3;
		float coast = d - sketch.z * (0.92 + wander * 0.9);
		nearest_coast = min(nearest_coast, coast);
		color = mix(color, land_color, fill(coast) * 0.85);
		// Hatching just inside the shore, then the coastline and its ripples out to sea.
		float hatch = abs(fract(dot(p, vec2(0.70710678)) / 46.0) - 0.5) * 46.0;
		float shore = (1.0 - smoothstep(0.0, 170.0, -coast)) * fill(coast);
		ink = max(ink, ink_line(hatch, 4.0) * shore * 0.4 * detail);
		ink = max(ink, ink_line(coast, 10.0) * 0.85);
		ink = max(ink, ink_line(coast - 70.0, 4.0) * 0.5);
		ink = max(ink, ink_line(coast - 150.0, 3.5) * 0.32);
		ink = max(ink, ink_line(coast - 250.0, 3.0) * 0.18);
		if (marker.z > 0.0 && distance(sketch.xy, marker.xy) < 1.0) {
			// Dashed red ring: K9-DA's signal comes from here.
			float ring = d - marker.z;
			float dash = step(0.5, fract(atan(v.y, v.x) / TAU * 36.0));
			red_ink = max(red_ink, ink_line(ring, 9.0) * dash * 0.85);
			red_ink = max(red_ink, ink_line(ring - 45.0, 3.5) * 0.5);
		}
	}
	float open_sea = smoothstep(120.0, 380.0, nearest_coast);

	// The navigator's grid, continuing the one on the charted sea: rings and meridians.
	float ring_distance = abs(fract(r / ring_spacing + 0.5) - 0.5) * ring_spacing;
	float segment = TAU / meridian_count;
	float meridian_distance = abs(fract(atan(p.y, p.x) / segment + 0.5) - 0.5) * segment * r;
	float grid = max(ink_line(ring_distance, 7.0), ink_line(meridian_distance, 5.0) * smoothstep(800.0, 2500.0, r));
	ink = max(ink, grid * 0.3 * open_sea);

	// Wave marks scattered on the open sea: a short double wiggle per chart cell, some cells empty.
	vec2 cell = floor(p / 560.0);
	vec3 h = fract(sin(vec3(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)), dot(cell, vec2(419.2, 371.9)))) * 43758.5453);
	if (h.x < 0.55) {
		vec2 local = p - (cell + 0.5) * 560.0 - (h.yz - 0.5) * 300.0;
		float wave_a = local.y - sin(local.x * 0.09) * 11.0;
		float wave_b = local.y - 26.0 - sin((local.x - 18.0) * 0.09) * 9.0;
		float waves = ink_line(wave_a, 4.0) * (1.0 - smoothstep(55.0, 70.0, abs(local.x)));
		waves = max(waves, ink_line(wave_b, 3.5) * (1.0 - smoothstep(30.0, 45.0, abs(local.x - 18.0))));
		ink = max(ink, waves * 0.45 * open_sea * detail);
	}

	color = mix(color, ink_color, ink * ink_room);
	color = mix(color, red_ink_color, red_ink * ink_room);
	// The burnt rim, darkest right at the tear.
	color = mix(color, burnt_color, 1.0 - smoothstep(0.0, 6.0 + aa, e));

	// Off the paper: a soft shadow on the water below the edge.
	float shadow = smoothstep(-SHADOW, 0.0, e) * (1.0 - on_paper);
	ALBEDO = mix(shadow_color.rgb, color, on_paper);
	ALPHA = max(on_paper, shadow * shadow * shadow_color.a);
}
