shader_type spatial;
render_mode unshaded, blend_add, depth_draw_alpha_prepass, cull_disabled;
uniform float pulse = 0.0;
uniform vec4 ring_color : source_color = vec4(1.0, 0.68, 0.25, 0.92);
void fragment() {
	float glow = 0.72 + 0.28 * sin(pulse);
	ALBEDO = ring_color.rgb * glow;
	EMISSION = ring_color.rgb * (1.4 + glow * 0.8);
	ALPHA = ring_color.a * (0.72 + glow * 0.20);
}
