shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

/**
 * Sea water spilling off the edge of the flat disc into space. A ribbon mesh whose UV.y runs
 * from the rim (0) to the bottom (1); streaks scroll downward and the ribbon thins and fades
 * into mist as it falls.
 */

uniform vec3 water_color : source_color = vec3(0.78, 0.92, 0.98);
uniform vec3 streak_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float speed = 0.35;
uniform float seed = 0.0;

float hash11(float x) {
	return fract(sin(x * 127.1 + seed * 311.7) * 43758.5453);
}

void fragment() {
	float along = UV.y;
	float across = abs(UV.x - 0.5) * 2.0;

	// Narrower as it falls.
	float width = mix(1.0, 0.35, along);
	float body = 1.0 - smoothstep(width * 0.6, width, across);

	// Vertical streaks that scroll down.
	float column = floor(UV.x * 9.0);
	float streak_phase = fract(along * 2.5 - TIME * speed * (0.7 + hash11(column) * 0.6) + hash11(column + 3.0));
	float streak = smoothstep(0.0, 0.25, streak_phase) * (1.0 - smoothstep(0.55, 1.0, streak_phase));

	float fade = (1.0 - smoothstep(0.35, 1.0, along)) * smoothstep(0.0, 0.04, along);
	ALBEDO = mix(water_color, streak_color, streak * 0.6);
	ALPHA = body * fade * (0.45 + streak * 0.35);
}
