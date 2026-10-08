shader_type spatial;
// The pool of light on the ground under a quest object (QuestHighlight): a flat disc, additive gold,
// with a soft glow in the middle, a thin ring around the object, and a ripple spreading out from it
// every few seconds. Drawn on a quad whose UVs span the disc.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.78, 0.34, 1.0);
// The whole effect's strength; QuestHighlight fades it out when the highlight is dropped.
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float pool : hint_range(0.0, 1.0) = 0.3;
// The ring's radius and width, as fractions of the disc's.
uniform float ring_radius : hint_range(0.0, 1.0) = 0.7;
uniform float ring_width : hint_range(0.0, 0.5) = 0.045;
uniform float ring_glow : hint_range(0.0, 2.0) = 0.55;
uniform float ripple_period = 2.6;
uniform float ripple_glow : hint_range(0.0, 2.0) = 0.45;
uniform float pulse_speed = 2.2;
// Offsets this object's pulse and ripple from its neighbours', in seconds.
uniform float phase = 0.0;

void fragment() {
	float time = TIME + phase;
	float r = length(UV * 2.0 - 1.0);
	if (r > 1.0) {
		discard;
	}
	float pulse = 0.75 + 0.25 * sin(time * pulse_speed);
	float glow = pool * pow(1.0 - r, 2.0);
	float ring = ring_glow * (1.0 - smoothstep(0.0, ring_width, abs(r - ring_radius)));
	// The ripple leaves the ring and fades as it reaches the disc's edge.
	float t = fract(time / ripple_period);
	float ripple_at = mix(ring_radius, 1.0, t);
	float ripple = ripple_glow * (1.0 - t) * (1.0 - smoothstep(0.0, ring_width * 1.4, abs(r - ripple_at)));
	ALBEDO = color.rgb * strength * ((glow + ring) * pulse + ripple);
}
