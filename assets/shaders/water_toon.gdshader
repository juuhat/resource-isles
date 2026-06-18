shader_type spatial;
render_mode unshaded, cull_disabled;

/**
 * Roystan toon water (roystan.net/articles/toon-water.html), adapted to Godot 4 and made
 * mobile-safe. The original reads the depth buffer for the water column; the Mobile renderer
 * doesn't deliver the depth texture to transparent passes, so instead this samples a baked
 * shore-distance field (R = normalized distance to the nearest land: 0 at the shore, 1 in
 * open water — see island_renderer.gd). That drives the same toon look: a shallow→deep
 * gradient and animated, distorted foam that hugs the shoreline.
 */

const float SMOOTHSTEP_AA = 0.01;

uniform sampler2D surfaceNoise : repeat_enable, filter_linear;
uniform sampler2D distortNoise : repeat_enable, filter_linear;

// Per-island shore-distance field, mapped from world XZ via grid_min / grid_size.
uniform sampler2D shore_distance : filter_linear;
uniform vec2 grid_min;
uniform vec2 grid_size;

// A single flat surface tint. There is no shallow/deep gradient — the sense of depth comes
// entirely from the sandy seabed (lighter coast shelf, darker ocean floor) showing through
// this translucent color. Keep alpha < 1 so the floor is visible.
uniform vec4 water_color : source_color = vec4(0.48, 0.74, 0.90, 0.6);
uniform vec4 foam_color : source_color = vec4(1.0);

uniform float foam_distance : hint_range(0.0, 1.0) = 0.12; // how far from shore foam reaches
uniform float surface_noise_cutoff : hint_range(0.0, 1.0) = 0.777;
uniform float surface_distortion_amount : hint_range(0.0, 1.0) = 0.27;

// Noise is sampled in world space (the plane is far larger than a UV tile), so these are
// world-space frequencies rather than the original's per-mesh UV tiling. Keep the scale well
// below 1/tile_size (~1/128) and roughly isotropic, or the foam repeats per hex tile.
uniform vec2 surface_noise_scale = vec2(0.0028, 0.0034);
uniform float distort_noise_scale = 0.0035;
uniform vec2 surface_noise_scroll = vec2(0.012, 0.009);

varying vec3 world_pos;

vec4 alphaBlend(vec4 top, vec4 bottom) {
	vec3 color = (top.rgb * top.a) + (bottom.rgb * (1.0 - top.a));
	float alpha = top.a + bottom.a * (1.0 - top.a);
	return vec4(color, alpha);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz - grid_min) / grid_size;
	float shore = texture(shore_distance, clamp(uv, vec2(0.0), vec2(1.0))).r;

	// Distort the surface-noise lookup with a second, slower noise so the foam edge wobbles.
	vec2 distortUV = world_pos.xz * distort_noise_scale;
	vec4 distortNoiseSample = texture(distortNoise, distortUV);
	vec2 distortAmount = (distortNoiseSample.xy * 2.0 - 1.0) * surface_distortion_amount;

	vec2 baseUV = world_pos.xz * surface_noise_scale;
	vec2 noise_uv = vec2(
		baseUV.x + TIME * surface_noise_scroll.x + distortAmount.x,
		baseUV.y + TIME * surface_noise_scroll.y + distortAmount.y
	);
	float surfaceNoiseSample = texture(surfaceNoise, noise_uv).r;

	// Foam shows where the noise clears a cutoff that drops toward the shoreline, so the
	// pale foam concentrates near land and thins out into open water.
	float foamDepth = clamp(shore / foam_distance, 0.0, 1.0);
	float surfaceNoiseCutoff = foamDepth * surface_noise_cutoff;
	float surfaceNoiseAmount = smoothstep(
		surfaceNoiseCutoff - SMOOTHSTEP_AA,
		surfaceNoiseCutoff + SMOOTHSTEP_AA,
		surfaceNoiseSample
	);

	vec4 waterColor = water_color;

	vec4 surfaceNoiseColor = foam_color;
	surfaceNoiseColor.a *= surfaceNoiseAmount;
	vec4 color = alphaBlend(surfaceNoiseColor, waterColor);

	ALBEDO = color.rgb;
	ALPHA = color.a;
}
