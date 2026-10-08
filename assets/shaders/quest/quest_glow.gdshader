shader_type spatial;
// A quest object's glow (QuestHighlight), drawn over the model as its material_overlay so the model
// keeps its own materials underneath. Additive gold: a faint fill, brighter where the faces turn
// away from the camera (a rim that follows the low-poly facets), breathing on a slow pulse. Every
// few seconds a band of light sweeps across the model, so the object glints like something worth
// picking up. The band runs along sweep_axis, a world direction tilted up from the ground so it
// crosses tall and flat objects alike, from sweep_from to sweep_to (distances along the axis, set by
// QuestHighlight to the model's extent).
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.34, 1.0);
// The whole effect's strength; QuestHighlight fades it out when the highlight is dropped.
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float fill : hint_range(0.0, 1.0) = 0.3;
uniform float rim : hint_range(0.0, 2.0) = 1.1;
uniform float rim_power = 1.5;
uniform float pulse_speed = 2.2;
uniform vec3 sweep_axis = vec3(0.0, 1.0, 0.0);
uniform float sweep_from = 0.0;
uniform float sweep_to = 1.0;
uniform float sweep_period = 3.2;
uniform float sweep_glow : hint_range(0.0, 2.0) = 0.85;
// Offsets this object's pulse and sweep from its neighbours', in seconds.
uniform float phase = 0.0;

varying float along;

void vertex() {
	along = dot((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, sweep_axis);
}

void fragment() {
	float time = TIME + phase;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim_light = pow(1.0 - facing, rim_power);
	float pulse = 0.6 + 0.4 * sin(time * pulse_speed);
	// The band's centre runs from just before the start (0) to past the end (1) over the first half
	// of each period, so it enters and leaves cleanly, and is out of sight for the rest.
	float at = (along - sweep_from) / max(sweep_to - sweep_from, 0.001);
	float sweep_at = fract(time / sweep_period) * 3.0 - 0.25;
	float band = 1.0 - smoothstep(0.0, 0.2, abs(at - sweep_at));
	ALBEDO = color.rgb * strength * ((fill + rim * rim_light) * pulse + band * sweep_glow);
}
