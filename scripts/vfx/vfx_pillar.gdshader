// E8.3: coluna de luz (cilindro aberto; UV.y 0 base -> 1 topo). `progress` controla surgimento/desaparecimento.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color_a : source_color = vec3(1.0, 0.9, 0.5);
uniform vec3 color_b : source_color = vec3(1.0, 0.6, 0.2);
uniform float cover = 0.18;
uniform float intensity = 1.6;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float grow = 0.25;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

void fragment() {
	float y = UV.y;
	float g = clamp(progress / grow, 0.0, 1.0);
	float reach = smoothstep(g, g - 0.15, y);
	float vert = pow(1.0 - y, 1.4) * smoothstep(0.0, 0.05, y);
	float band = 0.6 + 0.4 * sin(UV.x * 6.2831853 * 6.0 + y * 7.0 - TIME * 3.0);
	float bar = 0.7 + 0.3 * h11(floor(UV.x * 24.0));
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.2);
	float fade = 1.0 - smoothstep(0.55, 1.0, progress);
	float a = clamp(vert * band * bar * (0.35 + 0.65 * fres) * reach * fade * 1.4, 0.0, 1.0);
	ALBEDO = mix(color_b, color_a, vert) * intensity * a;
	ALPHA = a * cover;
}
