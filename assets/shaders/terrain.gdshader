shader_type spatial;
render_mode cull_disabled;

// World-space patterns cross hex boundaries. Geometry is never displaced.
uniform sampler2D ground_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 base_color : source_color = vec4(0.5, 0.55, 0.3, 1.0);
uniform vec4 patch_dark : source_color = vec4(0.4, 0.45, 0.25, 1.0);
uniform vec4 patch_light : source_color = vec4(0.6, 0.62, 0.4, 1.0);
uniform vec4 soil_color : source_color = vec4(0.48, 0.4, 0.28, 1.0);
uniform vec4 side_color : source_color = vec4(0.42, 0.36, 0.26, 1.0);
uniform vec4 hover_color : source_color = vec4(0.7, 0.75, 0.6, 1.0);
uniform vec4 action_hover_color : source_color = vec4(0.31, 0.89, 0.435, 1.0);
uniform vec4 silhouette_color : source_color = vec4(0.537, 0.584, 0.608, 1.0);
uniform float water_level = 6.0;
uniform float patch_scale = 0.00065;
// 0 leaves a flat base colour (the submerged seabed); soil patches only where soil_strength > 0.
uniform float detail_strength = 1.0;
uniform float soil_strength = 0.0;

// Shared materials retain independent interaction/discovery state on every tile.
instance uniform int hover_state = 0; // 0 normal, 1 ordinary hover, 2 actionable hover
instance uniform bool explored = true;

varying vec3 ground_position;
varying vec3 ground_normal;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ground_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 color = base_color.rgb;
	if (explored && detail_strength > 0.0) {
		vec2 p = ground_position.xz;
		float broad = texture(ground_noise, p * patch_scale).r;
		float small = texture(ground_noise, p * 0.008 + vec2(0.37, 0.71)).r;
		vec3 patches = mix(patch_dark.rgb, patch_light.rgb, smoothstep(0.25, 0.75, broad));
		color = mix(base_color.rgb, patches, 0.8);
		float soil = smoothstep(0.64, 0.82, broad + (small - 0.5) * 0.1);
		color = mix(color, soil_color.rgb, soil * soil_strength);
		// Mipmaps and low amplitude keep fine grain quiet at gameplay zoom.
		color *= 1.0 + (small - 0.5) * 0.07;
		float top = smoothstep(0.5, 0.9, normalize(ground_normal).y);
		float strata = smoothstep(0.35, 0.65, fract((ground_position.y + broad * 3.0) / 7.0));
		vec3 side = side_color.rgb * mix(0.92, 1.05, strata);
		float wet = 1.0 - smoothstep(water_level + 0.5, water_level + 4.0, ground_position.y);
		side *= mix(1.0, 0.73, wet);
		color = mix(base_color.rgb, mix(side, color, top), detail_strength);
	}
	// Flat whole-cell feedback remains legible over the subtle surface patterns.
	if (hover_state == 1) {
		color = hover_color.rgb;
	} else if (hover_state == 2) {
		color = action_hover_color.rgb;
	}
	if (!explored) {
		color = silhouette_color.rgb;
	}
	ALBEDO = color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
}
