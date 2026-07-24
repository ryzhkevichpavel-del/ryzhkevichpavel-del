shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D state_tex : filter_linear, repeat_disable;
uniform sampler2D flow_tex : filter_linear, repeat_disable;
uniform sampler2D water_noise : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 texel_size = vec2(0.00625, 0.00833);
uniform vec2 world_size = vec2(96.0, 68.0);
uniform float time = 0.0;
uniform float wave_strength = 1.0;
uniform float quality = 1.0;
uniform vec3 shallow_color : source_color = vec3(0.08, 0.60, 0.64);
uniform vec3 mid_color : source_color = vec3(0.025, 0.31, 0.40);
uniform vec3 deep_color : source_color = vec3(0.008, 0.105, 0.19);
uniform vec3 sky_reflection : source_color = vec3(0.47, 0.72, 0.83);
uniform vec3 sun_dir = vec3(-0.42, -0.77, -0.35);
uniform vec3 sun_color : source_color = vec3(1.0, 0.84, 0.60);

varying vec2 sim_uv;
varying vec3 world_pos_v;
varying float water_depth_v;
varying float foam_v;
varying float sediment_v;
varying vec2 flow_v;
varying float crest_v;

float wave_component(vec2 p, vec2 direction, float frequency, float speed, float amplitude) {
	return sin(dot(p, direction) * frequency + time * speed) * amplitude;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	sim_uv = UV;
	vec4 st = textureLod(state_tex, sim_uv, 0.0);
	vec4 fl = textureLod(flow_tex, sim_uv, 0.0);
	water_depth_v = st.b;
	foam_v = st.a;
	sediment_v = fl.b;
	flow_v = fl.rg;
	vec2 p = VERTEX.xz;
	float shallow = smoothstep(1.05, 0.025, st.b);
	float w = wave_component(p, normalize(vec2(0.27, 0.96)), 0.57, 1.02, 0.042 + 0.033 * wave_strength);
	w += wave_component(p, normalize(vec2(-0.82, 0.57)), 1.18, 1.71, 0.021 + 0.014 * wave_strength);
	w += wave_component(p, normalize(vec2(0.95, 0.18)), 2.32, 2.52, 0.010);
	w += wave_component(p, normalize(vec2(-0.35, 0.94)), 4.35, 4.10, 0.0045);
	w *= mix(0.46, 1.56, shallow);
	crest_v = clamp(w * 8.0 + length(flow_v) * 0.12, 0.0, 1.0);
	VERTEX.y = st.r + st.b + w;
	world_pos_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (water_depth_v < 0.0025) {
		discard;
	}
	vec2 p = world_pos_v.xz;
	vec2 flow_advect = flow_v * 0.017;
	mat2 rot = mat2(vec2(0.78, 0.63), vec2(-0.63, 0.78));
	vec3 n1 = texture(water_noise, p * 0.085 + vec2(time * 0.018, -time * 0.012) + flow_advect).rgb * 2.0 - 1.0;
	vec3 n2 = texture(water_noise, rot * p * 0.205 + vec2(-time * 0.014, time * 0.022) - flow_advect * 0.7).rgb * 2.0 - 1.0;
	vec3 n3 = texture(water_noise, p * 0.48 + vec2(time * 0.031, time * 0.017)).rgb * 2.0 - 1.0;
	vec2 normal_xy = n1.xy * 0.48 + (rot * n2.xy) * 0.36 + n3.xy * 0.16;
	vec3 tangent_normal = normalize(vec3(normal_xy * mix(0.42, 0.78, quality), 1.0));
	NORMAL_MAP = tangent_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.46, 0.90, quality);

	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = 0.025 + 0.975 * pow(1.0 - ndv, 5.0);
	float depth_mix = smoothstep(0.025, 2.2, water_depth_v);
	float deep_mix = smoothstep(0.65, 3.6, water_depth_v);
	vec3 water_base = mix(shallow_color, mid_color, depth_mix);
	water_base = mix(water_base, deep_color, deep_mix);
	float turbidity = clamp(sediment_v * 7.0, 0.0, 0.78);
	water_base = mix(water_base, vec3(0.25, 0.255, 0.19), turbidity);

	vec2 refract_offset = tangent_normal.xy * (0.0022 + min(water_depth_v, 1.5) * 0.0018) * (1.0 - fresnel);
	vec3 refracted = textureLod(screen_tex, SCREEN_UV + refract_offset, mix(0.0, 1.35, depth_mix)).rgb;
	vec3 absorption = exp(-vec3(0.72, 0.25, 0.12) * water_depth_v * 0.62);
	vec3 transmitted = refracted * absorption + water_base * (1.0 - absorption);
	vec3 reflected = mix(sky_reflection, vec3(0.86, 0.90, 0.91), fresnel * 0.28);
	vec3 color = mix(transmitted, reflected, fresnel * 0.72);

	float shore = smoothstep(0.23, 0.010, water_depth_v);
	float speed = length(flow_v);
	float foam_pattern_a = texture(foam_tex, p * 0.115 + flow_v * 0.012 + vec2(time * 0.010, -time * 0.004)).r;
	float foam_pattern_b = texture(foam_tex, rot * p * 0.31 + vec2(-time * 0.013, time * 0.006)).r;
	float foam_pattern = smoothstep(0.40, 0.72, foam_pattern_a * 0.68 + foam_pattern_b * 0.32);
	float foam_source = clamp(foam_v * 1.18 + shore * (0.18 + speed * 0.34) + crest_v * 0.16, 0.0, 1.0);
	float foam_mask = foam_source * foam_pattern;
	vec3 foam_color = vec3(0.91, 0.96, 0.94) * (0.92 + foam_pattern_b * 0.12);
	color = mix(color, foam_color, foam_mask);

	float caustic = sin(p.x * 4.7 + n1.x * 4.0 + time * 1.8) * sin(p.y * 4.2 - n2.y * 3.0 - time * 1.35);
	caustic = smoothstep(0.24, 0.92, caustic * 0.5 + 0.5) * smoothstep(0.95, 0.03, water_depth_v);
	color += vec3(0.06, 0.12, 0.10) * caustic * (1.0 - turbidity);

	vec3 half_vec = normalize(normalize(VIEW) + normalize(-sun_dir));
	float sun_glint = pow(max(dot(normalize(NORMAL), half_vec), 0.0), mix(220.0, 520.0, quality));
	color += sun_color * sun_glint * (1.4 + fresnel * 2.0);

	ALBEDO = color;
	ROUGHNESS = mix(0.055, 0.34, foam_mask);
	SPECULAR = 0.92;
	METALLIC = 0.0;
	ALPHA = clamp(mix(0.46, 0.94, depth_mix) + fresnel * 0.07 + foam_mask * 0.10, 0.0, 0.985);
	EMISSION = vec3(0.018, 0.060, 0.065) * (1.0 - depth_mix) + foam_color * foam_mask * 0.055 + sun_color * sun_glint * 0.16;
}
