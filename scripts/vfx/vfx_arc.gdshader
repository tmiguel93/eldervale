// E8.3: arco de corte com trilha. UV.x = ao longo do arco (cauda 0 -> cabeca 1), UV.y = dentro 0 -> fora 1.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color_head : source_color = vec3(1.0, 0.95, 0.8);
uniform vec3 color_tail : source_color = vec3(1.0, 0.5, 0.15);
uniform float cover = 0.7;
uniform float intensity = 1.6;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float sweep_end = 0.55;
uniform float tail_len = 0.6;
uniform float fade_start = 0.55;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

void fragment() {
	float head = clamp(progress / sweep_end, 0.0, 1.0);
	float d = head - UV.x;
	float tail = clamp(1.0 - d / tail_len, 0.0, 1.0);
	float vis = step(0.0, d) * tail * tail;
	float across = smoothstep(0.0, 0.45, UV.y) * (1.0 - smoothstep(0.9, 1.0, UV.y));
	float streak = 0.7 + 0.3 * h11(floor(UV.y * 11.0) + 3.7);
	float fade = 1.0 - smoothstep(fade_start, 1.0, progress);
	vec3 col = mix(color_tail, color_head, pow(tail, 2.0));
	col = mix(col, vec3(1.0), smoothstep(0.75, 1.0, tail) * smoothstep(0.5, 1.0, UV.y) * 0.6);
	float a = clamp(vis * across * streak * fade, 0.0, 1.0);
	ALBEDO = col * intensity * a;
	ALPHA = a * cover;
}
