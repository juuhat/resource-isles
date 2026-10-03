shader_type sky;

/**
 * Deep-space backdrop for the world map: the flat-disc planet floats in open space
 * (docs/intro-story.md). Two layers of hashed point stars plus a faint, slow nebula haze.
 * Everything is procedural, so it needs no textures and stays cheap on the mobile renderer.
 */

uniform vec3 space_color : source_color = vec3(0.012, 0.02, 0.045);
uniform vec3 nebula_color : source_color = vec3(0.13, 0.2, 0.34);
uniform vec3 nebula_warm : source_color = vec3(0.26, 0.16, 0.3);
uniform float star_density = 0.985; // hash threshold: higher = fewer stars

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z
	);
}

float fbm(vec3 p) {
	float total = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return total;
}

// One layer of stars: each cell of a 3D lattice around the unit sphere may hold one star.
float star_layer(vec3 dir, float scale, float threshold, float twinkle_speed) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	float h = hash13(cell);
	if (h < threshold) {
		return 0.0;
	}
	vec3 jitter = vec3(hash13(cell + 11.7), hash13(cell + 37.1), hash13(cell + 71.3)) - 0.5;
	float dist = length(fract(p) - 0.5 - jitter * 0.6);
	float core = smoothstep(0.16, 0.0, dist);
	float brightness = (h - threshold) / (1.0 - threshold);
	float twinkle = 0.75 + 0.25 * sin(TIME * twinkle_speed + h * 91.0);
	return core * (0.35 + brightness) * twinkle;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	float haze = fbm(dir * 2.2 + vec3(0.0, TIME * 0.004, 0.0));
	float band = smoothstep(0.45, 0.85, haze);
	vec3 color = space_color;
	color += nebula_color * band * 0.55;
	color += nebula_warm * smoothstep(0.62, 0.95, fbm(dir * 3.7 + 5.0)) * 0.35;

	float stars = star_layer(dir, 180.0, star_density, 1.7);
	stars += star_layer(dir, 90.0, star_density + 0.008, 0.9) * 1.4;
	color += vec3(0.95, 0.97, 1.0) * stars;

	COLOR = color;
}
