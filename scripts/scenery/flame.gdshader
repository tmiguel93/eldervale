// E8.2: chama procedural (billboard aditivo) para tochas/fogueiras. Sem textura; `phase` desfasa as chamas entre si.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 flame_color : source_color = vec3(1.0, 0.45, 0.12);
uniform float intensity = 2.2;
uniform float phase = 0.0;

void vertex() {
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * scale.x, INV_VIEW_MATRIX[1] * scale.y, INV_VIEW_MATRIX[2] * scale.z, MODEL_MATRIX[3]);
}

void fragment() {
	float y = 1.0 - UV.y;
	float x = UV.x * 2.0 - 1.0;
	x += sin(y * 7.0 + TIME * 9.0 + phase) * 0.10 * y + sin(y * 13.0 - TIME * 14.0 + phase * 1.7) * 0.04 * y;
	float width = mix(0.95, 0.12, pow(y, 0.8));
	float body = 1.0 - smoothstep(width * 0.35, width, abs(x));
	float fade = smoothstep(0.0, 0.12, y) * (1.0 - smoothstep(0.55, 1.0, y));
	float a = body * fade;
	vec3 col = mix(vec3(1.0, 0.92, 0.6), flame_color, smoothstep(0.0, 0.8, y));
	ALBEDO = col * intensity;
	ALPHA = clamp(a, 0.0, 1.0);
}
