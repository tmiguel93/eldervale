// E8.3: rastro/flecha de luz alinhado ao eixo -Z do no (cabeca em z=0, cauda em +z), girado em torno desse eixo para encarar a camera.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 color_a : source_color = vec3(1.0, 1.0, 0.9);
uniform vec3 color_b : source_color = vec3(1.0, 0.5, 0.1);
uniform float intensity = 1.6;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float fade_start = 0.5;
uniform float flash = 0.0;

void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[2].xyz);
	vec3 cam_z = INV_VIEW_MATRIX[2].xyz;
	vec3 right = cross(axis, cam_z);
	float rl = length(right);
	right = rl > 0.001 ? right / rl : normalize(MODEL_MATRIX[0].xyz);
	float sx = length(MODEL_MATRIX[0].xyz);
	float sz = length(MODEL_MATRIX[2].xyz);
	vec3 wp = MODEL_MATRIX[3].xyz + right * VERTEX.x * sx + axis * VERTEX.z * sz;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	float along = clamp(UV.y, 0.0, 1.0);
	float core = 1.0 - abs(UV.x * 2.0 - 1.0);
	float glow = pow(core, 1.6);
	float hot = pow(core, 5.0);
	float len = pow(1.0 - along, 1.5) * smoothstep(0.0, 0.03, along + 0.02);
	float fade = 1.0 - smoothstep(fade_start, 1.0, progress);
	float f = mix(1.0, 1.0 - progress, flash);
	vec3 col = mix(color_b, color_a, hot * 0.8 + len * 0.2);
	ALBEDO = col * intensity;
	ALPHA = clamp((glow * 0.6 + hot * 0.6) * len * fade * f, 0.0, 1.0);
}
