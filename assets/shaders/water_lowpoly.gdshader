shader_type spatial;
// Low-poly stylized water for the hex tiles: a few summed sine waves displace the tile
// tops, and flat (per-triangle) shading via screen-space derivatives gives the faceted
// "low poly" look as the light catches each facet. Color comes from the tile's coast/ocean
// classification (base_color). Surface_y tells the shader which vertices are the surface
// (vs the submerged side walls). Shoreline foam is handled separately, not in open water.
render_mode world_vertex_coords;

uniform vec4 base_color : source_color = vec4(0.16, 0.60, 0.80, 1.0);
uniform float surface_y = 6.0;
uniform float wave_height = 1.2;
uniform float wave_speed = 1.0;
uniform float wave_freq = 0.012;

varying vec3 world_pos;


float waves(vec2 p) {
	float t = TIME * wave_speed;
	float h = sin(p.x * wave_freq + t);
	h += sin(p.y * wave_freq * 1.3 - t * 0.8);
	h += 0.5 * sin((p.x + p.y) * wave_freq * 0.7 + t * 1.3);
	return h / 2.5; // roughly -1..1
}


void vertex() {
	// Only the surface ring moves; the submerged side-wall bottoms stay put.
	if (VERTEX.y > surface_y * 0.5) {
		VERTEX.y += waves(VERTEX.xz) * wave_height;
	}
	world_pos = VERTEX;
}


void fragment() {
	// Flat shading: derive a per-triangle normal from the displaced world position so each
	// facet catches the light separately (the low-poly look). Force it to point up since the
	// surface is roughly horizontal — robust regardless of derivative ordering.
	vec3 n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
	if (n.y < 0.0) {
		n = -n;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	ALBEDO = base_color.rgb;
	ROUGHNESS = 0.3;
}
