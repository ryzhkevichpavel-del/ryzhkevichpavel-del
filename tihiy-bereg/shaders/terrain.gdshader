shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D state_tex : filter_linear, repeat_disable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wet_sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 texel_size = vec2(0.00625, 0.00833);
uniform vec2 world_size = vec2(96.0, 68.0);
uniform float time = 0.0;
uniform float quality = 1.0;
uniform vec3 sun_dir = vec3(-0.42, -0.77, -0.35);
uniform vec3 dry_tint : source_color = vec3(1.0, 0.93, 0.79);
uniform vec3 wet_tint : source_color = vec3(0.47, 0.40, 0.31);

varying vec2 sim_uv;
varying vec3 world_pos_v;
varying float wet_v;
varying float water_v;
varying float slope_v;
varying float curvature_v;

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

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	mat2 rot = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 3; i++) {
		v += a * noise2(p);
		p = rot * p;
		a *= 0.48;
	}
	return v;
}

void vertex() {
	sim_uv = UV;
	vec4 st = textureLod(state_tex, sim_uv, 0.0);
	VERTEX.y = st.r;
	wet_v = st.g;
	water_v = st.b;
	float hl = textureLod(state_tex, sim_uv - vec2(texel_size.x, 0.0), 0.0).r;
	float hr = textureLod(state_tex, sim_uv + vec2(texel_size.x, 0.0), 0.0).r;
	float hd = textureLod(state_tex, sim_uv - vec2(0.0, texel_size.y), 0.0).r;
	float hu = textureLod(state_tex, sim_uv + vec2(0.0, texel_size.y), 0.0).r;
	float sx = world_size.x * texel_size.x * 2.0;
	float sz = world_size.y * texel_size.y * 2.0;
	vec3 n = normalize(vec3((hl - hr) / max(sx, 0.001), 1.0, (hd - hu) / max(sz, 0.001)));
	NORMAL = n;
	slope_v = 1.0 - n.y;
	curvature_v = clamp((hl + hr + hd + hu - st.r * 4.0) * 1.5, -1.0, 1.0);
	world_pos_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos_v.xz;
	mat2 r1 = mat2(vec2(0.823, 0.568), vec2(-0.568, 0.823));
	mat2 r2 = mat2(vec2(0.342, 0.940), vec2(-0.940, 0.342));
	vec2 uv_a = p * 0.095;
	vec2 uv_b = r1 * p * 0.245 + vec2(0.31, 0.17);
	vec2 uv_c = r2 * p * 0.72 + vec2(0.63, 0.41);
	vec3 dry_a = texture(sand_albedo, uv_a).rgb;
	vec3 dry_b = texture(sand_albedo, uv_b).rgb;
	vec3 wet_a = texture(wet_sand_albedo, uv_a * 1.07).rgb;
	float macro = fbm3(p * 0.032);
	float wind_phase = dot(p, normalize(vec2(0.94, 0.34))) * 5.6 + fbm3(p * 0.14) * 2.4;
	float wind_ripple = sin(wind_phase) * 0.5 + 0.5;
	float capillary = smoothstep(0.045, 0.78, wet_v);
	float underwater = smoothstep(0.012, 0.34, water_v);
	float wet_mix = clamp(capillary * 0.90 + underwater * 0.25, 0.0, 1.0);
	vec3 dry_col = mix(dry_a, dry_b, 0.34) * dry_tint;
	dry_col *= 0.91 + macro * 0.16 + (wind_ripple - 0.5) * 0.045;
	vec3 wet_col = wet_a * wet_tint * 1.45;
	vec3 col = mix(dry_col, wet_col, wet_mix);
	col *= 1.0 - slope_v * 0.16;
	col *= 1.0 + curvature_v * 0.045;
	col = mix(col, col * vec3(0.63, 0.80, 0.82), underwater * 0.22);

	vec3 n1 = texture(sand_normal, uv_b * 1.35).rgb * 2.0 - 1.0;
	vec3 n2 = texture(sand_normal, uv_c).rgb * 2.0 - 1.0;
	vec2 rotated_n2 = r2 * n2.xy;
	vec2 detail_xy = n1.xy * 0.62 + rotated_n2 * 0.38;
	float ripple_normal = cos(wind_phase) * 0.045 * (1.0 - wet_mix * 0.62);
	detail_xy += normalize(vec2(0.94, 0.34)) * ripple_normal;
	NORMAL_MAP = normalize(vec3(detail_xy * mix(0.34, 0.68, quality), 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.32, 0.76, quality) * (1.0 - wet_mix * 0.28);

	float rough_a = texture(sand_roughness, uv_a * 1.5).r;
	ROUGHNESS = mix(0.78 + rough_a * 0.17, 0.24 + rough_a * 0.12, wet_mix);
	SPECULAR = mix(0.18, 0.62, wet_mix);
	METALLIC = 0.0;
	AO = clamp(0.96 - max(0.0, -curvature_v) * 0.18 - slope_v * 0.10, 0.68, 1.0);
	ALBEDO = col;
	float back_scatter = pow(max(0.0, dot(normalize(-sun_dir), normalize(VIEW))), 3.0) * (1.0 - wet_mix);
	EMISSION = vec3(0.10, 0.055, 0.018) * back_scatter * 0.08;
}
