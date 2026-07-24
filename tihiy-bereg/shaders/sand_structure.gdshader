shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D sand_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0, 0.90, 0.72);

varying vec3 world_position_v;
varying vec3 world_normal_v;

void vertex() {
	world_position_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal_v = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec3 triplanar_color(sampler2D tex, vec3 p, vec3 n, float scale_value) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 x = texture(tex, p.zy * scale_value).rgb;
	vec3 y = texture(tex, p.xz * scale_value).rgb;
	vec3 z = texture(tex, p.xy * scale_value).rgb;
	return x * w.x + y * w.y + z * w.z;
}

float triplanar_scalar(sampler2D tex, vec3 p, vec3 n, float scale_value) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	float x = texture(tex, p.zy * scale_value).r;
	float y = texture(tex, p.xz * scale_value).r;
	float z = texture(tex, p.xy * scale_value).r;
	return x * w.x + y * w.y + z * w.z;
}

void fragment() {
	vec3 n = normalize(world_normal_v);
	vec3 base = triplanar_color(sand_albedo, world_position_v, n, 0.18);
	vec3 detail = triplanar_color(sand_albedo, world_position_v + vec3(3.7, 1.2, 5.1), n, 0.62);
	float rough = triplanar_scalar(sand_roughness, world_position_v, n, 0.34);
	vec3 color = mix(base, detail, 0.28) * tint;
	float form_band = sin(world_position_v.y * 17.0 + world_position_v.x * 0.35) * 0.5 + 0.5;
	color *= 0.965 + form_band * 0.035;
	ALBEDO = color;
	ROUGHNESS = 0.72 + rough * 0.20;
	SPECULAR = 0.22;
	AO = 0.92;
}
