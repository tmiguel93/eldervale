// E8.3: telegrafo retangular (golpe, investida, linha de projetil). UV.y = 0 na ponta do inimigo, 1 na ponta distante.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color_a : source_color = vec3(1.0, 0.4, 0.2);
uniform vec3 color_b : source_color = vec3(0.8, 0.1, 0.05);
uniform float cover = 0.6;
uniform float intensity = 1.5;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;
uniform vec2 size_m = vec2(1.6, 2.0);

void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x;
	float ex = min(x, 1.0 - x) * size_m.x;
	float ey = min(y, 1.0 - y) * size_m.y;
	float edge = 1.0 - smoothstep(0.03, 0.12, min(ex, ey));
	float filled = (1.0 - smoothstep(progress - 0.02, progress, y)) * 0.38;
	float front = (1.0 - smoothstep(0.0, 0.06 * size_m.y, abs(y - progress) * size_m.y)) * 0.6;
	float chev = fract(y * size_m.y * 1.6 - TIME * 1.2 + abs(x - 0.5) * 1.1);
	float arrows = smoothstep(0.55, 0.62, chev) * (1.0 - smoothstep(0.7, 0.78, chev)) * 0.18 * (1.0 - progress * 0.5);
	float base = 0.12 + 0.1 * pulse;
	float a = base + edge * (0.55 + 0.25 * pulse) + filled + front + arrows;
	a = clamp(a, 0.0, 0.9);
	ALBEDO = mix(color_b, color_a, clamp(edge + front + filled, 0.0, 1.0)) * intensity * a;
	ALPHA = a * cover;
}
