// E8.3: nucleo emissivo (esfera) com fresnel e redemoinho; aditivo.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color_a : source_color = vec3(1.0, 1.0, 0.9);
uniform vec3 color_b : source_color = vec3(1.0, 0.5, 0.1);
uniform float intensity = 1.8;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;
uniform float fade_start = 0.7;

void fragment() {
	float f = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	float sw = 0.5 + 0.5 * sin(UV.x * 18.0 + UV.y * 9.0 + TIME * 7.0);
	float core = 1.0 - f;
	vec3 col = mix(color_b, color_a, core * (0.6 + 0.4 * sw) + 0.15);
	col += color_b * f * 0.6;
	float fade = 1.0 - smoothstep(fade_start, 1.0, progress);
	ALBEDO = col * intensity * (0.85 + 0.3 * pulse);
	ALPHA = clamp((0.55 + 0.45 * core) * fade, 0.0, 1.0);
}
