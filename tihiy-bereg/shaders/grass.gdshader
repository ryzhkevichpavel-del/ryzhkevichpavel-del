shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley;
uniform float time = 0.0;
uniform float wind_strength = 1.0;
uniform vec3 base_color : source_color = vec3(0.105, 0.22, 0.095);
uniform vec3 tip_color : source_color = vec3(0.31, 0.39, 0.17);
varying float seed_v;
float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
void vertex() {
	seed_v = hash31(MODEL_MATRIX[3].xyz);
	float phase = seed_v * 6.2831853 + VERTEX.y * 2.1;
	float height_factor = clamp(UV.y, 0.0, 1.0);
	VERTEX.x += sin(time * 1.08 + phase) * height_factor * 0.12 * wind_strength;
	VERTEX.z += cos(time * 0.83 + phase * 1.31) * height_factor * 0.055 * wind_strength;
}
void fragment() {
	vec3 col = mix(base_color, tip_color, UV.y);
	col *= 0.82 + seed_v * 0.28;
	ALBEDO = col;
	ROUGHNESS = 0.91;
	SPECULAR = 0.12;
	ALPHA_SCISSOR_THRESHOLD = 0.18;
}
