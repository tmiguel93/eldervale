// E8.3: anel de onda de choque no chao (anulo; UV.x angulo, UV.y raio interno 0 -> externo 1). A escala vem do script.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.5);
uniform float cover = 0.6;
uniform float intensity = 1.5;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float dash = 0.0;

float h11(float p) { p = fract(p * 0.1031); p *= p + 33.33; p *= p + p; return fract(p); }

void fragment() {
	float soft = smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.75, 1.0, UV.y));
	float rim = 0.35 + 0.65 * smoothstep(0.5, 0.95, UV.y);
	float n = mix(1.0, 0.35 + 0.65 * h11(floor(UV.x * 56.0)), dash);
	float life = smoothstep(0.0, 0.06, progress) * (1.0 - progress * progress);
	float a = clamp(soft * rim * n * life, 0.0, 1.0);
	ALBEDO = mix(color, vec3(1.0), rim * 0.25) * intensity * a;
	ALPHA = a * cover;
}
