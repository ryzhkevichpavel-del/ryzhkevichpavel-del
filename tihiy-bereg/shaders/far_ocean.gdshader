shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D water_noise : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float time = 0.0;
uniform float sea_level = 0.0;
uniform float wave_strength = 1.0;
uniform float quality = 1.0;
uniform vec3 shallow_color : source_color = vec3(0.055, 0.36, 0.45);
uniform vec3 deep_color : source_color = vec3(0.006, 0.075, 0.14);
uniform vec3 sky_reflection : source_color = vec3(0.47, 0.72, 0.83);
uniform vec3 sun_dir = vec3(-0.42, -0.77, -0.35);
uniform vec3 sun_color : source_color = vec3(1.0, 0.84, 0.60);

varying vec3 world_pos_v;
varying float crest_v;

float wv(vec2 p, vec2 d, float f, float s, float a) {
	return sin(dot(p, d) * f + time * s) * a;
}

void vertex() {
	vec2 p = VERTEX.xz;
	float w = wv(p, normalize(vec2(0.31, 0.95)), 0.095, 0.52, 0.18 + wave_strength * 0.035);
	w += wv(p, normalize(vec2(-0.86, 0.51)), 0.19, 0.78, 0.085);
	w += wv(p, normalize(vec2(0.91, 0.41)), 0.42, 1.21, 0.033);
	w += wv(p, normalize(vec2(-0.28, 0.96)), 0.91, 1.92, 0.014);
	VERTEX.y = sea_level + w;
	crest_v = clamp(w * 2.8 - 0.24, 0.0, 1.0);
	world_pos_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos_v.xz;
	mat2 rot = mat2(vec2(0.81, 0.59), vec2(-0.59, 0.81));
	vec3 n1 = texture(water_noise, p * 0.026 + vec2(time * 0.006, -time * 0.004)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(water_noise, rot * p * 0.071 + vec2(-time * 0.009, time * 0.006)).rgb * 2.0 - 1.0;
	vec3 n = normalize(vec3((n1.xy + (rot * n2.xy) * 0.72) * mix(0.38, 0.68, quality), 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.48, 0.82, quality);
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = 0.025 + 0.975 * pow(1.0 - ndv, 5.0);
	float distance_haze = smoothstep(80.0, 480.0, length(world_pos_v.xz));
	vec3 base = mix(shallow_color, deep_color, 0.72);
	base = mix(base, sky_reflection, fresnel * 0.72 + distance_haze * 0.28);
	float whitecap_pattern = texture(foam_tex, p * 0.038 + vec2(time * 0.004, 0.0)).r;
	float whitecap = crest_v * smoothstep(0.58, 0.82, whitecap_pattern) * wave_strength * 0.45;
	base = mix(base, vec3(0.91, 0.96, 0.94), whitecap);
	vec3 half_vec = normalize(normalize(VIEW) + normalize(-sun_dir));
	float sun_glint = pow(max(dot(normalize(NORMAL), half_vec), 0.0), mix(180.0, 420.0, quality));
	base += sun_color * sun_glint * 1.6;
	ALBEDO = base;
	ROUGHNESS = mix(0.07, 0.32, whitecap);
	SPECULAR = 0.94;
	ALPHA = 0.975;
	EMISSION = sun_color * sun_glint * 0.12;
}
