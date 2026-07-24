shader_type sky;

uniform float time = 0.0;
uniform float day_phase = 0.0;
uniform float cloudiness = 0.42;
uniform vec3 sun_direction = vec3(0.42, 0.77, 0.35);

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

float fbm4(vec2 p) {
	float v = 0.0;
	float a = 0.52;
	mat2 m = mat2(vec2(1.64, 1.18), vec2(-1.18, 1.64));
	for (int i = 0; i < 4; i++) {
		v += noise2(p) * a;
		p = m * p;
		a *= 0.49;
	}
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float horizon = pow(clamp(1.0 - max(d.y, 0.0), 0.0, 1.0), 3.0);
	float sunset = smoothstep(0.25, 0.75, day_phase) * (1.0 - smoothstep(0.75, 1.0, day_phase));
	float night = smoothstep(0.72, 1.0, day_phase);
	vec3 day_top = vec3(0.12, 0.42, 0.68);
	vec3 day_horizon = vec3(0.72, 0.84, 0.86);
	vec3 sunset_top = vec3(0.11, 0.19, 0.35);
	vec3 sunset_horizon = vec3(1.0, 0.40, 0.17);
	vec3 night_top = vec3(0.006, 0.018, 0.055);
	vec3 night_horizon = vec3(0.055, 0.11, 0.18);
	vec3 top = mix(day_top, sunset_top, sunset);
	vec3 hz = mix(day_horizon, sunset_horizon, sunset);
	top = mix(top, night_top, night);
	hz = mix(hz, night_horizon, night);
	vec3 col = mix(top, hz, horizon);
	float sun_dot = max(dot(d, normalize(sun_direction)), 0.0);
	float sun_disk = smoothstep(0.99955, 0.99992, sun_dot);
	float sun_glow = pow(sun_dot, 96.0);
	vec3 sun_col = mix(vec3(1.0, 0.86, 0.62), vec3(1.0, 0.34, 0.12), sunset);
	col += sun_col * (sun_disk * 7.0 + sun_glow * 0.55) * (1.0 - night);
	vec2 cloud_uv = d.xz / max(0.12, d.y + 0.26);
	cloud_uv = cloud_uv * 0.52 + vec2(time * 0.0018, time * 0.0007);
	float clouds = fbm4(cloud_uv * 1.25);
	clouds = smoothstep(0.57 + (1.0 - cloudiness) * 0.12, 0.82, clouds) * smoothstep(-0.04, 0.22, d.y);
	vec3 cloud_col = mix(vec3(0.79, 0.84, 0.84), vec3(1.0, 0.50, 0.29), sunset * 0.72);
	cloud_col = mix(cloud_col, vec3(0.15, 0.20, 0.28), night);
	col = mix(col, cloud_col, clouds * (0.62 - night * 0.28));
	float stars = step(0.9984, hash21(floor(d.xz * 1100.0))) * pow(max(d.y, 0.0), 0.32) * night;
	col += vec3(0.75, 0.84, 1.0) * stars * 1.35;
	COLOR = col;
}
