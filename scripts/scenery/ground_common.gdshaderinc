// E8.2: funcoes comuns dos shaders de chao procedural (ruido por valor em coordenadas de MUNDO, sem texturas).
float g_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float g_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(g_hash(i), g_hash(i + vec2(1.0, 0.0)), f.x), mix(g_hash(i + vec2(0.0, 1.0)), g_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float g_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * g_noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

vec3 ground_albedo(vec2 p, vec3 a, vec3 b, vec3 c, float patch_amount, float scale, float tile, vec3 grout) {
	float n = g_fbm(p * scale);
	float d = g_fbm(p * scale * 7.0 + vec2(9.0, 3.0));
	vec3 col = mix(a, b, smoothstep(0.30, 0.70, n));
	float patches = smoothstep(0.52, 0.72, g_fbm(p * scale * 0.55 + vec2(31.0, 12.0)));
	col = mix(col, c, patches * patch_amount);
	col *= 0.82 + 0.34 * d;
	if (tile > 0.0) {
		vec2 g = p / tile;
		vec2 id = floor(g);
		vec2 f = fract(g);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * tile;
		float line = 1.0 - smoothstep(0.03, 0.09, edge);
		float tv = g_hash(id) * 0.3;
		col = col * (0.82 + tv) * (0.9 + 0.2 * g_noise(p * 3.0));
		col = mix(col, grout, line);
	}
	return col;
}
